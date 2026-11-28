import AppKit

extension Notification.Name {
    static let MACAutoSwitchDidChange = Notification.Name("MACAutoSwitchDidChange")
    static let MACAutoSwitchAppliedThemeDidChange = Notification.Name("MACAutoSwitchAppliedThemeDidChange")
}

enum MACAppSwitchAction {
    case none, applyOverride, revert
}

func MACAutoSwitchThemePathForIdentifier(_ identifier: String) -> String {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return ((support.path as NSString).appendingPathComponent("MaCursor/cursors") as NSString)
        .appendingPathComponent(identifier).appending(".cursor")
}

private func autoSwitchString(_ value: Any?) -> String? {
    guard let string = value as? String, !string.isEmpty else { return nil }
    return string
}

private func usableScheduleRule(_ candidate: Any) -> (theme: String, minutes: Int)? {
    guard let rule = candidate as? [AnyHashable: Any],
          let theme = autoSwitchString(rule["themeIdentifier"]),
          let number = rule["startMinutes"] as? NSNumber,
          CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
    let minutes = number.intValue
    guard (0...1439).contains(minutes) else { return nil }
    return (theme, minutes)
}

func MACAutoSwitchResolveScheduleTheme(_ rules: [Any]?, _ nowMinutes: Int) -> String? {
    var passed: (theme: String, minutes: Int)?
    var latest: (theme: String, minutes: Int)?
    for candidate in rules ?? [] {
        guard let rule = usableScheduleRule(candidate) else { continue }
        if rule.minutes >= (latest?.minutes ?? -1) { latest = rule }
        if rule.minutes <= nowMinutes && rule.minutes >= (passed?.minutes ?? -1) { passed = rule }
    }
    return (passed ?? latest)?.theme
}

func MACAutoSwitchNextBoundaryDate(_ config: [AnyHashable: Any]?, after now: Date, calendar: Calendar = .current) -> Date? {
    guard (config?["enabled"] as? NSNumber)?.boolValue == true, !MACAutoSwitchMatchesSystemAppearance(config) else { return nil }
    return ((config?["scheduleRules"] as? [Any]) ?? []).compactMap(usableScheduleRule).compactMap { rule in
        calendar.nextDate(after: now, matching: DateComponents(hour: rule.minutes / 60, minute: rule.minutes % 60),
                          matchingPolicy: .nextTime)
    }.min()
}

func MACAutoSwitchCurrentMinuteOfDay() -> Int {
    let parts = Calendar.current.dateComponents([.hour, .minute], from: Date())
    return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
}

private func usableAppRule(_ candidate: Any) -> (theme: String, bundle: String)? {
    guard let rule = candidate as? [AnyHashable: Any],
          let theme = autoSwitchString(rule["themeIdentifier"]),
          let bundle = autoSwitchString(rule["bundleIdentifier"]) else { return nil }
    return (theme, bundle)
}

func MACAutoSwitchAppRulesActive(_ config: [AnyHashable: Any]?) -> Bool {
    guard (config?["switchByApp"] as? NSNumber)?.boolValue == true,
          let rules = config?["appRules"] as? [Any] else { return false }
    return rules.contains { usableAppRule($0) != nil }
}

func MACAutoSwitchThemeForBundleID(_ config: [AnyHashable: Any]?, _ bundleID: String?) -> String? {
    guard let bundleID = autoSwitchString(bundleID), MACAutoSwitchAppRulesActive(config),
          let rules = config?["appRules"] as? [Any] else { return nil }
    for candidate in rules {
        if let rule = usableAppRule(candidate), rule.bundle == bundleID { return rule.theme }
    }
    return nil
}

func MACAutoSwitchMatchesSystemAppearance(_ config: [AnyHashable: Any]?) -> Bool {
    (config?["matchSystemAppearance"] as? NSNumber)?.boolValue ?? false
}

func MACAutoSwitchThemeForAppearance(_ config: [AnyHashable: Any]?, _ isDark: Bool) -> String? {
    autoSwitchString(config?[isDark ? "darkThemeIdentifier" : "lightThemeIdentifier"])
}

func MACAutoSwitchResolveThemeIdentifier(_ config: [AnyHashable: Any]?, _ nowMinutes: Int, isDark: Bool) -> String? {
    guard (config?["enabled"] as? NSNumber)?.boolValue == true else { return nil }
    if MACAutoSwitchMatchesSystemAppearance(config) { return MACAutoSwitchThemeForAppearance(config, isDark) }
    return MACAutoSwitchResolveScheduleTheme(config?["scheduleRules"] as? [Any], nowMinutes)
}

