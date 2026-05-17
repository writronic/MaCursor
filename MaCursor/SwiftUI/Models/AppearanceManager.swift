import SwiftUI
import AppKit

enum AppearanceMode: Int, CaseIterable, Identifiable {
    case system = 0
    case light  = 1
    case dark   = 2
    
    var id: Int { rawValue }
    
    var label: String {
        switch self {
        case .system: return String(localized: "System")
        case .light:  return String(localized: "Light")
        case .dark:   return String(localized: "Dark")
        }
    }
    
    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max.fill"
        case .dark:   return "moon.fill"
        }
    }
}

@Observable
@MainActor
final class AppearanceManager {
    var currentMode: AppearanceMode {
        didSet { applyAndPersist() }
    }
    
    init() {
        let raw = (MCPreferences.value(forKey: MCPreferences.appearanceModeKey) as? NSNumber)?.intValue ?? 0
        self.currentMode = AppearanceMode(rawValue: raw) ?? .system
    }
    
    func applyAndPersist() {
        MCPreferences.set(NSNumber(value: currentMode.rawValue), forKey: MCPreferences.appearanceModeKey)
        
        switch currentMode {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
    
    func applyOnLaunch() {
        applyAndPersist()
    }
}
