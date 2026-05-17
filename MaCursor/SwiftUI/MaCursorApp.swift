import SwiftUI
import Sparkle

@main
struct MaCursorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var library = LibraryViewModel()
    @State private var appearanceManager = AppearanceManager()
    @State private var languageManager = LanguageManager()
    @Environment(\.openWindow) private var openWindow

    private let updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }
    
    var body: some Scene {
        WindowGroup("MaCursor") {
            LibraryView()
                .environment(library)
                .environment(appearanceManager)
                .environment(languageManager)
                .onAppear {
                    appearanceManager.applyOnLaunch()
                    
                    appDelegate.isViewReady = true
                    
                    let pendingURLs = appDelegate.consumePendingImports()
                    for url in pendingURLs {
                        library.importTheme(at: url)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .macursorImportFile)) { notification in
                    if let url = notification.userInfo?["url"] as? URL {
                        library.importTheme(at: url)
                    }
                }
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        }
        .handlesExternalEvents(matching: [])
        .defaultSize(width: 1200, height: 850)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About MaCursor") {
                    SettingsWindowController.shared.window?.close()
                    openWindow(id: "about")
                }
            }

            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
            
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    NSApp.windows.first(where: { $0.title.hasPrefix("About MaCursor") })?.close()
                    SettingsWindowController.shared.configure(library: library, appearanceManager: appearanceManager, languageManager: languageManager, updater: updaterController.updater)
                    SettingsWindowController.shared.showWindow(nil)
                    NSApp.activate(ignoringOtherApps: true)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            
            CommandGroup(replacing: .newItem) {
                Button("New Theme") {
                    library.addNewTheme()
                }
                .keyboardShortcut("n")
                
                Button("Import Theme...") {
                    library.showImportPanel()
                }
                .keyboardShortcut("o")
            }
            
            CommandGroup(after: .pasteboard) {
                Button("Restore System Cursors") {
                    library.restoreCursors()
                }
            }
            
            CommandGroup(replacing: .help) {
                Button("MaCursor Help") {
                    if let url = URL(string: "https://github.com/writronic/MaCursor") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .keyboardShortcut("/", modifiers: .command)
            }
        }
        
        WindowGroup("Edit Theme", for: String.self) { $themeId in
            if let themeId, let cursorTheme = library.theme(withId: themeId) {
                CursorThemeEditorView(cursorTheme: cursorTheme)
                    .environment(library)
                    .onReceive(NotificationCenter.default.publisher(for: .cursorLibraryIdentifierDidChange)) { note in
                        guard let oldId = note.userInfo?["oldId"] as? String,
                              let newId = note.userInfo?["newId"] as? String,
                              themeId == oldId else { return }
                        $themeId.wrappedValue = newId
                    }
            } else {
                ContentUnavailableView(
                    "Theme Not Found",
                    systemImage: "exclamationmark.triangle",
                    description: Text("The cursor theme could not be loaded.")
                )
            }
        }
        .defaultSize(width: 720, height: 520)
        
        Window("About MaCursor", id: "about") {
            AboutWindowView()
                .windowMinimizeBehavior(.disabled)
                .windowResizeBehavior(.disabled)
        }
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)
    }
}
