import Foundation
import AppKit
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate {
    
    private(set) var pendingImportURLs: [URL] = []
    
    var isViewReady = false
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        ModalWindowCoordinator.shared.start()
        
        
        let appliedId = MCPreferences.value(forKey: MCPreferences.appliedCursorKey) as? String
        if let appliedId, !appliedId.isEmpty {
            
            guard let cursorsPath = try? FileManager.default.findOrCreateDirectory(
                .applicationSupportDirectory,
                in: .userDomainMask,
                appendPathComponent: "MaCursor/cursors"
            ) else { return }
            
            let themePath = (cursorsPath as NSString).appendingPathComponent(appliedId + ".cursor")
            if FileManager.default.fileExists(atPath: themePath) {
                CursorService.applyTheme(atPath: themePath)
            }
        }
        
        refreshHelperRegistrationIfNeeded()
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
    
    
    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let ext = (filename as NSString).pathExtension.lowercased()
        guard ext == "cursor" else { return false }
        
        let url = URL(fileURLWithPath: filename)
        enqueueOrImport(url)
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
    
    
    private func refreshHelperRegistrationIfNeeded() {
        let service = SMAppService.loginItem(identifier: "com.writronic.macursorhelper")
        guard service.status == .enabled else { return }
        
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: "com.writronic.macursorhelper")
        if running.isEmpty {
            NSLog("MaCursor: Helper registered but not running — refreshing registration")
            Task {
                do {
                    try await service.unregister()
                    try await Task.sleep(nanoseconds: 500_000_000)
                    try service.register()
                    NSLog("MaCursor: Helper re-registered successfully")
                    
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                    DistributedNotificationCenter.default().postNotificationName(
                        .init("MCShortcutsDidChange"),
                        object: nil,
                        userInfo: nil,
                        deliverImmediately: true
                    )
                } catch {
                    NSLog("MaCursor: Helper re-registration failed: %@", error.localizedDescription)
                }
            }
        }
    }

}

extension Notification.Name {
    static let macursorImportFile = Notification.Name("macursorImportFile")
}
