import CoreGraphics
import Foundation
import ImageIO

public struct ThemeMetadata: Sendable, Equatable {
    public var name: String
    public var author: String?

    public init(name: String, author: String? = nil) {
        self.name = name
        self.author = author
    }
}

public struct ImportedCursor: Sendable {
    public let sourceURL: URL
    public let cursor: AnimatedCursor

    public init(sourceURL: URL, cursor: AnimatedCursor) {
        self.sourceURL = sourceURL
        self.cursor = cursor
    }
}

public struct ImportWarning: Sendable, CustomStringConvertible, Equatable {
    public enum Kind: Sendable, Equatable {
        case unmapped(file: String)
        case unreadable(file: String, reason: String)
        case collision(file: String, identifier: String, keptFile: String)
        case missingArrow
        case frameResample(identifier: String, from: Int, to: Int)
        case animationCollapsedToRestFrame(identifier: String)
        case perFrameHotspotsCollapsed(identifier: String)
        case representationsNormalized(identifier: String)
        case unknownSlot(identifier: String)
        case nonSquareGeometry(identifier: String)
    }

    public let kind: Kind

    public init(_ kind: Kind) {
        self.kind = kind
    }

    public var description: String {
        switch kind {
        case .unmapped(let file):
            return "unmapped: \(file)"
        case .unreadable(let file, let reason):
            return "unreadable: \(file) (\(reason))"
        case .collision(let file, let identifier, let keptFile):
            return "collision: \(file) lost \(identifier) to \(keptFile)"
        case .missingArrow:
            return "theme has no Arrow cursor (com.apple.coregraphics.Arrow)"
        case .frameResample(let identifier, let from, let to):
            return "\(identifier): \(from) frames resampled to \(to) (engine limit)"
        case .animationCollapsedToRestFrame(let identifier):
            return "\(identifier): the animation rests on a single frame nearly all of the time; converted as a static cursor showing that frame"
        case .perFrameHotspotsCollapsed(let identifier):
            return "\(identifier): per-frame hotspots vary; macOS applies frame 1's hotspot to every frame"
        case .representationsNormalized(let identifier):
            return "\(identifier): representations were adapted to the standard 32/64/160/320 px scales for editing; sizes that could not be mapped without upscaling were removed"
        case .unknownSlot(let identifier):
            return "\(identifier): kept as-is, but MaCursor has no editable slot for it"
        case .nonSquareGeometry(let identifier):
            return "\(identifier): non-square point geometry was padded into MaCursor's square cursor box"
        }
    }
}

public struct ImportReport: Sendable, Equatable {
    public struct Mapped: Sendable, Equatable {
        public let source: String
        public let identifier: String
        public let displayName: String
        public let tier: MappingTier
        public let isSecondary: Bool

        public init(source: String, identifier: String, displayName: String,
                    tier: MappingTier, isSecondary: Bool) {
            self.source = source
            self.identifier = identifier
            self.displayName = displayName
            self.tier = tier
            self.isSecondary = isSecondary
        }
    }

    public struct Ignored: Sendable, Equatable {
        public let source: String
        public let reason: String

        public init(source: String, reason: String) {
            self.source = source
            self.reason = reason
        }
    }

    public var mapped: [Mapped]
    public var ignored: [Ignored]
    public var warnings: [ImportWarning]

    public init(mapped: [Mapped] = [],
                ignored: [Ignored] = [],
                warnings: [ImportWarning] = []) {
        self.mapped = mapped
        self.ignored = ignored
        self.warnings = warnings
    }
}

public struct ImportResult: Sendable {
    public var metadata: ThemeMetadata
    public var cursors: [String: ImportedCursor]
    public var report: ImportReport

    public var warnings: [ImportWarning] { report.warnings }

    public init(metadata: ThemeMetadata,
                cursors: [String: ImportedCursor],
                report: ImportReport) {
        self.metadata = metadata
        self.cursors = cursors
        self.report = report
    }
}

