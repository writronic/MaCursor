import Foundation

enum ScheduleRole: String, Codable, CaseIterable, Identifiable {
    case day
    case night

    var id: String { rawValue }

    var label: String {
        switch self {
        case .day:   return String(localized: "Day mode")
        case .night: return String(localized: "Night mode")
        }
    }

    var icon: String {
        switch self {
        case .day:   return "sun.max.fill"
        case .night: return "moon.fill"
        }
    }

    var defaultMinutes: Int {
        switch self {
        case .day:   return 420
        case .night: return 1140
        }
    }
}

enum AppearanceRole: String, CaseIterable, Identifiable {
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .light: return String(localized: "Light Appearance")
        case .dark:  return String(localized: "Dark Appearance")
        }
    }

    var icon: String {
        switch self {
        case .light: return "sun.max.fill"
        case .dark:  return "moon.fill"
        }
    }
}

struct ScheduleRule: Identifiable, Codable, Hashable {
    let id: UUID
    var themeIdentifier: String?
    var startMinutes: Int
    var role: ScheduleRole?

    init(id: UUID = UUID(), themeIdentifier: String? = nil, startMinutes: Int = 0, role: ScheduleRole? = nil) {
        self.id = id
        self.themeIdentifier = themeIdentifier
        self.startMinutes = startMinutes
        self.role = role
    }

}

enum TimeOfDay {
    static let minutesPerDay = 1440

    static func clamp(_ minutes: Int) -> Int {
        min(max(minutes, 0), minutesPerDay - 1)
    }

    static func hour24(fromMinutes minutes: Int) -> Int {
        clamp(minutes) / 60
    }

    static func minute(fromMinutes minutes: Int) -> Int {
        clamp(minutes) % 60
    }

    static func hour12(fromMinutes minutes: Int) -> Int {
        let hour = hour24(fromMinutes: minutes) % 12
        return hour == 0 ? 12 : hour
    }

    static func isAfternoon(minutes: Int) -> Bool {
        hour24(fromMinutes: minutes) >= 12
    }

    static func minutes(hour24: Int, minute: Int) -> Int {
        clamp((hour24 % 24) * 60 + (minute % 60))
    }

    static func minutes(hour12: Int, minute: Int, afternoon: Bool) -> Int {
        let normalized = hour12 % 12
        return minutes(hour24: normalized + (afternoon ? 12 : 0), minute: minute)
    }

    static func resolvedNonColliding(_ desired: Int, avoiding other: Int) -> Int {
        let target = clamp(desired)
        guard target == clamp(other) else { return target }
        return (target + 1) % minutesPerDay
    }

    static func amSymbol(locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        let symbol = formatter.amSymbol ?? ""
        return symbol.isEmpty ? "AM" : symbol
    }

    static func pmSymbol(locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        let symbol = formatter.pmSymbol ?? ""
        return symbol.isEmpty ? "PM" : symbol
    }
}

struct AppRule: Identifiable, Codable, Hashable {
    let id: UUID
    var themeIdentifier: String?
    var bundleIdentifier: String?
    var displayName: String?

    init(id: UUID = UUID(), themeIdentifier: String? = nil, bundleIdentifier: String? = nil, displayName: String? = nil) {
        self.id = id
        self.themeIdentifier = themeIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
    }
}

struct AutoSwitchConfig: Codable {
    var enabled: Bool
    var use24HourTime: Bool
    var matchSystemAppearance: Bool
    var switchByApp: Bool
    var lightThemeIdentifier: String?
    var darkThemeIdentifier: String?
    var scheduleRules: [ScheduleRule]
    var appRules: [AppRule]

    init(enabled: Bool = false,
         use24HourTime: Bool = AutoSwitchConfig.systemPrefers24HourTime(),
         matchSystemAppearance: Bool = false,
         switchByApp: Bool = false,
         lightThemeIdentifier: String? = nil,
         darkThemeIdentifier: String? = nil,
         scheduleRules: [ScheduleRule] = [],
         appRules: [AppRule] = []) {
        self.enabled = enabled
        self.use24HourTime = use24HourTime
        self.matchSystemAppearance = matchSystemAppearance
        self.switchByApp = switchByApp
        self.lightThemeIdentifier = lightThemeIdentifier
        self.darkThemeIdentifier = darkThemeIdentifier
        self.scheduleRules = scheduleRules
        self.appRules = appRules
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        use24HourTime = try container.decodeIfPresent(Bool.self, forKey: .use24HourTime)
            ?? AutoSwitchConfig.systemPrefers24HourTime()
        matchSystemAppearance = try container.decodeIfPresent(Bool.self, forKey: .matchSystemAppearance) ?? false
        switchByApp = try container.decodeIfPresent(Bool.self, forKey: .switchByApp) ?? false
        lightThemeIdentifier = try container.decodeIfPresent(String.self, forKey: .lightThemeIdentifier)
        darkThemeIdentifier = try container.decodeIfPresent(String.self, forKey: .darkThemeIdentifier)
        scheduleRules = try container.decodeIfPresent([ScheduleRule].self, forKey: .scheduleRules) ?? []
        appRules = try container.decodeIfPresent([AppRule].self, forKey: .appRules) ?? []
    }

