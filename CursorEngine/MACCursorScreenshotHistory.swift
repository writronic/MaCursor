import Foundation

enum CursorScreenshotHistoryKeep: String, CaseIterable, Codable, Sendable {
    case disabled, day, threeDays, week, month

    var days: Int? {
        switch self {
        case .disabled: return nil
        case .day: return 1
        case .threeDays: return 3
        case .week: return 7
        case .month: return 30
        }
    }
}

struct CursorScreenshotHistoryEntry: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var date: Date
    var scale: CGFloat
    var output: CursorScreenshotOutput
    var name: CursorScreenshotFileName
    var file: URL?
}

actor CursorScreenshotHistoryStore {
    private static let pictureName = "picture.png"
    private static let thumbnailName = "thumbnail.png"
    private static let entryName = "entry.json"

    nonisolated let root: URL

    init(root: URL) {
        self.root = root
    }

    nonisolated func pictureURL(_ entry: CursorScreenshotHistoryEntry) -> URL {
        folder(entry.id).appendingPathComponent(Self.pictureName)
    }

    nonisolated func thumbnailURL(_ entry: CursorScreenshotHistoryEntry) -> URL {
        folder(entry.id).appendingPathComponent(Self.thumbnailName)
    }

    private nonisolated func folder(_ id: UUID) -> URL {
        root.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    func add(_ entry: CursorScreenshotHistoryEntry, picture: Data, thumbnail: Data?) {
        let files = FileManager.default
        let folder = folder(entry.id)
        do {
            try files.createDirectory(at: root, withIntermediateDirectories: true)
            try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var marked = root
            try marked.setResourceValues(values)
            try files.createDirectory(at: folder, withIntermediateDirectories: false)
            try picture.write(to: folder.appendingPathComponent(Self.pictureName))
            try thumbnail?.write(to: folder.appendingPathComponent(Self.thumbnailName))
            try JSONEncoder().encode(entry).write(to: folder.appendingPathComponent(Self.entryName), options: .atomic)
        } catch {
            try? files.removeItem(at: folder)
        }
    }

    func entries() -> [CursorScreenshotHistoryEntry] {
        stored().compactMap(\.entry).sorted { $0.date > $1.date }
    }

    func remove(_ id: UUID) {
        try? FileManager.default.removeItem(at: folder(id))
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: root)
    }

    func prune(keeping keep: CursorScreenshotHistoryKeep, now: Date) {
        guard let days = keep.days else { return removeAll() }
        let oldest = now.addingTimeInterval(-TimeInterval(days) * 86_400)
        for (folder, entry) in stored() where entry.map({ $0.date < oldest }) ?? true {
            try? FileManager.default.removeItem(at: folder)
        }
    }

    private func stored() -> [(folder: URL, entry: CursorScreenshotHistoryEntry?)] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return folders.map { folder in
            let data = try? Data(contentsOf: folder.appendingPathComponent(Self.entryName))
            return (folder, data.flatMap { try? JSONDecoder().decode(CursorScreenshotHistoryEntry.self, from: $0) })
        }
    }
}
