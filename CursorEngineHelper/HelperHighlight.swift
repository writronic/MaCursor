import AppKit

@MainActor
final class CursorHighlightController {
    private static let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
    private static let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
    private static let screenSaver = CursorShaker.distributedPauses.filter { $0.value.pause == .screenSaver }
    private var config = CursorHighlightConfig()
    private var monitors: [Any] = []
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var windows: [NSWindow] = []
    private var ripples: [CursorHighlightRipple] = []
    private var clock: DispatchSourceTimer?
    private var shown = false
    private var hidden = false
    private var paused = false

    private var lit: Bool { config.showsSpotlight && !hidden && !paused }

    func start() {
        config = CursorHighlightConfig.load()
        guard config.enabled else { return stop() }
        if windows.isEmpty {
            windows = NSScreen.screens.map(Self.overlay)
            observe()
        }
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        if config.showsSpotlight {
            monitors += [NSEvent.addGlobalMonitorForEvents(matching: Self.moves) { [weak self] _ in
                             MainActor.assumeIsolated { self?.moved() }
                         },
                         NSEvent.addLocalMonitorForEvents(matching: Self.moves) { [weak self] event in
                             MainActor.assumeIsolated { self?.moved() }
                             return event
                         }].compactMap { $0 }
        }
        if config.showsRipple {
            monitors += [NSEvent.addGlobalMonitorForEvents(matching: Self.clicks) { [weak self] event in
                             guard !CursorGestureKeys.posted(event) else { return }
                             let right = event.type == .rightMouseDown
                             MainActor.assumeIsolated { self?.clicked(right) }
                         },
                         NSEvent.addLocalMonitorForEvents(matching: Self.clicks) { [weak self] event in
                             guard !CursorGestureKeys.posted(event) else { return event }
                             let right = event.type == .rightMouseDown
                             MainActor.assumeIsolated { self?.clicked(right) }
                             return event
                         }].compactMap { $0 }
        }
        var holes: [CGFloat: CGImage] = [:]
        for window in windows {
            let scale = window.backingScaleFactor
            if holes[scale] == nil { holes[scale] = CursorHighlightSpotlight.hole(config, scale: scale) }
            if let root = Self.root(of: window) { CursorHighlight.paint(root, config: config, hole: holes[scale]) }
        }
        motionChanged()
    }

    func stop() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        observers.forEach { $0.center.removeObserver($0.token) }
        observers = []
        clock?.cancel()
        clock = nil
        ripples = []
        shown = false
        windows.forEach { $0.close() }
        windows = []
    }

    private func observe() {
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append((workspace, workspace.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.motionChanged() }
        }))
        let distributed = DistributedNotificationCenter.default()
        for (name, change) in Self.screenSaver {
            observers.append((distributed, distributed.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.paused = change.starts
                    self?.moved()
                }
            }))
        }
    }

    private func motionChanged() {
        hidden = CursorHighlight.hidesForMotion(follows: CursorHighlight.followsReduceMotion, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        if hidden || !config.showsRipple { ripples = [] }
        tick()
        moved()
    }

    private func moved() {
        let tip = lit ? NSEvent.mouseLocation : nil
        for window in windows {
            guard let root = Self.root(of: window) else { continue }
            CursorHighlight.place(root, tip: tip, window: window.frame, scale: window.backingScaleFactor, side: config.side)
        }
        order()
    }

    private func clicked(_ right: Bool) {
        guard !hidden, !paused else { return }
        ripples.append(CursorHighlightRipple(point: NSEvent.mouseLocation, time: ProcessInfo.processInfo.systemUptime, right: right))
        tick()
        guard clock == nil else { return }
        let fps = NSScreen.screens.map(\.maximumFramesPerSecond).max() ?? 0
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: 1 / Double(fps > 0 ? fps : 60), leeway: .milliseconds(2))
        timer.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.tick() } }
        clock = timer
        timer.resume()
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        ripples = ripples.filter { now - $0.time <= config.look.duration }
        for window in windows {
            guard let root = Self.root(of: window) else { continue }
            let here = ripples.filter { window.frame.intersects($0.frame(config)) }
            CursorHighlight.show(here, at: now, in: root, window: window.frame, scale: window.backingScaleFactor, config: config)
        }
        order()
        guard ripples.isEmpty else { return }
        clock?.cancel()
        clock = nil
    }

    private func order() {
        let needed = lit || !ripples.isEmpty
        guard needed != shown else { return }
        shown = needed
        for window in windows {
            if needed { window.orderFrontRegardless() } else { window.orderOut(nil) }
        }
    }

    private static func root(of window: NSWindow) -> CALayer? {
        window.contentView?.layer?.sublayers?.first
    }

    private static func overlay(_ screen: NSScreen) -> NSWindow {
        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.canHide = false
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        let view = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
        view.layer = CALayer()
        view.wantsLayer = true
        let tree = CursorHighlight.tree()
        tree.frame = view.bounds
        view.layer?.addSublayer(tree)
        window.contentView = view
        window.setFrame(screen.frame, display: false)
        return window
    }
}