    static func systemPrefers24HourTime(locale: Locale = .current) -> Bool {
        let template = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale) ?? "h"
        return !template.contains("a")
    }

    func rule(for role: ScheduleRole) -> ScheduleRule {
        if let match = scheduleRules.first(where: { $0.role == role }) {
            return match
        }

        let unassigned = scheduleRules
            .filter { $0.role == nil }
            .sorted { $0.startMinutes < $1.startMinutes }
        let index = (role == .day) ? 0 : 1
        if index < unassigned.count {
            var migrated = unassigned[index]
            migrated.role = role
            return migrated
        }

        return ScheduleRule(startMinutes: role.defaultMinutes, role: role)
    }

    mutating func setRule(_ newRule: ScheduleRule, for role: ScheduleRole) {
        var day = rule(for: .day)
        var night = rule(for: .night)

        var updated = newRule
        updated.role = role
        if role == .day {
            day = updated
        } else {
            night = updated
        }

        day.role = .day
        night.role = .night
        scheduleRules = [day, night]
    }

    mutating func normalize() {
        var day = rule(for: .day)
        var night = rule(for: .night)
        day.role = .day
        night.role = .night
        day.startMinutes = TimeOfDay.clamp(day.startMinutes)
        night.startMinutes = TimeOfDay.resolvedNonColliding(night.startMinutes,
                                                            avoiding: day.startMinutes)
        scheduleRules = [day, night]

        var seenBundles = Set<String>()
        appRules = appRules.filter { rule in
            guard let bundle = rule.bundleIdentifier, !bundle.isEmpty else { return false }
            return seenBundles.insert(bundle).inserted
        }
    }

    func appRule(forBundleIdentifier bundleIdentifier: String) -> AppRule? {
        appRules.first { $0.bundleIdentifier == bundleIdentifier }
    }

    mutating func setAppRule(_ newRule: AppRule) {
        if let index = appRules.firstIndex(where: { $0.id == newRule.id }) {
            appRules[index] = newRule
        } else {
            appRules.append(newRule)
        }
    }

    mutating func removeAppRule(id: UUID) {
        appRules.removeAll { $0.id == id }
    }

    static func counterpart(of role: ScheduleRole) -> ScheduleRole {
        role == .day ? .night : .day
    }

    func themeIdentifier(for role: AppearanceRole) -> String? {
        role == .light ? lightThemeIdentifier : darkThemeIdentifier
    }

    mutating func setThemeIdentifier(_ identifier: String?, for role: AppearanceRole) {
        if role == .light {
            lightThemeIdentifier = identifier
        } else {
            darkThemeIdentifier = identifier
        }
    }

    mutating func seedAppearanceThemesIfNeeded() {
        guard lightThemeIdentifier == nil, darkThemeIdentifier == nil else { return }
        lightThemeIdentifier = rule(for: .day).themeIdentifier
        darkThemeIdentifier = rule(for: .night).themeIdentifier
    }

    @discardableResult
    mutating func setTime(_ minutes: Int, for role: ScheduleRole) -> Bool {
        let otherMinutes = rule(for: AutoSwitchConfig.counterpart(of: role)).startMinutes
        let resolved = TimeOfDay.resolvedNonColliding(minutes, avoiding: otherMinutes)

        var target = rule(for: role)
        target.startMinutes = resolved
        setRule(target, for: role)

        return resolved != TimeOfDay.clamp(minutes)
    }

    static func load() -> AutoSwitchConfig {
        guard let data = MACPreferences.value(forKey: MACPreferences.autoSwitchRulesKey) as? Data,
              var decoded = try? JSONDecoder().decode(AutoSwitchConfig.self, from: data) else {
            var fresh = AutoSwitchConfig()
            fresh.normalize()
            return fresh
        }
        decoded.normalize()
        return decoded
    }

    func save() {
        var normalized = self
        normalized.normalize()
        guard let data = try? JSONEncoder().encode(normalized) else { return }
        MACPreferences.set(data, forKey: MACPreferences.autoSwitchRulesKey)
        NotificationCenter.default.post(name: .macAutoSwitchConfigDidChange, object: nil)
        AutoSwitchConfig.notifyHelper()
    }

    static func notifyHelper() {
        DistributedNotificationCenter.default().postNotificationName(
            .MACAutoSwitchDidChange,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }
}

extension Notification.Name {
    static let macAutoSwitchConfigDidChange = Notification.Name("MACAutoSwitchConfigDidChangeLocally")
}
