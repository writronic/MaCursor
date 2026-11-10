import Foundation

enum WelcomeAccess: CaseIterable {
    case accessibility
    case screenRecording
    case finderExtension
    case fullDiskAccess

    var title: String {
        switch self {
        case .accessibility: return String(localized: "Accessibility")
        case .screenRecording: return String(localized: "Screen Recording")
        case .finderExtension: return String(localized: "Finder Extension")
        case .fullDiskAccess: return String(localized: "Full Disk Access")
        }
    }
}

enum WelcomeHelperNeed {
    case none
    case installed
    case running
}

enum WelcomeGrant: Equatable {
    case openSystemSettings
    case copyCommand

    static func of(_ access: WelcomeAccess, pane: SystemSettingsPane.FinderExtensions = SystemSettingsPane.finderExtensions()) -> WelcomeGrant {
        access == .finderExtension && pane == .command ? .copyCommand : .openSystemSettings
    }
}

enum WelcomeFeature: CaseIterable {
    case showMenuBarIcon
    case cursorTrails
    case cursorShadow
    case focusOnHover
    case cursorGestures
    case cursorShaker
    case cursorTranslator
    case cursorCapture
    case rightClickMenu

    var title: String {
        switch self {
        case .showMenuBarIcon: return String(localized: "Show Menu Bar Icon")
        case .cursorTrails: return String(localized: "Cursor Trails")
        case .cursorShadow: return String(localized: "Cursor Shadow")
        case .focusOnHover: return String(localized: "Focus on Hover")
        case .cursorGestures: return String(localized: "Cursor Gestures")
        case .cursorShaker: return String(localized: "Cursor Shaker")
        case .cursorTranslator: return String(localized: "Cursor Translator")
        case .cursorCapture: return String(localized: "Cursor Capture")
        case .rightClickMenu: return String(localized: "Right-Click Menu")
        }
    }

    var caption: String {
        switch self {
        case .showMenuBarIcon: return String(localized: "Shows a MaCursor icon in the menu bar for quick access. If it does not appear, open System Settings and look in the Menu Bar section.")
        case .cursorTrails: return String(localized: "A trail follows the cursor as it moves and fades when it stops. The trail stays hidden while Reduce motion is on.")
        case .cursorShadow: return String(localized: "When enabled, a soft drop shadow is drawn under the cursor. The shadow appears while a cursor theme is applied.")
        case .focusOnHover: return String(localized: "When you hover over a window with the cursor, MaCursor raises it to the front and hands it the focus after a short delay.")
        case .cursorGestures: return String(localized: "Draw a shape with the pointer to run an action.")
        case .cursorShaker: return String(localized: "While you are away, the pointer moves one pixel and back, and the display stays on, so your apps keep showing you as active.")
        case .cursorTranslator: return String(localized: "Click with the trigger to open a frame. The text inside it turns into your language and keeps up as it changes.")
        case .cursorCapture: return String(localized: "Press the shortcut to take a picture of your screen.")
        case .rightClickMenu: return String(localized: "Adds MaCursor’s shortcuts to the right-click menu in Finder and on the Desktop.")
        }
    }

    var accesses: [WelcomeAccess] {
        switch self {
        case .showMenuBarIcon, .cursorTrails, .cursorShadow: return []
        case .focusOnHover, .cursorGestures, .cursorShaker: return [.accessibility]
        case .cursorTranslator: return [.screenRecording, .accessibility]
        case .cursorCapture: return [.screenRecording]
        case .rightClickMenu: return [.finderExtension, .fullDiskAccess]
        }
    }

    var menuBarItems: [MACMenuBarItem] {
        switch self {
        case .cursorTrails: return [.cursorTrails]
        case .cursorShadow: return [.cursorShadow]
        case .focusOnHover: return [.focusOnHover]
        case .cursorGestures: return [.cursorGestures]
        case .cursorShaker: return [.cursorShaker]
        case .cursorTranslator: return [.cursorTranslator]
        case .showMenuBarIcon, .cursorCapture, .rightClickMenu: return []
        }
    }

    var menuBarCaptureRows: [MACMenuBarCaptureRow] {
        self == .cursorCapture ? MACMenuBarCaptureRow.allCases : []
    }

    var helper: WelcomeHelperNeed {
        switch self {
        case .cursorShadow, .rightClickMenu: return .none
        case .showMenuBarIcon: return .installed
        case .cursorTrails, .focusOnHover, .cursorGestures, .cursorShaker, .cursorTranslator, .cursorCapture: return .running
        }
    }
}

enum WelcomeHelperLine {
    case install
    case notRunning
}

struct WelcomeAccessState: Equatable {
    var helperInstalled = false
    var helperRunning = false
    var granted: Set<WelcomeAccess> = []
    var translocated = false

    var helperLine: WelcomeHelperLine? {
        if !helperInstalled { return .install }
        return helperRunning ? nil : .notRunning
    }

    func isUsable(_ feature: WelcomeFeature) -> Bool {
        let helper: Bool
        switch feature.helper {
        case .none: helper = true
        case .installed: helper = helperInstalled
        case .running: helper = helperRunning
        }
        return helper && feature.accesses.allSatisfy(granted.contains)
    }

    func showsGrant(_ access: WelcomeAccess, on feature: WelcomeFeature) -> Bool {
        feature.accesses.contains(access) && !granted.contains(access) && (feature.helper == .none || helperInstalled)
            && !(access == .finderExtension && translocated)
    }
}
