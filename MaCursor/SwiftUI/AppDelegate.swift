import Foundation
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {

    private(set) var pendingImportURLs: [URL] = []
    private var accessRequestObserver: NSObjectProtocol?
    private var gesturesAccessRequestObserver: NSObjectProtocol?
    private var shakerAccessRequestObserver: NSObjectProtocol?
    private var translatorAccessRequestObserver: NSObjectProtocol?

    var isViewReady = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        ModalWindowCoordinator.shared.start()
        TextEditingFocusCoordinator.shared.start()
        EditorTextShortcutCoordinator.shared.start()
        startFocusFollowsMouseAccessRequests()
        startCursorGesturesAccessRequests()
        startCursorShakerAccessRequests()
        startCursorTranslatorAccessRequests()

        MACCursorCapture.shared.capture(to: MACCursorCapture.systemDefaultPath)

        CursorService.assertPreferredScale()

        MACAutoSwitchEffects.shared.recoverBaseThemeIfNeeded()
        let config = MACAutoSwitchEffects.shared.readConfig()
        let nowMinutes = MACAutoSwitchCurrentMinuteOfDay()
        let isDark = MACAutoSwitchEffects.shared.isSystemInDarkMode()
        let scheduledId = MACAutoSwitchResolveThemeIdentifier(config, nowMinutes, isDark: isDark)
        let storedId = MACPreferences.value(forKey: MACPreferences.appliedCursorKey) as? String
        if let appliedId = MACAutoSwitchLaunchThemeIdentifier(config, nowMinutes, storedId, isDark: isDark),
           !appliedId.isEmpty,
           let cursorsPath = try? FileManager.default.findOrCreateDirectory(
               .applicationSupportDirectory,
               in: .userDomainMask,
               appendPathComponent: "MaCursor/cursors"
           ) {
            let themePath = (cursorsPath as NSString).appendingPathComponent(appliedId + ".cursor")
            if FileManager.default.fileExists(atPath: themePath),
               CursorService.applyTheme(atPath: themePath) {
                if scheduledId != nil {
                    MACPreferences.set(appliedId as NSString, forKey: MACPreferences.appliedCursorKey)
                }
                MACAutoSwitchEffects.shared.forceVisualRefresh()
            }
        }

        AutoSwitchScheduler.shared.start()
        FinderExtensionManager.shared.registerIfNeeded()

        Task { @MainActor in
            await HelperToolManager.shared.ensureCurrent()
        }
        Task { @MainActor in
            guard await FinderExtensionManager.shared.shouldAskForFullDiskAccessAtLaunch() else { return }
            AccessWindowController.rightClickMenu.present()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if flag {
            return false
        }
        return true
    }


    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.pathExtension.lowercased() == "cursor" {
            enqueueOrImport(url)
        }
    }

    private func enqueueOrImport(_ url: URL) {
        if isViewReady {
            NotificationCenter.default.post(
                name: .macursorImportFile,
                object: nil,
                userInfo: ["url": url]
            )
        } else {
            pendingImportURLs.append(url)
        }
    }

    func consumePendingImports() -> [URL] {
        let urls = pendingImportURLs
        pendingImportURLs = []
        return urls
    }

    private func startFocusFollowsMouseAccessRequests() {
        accessRequestObserver = DistributedNotificationCenter.default().addObserver(
            forName: .MACFocusFollowsMouseShowAccessWindow,
            object: nil,
            queue: .main
        ) { _ in
            AccessWindowController.focusFollowsMouse.present()
        }
        guard MACPreferences.flag(MACPreferences.pendingFFMAccessWindowKey) else { return }
        MACPreferences.setFlag(false, forKey: MACPreferences.pendingFFMAccessWindowKey)
        AccessWindowController.focusFollowsMouse.present()
    }

    private func startCursorGesturesAccessRequests() {
        gesturesAccessRequestObserver = DistributedNotificationCenter.default().addObserver(
            forName: .MACCursorGesturesShowAccessWindow,
            object: nil,
            queue: .main
        ) { _ in
            AccessWindowController.cursorGestures.present()
        }
        guard MACPreferences.flag(MACPreferences.pendingGesturesAccessWindowKey) else { return }
        MACPreferences.setFlag(false, forKey: MACPreferences.pendingGesturesAccessWindowKey)
        AccessWindowController.cursorGestures.present()
    }

    private func startCursorShakerAccessRequests() {
        shakerAccessRequestObserver = DistributedNotificationCenter.default().addObserver(
            forName: .MACCursorShakerShowAccessWindow,
            object: nil,
            queue: .main
        ) { _ in
            AccessWindowController.cursorShaker.present()
        }
        guard MACPreferences.flag(MACPreferences.pendingShakerAccessWindowKey) else { return }
        MACPreferences.setFlag(false, forKey: MACPreferences.pendingShakerAccessWindowKey)
        AccessWindowController.cursorShaker.present()
    }

    private func startCursorTranslatorAccessRequests() {
        translatorAccessRequestObserver = DistributedNotificationCenter.default().addObserver(
            forName: .MACCursorTranslatorShowAccessWindow,
            object: nil,
            queue: .main
        ) { _ in
            AccessWindowController.cursorTranslator.present()
        }
        guard MACPreferences.flag(MACPreferences.pendingTranslatorAccessWindowKey) else { return }
        MACPreferences.setFlag(false, forKey: MACPreferences.pendingTranslatorAccessWindowKey)
        AccessWindowController.cursorTranslator.present()
    }

}

extension Notification.Name {
    static let macursorImportFile = Notification.Name("macursorImportFile")
}

@MainActor
final class AutoSwitchScheduler {
    static let shared = AutoSwitchScheduler()

    private let boundarySchedule = MACAutoSwitchScheduleTimer()
    private var appearanceObservation: NSKeyValueObservation?
    private var activationDebounce: DispatchWorkItem?
    private var started = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true

        NotificationCenter.default.addObserver(
            forName: .macAutoSwitchConfigDidChange,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                AutoSwitchScheduler.shared.configDidChange()
            }
        }

        appearanceObservation = NSApplication.shared.observe(\.effectiveAppearance) { _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    AutoSwitchScheduler.shared.systemAppearanceDidChange()
                }
            }
        }

        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                AutoSwitchScheduler.shared.systemAppearanceDidChange()
            }
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                AutoSwitchScheduler.shared.configDidChange()
            }
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleID = app?.bundleIdentifier
            MainActor.assumeIsolated {
                AutoSwitchScheduler.shared.frontmostAppChanged(bundleID)
            }
        }

        boundarySchedule.start()
        resolveFrontmostApp()
    }

    private func configDidChange() {
        applyAndRefreshIfNeeded()
        resolveFrontmostApp()
        boundarySchedule.reschedule()
    }

    private func frontmostAppChanged(_ bundleID: String?) {
        activationDebounce?.cancel()
        let work = DispatchWorkItem {
            MainActor.assumeIsolated {
                MACAutoSwitchEffects.shared.handleFrontmostApp(bundleID)
            }
        }
        activationDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }

    private func resolveFrontmostApp() {
        MACAutoSwitchEffects.shared.handleFrontmostApp(NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
    }

    private func systemAppearanceDidChange() {
        guard MACAutoSwitchMatchesSystemAppearance(MACAutoSwitchEffects.shared.readConfig()) else { return }
        applyAndRefreshIfNeeded()
    }

    private func applyAndRefreshIfNeeded() {
        if MACAutoSwitchEffects.shared.applyIfNeeded() {
            MACAutoSwitchEffects.shared.forceVisualRefresh()
        }
    }
}
