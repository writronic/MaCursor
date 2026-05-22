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
    private var pendingRemovals: Set<String> = []
    private var originalMapping: [String: CursorModel] = [:]
    
    init(cursorTheme: CursorThemeModel) {
        self.cursorTheme = cursorTheme
        self.editingName = cursorTheme.name
        self.editingAuthor = cursorTheme.author
        self.editingVersion = cursorTheme.version
        self.editingHiDPI = cursorTheme.isHiDPI
        
        var copies: [CursorModel] = []
        var mapping: [String: CursorModel] = [:]
        for original in cursorTheme.cursors {
            guard let backingCopy = original.backingCursor.copy() as? MCCursorSwift else { continue }
            let copy = CursorModel(from: backingCopy, parentIdentifier: cursorTheme.backingLibrary.identifier)
            copies.append(copy)
            mapping[copy.id] = original
        }
        self.editingCursors = copies
        self.originalMapping = mapping
    }
    
    var selectedCursor: CursorModel? {
        guard let id = selectedCursorId else { return nil }
        return editingCursors.first { $0.id == id }
    }
    
    var visibleEditingCursors: [CursorModel] {
        editingCursors.filter {
            !MCConstants.hiddenCursorAliases.contains($0.identifier)
        }
    }
    
    func markDirty() {
        isDirty = true
    }
    
    func usedIdentifiers(excluding cursorId: String) -> Set<String> {
        Set(editingCursors.compactMap { $0.id == cursorId ? nil : $0.identifier })
    }
    
    func save() -> Error? {
        for editingModel in editingCursors {
            editingModel.syncToBacking()
            
            if let original = originalMapping[editingModel.id] {
                original.identifier = editingModel.identifier
                original.frameCount = editingModel.frameCount
                original.frameDuration = editingModel.frameDuration
                original.hotSpot = editingModel.hotSpot
                original.size = editingModel.size
                
                original.backingCursor.identifier = editingModel.backingCursor.identifier
                original.backingCursor.frameCount = editingModel.backingCursor.frameCount
                original.backingCursor.frameDuration = editingModel.backingCursor.frameDuration
                original.backingCursor.hotSpot = editingModel.backingCursor.hotSpot
                original.backingCursor.size = editingModel.backingCursor.size
                if let reps = editingModel.backingCursor.representations as NSDictionary? {
                    original.backingCursor.setValue(reps.mutableCopy(), forKey: "representations")
                }
                original.representationRevision += 1
            }
        }
        
        for editingModel in editingCursors {
            let backingId = editingModel.backingCursor.identifier
            if backingId == nil || backingId!.isEmpty {
                let uniqueId = "Unassigned.\(UUID().uuidString)"
                editingModel.backingCursor.identifier = uniqueId
                editingModel.identifier = uniqueId
                if let original = originalMapping[editingModel.id] {
                    original.backingCursor.identifier = uniqueId
                    original.identifier = uniqueId
                }
            }
        }
        
        cursorTheme.name = editingName
        cursorTheme.author = editingAuthor
        cursorTheme.version = editingVersion
        cursorTheme.isHiDPI = editingHiDPI
        
        var finalCursors: [CursorModel] = []
        for editingModel in editingCursors {
            if let original = originalMapping[editingModel.id] {
                finalCursors.append(original)
            } else {
                finalCursors.append(editingModel)
            }
        }
        cursorTheme.cursors = finalCursors
        
        for cursor in pendingAdditions {
            cursorTheme.backingLibrary.addCursor(cursor)
        }
        pendingAdditions.removeAll()
        
        for originalId in pendingRemovals {
            if let original = cursorTheme.backingLibrary.cursors.first(where: { $0.identifier == originalId }) {
                cursorTheme.backingLibrary.removeCursor(original)
            }
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
        
        var copies: [CursorModel] = []
        var mapping: [String: CursorModel] = [:]
        for original in cursorTheme.cursors {
            guard let backingCopy = original.backingCursor.copy() as? MCCursorSwift else { continue }
            let copy = CursorModel(from: backingCopy, parentIdentifier: cursorTheme.backingLibrary.identifier)
            copies.append(copy)
            mapping[copy.id] = original
        }
        
        editingName = cursorTheme.name
        editingAuthor = cursorTheme.author
        editingVersion = cursorTheme.version
        editingHiDPI = cursorTheme.isHiDPI
        editingCursors = copies
        originalMapping = mapping
        
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
        } else if let original = originalMapping[cursor.id] {
            pendingRemovals.insert(original.backingCursor.identifier ?? "")
        }
        originalMapping.removeValue(forKey: cursor.id)
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
