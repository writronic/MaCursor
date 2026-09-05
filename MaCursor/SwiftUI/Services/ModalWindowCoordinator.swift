import AppKit
import Combine
import Foundation

enum ModalWindowRole {
    case main
    case modal
}

private enum ModalWindowTitles {
    static let mainWindow = "MaCursor"
    static let editThemePrefix = "Edit Theme"
    static let aboutPrefix = "About MaCursor"
    static let settingsIdentifiers = ["Settings", "Preferences"]
}

enum ModalWindowPlacement {
    static func centeredOrigin(
        size: NSSize,
        over parentFrame: NSRect,
        constrainedTo visibleFrame: NSRect
    ) -> NSPoint {
        var x = parentFrame.midX - size.width / 2
        var y = parentFrame.midY - size.height / 2

        x = min(x, visibleFrame.maxX - size.width)
        y = min(y, visibleFrame.maxY - size.height)
        x = max(x, visibleFrame.minX)
        y = max(y, visibleFrame.minY)

        return NSPoint(x: x, y: y)
    }
}

private struct WeakWindow {
    weak var window: NSWindow?
}

class BlockingOverlayView: NSView {
    weak var modalWindowToFocus: NSWindow?

    static let blockedDragTypes: [NSPasteboard.PasteboardType] = [.fileURL, .URL]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.15).cgColor
        registerForDraggedTypes(Self.blockedDragTypes)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return self
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    override var acceptsFirstResponder: Bool {
        return false
    }

    override func mouseDown(with event: NSEvent) {
        beepAndRefocusModal()
    }

    override func mouseUp(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func scrollWheel(with event: NSEvent) {}

    override func rightMouseDown(with event: NSEvent) {
        beepAndRefocusModal()
    }

    override func rightMouseUp(with event: NSEvent) {}

    override func otherMouseDown(with event: NSEvent) {
        beepAndRefocusModal()
    }

    override func otherMouseUp(with event: NSEvent) {}


    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { [] }
    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation { [] }
    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool { false }
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool { false }


    private func beepAndRefocusModal() {
        NSSound.beep()
        if let modal = modalWindowToFocus, modal.isVisible {
            modal.makeKeyAndOrderFront(nil)
        }
    }
}

@MainActor
final class ModalWindowCoordinator: ObservableObject {
    static let shared = ModalWindowCoordinator()

    var windowProvider: () -> [NSWindow] = { NSApp.windows }

    var isApplicationActive: () -> Bool = { NSApp.isActive }

    @Published private(set) var isMainWindowBlocked = false

    private var modalStack: [WeakWindow] = []
    private var registeredMain: [WeakWindow] = []
    private var registeredModals: [WeakWindow] = []
    private var overlayView: BlockingOverlayView?
    private weak var overlayHost: NSWindow?
    private weak var mainWindow: NSWindow?
    private var eventMonitor: Any?
    private var isReassertingOrder = false

    init() {}


    private func refreshBlockedState() {
        let blocked = !modalStack.isEmpty
        guard isMainWindowBlocked != blocked else { return }
        isMainWindowBlocked = blocked
        if !blocked { unblockMainWindow() }
    }

    func runIfMainWindowIsUsable(_ action: () -> Void) {
        guard !isMainWindowBlocked else {
            NSSound.beep()
            activeModalWindow?.makeKeyAndOrderFront(nil)
            return
        }
        action()
    }


