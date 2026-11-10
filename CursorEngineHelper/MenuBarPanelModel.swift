import AppKit
import Combine

@MainActor
func MenuBarL(_ key: String) -> String {
    MenuBarService.localized(key)
}

@MainActor
final class MenuBarPanelModel: ObservableObject {
    static let shared = MenuBarPanelModel()

    @Published private(set) var themes: [MACMenuBarThemeEntry] = []
    @Published private(set) var favoriteThemes: [MACMenuBarThemeEntry] = []
    @Published private(set) var appliedIdentifier: String?
    @Published private(set) var overrideIdentifier: String?
    @Published private(set) var frontBundleIdentifier: String?
    @Published private(set) var frontDisplayName: String?
    @Published private(set) var frontIcon: NSImage?
    @Published private(set) var frontRuleThemeIdentifier: String?
    @Published private(set) var switchByApp = false
    @Published private(set) var cursorShadow = false
    @Published private(set) var focusFollowsMouse = false
    @Published private(set) var accessibilityTrusted = false
    @Published private(set) var cursorTrails = CursorTrailsConfig()
    @Published private(set) var cursorGestures = CursorGesturesConfig()
    @Published private(set) var cursorShaker = CursorShakerConfig()
    @Published private(set) var cursorTranslator = CursorTranslatorConfig()
    @Published private(set) var cursorScreenshot = CursorScreenshotConfig()
    @Published private(set) var screenRecording = false
    @Published private(set) var clipboardOffersImage = false
    @Published private(set) var thumbnails: [String: NSImage] = [:]
    @Published private(set) var panelBackdropAlpha: Double = 0.0
    @Published private(set) var panelBlocks: [MACMenuBarPanelBlock] = []
    @Published var cursorScale: Double = 1.0
    @Published var ffmDelayMs: Double = 100

    let brandImage: NSImage? = MenuBarService.brandImage()

    private let thumbnailLoader = MenuBarThumbnailLoader()
    private var thumbnailGeneration = 0
    private var observers: [NSObjectProtocol] = []
    var isShown = false
    var onCapture: (@MainActor (MACMenuBarCaptureItem) -> Void)?
    var onOpen: (@MainActor (MACMenuBarFileItem) -> Void)?

