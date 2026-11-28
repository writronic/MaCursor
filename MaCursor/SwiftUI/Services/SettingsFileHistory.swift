import AppKit

enum SettingsFileHistory {
    struct Capture {
        var entry: CursorScreenshotHistoryEntry
        var picture: Data
        var thumbnail: Data?
    }

    struct Board {
        var item: CursorBoardItem
        var files: [String: Data]
    }

    private static let entryName = "entry.json"
    private static let scales: Set<CGFloat> = [1, 2]
    private static let boardTypes: Set<String> = ["public.png", "public.jpeg", "public.heic", "org.webmproject.webp", "public.tiff"]

    static func root(_ group: SettingsFileHistoryGroup, place: SettingsFilePlace) -> URL? {
        group == .captureHistory ? place.captureHistory : place.cursorBoardHistory
    }

    static func size(_ group: SettingsFileHistoryGroup, place: SettingsFilePlace) -> Int? {
        let root = root(group, place: place)
        let folders = group == .captureHistory ? stored(CursorScreenshotHistoryEntry.self, in: root).map(\.folder) : stored(CursorBoardItem.self, in: root).map(\.folder)
        guard !folders.isEmpty else { return nil }
        return folders.reduce(0) { total, folder in
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])) ?? []
            return total + files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        }
    }

    static func export(_ groups: Set<SettingsFileHistoryGroup>, place: SettingsFilePlace) -> [String: [[String: Any]]] {
        var history: [String: [[String: Any]]] = [:]
        if groups.contains(.captureHistory), let root = place.captureHistory {
            let store = CursorScreenshotHistoryStore(root: root)
            history[SettingsFileHistoryGroup.captureHistory.rawValue] = stored(CursorScreenshotHistoryEntry.self, in: root).compactMap { _, entry -> [String: Any]? in
                var entry = entry
                entry.file = nil
                guard let picture = try? Data(contentsOf: store.pictureURL(entry)), let data = try? JSONEncoder().encode(entry) else { return nil }
                var item: [String: Any] = ["entry": data, "picture": picture]
                item["thumbnail"] = try? Data(contentsOf: store.thumbnailURL(entry))
                return item
            }
        }
        if groups.contains(.cursorBoardHistory), let root = place.cursorBoardHistory {
            let store = CursorBoardStore(root: root)
            history[SettingsFileHistoryGroup.cursorBoardHistory.rawValue] = stored(CursorBoardItem.self, in: root).compactMap { _, item -> [String: Any]? in
                guard let data = try? JSONEncoder().encode(item) else { return nil }
                var stored: [String: Any] = ["entry": data]
                if item.picture != nil {
                    guard let picture = store.file(item.id, CursorBoardStore.picture(item)), let thumbnail = store.file(item.id, CursorBoardStore.thumbnail) else { return nil }
                    stored["picture"] = picture
                    stored["thumbnail"] = thumbnail
                } else if item.rich {
                    stored["rich"] = store.file(item.id, CursorBoardStore.rich)
                }
                return stored
            }
        }
        return history
    }

    static func parse(_ raw: Any?, into contents: inout SettingsFileContents) throws {
        guard let raw else { return }
        guard let lists = raw as? [String: Any] else { throw SettingsFile.Refusal.unreadable }
        for group in SettingsFileHistoryGroup.allCases {
            guard let raw = lists[group.rawValue] else { continue }
            guard let list = raw as? [Any] else { throw SettingsFile.Refusal.unreadable }
            var ids: Set<UUID> = []
            for stored in list {
                let stored = stored as? [String: Any] ?? [:]
                switch group {
                case .captureHistory:
                    if let shot = capture(stored), ids.insert(shot.entry.id).inserted {
                        contents.captureHistory.append(shot)
                        continue
                    }
                case .cursorBoardHistory:
                    if let copy = board(stored), ids.insert(copy.item.id).inserted {
                        contents.boardHistory.append(copy)
                        continue
                    }
                }
                contents.failedHistory.insert(group)
            }
        }
    }

    @MainActor @discardableResult
    static func land(_ contents: SettingsFileContents, groups: Set<SettingsFileHistoryGroup>, place: SettingsFilePlace, now: Date = Date()) async -> [SettingsFileHistoryGroup] {
        func config<Value: Decodable>(_ key: String, _ fallback: Value) -> Value {
            (MACPreferences.value(forKey: key, operations: place.preferences) as? Data).flatMap { try? JSONDecoder().decode(Value.self, from: $0) } ?? fallback
        }
        var contents = contents
        contents.captureHistory.indices.forEach { contents.captureHistory[$0].entry.date = min(contents.captureHistory[$0].entry.date, now) }
        contents.boardHistory.indices.forEach { contents.boardHistory[$0].item.date = min(contents.boardHistory[$0].item.date, now) }
        let days = config(MACPreferences.cursorScreenshotKey, CursorScreenshotConfig()).keepHistory.days
        let board = config(MACPreferences.cursorBoardKey, CursorBoardConfig())
        let skipped = SettingsFileHistoryGroup.allCases.filter { groups.contains($0) && ($0 == .captureHistory ? days == nil : !board.keepsHistory) }
        if groups.contains(.captureHistory), let root = place.captureHistory, let days {
            let oldest = now.addingTimeInterval(-TimeInterval(days) * 86_400)
            let store = CursorScreenshotHistoryStore(root: root)
            for shot in contents.captureHistory where shot.entry.date >= oldest {
                guard !FileManager.default.fileExists(atPath: root.appendingPathComponent(shot.entry.id.uuidString).path) else { continue }
                await store.add(shot.entry, picture: shot.picture, thumbnail: shot.thumbnail)
            }
        }
        guard groups.contains(.cursorBoardHistory), board.keepsHistory, let root = place.cursorBoardHistory else { return skipped }
        let here = stored(CursorBoardItem.self, in: root).map(\.entry)
        let known = Set(here.map(\.id))
        let incoming = contents.boardHistory.sorted { $0.item.pinned != $1.item.pinned ? $0.item.pinned : $0.item.date > $1.item.date }.reduce(into: [Board]()) { taken, copy in
            guard !known.contains(copy.item.id), !here.contains(where: { $0.same(as: copy.item) }), !taken.contains(where: { $0.item.same(as: copy.item) }),
                  !FileManager.default.fileExists(atPath: root.appendingPathComponent(copy.item.id.uuidString).path) else { return }
            taken.append(copy)
        }
        let oldest = board.keep.days.map { now.addingTimeInterval(-TimeInterval($0) * 86_400) }
        let current = here.filter { item in item.pinned || oldest.map { item.date >= $0 } != false }
        var history = CursorBoardHistory(items: current.sorted { $0.date > $1.date } + incoming.map(\.item))
        _ = history.prune(keep: board.keep, limit: board.limit, now: now)
        let kept = Set(history.items.map(\.id))
        let landing = incoming.filter { kept.contains($0.item.id) }
        guard !landing.isEmpty else { return skipped }
        let store = CursorBoardStore(root: root)
        for copy in landing { store.add(copy.item, files: copy.files) }
        place.reloadBoard()
        return skipped
    }

    private static func stored<Entry: Decodable>(_ type: Entry.Type, in root: URL?) -> [(folder: URL, entry: Entry)] {
        guard let root else { return [] }
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return folders.compactMap { folder in
            (try? Data(contentsOf: folder.appendingPathComponent(entryName)))
                .flatMap { try? JSONDecoder().decode(Entry.self, from: $0) }
                .map { (folder, $0) }
        }
    }

    private static func capture(_ stored: [String: Any]) -> Capture? {
        guard let data = stored["entry"] as? Data, var entry = try? JSONDecoder().decode(CursorScreenshotHistoryEntry.self, from: data),
              scales.contains(entry.scale), !["", ".", ".."].contains(entry.name.stem), !entry.name.stem.contains("/"), !entry.name.stem.contains(":"),
              let picture = stored["picture"] as? Data, SettingsFile.opens(picture) else { return nil }
        let thumbnail = stored["thumbnail"]
        guard thumbnail == nil || (thumbnail as? Data).map(SettingsFile.opens) == true else { return nil }
        entry.file = nil
        return Capture(entry: entry, picture: picture, thumbnail: thumbnail as? Data)
    }

    private static func board(_ stored: [String: Any]) -> Board? {
        guard let data = stored["entry"] as? Data, var item = try? JSONDecoder().decode(CursorBoardItem.self, from: data) else { return nil }
        if let text = item.text {
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let rich = item.rich ? (stored["rich"] as? Data).flatMap { $0.count <= CursorBoard.largestPicture ? $0 : nil } : nil
            (item.rich, item.picture, item.bytes, item.type) = (rich != nil, nil, nil, nil)
            return Board(item: item, files: [CursorBoardStore.rich: rich].compactMapValues { $0 })
        }
        guard let picture = stored["picture"] as? Data, picture.count <= CursorBoard.largestPicture,
              let source = CGImageSourceCreateWithData(picture as CFData, nil), CGImageSourceGetCount(source) > 0,
              let type = CGImageSourceGetType(source) as String?, boardTypes.contains(type),
              let thumbnail = stored["thumbnail"] as? Data, SettingsFile.opens(thumbnail) else { return nil }
        (item.picture, item.bytes, item.type, item.rich, item.name) = (CursorBoard.digest(picture), picture.count, type, false, nil)
        return Board(item: item, files: [CursorBoardStore.picture(item): picture, CursorBoardStore.thumbnail: thumbnail])
    }
}
