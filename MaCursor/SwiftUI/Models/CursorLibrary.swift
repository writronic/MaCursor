import Foundation

extension Notification.Name {
    static let cursorLibraryWillSave = Notification.Name("MCLibraryWillSave")
    static let cursorLibraryDidSave  = Notification.Name("MCLibraryDidSave")
    static let cursorLibraryIdentifierDidChange = Notification.Name("MCLibraryIdentifierDidChange")
}

class CursorLibrary: NSObject, NSCopying, @unchecked Sendable {
    
    
    var name: String {
        didSet {
            guard name != oldValue else { return }
            let previous = oldValue
            undoManager.registerUndo(withTarget: self) { target in
                target.name = previous
            }
            if !undoManager.isUndoing {
                undoManager.setActionName(NSLocalizedString("Change Name", comment: "Undo change cursor theme name"))
            }
        }
    }
    
    var author: String {
        didSet {
            guard author != oldValue else { return }
            let previous = oldValue
            undoManager.registerUndo(withTarget: self) { target in
                target.author = previous
            }
            if !undoManager.isUndoing {
                undoManager.setActionName(NSLocalizedString("Change Author", comment: "Undo change cursor theme author"))
            }
        }
    }
    
    var identifier: String {
        didSet {
            guard identifier != oldValue else { return }
            oldIdentifier = oldValue
            let previous = oldValue
            undoManager.registerUndo(withTarget: self) { target in
                target.identifier = previous
            }
            if !undoManager.isUndoing {
                undoManager.setActionName(NSLocalizedString("Change Identifier", comment: "Undo change cursor theme identifier"))
            }
        }
    }
    
    var version: NSNumber {
        didSet {
            guard version != oldValue else { return }
            let previous = oldValue
            undoManager.registerUndo(withTarget: self) { target in
                target.version = previous
            }
            if !undoManager.isUndoing {
                undoManager.setActionName(NSLocalizedString("Change Version", comment: "Undo change cursor theme version"))
            }
        }
    }
    
    var fileURL: URL?
    
    weak var library: LibraryController?
    
    var isInCloud: Bool = false
    
    var isHiDPI: Bool {
        didSet {
            guard isHiDPI != oldValue else { return }
            let previous = oldValue
            undoManager.registerUndo(withTarget: self) { target in
                target.isHiDPI = previous
            }
            if !undoManager.isUndoing {
                undoManager.setActionName(NSLocalizedString("Change HiDPI", comment: "Undo change cursor theme hidpi"))
            }
        }
    }
    
    
    private(set) var cursors: Set<MCCursorSwift> = []
    
    
    let undoManager: UndoManager
    
    
    private var changeCount: Int = 0
    private var lastChangeCount: Int = 0
    
    var isDirty: Bool {
        changeCount != lastChangeCount
    }
    
