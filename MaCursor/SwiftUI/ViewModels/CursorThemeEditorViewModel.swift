import Foundation
import Observation

@Observable
class CursorThemeEditorViewModel {
    let cursorTheme: CursorThemeModel
    
    
    var editingName: String
    var editingAuthor: String
    var editingVersion: Double
    var editingHiDPI: Bool
    var editingCursors: [CursorModel]
    
    var selectedCursorId: String?
    var isShowingUnsavedAlert = false
    
    var isDirty: Bool = false
    
    private var pendingAdditions: [MCCursorSwift] = []
    private var pendingRemovals: [MCCursorSwift] = []
    
    init(cursorTheme: CursorThemeModel) {
        self.cursorTheme = cursorTheme
        self.editingName = cursorTheme.name
        self.editingAuthor = cursorTheme.author
        self.editingVersion = cursorTheme.version
        self.editingHiDPI = cursorTheme.isHiDPI
        self.editingCursors = cursorTheme.cursors
    }
    
    var selectedCursor: CursorModel? {
        guard let id = selectedCursorId else { return nil }
        return editingCursors.first { $0.id == id }
    }
    
    func markDirty() {
        isDirty = true
    }
    
    
    func save() -> Error? {
        for cursorModel in editingCursors {
            cursorModel.syncToBacking()
        }
        
        for cursorModel in editingCursors {
            let backingId = cursorModel.backingCursor.identifier
            if backingId == nil || backingId!.isEmpty {
                let uniqueId = "Unassigned.\(UUID().uuidString)"
                cursorModel.backingCursor.identifier = uniqueId
                cursorModel.identifier = uniqueId
            }
        }
        
        cursorTheme.name = editingName
        cursorTheme.author = editingAuthor
        cursorTheme.version = editingVersion
        cursorTheme.isHiDPI = editingHiDPI
        cursorTheme.cursors = editingCursors
        
        for cursor in pendingAdditions {
            cursorTheme.backingLibrary.addCursor(cursor)
        }
        pendingAdditions.removeAll()
        
        for cursor in pendingRemovals {
            cursorTheme.backingLibrary.removeCursor(cursor)
        }
        pendingRemovals.removeAll()
        
        let error = cursorTheme.save()
        if error == nil {
            isDirty = false
            
            if cursorTheme.isApplied {
                CursorService.applyTheme(from: cursorTheme.backingLibrary)
            }
        }
        return error
    }
    
    func revertToSaved() {
        pendingAdditions.removeAll()
        pendingRemovals.removeAll()
        
        editingName = cursorTheme.name
        editingAuthor = cursorTheme.author
        editingVersion = cursorTheme.version
        editingHiDPI = cursorTheme.isHiDPI
        editingCursors = cursorTheme.cursors
        
        isDirty = false
    }
    
    func addCursor() {
        let newCursor = MCCursorSwift()
        pendingAdditions.append(newCursor)
        let model = CursorModel(from: newCursor, parentIdentifier: cursorTheme.backingLibrary.identifier)
        editingCursors.append(model)
        editingCursors.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        markDirty()
    }
    
    func removeCursor(_ cursor: CursorModel) {
        if selectedCursorId == cursor.id {
            selectedCursorId = nil
        }
        if let idx = pendingAdditions.firstIndex(where: { $0 === cursor.backingCursor }) {
            pendingAdditions.remove(at: idx)
        } else {
            pendingRemovals.append(cursor.backingCursor)
        }
        editingCursors.removeAll { $0.id == cursor.id }
        markDirty()
    }
    
    func duplicateCursor(_ cursor: CursorModel) {
        if let copy = cursor.backingCursor.copy() as? MCCursorSwift {
            copy.identifier = UUID().uuidString.replacingOccurrences(of: "-", with: "")
            pendingAdditions.append(copy)
            let model = CursorModel(from: copy, parentIdentifier: cursorTheme.backingLibrary.identifier)
            editingCursors.append(model)
            editingCursors.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            markDirty()
        }
    }
    
    func importWindowsCursors(from urls: [URL]) {
        for url in urls {
            do {
                let cursor = try WindowsCursorImporter.importFile(from: url)
                pendingAdditions.append(cursor)
                let model = CursorModel(from: cursor, parentIdentifier: cursorTheme.backingLibrary.identifier)
                editingCursors.append(model)
            } catch {
                NSLog("CursorThemeEditorViewModel: Failed to import \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        editingCursors.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if !urls.isEmpty { markDirty() }
    }
}