func MACAutoSwitchPendingIdentifier(_ desired: String?, _ current: String?) -> String? {
    guard let desired = autoSwitchString(desired), desired != current else { return nil }
    return desired
}

func MACAutoSwitchLaunchThemeIdentifier(
    _ config: [AnyHashable: Any]?, _ nowMinutes: Int, _ storedIdentifier: String?, isDark: Bool
) -> String? {
    MACAutoSwitchResolveThemeIdentifier(config, nowMinutes, isDark: isDark) ?? autoSwitchString(storedIdentifier)
}

func MACAutoSwitchAppActionForState(_ ruleTheme: String?, _ activeOverride: String?) -> MACAppSwitchAction {
    if let ruleTheme = autoSwitchString(ruleTheme) { return ruleTheme == activeOverride ? .none : .applyOverride }
    return autoSwitchString(activeOverride) == nil ? .none : .revert
}

@MainActor
struct MACAutoSwitchEffects {
    static let shared = MACAutoSwitchEffects()

    var readPreference: (String) -> Any? = { MACPreferences.value(forKey: $0) }
    var writePreference: (Any?, String) -> Void = { MACPreferences.set($0, forKey: $1) }
    var synchronize: () -> Void = {
        CFPreferencesSynchronize(MACPreferences.domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
    }
    var currentMinute: () -> Int = MACAutoSwitchCurrentMinuteOfDay
    var fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    var apply: (String) -> Bool = { MACCursorActions.shared.applyTheme(atPath: $0) }
    var reset: () -> Bool = {
        do {
            try MACCursorActions.shared.resetAllCursors()
            return true
        } catch {
            print("App switch could not restore the system cursors: \(error.localizedDescription)")
            return false
        }
    }
    var applicationAppearance: () -> (hasOverride: Bool, effectiveIsDark: Bool)? = {
        guard let app = NSApp else { return nil }
        return (app.appearance != nil, app.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
    }
    var globalInterfaceStyle: () -> String? = {
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        return CFPreferencesCopyValue("AppleInterfaceStyle" as CFString, kCFPreferencesAnyApplication,
                                      kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? String
    }
    var postAppliedThemeChange: () -> Void = {
        DistributedNotificationCenter.default().postNotificationName(.MACAutoSwitchAppliedThemeDidChange,
                                                                     object: nil, userInfo: nil, deliverImmediately: true)
    }
    static func refreshWindowFrame(at point: NSPoint) -> NSRect {
        NSRect(x: point.x - 1, y: point.y - 1, width: 2, height: 2)
    }

    var showRefreshWindow: @MainActor () -> Void = {
        let window = NSWindow(contentRect: MACAutoSwitchEffects.refreshWindowFrame(at: NSEvent.mouseLocation),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = false
        window.level = .floating
        window.hasShadow = false
        window.orderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + MACCursorDefinitions.windowDismissDelay) { window.close() }
    }

    func readConfig() -> [AnyHashable: Any]? {
        synchronize()
        guard let data = readPreference(MACPreferences.autoSwitchRulesKey) as? Data else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [AnyHashable: Any]
    }

    func isSystemInDarkMode() -> Bool {
        if let appearance = applicationAppearance(), !appearance.hasOverride { return appearance.effectiveIsDark }
        return globalInterfaceStyle()?.caseInsensitiveCompare("dark") == .orderedSame
    }

    func forceVisualRefresh() {
        let show = showRefreshWindow
        DispatchQueue.main.async { show() }
        print("Forcing visual refresh via Invisible Window trick")
    }

    private func storedString(_ key: String) -> String? {
        autoSwitchString(readPreference(key))
    }

    @discardableResult
    func applyIfNeeded() -> Bool {
        let config = readConfig()
        let desired = MACAutoSwitchResolveThemeIdentifier(config, currentMinute(), isDark: isSystemInDarkMode())
        guard let pending = MACAutoSwitchPendingIdentifier(desired, storedString(MACPreferences.appliedCursorKey)) else { return false }
        let path = MACAutoSwitchThemePathForIdentifier(pending)
        guard fileExists(path) else {
            print("Auto-switch target \(pending) is missing on disk, keeping current cursor")
            return false
        }
        if storedString(MACPreferences.appOverrideKey) != nil {
            writePreference(pending, MACPreferences.appliedCursorKey)
            print("Auto-switch recorded \(pending) as the base theme, app override stays on screen")
            postAppliedThemeChange()
            return false
        }
        guard apply(path) else {
            print("Auto-switch failed to apply \(pending)")
            return false
        }
        writePreference(pending, MACPreferences.appliedCursorKey)
        print("Auto-switch applied \(pending)")
        postAppliedThemeChange()
        return true
    }

    func clearAppOverride() {
        writePreference(nil, MACPreferences.appOverrideKey)
        writePreference(nil, MACPreferences.appOverrideBaseKey)
    }

    func recoverBaseThemeIfNeeded() {
        if let snapshot = storedString(MACPreferences.appOverrideBaseKey) {
            writePreference(snapshot, MACPreferences.appliedCursorKey)
            print("Recovered base theme \(snapshot) after an interrupted app override")
        }
        clearAppOverride()
    }

    private func applyIdentifierIfOnDisk(_ identifier: String) -> Bool {
        let path = MACAutoSwitchThemePathForIdentifier(identifier)
        guard fileExists(path) else {
            print("App-switch target \(identifier) is missing on disk, keeping current cursor")
            return false
        }
        guard apply(path) else {
            print("App-switch failed to apply \(identifier)")
            return false
        }
        return true
    }

    func handleFrontmostApp(_ bundleID: String?) {
        guard !MACMenuBarIsHelperBundleIdentifier(bundleID) else { return }
        let config = readConfig()
        let ruleTheme = MACAutoSwitchThemeForBundleID(config, bundleID)
        let activeOverride = storedString(MACPreferences.appOverrideKey)
        switch MACAutoSwitchAppActionForState(ruleTheme, activeOverride) {
        case .none:
            return
        case .applyOverride:
            guard let ruleTheme else { return }
            let base = storedString(MACPreferences.appOverrideBaseKey) ?? storedString(MACPreferences.appliedCursorKey)
            if let base { writePreference(base, MACPreferences.appOverrideBaseKey) }
            guard applyIdentifierIfOnDisk(ruleTheme) else {
                if activeOverride == nil { writePreference(nil, MACPreferences.appOverrideBaseKey) }
                return
            }
            writePreference(base, MACPreferences.appliedCursorKey)
            writePreference(ruleTheme, MACPreferences.appOverrideKey)
            print("App switch applied \(ruleTheme) for \(bundleID ?? "")")
            forceVisualRefresh()
        case .revert:
            let stored = storedString(MACPreferences.appOverrideBaseKey) ?? storedString(MACPreferences.appliedCursorKey)
            let desired = MACAutoSwitchLaunchThemeIdentifier(config, currentMinute(), stored, isDark: isSystemInDarkMode())
            if let desired {
                guard applyIdentifierIfOnDisk(desired) else { return }
                print("App switch reverted to \(desired)")
            } else {
                guard reset() else { return }
                print("App switch reverted to the system cursors")
            }
            clearAppOverride()
            forceVisualRefresh()
        }
        postAppliedThemeChange()
    }
}

@MainActor
final class MACAutoSwitchScheduleTimer {
    private let effects: MACAutoSwitchEffects
    private var timer: DispatchSourceTimer?
    private var observers: [NSObjectProtocol] = []

    init(effects: MACAutoSwitchEffects = .shared) {
        self.effects = effects
    }

    func start() {
        guard observers.isEmpty else { return }
        for name in [Notification.Name.NSSystemClockDidChange, .NSSystemTimeZoneDidChange] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                NSTimeZone.resetSystemTimeZone()
                MainActor.assumeIsolated { self?.boundaryReached() }
            })
        }
        reschedule()
    }

    func reschedule() {
        timer?.cancel()
        timer = nil
        guard let next = MACAutoSwitchNextBoundaryDate(effects.readConfig(), after: Date()) else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(wallDeadline: .now() + next.timeIntervalSinceNow, leeway: .seconds(5))
        timer.setEventHandler { [weak self, weak timer] in
            MainActor.assumeIsolated {
                guard let self, let timer, self.timer === timer else { return }
                self.boundaryReached()
            }
        }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
    }

    private func boundaryReached() {
        if effects.applyIfNeeded() { effects.forceVisualRefresh() }
        reschedule()
    }
}
