import Foundation
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {

    private(set) var pendingImportURLs: [URL] = []
    private var accessRequestObserver: NSObjectProtocol?

    var isViewReady = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        ModalWindowCoordinator.shared.start()
        TextEditingFocusCoordinator.shared.start()
        startFocusFollowsMouseAccessRequests()

        let systemDefaultPath = MACSystemDefaultCursorPath()
        if !FileManager.default.fileExists(atPath: systemDefaultPath) {
            NSLog("MaCursor: Capturing system default cursors...")
            let success = MACCaptureSystemDefaults(systemDefaultPath)
            NSLog("MaCursor: System default capture %@", success ? "succeeded" : "failed")
        }

        CursorService.assertPreferredScale()

        MACAutoSwitchRecoverBaseThemeIfNeeded()
        let config = MACAutoSwitchReadConfig()
        let nowMinutes = MACAutoSwitchCurrentMinuteOfDay()
        let scheduledId = MACAutoSwitchResolveThemeIdentifier(config, nowMinutes)
        let storedId = MACPreferences.value(forKey: MACPreferences.appliedCursorKey) as? String
        if let appliedId = MACAutoSwitchLaunchThemeIdentifier(config, nowMinutes, storedId),
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
                MACAutoSwitchForceVisualRefresh()
            }
        }

        AutoSwitchScheduler.shared.start()

        Task { @MainActor in
            await HelperToolManager.shared.ensureCurrent()
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
            FocusFollowsMouseAccessWindowController.shared.present()
        }
        guard MACPreferences.flag(MACPreferences.pendingFFMAccessWindowKey) else { return }
        MACPreferences.setFlag(false, forKey: MACPreferences.pendingFFMAccessWindowKey)
        FocusFollowsMouseAccessWindowController.shared.present()
    }

}

extension Notification.Name {
    static let macursorImportFile = Notification.Name("macursorImportFile")
}

@MainActor
final class AutoSwitchScheduler {
    static let shared = AutoSwitchScheduler()

    private var boundaryTimer: DispatchSourceTimer?
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

        rescheduleBoundaryTimer()
        resolveFrontmostApp()
    }

    private func configDidChange() {
        applyAndRefreshIfNeeded()
        resolveFrontmostApp()
        rescheduleBoundaryTimer()
    }

    private func frontmostAppChanged(_ bundleID: String?) {
        activationDebounce?.cancel()
        let work = DispatchWorkItem {
            MACAutoSwitchHandleFrontmostApp(bundleID)
        }
        activationDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }

    private func resolveFrontmostApp() {
        MACAutoSwitchHandleFrontmostApp(NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
    }

    private func systemAppearanceDidChange() {
        guard MACAutoSwitchMatchesSystemAppearance(MACAutoSwitchReadConfig()) else { return }
        applyAndRefreshIfNeeded()
    }

    private func applyAndRefreshIfNeeded() {
        if MACAutoSwitchApplyIfNeeded() {
            MACAutoSwitchForceVisualRefresh()
        }
    }

    private func rescheduleBoundaryTimer() {
        boundaryTimer?.cancel()
        boundaryTimer = nil

        guard let config = MACAutoSwitchReadConfig(),
              (config["enabled"] as? NSNumber)?.boolValue == true,
              !MACAutoSwitchMatchesSystemAppearance(config) else { return }

        let minutes = MACAutoSwitchMinutesUntilNextBoundary(
            config["scheduleRules"] as? [Any], MACAutoSwitchCurrentMinuteOfDay())
        guard minutes >= 0 else { return }

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(wallDeadline: .now() + .seconds(minutes * 60), leeway: .seconds(5))
        timer.setEventHandler {
            MainActor.assumeIsolated {
                AutoSwitchScheduler.shared.boundaryTimerFired()
            }
        }
        timer.resume()
        boundaryTimer = timer
    }

    private func boundaryTimerFired() {
        applyAndRefreshIfNeeded()
        rescheduleBoundaryTimer()
    }
}
