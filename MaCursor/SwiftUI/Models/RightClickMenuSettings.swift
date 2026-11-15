import Foundation

enum RightClickMenuContext: Equatable {
    case items
    case container
}

struct RightClickMenuRowOptions: Codable, Equatable {
    var addToMainMenu = false
    var enabled = true

    init(addToMainMenu: Bool = false, enabled: Bool = true) {
        self.addToMainMenu = addToMainMenu
        self.enabled = enabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        addToMainMenu = try container.decodeIfPresent(Bool.self, forKey: .addToMainMenu) ?? false
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }
}

struct RightClickMenuAppRow: Codable, Equatable, Identifiable {
    let bundleIdentifier: String
    var addToMainMenu = false
    var enabled = true

    var id: String { bundleIdentifier }

    init(bundleIdentifier: String, addToMainMenu: Bool = false, enabled: Bool = true) {
        self.bundleIdentifier = bundleIdentifier
        self.addToMainMenu = addToMainMenu
        self.enabled = enabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bundleIdentifier = try container.decode(String.self, forKey: .bundleIdentifier)
        addToMainMenu = try container.decodeIfPresent(Bool.self, forKey: .addToMainMenu) ?? false
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }
}

enum RightClickMenuAppList: CaseIterable {
    case openWith
    case commonApps

    var keyPath: WritableKeyPath<RightClickMenuSettings, [RightClickMenuAppRow]> {
        switch self {
        case .openWith: return \.openWithApps
        case .commonApps: return \.commonApps
        }
    }

    var group: RightClickMenuGroup {
        switch self {
        case .openWith: return .openWith
        case .commonApps: return .commonApps
        }
    }

    func itemTitle(_ applicationName: String) -> String {
        let format = self == .openWith ? String(localized: "Open With %@") : String(localized: "Open in %@")
        return String(format: format, applicationName)
    }
}

enum RightClickMenuAddedFileProblem: LocalizedError, Equatable {
    case limitReached
    case missingField
    case nameTaken
    case fileNameHasSlashOrColon
    case fileNameTooLong
    case badExtension

    var reason: String? {
        switch self {
        case .limitReached, .missingField: return nil
        case .nameTaken: return String(localized: "This name is already used.")
        case .fileNameHasSlashOrColon: return String(localized: "The file name can’t contain “/” or “:”.")
        case .fileNameTooLong: return String(localized: "This file name is too long.")
        case .badExtension: return String(localized: "The extension can use up to 16 letters, numbers, - or _.")
        }
    }

    var errorDescription: String? { reason }
}

struct RightClickMenuAddedFile: Codable, Equatable, Identifiable {
    let menuName: String
    let name: String
    let fileExtension: String
    var options = RightClickMenuRowOptions()

    var id: String { "\(name).\(fileExtension)" }
    var file: RightClickMenuFile { RightClickMenuFile(key: id, name: menuName) }

    fileprivate init(menuName: String, name: String, fileExtension: String) {
        self.menuName = menuName
        self.name = name
        self.fileExtension = fileExtension
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        fileExtension = try container.decode(String.self, forKey: .fileExtension)
        menuName = try container.decodeIfPresent(String.self, forKey: .menuName) ?? "\(name).\(fileExtension)"
        options = try container.decode(RightClickMenuRowOptions.self, forKey: .options)
    }
}

struct RightClickMenuFile: Hashable {
    let key: String
    let name: String

    init(key: String, name: String) {
        self.key = key
        self.name = name
    }

    init?(key: String) {
        guard key.contains(".") else { return nil }
        self.init(key: key, name: key)
    }

    var rowTitle: String { "\(name) (\(key))" }

    var baseName: String { String(key[..<(key.lastIndex(of: ".") ?? key.endIndex)]) }

    var fileExtension: String { key.lastIndex(of: ".").map { String(key[key.index(after: $0)...]) } ?? "" }
}

enum RightClickMenuGroup: String, CaseIterable {
    case openWith
    case newFile
    case commonApps

    var title: String {
        switch self {
        case .openWith: return String(localized: "Open With")
        case .newFile: return String(localized: "New File")
        case .commonApps: return String(localized: "Common Apps")
        }
    }

