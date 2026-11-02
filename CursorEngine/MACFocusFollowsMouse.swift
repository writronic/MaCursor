import AppKit
import ApplicationServices

extension Notification.Name {
    nonisolated static let MACFocusFollowsMouseDidChange = Notification.Name("MACFocusFollowsMouseDidChange")
    nonisolated static let MACFocusFollowsMouseStatusDidChange = Notification.Name("MACFocusFollowsMouseStatusDidChange")
}

let MACFFMTrustPollInterval: TimeInterval = 2
let MACFFMDefaultDelayMs = 100
let MACFFMMaxDelayMs = 1000
let MACFFMMovementThreshold: CGFloat = 2
let MACFFMRecentRaiseWindow: TimeInterval = 1
let MACFFMSameWindowDebounce: TimeInterval = 0.5
let MACFFMGestureCooldown: TimeInterval = 0.3
let MACFFMSpaceChangeCooldown: TimeInterval = 1
let MACFFMMessagingTimeout: Float = 0.5
let MACFFMRaiseRetries = 3
let MACFFMRaiseRetryInterval: TimeInterval = 0.05

typealias MACFFMWindow = (window: AXUIElement, owner: NSRunningApplication)

struct MACFFMDecisionInputs: Sendable {
    var disableModifierHeld = false
    var mouseButtonDown = false
    var spaceChangeCooldownActive = false
    var gestureCooldownActive = false
    var frontmostIsDock = false
    var frontmostIsStayFocused = false
    var candidateAlreadyFocused = false
    var candidateIsChildOfFocused = false
    var sameWindowRecentlyRaised = false
    var strokeInProgress = false
}

enum MACFFMTrustAction: Sendable {
    case keep, start, stop
}