    init() {
        let names: [Notification.Name] = [
            .MACAutoSwitchDidChange,
            .MACAutoSwitchAppliedThemeDidChange,
            .MACFocusFollowsMouseStatusDidChange,
            .MACCursorTranslatorStatusDidChange,
            .MACCursorPreferencesDidChange,
        ]
        for name in names {
            observers.append(DistributedNotificationCenter.default().addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in guard let self, self.isShown else { return }; self.reload() }
            })
        }
    }

    var visibleIdentifier: String? {
        overrideIdentifier ?? appliedIdentifier
    }

    var visibleThemeName: String? {
        name(forTheme: visibleIdentifier)
    }

    func name(forTheme identifier: String?) -> String? {
        guard let identifier else { return nil }
        return themes.first { $0.id == identifier }?.name
    }

    func thumbnail(forTheme identifier: String?) -> NSImage? {
        guard let identifier else { return nil }
        return thumbnails[identifier]
    }

    var appRuleChoices: [MACMenuBarThemeEntry] {
        guard let rule = frontRuleThemeIdentifier,
              !favoriteThemes.contains(where: { $0.id == rule }),
              let ruled = themes.first(where: { $0.id == rule }) else { return favoriteThemes }
        return favoriteThemes + [ruled]
    }

    func reload() {
        let snapshot = MenuBarService.currentSnapshot()
        themes = snapshot.catalog
        favoriteThemes = snapshot.favorites
        appliedIdentifier = snapshot.appliedIdentifier
        overrideIdentifier = snapshot.overrideIdentifier
        frontBundleIdentifier = snapshot.frontBundleIdentifier
        frontDisplayName = snapshot.frontDisplayName
        frontIcon = snapshot.frontIcon
        frontRuleThemeIdentifier = snapshot.frontRuleThemeIdentifier
        switchByApp = snapshot.switchByApp
        cursorShadow = snapshot.cursorShadow
        focusFollowsMouse = snapshot.focusFollowsMouse
        accessibilityTrusted = snapshot.accessibilityTrusted
        cursorTrails = snapshot.cursorTrails
        cursorGestures = snapshot.cursorGestures
        cursorShaker = snapshot.cursorShaker
        cursorTranslator = snapshot.cursorTranslator
        screenRecording = snapshot.screenRecording
        cursorScale = snapshot.cursorScale
        ffmDelayMs = Double(snapshot.ffmDelayMs)
        panelBackdropAlpha = snapshot.panelBackdropAlpha
        cursorScreenshot = CursorScreenshotConfig.load()
        clipboardOffersImage = CursorScreenshotImageSource.offersImage(.general)
        panelBlocks = MACMenuBarPanelBlocks(
            order: MACMenuBarItemOrder(MACPreferences.value(forKey: MACPreferences.menuBarItemOrderKey)),
            hidden: MACMenuBarHiddenItems(MACPreferences.value(forKey: MACPreferences.menuBarHiddenItemsKey)),
            captureOrder: MACMenuBarCaptureRowOrder(MACPreferences.value(forKey: MACPreferences.menuBarCaptureOrderKey)),
            captureHidden: cursorScreenshot.enabled
                ? MACMenuBarHiddenCaptureRows(MACPreferences.value(forKey: MACPreferences.menuBarHiddenCaptureRowsKey))
                : Set(MACMenuBarCaptureRow.allCases))
        var wanted = favoriteThemes.map(\.id)
        if let visible = visibleIdentifier, !wanted.contains(visible) { wanted.append(visible) }
        loadThumbnails(for: wanted)
    }

    func capture(_ item: MACMenuBarCaptureItem) { onCapture?(item) }

    func isEnabled(_ item: MACMenuBarFileItem) -> Bool { item != .openClipboard || clipboardOffersImage }

    func open(_ item: MACMenuBarFileItem) { onOpen?(item) }

    func reloadTrails() {
        cursorTrails = CursorTrailsConfig.load()
    }

    func reloadShaker() {
        cursorShaker = CursorShakerConfig.load()
    }

    private func loadThumbnails(for identifiers: [String]) {
        thumbnailGeneration += 1
        let generation = thumbnailGeneration
        Task { [weak self, thumbnailLoader] in
            for identifier in identifiers {
                let record = await thumbnailLoader.thumbnail(for: identifier)
                guard let self, self.thumbnailGeneration == generation else { return }
                self.thumbnails[identifier] = record.flatMap {
                    MACMenuBarThumbnailImageFromData($0.thumbnail.data, $0.thumbnail.frameCount)
                }
            }
        }
    }

    func apply(theme identifier: String) {
        MenuBarService.applyTheme(identifier)
        reload()
    }

    func restoreSystemCursors() {
        MenuBarService.restoreSystemCursors()
        reload()
    }

    func setSwitchByApp(_ enabled: Bool) {
        MenuBarService.setSwitchByApp(enabled)
        reload()
    }

    func setFrontAppRule(_ identifier: String?) {
        MenuBarService.setFrontAppRule(identifier)
        reload()
    }

    func previewCursorScale(_ scale: Double) {
        cursorScale = scale
        MenuBarService.previewCursorScale(scale)
    }

    func commitCursorScale() {
        MenuBarService.commitCursorScale(cursorScale)
        reload()
    }

    func commitFocusFollowsMouseDelay() {
        MenuBarService.setFocusFollowsMouseDelay(Int(ffmDelayMs.rounded()))
        reload()
    }

    func setCursorShadow(_ enabled: Bool) {
        MenuBarService.setCursorShadow(enabled)
        reload()
    }

    func toggleFocusFollowsMouse() {
        guard accessibilityTrusted else {
            MenuBarService.requestFocusFollowsMouseAccess()
            return
        }
        MenuBarService.setFocusFollowsMouse(!focusFollowsMouse)
        reload()
    }

    func setCursorTrails(_ key: WritableKeyPath<CursorTrailsConfig, Bool>, _ value: Bool) {
        MenuBarService.setCursorTrails(key, value)
        reload()
    }

    var ignoresFrontApp: Bool {
        cursorGestures.ignores(frontBundleIdentifier)
    }

    func toggleCursorGestures() {
        guard accessibilityTrusted else {
            MenuBarService.requestCursorGesturesAccess()
            return
        }
        MenuBarService.setCursorGestures { $0.turn(!cursorGestures.enabled) }
        reload()
    }

    func toggleCursorShaker() {
        guard accessibilityTrusted else {
            MenuBarService.requestCursorShakerAccess()
            return
        }
        MenuBarService.setCursorShakerEnabled(!cursorShaker.enabled)
        reload()
    }

    func toggleCursorTranslator() {
        guard accessibilityTrusted, screenRecording else {
            MenuBarService.requestCursorTranslatorAccess()
            return
        }
        CursorTranslatorConfig.setEnabled(!cursorTranslator.enabled)
        reload()
    }

    func setCursorShakerStopAfter(_ minutes: Int?) {
        CursorShakerConfig.setStopAfter(minutes)
        reloadShaker()
    }

    func ignoreFrontApp(_ ignored: Bool) {
        guard let front = frontBundleIdentifier else { return }
        MenuBarService.setCursorGestures { $0.ignoreFully(front, ignored) }
        reload()
    }

    func openAccessibilitySettings() {
        MenuBarService.openAccessibilitySettings()
    }
}
