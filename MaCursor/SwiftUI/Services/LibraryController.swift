import Foundation

class LibraryController: @unchecked Sendable {


    private(set) var themes: Set<CursorLibrary> = []

    weak var appliedTheme: CursorLibrary? {
        didSet {
            if let id = appliedTheme?.identifier {
                MACPreferences.set(id, forKey: MACPreferences.appliedCursorKey, operations: preferences)
            } else {
                MACPreferences.set(nil, forKey: MACPreferences.appliedCursorKey, operations: preferences)
            }
        }
    }

    let undoManager: UndoManager
    let libraryURL: URL
    private let preferences: MACPreferences.Operations

    var trashItem: (URL) throws -> URL? = { url in
        var resultingURL: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
        return resultingURL as URL?
    }

    private var willSaveObserver: Any?


    init(url: URL, preferences: MACPreferences.Operations = .live) {
        self.libraryURL = url
        self.preferences = preferences
        self.undoManager = UndoManager()

        willSaveObserver = NotificationCenter.default.addObserver(
            forName: .cursorLibraryWillSave,
            object: nil,
            queue: nil
        ) { [weak self] note in
            self?.willSaveNotification(note)
        }

        loadLibrary()
    }

    deinit {
        if let observer = willSaveObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func url(for theme: CursorLibrary) -> URL {
        let baseName = sanitizedFilename(from: theme.name)

        if let existingURL = theme.fileURL,
           existingURL.deletingLastPathComponent().standardizedFileURL == libraryURL.standardizedFileURL,
           existingURL.deletingPathExtension().lastPathComponent == baseName {
            return existingURL
        }

        let fm = FileManager.default
        var candidate = libraryURL.appendingPathComponent(baseName + ".cursor")
        var suffix = 2
        while fm.fileExists(atPath: candidate.path), !(theme.fileURL.map { CursorLibrary.isSameFile($0, candidate) } ?? false) {
            candidate = libraryURL.appendingPathComponent("\(baseName)-\(suffix).cursor")
            suffix += 1
        }

        return candidate
    }

    private func sanitizedFilename(from name: String) -> String {
        let sanitized = name
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .drop { $0 == "." }
        return sanitized.isEmpty ? "Unnamed" : String(sanitized)
    }


    private func loadLibrary() {
        undoManager.disableUndoRegistration()
        defer { undoManager.enableUndoRegistration() }

        themes = []
        let fm = FileManager.default
        let themesPath = libraryURL.path

        guard let contents = try? fm.contentsOfDirectory(atPath: themesPath) else { return }
        let applied = MACPreferences.value(forKey: MACPreferences.appliedCursorKey, operations: preferences) as? String

        for filename in contents {
            guard !filename.hasPrefix(".") else { continue }

            let fileURL = libraryURL.appendingPathComponent(filename)
            guard let library = CursorLibrary(contentsOfURL: fileURL) else { continue }

            if library.identifier == applied {
                appliedTheme = library
            }

            addTheme(library)
        }
    }


    func importTheme(at url: URL) {
        guard let lib = CursorLibrary(contentsOfURL: url) else { return }
        importTheme(lib)
    }

    @discardableResult
    func importTheme(_ lib: CursorLibrary) -> Bool {
        (lib.name, lib.identifier) = CursorLibrary.uniqueIdentity(forName: lib.name, avoiding: Set(themes.map(\.identifier)))
        lib.fileURL = url(for: lib)
        guard lib.write(toFile: lib.fileURL!.path, atomically: true) else { return false }

        addTheme(lib)
        return true
    }

    static func existingTheme(sameNameAs identifier: String, in themes: some Sequence<CursorLibrary>, excluding taken: [CursorLibrary]) -> CursorLibrary? {
        let open = themes.filter { theme in !taken.contains { $0 === theme } }.sorted { $0.identifier < $1.identifier }
        let same = { (candidate: String) in candidate.caseInsensitiveCompare(identifier) == .orderedSame }
        return open.first { same($0.identifier) } ?? open.first { same(CursorLibrary.sanitizeName($0.name)) }
    }

    @MainActor
    func replaceOrAdd(_ lib: CursorLibrary, replacing old: CursorLibrary?) -> Bool {
        guard let old else {
            return importTheme(lib)
        }
        lib.undoManager.disableUndoRegistration()
        (lib.name, lib.identifier) = (old.name, old.identifier)
        lib.undoManager.enableUndoRegistration()
        lib.fileURL = old.fileURL ?? url(for: lib)
        guard let path = lib.fileURL?.path, lib.write(toFile: path, atomically: true) else { return false }
        old.library = nil
        lib.library = self
        themes = themes.filter { $0 !== old }
        themes.insert(lib)
        if appliedTheme === old {
            appliedTheme = lib
        }
        return true
    }


    func addTheme(_ theme: CursorLibrary) {
        let id = theme.identifier
        guard !themes.contains(theme),
              !themes.contains(where: { $0.identifier == id }) else {
            NSLog("Not adding %@ to the library because an object with that identifier already exists", id)
            return
        }

        theme.library = self
        themes.insert(theme)

        undoManager.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated { try? target.removeTheme(theme) }
        }
        if !undoManager.isUndoing {
            undoManager.setActionName("Add " + (theme.name.isEmpty ? "Theme" : theme.name))
        }

        theme.undoManager.removeAllActions()
    }

    @MainActor
    func removeTheme(_ theme: CursorLibrary) throws {
        if let fileURL = theme.fileURL, let trashedURL = try trash(fileURL) {
            undoManager.registerUndo(withTarget: self) { target in
                target.importTheme(at: trashedURL)
            }
        }

        if theme === appliedTheme {
            restoreTheme()
        }

        if theme.library === self {
            theme.library = nil
        }

        themes = themes.filter { $0 !== theme }

        if !undoManager.isUndoing {
            undoManager.setActionName("Remove " + (theme.name.isEmpty ? "Theme" : theme.name))
        }
    }

    @MainActor
    func removeAllThemes() throws {
        if appliedTheme != nil {
            restoreTheme()
        }

        var failure: Error?
        var kept: [CursorLibrary] = []
        for theme in themes {
            do {
                if let fileURL = theme.fileURL {
                    _ = try trash(fileURL)
                }
                theme.library = nil
            } catch {
                failure = failure ?? error
                kept.append(theme)
            }
        }

        if let remaining = try? FileManager.default.contentsOfDirectory(atPath: libraryURL.path) {
            for filename in remaining where !filename.hasPrefix(".") {
                do {
                    _ = try trash(libraryURL.appendingPathComponent(filename))
                } catch {
                    failure = failure ?? error
                }
            }
        }

        themes = Set(kept)

        undoManager.removeAllActions()

        if let failure {
            throw failure
        }
    }

    private func trash(_ url: URL) throws -> URL? {
        do {
            return try trashItem(url)
        } catch CocoaError.fileNoSuchFile {
            return nil
        }
    }


    @MainActor
    func applyTheme(_ theme: CursorLibrary) {
        guard let path = theme.fileURL?.path else { return }
        if MACCursorActions.shared.applyTheme(atPath: path) {
            appliedTheme = theme
        }
    }

    @MainActor
    func restoreTheme() {
        CursorService.restoreAll()
        appliedTheme = nil
    }


    func themes(withIdentifier identifier: String) -> Set<CursorLibrary> {
        Set(themes.filter { $0.identifier == identifier })
    }


    private func willSaveNotification(_ note: Notification) {
        guard let theme = note.object as? CursorLibrary, theme.library === self else { return }
        theme.fileURL = url(for: theme)
    }
}
