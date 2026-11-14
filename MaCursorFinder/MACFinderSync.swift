import FinderSync

final class MACFinderSync: FIFinderSync, RightClickMenuActionTarget {
    private var menuSettings = RightClickMenuSettings()
    private var menuContext = RightClickMenuContext.items

    override init() {
        super.init()
        refreshScope()
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(refreshScope), name: name, object: nil)
        }
    }

    @objc private func refreshScope() {
        FIFinderSyncController.default().directoryURLs = RightClickMenuScope.directoryURLs(
            mountedVolumes: FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]))
    }

    private var targetFolder: URL? { RightClickMenuActions.usableFolder(FIFinderSyncController.default().targetedURL()) }

    override var toolbarItemName: String { "MaCursor" }

    override var toolbarItemToolTip: String { "MaCursor" }

    override var toolbarItemImage: NSImage { RightClickMenuActions.symbolIcon("contextualmenu.and.cursorarrow") ?? NSImage() }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let context: RightClickMenuContext
        switch menuKind {
        case .contextualMenuForItems: context = .items
        case .contextualMenuForContainer: context = .container
        case .toolbarItemMenu: context = .container
        default: return nil
        }
        let settings = RightClickMenuSettings.load()
        let applications = RightClickMenuActions.resolvedApplications(settings: settings)
        menuSettings = settings
        menuContext = context
        let folder = targetFolder
        let place = RightClickMenuActions.place(context: context, target: folder,
                                                selectedItems: context == .items ? FIFinderSyncController.default().selectedItemURLs() ?? [] : [])
        if menuKind == .toolbarItemMenu {
            let helperIsRunning = folder == nil && !NSRunningApplication.runningApplications(withBundleIdentifier: RightClickMenuHandoff.helperBundleIdentifier).isEmpty
            return RightClickMenuActions.toolbarMenu(settings: settings, targetedURL: folder, helperIsRunning: helperIsRunning, target: self, applications: applications, place: place)
        }
        return RightClickMenuActions.menu(settings: settings, context: context, target: self, applications: applications, place: place)
    }

    @objc func openApplication(_ sender: NSMenuItem) {
        RightClickMenuActions.openApplication(
            tag: sender.tag, context: menuContext, shown: menuSettings, latest: RightClickMenuSettings.load(),
            target: targetFolder,
            selectedItems: menuContext == .items ? FIFinderSyncController.default().selectedItemURLs() ?? [] : []
        )
    }

    @objc func copySelectedPaths() {
        RightClickMenuActions.copyPaths(FIFinderSyncController.default().selectedItemURLs() ?? [])
    }

    @objc func copyFolderPath() {
        guard let url = targetFolder else { return RightClickMenuHandoff.post(.copyPath) }
        RightClickMenuActions.copyPaths([url])
    }

    @objc func newFile(_ sender: NSMenuItem) {
        let files = menuSettings.files
        guard files.indices.contains(sender.tag) else { return }
        guard menuContext == .items || targetFolder != nil else { return RightClickMenuHandoff.post(.newFile(sender.tag)) }
        createFile(context: menuContext, baseName: files[sender.tag].baseName, ext: files[sender.tag].fileExtension)
    }

    @objc func hideSelectedFiles() {
        changeVisibility(hidden: true, context: .items)
    }

    @objc func unhideSelectedFiles() {
        changeVisibility(hidden: false, context: .items)
    }

    @objc func hideAllFilesInPath() {
        changeVisibility(hidden: true, context: .container)
    }

    @objc func unhideAllFilesInPath() {
        changeVisibility(hidden: false, context: .container)
    }

    private func changeVisibility(hidden: Bool, context: RightClickMenuContext) {
        let result = RightClickMenuActions.changeVisibility(
            hidden: hidden, context: context, target: targetFolder,
            selectedItems: context == .items ? FIFinderSyncController.default().selectedItemURLs() ?? [] : []
        )
        RightClickMenuActions.reportVisibilityFailures(result)
    }

    private func createFile(context: RightClickMenuContext, baseName: String, ext: String) {
        do {
            guard let directory = RightClickMenuActions.creationDirectory(
                context: context, target: targetFolder,
                selectedItems: context == .items ? FIFinderSyncController.default().selectedItemURLs() ?? [] : []
            ) else {
                throw CocoaError(.fileNoSuchFile)
            }
            let url = try RightClickMenuActions.createFile(in: directory, baseName: baseName, ext: ext) {
                try Data().write(to: $0, options: .withoutOverwriting)
            }
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            NSSound.beep()
            NSLog("MaCursor: New File failed (%ld)", (error as NSError).code)
        }
    }
}