    var symbolName: String {
        switch self {
        case .openWith: return "arrow.up.forward.app"
        case .newFile: return "doc.badge.plus"
        case .commonApps: return "square.stack.3d.up"
        }
    }

    var appList: RightClickMenuAppList? {
        switch self {
        case .openWith: return .openWith
        case .newFile: return nil
        case .commonApps: return .commonApps
        }
    }
}

enum RightClickMenuSwitch: String, CaseIterable {
    case copyPath
    case hideSelected
    case unhideSelected
    case hideAll
    case unhideAll

    var keyPath: WritableKeyPath<RightClickMenuSettings, Bool> {
        switch self {
        case .copyPath: return \.copyPathEnabled
        case .hideSelected: return \.hideSelectedFilesEnabled
        case .unhideSelected: return \.unhideSelectedFilesEnabled
        case .hideAll: return \.hideAllFilesInPathEnabled
        case .unhideAll: return \.unhideAllFilesInPathEnabled
        }
    }

    var title: String {
        switch self {
        case .copyPath: return String(localized: "Copy Path")
        case .hideSelected: return String(localized: "Hide Selected File(s)")
        case .unhideSelected: return String(localized: "Unhide Selected Files")
        case .hideAll: return String(localized: "Hide All Files in Path")
        case .unhideAll: return String(localized: "Unhide All Files in Path")
        }
    }

    var symbolName: String {
        switch self {
        case .copyPath: return "doc.on.doc"
        case .hideSelected, .hideAll: return "eye.slash"
        case .unhideSelected, .unhideAll: return "eye"
        }
    }
}

enum RightClickMenuItem: Hashable, Encodable {
    case group(RightClickMenuGroup)
    case action(RightClickMenuSwitch)
    case application(RightClickMenuAppList, String)
    case file(RightClickMenuFile)

    static var defaultOrder: [RightClickMenuItem] {
        [.group(.openWith), .action(.copyPath), .group(.newFile), .group(.commonApps),
         .action(.hideSelected), .action(.unhideSelected), .action(.hideAll), .action(.unhideAll)]
    }

    init?(key: String) {
        if let group = RightClickMenuGroup(rawValue: key) {
            self = .group(group)
        } else if let action = RightClickMenuSwitch(rawValue: key) {
            self = .action(action)
        } else {
            let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2, let group = RightClickMenuGroup(rawValue: parts[0]) else { return nil }
            if let list = group.appList {
                self = .application(list, parts[1])
            } else if let file = RightClickMenuFile(key: parts[1]) {
                self = .file(file)
            } else {
                return nil
            }
        }
    }

    var key: String {
        switch self {
        case .group(let group): return group.rawValue
        case .action(let action): return action.rawValue
        case .application(let list, let identifier): return "\(list.group.rawValue):\(identifier)"
        case .file(let file): return "\(RightClickMenuGroup.newFile.rawValue):\(file.key)"
        }
    }

    func shows(in context: RightClickMenuContext) -> Bool {
        switch self {
        case .group(.openWith), .application(.openWith, _), .action(.hideSelected), .action(.unhideSelected):
            return context == .items
        case .action(.hideAll), .action(.unhideAll):
            return context == .container
        default:
            return true
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(key)
    }
}

enum RightClickMenuSettingsError: LocalizedError {
    case duplicateApplication

    var errorDescription: String? {
        switch self {
        case .duplicateApplication: return String(localized: "That app is already in the list.")
        }
    }
}

struct RightClickMenuSettings: Codable, Equatable {
    static let appGroupIdentifier = "SP495GG2KZ.com.writronic.macursor"

    var isEnabled = false
    var hasFullDiskAccess = false
    var copyPathEnabled = true
    var hideSelectedFilesEnabled = false
    var unhideSelectedFilesEnabled = false
    var hideAllFilesInPathEnabled = false
    var unhideAllFilesInPathEnabled = false
    var addedFiles = Self.defaultFiles
    var openWithApps = [RightClickMenuAppRow(bundleIdentifier: "com.sublimetext.4")]
    var commonApps = [RightClickMenuAppRow(bundleIdentifier: "com.apple.Terminal", addToMainMenu: true)]
    var menuOrder = RightClickMenuItem.defaultOrder

