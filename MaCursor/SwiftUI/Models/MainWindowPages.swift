import SwiftUI

extension MainPage {
    static func takePendingSettingsRequest(operations: MACPreferences.Operations = .live) -> (page: MainPage, tab: Int?)? {
        operations.synchronize(MACPreferences.domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        guard MACPreferences.flag(MACPreferences.pendingOpenSettingsKey, operations: operations) else { return nil }
        MACPreferences.setFlag(false, forKey: MACPreferences.pendingOpenSettingsKey, operations: operations)
        let page = (MACPreferences.value(forKey: MACPreferences.pendingSettingsTabKey, operations: operations) as? String).flatMap(MainPage.init(rawValue:)) ?? .settings
        MACPreferences.set(nil, forKey: MACPreferences.pendingSettingsTabKey, operations: operations)
        return (page, page == .settings ? 0 : nil)
    }
}

enum MainPage: String, CaseIterable, Hashable, Identifiable {
    case themes = "Cursor Themes"
    case cursor = "Cursor Control"
    case cursorTrails = "Cursor Trails"
    case cursorHighlight = "Cursor Highlight"
    case shortcut = "Shortcut"
    case cursorScreenshot = "Cursor Capture"
    case cursorBoard = "Cursor Board"
    case cursorTranslator = "Cursor Translator"
    case cursorGestures = "Cursor Gestures"
    case rightClickMenu = "Right-Click Menu"
    case settings = "Settings"

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .themes: return String(localized: "Cursor Themes")
        case .cursor: return String(localized: "Cursor Control")
        case .cursorTrails: return String(localized: "Cursor Trails")
        case .cursorHighlight: return String(localized: "Cursor Highlight")
        case .shortcut: return String(localized: "Shortcut")
        case .cursorScreenshot: return String(localized: "Cursor Capture")
        case .cursorBoard: return String(localized: "Cursor Board")
        case .cursorTranslator: return String(localized: "Cursor Translator")
        case .cursorGestures: return String(localized: "Cursor Gestures")
        case .rightClickMenu: return String(localized: "Right-Click Menu")
        case .settings: return String(localized: "Settings")
        }
    }
}

enum MainWindowLayout {
    static let defaultSize = CGSize(width: 1200, height: 850)
    static let minimumContentSize = CGSize(width: 990, height: 560)
}

enum FeaturePageLayout {
    static let listWidth: CGFloat = 288, listLeading: CGFloat = 16, listTrailing: CGFloat = 12
    static var listColumn: CGFloat { listLeading + listWidth + listTrailing }
    static let rowHeight: CGFloat = 54, rowGap: CGFloat = 2, rowRadius: CGFloat = 10, rowPadding: CGFloat = 10, rowSpacing: CGFloat = 11
    static let tile: CGFloat = 32, tileRadius: CGFloat = 9, tileSymbol: CGFloat = 18
    static var textWidth: CGFloat { listWidth - 2 * rowPadding - tile - rowSpacing }
    static let boxTile: CGFloat = 40, boxTileRadius: CGFloat = 11, boxTileSymbol: CGFloat = 22
    static let boxRadius: CGFloat = 16, boxMinHeight: CGFloat = 64, cardRadius: CGFloat = 14
    static let sideMargin: CGFloat = 26, gap: CGFloat = 14
    static let formRowFloor: CGFloat = 20
    static let checkColumn: CGFloat = 108
    static let paneTopInset: CGFloat = 2, formTopInset: CGFloat = 20
    static let formColumn: CGFloat = 704
}

enum FeatureTint: CaseIterable {
    case blue, indigo, orange, green, purple, gray, teal, red, yellow

    var color: Color {
        switch self {
        case .blue: return .blue
        case .indigo: return .indigo
        case .orange: return .orange
        case .green: return .green
        case .purple: return .purple
        case .gray: return .gray
        case .teal: return .teal
        case .red: return .red
        case .yellow: return .yellow
        }
    }
}

