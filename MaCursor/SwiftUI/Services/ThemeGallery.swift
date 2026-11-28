import AppKit
import CryptoKit
import ImageIO

struct ThemeGalleryEntry: Codable, Equatable, Identifiable, Sendable {
    let identifier: String
    let name: String
    let creator: String
    let file: String
    let picture: String
    let sha256: String
    let size: Int
    let pictureSha256: String

    var id: String { identifier }
}

enum ThemeGalleryError: Error, Equatable {
    case noIndexURL
    case refusedURL
    case tooLarge
    case tooManyEntries
    case badResponse
    case checksum
    case importFailed
}

enum ThemeGalleryGetState: Equatable {
    case get
    case adding
    case inLibrary
    case failed
}

struct ThemeGalleryCursor: Identifiable {
    let id: String
    let name: String
    let frames: [CGImage]
    let frameDuration: Double

    var moves: Bool { frames.count > 1 && frameDuration.isFinite && frameDuration > 0 }

    func frame(at index: Int) -> CGImage? {
        guard moves else { return frames.first }
        return frames[index % frames.count]
    }
}

enum ThemeGalleryPreview {
    case loading
    case loaded([ThemeGalleryCursor])
    case failed

    var cursors: [ThemeGalleryCursor]? {
        if case .loaded(let cursors) = self { return cursors }
        return nil
    }

    var failed: Bool {
        if case .failed = self { return true }
        return false
    }
}

struct ThemeGalleryService: Sendable {
    static let indexURLKey = "MACGalleryIndexURL"
    static let indexLimit = 2 << 20
    static let pictureLimit = 4 << 20
    static let themeLimit = 64 << 20
    static let maxEntries = 1000
    static let pictureMaxPixels = 640
    static let keptThemeFiles = 5

    let indexURL: URL?
    let cacheFolder: URL
    private let session: URLSession

    init(indexURL: URL?, configuration: URLSessionConfiguration = .ephemeral, cacheFolder: URL) {
        self.indexURL = indexURL
        self.cacheFolder = cacheFolder
        let configuration = configuration.copy() as? URLSessionConfiguration ?? .ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
    }

    static func indexURL(in bundle: Bundle) -> URL? {
        (bundle.object(forInfoDictionaryKey: indexURLKey) as? String).flatMap { URL(string: $0) }
    }

