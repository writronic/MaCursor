import Foundation
import AppKit
import UniformTypeIdentifiers
import Observation

@MainActor
@Observable
class LibraryViewModel {
    var cursorThemes: [CursorThemeModel] = []
    var appliedThemeId: String?
    
    private let backingController: LibraryController
    private nonisolated(unsafe) var didSaveObserver: Any?
    private nonisolated(unsafe) var identifierChangeObserver: Any?
    
    init() {
        let cursorsPath = (try? FileManager.default.findOrCreateDirectory(
            .applicationSupportDirectory,
            in: .userDomainMask,
            appendPathComponent: "MaCursor/cursors"
        )) ?? ""
        
        backingController = LibraryController(url: URL(fileURLWithPath: cursorsPath))
        reload()
        
        didSaveObserver = NotificationCenter.default.addObserver(
            forName: .cursorLibraryDidSave,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reload()
            }
        }
        
        identifierChangeObserver = NotificationCenter.default.addObserver(
            forName: .cursorLibraryIdentifierDidChange,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let oldId = note.userInfo?["oldId"] as? String
            let newId = note.userInfo?["newId"] as? String
            MainActor.assumeIsolated {
                guard let oldId, let newId else { return }
                if self?.appliedThemeId == oldId {
                    self?.appliedThemeId = newId
                }
            }
        }
    }
    
    deinit {
        if let observer = didSaveObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = identifierChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    
    func reload() {
        let appliedId = backingController.appliedTheme?.identifier
        
        var existingByIdentity: [ObjectIdentifier: CursorThemeModel] = [:]
        for model in cursorThemes {
            existingByIdentity[ObjectIdentifier(model.backingLibrary)] = model
        }
        
        cursorThemes = backingController.themes
            .map { lib -> CursorThemeModel in
                let key = ObjectIdentifier(lib)
                if let existing = existingByIdentity[key] {
                    existing.refreshFromObjC()
                    existing.isApplied = (lib.identifier == appliedId)
                    return existing
                } else {
                    let model = CursorThemeModel(from: lib)
                    model.isApplied = (lib.identifier == appliedId)
                    return model
                }
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        
        appliedThemeId = appliedId
    }
    
    
    func theme(withId id: String?) -> CursorThemeModel? {
        guard let id else { return nil }
        return cursorThemes.first { $0.id == id }
    }
    
    
    func apply(_ cursorTheme: CursorThemeModel) {
        let success = CursorService.applyTheme(from: cursorTheme.backingLibrary)
        guard success else { return }
        
        backingController.appliedTheme = cursorTheme.backingLibrary
        
        for c in cursorThemes {
            c.isApplied = (c.id == cursorTheme.id)
        }
        appliedThemeId = cursorTheme.id
    }
    
    func restoreCursors() {
        backingController.restoreTheme()
        for c in cursorThemes {
            c.isApplied = false
        }
        appliedThemeId = nil
    }
    
    @discardableResult
    func addNewTheme() -> String {
        let newLib = CursorLibrary()
        backingController.importTheme(newLib)
        reload()
        return newLib.identifier
    }
    
    func remove(_ cursorTheme: CursorThemeModel) {
        backingController.removeTheme(cursorTheme.backingLibrary)
        cursorThemes.removeAll { $0.id == cursorTheme.id }
        if appliedThemeId == cursorTheme.id {
            appliedThemeId = nil
        }
    }
    
    func removeAllThemes() {
        backingController.removeAllThemes()
        cursorThemes = []
        appliedThemeId = nil
    }
    
    @discardableResult
    func duplicateTheme(_ cursorTheme: CursorThemeModel) -> String? {
        if let copy = cursorTheme.backingLibrary.copy() as? CursorLibrary {
            backingController.importTheme(copy)
            reload()
            return copy.identifier
        }
        return nil
    }
    
    func importTheme(at url: URL) {
        backingController.importTheme(at: url)
        reload()
    }
    
    
    func showImportPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: "cursor")
        ].compactMap { $0 }
        panel.allowsMultipleSelection = true
        panel.title = NSLocalizedString("Import", comment: "MaCursor Import Title")
        panel.message = NSLocalizedString("Choose cursor theme files to import (.cursor)", comment: "MaCursor Import description")
        panel.prompt = NSLocalizedString("Import", comment: "MaCursor Import Prompt")
        
        if panel.runModal() == .OK {
            for url in panel.urls where url.pathExtension.lowercased() == "cursor" {
                importTheme(at: url)
            }
        }
    }
    
    
    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let _ = Task { @MainActor [weak self] in
            for provider in providers {
                if let item = try? await provider.loadItem(forTypeIdentifier: "public.file-url", options: nil),
                   let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    
                    if url.pathExtension.lowercased() == "cursor" {
                        self?.importTheme(at: url)
                    }
                }
            }
        }
        return true
    }
    
    
    nonisolated func dumpCursors(progress: @Sendable @escaping (UInt, UInt) -> Bool, completion: @MainActor @Sendable @escaping () -> Void) {
        DispatchQueue.global(qos: .background).async { [backingController] in
            let _ = backingController.dumpCursors { current, total in
                return progress(current, total)
            }
            DispatchQueue.main.async {
                completion()
            }
        }
    }
}
