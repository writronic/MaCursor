import AppKit
import UniformTypeIdentifiers

struct SettingsFilePlace {
    var preferences: MACPreferences.Operations
    var rightClickMenu: URL?
    var wallpapers: URL?
    var captureHistory: URL? = nil
    var cursorBoardHistory: URL? = nil
    var reloadBoard: () -> Void = {}

    static var live: SettingsFilePlace {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return SettingsFilePlace(preferences: .live, rightClickMenu: RightClickMenuSettings.fileURL,
                                 wallpapers: support?.appendingPathComponent(CursorScreenshot.wallpaperFolder, isDirectory: true),
                                 captureHistory: support?.appendingPathComponent(CursorScreenshot.historyFolder, isDirectory: true),
                                 cursorBoardHistory: support?.appendingPathComponent(CursorBoard.folder, isDirectory: true),
                                 reloadBoard: CursorBoardConfig.reloadHistory)
    }
}

struct SettingsFileContents {
    var settings: [SettingsFileGroup: [String: Any]] = [:]
    var wallpapers: [String: Data] = [:]
    var themes: [CursorLibrary] = []
    var favoriteThemes: Set<String> = []
    var sentIdentifiers: [String: String] = [:]
    var failedThemes: [String] = []
    var captureHistory: [SettingsFileHistory.Capture] = []
    var boardHistory: [SettingsFileHistory.Board] = []
    var failedHistory: Set<SettingsFileHistoryGroup> = []

    var groups: [SettingsFileGroup] { SettingsFileGroup.allCases.filter { settings[$0] != nil } }

    var histories: [SettingsFileHistoryGroup] {
        SettingsFileHistoryGroup.allCases.filter { $0 == .captureHistory ? !captureHistory.isEmpty : !boardHistory.isEmpty }
    }
}

struct SettingsFileResult: Equatable {
    var failed: [String] = []
    var cleared: [String] = []
}

enum SettingsFile {
    enum Refusal: Error { case newer, unreadable }

    static let format = 1
    static let maxBytes = CursorBoard.largestTotal
    static let typeIdentifier = "com.writronic.macursor.settings"
    static let themeKeys = [MACPreferences.favoriteThemesKey]

    static var type: UTType { UTType(exportedAs: typeIdentifier) }

