import SwiftUI
import AppKit

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
        }
    }
    
    var languageCode: String? {
        switch self {
        case .system: return nil
        default:      return rawValue
        }
    }
}

@Observable
@MainActor
final class LanguageManager {
    var currentLanguage: AppLanguage {
        didSet { applyAndPersist() }
    }
    
    var needsRestart: Bool = false
    
    private let launchLanguage: AppLanguage
    
    init() {
        let saved = MCPreferences.value(forKey: MCPreferences.languageKey) as? String ?? "system"
        let resolved = AppLanguage(rawValue: saved) ?? .system
        self.currentLanguage = resolved
        self.launchLanguage = resolved
    }
    
    func applyAndPersist() {
        MCPreferences.set(currentLanguage.rawValue as NSString, forKey: MCPreferences.languageKey)
        
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