    static let maximumFileTypes = 64

    var isActive: Bool { isEnabled && hasFullDiskAccess }

    static var defaultFiles: [RightClickMenuAddedFile] {
        [RightClickMenuAddedFile(menuName: String(localized: "Text File"), name: String(localized: "New Text File"), fileExtension: "txt"),
         RightClickMenuAddedFile(menuName: String(localized: "Markdown File"), name: String(localized: "New Markdown File"), fileExtension: "md")]
    }

    var files: [RightClickMenuFile] { addedFiles.map(\.file) }

    subscript(file file: RightClickMenuFile) -> RightClickMenuRowOptions {
        get { addedFiles.first { $0.id == file.key }?.options ?? RightClickMenuRowOptions(enabled: false) }
        set {
            guard let index = addedFiles.firstIndex(where: { $0.id == file.key }) else { return }
            addedFiles[index].options = newValue
        }
    }

    func addedFile(menuName: String, name: String, fileExtension: String,
                   replacing replaced: String? = nil) -> Result<RightClickMenuAddedFile, RightClickMenuAddedFileProblem> {
        if let replaced {
            var others = self
            others.addedFiles.removeAll { $0.id == replaced }
            return others.addedFile(menuName: menuName, name: name, fileExtension: fileExtension)
        }
        let menuName = menuName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let typedExtension = fileExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        let file = RightClickMenuAddedFile(menuName: menuName, name: name,
                                           fileExtension: typedExtension.hasPrefix(".") ? String(typedExtension.dropFirst()) : typedExtension)
        func same(_ one: String, _ other: String) -> Bool { one.caseInsensitiveCompare(other) == .orderedSame }
        guard files.count < Self.maximumFileTypes else { return .failure(.limitReached) }
        if !menuName.isEmpty && addedFiles.contains(where: { same($0.menuName, menuName) })
            || !name.isEmpty && !typedExtension.isEmpty && addedFiles.contains(where: { same($0.id, file.id) }) {
            return .failure(.nameTaken)
        }
        if name.contains("/") || name.contains(":") { return .failure(.fileNameHasSlashOrColon) }
        if "\(name) 100.\(file.fileExtension)".decomposedStringWithCanonicalMapping.utf16.count > 255 { return .failure(.fileNameTooLong) }
        if !typedExtension.isEmpty && !((1...16).contains(file.fileExtension.count)
            && file.fileExtension.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })) {
            return .failure(.badExtension)
        }
        if menuName.isEmpty || name.isEmpty || typedExtension.isEmpty { return .failure(.missingField) }
        return .success(file)
    }

    @discardableResult
    mutating func addFile(menuName: String, name: String, fileExtension: String) throws -> RightClickMenuAddedFile {
        let file = try addedFile(menuName: menuName, name: name, fileExtension: fileExtension).get()
        addedFiles.append(file)
        return file
    }

    @discardableResult
    mutating func editFile(_ id: String, menuName: String, name: String, fileExtension: String) throws -> RightClickMenuAddedFile {
        guard let index = addedFiles.firstIndex(where: { $0.id == id }) else { throw CocoaError(.fileNoSuchFile) }
        var file = try addedFile(menuName: menuName, name: name, fileExtension: fileExtension, replacing: id).get()
        let old = addedFiles[index].file
        file.options = addedFiles[index].options
        addedFiles[index] = file
        menuOrder = menuOrder.map { $0 == .file(old) ? .file(file.file) : $0 }
        return file
    }

    init(isEnabled: Bool = false, hasFullDiskAccess: Bool = false, copyPathEnabled: Bool = true,
         addedFiles: [RightClickMenuAddedFile] = defaultFiles,
         openWithApps: [RightClickMenuAppRow] = [RightClickMenuAppRow(bundleIdentifier: "com.sublimetext.4")],
         commonApps: [RightClickMenuAppRow] = [RightClickMenuAppRow(bundleIdentifier: "com.apple.Terminal", addToMainMenu: true)],
         hideSelectedFilesEnabled: Bool = false, unhideSelectedFilesEnabled: Bool = false,
         hideAllFilesInPathEnabled: Bool = false, unhideAllFilesInPathEnabled: Bool = false,
         menuOrder: [RightClickMenuItem] = RightClickMenuItem.defaultOrder) {
        self.isEnabled = isEnabled
        self.hasFullDiskAccess = hasFullDiskAccess
        self.copyPathEnabled = copyPathEnabled
        self.hideSelectedFilesEnabled = hideSelectedFilesEnabled
        self.unhideSelectedFilesEnabled = unhideSelectedFilesEnabled
        self.hideAllFilesInPathEnabled = hideAllFilesInPathEnabled
        self.unhideAllFilesInPathEnabled = unhideAllFilesInPathEnabled
        self.addedFiles = addedFiles
        self.openWithApps = openWithApps
        self.commonApps = commonApps
        self.menuOrder = menuOrder
        normalizeMenuOrder()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        hasFullDiskAccess = try container.decodeIfPresent(Bool.self, forKey: .hasFullDiskAccess) ?? false
        copyPathEnabled = try container.decodeIfPresent(Bool.self, forKey: .copyPathEnabled) ?? true
        hideSelectedFilesEnabled = try container.decodeIfPresent(Bool.self, forKey: .hideSelectedFilesEnabled) ?? false
        unhideSelectedFilesEnabled = try container.decodeIfPresent(Bool.self, forKey: .unhideSelectedFilesEnabled) ?? false
        hideAllFilesInPathEnabled = try container.decodeIfPresent(Bool.self, forKey: .hideAllFilesInPathEnabled) ?? false
        unhideAllFilesInPathEnabled = try container.decodeIfPresent(Bool.self, forKey: .unhideAllFilesInPathEnabled) ?? false
        if let saved = try? container.decodeIfPresent([RightClickMenuAddedFile].self, forKey: .addedFiles) {
            addedFiles = []
            for file in saved {
                guard case .success(var valid) = addedFile(menuName: file.menuName, name: file.name, fileExtension: file.fileExtension),
                      valid.id == file.id else { continue }
                valid.options = file.options
                addedFiles.append(valid)
            }
        }
        openWithApps = try container.decodeIfPresent([RightClickMenuAppRow].self, forKey: .openWithApps) ?? [RightClickMenuAppRow(bundleIdentifier: "com.sublimetext.4")]
        commonApps = try container.decodeIfPresent([RightClickMenuAppRow].self, forKey: .commonApps) ?? [RightClickMenuAppRow(bundleIdentifier: "com.apple.Terminal", addToMainMenu: true)]
        let keys = try? container.decodeIfPresent([String].self, forKey: .menuOrder)
        menuOrder = keys?.compactMap(RightClickMenuItem.init(key:)) ?? RightClickMenuItem.defaultOrder
        try validate()
        normalizeMenuOrder()
    }

    mutating func addApplication(_ bundleIdentifier: String, to list: RightClickMenuAppList) throws {
        guard !self[keyPath: list.keyPath].contains(where: { $0.bundleIdentifier == bundleIdentifier }) else {
            throw RightClickMenuSettingsError.duplicateApplication
        }
        guard !bundleIdentifier.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
        self[keyPath: list.keyPath].append(RightClickMenuAppRow(bundleIdentifier: bundleIdentifier))
    }

    func menuItems(isAvailable: (String) -> Bool) -> [RightClickMenuItem] {
        let arrangement = menuArrangement(isAvailable: isAvailable)
        return arrangement.order.filter(arrangement.shown.contains)
    }

    func submenuItems(of group: RightClickMenuGroup, isAvailable: (String) -> Bool) -> [RightClickMenuItem] {
        rows(of: group, isAvailable: isAvailable).filter { !$0.promoted }.map(\.item)
    }

    mutating func setMenuOrder(_ items: [RightClickMenuItem], isAvailable: (String) -> Bool) {
        let arrangement = menuArrangement(isAvailable: isAvailable)
        var seen = Set<RightClickMenuItem>()
        let moved = items.filter { arrangement.shown.contains($0) && seen.insert($0).inserted }
        var queue = moved + arrangement.order.filter { arrangement.shown.contains($0) && !seen.contains($0) }
        menuOrder = arrangement.order.map { arrangement.shown.contains($0) ? queue.removeFirst() : $0 }
    }

    private func rows(of group: RightClickMenuGroup, isAvailable: (String) -> Bool) -> [(item: RightClickMenuItem, promoted: Bool)] {
        if let list = group.appList {
            return self[keyPath: list.keyPath].filter { $0.enabled && isAvailable($0.bundleIdentifier) }
                .map { (.application(list, $0.bundleIdentifier), $0.addToMainMenu) }
        }
        return files.filter { self[file: $0].enabled }.map { (.file($0), self[file: $0].addToMainMenu) }
    }

    private func menuArrangement(isAvailable: (String) -> Bool) -> (order: [RightClickMenuItem], shown: Set<RightClickMenuItem>) {
        var order: [RightClickMenuItem] = []
        var shown = Set<RightClickMenuItem>()
        for item in menuOrder {
            switch item {
            case .group(let group):
                let rows = rows(of: group, isAvailable: isAvailable)
                let submenu = rows.firstIndex { !$0.promoted } ?? rows.endIndex
                let unplaced = rows.indices.filter { rows[$0].promoted && !menuOrder.contains(rows[$0].item) }
                order += unplaced.filter { $0 < submenu }.map { rows[$0].item }
                order.append(item)
                order += unplaced.filter { $0 > submenu }.map { rows[$0].item }
                if submenu < rows.endIndex { shown.insert(item) }
                for row in rows where row.promoted { shown.insert(row.item) }
            case .action(let action):
                order.append(item)
                if self[keyPath: action.keyPath] { shown.insert(item) }
            case .application, .file:
                order.append(item)
            }
        }
        return (order, shown)
    }

    private mutating func normalizeMenuOrder() {
        var seen = Set<RightClickMenuItem>()
        var order = menuOrder.compactMap(stored).filter { seen.insert($0).inserted }
        let defaults = RightClickMenuItem.defaultOrder
        for (index, item) in defaults.enumerated() where !seen.contains(item) {
            let previous = index == 0 ? nil : order.firstIndex(of: defaults[index - 1])
            order.insert(item, at: previous.map { $0 + 1 } ?? 0)
        }
        menuOrder = order
    }

    private func stored(_ item: RightClickMenuItem) -> RightClickMenuItem? {
        switch item {
        case .group, .action:
            return item
        case .application(let list, let identifier):
            return self[keyPath: list.keyPath].contains { $0.bundleIdentifier == identifier && $0.addToMainMenu } ? item : nil
        case .file(let file):
            return files.first { $0.key == file.key && self[file: $0].addToMainMenu }.map(RightClickMenuItem.file)
        }
    }

    private func validate() throws {
        for list in RightClickMenuAppList.allCases {
            let identifiers = self[keyPath: list.keyPath].map(\.bundleIdentifier)
            guard Set(identifiers).count == identifiers.count else { throw RightClickMenuSettingsError.duplicateApplication }
            guard identifiers.allSatisfy({ !$0.isEmpty }) else { throw CocoaError(.fileReadCorruptFile) }
        }
    }

    static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent("RightClickMenuSettings.json")
    }

    static func load(from url: URL? = fileURL) -> Self {
        guard let url,
              let data = try? Data(contentsOf: url),
              let settings = try? JSONDecoder().decode(Self.self, from: data) else {
            return Self()
        }
        return settings
    }

    func save(to url: URL? = fileURL) throws {
        guard let url else { throw CocoaError(.fileWriteNoPermission) }
        try validate()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }

    static func update(shown: Self, load: () -> Self = { Self.load() },
                       save: (Self) throws -> Void = { try $0.save() },
                       change: (inout Self) throws -> Void) -> (settings: Self, error: Error?) {
        var updated = load()
        do {
            try change(&updated)
            updated.normalizeMenuOrder()
            try updated.validate()
            try save(updated)
            return (updated, nil)
        } catch {
            return (shown, error)
        }
    }

    static func reset(to url: URL? = fileURL) throws -> Self {
        let defaults = Self(hasFullDiskAccess: load(from: url).hasFullDiskAccess)
        try defaults.save(to: url)
        return defaults
    }
}