    static func diskSize(_ url: URL?) -> Int {
        url.flatMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize } ?? 0
    }

    static func export(_ groups: Set<SettingsFileGroup>, themes: [CursorLibrary] = [], favorites: Set<String> = [],
                       history: Set<SettingsFileHistoryGroup> = [], place: SettingsFilePlace) throws -> Data {
        var settings: [String: Any] = [:]
        for group in SettingsFileGroup.allCases where groups.contains(group) {
            var values: [String: Any] = [:]
            for field in group.fields {
                values[field.key] = field.read(place)
            }
            settings[group.rawValue] = values
        }
        var root: [String: Any] = ["format": format, "app": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
                                   "settings": settings]
        if groups.contains(.cursorCapture), let folder = place.wallpapers {
            let ids = (settings[SettingsFileGroup.cursorCapture.rawValue] as? [String: Any])?[MACPreferences.cursorScreenshotKey]
                .flatMap { $0 as? Data }.flatMap { try? JSONDecoder().decode(CursorScreenshotConfig.self, from: $0) }?.background.wallpapers ?? []
            var pictures: [String: Data] = [:]
            for id in ids { pictures[id] = try? Data(contentsOf: folder.appendingPathComponent(id, isDirectory: false)) }
            root["captureWallpapers"] = pictures
        }
        if !themes.isEmpty {
            root["themes"] = try themes.map { lib -> NSDictionary in
                guard let url = lib.fileURL, let stored = NSDictionary(contentsOf: url) else { throw Refusal.unreadable }
                return stored
            }
            root["favoriteThemes"] = themes.map(\.identifier).filter(favorites.contains)
        }
        let lists = SettingsFileHistory.export(history, place: place)
        if !history.isEmpty {
            root["history"] = lists
        }
        guard !settings.isEmpty || !themes.isEmpty || lists.values.contains(where: { !$0.isEmpty }) else { throw Refusal.unreadable }
        return try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
    }

    static func read(_ url: URL, maxBytes: Int = maxBytes) throws -> SettingsFileContents {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= maxBytes,
              let handle = try? FileHandle(forReadingFrom: url) else { throw Refusal.unreadable }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maxBytes + 1) else { throw Refusal.unreadable }
        return try parse(data, maxBytes: maxBytes)
    }

    static func parse(_ data: Data, maxBytes: Int = maxBytes) throws -> SettingsFileContents {
        guard data.count <= maxBytes,
              let root = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              let version = SettingsFileGroup.integer(root["format"]) else { throw Refusal.unreadable }
        guard version <= format else { throw Refusal.newer }
        guard version == format else { throw Refusal.unreadable }
        var contents = SettingsFileContents()
        if let raw = root["settings"] {
            guard let groups = raw as? [String: Any] else { throw Refusal.unreadable }
            for (id, raw) in groups {
                guard let group = SettingsFileGroup(rawValue: id) else { continue }
                guard let stored = raw as? [String: Any] else { throw Refusal.unreadable }
                var values: [String: Any] = [:]
                for field in group.fields {
                    guard let value = stored[field.key] else { continue }
                    guard let checked = field.check(value) else { throw Refusal.unreadable }
                    values[field.key] = checked
                }
                contents.settings[group] = values
            }
        }
        if let raw = root["captureWallpapers"] {
            guard let pictures = raw as? [String: Any] else { throw Refusal.unreadable }
            for (id, picture) in pictures {
                guard UUID(uuidString: id) != nil, let data = picture as? Data, opens(data) else { continue }
                contents.wallpapers[id] = data
            }
        }
        try readThemes(root, into: &contents)
        try SettingsFileHistory.parse(root["history"], into: &contents)
        guard !contents.settings.isEmpty || !contents.themes.isEmpty || !contents.histories.isEmpty else { throw Refusal.unreadable }
        return contents
    }

    private static func readThemes(_ root: [String: Any], into contents: inout SettingsFileContents) throws {
        var stars: Set<String> = []
        if let raw = root["favoriteThemes"] {
            guard let ids = raw as? [String] else { throw Refusal.unreadable }
            stars = Set(ids)
        }
        guard let raw = root["themes"] else { return }
        guard let list = raw as? [Any] else { throw Refusal.unreadable }
        for item in list {
            let stored = item as? [String: Any]
            guard let stored, let lib = CursorLibrary(dictionary: stored), lib.cursors.contains(where: \.isApplicable) else {
                let name = stored?[MACCursorDefinitions.themeNameKey] as? String ?? ""
                contents.failedThemes.append(name.isEmpty ? String(localized: "Unnamed") : name)
                continue
            }
            lib.undoManager.disableUndoRegistration()
            lib.identifier = CursorLibrary.sanitizeName(lib.name)
            lib.undoManager.enableUndoRegistration()
            guard !contents.themes.contains(where: { $0.identifier.caseInsensitiveCompare(lib.identifier) == .orderedSame }) else {
                contents.failedThemes.append(lib.name)
                continue
            }
            if let sent = stored[MACCursorDefinitions.identifierKey] as? String {
                contents.sentIdentifiers[lib.identifier] = sent
                if stars.contains(sent) { contents.favoriteThemes.insert(lib.identifier) }
            }
            contents.themes.append(lib)
        }
    }

    @discardableResult
    static func apply(_ contents: SettingsFileContents, groups: Set<SettingsFileGroup>, place: SettingsFilePlace,
                      landed: [String: String] = [:]) -> SettingsFileResult {
        var incoming = contents.settings.filter { groups.contains($0.key) }
        follow(landed.compactMap { id, final in contents.sentIdentifiers[id].flatMap { $0 == final ? nil : ($0, final) } }, in: &incoming)
        var result = SettingsFileResult()
        result.cleared = SettingsFileClashes.clear(&incoming, place: place)
        if incoming[.cursorCapture] != nil {
            landWallpapers(contents.wallpapers, in: &incoming, place: place)
        }
        for group in SettingsFileGroup.writeOrder {
            guard let values = incoming[group] else { continue }
            do {
                for field in group.fields { try field.write(values[field.key], place) }
            } catch {
                result.failed.append(group.title)
            }
        }
        return result
    }

    static func scriptWarning(_ contents: SettingsFileContents, groups: Set<SettingsFileGroup>) -> String? {
        guard groups.contains(.cursorGestures),
              let data = contents.settings[.cursorGestures]?[MACPreferences.cursorGesturesKey] as? Data,
              let config = try? JSONDecoder().decode(CursorGesturesConfig.self, from: data) else { return nil }
        let scripts: [(name: String, text: String)] = config.actions.compactMap { action in
            switch action.kind {
            case .appleScript(let script): (action.name, CursorGestures.scriptFile(script) == nil ? script : fromHome(script.trimmingCharacters(in: .whitespacesAndNewlines)))
            case .shell(let command), .shortcutsApp(let command), .website(let command): (action.name, command)
            default: nil
            }
        }
        guard !scripts.isEmpty else { return nil }
        var lines: [String] = []
        for script in scripts.prefix(5) {
            let shown = script.text.split(whereSeparator: \.isNewline).map { plain(String($0)) }.filter { !$0.isEmpty }
            lines.append(plain(script.name.split(whereSeparator: \.isNewline).joined(separator: " ")))
            lines += shown.prefix(3).map { "    " + $0 } + (shown.count > 3 ? ["    …"] : [])
        }
        if scripts.count > 5 {
            lines.append(String(localized: "and \(scripts.count - 5) more"))
        }
        return lines.joined(separator: "\n")
    }

    static func plain(_ line: String) -> String {
        let needed: [ClosedRange<UInt32>] = [0x200C...0x200D, 0xFE00...0xFE0F, 0xE0100...0xE01EF]
        var visible = String.UnicodeScalarView()
        for scalar in line.unicodeScalars where !scalar.properties.isDefaultIgnorableCodePoint || needed.contains(where: { $0.contains(scalar.value) }) {
            visible.append(scalar.properties.generalCategory == .control ? " " : scalar)
        }
        let text = visible.split(whereSeparator: \.properties.isWhitespace).map(String.init).joined(separator: " ")
        return text.count > 60 ? String(text.prefix(59)) + "…" : text
    }

    static func fromHome(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path == home || path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }

    static func homeExpanded(_ path: String) -> String {
        path == "~" || path.hasPrefix("~/") ? FileManager.default.homeDirectoryForCurrentUser.path + path.dropFirst() : path
    }

    static func onThisMac(_ path: String) -> String {
        let named = homeExpanded(path)
        guard named.hasPrefix("/") else { return "" }
        let home = FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath().path
        let full = URL(fileURLWithPath: named).resolvingSymlinksInPath().path
        var folder: ObjCBool = false
        guard full == home || full.hasPrefix(home + "/"),
              FileManager.default.fileExists(atPath: full, isDirectory: &folder), folder.boolValue else { return "" }
        return full
    }

    private static func follow(_ moves: [(sent: String, landed: String)], in incoming: inout [SettingsFileGroup: [String: Any]]) {
        guard !moves.isEmpty else { return }
        let steps = moves.map { (sent: $0.sent, mark: UUID().uuidString, landed: $0.landed) }
        let rulesKey = MACPreferences.autoSwitchRulesKey
        if let data = incoming[.cursorControl]?[rulesKey] as? Data, var rules = try? JSONDecoder().decode(AutoSwitchConfig.self, from: data) {
            for step in steps { rules.replaceThemeIdentifier(step.sent, with: step.mark) }
            for step in steps { rules.replaceThemeIdentifier(step.mark, with: step.landed) }
            incoming[.cursorControl]?[rulesKey] = try? JSONEncoder().encode(rules)
        }
        let slotsKey = MACPreferences.favoriteCursorsKey
        if var slots = incoming[.shortcut]?[slotsKey] {
            for step in steps { slots = MACShortcutSlotsByReplacingTheme(slots, step.sent, step.mark) ?? slots }
            for step in steps { slots = MACShortcutSlotsByReplacingTheme(slots, step.mark, step.landed) ?? slots }
            incoming[.shortcut]?[slotsKey] = slots
        }
        let gesturesKey = MACPreferences.cursorGesturesKey
        if let data = incoming[.cursorGestures]?[gesturesKey] as? Data, var config = try? JSONDecoder().decode(CursorGesturesConfig.self, from: data) {
            for (from, to) in steps.map({ ($0.sent, $0.mark) }) + steps.map({ ($0.mark, $0.landed) }) {
                for gesture in config.gestures.indices {
                    for step in config.gestures[gesture].steps.indices where config.gestures[gesture].steps[step].action == CursorGestures.themePrefix + from {
                        config.gestures[gesture].steps[step].action = CursorGestures.themePrefix + to
                    }
                }
            }
            incoming[.cursorGestures]?[gesturesKey] = try? JSONEncoder().encode(config)
        }
    }

    static func opens(_ data: Data) -> Bool {
        CGImageSourceCreateWithData(data as CFData, nil).map { CGImageSourceGetCount($0) > 0 } ?? false
    }

    private static func landWallpapers(_ pictures: [String: Data], in incoming: inout [SettingsFileGroup: [String: Any]], place: SettingsFilePlace) {
        let key = MACPreferences.cursorScreenshotKey
        guard let data = incoming[.cursorCapture]?[key] as? Data,
              var config = try? JSONDecoder().decode(CursorScreenshotConfig.self, from: data) else { return }
        config.background.wallpapers = config.background.wallpapers.filter { id in
            guard let picture = pictures[id], let folder = place.wallpapers else { return false }
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try picture.write(to: folder.appendingPathComponent(id, isDirectory: false), options: .atomic)
                return true
            } catch {
                return false
            }
        }
        incoming[.cursorCapture]?[key] = try? JSONEncoder().encode(config)
    }
}

