import Combine
import Sparkle
import SwiftUI

struct MainWindowBackCommand: View {
    @ObservedObject private var router = MainWindowRouter.shared
    @ObservedObject private var coordinator = ModalWindowCoordinator.shared

    var body: some View {
        Button("Back") { router.back() }
            .keyboardShortcut("[")
            .disabled((router.page == nil && router.editor == nil) || coordinator.isMainWindowBlocked)
    }
}

struct MainWindowView: View {
    let updater: SPUUpdater

    var body: some View {
        MainWindowShell(router: .shared, overview: { OverviewHost() }, page: { MainPageView(page: $0, updater: updater) })
            .onAppear {
                MainWindowRouter.shared.canLeavePage = { ModalWindowCoordinator.shared.resolvedMainWindow?.attachedSheet == nil }
                MainWindowRouter.shared.bringForward = { ModalWindowCoordinator.shared.resolvedMainWindow?.makeKeyAndOrderFront(nil) }
                MainWindowRouter.shared.selectTab = { MainPageView.selectTab($0, $1) }
                MainWindowRouter.shared.snapshot = {
                    let feed = OverviewFeed()
                    feed.read()
                    return feed.snapshot
                }
            }
    }
}

private struct OverviewHost: View {
    @EnvironmentObject private var library: LibraryViewModel
    @EnvironmentObject private var router: MainWindowRouter
    @StateObject private var feed = OverviewFeed()

    var body: some View {
        OverviewView(library: library, snapshot: feed.snapshot,
                     openThemes: { _ = router.open(.themes) },
                     open: { _ = router.open($0.page, tab: $0.tab) },
                     toggle: { feed.toggle($0) },
                     openGallery: { router.openGallery() })
            .onAppear { feed.refreshAccess() }
            .onReceive(OverviewFeed.events) { _ in feed.read() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in feed.refreshAccess() }
    }
}

@MainActor
final class OverviewFeed: ObservableObject {
    @Published private(set) var snapshot = OverviewSnapshot()
    private var rightClickMenuError: String?

    static let events: AnyPublisher<Void, Never> = {
        let local: [Notification.Name] = [.cursorSettingsDidReset, .macAutoSwitchConfigDidChange, .macFocusFollowsMouseConfigDidChange]
        let distributed: [Notification.Name] = [
            .MACFocusFollowsMouseDidChange, .MACFocusFollowsMouseStatusDidChange, .MACCursorTrailsDidChange, .MACCursorHighlightDidChange, .MACCursorGesturesDidChange,
            .MACCursorShakerDidChange, .MACCursorBoardDidChange, .MACCursorScreenshotDidChange, .MACCursorTranslatorDidChange,
            .MACCursorTranslatorStatusDidChange, .MACAutoSwitchDidChange, .MACCursorPreferencesDidChange, .MACMenuBarDidChange,
        ]
        return Publishers.MergeMany(local.map { NotificationCenter.default.publisher(for: $0) }
                                    + distributed.map { DistributedNotificationCenter.default().publisher(for: $0) })
            .map { _ in () }
            .merge(with: HelperToolManager.shared.objectWillChange, FinderExtensionManager.shared.objectWillChange)
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }()

    func refreshAccess() {
        FocusFollowsMouseConfig.notifyHelper()
        CursorTranslatorConfig.notifyHelper()
        CursorScreenshotConfig.notifyHelper()
        FinderExtensionManager.shared.refresh()
        read()
    }

    func toggle(_ card: OverviewCard) {
        guard !snapshot.isLocked(card) else { return }
        let usable = card.feature.map(snapshot.welcome.access.isUsable) ?? false
        switch card {
        case .perAppThemes:
            var config = AutoSwitchConfig.load()
            config.switchByApp.toggle()
            config.save()
        case .themeAutomation:
            var config = AutoSwitchConfig.load()
            config.enabled.toggle()
            config.save()
        case .focusOnHover: AccessWindowController.tapFocusFollowsMouse(enabled: FocusFollowsMouseConfig.load().enabled, trusted: usable)
        case .cursorShaker: AccessWindowController.tapCursorShaker(enabled: CursorShakerConfig.load().enabled, usable: usable)
        case .cursorTrails:
            var trails = CursorTrailsConfig.load()
            CursorTrailsConfig.tap(&trails)
        case .cursorHighlight: CursorHighlightConfig.tap()
        case .cursorCapture: AccessWindowController.tapCursorScreenshot(enabled: CursorScreenshotConfig.load().enabled, usable: usable)
        case .cursorBoard: AccessWindowController.tapCursorBoard(enabled: CursorBoardConfig.load().enabled)
        case .cursorTranslator: AccessWindowController.tapCursorTranslator(enabled: CursorTranslatorConfig.load().enabled, usable: usable)
        case .cursorGestures: AccessWindowController.tapCursorGestures(enabled: CursorGesturesConfig.load().enabled, usable: usable)
        case .rightClickMenu: AccessWindowController.tapRightClickMenu(save: saveRightClickMenu)
        case .cursorControl, .shortcut: return
        }
        read()
    }

