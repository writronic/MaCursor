import Combine
import FinderSync
import Foundation

@MainActor
final class FinderExtensionManager: ObservableObject {
    static let shared = FinderExtensionManager()

    @Published private(set) var election: FinderExtensionElection = .unregistered
    @Published private(set) var settings = RightClickMenuSettings.load()
    @Published private(set) var registrationFailed = false
    @Published private(set) var isRequesting = false
    @Published private(set) var isRefreshing = false
    @Published var selectedTab = RightClickMenuTab.mainMenu

    private var backgroundTask: Task<Void, Never>?

    var isBusy: Bool { isRequesting || isRefreshing }
    var isTranslocated: Bool { RightClickMenuState.isTranslocated(bundlePath: Bundle.main.bundlePath) }

    private init() {}

    func refresh() {
        settings = RightClickMenuSettings.load()
        guard !isBusy else { return }
        isRefreshing = true
        backgroundTask = Task {
            defer {
                isRefreshing = false
                backgroundTask = nil
            }
            await readElection()
            await readFullDiskAccess()
        }
    }

    func registerIfNeeded() {
        guard !isBusy else { return }
        isRefreshing = true
        backgroundTask = Task {
            defer {
                isRefreshing = false
                backgroundTask = nil
            }
            await registerBundledExtension()
            await readElection()
        }
    }

    func prepareAccessRequest() async {
        guard !isRequesting, !isTranslocated else { return }
        isRequesting = true
        defer { isRequesting = false }
        if let backgroundTask { await backgroundTask.value }
        await registerBundledExtension()
        await readElection()
    }

    @discardableResult
    func setEnabled(_ enabled: Bool) throws -> Bool {
        guard !enabled || election == .elected else { return false }
        try update(\.isEnabled, to: enabled)
        return true
    }

    func update<Value>(_ keyPath: WritableKeyPath<RightClickMenuSettings, Value>, to value: Value) throws {
        try change { $0[keyPath: keyPath] = value }
    }

    func change(_ change: (inout RightClickMenuSettings) throws -> Void) throws {
        let result = RightClickMenuSettings.update(shown: settings, change: change)
        settings = result.settings
        if let error = result.error { throw error }
    }

    func resetSettings() throws {
        settings = try RightClickMenuSettings.reset()
    }

    func openSystemSettings() {
        guard SystemSettingsPane.finderExtensions() != .command else { return }
        FIFinderSyncController.showExtensionManagementInterface()
    }

    func copyCommand() {
        guard SystemSettingsPane.finderExtensions() == .command else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(RightClickMenuState.enableCommand, forType: .string)
    }

    private func registerBundledExtension() async {
        guard !isTranslocated,
              let url = Bundle.main.builtInPlugInsURL?.appendingPathComponent("MaCursorFinder.appex"),
              FileManager.default.fileExists(atPath: url.path) else {
            registrationFailed = true
            return
        }
        registrationFailed = await Self.runPluginkit(["-a", url.path]) == nil
    }

    private func readElection() async {
        let row = await Self.runPluginkit(["-m", "-i", RightClickMenuState.extensionBundleIdentifier])
        election = RightClickMenuState.election(fromPluginkitRow: row ?? "")
    }

    private func readFullDiskAccess() async {
        let granted = await Self.run("/bin/sh", RightClickMenuState.fullDiskAccessProbeArguments(home: FileManager.default.homeDirectoryForCurrentUser)) != nil
        guard granted != settings.hasFullDiskAccess else { return }
        try? update(\.hasFullDiskAccess, to: granted)
    }

    func openFullDiskAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }

    func shouldAskForFullDiskAccessAtLaunch() async -> Bool {
        if let backgroundTask { await backgroundTask.value }
        let asked = MACPreferences.flag(MACPreferences.fullDiskAccessAskedKey)
        if settings.isEnabled { await readFullDiskAccess() }
        return RightClickMenuState.asksForFullDiskAccessAtLaunch(enabled: settings.isEnabled, hasFullDiskAccess: settings.hasFullDiskAccess, alreadyAsked: asked)
    }

    nonisolated private static func runPluginkit(_ arguments: [String]) async -> String? {
        await run("/usr/bin/pluginkit", arguments)
    }

    nonisolated static func run(_ executable: String, _ arguments: [String]) async -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        let reader = Task.detached {
            pipe.fileHandleForReading.readDataToEndOfFile()
        }
        let status: Int32? = await withCheckedContinuation { continuation in
            process.terminationHandler = { terminated in
                continuation.resume(returning: terminated.terminationStatus)
            }
            do {
                try process.run()
                try? pipe.fileHandleForWriting.close()
                DispatchQueue.global().asyncAfter(deadline: .now() + 10) {
                    if process.isRunning { process.terminate() }
                }
            } catch {
                process.terminationHandler = nil
                try? pipe.fileHandleForWriting.close()
                continuation.resume(returning: nil)
            }
        }
        let data = await reader.value
        try? pipe.fileHandleForReading.close()
        guard status == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
