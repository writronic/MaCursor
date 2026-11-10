import AppKit

@MainActor
enum MenuBarService {
    struct Snapshot {
        let catalog: [MACMenuBarThemeEntry]
        let favorites: [MACMenuBarThemeEntry]
        let appliedIdentifier: String?
        let overrideIdentifier: String?
        let frontBundleIdentifier: String?
        let frontDisplayName: String?
        let frontIcon: NSImage?
        let frontRuleThemeIdentifier: String?
        let switchByApp: Bool
        let cursorShadow: Bool
        let focusFollowsMouse: Bool
        let ffmDelayMs: Int
        let accessibilityTrusted: Bool
        let cursorTrails: CursorTrailsConfig
        let cursorGestures: CursorGesturesConfig
        let cursorShaker: CursorShakerConfig
        let cursorTranslator: CursorTranslatorConfig
        let screenRecording: Bool
        let cursorScale: Double
        let panelBackdropAlpha: Double
    }

    static func parentAppBundle() -> Bundle? {
        var url = Bundle.main.bundleURL
        for _ in 0..<4 { url.deleteLastPathComponent() }
        guard let bundle = Bundle(url: url), bundle.bundleIdentifier == MACAppBundleIdentifier else { return nil }
        return bundle
    }

    static func language() -> String? {
        guard let parent = parentAppBundle() else { return nil }
        let stored = storedString(MACPreferences.languageKey)
        return stored != "system" && stored != nil
            ? stored : Bundle.preferredLocalizations(from: parent.localizations).first
    }

    static func localized(_ key: String) -> String {
        guard let parent = parentAppBundle(), let language = language(), let path = parent.path(forResource: language, ofType: "lproj"),
              let strings = Bundle(path: path) else { return key }
        return strings.localizedString(forKey: key, value: key, table: "Localizable")
    }

    static func brandImage() -> NSImage? {
        let image = parentAppBundle()?.image(forResource: "MenuBarIcon")
            ?? NSImage(systemSymbolName: "cursorarrow", accessibilityDescription: nil)
        image?.isTemplate = true
        image?.size = NSSize(width: 18, height: 18)
        return image
    }

    private static func storedString(_ key: String) -> String? {
        guard let value = MACPreferences.value(forKey: key) as? String, !value.isEmpty else { return nil }
        return value
    }

