import Foundation
import AppKit
import ServiceManagement
import Combine

@MainActor
class HelperToolManager: ObservableObject {
    static let shared = HelperToolManager()

    private let helperBundleIdentifier = MACHelperBundleIdentifier
    private static let legacyHelperBundleIdentifier = "com.writronic.macursorhelper"
    private static let launchGrace: UInt64 = 3_000_000_000
    private static let launchItemRebuildWindow: UInt64 = 10_000_000_000

    @Published private(set) var isInstalled: Bool = false
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var statusDescription: String = "Not Installed"

    private var statusCheckTimer: Timer?
    private var runStateObservers: [NSObjectProtocol] = []

    private init() {
        refreshStatus()
        startStatusMonitoring()
        startRunStateMonitoring()
    }

    nonisolated func stopMonitoring() {
        Task { @MainActor in
            statusCheckTimer?.invalidate()
            for observer in runStateObservers {
                NSWorkspace.shared.notificationCenter.removeObserver(observer)
            }
            runStateObservers = []
        }
    }

    private var service: SMAppService {
        SMAppService.loginItem(identifier: helperBundleIdentifier)
    }

    func install() async throws {
        await migrateLegacyLoginItem()
        registerBundledHelperWithLaunchServices()
        try service.register()

        try await Task.sleep(nanoseconds: 500_000_000)

        refreshStatus()
        if needsRestart() {
            await ensureCurrent()
        }
    }

    func uninstall() async throws {
        try await service.unregister()

        try await Task.sleep(nanoseconds: 500_000_000)

        refreshStatus()
    }

    func toggle() async throws {
        if isInstalled {
            try await uninstall()
        } else {
            try await install()
        }
    }

    func ensureCurrent() async {
        await migrateLegacyLoginItem()
        registerBundledHelperWithLaunchServices()
        refreshStatus()
        guard isInstalled, needsRestart() else { return }

        for delay in [UInt64(0), Self.launchItemRebuildWindow] {
            try? await Task.sleep(nanoseconds: delay)
            try? await service.unregister()
            do {
                try service.register()
            } catch {
                NSLog("MaCursor: Helper re-registration failed: %@", error.localizedDescription)
                return
            }
            try? await Task.sleep(nanoseconds: Self.launchGrace)
            refreshStatus()
            if !needsRestart() {
                NSLog("MaCursor: Helper restarted with the bundled build")
                return
            }
        }
        NSLog("MaCursor: Helper did not start after re-registration")
    }

    func refreshStatus() {
        let status = service.status

        isInstalled = (status == .enabled)
        isRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: helperBundleIdentifier).isEmpty

        switch status {
        case .enabled:
            statusDescription = isRunning
                ? String(localized: "Installed & Active")
                : String(localized: "Installed, not running")
        case .notRegistered:
            statusDescription = String(localized: "Not Installed")
        case .notFound:
            statusDescription = String(localized: "Helper Not Found")
        case .requiresApproval:
            statusDescription = String(localized: "Requires Approval in System Settings")
        @unknown default:
            statusDescription = String(localized: "Unknown")
        }
    }

    private var bundledHelperURL: URL {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/LoginItems")
            .appendingPathComponent("\(MACHelperBundleName).app")
    }

    private var bundledHelperBuild: String? {
        let executable = bundledHelperURL.appendingPathComponent("Contents/MacOS/\(MACHelperBundleName)")
        return MACHelperBuildIdentityAtPath(executable.path)
    }

    private func migrateLegacyLoginItem() async {
        let legacy = SMAppService.loginItem(identifier: Self.legacyHelperBundleIdentifier)
        guard legacy.status != .notRegistered else { return }
        let wasEnabled = legacy.status == .enabled
        try? await legacy.unregister()
        guard wasEnabled, service.status != .enabled else { return }
        registerBundledHelperWithLaunchServices()
        try? service.register()
        NSLog("MaCursor: Migrated the login item to %@", helperBundleIdentifier)
    }

    private func registerBundledHelperWithLaunchServices() {
        let status = LSRegisterURL(bundledHelperURL as CFURL, true)
        if status != noErr {
            NSLog("MaCursor: LaunchServices registration of the helper returned %d", status)
        }
    }

    private func needsRestart() -> Bool {
        CFPreferencesAppSynchronize(MACPreferences.domain)
        let runningBuild = MACPreferences.value(forKey: MACPreferences.helperBuildKey) as? String
        return MACHelperNeedsRestart(isRunning, runningBuild, bundledHelperBuild)
    }

    private func startRunStateMonitoring() {
        let names: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
        ]
        for name in names {
            let observer = NSWorkspace.shared.notificationCenter.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard app?.bundleIdentifier == MACHelperBundleIdentifier else { return }
                Task { @MainActor in
                    self?.refreshStatus()
                }
            }
            runStateObservers.append(observer)
        }
    }

    private func startStatusMonitoring() {
        statusCheckTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshStatus()
            }
        }
    }
}