    private func saveRightClickMenu(_ action: () throws -> Void) {
        do {
            try action()
            rightClickMenuError = nil
        } catch {
            rightClickMenuError = error.localizedDescription
        }
    }

    func read() {
        let helper = HelperToolManager.shared
        let manager = FinderExtensionManager.shared
        var granted: Set<WelcomeAccess> = []
        if FocusFollowsMouseConfig.accessibilityTrusted { granted.insert(.accessibility) }
        if CursorTranslatorConfig.screenRecordingAllowed { granted.insert(.screenRecording) }
        if manager.election == .elected { granted.insert(.finderExtension) }
        if manager.settings.hasFullDiskAccess { granted.insert(.fullDiskAccess) }
        let stored: [(WelcomeFeature, Bool)] = [
            (.showMenuBarIcon, MACPreferences.flag(MACPreferences.showMenuBarIconKey)), (.cursorTrails, CursorTrailsConfig.load().enabled),
            (.cursorHighlight, CursorHighlightConfig.load().enabled),
            (.cursorShadow, MACPreferences.flag(MACPreferences.cursorShadowKey)), (.focusOnHover, FocusFollowsMouseConfig.load().enabled),
            (.cursorGestures, CursorGesturesConfig.load().enabled), (.cursorShaker, CursorShakerConfig.load().enabled),
            (.cursorBoard, CursorBoardConfig.load().enabled), (.cursorTranslator, CursorTranslatorConfig.load().enabled),
            (.cursorCapture, CursorScreenshotConfig.load().enabled),
            (.rightClickMenu, RightClickMenuState.isOn(settings: manager.settings, election: manager.election)),
        ]
        let welcome = WelcomeSnapshot(
            access: WelcomeAccessState(helperInstalled: helper.isInstalled, helperRunning: helper.isRunning, granted: granted,
                                       translocated: manager.isTranslocated),
            stored: Set(stored.filter(\.1).map(\.0)),
            rightClickMenuBusy: manager.isBusy,
            rightClickMenuError: rightClickMenuError
        )
        let autoSwitch = AutoSwitchConfig.load()
        snapshot = OverviewSnapshot(welcome: welcome, perAppThemes: autoSwitch.switchByApp, themeAutomation: autoSwitch.enabled)
    }
}

struct MainPageView: View {
    let page: MainPage
    let updater: SPUUpdater?

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        switch page {
        case .themes: EmptyView()
        case .cursor: CursorSettingsView()
        case .cursorTrails: CursorTrailsSettingsView()
        case .cursorHighlight: CursorHighlightSettingsView()
        case .shortcut: ShortcutSettingsView()
        case .cursorScreenshot: CursorScreenshotSettingsView()
        case .cursorBoard: CursorBoardSettingsView()
        case .cursorTranslator: CursorTranslatorSettingsView()
        case .cursorGestures: CursorGesturesSettingsView()
        case .rightClickMenu: RightClickMenuSettingsView()
        case .settings: SettingsPageView(updater: updater)
        }
    }

    static func selectTab(_ page: MainPage, _ index: Int) {
        switch page {
        case .cursor: if let tab = pick(index, from: CursorControlTab.self) { CursorControlTab.selected = tab }
        case .cursorScreenshot: if let tab = pick(index, from: CursorScreenshotTab.self) { CursorScreenshotTab.selected = tab }
        case .cursorBoard: if let tab = pick(index, from: CursorBoardTab.self) { CursorBoardTab.selected = tab }
        case .cursorGestures: if let tab = pick(index, from: CursorGesturesTab.self) { CursorGesturesTab.selected = tab }
        case .rightClickMenu: if let tab = pick(index, from: RightClickMenuTab.self) { FinderExtensionManager.shared.selectedTab = tab }
        case .settings: if let tab = pick(index, from: SettingsPageTab.self) { SettingsPageTab.selected = tab }
        case .themes, .cursorTrails, .cursorHighlight, .shortcut, .cursorTranslator: break
        }
    }

    private static func pick<T: CaseIterable>(_ index: Int, from _: T.Type) -> T? where T.AllCases == [T] {
        T.allCases.indices.contains(index) ? T.allCases[index] : nil
    }
}
