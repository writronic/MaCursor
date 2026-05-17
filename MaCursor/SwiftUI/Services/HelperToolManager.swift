import Foundation
import ServiceManagement
import Observation

@MainActor
@Observable
class HelperToolManager {
    static let shared = HelperToolManager()
    
    private let helperBundleIdentifier = "com.writronic.macursorhelper"
    
    private(set) var isInstalled: Bool = false
    private(set) var statusDescription: String = "Not Installed"
    
    private var statusCheckTimer: Timer?
    
    private init() {
        refreshStatus()
        startStatusMonitoring()
    }
    
    nonisolated func stopMonitoring() {
        Task { @MainActor in
            statusCheckTimer?.invalidate()
        }
    }
    
    
    func install() async throws {
        let service = SMAppService.loginItem(identifier: helperBundleIdentifier)
        try service.register()
        
        try await Task.sleep(nanoseconds: 500_000_000)
        
        refreshStatus()
    }
    
    func uninstall() async throws {
        let service = SMAppService.loginItem(identifier: helperBundleIdentifier)
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
    
    
    func refreshStatus() {
        let service = SMAppService.loginItem(identifier: helperBundleIdentifier)
        let status = service.status
        
        isInstalled = (status == .enabled)
        
        switch status {
        case .enabled:
            statusDescription = String(localized: "Installed & Active")
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
    
    
    private func startStatusMonitoring() {
        statusCheckTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshStatus()
            }
        }
    }
}
