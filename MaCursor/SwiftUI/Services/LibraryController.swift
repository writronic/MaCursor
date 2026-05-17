import Foundation

class LibraryController: @unchecked Sendable {
    
    
    private(set) var themes: Set<CursorLibrary> = []
    
    weak var appliedTheme: CursorLibrary? {
        didSet {
            if let id = appliedTheme?.identifier {
                MCPreferences.set(id, forKey: MCPreferences.appliedCursorKey)
            } else {
                MCPreferences.set(nil, forKey: MCPreferences.appliedCursorKey)
            }
        }
    }
    
    let undoManager: UndoManager
    let libraryURL: URL
    
    
    private var willSaveObserver: Any?
    
    
    init(url: URL) {
        self.libraryURL = url
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
        let baseName = sanitizedFilename(from: theme.identifier)
        return libraryURL.appendingPathComponent(baseName + ".cursor")
    }
    
    private func sanitizedFilename(from name: String) -> String {
        var sanitized = name
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if sanitized.isEmpty { sanitized = "Unnamed" }
        return sanitized
    }
    
    
    private func loadLibrary() {
        undoManager.disableUndoRegistration()
        defer { undoManager.enableUndoRegistration() }
        
        themes = []
        let fm = FileManager.default
        let themesPath = libraryURL.path
        
        guard let contents = try? fm.contentsOfDirectory(atPath: themesPath) else { return }
        let applied = MCPreferences.value(forKey: MCPreferences.appliedCursorKey) as? String
        
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
    
    func importTheme(_ lib: CursorLibrary) {
        let existingIds = Set(themes.map { $0.identifier })
        if existingIds.contains(lib.identifier) {
            lib.identifier = lib.identifier + "." + UUID().uuidString
        }
        
        lib.fileURL = url(for: lib)
        lib.write(toFile: lib.fileURL!.path, atomically: true)
        
        addTheme(lib)
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
            target.removeTheme(theme)
        }
        if !undoManager.isUndoing {
            undoManager.setActionName("Add " + (theme.name.isEmpty ? "Theme" : theme.name))
        }
        
        theme.undoManager.removeAllActions()
    }
    
    func removeTheme(_ theme: CursorLibrary) {
        if theme === appliedTheme {
            restoreTheme()
        }
        
        if theme.library === self {
            theme.library = nil
        }
        
        themes = themes.filter { $0 !== theme }
        
        let fm = FileManager.default
        if let fileURL = theme.fileURL {
            let trashPath = NSHomeDirectory() + "/.Trash/" + fileURL.lastPathComponent
            let trashURL = URL(fileURLWithPath: trashPath)
            
            try? fm.removeItem(at: trashURL)
            try? fm.moveItem(at: fileURL, to: trashURL)
            
            undoManager.registerUndo(withTarget: self) { target in
                target.importTheme(at: trashURL)
            }
        }
        
        if !undoManager.isUndoing {
            undoManager.setActionName("Remove " + (theme.name.isEmpty ? "Theme" : theme.name))
        }
    }
    
    func removeAllThemes() {
        if appliedTheme != nil {
            restoreTheme()
        }
        
        let fm = FileManager.default
        
        for theme in themes {
            theme.library = nil
            if let fileURL = theme.fileURL {
                let trashPath = NSHomeDirectory() + "/.Trash/" + fileURL.lastPathComponent
                let trashURL = URL(fileURLWithPath: trashPath)
                try? fm.removeItem(at: trashURL)
                try? fm.moveItem(at: fileURL, to: trashURL)
            }
        }
        
        if let remaining = try? fm.contentsOfDirectory(atPath: libraryURL.path) {
            for filename in remaining where !filename.hasPrefix(".") {
                let fileURL = libraryURL.appendingPathComponent(filename)
                let trashPath = NSHomeDirectory() + "/.Trash/" + filename
                let trashURL = URL(fileURLWithPath: trashPath)
                try? fm.removeItem(at: trashURL)
                try? fm.moveItem(at: fileURL, to: trashURL)
            }
        }
        
        themes = []
        
        undoManager.removeAllActions()
    }
    
    
    func applyTheme(_ theme: CursorLibrary) {
        guard let path = theme.fileURL?.path else { return }
        if applyThemeAtPath(path) {
            appliedTheme = theme
        }
    }
    
    func restoreTheme() {
        resetAllCursors(nil)
        appliedTheme = nil
    }
    
    
    func themes(withIdentifier identifier: String) -> Set<CursorLibrary> {
        Set(themes.filter { $0.identifier == identifier })
    }
    
    
    private func willSaveNotification(_ note: Notification) {
        guard let theme = note.object as? CursorLibrary else { return }
        let oldURL = theme.fileURL
        theme.fileURL = url(for: theme)
        
        if let oldURL, oldURL != theme.fileURL {
            do {
                try FileManager.default.removeItem(at: oldURL)
            } catch {
                NSLog("error removing cursor theme after rename: %@", error.localizedDescription)
            }
        }
    }
    
    
    func dumpCursors(progressBlock: @escaping (UInt, UInt) -> Bool) -> Bool {
        let path = NSTemporaryDirectory() + String(
            format: "%@ (%f).cursor",
            NSLocalizedString("MaCursor Dump", comment: "MaCursor dump cursor file name"),
            Date().timeIntervalSince1970
        )
        
        if dumpCursorsToFile(path, { current, total in
            return progressBlock(current, total)
        }) {
            DispatchQueue.main.async { [weak self] in
                self?.importTheme(at: URL(fileURLWithPath: path))
            }
            return true
        }
        
        return false
    }
}
