import AppKit
import Combine

func MenuBarL(_ key: String) -> String {
    MACMenuBarLocalized(key)
}

struct MenuBarThemeItem: Identifiable, Hashable {
    let id: String
    let name: String
}

private struct ThumbnailBox: @unchecked Sendable {
    let image: NSImage?
}

@MainActor
final class MenuBarPanelModel: ObservableObject {
    static let shared = MenuBarPanelModel()

    @Published private(set) var themes: [MenuBarThemeItem] = []
    @Published private(set) var favoriteThemes: [MenuBarThemeItem] = []
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
    @Published private(set) var thumbnails: [String: NSImage] = [:]
    @Published private(set) var panelBackdropAlpha: Double = 0.0
    @Published var cursorScale: Double = 1.0

    let brandImage: NSImage? = MACMenuBarBrandImage()

    private let thumbnailQueue = DispatchQueue(label: "com.writronic.macursor.helper.thumbnails")
    private var thumbnailGeneration = 0
    private var observers: [NSObjectProtocol] = []

    init() {
        let names: [Notification.Name] = [
            .MACAutoSwitchDidChange,
            .MACAutoSwitchAppliedThemeDidChange,
            .MACFocusFollowsMouseStatusDidChange,
            .MACCursorPreferencesDidChange,
        ]
        for name in names {
            observers.append(DistributedNotificationCenter.default().addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.reload() }
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

    var appRuleChoices: [MenuBarThemeItem] {
        guard let rule = frontRuleThemeIdentifier,
              !favoriteThemes.contains(where: { $0.id == rule }),
              let ruled = themes.first(where: { $0.id == rule }) else { return favoriteThemes }
        return favoriteThemes + [ruled]
    }

    private static func items(from catalog: [[String: String]]) -> [MenuBarThemeItem] {
        catalog.compactMap { entry in
            guard let identifier = entry[MACMenuBarThemeIdentifierKey],
                  let name = entry[MACMenuBarThemeNameKey] else { return nil }
            return MenuBarThemeItem(id: identifier, name: name)
        }
    }

    func reload() {
        let snapshot = MACMenuBarCurrentSnapshot()
        themes = Self.items(from: snapshot.catalog)
        favoriteThemes = Self.items(from: snapshot.favorites)
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
        cursorScale = snapshot.cursorScale
        panelBackdropAlpha = snapshot.panelBackdropAlpha
        var wanted = favoriteThemes.map(\.id)
        if let visible = visibleIdentifier, !wanted.contains(visible) { wanted.append(visible) }
        loadThumbnails(for: wanted)
    }

    private func loadThumbnails(for identifiers: [String]) {
        thumbnailGeneration += 1
        let generation = thumbnailGeneration
        thumbnailQueue.async { [weak self] in
            for identifier in identifiers {
                let box = ThumbnailBox(image: MACMenuBarThumbnailForTheme(identifier))
                Task { @MainActor [weak self] in
                    guard let self, self.thumbnailGeneration == generation else { return }
                    self.thumbnails[identifier] = box.image
                }
            }
        }
    }

    func apply(theme identifier: String) {
        MACMenuBarApplyTheme(identifier)
        reload()
    }

    func restoreSystemCursors() {
        MACMenuBarRestoreSystemCursors()
        reload()
    }

    func setSwitchByApp(_ enabled: Bool) {
        MACMenuBarSetSwitchByApp(enabled)
        reload()
    }

    func setFrontAppRule(_ identifier: String?) {
        MACMenuBarSetFrontAppRule(identifier)
        reload()
    }

    func previewCursorScale(_ scale: Double) {
        cursorScale = scale
        MACMenuBarPreviewCursorScale(scale)
    }

    func commitCursorScale() {
        MACMenuBarCommitCursorScale(cursorScale)
        reload()
    }

    func setCursorShadow(_ enabled: Bool) {
        MACMenuBarSetCursorShadow(enabled)
        reload()
    }

    func toggleFocusFollowsMouse() {
        guard accessibilityTrusted else {
            MACMenuBarRequestFocusFollowsMouseAccess()
            return
        }
        MACMenuBarSetFocusFollowsMouse(!focusFollowsMouse)
        reload()
    }

    func openAccessibilitySettings() {
        MACMenuBarOpenAccessibilitySettings()
    }
}
