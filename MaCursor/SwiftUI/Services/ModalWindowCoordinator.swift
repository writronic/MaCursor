import AppKit
import Foundation

private enum ModalWindowTitles {
    static let mainWindow = "MaCursor"
    static let editThemePrefix = "Edit Theme"
    static let aboutPrefix = "About MaCursor"
    static let settingsIdentifiers = ["Settings", "Preferences"]
}

private class BlockingOverlayView: NSView {
    weak var modalWindowToFocus: NSWindow?
    
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
    
    
    private func beepAndRefocusModal() {
        NSSound.beep()
        if let modal = modalWindowToFocus, modal.isVisible {
            modal.makeKeyAndOrderFront(nil)
        }
    }
}

@MainActor
final class ModalWindowCoordinator {
    static let shared = ModalWindowCoordinator()
    
    private var blockingWindowNumbers: Set<Int> = []
    private var overlayView: BlockingOverlayView?
    private weak var mainWindow: NSWindow?
    
    private init() {}
    
    
    func start() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowBecameKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }
    
    
    private func isMainLibraryWindow(_ window: NSWindow) -> Bool {
        guard !window.isSheet,
              !(window is NSPanel),
              !isBlockingWindow(window) else { return false }
        
        let title = window.title
        return title == ModalWindowTitles.mainWindow || title.isEmpty
    }
    
    private func isBlockingWindow(_ window: NSWindow) -> Bool {
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
    
    
    private func findMainWindow() -> NSWindow? {
        if let cached = mainWindow, cached.isVisible { return cached }
        
        let candidate = NSApp.windows.first(where: { isMainLibraryWindow($0) })
        mainWindow = candidate
        return candidate
    }
    
    
    private func blockMainWindow(for modalWindow: NSWindow) {
        guard let main = findMainWindow() else { return }
        
        attachAsChildWindow(modalWindow, to: main)
        installOverlay(on: main, targeting: modalWindow)
    }
    
    private func unblockMainWindow() {
        guard let main = findMainWindow() else { return }
        
        removeOverlay()
        detachBlockingChildren(from: main)
        main.makeKeyAndOrderFront(nil)
    }
    
    
    private func attachAsChildWindow(_ child: NSWindow, to parent: NSWindow) {
        let alreadyAttached = parent.childWindows?.contains(child) ?? false
        if !alreadyAttached {
            parent.addChildWindow(child, ordered: .above)
        }
    }
    
    private func detachBlockingChildren(from parent: NSWindow) {
        guard let children = parent.childWindows else { return }
        for child in children where blockingWindowNumbers.contains(child.windowNumber) {
            parent.removeChildWindow(child)
        }
    }
    
    
    private func installOverlay(on window: NSWindow, targeting modal: NSWindow) {
        if overlayView == nil {
            guard let themeFrame = window.contentView?.superview else { return }
            
            let overlay = BlockingOverlayView()
            overlay.autoresizingMask = [.width, .height]
            overlay.frame = themeFrame.bounds
            overlay.modalWindowToFocus = modal
            themeFrame.addSubview(overlay)
            overlayView = overlay
        } else {
            overlayView?.modalWindowToFocus = modal
        }
    }
    
    private func removeOverlay() {
        overlayView?.removeFromSuperview()
        overlayView = nil
    }
    
    
    private func pruneStaleEntries() {
        blockingWindowNumbers = blockingWindowNumbers.filter { num in
            NSApp.windows.contains(where: { $0.windowNumber == num && $0.isVisible })
        }
    }
    
    private func refocusRemainingModal() {
        guard let nextModal = NSApp.windows.first(where: {
            blockingWindowNumbers.contains($0.windowNumber) && $0.isVisible
        }) else { return }
        
        overlayView?.modalWindowToFocus = nextModal
        nextModal.makeKeyAndOrderFront(nil)
    }
    
    
    @objc private func handleWindowBecameKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              isBlockingWindow(window) else { return }
        
        blockingWindowNumbers.insert(window.windowNumber)
        blockMainWindow(for: window)
    }
    
    @objc private func handleWindowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              blockingWindowNumbers.contains(window.windowNumber) else { return }
        
        findMainWindow()?.removeChildWindow(window)
        blockingWindowNumbers.remove(window.windowNumber)
        pruneStaleEntries()
        
        if blockingWindowNumbers.isEmpty {
            unblockMainWindow()
        } else {
            refocusRemainingModal()
        }
    }
}