public enum ThemeImporter {
    public static func load(_ url: URL) throws -> ImportResult {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw ThemeImportError.unreadableInput(
                String(localized: "no such file or directory: \(url.path)",
                       comment: "Convert Theme failure detail, embedded in “Cannot read input: …”"))
        }

        if isDirectory.boolValue {
            return try loadDirectory(url)
        }
        if let reason = unsupportedFileReason(url) {
            throw ThemeImportError.unsupportedInput(reason)
        }
        if let plist = themePlist(at: url) {
            return try loadThemePlist(url, root: plist)
        }
        return try loadSingleFile(url)
    }

    public static func withImportResult<T>(from url: URL,
                                           _ body: (ImportResult) throws -> T) throws -> T {
        try body(try load(url))
    }

    private struct Candidate {
        let identifier: String
        let tier: MappingTier
        let file: URL
        let cursor: AnimatedCursor
        let secondaries: [String]
    }

    private struct SlotClaim {
        var candidate: Candidate
        var isSecondary: Bool
    }

    private static func resolve(
        _ candidates: [Candidate], warnings: inout [ImportWarning]
    ) -> (cursors: [String: ImportedCursor], mapped: [ImportReport.Mapped]) {
        var slots: [String: SlotClaim] = [:]

        func claimPrimary(_ candidate: Candidate) {
            let id = candidate.identifier
            if let holder = slots[id], !holder.isSecondary {
                if candidate.tier < holder.candidate.tier {
                    warnings.append(.init(.collision(
                        file: holder.candidate.file.lastPathComponent,
                        identifier: id,
                        keptFile: candidate.file.lastPathComponent)))
                    slots[id] = SlotClaim(candidate: candidate, isSecondary: false)
                } else {
                    warnings.append(.init(.collision(
                        file: candidate.file.lastPathComponent,
                        identifier: id,
                        keptFile: holder.candidate.file.lastPathComponent)))
                }
            } else {
                slots[id] = SlotClaim(candidate: candidate, isSecondary: false)
            }
        }

        for candidate in candidates {
            claimPrimary(candidate)
        }
        for candidate in candidates {
            for secondary in candidate.secondaries where slots[secondary] == nil {
                slots[secondary] = SlotClaim(
                    candidate: Candidate(identifier: secondary, tier: candidate.tier,
                                         file: candidate.file, cursor: candidate.cursor,
                                         secondaries: []),
                    isSecondary: true)
            }
        }

        let cursors = slots.mapValues {
            ImportedCursor(sourceURL: $0.candidate.file, cursor: $0.candidate.cursor)
        }
        let mapped = slots
            .sorted {
                (Slots.indexByIdentifier[$0.key] ?? Int.max, $0.key)
                    < (Slots.indexByIdentifier[$1.key] ?? Int.max, $1.key)
            }
            .map { identifier, claim in
                ImportReport.Mapped(source: claim.candidate.file.lastPathComponent,
                                    identifier: identifier,
                                    displayName: Slots.displayName(for: identifier),
                                    tier: claim.candidate.tier,
                                    isSecondary: claim.isSecondary)
            }
        return (cursors, mapped)
    }

    private static func loadDirectory(_ url: URL) throws -> ImportResult {
        let fm = FileManager.default
        let cursorsDir = url.appendingPathComponent("cursors")
        var isDirectory: ObjCBool = false
        if fm.fileExists(atPath: cursorsDir.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            let inner = try sortedFiles(in: cursorsDir)
            if !inner.contains(where: { fileMagic($0, matches: XCursorReader.self) }),
               inner.contains(where: {
                   fileMagic($0, matches: CURReader.self) || fileMagic($0, matches: ANIReader.self)
               }) {
                return try loadWindowsPack(cursorsDir, themeRoot: url,
                                           infURL: preferredINF(in: url) ?? preferredINF(in: cursorsDir))
            }
            return try loadLinuxTheme(themeRoot: url, cursorDir: cursorsDir)
        }

        let entries = try sortedFiles(in: url)
        if entries.contains(where: { fileMagic($0, matches: XCursorReader.self) }) {
            return try loadLinuxTheme(themeRoot: url, cursorDir: url)
        }
        if let inf = preferredINF(in: url) {
            return try loadWindowsPack(url, themeRoot: url, infURL: inf)
        }
        if entries.contains(where: {
            fileMagic($0, matches: CURReader.self) || fileMagic($0, matches: ANIReader.self)
        }) {
            return try loadWindowsPack(url, themeRoot: url, infURL: nil)
        }

        let themes = entries.compactMap { file -> (URL, [String: Any])? in
            guard let plist = themePlist(at: file) else { return nil }
            return (file, plist)
        }
        if themes.count == 1 {
            return try loadThemePlist(themes[0].0, root: themes[0].1)
        }
        if themes.count > 1 {
            throw ThemeImportError.multipleThemes(count: themes.count)
        }
        throw ThemeImportError.nothingMappable
    }

    private static func themePlist(at url: URL) -> [String: Any]? {
        guard !isSymlink(url),
              let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let root = (try? PropertyListSerialization.propertyList(
                  from: data, format: nil)) as? [String: Any],
              let cursors = root["Cursors"] as? [String: Any],
              !cursors.isEmpty else { return nil }
        return root
    }

    private static func loadThemePlist(_ url: URL, root: [String: Any]) throws -> ImportResult {
        var warnings: [ImportWarning] = []
        var ignored: [ImportReport.Ignored] = []
        var candidates: [Candidate] = []

        let entries = (root["Cursors"] as? [String: Any]) ?? [:]
        for (identifier, value) in entries.sorted(by: { $0.key < $1.key }) {
            guard let entry = value as? [String: Any] else {
                ignored.append(.init(source: identifier, reason: "not a cursor dictionary"))
                continue
            }
            do {
                let cursor = try decodeThemeCursor(entry, identifier: identifier,
                                                   warnings: &warnings)
                if !Slots.isValid(identifier),
                   !Slots.intentionallyExcludedFromCursorMap.contains(identifier) {
                    warnings.append(.init(.unknownSlot(identifier: identifier)))
                }
                candidates.append(Candidate(identifier: identifier, tier: .exactName,
                                            file: url, cursor: cursor, secondaries: []))
            } catch {
                warnings.append(.init(.unreadable(
                    file: identifier,
                    reason: (error as? LocalizedError)?.errorDescription ?? "undecodable cursor")))
            }
        }

        let (cursors, mapped) = resolve(candidates, warnings: &warnings)
        guard !cursors.isEmpty else { throw ThemeImportError.nothingMappable }
        if cursors["com.apple.coregraphics.Arrow"] == nil {
            warnings.append(.init(.missingArrow))
        }

        let name = [root["CapeName"], root["ThemeName"], root["Identifier"]]
            .compactMap { $0 as? String }
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            ?? url.deletingPathExtension().lastPathComponent
        let author = [root["Author"], root["Creator"]]
            .compactMap { $0 as? String }
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        return ImportResult(metadata: ThemeMetadata(name: name, author: author),
                            cursors: cursors,
                            report: ImportReport(mapped: mapped, ignored: ignored,
                                                 warnings: warnings))
    }

    private static func decodeThemeCursor(_ entry: [String: Any], identifier: String,
                                          warnings: inout [ImportWarning]) throws -> AnimatedCursor {
        guard let representations = entry["Representations"] as? [Data],
              !representations.isEmpty else {
            throw CursorReadError.malformed("\(identifier) has no representations")
        }
        guard let declaredFrames = (entry["FrameCount"] as? NSNumber)?.doubleValue,
              declaredFrames.isFinite, declaredFrames == declaredFrames.rounded(),
              declaredFrames >= 1, declaredFrames <= Double(MACCursorDefinitions.maxImportFrameCount) else {
            throw CursorReadError.malformed("\(identifier) declares an unusable frame count")
        }
        let frameCount = Int(declaredFrames)
        let pointsWide = pointExtent(entry["PointsWide"])
        let pointsHigh = pointExtent(entry["PointsHigh"] ?? entry["PointsWide"])
        if pointsWide != pointsHigh {
            warnings.append(.init(.nonSquareGeometry(identifier: identifier)))
        }
        let hotSpotX = finiteValue(entry["HotSpotX"])
        let hotSpotY = finiteValue(entry["HotSpotY"])
        let frameDuration = finiteValue(entry["FrameDuration"])

        var framesTiles: [[CursorImage]] = []
        var claimedWidths: Set<Int> = []

        for (index, data) in representations.enumerated() {
            let label = "\(identifier) representation \(index + 1)"
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  CGImageSourceGetCount(source) > 0,
                  let sheet = CGImageSourceCreateImageAtIndex(source, 0, nil),
                  sheet.width > 0, sheet.height > 0 else {
                warnings.append(.init(.unreadable(file: label, reason: "undecodable image data")))
                continue
            }
            guard sheet.height % frameCount == 0 else {
                warnings.append(.init(.unreadable(
                    file: label,
                    reason: "height \(sheet.height) is not \(frameCount) whole frames")))
                continue
            }
            guard claimedWidths.insert(sheet.width).inserted else {
                warnings.append(.init(.unreadable(
                    file: label, reason: "duplicate \(sheet.width) px scale")))
                continue
            }

            if framesTiles.isEmpty {
                framesTiles = Array(repeating: [], count: frameCount)
            }
            let frameHeight = sheet.height / frameCount
            let hotspot = CGPoint(
                x: clampedHotspot(hotSpotX, points: pointsWide, pixels: sheet.width),
                y: clampedHotspot(hotSpotY, points: pointsHigh, pixels: frameHeight))
            for frame in 0 ..< frameCount {
                let tile = try ImageScaler.crop(
                    sheet, to: CGRect(x: 0, y: frame * frameHeight,
                                      width: sheet.width, height: frameHeight))
                framesTiles[frame].append(try CursorImage(image: tile, hotspot: hotspot))
            }
        }

        guard !framesTiles.isEmpty, framesTiles.allSatisfy({ !$0.isEmpty }) else {
            throw CursorReadError.malformed("\(identifier) has no usable representation")
        }

        let seconds = min(frameDuration, maxFrameDurationSeconds)
        let delayMS = seconds > 0
            ? max(1, Int((seconds * 1000).rounded()))
            : defaultFrameDelayMS
        return AnimatedCursor(frames: framesTiles.map {
            AnimatedCursor.Frame(cursor: Cursor($0), delayMS: delayMS)
        })
    }

    private static let defaultFrameDelayMS = 100
    private static let maxFrameDurationSeconds = 60.0

    private static func finiteValue(_ value: Any?) -> Double {
        guard let number = (value as? NSNumber)?.doubleValue, number.isFinite else { return 0 }
        return number
    }

    private static func pointExtent(_ value: Any?) -> Double {
        let extent = finiteValue(value)
        return extent > 0 ? extent : Double(CursorGeometry.basePointSize)
    }

    private static func clampedHotspot(_ value: Double, points: Double, pixels: Int) -> Double {
        let scaled = value * Double(pixels) / points
        guard scaled.isFinite else { return 0 }
        return min(max(scaled, 0), Double(pixels - 1))
    }

    private static func loadLinuxTheme(themeRoot: URL, cursorDir: URL) throws -> ImportResult {
        var warnings: [ImportWarning] = []
        var ignored: [ImportReport.Ignored] = []
        var candidates: [Candidate] = []
        var mappedRealPaths: Set<String> = []

        let entries = try sortedFiles(in: cursorDir)
        let regular = entries.filter { !isSymlink($0) }
        let symlinks = entries.filter { isSymlink($0) }

        func appendCandidate(named name: String, file: URL, data: Data) {
            if RoleMapper.isDeliberatelyUnmapped(name) {
                ignored.append(.init(source: name,
                                     reason: "no macOS equivalent (\(RoleMapper.normalize(name)))"))
                return
            }
            let decoded: AnimatedCursor?
            do {
                decoded = try CursorFormatRegistry.readCursorFile(data)
            } catch {
                warnings.append(.init(.unreadable(file: name, reason: "undecodable cursor data")))
                return
            }
            guard let cursor = decoded else { return }
            if let mapping = RoleMapper.mapX11Name(name) {
                candidates.append(Candidate(identifier: mapping.primary, tier: .exactName,
                                            file: file, cursor: cursor,
                                            secondaries: mapping.secondaries))
            } else if let mapping = RoleMapper.mapFilenameHeuristic(name) {
                candidates.append(Candidate(identifier: mapping.primary, tier: .heuristic,
                                            file: file, cursor: cursor,
                                            secondaries: mapping.secondaries))
            } else {
                warnings.append(.init(.unmapped(file: name)))
                return
            }
            mappedRealPaths.insert(file.resolvingSymlinksInPath().path)
        }

        for file in regular {
            guard let data = try? Data(contentsOf: file) else {
                warnings.append(.init(.unreadable(file: file.lastPathComponent, reason: "read failed")))
                continue
            }
            appendCandidate(named: file.lastPathComponent, file: file, data: data)
        }

        var aliasLinks: [URL] = []
        for link in symlinks {
            let resolved = link.resolvingSymlinksInPath()
            if mappedRealPaths.contains(resolved.path) {
                aliasLinks.append(link)
                continue
            }
            guard let data = try? Data(contentsOf: resolved) else {
                warnings.append(.init(.unreadable(file: link.lastPathComponent,
                                                  reason: "dangling symlink")))
                continue
            }
            appendCandidate(named: link.lastPathComponent, file: resolved, data: data)
        }

        let directNamed = aliasLinks.filter {
            CursorNameList.linuxAliases[$0.lastPathComponent.lowercased()] == nil
        }
        let aliasNamed = aliasLinks.filter {
            CursorNameList.linuxAliases[$0.lastPathComponent.lowercased()] != nil
        }
        for link in directNamed + aliasNamed {
            let name = link.lastPathComponent
            let resolved = link.resolvingSymlinksInPath()
            guard !RoleMapper.isDeliberatelyUnmapped(name),
                  let mapping = RoleMapper.mapX11Name(name),
                  !candidates.contains(where: { $0.identifier == mapping.primary }),
                  let data = try? Data(contentsOf: resolved) else { continue }
            appendCandidate(named: name, file: resolved, data: data)
        }

        let (cursors, mapped) = resolve(candidates, warnings: &warnings)
        guard !cursors.isEmpty else { throw ThemeImportError.nothingMappable }
        if cursors["com.apple.coregraphics.Arrow"] == nil {
            warnings.append(.init(.missingArrow))
        }
        let meta = folderMetadata(in: themeRoot)
        let name = meta.name ?? themeRoot.lastPathComponent
        return ImportResult(metadata: ThemeMetadata(name: name, author: meta.author),
                            cursors: cursors,
                            report: ImportReport(mapped: mapped, ignored: ignored,
                                                 warnings: warnings))
    }


    private static func folderMetadata(in themeRoot: URL) -> (name: String?, author: String?) {
        var name: String?

        if let infURL = preferredINF(in: themeRoot),
           let data = try? Data(contentsOf: infURL) {
            name = nonBlank(INFParser.parse(data).schemeName)
        }
        if name == nil { name = indexThemeName(at: themeRoot) }

        let readme = readmeMetadata(in: themeRoot)
        if name == nil { name = readme.name }
        return (name, readme.author)
    }

    private static func preferredINF(in dir: URL) -> URL? {
        let infs = ((try? sortedFiles(in: dir)) ?? [])
            .filter { $0.pathExtension.lowercased() == "inf" }
        return infs.first { $0.lastPathComponent.lowercased() == "install.inf" } ?? infs.first
    }

    private static func nonBlank(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private static func indexThemeName(at themeRoot: URL) -> String? {
        let indexURL = themeRoot.appendingPathComponent("index.theme")
        guard let text = try? String(contentsOf: indexURL, encoding: .utf8) else { return nil }
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let eq = trimmed.firstIndex(of: "=") else { continue }
            let key = trimmed[..<eq].trimmingCharacters(in: .whitespaces).lowercased()
            guard key == "name" else { continue }
            let value = trimmed[trimmed.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if !value.isEmpty { return value }
        }
        return nil
    }


    private static func readmeMetadata(in dir: URL) -> (name: String?, author: String?) {
        guard let readme = ((try? sortedFiles(in: dir)) ?? []).first(where: isReadmeFile),
              let text = readmeText(readme) else { return (nil, nil) }
        return parseReadme(text)
    }

    private static func isReadmeFile(_ url: URL) -> Bool {
        guard url.deletingPathExtension().lastPathComponent.lowercased() == "readme" else {
            return false
        }
        let ext = url.pathExtension.lowercased()
        return ext.isEmpty || ext == "txt" || ext == "md" || ext == "nfo"
    }

    private static func readmeText(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        var text: String
        if data.starts(with: [0xFF, 0xFE]) {
            text = String(data: data.dropFirst(2), encoding: .utf16LittleEndian) ?? ""
        } else if data.starts(with: [0xFE, 0xFF]) {
            text = String(data: data.dropFirst(2), encoding: .utf16BigEndian) ?? ""
        } else if let utf8 = String(data: data, encoding: .utf8) {
            text = utf8
        } else {
            text = String(data: data, encoding: .isoLatin1) ?? ""
        }
        if text.first == "\u{FEFF}" { text.removeFirst() }
        return text.isEmpty ? nil : text
    }

    private static func parseReadme(_ text: String) -> (name: String?, author: String?) {
        var name: String?
        var author: String?
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = String(rawLine).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if name == nil { name = readmeTitle(line) }
            if author == nil { author = readmeAuthor(line) }
            if name != nil, author != nil { break }
        }
        return (name, author)
    }

    private static let readmeAuthorLabels: Set<String> =
        ["by", "author", "creator", "artist", "made by", "created by"]

    private static func readmeTitle(_ line: String) -> String? {
        if let (label, value) = labelValue(line), label == "name" || label == "title" {
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty, trimmed.count <= 80 { return trimmed }
        }
        let leading = line.prefix { "=*#".contains($0) }.count
        let trailing = line.reversed().prefix { "=*#".contains($0) }.count
        guard leading >= 3, trailing >= 3 else { return nil }
        let inner = line.trimmingCharacters(in: CharacterSet(charactersIn: "=*# \t"))
        guard !inner.isEmpty, inner.count <= 80 else { return nil }
        return inner
    }

    private static func readmeAuthor(_ line: String) -> String? {
        guard let (label, value) = labelValue(line),
              readmeAuthorLabels.contains(label) else { return nil }
        let author = value.trimmingCharacters(in: CharacterSet(charactersIn: " \t.-–—"))
        let lower = author.lowercased()
        guard !author.isEmpty, author.count <= 50,
              !lower.contains("://"), !lower.hasPrefix("http") else { return nil }
        return author
    }

    private static func labelValue(_ line: String) -> (label: String, value: String)? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let label = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
        guard !label.isEmpty else { return nil }
        return (label, String(line[line.index(after: colon)...]))
    }

    private static func loadWindowsPack(_ dir: URL, themeRoot: URL, infURL: URL?) throws -> ImportResult {
        var warnings: [ImportWarning] = []
        var ignored: [ImportReport.Ignored] = []
        var candidates: [Candidate] = []
        var referencedPaths: Set<String> = []
        let meta = folderMetadata(in: themeRoot)
        let themeName = meta.name ?? themeRoot.lastPathComponent

        let entries = try sortedFiles(in: dir)

        if let infURL, let infData = try? Data(contentsOf: infURL) {
            let scheme = INFParser.parse(infData)
            for (role, fileName) in scheme.roleFiles.sorted(by: { $0.key < $1.key }) {
                guard let file = entries.first(where: {
                    $0.lastPathComponent.lowercased() == fileName.lowercased()
                }) else {
                    warnings.append(.init(.unreadable(file: fileName,
                                                      reason: "referenced by INF but missing")))
                    continue
                }
                referencedPaths.insert(file.path)
                if CursorNameList.ignoredINFRoles.contains(role) {
                    ignored.append(.init(source: fileName,
                                         reason: "role '\(role)' has no macOS slot"))
                    continue
                }
                guard let mapping = RoleMapper.mapINFRole(role) else {
                    warnings.append(.init(.unmapped(file: fileName)))
                    continue
                }
                guard let data = try? Data(contentsOf: file),
                      let cursor = (try? CursorFormatRegistry.readCursorFile(data)) ?? nil else {
                    warnings.append(.init(.unreadable(file: fileName,
                                                      reason: "undecodable cursor data")))
                    continue
                }
                candidates.append(Candidate(identifier: mapping.primary, tier: .infDeclaration,
                                            file: file, cursor: cursor,
                                            secondaries: mapping.secondaries))
            }
        }

        for file in entries where !referencedPaths.contains(file.path) {
            guard fileMagic(file, matches: CURReader.self)
                    || fileMagic(file, matches: ANIReader.self) else { continue }
            let name = file.lastPathComponent
            let match = RoleMapper.matchWindowsFileName(name)
            if match == .ignored {
                ignored.append(.init(source: name,
                                     reason: "no macOS equivalent (\(RoleMapper.normalize(name)))"))
                continue
            }
            guard let data = try? Data(contentsOf: file),
                  let cursor = (try? CursorFormatRegistry.readCursorFile(data)) ?? nil else {
                warnings.append(.init(.unreadable(file: name, reason: "undecodable cursor data")))
                continue
            }
            if case .slot(let mapping, let tier)? = match {
                candidates.append(Candidate(identifier: mapping.primary, tier: tier,
                                            file: file, cursor: cursor,
                                            secondaries: mapping.secondaries))
            } else {
                warnings.append(.init(.unmapped(file: name)))
            }
        }

        let (cursors, mapped) = resolve(candidates, warnings: &warnings)
        guard !cursors.isEmpty else { throw ThemeImportError.nothingMappable }
        if cursors["com.apple.coregraphics.Arrow"] == nil {
            warnings.append(.init(.missingArrow))
        }
        return ImportResult(metadata: ThemeMetadata(name: themeName, author: meta.author),
                            cursors: cursors,
                            report: ImportReport(mapped: mapped, ignored: ignored,
                                                 warnings: warnings))
    }

    private static func loadSingleFile(_ url: URL) throws -> ImportResult {
        guard let data = try? Data(contentsOf: url) else {
            throw ThemeImportError.unreadableInput(
                String(localized: "cannot read \(url.path)",
                       comment: "Convert Theme failure detail, embedded in “Cannot read input: …”"))
        }
        guard let cursor = (try? CursorFormatRegistry.readCursorFile(data)) ?? nil else {
            throw ThemeImportError.nothingMappable
        }
        let name = url.lastPathComponent
        let stem = url.deletingPathExtension().lastPathComponent
        var (mapping, tier) = (RoleMapping(primary: "com.apple.coregraphics.Arrow"), MappingTier.heuristic)
        if fileMagic(url, matches: CURReader.self) || fileMagic(url, matches: ANIReader.self) {
            if case .slot(let named, let namedTier)? = RoleMapper.matchWindowsFileName(name) {
                (mapping, tier) = (named, namedTier)
            }
        } else if !RoleMapper.isDeliberatelyUnmapped(name) {
            if let named = RoleMapper.mapX11Name(stem) {
                (mapping, tier) = (named, .exactName)
            } else if let guess = RoleMapper.mapFilenameHeuristic(stem) {
                mapping = guess
            }
        }

        var warnings: [ImportWarning] = []
        let candidates = [Candidate(identifier: mapping.primary, tier: tier,
                                    file: url, cursor: cursor,
                                    secondaries: mapping.secondaries)]
        let (cursors, mapped) = resolve(candidates, warnings: &warnings)
        if cursors["com.apple.coregraphics.Arrow"] == nil {
            warnings.append(.init(.missingArrow))
        }
        return ImportResult(metadata: ThemeMetadata(name: stem),
                            cursors: cursors,
                            report: ImportReport(mapped: mapped, warnings: warnings))
    }

    private static let archiveSuffixes = [
        ".zip", ".tar", ".tar.gz", ".tgz", ".tar.bz2", ".tbz", ".tar.xz", ".txz",
        ".gz", ".bz2", ".xz", ".rar", ".7z",
    ]

    private static let imageExtensions: Set<String> = [
        "png", "gif", "jpg", "jpeg", "tif", "tiff", "bmp", "webp", "heic", "apng",
    ]

    static func unsupportedFileReasonByName(_ url: URL) -> String? {
        let name = url.lastPathComponent.lowercased()
        if archiveSuffixes.contains(where: { name.hasSuffix($0) }) { return archiveReason(url) }
        if imageExtensions.contains(url.pathExtension.lowercased()) { return imageReason(url) }
        return nil
    }

    static func unsupportedFileReason(_ url: URL) -> String? {
        if let reason = unsupportedFileReasonByName(url) { return reason }

        let head = firstBytes(of: url)
        if isArchiveData(head) { return archiveReason(url) }
        if isImageData(head) { return imageReason(url) }
        return nil
    }

    private static func archiveReason(_ url: URL) -> String {
        String(localized: "\(url.lastPathComponent) is an archive. Expand it first, then choose the theme folder inside it.",
               comment: "Convert Theme rejection: the chosen file is a compressed archive")
    }

    private static func imageReason(_ url: URL) -> String {
        String(localized: "\(url.lastPathComponent) is an image, not a cursor theme. Use Edit Theme to drop images onto a cursor slot.",
               comment: "Convert Theme rejection: the chosen file is a plain image")
    }

    private static func firstBytes(of url: URL, count: Int = 8) -> [UInt8] {
        guard !isSymlink(url),
              let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: count) else { return [] }
        return [UInt8](head)
    }

    private static func isArchiveData(_ head: [UInt8]) -> Bool {
        guard head.count >= 4 else { return false }
        if head[0] == 0x50, head[1] == 0x4B { return true }
        if head[0] == 0x1F, head[1] == 0x8B { return true }
        if head[0] == 0x42, head[1] == 0x5A, head[2] == 0x68 { return true }
        if Array(head.prefix(6)) == [0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00] { return true }
        if Array(head.prefix(4)) == [0x52, 0x61, 0x72, 0x21] { return true }
        if Array(head.prefix(4)) == [0x37, 0x7A, 0xBC, 0xAF] { return true }
        return false
    }

    private static func isImageData(_ head: [UInt8]) -> Bool {
        guard head.count >= 4 else { return false }
        if Array(head.prefix(4)) == [0x89, 0x50, 0x4E, 0x47] { return true }
        if Array(head.prefix(4)) == Array("GIF8".utf8) { return true }
        if head[0] == 0xFF, head[1] == 0xD8, head[2] == 0xFF { return true }
        return false
    }

    private static func sortedFiles(in dir: URL) throws -> [URL] {
        let fm = FileManager.default
        guard let children = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]) else {
            throw ThemeImportError.unreadableInput(
                String(localized: "cannot list \(dir.path)",
                       comment: "Convert Theme failure detail, embedded in “Cannot read input: …”"))
        }
        return children
            .filter { url in
                var isDirectory: ObjCBool = false
                FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                return !isDirectory.boolValue || isSymlink(url)
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func isSymlink(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType)
            == .typeSymbolicLink
    }

    private static func fileMagic(_ url: URL, matches format: any CursorFormat.Type) -> Bool {
        guard !isSymlink(url),
              let handle = try? FileHandle(forReadingFrom: url),
              let head = try? handle.read(upToCount: 12) else { return false }
        try? handle.close()
        return format.matches(firstBytes: head)
    }
}