    func start() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowBecameKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowBecameKey(_:)),
            name: NSWindow.didBecomeMainNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppBecameActive(_:)),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppResignedActive(_:)),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
    }


    func register(_ window: NSWindow, as role: ModalWindowRole) {
        switch role {
        case .main:
            guard !isRegisteredMain(window) else { return }
            pruneRegistrations()
            registeredModals.removeAll { $0.window === window }
            if modalStack.contains(where: { $0.window === window }) {
                releaseModal(window)
            }
            registeredMain.append(WeakWindow(window: window))
            mainWindow = window

        case .modal:
            window.isRestorable = false
            let alreadyRegistered = isRegisteredModal(window)
            if !alreadyRegistered {
                pruneRegistrations()
                registeredMain.removeAll { $0.window === window }
                registeredModals.append(WeakWindow(window: window))
                if mainWindow === window { mainWindow = nil }
            }
            if window.isKeyWindow, modalStack.last?.window !== window {
                windowDidBecomeKey(window)
            }
        }
    }

    private func pruneRegistrations() {
        registeredMain.removeAll { $0.window == nil }
        registeredModals.removeAll { $0.window == nil }
        modalStack.removeAll { $0.window == nil }
        refreshBlockedState()
    }

    private func isRegisteredMain(_ window: NSWindow) -> Bool {
        registeredMain.contains { $0.window === window }
    }

    private func isRegisteredModal(_ window: NSWindow) -> Bool {
        registeredModals.contains { $0.window === window }
    }


    func isMainLibraryWindow(_ window: NSWindow) -> Bool {
        if isRegisteredMain(window) { return true }
        if isRegisteredModal(window) { return false }
        if modalStack.contains(where: { $0.window === window }) { return false }

        guard !window.isSheet,
              !(window is NSPanel),
              !isBlockingWindow(window) else { return false }

        let title = window.title
        return title == ModalWindowTitles.mainWindow || title.isEmpty
    }

    func isBlockingWindow(_ window: NSWindow) -> Bool {
        if isRegisteredModal(window) { return true }
        if isRegisteredMain(window) { return false }

        let title = window.title

        if title.hasPrefix(ModalWindowTitles.editThemePrefix) { return true }
        if title.hasPrefix(ModalWindowTitles.aboutPrefix) { return true }

        let className = String(describing: type(of: window))
        for identifier in ModalWindowTitles.settingsIdentifiers {
            if title.contains(identifier) || className.contains(identifier) {
                return true
            }
        }

        return false
    }


    var trackedModalWindows: [NSWindow] {
        modalStack.compactMap { $0.window }
    }

    var activeModalWindow: NSWindow? {
        let live = trackedModalWindows
        return live.last(where: { $0.isVisible }) ?? live.last
    }

    var resolvedMainWindow: NSWindow? {
        findMainWindow()
    }

    var hasEventMonitor: Bool {
        eventMonitor != nil
    }

    var hasOverlay: Bool {
        overlayView != nil
    }


    private func findMainWindow() -> NSWindow? {
        let registered = registeredMain.compactMap { $0.window }
        if !registered.isEmpty {
            let candidate =
                registered.first(where: { $0.isKeyWindow || $0.isMainWindow })
                ?? registered.first(where: { $0 === mainWindow })
                ?? registered.first(where: { $0.isVisible })
                ?? registered.first
            mainWindow = candidate
            return candidate
        }

        if let cached = mainWindow, cached.isVisible, isMainLibraryWindow(cached) { return cached }

        let windows = windowProvider()
        let candidate =
            windows.first(where: { $0.title == ModalWindowTitles.mainWindow && isMainLibraryWindow($0) })
            ?? windows.first(where: { isMainLibraryWindow($0) })

        mainWindow = candidate
        return candidate
    }


    private func blockMainWindow(for modalWindow: NSWindow) {
        modalWindow.parent?.removeChildWindow(modalWindow)
        modalWindow.collectionBehavior.insert(.fullScreenAuxiliary)
        applyModalLevel(to: modalWindow)

        installEventMonitor()

        guard let main = findMainWindow(), main !== modalWindow else { return }

        modalWindow.order(.above, relativeTo: main.windowNumber)
        installOverlay(on: main, targeting: modalWindow)
    }

    private func unblockMainWindow() {
        removeOverlay()
        removeEventMonitor()
        findMainWindow()?.makeKeyAndOrderFront(nil)
    }


    private func applyModalLevel(to window: NSWindow, active: Bool) {
        window.level = active ? .floating : .normal
    }

    private func applyModalLevel(to window: NSWindow) {
        applyModalLevel(to: window, active: isApplicationActive())
    }

    private func refreshModalLevels(active: Bool) {
        for modal in trackedModalWindows {
            applyModalLevel(to: modal, active: active)
        }
    }


    @discardableResult
    func raiseActiveModal(above window: NSWindow) -> NSWindow? {
        guard !isReassertingOrder,
              isMainLibraryWindow(window),
              let modal = activeModalWindow,
              modal !== window else { return nil }

        isReassertingOrder = true
        defer { isReassertingOrder = false }

        modal.order(.above, relativeTo: window.windowNumber)
        modal.makeKeyAndOrderFront(nil)
        return modal
    }


    private func installEventMonitor() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]
        ) { [weak self] event in
            guard let self else { return event }
            guard let eventWindow = event.window,
                  self.shouldSwallow(event, in: eventWindow),
                  let modal = self.activeModalWindow else { return event }
            if event.type != .keyDown { NSSound.beep() }
            modal.makeKeyAndOrderFront(nil)
            return nil
        }
    }

    func shouldSwallow(_ event: NSEvent, in window: NSWindow) -> Bool {
        if event.type == .keyDown {
            return isRegisteredMain(window) && !isRegisteredModal(window)
        }
        return isMainLibraryWindow(window)
    }

    private func removeEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }


    private func installOverlay(on window: NSWindow, targeting modal: NSWindow) {
        if let existing = overlayView,
           overlayHost === window,
           existing.window === window,
           existing.superview != nil {
            existing.modalWindowToFocus = modal
            return
        }

        removeOverlay()

        guard let themeFrame = window.contentView?.superview else { return }

        let overlay = BlockingOverlayView()
        overlay.autoresizingMask = [.width, .height]
        overlay.frame = themeFrame.bounds
        overlay.modalWindowToFocus = modal
        themeFrame.addSubview(overlay)
        overlayView = overlay
        overlayHost = window
    }

    private func removeOverlay() {
        overlayView?.removeFromSuperview()
        overlayView = nil
        overlayHost = nil
    }


    private func promoteToTopOfModalStack(_ window: NSWindow) {
        modalStack.removeAll { $0.window == nil || $0.window === window }
        modalStack.append(WeakWindow(window: window))
        refreshBlockedState()
    }

    private func refocusRemainingModal() {
        guard let modal = activeModalWindow else { return }
        overlayView?.modalWindowToFocus = modal
        modal.makeKeyAndOrderFront(nil)
    }


    func windowDidBecomeKey(_ window: NSWindow) {
        pruneRegistrations()

        if isBlockingWindow(window) {
            promoteToTopOfModalStack(window)
            blockMainWindow(for: window)
            return
        }

        if isMainLibraryWindow(window) {
            mainWindow = window
            raiseActiveModal(above: window)
        }
    }

    private func releaseModal(_ window: NSWindow) {
        window.parent?.removeChildWindow(window)
        window.level = .normal
        modalStack.removeAll { $0.window == nil || $0.window === window }
        refreshBlockedState()

        if modalStack.isEmpty {
            unblockMainWindow()
        } else {
            refocusRemainingModal()
        }
    }

    func windowWillClose(_ window: NSWindow) {
        registeredModals.removeAll { $0.window === window }
        registeredMain.removeAll { $0.window === window }

        guard modalStack.contains(where: { $0.window === window }) else { return }
        releaseModal(window)
    }


    @objc private func handleWindowBecameKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        windowDidBecomeKey(window)
    }

    @objc private func handleWindowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        windowWillClose(window)
    }

    func applicationDidBecomeActive() {
        refreshModalLevels(active: true)
        guard let main = findMainWindow() else { return }
        raiseActiveModal(above: main)
    }

    func applicationDidResignActive() {
        refreshModalLevels(active: false)
    }

    @objc private func handleAppBecameActive(_ notification: Notification) {
        applicationDidBecomeActive()
    }

    @objc private func handleAppResignedActive(_ notification: Notification) {
        applicationDidResignActive()
    }
}
