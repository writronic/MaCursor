import AppKit
import IOKit.ps
import IOKit.pwr_mgt
import SystemConfiguration

@MainActor
final class CursorShakerController {
    @MainActor
    struct Effects {
        var idle: () -> TimeInterval = {
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        }
        var now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
        var consoleUser: () -> String? = { SCDynamicStoreCopyConsoleUser(nil, nil, nil) as String? }
        var hold: () -> IOPMAssertionID? = {
            var id = IOPMAssertionID(0)
            let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                                     IOPMAssertionLevel(kIOPMAssertionLevelOn), "Cursor Shaker" as CFString, &id)
            return result == kIOReturnSuccess ? id : nil
        }
        var release: (IOPMAssertionID) -> Void = { IOPMAssertionRelease($0) }
        var post: (CGEvent) -> Void = { $0.post(tap: .cghidEventTap) }
        var front: () -> String? = { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }
        var pointerOwner: () -> String? = {
            let number = NSWindow.windowNumber(at: NSEvent.mouseLocation, belowWindowWithWindowNumber: 0)
            guard number > 0, let info = (CGWindowListCopyWindowInfo(.optionIncludingWindow, CGWindowID(number)) as? [[String: Any]])?.first,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t else { return nil }
            return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        }
        var date: () -> Date = { Date() }
        var battery: () -> (onBattery: Bool, percent: Int)? = {
            guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
                  let source = (IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef])?.first,
                  let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { return nil }
            let providing = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
            return (providing == kIOPSBatteryPowerValue, current * 100 / maximum)
        }
        var turnOff: () -> Void = { CursorShakerConfig.setEnabled(false) }
        var nextTab: @MainActor () -> Void = { if let key = CursorShaker.nextTab { CursorGestureKeys.press(key) } }
        var brightness: @MainActor (CursorGestureOperation) -> Void = { if let key = CursorGestureKeys.mediaKey(for: $0) { CursorGestureKeys.pressMedia(key) } }
        var level: () -> Double? = {
            guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
                  let symbol = dlsym(handle, "DisplayServicesGetBrightness") else { return nil }
            let get = unsafeBitCast(symbol, to: (@convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32).self)
            var count: UInt32 = 0
            guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
            var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
            guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return nil }
            return displays.prefix(Int(count)).compactMap { display -> Double? in
                var brightness: Float = 0
                return get(display, &brightness) == 0 ? min(max(Double(brightness), 0), 1) : nil
            }.min()
        }
    }

    var effects: Effects
    private let source = CGEventSource(stateID: .combinedSessionState)
    private var config = CursorShakerConfig()
    private var trusted = false
    private var pauses: Set<CursorShakerPause> = []
    private var timer: DispatchSourceTimer?
    private var lastBurst: TimeInterval?
    private var lastTab: TimeInterval?
    private var scrolls = 0
    private(set) var assertion: IOPMAssertionID?
    private(set) var dimmed: Int?

    init(effects: Effects = Effects()) {
        self.effects = effects
        let centers: [(NotificationCenter, [Notification.Name])] = [
            (NSWorkspace.shared.notificationCenter, Array(CursorShaker.workspacePauses.keys)),
            (DistributedNotificationCenter.default(), Array(CursorShaker.distributedPauses.keys)),
        ]
        for (center, names) in centers {
            for name in names {
                _ = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                    let name = note.name
                    MainActor.assumeIsolated { self?.noted(name) }
                }
            }
        }
    }

    var wantsTrust: Bool { config.enabled }
    var isRunning: Bool { timer != nil }

    func sync(trusted: Bool, config latest: CursorShakerConfig = CursorShakerConfig.load()) {
        let changed = latest != config
        self.trusted = trusted
        config = latest
        let wanted = latest.enabled && trusted
        guard changed || wanted != isRunning else { return }
        if wanted {
            start()
        } else {
            stop()
        }
    }

    func start() {
        stop()
        guard CursorShaker.mayRun(enabled: config.enabled, pauses: pauses, consoleUser: effects.consoleUser(), user: NSUserName()) else { return }
        guard !endedItself() else { return }
        assertion = effects.hold()
        lastBurst = nil
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.tick() } }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
        if let assertion { effects.release(assertion) }
        assertion = nil
        if dimmed != nil { brighten() }
    }

    func tick() {
        guard trusted else { return }
        guard !endedItself() else { return }
        let idle = effects.idle()
        let sinceBurst = lastBurst.map { effects.now() - $0 } ?? .infinity
        if dimmed != nil && CursorShaker.userBack(idle: idle, sinceBurst: sinceBurst) { brighten() }
        guard CursorShaker.due(idle: idle, sinceBurst: sinceBurst, period: TimeInterval(config.period)) else { return }
        nudge()
        if config.click != .off || config.scroll != .off || config.switchTabs,
           CursorShaker.mayClickOrScroll(front: effects.front(), pointer: effects.pointerOwner()) {
            if let point = CGEvent(source: nil)?.location {
                if config.click != .off { click(at: point) }
                if config.scroll != .off { scroll() }
            }
            if config.switchTabs && CursorShaker.tabDue(lastTab: lastTab, now: effects.now()) {
                effects.nextTab()
                lastTab = effects.now()
            }
        }
        if config.dim && dimmed == nil {
            let steps = CursorShaker.dimCount(level: effects.level())
            dimmed = steps
            for _ in 0..<steps { effects.brightness(.brightnessDown) }
        }
        lastBurst = effects.now()
    }

    private func brighten() {
        let steps = dimmed ?? 0
        dimmed = nil
        for _ in 0..<steps { effects.brightness(.brightnessUp) }
    }

    private func endedItself() -> Bool {
        if !CursorShaker.expired(endTime: config.endTime, now: effects.date()) {
            guard config.batteryStop, let battery = effects.battery(),
                  CursorShaker.batteryStops(onBattery: battery.onBattery, percent: battery.percent) else { return false }
        }
        stop()
        config.enabled = false
        effects.turnOff()
        return true
    }

    private func nudge() {
        guard let point = CGEvent(source: nil)?.location else { return }
        for at in [CGPoint(x: point.x + 1, y: point.y), point] {
            send(CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: at, mouseButton: .left))
        }
    }

    private func click(at point: CGPoint) {
        let (types, button): ([CGEventType], CGMouseButton) = config.click == .right ? ([.rightMouseDown, .rightMouseUp], .right) : ([.leftMouseDown, .leftMouseUp], .left)
        for type in types {
            send(CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: button))
        }
    }

    private func scroll() {
        send(CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 1, wheel1: CursorShaker.scrollDelta(config.scroll, turn: scrolls), wheel2: 0, wheel3: 0))
        scrolls += 1
    }

    private func send(_ event: CGEvent?) {
        guard let event else { return }
        event.setIntegerValueField(.eventSourceUserData, value: CursorShaker.marker)
        effects.post(event)
    }

    private func noted(_ name: Notification.Name) {
        let before = pauses
        pauses = CursorShaker.paused(pauses, after: name)
        guard pauses != before else { return }
        if !pauses.isEmpty {
            stop()
        } else if config.enabled && trusted {
            start()
        }
    }
}