    static var appCacheFolder: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "MaCursor", isDirectory: true)
            .appendingPathComponent("ThemeGallery", isDirectory: true)
    }

    static func isDigest(_ text: String) -> Bool {
        text.utf8.count == 64 && text.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private struct Index: Decodable {
        let themes: [ThemeGalleryEntry]
    }

    static func decodeIndex(_ data: Data) throws -> [ThemeGalleryEntry] {
        let themes = try JSONDecoder().decode(Index.self, from: data).themes
        guard themes.count <= maxEntries else { throw ThemeGalleryError.tooManyEntries }
        return themes.filter { isDigest($0.sha256) && isDigest($0.pictureSha256) && (1...themeLimit).contains($0.size) }
    }

    static func image(fromPNG data: Data, maxPixels: Int = pictureMaxPixels) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetType(source) as String? == "public.png" else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    func assetURL(for path: String) throws -> URL {
        guard let indexURL, indexURL.scheme?.lowercased() == "https", let host = indexURL.host?.lowercased(),
              let url = URL(string: path, relativeTo: indexURL)?.absoluteURL,
              url.scheme?.lowercased() == "https", url.host?.lowercased() == host else {
            throw ThemeGalleryError.refusedURL
        }
        return url
    }

    func request(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = false
        request.setValue("MaCursor", forHTTPHeaderField: "User-Agent")
        request.setValue("en", forHTTPHeaderField: "Accept-Language")
        return request
    }

    func fetch(_ url: URL, limit: Int) async throws -> Data {
        guard url.scheme?.lowercased() == "https" else { throw ThemeGalleryError.refusedURL }
        let (bytes, response) = try await session.bytes(for: request(for: url), delegate: ThemeGalleryRedirects())
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw ThemeGalleryError.badResponse }
        guard response.expectedContentLength <= Int64(limit) else { throw ThemeGalleryError.tooLarge }
        var data = Data()
        data.reserveCapacity(Int(max(0, response.expectedContentLength)))
        for try await byte in bytes {
            guard data.count < limit else { throw ThemeGalleryError.tooLarge }
            data.append(byte)
        }
        return data
    }

    private var cachedIndexFile: URL {
        cacheFolder.appendingPathComponent("index.json")
    }

    private var cachedIndexURLFile: URL {
        cacheFolder.appendingPathComponent("index-url")
    }

    func fetchIndex() async throws -> [ThemeGalleryEntry] {
        guard let indexURL else { throw ThemeGalleryError.noIndexURL }
        let data = try await fetch(indexURL, limit: Self.indexLimit)
        let entries = try Self.decodeIndex(data)
        guard !entries.isEmpty else { throw ThemeGalleryError.badResponse }
        try? FileManager.default.removeItem(at: cachedIndexURLFile)
        if (try? save(data, to: cachedIndexFile, replacing: true)) != nil {
            try? save(Data(indexURL.absoluteString.utf8), to: cachedIndexURLFile, replacing: true)
        }
        return entries
    }

    func removeLeftovers() {
        guard let walker = FileManager.default.enumerator(at: cacheFolder, includingPropertiesForKeys: nil) else { return }
        for case let file as URL in walker where file.pathExtension == "part" {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func save(_ data: Data, to file: URL, replacing: Bool) throws {
        let folder = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let part = folder.appendingPathComponent("\(file.lastPathComponent).\(UUID().uuidString).part")
        try data.write(to: part)
        if replacing { try? FileManager.default.removeItem(at: file) }
        do {
            try FileManager.default.moveItem(at: part, to: file)
        } catch {
            try? FileManager.default.removeItem(at: part)
            guard !replacing, FileManager.default.fileExists(atPath: file.path) else { throw error }
        }
    }

    func cachedIndex() -> [ThemeGalleryEntry]? {
        guard let indexURL, (try? Data(contentsOf: cachedIndexURLFile)) == Data(indexURL.absoluteString.utf8),
              let data = try? Data(contentsOf: cachedIndexFile),
              let entries = try? Self.decodeIndex(data), !entries.isEmpty else { return nil }
        return entries
    }

    func pictureData(for entry: ThemeGalleryEntry) async throws -> Data {
        let file = cacheFolder.appendingPathComponent("pictures", isDirectory: true).appendingPathComponent(entry.pictureSha256)
        if let data = try? Data(contentsOf: file) {
            if Self.digest(data) == entry.pictureSha256 { return data }
            try? FileManager.default.removeItem(at: file)
        }
        let data = try await fetch(try assetURL(for: entry.picture), limit: Self.pictureLimit)
        guard Self.digest(data) == entry.pictureSha256 else { throw ThemeGalleryError.checksum }
        try? save(data, to: file, replacing: false)
        return data
    }

    func downloadTheme(_ entry: ThemeGalleryEntry) async throws -> URL {
        let folder = cacheFolder.appendingPathComponent("themes", isDirectory: true)
        let file = folder.appendingPathComponent(entry.sha256 + ".cursor")
        if let data = try? Data(contentsOf: file) {
            if data.count == entry.size, Self.digest(data) == entry.sha256 {
                touch(file)
                return file
            }
            try? FileManager.default.removeItem(at: file)
        }
        let data = try await fetch(try assetURL(for: entry.file), limit: entry.size)
        guard data.count == entry.size, Self.digest(data) == entry.sha256 else { throw ThemeGalleryError.checksum }
        try save(data, to: file, replacing: false)
        touch(file)
        keepRecentThemeFiles(in: folder)
        return file
    }

    private func touch(_ file: URL) {
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
    }

    private func keepRecentThemeFiles(in folder: URL) {
        let key = URLResourceKey.contentModificationDateKey
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [key]) else { return }
        let dated = files.filter { $0.pathExtension == "cursor" }
            .map { ($0, (try? $0.resourceValues(forKeys: [key]).contentModificationDate) ?? .distantPast) }
            .sorted { $0.1 > $1.1 }
        for (file, _) in dated.dropFirst(Self.keptThemeFiles) {
            try? FileManager.default.removeItem(at: file)
        }
    }
}

final class ThemeGalleryRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(request.url?.scheme?.lowercased() == "https" ? request : nil)
    }
}