struct FeatureTabStyle: Equatable {
    let subtitle: String
    let symbol: String
    let tint: FeatureTint
    let explainer: String?
}

enum FeatureTabCatalog {
    static func styles(for page: MainPage) -> [FeatureTabStyle] {
        switch page {
        case .cursor:
            return [
                FeatureTabStyle(subtitle: String(localized: "Scale, hand and shadow"), symbol: "cursorarrow", tint: .blue,
                                explainer: String(localized: "Choose how big the cursor is, which hand it is drawn for and whether it casts a shadow.")),
                FeatureTabStyle(subtitle: String(localized: "A theme for each app"), symbol: "macwindow.on.rectangle", tint: .indigo, explainer: nil),
                FeatureTabStyle(subtitle: String(localized: "Follow Light, Dark or the clock"), symbol: "clock.arrow.2.circlepath", tint: .orange, explainer: nil),
                FeatureTabStyle(subtitle: String(localized: "Focus follows the pointer"), symbol: "cursorarrow.and.square.on.square.dashed", tint: .green, explainer: nil),
                FeatureTabStyle(subtitle: String(localized: "Start, stop and shortcut"), symbol: "cursorarrow.rays", tint: .purple,
                                explainer: String(localized: "Choose when the shaker starts and stops, and which shortcut runs it.")),
            ]
        case .cursorScreenshot:
            return [
                FeatureTabStyle(subtitle: String(localized: "Sounds, export, after capture"), symbol: "slider.horizontal.3", tint: .gray,
                                explainer: String(localized: "Choose the sounds, where files go and what happens right after a capture.")),
                FeatureTabStyle(subtitle: String(localized: "Area, previous area, fullscreen"), symbol: "keyboard", tint: .blue,
                                explainer: String(localized: "Give each kind of capture a keyboard shortcut or a mouse button.")),
                FeatureTabStyle(subtitle: String(localized: "Where the overlay sits"), symbol: "rectangle.on.rectangle", tint: .orange,
                                explainer: String(localized: "The overlay shows your latest capture. Choose where it sits on the screen.")),
                FeatureTabStyle(subtitle: String(localized: "Format, cursor, freeze"), symbol: "photo", tint: .green,
                                explainer: String(localized: "Choose the file format and what a screenshot includes.")),
                FeatureTabStyle(subtitle: String(localized: "File name and history"), symbol: "gearshape", tint: .indigo,
                                explainer: String(localized: "Choose how files are named and how long Capture keeps its history.")),
            ]
        case .cursorBoard:
            return [
                FeatureTabStyle(subtitle: String(localized: "How long and how many"), symbol: "slider.horizontal.3", tint: .gray,
                                explainer: String(localized: "Choose how long Cursor Board keeps what you copy, and how many items it holds.")),
                FeatureTabStyle(subtitle: String(localized: "Recent items and the panel"), symbol: "keyboard", tint: .blue,
                                explainer: String(localized: "Set the shortcuts that show recent items and the Cursor Board panel.")),
                FeatureTabStyle(subtitle: String(localized: "Position and screen edge"), symbol: "sidebar.right", tint: .teal,
                                explainer: String(localized: "Choose where the side panel opens.")),
                FeatureTabStyle(subtitle: String(localized: "Apps Cursor Board skips"), symbol: "eye.slash", tint: .red,
                                explainer: String(localized: "Cursor Board does not keep what you copy in these apps.")),
            ]
        case .cursorGestures:
            return [
                FeatureTabStyle(subtitle: String(localized: "Line, color, strictness"), symbol: "slider.horizontal.3", tint: .gray, explainer: nil),
                FeatureTabStyle(subtitle: String(localized: "Search and add gestures"), symbol: "scribble", tint: .purple, explainer: nil),
                FeatureTabStyle(subtitle: String(localized: "Draw and name shapes"), symbol: "square.on.circle", tint: .orange, explainer: nil),
                FeatureTabStyle(subtitle: String(localized: "Make your own actions"), symbol: "bolt", tint: .green, explainer: nil),
            ]
        case .rightClickMenu:
            return [
                FeatureTabStyle(subtitle: String(localized: "Open With, New File, Common Apps"), symbol: "list.bullet", tint: .blue, explainer: nil),
                FeatureTabStyle(subtitle: String(localized: "Copy path, hide and unhide files"), symbol: "bolt", tint: .orange, explainer: nil),
                FeatureTabStyle(subtitle: String(localized: "File types for New File"), symbol: "doc.badge.plus", tint: .green, explainer: nil),
                FeatureTabStyle(subtitle: String(localized: "Apps for the selected files"), symbol: "arrow.up.forward.app", tint: .indigo, explainer: nil),
                FeatureTabStyle(subtitle: String(localized: "Apps for the current folder"), symbol: "square.grid.2x2", tint: .teal, explainer: nil),
            ]
        case .settings:
            return [
                FeatureTabStyle(subtitle: String(localized: "Appearance, language, updates"), symbol: "gearshape", tint: .gray,
                                explainer: String(localized: "Choose how MaCursor looks, which language it uses and how it keeps itself up to date.")),
                FeatureTabStyle(subtitle: String(localized: "Version and license"), symbol: "info.circle", tint: .blue, explainer: nil),
            ]
        case .themes, .cursorTrails, .cursorHighlight, .shortcut, .cursorTranslator:
            return []
        }
    }
}

