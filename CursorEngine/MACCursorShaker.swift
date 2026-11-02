import AppKit

extension Notification.Name {
    nonisolated static let MACCursorShakerDidChange = Notification.Name("MACCursorShakerDidChange")
}

struct CursorShakerConfig: Codable, Equatable {
    static let periods = [10, 30, 60, 300]
    static let defaultPeriod = 60

    var enabled = false
    var period = CursorShakerConfig.defaultPeriod
    var click = CursorShakerClick.off
    var scroll = CursorShakerScroll.off
    var stopAfter: Int?
    var endTime: Date?
    var batteryStop = false
    var shortcut: KeyboardShortcutData?
    var switchTabs = false
    var dim = false

    static let stopTimes = [15, 30, 60, 120, 240, 480]

    mutating func turn(_ on: Bool, at now: Date) {
        enabled = on
        endTime = on ? stopAfter.map { now.addingTimeInterval(TimeInterval($0 * 60)) } : nil
    }

    mutating func stop(after minutes: Int?, at now: Date) {
        stopAfter = minutes
        turn(enabled, at: now)
    }

    static func stopLabel(_ minutes: Int) -> String {
        Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    static func setStopAfter(_ minutes: Int?) {
        var config = load()
        config.stop(after: minutes, at: Date())
        config.save()
    }

    static func load() -> CursorShakerConfig {
        CFPreferencesSynchronize(MACPreferences.domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        guard let data = MACPreferences.value(forKey: MACPreferences.cursorShakerKey) as? Data,
              let config = try? JSONDecoder().decode(CursorShakerConfig.self, from: data) else { return CursorShakerConfig() }
        return config
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        MACPreferences.set(data, forKey: MACPreferences.cursorShakerKey)
        CursorShakerConfig.notifyHelper()
    }

    static func notifyHelper() {
        DistributedNotificationCenter.default().postNotificationName(.MACCursorShakerDidChange, object: nil,
                                                                     userInfo: nil, deliverImmediately: true)
    }

    static func setEnabled(_ enabled: Bool) {
        var config = load()
        guard config.enabled != enabled else { return }
        config.turn(enabled, at: Date())
        config.save()
    }
}

extension CursorShakerConfig {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = (try? container.decode(Bool.self, forKey: .enabled)) ?? false
        let period = (try? container.decode(Int.self, forKey: .period)) ?? Self.defaultPeriod
        self.period = Self.periods.contains(period) ? period : Self.defaultPeriod
        click = (try? container.decode(CursorShakerClick.self, forKey: .click)) ?? .off
        scroll = (try? container.decode(CursorShakerScroll.self, forKey: .scroll)) ?? .off
        stopAfter = (try? container.decode(Int.self, forKey: .stopAfter)).flatMap { Self.stopTimes.contains($0) ? $0 : nil }
        endTime = stopAfter == nil ? nil : try? container.decode(Date.self, forKey: .endTime)
        batteryStop = (try? container.decode(Bool.self, forKey: .batteryStop)) ?? false
        shortcut = try? container.decode(KeyboardShortcutData.self, forKey: .shortcut)
        switchTabs = (try? container.decode(Bool.self, forKey: .switchTabs)) ?? false
        dim = (try? container.decode(Bool.self, forKey: .dim)) ?? false
    }
}

enum CursorShakerClick: String, Codable, CaseIterable {
    case off, left, right
}

enum CursorShakerScroll: String, Codable, CaseIterable {
    case off, down, downAndUp
}

enum CursorShakerPause: Sendable {
    case locked, screenSaver, screensAsleep, asleep, away
}

enum CursorShaker {
    static let marker: Int64 = 0x4D_6143_5368
    static let backMargin: TimeInterval = 1
    static let hotKeyID = UInt32.max
    static let tabGap: TimeInterval = 60
    static let dimSteps = 4
    static let levelSteps = 16.0
    static let nextTab: CursorGestureShortcut? = CursorGestures.actions.lazy.compactMap { action -> CursorGestureShortcut? in
        guard action.id == "nextTab", case .shortcut(let key) = action.kind else { return nil }
        return key
    }.first

    static func tabDue(lastTab: TimeInterval?, now: TimeInterval) -> Bool {
        lastTab.map { now - $0 >= tabGap } ?? true
    }

    static func dimCount(level: Double?) -> Int {
        guard let level else { return dimSteps }
        return min(dimSteps, Int((min(max(level, 0), 1) * levelSteps).rounded(.down)))
    }

    static func expired(endTime: Date?, now: Date) -> Bool {
        endTime.map { now >= $0 } ?? false
    }

    static func batteryStops(onBattery: Bool, percent: Int) -> Bool {
        onBattery && percent <= 20
    }

    static let workspacePauses: [Notification.Name: (pause: CursorShakerPause, starts: Bool)] = [
        NSWorkspace.screensDidSleepNotification: (.screensAsleep, true),
        NSWorkspace.screensDidWakeNotification: (.screensAsleep, false),
        NSWorkspace.willSleepNotification: (.asleep, true),
        NSWorkspace.didWakeNotification: (.asleep, false),
        NSWorkspace.sessionDidResignActiveNotification: (.away, true),
        NSWorkspace.sessionDidBecomeActiveNotification: (.away, false),
    ]

    static let distributedPauses: [Notification.Name: (pause: CursorShakerPause, starts: Bool)] = [
        Notification.Name("com.apple.screenIsLocked"): (.locked, true),
        Notification.Name("com.apple.screenIsUnlocked"): (.locked, false),
        Notification.Name("com.apple.screensaver.didstart"): (.screenSaver, true),
        Notification.Name("com.apple.screensaver.didstop"): (.screenSaver, false),
    ]

    static func posted(_ event: NSEvent) -> Bool {
        event.cgEvent?.getIntegerValueField(.eventSourceUserData) == marker
    }

    static func due(idle: TimeInterval, sinceBurst: TimeInterval, period: TimeInterval) -> Bool {
        idle >= period && sinceBurst >= period
    }

    static func userBack(idle: TimeInterval, sinceBurst: TimeInterval) -> Bool {
        idle + backMargin < sinceBurst
    }

    static func paused(_ pauses: Set<CursorShakerPause>, after name: Notification.Name) -> Set<CursorShakerPause> {
        guard let change = workspacePauses[name] ?? distributedPauses[name] else { return pauses }
        return change.starts ? pauses.union([change.pause]) : pauses.subtracting([change.pause])
    }

    static func mayRun(enabled: Bool, pauses: Set<CursorShakerPause>, consoleUser: String?, user: String) -> Bool {
        enabled && pauses.isEmpty && consoleUser == user
    }

    static func mayClickOrScroll(front: String?, pointer: String?) -> Bool {
        [front, pointer].allSatisfy { app in
            guard let app else { return false }
            return ![MACAppBundleIdentifier, MACHelperBundleIdentifier, "com.apple.loginwindow"].contains(app) && !app.hasPrefix("com.apple.ScreenSaver.Engine")
        }
    }

    static func scrollDelta(_ scroll: CursorShakerScroll, turn: Int) -> Int32 {
        switch scroll {
        case .off: 0
        case .down: -48
        case .downAndUp: turn.isMultiple(of: 2) ? -48 : 48
        }
    }
}