    private(set) var oldIdentifier: String?
    
    
    private var undoObservers: [Any] = []
    
    
    private static let cursorUndoProperties: [String: String] = [
        "identifier":    NSLocalizedString("cursor type", comment: "Undo change cursor type suffix"),
        "frameDuration": NSLocalizedString("frame duration", comment: "Undo change cursor frame duration suffix"),
        "frameCount":    NSLocalizedString("frame count", comment: "Undo change cursor frame count suffix"),
        "size":          NSLocalizedString("dimensions", comment: "Undo change cursor image dimensions suffix"),
        "hotSpot":       NSLocalizedString("hotspot", comment: "Undo change cursor hotspot suffix"),
    ]
    
    
    static func sanitizeName(_ name: String) -> String {
        let sanitized = name
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "/", with: "")
            .replacingOccurrences(of: ":", with: "")
        return sanitized.isEmpty ? "Unnamed" : sanitized
    }
    
    static func generateIdentifier(from name: String) -> String {
        let base = sanitizeName(name)
        return "\(base).\(UUID().uuidString)"
    }
    
    static func updateIdentifier(_ existingId: String, newName: String) -> String {
        let sanitized = sanitizeName(newName)
        if let dotIndex = existingId.firstIndex(of: ".") {
            let uuidPart = existingId[dotIndex...]
            return sanitized + uuidPart
        }
        return "\(sanitized).\(UUID().uuidString)"
    }
    
    
    override init() {
        let um = UndoManager()
        self.undoManager = um
        self.name = NSLocalizedString("Unnamed", comment: "Default New Cursor Theme Name")
        self.author = NSUserName()
        self.isHiDPI = false
        self.isInCloud = false
        self.identifier = CursorLibrary.generateIdentifier(from: "Unnamed")
        self.version = NSNumber(value: 1.0)
        
        super.init()
        
        setupUndoObservers()
    }
    
    
    convenience init?(contentsOfFile path: String) {
        self.init(contentsOfURL: URL(fileURLWithPath: path))
    }
    
    convenience init?(contentsOfURL url: URL) {
        guard let dict = NSDictionary(contentsOf: url) as? [String: Any] else { return nil }
        self.init(dictionary: dict)
        self.fileURL = url
    }
    
    convenience init?(dictionary: [String: Any]) {
        self.init()
        if !readFromDictionary(dictionary) {
            return nil
        }
    }
    
    convenience init(cursors: Set<MCCursorSwift>) {
        self.init()
        self.cursors = cursors
    }
    
    deinit {
        for observer in undoObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    
    private func setupUndoObservers() {
        let center = NotificationCenter.default
        
        let ob1 = center.addObserver(forName: .NSUndoManagerDidCloseUndoGroup, object: undoManager, queue: nil) { [weak self] _ in
            self?.updateChangeCount(.changeDone)
        }
        let ob2 = center.addObserver(forName: .NSUndoManagerDidUndoChange, object: undoManager, queue: nil) { [weak self] _ in
            self?.updateChangeCount(.changeUndone)
        }
        let ob3 = center.addObserver(forName: .NSUndoManagerDidRedoChange, object: undoManager, queue: nil) { [weak self] _ in
            self?.updateChangeCount(.changeRedone)
        }
        
        undoObservers = [ob1, ob2, ob3]
    }
    
    
    private func readFromDictionary(_ dictionary: [String: Any]) -> Bool {
        guard !dictionary.isEmpty else {
            NSLog("cannot make library from empty dictionary")
            return false
        }
        
        cursors = []
        undoManager.disableUndoRegistration()
        defer { undoManager.enableUndoRegistration() }
        
        let minimumVersion = dictionary[MCConstants.minimumVersionKey] as? NSNumber
        let versionNum     = dictionary[MCConstants.versionKey] as? NSNumber
        let cursorDicts    = dictionary[MCConstants.cursorsKey] as? [String: Any]
        let cloud          = dictionary[MCConstants.cloudKey] as? NSNumber
        let authorStr      = dictionary[MCConstants.authorKey] as? String
        let hiDPINum       = dictionary[MCConstants.hiDPIKey] as? NSNumber
        let identifierStr  = dictionary[MCConstants.identifierKey] as? String
        let themeName      = dictionary[MCConstants.themeNameKey] as? String
        let themeVersion   = dictionary[MCConstants.themeVersionKey] as? NSNumber
        
        self.name       = themeName ?? ""
        self.version    = themeVersion ?? NSNumber(value: 1.0)
        self.author     = authorStr ?? ""
        self.identifier = identifierStr ?? ""
        self.isHiDPI    = hiDPINum?.boolValue ?? false
        self.isInCloud  = cloud?.boolValue ?? false
        
        guard !self.identifier.isEmpty else {
            NSLog("cannot make library from dictionary with no identifier")
            return false
        }
        
        let doubleVersion = versionNum?.doubleValue ?? 0
        
        if let minVer = minimumVersion?.doubleValue, minVer > MCCursorParserVersion {
            return false
        }
        
        if let cursorDicts {
            addCursors(from: cursorDicts, ofVersion: CGFloat(doubleVersion))
        }
        
        return true
    }
    
    private func addCursors(from cursorDicts: [String: Any], ofVersion version: CGFloat) {
        for (key, value) in cursorDicts {
            guard let cursorDict = value as? [AnyHashable: Any] else { continue }
            guard let cursor = MCCursorSwift(cursorDictionary: cursorDict, ofVersion: version) else { continue }
            cursor.identifier = key
            addCursor(cursor)
        }
    }
    
    func dictionaryRepresentation() -> [String: Any] {
        var drep = [String: Any]()
        
        drep[MCConstants.minimumVersionKey] = NSNumber(value: 2.0)
        drep[MCConstants.versionKey]        = NSNumber(value: 2.0)
        drep[MCConstants.themeNameKey]      = name
        drep[MCConstants.themeVersionKey]   = version
        drep[MCConstants.cloudKey]          = NSNumber(value: isInCloud)
        drep[MCConstants.authorKey]         = author
        drep[MCConstants.hiDPIKey]          = NSNumber(value: isHiDPI)
        drep[MCConstants.identifierKey]     = identifier
        
        var cursorsDict = [String: Any]()
        for cursor in cursors {
            if let id = cursor.identifier {
                cursorsDict[id] = cursor.dictionaryRepresentation() as Any
            }
        }
        
        drep[MCConstants.cursorsKey] = cursorsDict
        
        return drep
    }
    
    
    func cursors(withIdentifier identifier: String) -> Set<MCCursorSwift> {
        Set(cursors.filter { $0.identifier == identifier })
    }
    
    func addCursor(_ cursor: MCCursorSwift) {
        guard !cursors.contains(cursor) else { return }
        
        undoManager.registerUndo(withTarget: self) { target in
            target.removeCursor(cursor)
        }
        if !undoManager.isUndoing {
            undoManager.setActionName(NSLocalizedString("Add Cursor", comment: "Add Cursor Undo Title"))
        }
        
        cursors.insert(cursor)
    }
    
    func removeCursor(_ cursor: MCCursorSwift) {
        undoManager.registerUndo(withTarget: self) { target in
            target.addCursor(cursor)
        }
        if !undoManager.isUndoing {
            undoManager.setActionName(NSLocalizedString("Remove Cursor", comment: "Remove Cursor Undo Title"))
        }
        
        cursors.remove(cursor)
    }
    
    func removeCursors(withIdentifier identifier: String) {
        for cursor in cursors(withIdentifier: identifier) {
            removeCursor(cursor)
        }
    }
    
    
    @discardableResult
    func write(toFile path: String, atomically: Bool) -> Bool {
        let dict = dictionaryRepresentation() as NSDictionary
        return dict.write(toFile: path, atomically: atomically)
    }
    
    func save() -> Error? {
        let identifiers = cursors.compactMap { $0.identifier }.filter { !$0.isEmpty }
        let counted = NSCountedSet(array: identifiers)
        var duplicates = Set<String>()
        
        for case let identifier as String in counted {
            if counted.count(for: identifier) > 1 {
                duplicates.insert(MCConstants.nameForIdentifier(identifier))
            }
        }
        
        if !duplicates.isEmpty {
            return NSError(
                domain: MCConstants.errorDomain,
                code: MCConstants.ErrorCode.multipleCursorIdentifiers.rawValue,
                userInfo: [
                    NSLocalizedDescriptionKey: NSLocalizedString("Save failed", comment: "New Cursor Theme Failure Title"),
                    NSLocalizedFailureReasonErrorKey: String(format: NSLocalizedString("Multiple cursors with the name(s): %@ exist.", comment: "New Cursor Theme Failure Duplicate cursor name error"), duplicates)
                ]
            )
        }
        
        NotificationCenter.default.post(name: .cursorLibraryWillSave, object: self)
        
        guard let path = fileURL?.path else {
            return NSError(
                domain: MCConstants.errorDomain,
                code: MCConstants.ErrorCode.writeFail.rawValue,
                userInfo: [
                    NSLocalizedDescriptionKey: NSLocalizedString("Save failed", comment: "New Cursor Theme Failure Title"),
                    NSLocalizedFailureReasonErrorKey: NSLocalizedString("No file URL set.", comment: "No file URL error")
                ]
            )
        }
        
        if write(toFile: path, atomically: true) {
            updateChangeCount(.changeCleared)
            NotificationCenter.default.post(name: .cursorLibraryDidSave, object: self)
            return nil
        }
        
        return NSError(
            domain: MCConstants.errorDomain,
            code: MCConstants.ErrorCode.writeFail.rawValue,
            userInfo: [
                NSLocalizedDescriptionKey: NSLocalizedString("Save failed", comment: "New Cursor Theme Failure Title"),
                NSLocalizedFailureReasonErrorKey: NSLocalizedString("Error writing cursor theme to disk.", comment: "New Cursor Theme Failure Filesystem Error")
            ]
        )
    }
    
    
    func updateChangeCount(_ change: NSDocument.ChangeType) {
        switch change {
        case .changeDone, .changeRedone:
            changeCount += 1
        case .changeUndone:
            if changeCount > 0 { changeCount -= 1 }
        case .changeCleared, .changeAutosaved:
            lastChangeCount = changeCount
        @unknown default:
            break
        }
    }
    
    func revertToSaved() {
        while isDirty {
            undoManager.undo()
        }
        updateChangeCount(.changeCleared)
        undoManager.removeAllActions()
    }
    
    
    func copy(with zone: NSZone? = nil) -> Any {
        let copy = CursorLibrary(cursors: cursors)
        copy.undoManager.disableUndoRegistration()
        copy.name = name
        copy.author = author
        copy.isHiDPI = isHiDPI
        copy.isInCloud = isInCloud
        copy.version = version
        copy.identifier = CursorLibrary.generateIdentifier(from: name)
        copy.undoManager.enableUndoRegistration()
        return copy
    }
    
    
    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? CursorLibrary else { return false }
        return name == other.name
            && author == other.author
            && identifier == other.identifier
            && version == other.version
            && isInCloud == other.isInCloud
            && isHiDPI == other.isHiDPI
            && cursors == other.cursors
    }
    
    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(identifier)
        return hasher.finalize()
    }
}
