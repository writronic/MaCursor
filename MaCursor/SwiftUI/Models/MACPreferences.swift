import Foundation

enum MACPreferences {
    nonisolated(unsafe) static let domain: CFString = "com.writronic.MaCursor" as CFString

    struct Operations {
        var readApp: (CFString, CFString) -> Any?
        var read: (CFString, CFString, CFString, CFString) -> Any?
        var write: (CFString, Any?, CFString, CFString, CFString) -> Void
        var synchronize: (CFString, CFString, CFString) -> Void

        static var live: Operations {
            Operations(readApp: { CFPreferencesCopyAppValue($0, $1) },
                       read: { CFPreferencesCopyValue($0, $1, $2, $3) },
                       write: { CFPreferencesSetValue($0, $1 as CFPropertyList?, $2, $3, $4) },
                       synchronize: { _ = CFPreferencesSynchronize($0, $1, $2) })
        }
    }


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
    static let cursorTrailsKey           = "MACCursorTrails"
    static let cursorGesturesKey         = "MACCursorGestures"
    static let cursorShakerKey           = "MACCursorShaker"
    static let cursorScreenshotKey       = "MACCursorScreenshot"
    static let cursorScreenshotMarkupKey = "MACCursorScreenshotMarkup"
    static let cursorTranslatorKey       = "MACCursorTranslator"
    static let cursorTranslatorScreenRecordingKey = "MACCursorTranslatorScreenRecording"
    static let ffmAccessibilityTrustedKey = "MACFFMAccessibilityTrusted"
    static let showMenuBarIconKey        = "MACShowMenuBarIcon"
    static let menuBarPanelBackgroundKey = "MACMenuBarPanelBackground"
    static let menuBarItemOrderKey       = "MACMenuBarItemOrder"
    static let menuBarHiddenItemsKey     = "MACMenuBarHiddenItems"
    static let menuBarCaptureOrderKey    = "MACMenuBarCaptureOrder"
    static let menuBarHiddenCaptureRowsKey = "MACMenuBarHiddenCaptureRows"
    static let favoriteThemesKey         = "MACFavoriteThemes"
    static let pendingOpenSettingsKey    = "MACPendingOpenSettings"
    static let pendingFFMAccessWindowKey = "MACPendingFFMAccessWindow"
    static let pendingGesturesAccessWindowKey = "MACPendingGesturesAccessWindow"
    static let pendingShakerAccessWindowKey = "MACPendingShakerAccessWindow"
    static let pendingScreenshotAccessWindowKey = "MACPendingScreenshotAccessWindow"
    static let pendingTranslatorAccessWindowKey = "MACPendingTranslatorAccessWindow"
    static let welcomeShownKey           = "MACWelcomeShown"
    static let welcomePageKey            = "MACWelcomePage"
    static let fullDiskAccessAskedKey   = "MACFullDiskAccessAsked"
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
        welcomeShownKey,
        welcomePageKey,
        hideTahoeCursorsKey,
        advancedEditorLayoutKey,
        cursorShadowKey,
        autoSwitchRulesKey,
        appOverrideKey,
        appOverrideBaseKey,
        focusFollowsMouseKey,
        cursorTrailsKey,
        cursorGesturesKey,
        cursorShakerKey,
        cursorScreenshotKey,
        cursorScreenshotMarkupKey,
        cursorTranslatorKey,
        cursorTranslatorScreenRecordingKey,
        showMenuBarIconKey,
        menuBarPanelBackgroundKey,
        menuBarItemOrderKey,
        menuBarHiddenItemsKey,
        menuBarCaptureOrderKey,
        menuBarHiddenCaptureRowsKey,
        favoriteThemesKey,
        ffmAccessibilityTrustedKey,
        fullDiskAccessAskedKey
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

    static func value(forKey key: String, operations: Operations = .live) -> Any? {
        operations.readApp(key as CFString, domain)
    }

    static func value(forKey key: String, user: CFString, host: CFString, operations: Operations = .live) -> Any? {
        operations.read(key as CFString, domain, user, host)
    }

    static func flag(_ key: String, operations: Operations = .live) -> Bool {
        return (value(forKey: key, operations: operations) as? NSNumber)?.boolValue ?? false
    }


    static func set(_ value: Any?, forKey key: String, operations: Operations = .live) {
        set(value, forKey: key, user: kCFPreferencesCurrentUser, host: kCFPreferencesCurrentHost, operations: operations)
    }

    static func set(_ value: Any?, forKey key: String, user: CFString, host: CFString, operations: Operations = .live) {
        operations.write(key as CFString, value, domain, user, host)
        operations.synchronize(domain, user, host)
    }

    static func setFlag(_ value: Bool, forKey key: String, operations: Operations = .live) {
        set(NSNumber(value: value), forKey: key, operations: operations)
    }
}