    private static func displayName(for bundleID: String?) -> String? {
        guard let bundleID, !bundleID.isEmpty else { return nil }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path)
    }

    private static func icon(for bundleID: String?) -> NSImage? {
        guard let bundleID, !bundleID.isEmpty,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        image.size = NSSize(width: 32, height: 32)
        return image
    }

    private static func postDistributed(_ name: Notification.Name) {
        DistributedNotificationCenter.default().postNotificationName(name, object: nil, userInfo: nil,
                                                                     deliverImmediately: true)
    }

    static func panelBackgroundLevel() -> Double {
        MACMenuBarPanelBackgroundLevel(MACPreferences.value(forKey: MACPreferences.menuBarPanelBackgroundKey))
    }

    private static func reapplyVisibleTheme(restoreWhenNone: Bool) {
        let applied = storedString(MACPreferences.appliedCursorKey)
        let override = storedString(MACPreferences.appOverrideKey)
        guard let visible = MACMenuBarVisibleThemeIdentifier(applied, override) else {
            if restoreWhenNone { try? MACCursorActions.shared.resetAllCursors() }
            return
        }
        let path = MACAutoSwitchThemePathForIdentifier(visible)
        guard FileManager.default.fileExists(atPath: path) else { return }
        let base = override != nil ? (storedString(MACPreferences.appOverrideBaseKey) ?? applied) : nil
        guard MACCursorActions.shared.applyTheme(atPath: path) else { return }
        if override != nil { MACPreferences.set(base, forKey: MACPreferences.appliedCursorKey) }
        MACAutoSwitchEffects.shared.forceVisualRefresh()
    }

    static func currentSnapshot() -> Snapshot {
        let config = MACAutoSwitchEffects.shared.readConfig()
        let catalog = MACMenuBarState.shared.catalog()
        let favorites = MACMenuBarFavoriteCatalog(catalog, MACPreferences.value(forKey: MACPreferences.favoriteThemesKey))
        let front = MACMenuBarState.shared.lastForegroundBundleID
        let scale = MACPreferences.value(forKey: MACPreferences.cursorScaleKey) as? NSNumber
        let ffm = MACFFMReadConfig()
        return Snapshot(
            catalog: catalog,
            favorites: favorites,
            appliedIdentifier: storedString(MACPreferences.appliedCursorKey),
            overrideIdentifier: storedString(MACPreferences.appOverrideKey),
            frontBundleIdentifier: front,
            frontDisplayName: displayName(for: front),
            frontIcon: icon(for: front),
            frontRuleThemeIdentifier: MACMenuBarRuleThemeForBundleID(config, front),
            switchByApp: (config?["switchByApp"] as? NSNumber)?.boolValue ?? false,
            cursorShadow: MACPreferences.flag(MACPreferences.cursorShadowKey),
            focusFollowsMouse: MACFFMEnabled(ffm),
            ffmDelayMs: MACFFMDelayMs(ffm),
            accessibilityTrusted: HelperTrustProbe.isTrusted(),
            cursorTrails: CursorTrailsConfig.load(),
            cursorGestures: CursorGesturesConfig.load(),
            cursorShaker: CursorShakerConfig.load(),
            cursorTranslator: CursorTranslatorConfig.load(),
            screenRecording: HelperTrustProbe.screenRecordingAllowed(),
            cursorScale: scale.map { MACMenuBarClampCursorScale($0.doubleValue) } ?? 1,
            panelBackdropAlpha: MACMenuBarPanelBackdropAlpha(panelBackgroundLevel())
        )
    }

    @discardableResult
    static func applyTheme(_ identifier: String) -> Bool {
        guard !identifier.isEmpty else { return false }
        let path = MACAutoSwitchThemePathForIdentifier(identifier)
        guard FileManager.default.fileExists(atPath: path), MACCursorActions.shared.applyTheme(atPath: path) else { return false }
        MACAutoSwitchEffects.shared.clearAppOverride()
        postDistributed(.MACAutoSwitchAppliedThemeDidChange)
        return true
    }

    static func restoreSystemCursors() {
        MACPreferences.set(1.0, forKey: MACPreferences.cursorScaleKey)
        MACPreferences.setFlag(false, forKey: MACPreferences.handednessKey)
        MACPreferences.setFlag(false, forKey: MACPreferences.cursorShadowKey)
        MACCursorActions.shared.setCursorScale(1)
        MACAutoSwitchEffects.shared.clearAppOverride()
        try? MACCursorActions.shared.resetAllCursors()
        postDistributed(.MACAutoSwitchAppliedThemeDidChange)
        postDistributed(.MACCursorPreferencesDidChange)
    }

    static func resetCursorsOnly() {
        MACAutoSwitchEffects.shared.clearAppOverride()
        try? MACCursorActions.shared.resetAllCursors()
        postDistributed(.MACAutoSwitchAppliedThemeDidChange)
    }

    static func setSwitchByApp(_ enabled: Bool) {
        MACMenuBarWriteConfig(MACMenuBarConfigBySettingSwitchByApp(MACAutoSwitchEffects.shared.readConfig(), enabled))
        MACAutoSwitchEffects.shared.handleFrontmostApp(MACMenuBarState.shared.lastForegroundBundleID)
    }

    static func setFrontAppRule(_ themeIdentifier: String?) {
        guard let front = MACMenuBarState.shared.lastForegroundBundleID, !front.isEmpty else { return }
        let theme = themeIdentifier.flatMap { $0.isEmpty ? nil : $0 }
        var updated = MACMenuBarConfigBySettingRule(MACAutoSwitchEffects.shared.readConfig(), front, displayName(for: front), theme)
        if (updated["switchByApp"] as? NSNumber)?.boolValue != true && theme != nil {
            updated = MACMenuBarConfigBySettingSwitchByApp(updated, true)
        }
        MACMenuBarWriteConfig(updated)
        MACAutoSwitchEffects.shared.handleFrontmostApp(front)
    }

    static func previewCursorScale(_ scale: Double) {
        let clamped = MACMenuBarClampCursorScale(scale)
        MACCursorActions.shared.setCursorScale(Float(max(1, clamped)))
    }

    static func commitCursorScale(_ scale: Double) {
        let clamped = MACMenuBarClampCursorScale(scale)
        MACPreferences.set(clamped, forKey: MACPreferences.cursorScaleKey)
        MACCursorActions.shared.setCursorScale(Float(max(1, clamped)))
        reapplyVisibleTheme(restoreWhenNone: true)
        postDistributed(.MACCursorPreferencesDidChange)
    }

    static func setCursorShadow(_ enabled: Bool) {
        MACPreferences.setFlag(enabled, forKey: MACPreferences.cursorShadowKey)
        reapplyVisibleTheme(restoreWhenNone: false)
        postDistributed(.MACCursorPreferencesDidChange)
    }

    static func setFocusFollowsMouse(_ enabled: Bool) {
        let updated = MACMenuBarFFMConfigBySettingEnabled(MACFFMReadConfig(), enabled)
        guard JSONSerialization.isValidJSONObject(updated),
              let data = try? JSONSerialization.data(withJSONObject: updated) else { return }
        MACPreferences.set(data, forKey: MACPreferences.focusFollowsMouseKey)
        postDistributed(.MACFocusFollowsMouseDidChange)
    }

    static func setFocusFollowsMouseDelay(_ delayMs: Int) {
        let updated = MACMenuBarFFMConfigBySettingDelay(MACFFMReadConfig(), delayMs: delayMs)
        guard JSONSerialization.isValidJSONObject(updated),
              let data = try? JSONSerialization.data(withJSONObject: updated) else { return }
        MACPreferences.set(data, forKey: MACPreferences.focusFollowsMouseKey)
        postDistributed(.MACFocusFollowsMouseDidChange)
    }

    static func setCursorTrails(_ key: WritableKeyPath<CursorTrailsConfig, Bool>, _ value: Bool) {
        var config = CursorTrailsConfig.load()
        config[keyPath: key] = value
        config.save()
    }

    static func setCursorGestures(_ change: (inout CursorGesturesConfig) -> Void) {
        var config = CursorGesturesConfig.load()
        change(&config)
        config.save()
    }

    static func setCursorShakerEnabled(_ enabled: Bool) {
        CursorShakerConfig.setEnabled(enabled)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    static func launchParentAppThenPost(_ name: Notification.Name?) {
        guard let parent = parentAppBundle() else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: parent.bundleURL, configuration: configuration) { _, _ in
            guard let name else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                postDistributed(name)
            }
        }
    }

    static func requestFocusFollowsMouseAccess() {
        if NSRunningApplication.runningApplications(withBundleIdentifier: MACAppBundleIdentifier).isEmpty {
            MACPreferences.setFlag(true, forKey: MACPreferences.pendingFFMAccessWindowKey)
        } else {
            postDistributed(.MACFocusFollowsMouseShowAccessWindow)
        }
        launchParentAppThenPost(nil)
    }

    static func requestCursorGesturesAccess() {
        if NSRunningApplication.runningApplications(withBundleIdentifier: MACAppBundleIdentifier).isEmpty {
            MACPreferences.setFlag(true, forKey: MACPreferences.pendingGesturesAccessWindowKey)
        } else {
            postDistributed(.MACCursorGesturesShowAccessWindow)
        }
        launchParentAppThenPost(nil)
    }

    static func requestCursorShakerAccess() {
        if NSRunningApplication.runningApplications(withBundleIdentifier: MACAppBundleIdentifier).isEmpty {
            MACPreferences.setFlag(true, forKey: MACPreferences.pendingShakerAccessWindowKey)
        } else {
            postDistributed(.MACCursorShakerShowAccessWindow)
        }
        launchParentAppThenPost(nil)
    }

    static func requestCursorScreenshotAccess() {
        if NSRunningApplication.runningApplications(withBundleIdentifier: MACAppBundleIdentifier).isEmpty {
            MACPreferences.setFlag(true, forKey: MACPreferences.pendingScreenshotAccessWindowKey)
        } else {
            postDistributed(.MACCursorScreenshotShowAccessWindow)
        }
        launchParentAppThenPost(nil)
    }

    static func requestCursorTranslatorAccess() {
        if NSRunningApplication.runningApplications(withBundleIdentifier: MACAppBundleIdentifier).isEmpty {
            MACPreferences.setFlag(true, forKey: MACPreferences.pendingTranslatorAccessWindowKey)
        } else {
            postDistributed(.MACCursorTranslatorShowAccessWindow)
        }
        launchParentAppThenPost(nil)
    }
}

actor MenuBarThumbnailLoader {
    struct Record: Sendable {
        let modified: Date
        let thumbnail: MACMenuBarThumbnail
    }

    private var cache: [String: Record] = [:]

    func thumbnail(for identifier: String) -> Record? {
        guard !identifier.isEmpty else { return nil }
        let path = MACAutoSwitchThemePathForIdentifier(identifier)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let modified = attributes[.modificationDate] as? Date else { return nil }
        if let cached = cache[identifier], cached.modified == modified { return cached }
        guard let contents = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let theme = try? PropertyListSerialization.propertyList(from: contents, format: nil) as? [AnyHashable: Any]
        else { return nil }
        guard let thumbnail = MACMenuBarThemeThumbnailData(theme) else { return nil }
        let record = Record(modified: modified, thumbnail: thumbnail)
        cache[identifier] = record
        return record
    }
}