enum SettingsFileClashes {
    private struct Row {
        let group: SettingsFileGroup
        let name: String
        var key: KeyboardShortcutData?
        var click: CursorGestureTrigger?
    }

    private static var clickPairs: Set<Set<SettingsFileGroup>> {
        [[.cursorCapture, .cursorBoard], [.cursorBoard, .cursorTranslator], [.cursorHighlight, .cursorCapture], [.cursorHighlight, .cursorBoard], [.cursorHighlight, .cursorTranslator]]
    }

    private static var captureRows: [(item: MACMenuBarCaptureItem, click: WritableKeyPath<CursorScreenshotConfig, CursorGestureTrigger>)] {
        [(.area, \.areaClick), (.previousArea, \.repeatClick), (.fullscreen, \.wholeScreenClick), (.selfTimer, \.selfTimerClick), (.text, \.textClick)]
    }

    static func clear(_ incoming: inout [SettingsFileGroup: [String: Any]], place: SettingsFilePlace) -> [String] {
        func decoded<Value: Decodable>(_ stored: Any?, fallback: String) -> Value? {
            try? JSONDecoder().decode(Value.self, from: stored as? Data ?? Data(fallback.utf8))
        }
        func value<Value: Decodable>(_ type: Value.Type, _ group: SettingsFileGroup, _ key: String, fallback: String = "{}") -> Value? {
            decoded(incoming[group].map { $0[key] } ?? MACPreferences.value(forKey: key, operations: place.preferences), fallback: fallback)
        }
        guard var capture = value(CursorScreenshotConfig.self, .cursorCapture, MACPreferences.cursorScreenshotKey),
              var board = value(CursorBoardConfig.self, .cursorBoard, MACPreferences.cursorBoardKey),
              var shaker = value(CursorShakerConfig.self, .cursorControl, MACPreferences.cursorShakerKey),
              var translator = value(CursorTranslatorConfig.self, .cursorTranslator, MACPreferences.cursorTranslatorKey),
              var highlight = value(CursorHighlightConfig.self, .cursorHighlight, MACPreferences.cursorHighlightKey),
              var slots = value([FavoriteCursorSlot].self, .shortcut, MACPreferences.favoriteCursorsKey, fallback: "[]") else { return [] }

        var rows = captureRows.map { Row(group: .cursorCapture, name: String(localized: String.LocalizationValue($0.item.title)),
                                         key: capture[keyPath: $0.item.field], click: capture[keyPath: $0.click]) }
        rows.append(Row(group: .cursorBoard, name: String(localized: "Show Recent Items"), key: board.listShortcut, click: board.listClick))
        rows.append(Row(group: .cursorBoard, name: String(localized: "Show Cursor Board"), key: board.panelShortcut, click: board.panelClick))
        rows.append(Row(group: .cursorControl, name: String(localized: "Cursor Shaker"), key: shaker.shortcut))
        rows.append(Row(group: .cursorTranslator, name: String(localized: "Cursor Translator"), key: translator.shortcut, click: translator.trigger))
        rows.append(Row(group: .cursorHighlight, name: String(localized: "Cursor Highlight"), key: highlight.shortcut))
        rows.append(Row(group: .cursorHighlight, name: String(localized: "Spotlight (Cursor Highlight)"), key: highlight.spotlightKey, click: highlight.spotlightClick))
        rows.append(Row(group: .cursorHighlight, name: String(localized: "Flashlight Mode"), key: highlight.flashlightKey, click: highlight.flashlightClick))
        rows.append(Row(group: .cursorHighlight, name: String(localized: "Magnifier"), key: highlight.magnifierKey, click: highlight.magnifierClick))
        let slotRows = slots.indices.filter { slots[$0].themeIdentifier != nil }
        rows += slotRows.map { Row(group: .shortcut, name: String(localized: "Shortcut"), key: slots[$0].shortcut) }

        let held = rows.filter { incoming[$0.group] == nil }
        var cleared: [String] = []
        for index in rows.indices where incoming[rows[index].group] != nil {
            var row = rows[index]
            if let key = row.key, CursorScreenshot.refuses(key, held: held.compactMap(\.key)) {
                row.key = nil
            }
            if let click = row.click,
               CursorScreenshot.refuses(click, held: held.filter { clickPairs.contains([row.group, $0.group]) }.compactMap(\.click)) {
                row.click = CursorGestureTrigger()
            }
            if row.key != rows[index].key || row.click != rows[index].click, !cleared.contains(row.name) {
                cleared.append(row.name)
            }
            rows[index] = row
        }
        guard !cleared.isEmpty else { return [] }

        for (offset, entry) in captureRows.enumerated() {
            capture[keyPath: entry.item.field] = rows[offset].key
            capture[keyPath: entry.click] = rows[offset].click ?? CursorGestureTrigger()
        }
        let next = captureRows.count
        board.listShortcut = rows[next].key
        board.listClick = rows[next].click ?? CursorGestureTrigger()
        board.panelShortcut = rows[next + 1].key
        board.panelClick = rows[next + 1].click ?? CursorGestureTrigger()
        shaker.shortcut = rows[next + 2].key
        translator.shortcut = rows[next + 3].key
        translator.trigger = rows[next + 3].click ?? CursorGestureTrigger()
        highlight.shortcut = rows[next + 4].key
        highlight.spotlightKey = rows[next + 5].key
        highlight.spotlightClick = rows[next + 5].click ?? CursorGestureTrigger()
        highlight.flashlightKey = rows[next + 6].key
        highlight.flashlightClick = rows[next + 6].click ?? CursorGestureTrigger()
        highlight.magnifierKey = rows[next + 7].key
        highlight.magnifierClick = rows[next + 7].click ?? CursorGestureTrigger()
        for (offset, slot) in slotRows.enumerated() { slots[slot].shortcut = rows[next + 8 + offset].key }

        func store<Value: Encodable>(_ value: Value, _ group: SettingsFileGroup, _ key: String) {
            guard incoming[group] != nil else { return }
            incoming[group]?[key] = try? JSONEncoder().encode(value)
        }
        store(capture, .cursorCapture, MACPreferences.cursorScreenshotKey)
        store(board, .cursorBoard, MACPreferences.cursorBoardKey)
        store(shaker, .cursorControl, MACPreferences.cursorShakerKey)
        store(translator, .cursorTranslator, MACPreferences.cursorTranslatorKey)
        store(highlight, .cursorHighlight, MACPreferences.cursorHighlightKey)
        store(slots, .shortcut, MACPreferences.favoriteCursorsKey)
        return cleared
    }
}