enum OverviewSection: CaseIterable {
    case cursorControl, cursorTools

    var title: String {
        switch self {
        case .cursorControl: return String(localized: "Cursor Control")
        case .cursorTools: return String(localized: "Cursor Tools")
        }
    }

    var cards: [OverviewCard] {
        switch self {
        case .cursorControl: return [.cursorControl, .perAppThemes, .themeAutomation, .focusOnHover, .cursorShaker, .shortcut]
        case .cursorTools: return [.cursorCapture, .cursorBoard, .cursorTranslator, .cursorGestures, .rightClickMenu, .cursorTrails, .cursorHighlight]
        }
    }
}

enum OverviewCard: CaseIterable {
    case cursorControl, perAppThemes, themeAutomation, focusOnHover, cursorShaker, shortcut,
         cursorCapture, cursorBoard, cursorTranslator, cursorGestures, rightClickMenu, cursorTrails, cursorHighlight

    static let minWidth: CGFloat = 210, height: CGFloat = 94, padding: CGFloat = 12, spacing: CGFloat = 12, heroHeight: CGFloat = 96

    var title: String {
        switch self {
        case .cursorControl: return String(localized: "Cursor Control")
        case .perAppThemes: return String(localized: "Per-App Themes")
        case .themeAutomation: return String(localized: "Theme Automation")
        case .focusOnHover: return String(localized: "Focus on Hover")
        case .cursorShaker: return String(localized: "Cursor Shaker")
        case .cursorTrails: return String(localized: "Cursor Trails")
        case .cursorHighlight: return String(localized: "Cursor Highlight")
        case .shortcut: return String(localized: "Shortcut")
        case .cursorCapture: return String(localized: "Cursor Capture")
        case .cursorBoard: return String(localized: "Cursor Board")
        case .cursorTranslator: return String(localized: "Cursor Translator")
        case .cursorGestures: return String(localized: "Cursor Gestures")
        case .rightClickMenu: return String(localized: "Right-Click Menu")
        }
    }

