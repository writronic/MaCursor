import AppKit
import SwiftUI

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

@MainActor
final class AppearanceManager: ObservableObject {
    @Published var currentMode: AppearanceMode {
        didSet { applyAndPersist() }
    }

    init() {
        let raw = (MACPreferences.value(forKey: MACPreferences.appearanceModeKey) as? NSNumber)?.intValue ?? 0
        self.currentMode = AppearanceMode(rawValue: raw) ?? .system
    }

    func applyAndPersist() {
        MACPreferences.set(NSNumber(value: currentMode.rawValue), forKey: MACPreferences.appearanceModeKey)

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

enum AppLanguage: String, CaseIterable, Identifiable {
    case system  = "system"
    case en      = "en"
    case nl      = "nl"
    case zhHans  = "zh-Hans"
    case fr      = "fr"
    case de      = "de"
    case ru      = "ru"
    case es      = "es"
    case tr      = "tr"
    case ja      = "ja"
    case ar      = "ar"
    case pl      = "pl"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return String(localized: "System Default")
        case .en:     return "English"
        case .nl:     return "Nederlands"
        case .zhHans: return "简体中文"
        case .fr:     return "Français"
        case .de:     return "Deutsch"
        case .ru:     return "Русский"
        case .es:     return "Español"
        case .tr:     return "Türkçe"
        case .ja:     return "日本語"
        case .ar:     return "العربية"
        case .pl:     return "Polski"
        }
    }

    var languageCode: String? {
        switch self {
        case .system: return nil
        default:      return rawValue
        }
    }
}

@MainActor
final class LanguageManager: ObservableObject {
    @Published var currentLanguage: AppLanguage {
        didSet { applyAndPersist() }
    }

    @Published var needsRestart: Bool = false

    private let launchLanguage: AppLanguage

    init() {
        let saved = MACPreferences.value(forKey: MACPreferences.languageKey) as? String ?? "system"
        let resolved = AppLanguage(rawValue: saved) ?? .system
        self.currentLanguage = resolved
        self.launchLanguage = resolved
    }

    func applyAndPersist() {
        MACPreferences.set(currentLanguage.rawValue as NSString, forKey: MACPreferences.languageKey)

        if let code = currentLanguage.languageCode {
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
        UserDefaults.standard.synchronize()

        needsRestart = (currentLanguage != launchLanguage)
    }

    func restartApp() {
        let url = URL(fileURLWithPath: Bundle.main.resourcePath!)
        let path = url.deletingLastPathComponent().deletingLastPathComponent().absoluteString
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-n", path]
        task.launch()

        NSApp.terminate(nil)
    }
}
