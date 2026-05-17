import Foundation

enum MCPreferences {
    nonisolated(unsafe) static let domain: CFString = "com.writronic.MaCursor" as CFString
    
    
    static let appliedCursorKey          = "MCAppliedCursor"
    static let clickActionKey            = "MCLibraryClickAction"
    static let cursorScaleKey            = "MCCursorScale"
    static let handednessKey             = "MCHandedness"
    static let suppressDeleteLibraryKey  = "MCSuppressDeleteLibraryConfirmationKey"
    static let suppressDeleteCursorKey   = "MCSuppressDeleteCursorConfirmationKey"
    static let favoriteCursorsKey        = "MCFavoriteCursors"
    static let appearanceModeKey         = "MCAppearanceMode"
    static let languageKey               = "MCLanguage"
    
    
    static func value(forKey key: String) -> Any? {
        let result = CFPreferencesCopyAppValue(key as CFString, domain)
        return result as Any?
    }
    
    static func value(forKey key: String, user: CFString, host: CFString) -> Any? {
        let result = CFPreferencesCopyValue(key as CFString, domain, user, host)
        return result as Any?
    }
    
    static func flag(_ key: String) -> Bool {
        return (value(forKey: key) as? NSNumber)?.boolValue ?? false
    }
    
    
    static func set(_ value: Any?, forKey key: String) {
        CFPreferencesSetValue(
            key as CFString,
            value as CFPropertyList?,
            domain,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
        CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
    }
    
    static func set(_ value: Any?, forKey key: String, user: CFString, host: CFString) {
        CFPreferencesSetValue(key as CFString, value as CFPropertyList?, domain, user, host)
        CFPreferencesSynchronize(domain, user, host)
    }
    
    static func setFlag(_ value: Bool, forKey key: String) {
        set(NSNumber(value: value), forKey: key)
    }
}
