import Foundation
import AppKit
import UniformTypeIdentifiers
import Combine

@MainActor
class LibraryViewModel: ObservableObject {
    @Published var cursorThemes: [CursorThemeModel] = []
    @Published var appliedThemeId: String?
    @Published var favoriteThemeIds = Set(MACMenuBarFavoriteThemeIdentifiers(MACPreferences.value(forKey: MACPreferences.favoriteThemesKey)))
    let conversion = ThemeConversionCoordinator()

    private let backingController: LibraryController
    private var conversionForwarder: AnyCancellable?
    private nonisolated(unsafe) var didSaveObserver: Any?
    private nonisolated(unsafe) var identifierChangeObserver: Any?
    private nonisolated(unsafe) var autoSwitchObserver: Any?

    init(libraryDirectory: URL? = nil) {
        let cursorsPath = (try? FileManager.default.findOrCreateDirectory(
            .applicationSupportDirectory,
            in: .userDomainMask,
            appendPathComponent: "MaCursor/cursors"
        )) ?? ""

        backingController = LibraryController(url: libraryDirectory ?? URL(fileURLWithPath: cursorsPath))
        reload()

        conversionForwarder = conversion.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }

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
                if let self, self.favoriteThemeIds.remove(oldId) != nil {
                    self.favoriteThemeIds.insert(newId)
                    self.saveFavorites()
                }
            }
        }

        autoSwitchObserver = DistributedNotificationCenter.default().addObserver(
            forName: .MACAutoSwitchAppliedThemeDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.syncAppliedThemeFromPreferences()
            }
        }
    }

    private func syncAppliedThemeFromPreferences() {
        let storedId = MACPreferences.value(forKey: MACPreferences.appliedCursorKey) as? String
        if let storedId, !storedId.isEmpty {
            backingController.appliedTheme = backingController.themes.first { $0.identifier == storedId }
        } else {
            backingController.appliedTheme = nil
        }
        reload()
    }

    deinit {
        if let observer = didSaveObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = identifierChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = autoSwitchObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
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

    func isFavorite(_ cursorTheme: CursorThemeModel) -> Bool {
        favoriteThemeIds.contains(cursorTheme.id)
    }

    func toggleFavorite(_ cursorTheme: CursorThemeModel) {
        if favoriteThemeIds.remove(cursorTheme.id) == nil {
            favoriteThemeIds.insert(cursorTheme.id)
        }
        saveFavorites()
    }

    private func saveFavorites() {
        MACPreferences.set(favoriteThemeIds.isEmpty ? nil : favoriteThemeIds.sorted() as NSArray,
                           forKey: MACPreferences.favoriteThemesKey)
    }


    func apply(_ cursorTheme: CursorThemeModel) {
        let success = CursorService.applyTheme(from: cursorTheme.backingLibrary)
        guard success else { return }

        MACAutoSwitchClearAppOverride()
        backingController.appliedTheme = cursorTheme.backingLibrary

        for c in cursorThemes {
            c.isApplied = (c.id == cursorTheme.id)
        }
        appliedThemeId = cursorTheme.id
    }

    func restoreCursors() {
        MACPreferences.set(NSNumber(value: 1.0), forKey: MACPreferences.cursorScaleKey)
        MACPreferences.setFlag(false, forKey: MACPreferences.handednessKey)
        MACPreferences.setFlag(false, forKey: MACPreferences.cursorShadowKey)
        CursorService.setScale(1.0)
        MACAutoSwitchClearAppOverride()
        backingController.restoreTheme()
        for c in cursorThemes {
            c.isApplied = false
        }
        appliedThemeId = nil
        NotificationCenter.default.post(name: .cursorSettingsDidReset, object: nil)
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
        if favoriteThemeIds.remove(cursorTheme.id) != nil {
            saveFavorites()
        }
    }

    func removeAllThemes() {
        backingController.removeAllThemes()
        cursorThemes = []
        appliedThemeId = nil
        favoriteThemeIds = []
        saveFavorites()
    }

    @discardableResult
    func duplicateTheme(_ cursorTheme: CursorThemeModel) -> String? {
        guard let copy = cursorTheme.backingLibrary.copy() as? CursorLibrary else { return nil }

        let baseName = cursorTheme.name
        let existingNames = Set(cursorThemes.map { $0.name })
        var suffix = 2
        var candidateName = "\(baseName)-\(suffix)"
        while existingNames.contains(candidateName) {
            suffix += 1
            candidateName = "\(baseName)-\(suffix)"
        }
        copy.undoManager.disableUndoRegistration()
        copy.name = candidateName
        copy.identifier = CursorLibrary.updateIdentifier(copy.identifier, newName: candidateName)
        copy.undoManager.enableUndoRegistration()

        backingController.importTheme(copy)
        reload()
        return copy.identifier
    }

    func importTheme(at url: URL) {
        backingController.importTheme(at: url)
        reload()
    }

    @discardableResult
    func importThemeReturningId(at url: URL) -> String? {
        let existing = Set(cursorThemes.map(\.id))
        importTheme(at: url)
        guard let landed = cursorThemes.first(where: { !existing.contains($0.id) }),
              let fileURL = landed.fileURL,
              FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return landed.id
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

    func showConvertPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = NSLocalizedString("Convert Theme", comment: "Convert theme panel title")
        panel.message = NSLocalizedString("Choose a Mousecape .cape file, a Windows cursor folder (.cur/.ani), or a Linux Xcursor theme folder.", comment: "Convert theme panel message")
        panel.prompt = NSLocalizedString("Convert", comment: "Convert theme prompt")

        let filter = ConvertPanelFilter()
        panel.delegate = filter

        let response = withExtendedLifetime(filter) { panel.runModal() }
        if response == .OK, let url = panel.url {
            Task { await conversion.convert(url) }
        }
    }


    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let _ = Task { @MainActor [weak self] in
            guard let self else { return }
            for provider in providers {
                if let item = try? await provider.loadItem(forTypeIdentifier: "public.file-url", options: nil),
                   let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {

                    if url.pathExtension.lowercased() == "cursor" {
                        self.importTheme(at: url)
                    } else {
                        await self.conversion.convert(url)
                        break
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

extension LibraryViewModel: ThemeLibraryLanding {}
