import AppKit
import CoreMedia
@preconcurrency import ScreenCaptureKit

@MainActor
final class CursorMagnifierController {
    private static let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
    private static let screenSaver = CursorShaker.distributedPauses.filter { $0.value.pause == .screenSaver }
    var allowed: @MainActor () -> Bool = { false }
    var requestAccess: @MainActor () -> Void = {}
    private var config = CursorHighlightConfig.load()
    private var window: NSWindow?
    private var stream: SCStream?
    private var frames: CursorMagnifierFrames?
    private var display: CGDirectDisplayID?
    private var token = 0
    private var shown = false
    private var paused = false
    private var monitors: [Any] = []
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []

    private var hiddenForMotion: Bool {
        CursorHighlight.hidesForMotion(follows: CursorHighlight.followsReduceMotion, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    func start() {
        let before = config
        config = CursorHighlightConfig.load()
        switch CursorMagnifier.step(config, before: before, paused: paused, hidden: hiddenForMotion, shown: shown, allowed: allowed()) {
        case .stop: stop()
        case .hide: observe(); hide()
        case .ask: observe(); hide(); requestAccess()
        case .show: observe(); show()
        }
    }

    private func show() {
        if !shown {
            shown = true
            if window == nil { window = Self.overlay() }
            watch()
        }
        moved()
        window?.orderFrontRegardless()
    }

    private func hide() {
        token += 1
        stream?.stopCapture { _ in }
        stream = nil
        frames = nil
        display = nil
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        shown = false
        window?.orderOut(nil)
        if let lens = Self.lens(of: window) { CursorMagnifier.paint(lens, contents: nil) }
    }

    func stop() {
        hide()
        observers.forEach { $0.center.removeObserver($0.token) }
        observers = []
        window?.close()
        window = nil
    }

    private func watch() {
        monitors = [NSEvent.addGlobalMonitorForEvents(matching: Self.moves) { [weak self] _ in
                        MainActor.assumeIsolated { self?.moved() }
                    },
                    NSEvent.addLocalMonitorForEvents(matching: Self.moves) { [weak self] event in
                        MainActor.assumeIsolated { self?.moved() }
                        return event
                    }].compactMap { $0 }
    }

    private func observe() {
        guard observers.isEmpty else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append((workspace, workspace.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.start() }
        }))
        let distributed = DistributedNotificationCenter.default()
        for (name, change) in Self.screenSaver {
            observers.append((distributed, distributed.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.paused = change.starts
                    self?.start()
                }
            }))
        }
    }

    private func moved() {
        guard shown, let window, let lens = Self.lens(of: window) else { return }
        let point = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) ?? NSScreen.main else { return }
        if window.frame != screen.frame { window.setFrame(screen.frame, display: false) }
        let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? CGMainDisplayID()
        if id != display {
            CursorMagnifier.paint(lens, contents: nil)
            capture(screen, id)
        }
        CursorMagnifier.place(lens, pointer: point, config: config, display: screen.frame, scale: screen.backingScaleFactor)
    }

    private func capture(_ screen: NSScreen, _ id: CGDirectDisplayID) {
        token += 1
        let start = token
        stream?.stopCapture { _ in }
        stream = nil
        frames = nil
        display = id
        let width = Int((screen.frame.width * screen.backingScaleFactor).rounded())
        let height = Int((screen.frame.height * screen.backingScaleFactor).rounded())
        Task { [weak self] in
            var running: SCStream?
            do {
                let content = try await CursorTranslatorOnce.within(2) { try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) }
                guard let self, start == self.token, let shown = content.displays.first(where: { $0.displayID == id }) else { return }
                let own = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
                let filter = SCContentFilter(display: shown, excludingApplications: own, exceptingWindows: [])
                let configuration = SCStreamConfiguration()
                configuration.width = width
                configuration.height = height
                configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
                configuration.queueDepth = 3
                configuration.pixelFormat = kCVPixelFormatType_32BGRA
                configuration.showsCursor = false
                let frames = CursorMagnifierFrames(shown: { [weak self] surface in self?.received(surface, start) },
                                                   stopped: { [weak self] in self?.failed(start) })
                let stream = SCStream(filter: filter, configuration: configuration, delegate: frames)
                try stream.addStreamOutput(frames, type: .screen, sampleHandlerQueue: .main)
                running = stream
                self.stream = stream
                self.frames = frames
                try await CursorTranslatorOnce.within(2) { try await stream.startCapture() }
                if start != self.token { Self.end(stream) }
            } catch {
                Self.end(running)
                self?.failed(start)
            }
        }
    }

    private func received(_ surface: IOSurfaceRef, _ start: Int) {
        guard start == token, let lens = Self.lens(of: window) else { return }
        CursorMagnifier.paint(lens, contents: surface)
    }

    private func failed(_ start: Int) {
        guard start == token else { return }
        hide()
        _ = allowed()
    }

    private static func end(_ stream: SCStream?) {
        stream?.stopCapture { _ in }
    }

    private static func lens(of window: NSWindow?) -> CALayer? {
        window?.contentView?.layer?.sublayers?.first
    }

    private static func overlay() -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.canHide = false
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        let view = NSView()
        view.layer = CALayer()
        view.wantsLayer = true
        view.layer?.addSublayer(CursorMagnifier.layers())
        window.contentView = view
        return window
    }
}

final class CursorMagnifierFrames: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let shown: @MainActor (IOSurfaceRef) -> Void
    private let stopped: @MainActor () -> Void

    init(shown: @escaping @MainActor (IOSurfaceRef) -> Void, stopped: @escaping @MainActor () -> Void) {
        self.shown = shown
        self.stopped = stopped
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[SCStreamFrameInfo.status] as? Int, SCFrameStatus(rawValue: raw) == .complete,
              let pixels = sampleBuffer.imageBuffer, let surface = CVPixelBufferGetIOSurface(pixels)?.takeUnretainedValue() else { return }
        nonisolated(unsafe) let frame = surface
        MainActor.assumeIsolated { shown(frame) }
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        DispatchQueue.main.async { [stopped] in
            MainActor.assumeIsolated { stopped() }
        }
    }
}