func MACFFMReadConfig() -> [String: Any]? {
    CFPreferencesSynchronize(MACPreferences.domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
    guard let data = MACPreferences.value(forKey: MACPreferences.focusFollowsMouseKey) as? Data else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
}

func MACFFMEnabled(_ config: [String: Any]?) -> Bool {
    (config?["enabled"] as? NSNumber)?.boolValue ?? false
}

func MACFFMDelayMs(_ config: [String: Any]?) -> Int {
    guard let value = config?["delayMs"] as? NSNumber,
          CFGetTypeID(value) != CFBooleanGetTypeID() else { return MACFFMDefaultDelayMs }
    return min(max(value.intValue, 0), MACFFMMaxDelayMs)
}

func MACFFMDisableModifierFlag(_ config: [String: Any]?) -> UInt {
    switch (config?["disableModifier"] as? String)?.lowercased() {
    case "off": return 0
    case "option": return NSEvent.ModifierFlags.option.rawValue
    default: return NSEvent.ModifierFlags.control.rawValue
    }
}

func MACFFMIgnoreSpaceChange(_ config: [String: Any]?) -> Bool {
    (config?["ignoreSpaceChange"] as? NSNumber)?.boolValue ?? false
}

private func usableStringList(_ candidate: Any?) -> [String]? {
    (candidate as? [Any])?.compactMap { value in
        guard let string = value as? String, !string.isEmpty else { return nil }
        return string
    }
}

func MACFFMIgnoreBundleIdentifiers(_ config: [String: Any]?) -> [String] {
    usableStringList(config?["ignoreBundleIdentifiers"]) ?? []
}

func MACFFMStayFocusedBundleIdentifiers(_ config: [String: Any]?) -> [String] {
    usableStringList(config?["stayFocusedBundleIdentifiers"]) ?? ["com.apple.SecurityAgent"]
}

func MACFFMBuiltInIgnoreBundleIdentifiers() -> [String] {
    ["com.apple.dock", "com.apple.notificationcenterui", "com.apple.controlcenter",
     "com.apple.WindowManager", "com.apple.Spotlight", "com.writronic.MaCursor", "com.writronic.macursor.helper"]
}

func MACFFMConvertToAXPoint(_ cocoaPoint: CGPoint, _ primaryScreenHeight: CGFloat) -> CGPoint {
    CGPoint(x: cocoaPoint.x, y: primaryScreenHeight - cocoaPoint.y)
}

func MACFFMRoleIsWindowLike(_ role: String?) -> Bool {
    role == "AXWindow" || role == "AXSheet" || role == "AXDrawer"
}

func MACFFMRoleIsAcceptable(_ role: String?, _ subrole: String?) -> Bool {
    MACFFMRoleIsWindowLike(role) && subrole != "AXDesktop"
}

func MACFFMRoleIsMenuOrDock(_ role: String?) -> Bool {
    ["AXDockItem", "AXMenuItem", "AXMenu", "AXMenuBar", "AXMenuBarItem"].contains(role ?? "")
}

func MACFFMBundleListContains(_ list: [String]?, _ bundleID: String?) -> Bool {
    guard let bundleID, !bundleID.isEmpty else { return false }
    return list?.contains { $0.caseInsensitiveCompare(bundleID) == .orderedSame } ?? false
}

func MACFFMMovementExceedsThreshold(_ previous: CGPoint, _ current: CGPoint, _ threshold: CGFloat) -> Bool {
    let dx = current.x - previous.x
    let dy = current.y - previous.y
    return dx * dx + dy * dy >= threshold * threshold
}

func MACFFMWithinInterval(_ earlier: TimeInterval, _ now: TimeInterval, _ window: TimeInterval) -> Bool {
    earlier > 0 && now - earlier >= 0 && now - earlier <= window
}

func MACFFMTrustActionFor(_ enabled: Bool, _ running: Bool, _ trusted: Bool) -> MACFFMTrustAction {
    if running && (!trusted || !enabled) { return .stop }
    if !running && enabled && trusted { return .start }
    return .keep
}

func MACFFMShouldPollForTrust(_ enabled: Bool, _ strokesEnabled: Bool, _ trusted: Bool) -> Bool {
    enabled || strokesEnabled
}

func MACFFMShouldSkip(_ inputs: MACFFMDecisionInputs) -> Bool {
    inputs.disableModifierHeld || inputs.mouseButtonDown || inputs.spaceChangeCooldownActive ||
    inputs.gestureCooldownActive || inputs.frontmostIsDock || inputs.frontmostIsStayFocused ||
    inputs.candidateAlreadyFocused || inputs.candidateIsChildOfFocused || inputs.sameWindowRecentlyRaised ||
    inputs.strokeInProgress
}

func MACFFMShouldRaise(_ inputs: MACFFMDecisionInputs, retrying: Bool) -> Bool {
    var inputs = inputs
    if retrying { inputs.sameWindowRecentlyRaised = false }
    return !MACFFMShouldSkip(inputs)
}

func MACFFMRetryDelay(raised: Bool, retriesLeft: Int) -> TimeInterval? {
    raised && retriesLeft > 0 ? MACFFMRaiseRetryInterval : nil
}

@MainActor
final class MACFocusFollowsMouseController {
    @MainActor
    struct Effects {
        var readConfig: () -> [String: Any]? = MACFFMReadConfig
        var now: () -> TimeInterval = { Date.timeIntervalSinceReferenceDate }
        var createSystemWide: () -> AXUIElement? = {
            let element = AXUIElementCreateSystemWide()
            AXUIElementSetMessagingTimeout(element, MACFFMMessagingTimeout)
            return element
        }
        var addMonitor: (@escaping @MainActor (Bool, CGPoint) -> Void) -> Any? = { handler in
            let events: NSEvent.EventTypeMask = [.mouseMoved, .scrollWheel]
            let forward: (NSEvent) -> Void = { event in
                guard !CursorShaker.posted(event) else { return }
                let scrolling = event.type == .scrollWheel
                MainActor.assumeIsolated { handler(scrolling, NSEvent.mouseLocation) }
            }
            return [NSEvent.addGlobalMonitorForEvents(matching: events, handler: forward),
                    NSEvent.addLocalMonitorForEvents(matching: events) { event in
                        forward(event)
                        return event
                    }].compactMap { $0 }
        }
        var removeMonitor: (Any) -> Void = { ($0 as? [Any])?.forEach(NSEvent.removeMonitor) }
        var schedule: (TimeInterval, TimeInterval?, TimeInterval, @escaping @MainActor () -> Void) -> (() -> Void) = { delay, interval, leeway, handler in
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(deadline: .now() + delay, repeating: interval.map { .nanoseconds(Int($0 * 1_000_000_000)) } ?? .never,
                           leeway: .nanoseconds(Int(leeway * 1_000_000_000)))
            timer.setEventHandler { MainActor.assumeIsolated { handler() } }
            timer.resume()
            return { timer.cancel() }
        }
        var persistTrust: (Bool) -> Void = { trusted in
            let stored = MACPreferences.value(forKey: MACPreferences.ffmAccessibilityTrustedKey) as? NSNumber
            guard stored?.boolValue != trusted else { return }
            MACPreferences.setFlag(trusted, forKey: MACPreferences.ffmAccessibilityTrustedKey)
            DistributedNotificationCenter.default().postNotificationName(
                .MACFocusFollowsMouseStatusDidChange, object: nil, userInfo: nil, deliverImmediately: true)
            print("Focus follows mouse Accessibility access is now \(trusted ? "granted" : "missing")")
        }
    }

    private let trustCheck: @MainActor () -> Bool
    private let effects: Effects
    private var mouseMonitor: Any?
    private var monitorID: UUID?
    private var systemWideElement: AXUIElement?
    private var activeConfig: [String: Any]?
    private var dwellTimer: (id: UUID, cancel: () -> Void)?
    private var trustPollTimer: (id: UUID, cancel: () -> Void)?
    private var dwellAnchor: CGPoint?
    private var lastGestureTime: TimeInterval = 0
    private var lastSpaceChangeTime: TimeInterval = 0
    private var lastRaisedWindowHash: CFHashCode = 0
    private var lastRaisedWindowTime: TimeInterval = 0
    private var lastRaiseTime: TimeInterval = 0
    private var lastRaiseBundleID: String?
    private var configEnabled = false
    private(set) var lastTrusted = false
    var strokesEnabled: @MainActor () -> Bool = { false }
    var strokeInProgress: @MainActor () -> Bool = { false }
    var trustSynced: @MainActor (Bool) -> Void = { _ in }
    var trustWillCheck: @MainActor () -> Void = {}

    init(trustCheck: @escaping @MainActor () -> Bool, effects: Effects = Effects()) {
        self.trustCheck = trustCheck
        self.effects = effects
    }

    var isRunning: Bool { mouseMonitor != nil }

    func noteRaise(_ bundleID: String?, at timestamp: TimeInterval) {
        lastRaiseTime = timestamp
        lastRaiseBundleID = bundleID
    }

    func consumeRecentRaise(_ bundleID: String?, at now: TimeInterval) -> Bool {
        guard MACFFMWithinInterval(lastRaiseTime, now, MACFFMRecentRaiseWindow) else { return false }
        if let previous = lastRaiseBundleID, !previous.isEmpty,
           let bundleID, !bundleID.isEmpty, previous != bundleID { return false }
        lastRaiseTime = 0
        lastRaiseBundleID = nil
        return true
    }

    func consumeRecentRaise(_ bundleID: String?) -> Bool {
        consumeRecentRaise(bundleID, at: effects.now())
    }

    func noteSpaceChange() {
        lastSpaceChangeTime = effects.now()
    }

    func cancelPendingRaise() {
        dwellTimer?.cancel()
        dwellTimer = nil
    }

    private func stopTrustPoll() {
        trustPollTimer?.cancel()
        trustPollTimer = nil
    }

    private func updateTrustPoll(_ trusted: Bool) {
        guard MACFFMShouldPollForTrust(configEnabled, strokesEnabled(), trusted) else {
            stopTrustPoll()
            return
        }
        guard trustPollTimer == nil else { return }
        let id = Foundation.UUID()
        let cancel = effects.schedule(MACFFMTrustPollInterval, MACFFMTrustPollInterval, 0.5) { [weak self] in
            guard let self, self.trustPollTimer?.id == id else { return }
            self.syncTrust()
        }
        trustPollTimer = (id, cancel)
    }

    func syncTrust() {
        trustWillCheck()
        let trusted = trustCheck()
        lastTrusted = trusted
        effects.persistTrust(trusted)
        trustSynced(trusted)
        switch MACFFMTrustActionFor(configEnabled, isRunning, trusted) {
        case .start: start()
        case .stop: stop()
        case .keep: break
        }
        if trusted, strokesEnabled(), systemWideElement == nil { systemWideElement = effects.createSystemWide() }
        updateTrustPoll(trusted)
    }

    func configDidChange() {
        stop()
        configEnabled = MACFFMEnabled(effects.readConfig())
        syncTrust()
    }

    func start() {
        guard !isRunning else { return }
        let config = effects.readConfig()
        configEnabled = MACFFMEnabled(config)
        guard configEnabled else { return }
        guard trustCheck() else {
            print("Focus follows mouse is enabled but Accessibility access is missing")
            updateTrustPoll(false)
            return
        }
        activeConfig = config
        if systemWideElement == nil { systemWideElement = effects.createSystemWide() }
        dwellAnchor = nil
        let id = Foundation.UUID()
        monitorID = id
        mouseMonitor = effects.addMonitor { [weak self] scrolling, location in
            guard let self, self.monitorID == id else { return }
            if scrolling {
                self.lastGestureTime = self.effects.now()
                self.cancelPendingRaise()
            } else {
                self.handleMouseMoved(location)
            }
        }
        updateTrustPoll(true)
        print("Focus follows mouse started (delay \(MACFFMDelayMs(activeConfig)) ms)")
    }

    func stop() {
        cancelPendingRaise()
        stopTrustPoll()
        monitorID = nil
        if let mouseMonitor {
            effects.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
            print("Focus follows mouse stopped")
        }
        systemWideElement = nil
        activeConfig = nil
        dwellAnchor = nil
    }

    private func handleMouseMoved(_ location: CGPoint) {
        if let dwellAnchor, !MACFFMMovementExceedsThreshold(dwellAnchor, location, MACFFMMovementThreshold) { return }
        dwellAnchor = location
        scheduleAttempt(after: Double(MACFFMDelayMs(activeConfig)) / 1000, retriesLeft: MACFFMRaiseRetries)
    }

    private func scheduleAttempt(after delay: TimeInterval, retriesLeft: Int) {
        cancelPendingRaise()
        let id = Foundation.UUID()
        let cancel = effects.schedule(delay, nil, 0.005) { [weak self] in
            guard let self, self.dwellTimer?.id == id else { return }
            self.cancelPendingRaise()
            let raised = self.attemptRaise(retrying: retriesLeft < MACFFMRaiseRetries)
            if let next = MACFFMRetryDelay(raised: raised, retriesLeft: retriesLeft) {
                self.scheduleAttempt(after: next, retriesLeft: retriesLeft - 1)
            }
        }
        dwellTimer = (id, cancel)
    }

    private func copyAttribute(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    private func copyContainingWindow(_ start: AXUIElement) -> AXUIElement? {
        var current = start
        for _ in 0..<20 {
            let role = copyAttribute(current, kAXRoleAttribute) as? String
            if MACFFMRoleIsMenuOrDock(role) { return nil }
            if MACFFMRoleIsWindowLike(role) {
                let subrole = copyAttribute(current, kAXSubroleAttribute) as? String
                return MACFFMRoleIsAcceptable(role, subrole) ? current : nil
            }
            guard let parent = copyAttribute(current, kAXParentAttribute),
                  CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
            current = parent as! AXUIElement
        }
        guard let window = copyAttribute(start, kAXWindowAttribute),
              CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }
        let element = window as! AXUIElement
        return MACFFMRoleIsAcceptable(copyAttribute(element, kAXRoleAttribute) as? String,
                                      copyAttribute(element, kAXSubroleAttribute) as? String) ? element : nil
    }

    func copyWindowFrame(_ window: AXUIElement) -> CGRect? {
        guard let position = copyAttribute(window, kAXPositionAttribute),
              let size = copyAttribute(window, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
              AXValueGetValue(size as! AXValue, .cgSize, &dimensions) else { return nil }
        return CGRect(origin: origin, size: dimensions)
    }

    func windowUnderPointer() -> MACFFMWindow? {
        guard let systemWideElement, let primary = NSScreen.screens.first else { return nil }
        let point = MACFFMConvertToAXPoint(NSEvent.mouseLocation, primary.frame.height)
        var hit: AXUIElement?
        var pid: pid_t = 0
        guard AXUIElementCopyElementAtPosition(systemWideElement, Float(point.x), Float(point.y), &hit) == .success, let hit,
              let window = copyContainingWindow(hit), AXUIElementGetPid(window, &pid) == .success, pid > 0,
              pid != ProcessInfo.processInfo.processIdentifier,
              let owner = NSRunningApplication(processIdentifier: pid),
              !MACFFMBundleListContains(MACFFMBuiltInIgnoreBundleIdentifiers(), owner.bundleIdentifier) else { return nil }
        return (window, owner)
    }

    func raise(_ target: MACFFMWindow) -> Bool {
        let switching = target.owner.processIdentifier != NSWorkspace.shared.frontmostApplication?.processIdentifier
        AXUIElementPerformAction(target.window, kAXRaiseAction as CFString)
        target.owner.activate(options: [])
        return switching
    }

    private func attemptRaise(retrying: Bool) -> Bool {
        guard let config = activeConfig else { return false }
        let now = effects.now()
        guard let systemWideElement else { return false }
        let frontmost = NSWorkspace.shared.frontmostApplication
        let frontBundle = frontmost?.bundleIdentifier
        let disableFlag = MACFFMDisableModifierFlag(config)
        var inputs = MACFFMDecisionInputs(
            disableModifierHeld: disableFlag != 0 && NSEvent.modifierFlags.rawValue & disableFlag != 0,
            mouseButtonDown: NSEvent.pressedMouseButtons != 0,
            spaceChangeCooldownActive: MACFFMIgnoreSpaceChange(config) &&
                MACFFMWithinInterval(lastSpaceChangeTime, now, MACFFMSpaceChangeCooldown),
            gestureCooldownActive: MACFFMWithinInterval(lastGestureTime, now, MACFFMGestureCooldown),
            frontmostIsDock: frontBundle == "com.apple.dock",
            frontmostIsStayFocused: MACFFMBundleListContains(MACFFMStayFocusedBundleIdentifiers(config), frontBundle),
            strokeInProgress: strokeInProgress()
        )
        guard !MACFFMShouldSkip(inputs), let primary = NSScreen.screens.first else { return false }
        let point = MACFFMConvertToAXPoint(NSEvent.mouseLocation, primary.frame.height)
        var hit: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(systemWideElement, Float(point.x), Float(point.y), &hit)
        if result == .apiDisabled {
            syncTrust()
            return false
        }
        guard result == .success, let hit else { return false }
        guard let window = copyContainingWindow(hit) else { return false }
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success, pid > 0,
              pid != ProcessInfo.processInfo.processIdentifier,
              let owner = NSRunningApplication(processIdentifier: pid) else { return false }
        let ownerBundle = owner.bundleIdentifier
        guard !MACFFMBundleListContains(MACFFMBuiltInIgnoreBundleIdentifiers(), ownerBundle),
              !MACFFMBundleListContains(MACFFMIgnoreBundleIdentifiers(config), ownerBundle) else { return false }
        if pid == frontmost?.processIdentifier {
            if let main = copyAttribute(window, kAXMainAttribute), CFGetTypeID(main) == CFBooleanGetTypeID() {
                inputs.candidateAlreadyFocused = (main as! CFBoolean) == kCFBooleanTrue
            }
            if !inputs.candidateAlreadyFocused {
                let appElement = AXUIElementCreateApplication(pid)
                if let focused = copyAttribute(appElement, kAXFocusedWindowAttribute),
                   CFGetTypeID(focused) == AXUIElementGetTypeID() {
                    if CFEqual(focused, window) {
                        inputs.candidateAlreadyFocused = true
                    } else if let focusedFrame = copyWindowFrame(focused as! AXUIElement),
                              let candidateFrame = copyWindowFrame(window) {
                        inputs.candidateIsChildOfFocused = focusedFrame.contains(candidateFrame)
                    }
                }
            }
        }
        let windowHash = CFHash(window)
        inputs.sameWindowRecentlyRaised = windowHash == lastRaisedWindowHash &&
            MACFFMWithinInterval(lastRaisedWindowTime, now, MACFFMSameWindowDebounce)
        guard MACFFMShouldRaise(inputs, retrying: retrying) else { return false }
        if pid != frontmost?.processIdentifier { noteRaise(ownerBundle, at: effects.now()) }
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        owner.activate(options: [])
        lastRaisedWindowHash = windowHash
        lastRaisedWindowTime = now
        return true
    }
}
