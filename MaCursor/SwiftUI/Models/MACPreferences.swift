import Foundation

enum MACPreferences {
    nonisolated(unsafe) static let domain: CFString = "com.writronic.MaCursor" as CFString


    static let appliedCursorKey          = "MACAppliedCursor"
    static let cursorScaleKey            = "MACCursorScale"
    static let handednessKey             = "MACHandedness"
    static let cursorShadowKey           = "MACCursorShadow"
    static let suppressDeleteLibraryKey  = "MACSuppressDeleteLibraryConfirmationKey"
    static let suppressDeleteCursorKey   = "MACSuppressDeleteCursorConfirmationKey"
    static let favoriteCursorsKey        = "MACFavoriteCursors"
    static let appearanceModeKey         = "MACAppearanceMode"
    static let languageKey               = "MACLanguage"
    static let hideTahoeCursorsKey       = "MACHideTahoeCursors"
    static let advancedEditorLayoutKey   = "MACAdvancedEditorLayout"
    static let autoSwitchRulesKey        = "MACAutoSwitchRules"
    static let appOverrideKey            = "MACAutoSwitchAppOverride"
    static let appOverrideBaseKey        = "MACAutoSwitchAppOverrideBase"
    static let focusFollowsMouseKey      = "MACFocusFollowsMouse"
    static let ffmAccessibilityTrustedKey = "MACFFMAccessibilityTrusted"
    static let showMenuBarIconKey        = "MACShowMenuBarIcon"
    static let menuBarPanelBackgroundKey = "MACMenuBarPanelBackground"
    static let favoriteThemesKey         = "MACFavoriteThemes"
    static let pendingOpenSettingsKey    = "MACPendingOpenSettings"
    static let pendingFFMAccessWindowKey = "MACPendingFFMAccessWindow"
    static let helperBuildKey            = "MACHelperBuild"

    static let resetKeys: [String] = [
        appliedCursorKey,
        cursorScaleKey,
        handednessKey,
        suppressDeleteLibraryKey,
        suppressDeleteCursorKey,
        favoriteCursorsKey,
        appearanceModeKey,
        languageKey,
        hideTahoeCursorsKey,
        cursorShadowKey,
        autoSwitchRulesKey,
        appOverrideKey,
        appOverrideBaseKey,
        focusFollowsMouseKey,
        showMenuBarIconKey,
        menuBarPanelBackgroundKey,
        favoriteThemesKey,
        ffmAccessibilityTrustedKey
    ]

    static var hideTahoeCursors: Bool {
        (value(forKey: hideTahoeCursorsKey) as? NSNumber)?.boolValue ?? true
    }

    static var advancedEditorLayout: String {
        (value(forKey: advancedEditorLayoutKey) as? String) ?? "list"
    }

    static var isLeftHanded: Bool {
        guard let stored = value(forKey: handednessKey) as? NSNumber else { return false }
        return stored.boolValue
    }

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