@MainActor
final class ThemeGalleryModel: ObservableObject {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed
    }

    @Published private(set) var phase = Phase.loading
    @Published private(set) var entries: [ThemeGalleryEntry] = []
    @Published private(set) var pictures: [String: CGImage] = [:]
    @Published private(set) var adding: Set<String> = []
    @Published private(set) var failed: Set<String> = []
    @Published var searchText = ""
    @Published private(set) var selection: String?
    @Published private(set) var preview = ThemeGalleryPreview.loading
    @Published private(set) var previewAttempt = 0
    let service: ThemeGalleryService
    private var downloads: [String: Task<URL, Error>] = [:]

    init(service: ThemeGalleryService) {
        self.service = service
    }

    convenience init() {
        self.init(service: ThemeGalleryService(indexURL: ThemeGalleryService.indexURL(in: .main),
                                               cacheFolder: ThemeGalleryService.appCacheFolder))
    }

    var visibleEntries: [ThemeGalleryEntry] {
        Self.entries(entries, matching: searchText)
    }

    static func entries(_ entries: [ThemeGalleryEntry], matching query: String) -> [ThemeGalleryEntry] {
        let query = MainSearch.folded(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !query.isEmpty else { return entries }
        return entries.filter { MainSearch.folded($0.name).contains(query) || MainSearch.folded($0.creator).contains(query) }
    }

    static func libraryTheme(for entry: ThemeGalleryEntry, in themes: [CursorLibrary]) -> CursorLibrary? {
        LibraryController.existingTheme(sameNameAs: CursorLibrary.sanitizeName(entry.name), in: themes, excluding: [])
            ?? LibraryController.existingTheme(sameNameAs: entry.identifier, in: themes, excluding: [])
    }

    private static func libraryTheme(for entry: ThemeGalleryEntry, in library: LibraryViewModel) -> CursorLibrary? {
        libraryTheme(for: entry, in: library.cursorThemes.map(\.backingLibrary))
    }

    func state(of entry: ThemeGalleryEntry, in library: LibraryViewModel) -> ThemeGalleryGetState {
        if adding.contains(entry.id) { return .adding }
        if Self.libraryTheme(for: entry, in: library) != nil { return .inLibrary }
        return failed.contains(entry.id) ? .failed : .get
    }

    func load() async {
        service.removeLeftovers()
        phase = .loading
        do {
            entries = try await service.fetchIndex()
            phase = .loaded
        } catch {
            if let cached = service.cachedIndex() {
                entries = cached
                phase = .loaded
            } else {
                phase = .failed
            }
        }
        guard phase == .loaded else { return }
        await withTaskGroup(of: Void.self) { group in
            for entry in entries {
                group.addTask { await self.loadPicture(for: entry) }
            }
        }
    }

    func select(_ id: String) {
        guard id != selection else { return }
        if let old = selection, !adding.contains(old) {
            downloads.removeValue(forKey: old)?.cancel()
        }
        selection = id
        previewAttempt += 1
        preview = .loading
    }

    func retryPreview() {
        previewAttempt += 1
    }

    func loadPreview() async {
        guard let id = selection, let entry = entries.first(where: { $0.id == id }) else { return }
        let attempt = previewAttempt
        preview = .loading
        do {
            let file = try await download(entry)
            guard attempt == previewAttempt else { return }
            guard let cursors = Self.cursors(in: file) else { throw ThemeGalleryError.importFailed }
            preview = .loaded(cursors)
        } catch {
            if attempt == previewAttempt { preview = .failed }
        }
    }

    private func download(_ entry: ThemeGalleryEntry) async throws -> URL {
        if let running = downloads[entry.id] { return try await running.value }
        let service = service
        let task = Task { try await service.downloadTheme(entry) }
        downloads[entry.id] = task
        defer { if downloads[entry.id] == task { downloads[entry.id] = nil } }
        return try await task.value
    }

    static func cursors(in file: URL) -> [ThemeGalleryCursor]? {
        guard let library = CursorLibrary(contentsOfURL: file) else { return nil }
        let hideTahoe = MACPreferences.hideTahoeCursors
        return CursorThemeModel(from: library).cursors
            .filter { !hideTahoe || !MACCursorDefinitions.hiddenCursorAliases.contains($0.identifier) }
            .map { ThemeGalleryCursor(id: $0.id, name: $0.name, frames: frames(of: $0), frameDuration: $0.frameDuration) }
    }

    static func frames(of cursor: CursorModel) -> [CGImage] {
        let reps = [1000, 500, 200, 100].compactMap { MACCursorScale(rawValue: $0).flatMap(cursor.backingCursor.representation(for:)) }
        guard let image = reps.max(by: { $0.pixelsWide * $0.pixelsHigh < $1.pixelsWide * $1.pixelsHigh })?.cgImage else { return [] }
        let count = max(1, cursor.frameCount), height = image.height / count
        guard height > 0, let box = opaqueBounds(image, frameHeight: height) else { return cursor.trimmedPicture.map { [$0] } ?? [] }
        return (0..<count).compactMap { image.cropping(to: box.offsetBy(dx: 0, dy: CGFloat($0 * height))) }
    }

    nonisolated static func trimmed(_ image: CGImage) -> CGImage? {
        opaqueBounds(image, frameHeight: image.height).flatMap(image.cropping(to:))
    }

    nonisolated static func opaqueBounds(_ image: CGImage, frameHeight: Int) -> CGRect? {
        let width = image.width, height = image.height
        guard width > 0, height > 0, frameHeight > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let bytes = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var minX = width, minY = frameHeight, maxX = -1, maxY = -1
        for row in 0..<(height / frameHeight * frameHeight) {
            let y = row % frameHeight
            for column in 0..<width where bytes[(row * width + column) * 4 + 3] != 0 {
                minX = min(minX, column)
                maxX = max(maxX, column)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    func loadPicture(for entry: ThemeGalleryEntry) async {
        guard pictures[entry.id] == nil,
              let data = try? await service.pictureData(for: entry),
              let image = ThemeGalleryService.image(fromPNG: data) else { return }
        pictures[entry.id] = image
    }

    func get(_ entry: ThemeGalleryEntry, into library: LibraryViewModel) async {
        guard [.get, .failed].contains(state(of: entry, in: library)) else { return }
        adding.insert(entry.id)
        failed.remove(entry.id)
        defer { adding.remove(entry.id) }
        do {
            let file = try await download(entry)
            guard Self.libraryTheme(for: entry, in: library) == nil else { return }
            guard library.importTheme(at: file) != nil else { throw ThemeGalleryError.importFailed }
        } catch {
            failed.insert(entry.id)
        }
    }
}
