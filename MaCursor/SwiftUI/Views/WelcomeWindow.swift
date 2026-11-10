import Combine
import SwiftUI

final class WelcomeWindowController: NSWindowController, NSWindowDelegate, ObservableObject {
    static let shared = WelcomeWindowController()

    @Published var page = WelcomePage.welcome {
        didSet {
            guard window?.isVisible == true else { return }
            page.save()
        }
    }

    private init() {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: WelcomeLayout.contentSize),
            styleMask: WelcomeLayout.styleMask,
            backing: .buffered, defer: false
        )
        window.title = "MaCursor"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func presentAtLaunchIfNeeded(library: LibraryViewModel) {
        guard ModalWindowCoordinator.shared.holdsMainWindow, window?.isVisible != true else { return }
        present(library: library)
    }

    private func present(library: LibraryViewModel) {
        guard let window else { return }
        page = WelcomePage.resumed()?.shown(menuBar: HelperToolManager.shared.isInstalled && MACPreferences.flag(MACPreferences.showMenuBarIconKey)) ?? .welcome
        let content = NSHostingController(rootView: WelcomeView(controller: self, library: library))
        window.contentViewController = content
        window.setContentSize(WelcomeLayout.contentSize)
        window.center()
        ModalWindowCoordinator.shared.register(window, as: .modal)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if window.isVisible {
            ModalWindowCoordinator.shared.windowDidBecomeKey(window)
            MACPreferences.setFlag(true, forKey: MACPreferences.welcomeShownKey)
            page.save()
        } else {
            ModalWindowCoordinator.shared.releaseMainWindow()
            ModalWindowCoordinator.shared.resolvedMainWindow?.makeKeyAndOrderFront(nil)
        }
    }

    func finish() {
        WelcomePage.clearSaved()
        ModalWindowCoordinator.shared.releaseMainWindow()
        window?.close()
    }

    func closeFromEscape() {
        guard let window else { return }
        if windowShouldClose(window) { window.close() }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard page.warnsOnClose else {
            WelcomePage.clearSaved()
            ModalWindowCoordinator.shared.releaseMainWindow()
            return true
        }
        guard sender.attachedSheet == nil else { return false }
        let alert = NSAlert()
        alert.messageText = String(localized: "Are you sure you want to close this window?")
        alert.informativeText = String(localized: "You can change these features in Settings. This window opens again only after Reset All Settings.")
        alert.addButton(withTitle: String(localized: "Close"))
        alert.addButton(withTitle: String(localized: "Cancel")).keyEquivalent = "\u{1b}"
        alert.beginSheetModal(for: sender) { response in
            guard response == .alertFirstButtonReturn else { return }
            self.finish()
        }
        return false
    }
}

private struct WelcomeView: View {
    @ObservedObject var controller: WelcomeWindowController
    let library: LibraryViewModel
    @ObservedObject private var helperManager = HelperToolManager.shared
    @ObservedObject private var manager = FinderExtensionManager.shared
    @State private var hover = FocusFollowsMouseConfig.load()
    @State private var gestures = CursorGesturesConfig.load()
    @State private var shaker = CursorShakerConfig.load()
    @State private var translator = CursorTranslatorConfig.load()
    @State private var screenshot = CursorScreenshotConfig.load()
    @State private var trails = CursorTrailsConfig.load()
    @State private var menuBarIcon = MACPreferences.flag(MACPreferences.showMenuBarIconKey)
    @State private var shadow = MACPreferences.flag(MACPreferences.cursorShadowKey)
    @State private var trusted = FocusFollowsMouseConfig.accessibilityTrusted
    @State private var screenRecording = CursorTranslatorConfig.screenRecordingAllowed
    @State private var rightClickMenuError: String?
    @State private var syncedMenuBarRows: [WelcomeFeature: Bool] = [:]
    private let liveTicker = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()
    private let rightClickMenuTicker = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    private var snapshot: WelcomeSnapshot {
        var granted: Set<WelcomeAccess> = []
        if trusted { granted.insert(.accessibility) }
        if screenRecording { granted.insert(.screenRecording) }
        if manager.election == .elected { granted.insert(.finderExtension) }
        if manager.settings.hasFullDiskAccess { granted.insert(.fullDiskAccess) }
        let stored: [(WelcomeFeature, Bool)] = [
            (.showMenuBarIcon, menuBarIcon), (.cursorTrails, trails.enabled), (.cursorShadow, shadow),
            (.focusOnHover, hover.enabled), (.cursorGestures, gestures.enabled), (.cursorShaker, shaker.enabled),
            (.cursorTranslator, translator.enabled), (.cursorCapture, screenshot.enabled),
            (.rightClickMenu, RightClickMenuState.isOn(settings: manager.settings, election: manager.election)),
        ]
        return WelcomeSnapshot(
            access: WelcomeAccessState(helperInstalled: helperManager.isInstalled, helperRunning: helperManager.isRunning, granted: granted,
                                       translocated: manager.isTranslocated),
            stored: Set(stored.filter(\.1).map(\.0)),
            rightClickMenuBusy: manager.isBusy,
            rightClickMenuError: rightClickMenuError
        )
    }

