import AppKit
import SwiftUI

@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var keyMonitor: Any?
    private var previousApp: NSRunningApplication?
    private var closedAt: TimeInterval = 0
    private var pendingCapture: MACMenuBarCaptureItem?
    private var pendingFile: MACMenuBarFileItem?
    var captureHandler: (@MainActor (MACMenuBarCaptureItem) -> Void)?
    var historyHandler: (@MainActor () -> Void)?

    private func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item
        item.behavior = .removalAllowed
        item.autosaveName = "MaCursorMenuBarItem"
        let button = item.button
        button?.image = MenuBarService.brandImage()
        button?.toolTip = "MaCursor"
        button?.setAccessibilityTitle("MaCursor")
        button?.setAccessibilityRole(.button)
        button?.target = self
        button?.action = #selector(statusItemClicked(_:))
        button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func uninstall() {
        closePanel()
        popover = nil
        guard let statusItem else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }

    func applyVisibility() {
        if MACPreferences.flag(MACPreferences.showMenuBarIconKey) {
            install()
            statusItem?.isVisible = true
        } else {
            uninstall()
        }
    }

    func refreshTrails() {
        if popover != nil { MenuBarPanelModel.shared.reloadTrails() }
    }

    func refreshShaker() {
        if popover != nil { MenuBarPanelModel.shared.reloadShaker() }
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        if let event = NSApp.currentEvent, MACMenuBarClickIsSecondary(event.type, event.modifierFlags) {
            showContextMenu()
        } else {
            togglePanel()
        }
    }

    private func panelPopover() -> NSPopover {
        if let popover { return popover }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        let host = NSHostingController(rootView: MenuBarPanelView(model: MenuBarPanelModel.shared))
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        MenuBarPanelModel.shared.onCapture = { [weak self] item in
            self?.pendingCapture = item
            self?.closePanel()
        }
        MenuBarPanelModel.shared.onOpen = { [weak self] item in
            self?.pendingFile = item
            self?.closePanel()
        }
        self.popover = popover
        return popover
    }

    private func togglePanel() {
        if popover?.isShown == true {
            closePanel()
            return
        }
        guard ProcessInfo.processInfo.systemUptime - closedAt >= 0.35 else { return }
        showPanel()
    }

    private func showPanel() {
        guard let button = statusItem?.button else { return }
        let popover = panelPopover()
        let appearance = MACMenuBarAppearanceNameForMode(MACPreferences.value(forKey: MACPreferences.appearanceModeKey))
        popover.appearance = appearance.flatMap { NSAppearance(named: $0) }
        MenuBarPanelModel.shared.isShown = true
        MenuBarPanelModel.shared.panelMaxHeight = MACMenuBarPanelMaxHeight(button.window?.screen?.visibleFrame.height ?? .nan)
        MenuBarPanelModel.shared.openCount += 1
        MenuBarPanelModel.shared.reload()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        applyPanelGlassAlpha(popover.contentViewController?.view,
                             alpha: MACMenuBarPanelGlassAlpha(MenuBarService.panelBackgroundLevel()))
        let front = NSWorkspace.shared.frontmostApplication
        previousApp = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.closePanel()
                return nil
            }
            return event
        }
    }

    private func applyPanelGlassAlpha(_ contentView: NSView?, alpha: Double) {
        guard var frame = contentView else { return }
        while let parent = frame.superview { frame = parent }
        for view in frame.subviews where NSStringFromClass(type(of: view)).contains("Glass") {
            view.alphaValue = alpha
        }
    }

    private func closePanel() {
        if popover?.isShown == true { popover?.performClose(nil) }
    }

    func popoverDidClose(_ notification: Notification) {
        closedAt = ProcessInfo.processInfo.systemUptime
        MenuBarPanelModel.shared.isShown = false
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        var back: NSRunningApplication?
        if NSApp.isActive, let previousApp, !previousApp.isTerminated {
            previousApp.activate(options: [])
            back = previousApp
        }
        previousApp = nil
        if let file = pendingFile {
            pendingFile = nil
            Task { [weak self, back] in
                if let back { await CursorScreenshotController.waited { back.isActive } }
                self?.run(file)
            }
            return
        }
        guard let item = pendingCapture else { return }
        pendingCapture = nil
        Task { [weak self, back] in
            if let back { await CursorScreenshotController.waited { back.isActive } }
            self?.captureHandler?(item)
        }
    }

    private func run(_ item: MACMenuBarFileItem) {
        switch item {
        case .open: CursorScreenshotEditor.openFile()
        case .openClipboard: CursorScreenshotEditor.openClipboard()
        case .pin: CursorScreenshotEditor.pinFile()
        case .history: historyHandler?()
        }
    }

    private func showContextMenu() {
        if popover?.isShown == true {
            previousApp = nil
            closePanel()
        }
        statusItem?.menu = contextMenu()
        statusItem?.button?.performClick(nil)
        DispatchQueue.main.async { [weak self] in self?.statusItem?.menu = nil }
    }

    private func item(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: MenuBarService.localized(title), action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func contextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item("Open MaCursor", action: #selector(openMainApp(_:))))
        menu.addItem(item("Settings...", action: #selector(openSettings(_:)), key: ","))
        menu.addItem(.separator())
        menu.addItem(item("Quit MaCursor", action: #selector(quit(_:))))
        return menu
    }

    @objc private func openMainApp(_ sender: NSMenuItem) {
        MenuBarService.launchParentAppThenPost(nil)
    }

    @objc private func openSettings(_ sender: NSMenuItem) {
        MenuBarService.openSettings()
    }

    @objc private func quit(_ sender: NSMenuItem) {
        guard CursorScreenshotEditor.closeThen({ [weak self] in self?.quit(sender) }) else { return }
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: MACAppBundleIdentifier) {
            app.terminate()
        }
        NSApp.terminate(nil)
    }
}
