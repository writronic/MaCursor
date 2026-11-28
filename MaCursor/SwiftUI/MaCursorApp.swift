import SwiftUI
import Sparkle

@main
struct MaCursorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var library = LibraryViewModel()
    @StateObject private var appearanceManager = AppearanceManager()
    @StateObject private var languageManager = LanguageManager()
    @Environment(\.openWindow) private var openWindow

    private let updaterController: SPUStandardUpdaterController

    init() {
        MACForceOverlayScrollers()
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var body: some Scene {
        WindowGroup("MaCursor") {
            MainWindowView(updater: updaterController.updater)
                .background(MainWindowHoldAccessor { WelcomeWindowController.shared.presentAtLaunchIfNeeded(library: library) })
                .environmentObject(library)
                .environmentObject(appearanceManager)
                .environmentObject(languageManager)
                .onAppear {
                    configureSettingsFiles()
                    appearanceManager.applyOnLaunch()

                    appDelegate.isViewReady = true

                    let pendingURLs = appDelegate.consumePendingImports()
                    for url in pendingURLs {
                        openFile(url)
                    }

                    drainPendingSettingsRequest()
                }
                .onReceive(DistributedNotificationCenter.default().publisher(
                    for: .MACOpenSettingsRequested)) { _ in
                    openRequestedSettings()
                }
                .onReceive(NotificationCenter.default.publisher(for: .macursorImportFile)) { notification in
                    if let url = notification.userInfo?["url"] as? URL {
                        openFile(url)
                    }
                }
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        }
        .handlesExternalEvents(matching: [])
        .defaultSize(MainWindowLayout.defaultSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About MaCursor") {
                    openWindow(id: "about")
                }
            }

            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }

            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    openMainPage(.settings, tab: 0)
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandGroup(replacing: .newItem) {
                LibraryFileCommands(library: library)
            }

            CommandGroup(replacing: .pasteboard) { }

            CommandGroup(before: .textEditing) {
                LibraryFindCommand()
            }

            CommandGroup(before: .toolbar) { MainWindowBackCommand() }

            CommandGroup(replacing: .help) {
                Button("MaCursor Help") {
                    if let url = URL(string: "https://github.com/writronic/MaCursor") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .keyboardShortcut("/", modifiers: .command)
            }
        }

        Window("About MaCursor", id: "about") {
            if #available(macOS 15, *) {
                AboutWindowView()
                    .windowMinimizeBehavior(.disabled)
                    .windowResizeBehavior(.disabled)
            } else {
                AboutWindowView()
            }
        }
        .windowResizability(.contentSize)
        .handlesExternalEvents(matching: [])
        .commandsRemoved()
    }
}

private extension MaCursorApp {
    func openMainPage(_ page: MainPage, tab: Int? = nil) {
        AboutWindowView.window?.close()
        ModalWindowCoordinator.shared.runIfMainWindowIsUsable {
            guard MainWindowRouter.shared.open(page, tab: tab) else { return }
            guard !ModalWindowCoordinator.shared.holdsMainWindow else { return }
            ModalWindowCoordinator.shared.resolvedMainWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func configureSettingsFiles() {
        SettingsFileWindowController.shared.effects = .app(library: library, appearanceManager: appearanceManager,
                                                           updater: updaterController.updater)
        SettingsFileWindowController.shared.library = library
    }

    func openFile(_ url: URL) {
        guard url.pathExtension.lowercased() == "macursor" else {
            library.importTheme(at: url)
            return
        }
        configureSettingsFiles()
        SettingsFileWindowController.shared.presentImport(url)
    }

    func openRequestedSettings() {
        guard let request = MainPage.takePendingSettingsRequest() else { return }
        openMainPage(request.page, tab: request.tab)
    }

    func drainPendingSettingsRequest() {
        guard MACPreferences.flag(MACPreferences.pendingOpenSettingsKey) else { return }
        openRequestedSettings()
    }
}

private struct LibraryFileCommands: View {
    let library: LibraryViewModel

    @ObservedObject private var coordinator = ModalWindowCoordinator.shared
    @ObservedObject private var router = MainWindowRouter.shared

    var body: some View {
        Button("New Theme") {
            coordinator.runIfMainWindowIsUsable {
                if let id = library.addNewTheme() {
                    MainWindowRouter.shared.selectedThemeId = id
                    MainWindowRouter.shared.open(.themes)
                }
            }
        }
        .keyboardShortcut("n")
        .disabled(coordinator.isMainWindowBlocked || router.editor != nil)

        Button("Import Theme...") {
            coordinator.runIfMainWindowIsUsable { library.showImportPanel() }
        }
        .keyboardShortcut("o")
        .disabled(coordinator.isMainWindowBlocked || router.editor != nil)

        Button("Convert Theme...") {
            coordinator.runIfMainWindowIsUsable { library.showConvertPanel() }
        }
        .keyboardShortcut("o", modifiers: [.command, .shift])
        .disabled(coordinator.isMainWindowBlocked || router.editor != nil)

        Button("Restore") { coordinator.runIfMainWindowIsUsable { library.restoreCursors() } }
            .disabled(coordinator.isMainWindowBlocked || router.editor != nil)
    }
}

private struct LibraryFindCommand: View {
    @FocusedValue(\.librarySearch) private var search

    @ObservedObject private var coordinator = ModalWindowCoordinator.shared
    @ObservedObject private var router = MainWindowRouter.shared

    var body: some View {
        Button("Search") {
            if router.page == .themes {
                search?()
            } else {
                MainWindowRouter.shared.focusSearch()
            }
        }
        .keyboardShortcut("f")
        .disabled(coordinator.isMainWindowBlocked || router.editor != nil || (router.page == .themes && search == nil))
    }
}