    var body: some View {
        WelcomeContent(page: controller.page, snapshot: snapshot, toggle: toggle, grant: grant, turn: turn(to:), pressMain: pressMainButton)
            .overlay {
                Button("") { controller.closeFromEscape() }
                    .keyboardShortcut(.cancelAction)
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .onAppear {
                refreshAccess()
                matchMenuBarRows()
            }
            .onChangeCompat(of: snapshot.menuBarSwitches) { _ in
                guard WelcomeWindowController.shared.window?.isVisible == true else { return }
                matchMenuBarRows()
            }
            .onReceive(liveTicker) { _ in
                guard WelcomeWindowController.shared.window?.isVisible == true else { return }
                read()
            }
            .onReceive(rightClickMenuTicker) { _ in
                guard WelcomeWindowController.shared.window?.isVisible == true, controller.page == .rightClickMenu,
                      !(manager.election == .elected && manager.settings.hasFullDiskAccess) else { return }
                manager.refresh()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                guard WelcomeWindowController.shared.window?.isVisible == true else { return }
                refreshAccess()
            }
            .onChangeCompat(of: controller.page) { page in
                NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                                     userInfo: [.announcement: page.title, .priority: NSAccessibilityPriorityLevel.high.rawValue])
            }
    }

    private func toggle(_ feature: WelcomeFeature) {
        let usable = snapshot.access.isUsable(feature)
        switch feature {
        case .showMenuBarIcon: GeneralSettingsView.setShowMenuBarIcon(!menuBarIcon)
        case .cursorTrails:
            var trails = CursorTrailsConfig.load()
            CursorTrailsConfig.tap(&trails)
        case .cursorShadow: CursorSettingsView.setCursorShadow(!shadow, library: library)
        case .focusOnHover: AccessWindowController.tapFocusFollowsMouse(enabled: hover.enabled, trusted: usable)
        case .cursorGestures: AccessWindowController.tapCursorGestures(enabled: gestures.enabled, usable: usable)
        case .cursorShaker: AccessWindowController.tapCursorShaker(enabled: shaker.enabled, usable: usable)
        case .cursorTranslator: AccessWindowController.tapCursorTranslator(enabled: translator.enabled, usable: usable)
        case .cursorCapture: AccessWindowController.tapCursorScreenshot(enabled: screenshot.enabled, usable: usable)
        case .rightClickMenu: AccessWindowController.tapRightClickMenu(save: saveRightClickMenu)
        }
        read()
    }

    private func matchMenuBarRows() {
        let features = snapshot.menuBarRowsToMatch(since: syncedMenuBarRows)
        guard !features.isEmpty else { return }
        let rows = snapshot.menuBarRows(features)
        MenuBarItemsSettingsView.setShown(items: rows.items, captureRows: rows.captureRows)
        syncedMenuBarRows = snapshot.menuBarSwitches
    }

    private func grant(_ access: WelcomeAccess) {
        switch access {
        case .accessibility: FocusFollowsMouseConfig.requestAccessibility()
        case .screenRecording: CursorTranslatorConfig.requestScreenRecording()
        case .fullDiskAccess: manager.openFullDiskAccessSettings()
        case .finderExtension:
            Task {
                await manager.prepareAccessRequest()
                switch WelcomeGrant.of(.finderExtension) {
                case .copyCommand: manager.copyCommand()
                case .openSystemSettings: manager.openSystemSettings()
                }
            }
        }
    }

    private var isRepeatClick: Bool {
        guard let event = NSApp.currentEvent, event.type == .leftMouseDown || event.type == .leftMouseUp else { return false }
        return event.clickCount > 1
    }

    private func turn(to page: WelcomePage?) {
        guard !isRepeatClick, let page else { return }
        controller.page = page
    }

    private func pressMainButton() {
        guard !isRepeatClick else { return }
        if let next = controller.page.next(menuBar: snapshot.showsMenuBarPage) {
            controller.page = next
        } else {
            controller.finish()
        }
    }

    private func saveRightClickMenu(_ action: () throws -> Void) {
        do {
            try action()
            rightClickMenuError = nil
        } catch {
            rightClickMenuError = error.localizedDescription
        }
    }

    private func refreshAccess() {
        FocusFollowsMouseConfig.notifyHelper()
        CursorTranslatorConfig.notifyHelper()
        CursorScreenshotConfig.notifyHelper()
        manager.refresh()
        read()
    }

    private func read() {
        hover = FocusFollowsMouseConfig.load()
        gestures = CursorGesturesConfig.load()
        shaker = CursorShakerConfig.load()
        translator = CursorTranslatorConfig.load()
        screenshot = CursorScreenshotConfig.load()
        trails = CursorTrailsConfig.load()
        menuBarIcon = MACPreferences.flag(MACPreferences.showMenuBarIconKey)
        shadow = MACPreferences.flag(MACPreferences.cursorShadowKey)
        trusted = FocusFollowsMouseConfig.accessibilityTrusted
        screenRecording = CursorTranslatorConfig.screenRecordingAllowed
    }
}