    var symbol: String {
        switch self {
        case .cursorControl: return "cursorarrow"
        case .perAppThemes: return "macwindow.on.rectangle"
        case .themeAutomation: return "clock.arrow.2.circlepath"
        case .focusOnHover: return "cursorarrow.and.square.on.square.dashed"
        case .cursorShaker: return "cursorarrow.rays"
        case .cursorTrails: return "cursorarrow.motionlines"
        case .cursorHighlight: return "cursorarrow.click.2"
        case .shortcut: return "star"
        case .cursorCapture: return "camera.viewfinder"
        case .cursorBoard: return "list.clipboard"
        case .cursorTranslator: return "character.bubble"
        case .cursorGestures: return "scribble.variable"
        case .rightClickMenu: return "contextualmenu.and.cursorarrow"
        }
    }

    var tint: FeatureTint {
        switch self {
        case .cursorControl: return .blue
        case .perAppThemes, .rightClickMenu: return .indigo
        case .themeAutomation, .cursorBoard, .cursorHighlight: return .orange
        case .focusOnHover, .cursorTranslator: return .green
        case .cursorShaker, .cursorGestures: return .purple
        case .cursorTrails: return .teal
        case .shortcut: return .yellow
        case .cursorCapture: return .red
        }
    }

    var page: MainPage {
        switch self {
        case .cursorControl, .perAppThemes, .themeAutomation, .focusOnHover, .cursorShaker: return .cursor
        case .cursorTrails: return .cursorTrails
        case .cursorHighlight: return .cursorHighlight
        case .shortcut: return .shortcut
        case .cursorCapture: return .cursorScreenshot
        case .cursorBoard: return .cursorBoard
        case .cursorTranslator: return .cursorTranslator
        case .cursorGestures: return .cursorGestures
        case .rightClickMenu: return .rightClickMenu
        }
    }

    var tab: Int? {
        switch self {
        case .cursorControl: return 0
        case .perAppThemes: return 1
        case .themeAutomation: return 2
        case .focusOnHover: return 3
        case .cursorShaker: return 4
        case .cursorTrails, .cursorHighlight, .shortcut, .cursorCapture, .cursorBoard, .cursorTranslator, .cursorGestures, .rightClickMenu: return nil
        }
    }

    var feature: WelcomeFeature? {
        switch self {
        case .cursorControl, .perAppThemes, .themeAutomation, .shortcut: return nil
        case .focusOnHover: return .focusOnHover
        case .cursorShaker: return .cursorShaker
        case .cursorTrails: return .cursorTrails
        case .cursorHighlight: return .cursorHighlight
        case .cursorCapture: return .cursorCapture
        case .cursorBoard: return .cursorBoard
        case .cursorTranslator: return .cursorTranslator
        case .cursorGestures: return .cursorGestures
        case .rightClickMenu: return .rightClickMenu
        }
    }

    var hasSwitch: Bool { self != .cursorControl && self != .shortcut }
}

struct OverviewSnapshot {
    var welcome = WelcomeSnapshot()
    var perAppThemes = false
    var themeAutomation = false

    func isOn(_ card: OverviewCard) -> Bool {
        switch card {
        case .perAppThemes: return perAppThemes
        case .themeAutomation: return themeAutomation
        default: return card.feature.map(welcome.isOn) ?? false
        }
    }

    func isLocked(_ card: OverviewCard) -> Bool {
        guard card.hasSwitch else { return false }
        return card == .rightClickMenu ? welcome.rightClickMenuLocked : !welcome.access.helperInstalled
    }

    func statusIsError(_ card: OverviewCard) -> Bool {
        card == .rightClickMenu && welcome.rightClickMenuError != nil
    }

    func statusText(_ card: OverviewCard) -> String? {
        if statusIsError(card) { return welcome.rightClickMenuError }
        switch card.feature?.accesses.first(where: { !welcome.access.granted.contains($0) }) {
        case .accessibility: return String(localized: "Needs Accessibility access")
        case .screenRecording: return String(localized: "Needs Screen Recording access")
        case .finderExtension: return String(localized: "Needs the Finder extension")
        case .fullDiskAccess: return String(localized: "Needs Full Disk Access")
        case nil: return nil
        }
    }
}
