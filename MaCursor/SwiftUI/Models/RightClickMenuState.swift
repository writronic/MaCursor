import Foundation

enum FinderExtensionElection: Equatable {
    case unregistered
    case registered
    case ignored
    case elected
}

enum RightClickMenuToggleAction: Equatable {
    case enable
    case disable
    case requestAccess
}

enum RightClickMenuAccessStep {
    case finderExtension
    case fullDiskAccess

    var title: String {
        switch self {
        case .finderExtension: return String(localized: "Finder Extension")
        case .fullDiskAccess: return String(localized: "Full Disk Access")
        }
    }

    var progress: String {
        switch self {
        case .finderExtension: return String(localized: "Step 1 of 2")
        case .fullDiskAccess: return String(localized: "Step 2 of 2")
        }
    }
}

enum RightClickMenuTab: CaseIterable, Identifiable {
    case mainMenu
    case actions
    case newFile
    case openWith
    case commonApps

    var id: Self { self }

    var title: String {
        switch self {
        case .mainMenu: return String(localized: "Main Menu")
        case .actions: return String(localized: "Actions")
        case .newFile: return String(localized: "New File")
        case .openWith: return String(localized: "Open With")
        case .commonApps: return String(localized: "Common Apps")
        }
    }

    var note: String {
        switch self {
        case .mainMenu: return String(localized: "Everything that is on, in the order Finder shows it. Drag a row to move it.")
        case .actions: return String(localized: "Turn items on or off. Items that are on show in Main Menu.")
        case .newFile: return String(localized: "File types you can create from the right-click menu.")
        case .openWith: return String(localized: "Opens the selected files in one of these apps.")
        case .commonApps: return String(localized: "Opens the current folder in one of these apps.")
        }
    }
}

enum RightClickMenuShowsOn: CaseIterable {
    case files
    case emptySpace
    case filesAndEmptySpace

    init(_ item: RightClickMenuItem) {
        switch (item.shows(in: .items), item.shows(in: .container)) {
        case (true, false): self = .files
        case (false, true): self = .emptySpace
        default: self = .filesAndEmptySpace
        }
    }

    var title: String {
        switch self {
        case .files: return String(localized: "Files")
        case .emptySpace: return String(localized: "Empty space")
        case .filesAndEmptySpace: return String(localized: "Files and empty space")
        }
    }

    var caption: String {
        switch self {
        case .files: return String(localized: "Shows on files")
        case .emptySpace: return String(localized: "Shows on empty space")
        case .filesAndEmptySpace: return String(localized: "Shows on files and empty space")
        }
    }
}

enum RightClickMenuState {
    static let extensionBundleIdentifier = "com.writronic.macursor.finder"
    static let enableCommand = "pluginkit -e use -i \(extensionBundleIdentifier)"

    static func election(fromPluginkitRow row: String) -> FinderExtensionElection {
        guard let first = row.trimmingCharacters(in: .whitespacesAndNewlines).first else { return .unregistered }
        switch first {
        case "+": return .elected
        case "-": return .ignored
        case "!", "=", "?": return .registered
        default: return .registered
        }
    }

    static func isTranslocated(bundlePath: String) -> Bool {
        bundlePath.contains("/AppTranslocation/")
    }

    static func isOn(settings: RightClickMenuSettings, election: FinderExtensionElection) -> Bool {
        settings.isActive && election == .elected
    }

    static func showsItems(settings: RightClickMenuSettings, election: FinderExtensionElection) -> Bool {
        isOn(settings: settings, election: election)
    }

    static func toggleAction(settings: RightClickMenuSettings, election: FinderExtensionElection) -> RightClickMenuToggleAction {
        if isOn(settings: settings, election: election) { return .disable }
        return election == .elected && settings.hasFullDiskAccess ? .enable : .requestAccess
    }

    static func accessStep(election: FinderExtensionElection) -> RightClickMenuAccessStep {
        election == .elected ? .fullDiskAccess : .finderExtension
    }

    static func asksForFullDiskAccessAtLaunch(enabled: Bool, hasFullDiskAccess: Bool, alreadyAsked: Bool) -> Bool {
        enabled && !hasFullDiskAccess && !alreadyAsked
    }

    static func fullDiskAccessProbeArguments(home: URL) -> [String] {
        ["-c", "true < \"$1\" || true < \"$2\"", "sh"]
            + ["Library/Application Support/com.apple.TCC/TCC.db", "Library/Safari/Bookmarks.plist"].map { home.appendingPathComponent($0).path }
    }
}

enum RightClickMenuLayout {
    static let contentMaxWidth: CGFloat = 704
    static let pageMargin: CGFloat = 20
    static let inset: CGFloat = 10
    static let cardRadius: CGFloat = 12
    static let blockSpacing: CGFloat = 10
    static let rowHeight: CGFloat = 40
    static let twoLineRowHeight: CGFloat = 52
    static let handleColumn: CGFloat = 20
    static let columnSpacing: CGFloat = 12
    static let iconSize: CGFloat = 16
    static let iconGap: CGFloat = 8
    static let iconColumn: CGFloat = iconSize + iconGap
    static let chevronAllowance: CGFloat = 17
    static let itemColumnCap: CGFloat = 270
    static let miniSwitchWidth: CGFloat = 36
    static let popUpChrome: CGFloat = 48
    static let bodyFontSize: CGFloat = 13
    static let calloutFontSize: CGFloat = 12

    static func tableWidth(contentWidth: CGFloat) -> CGFloat {
        min(contentWidth, contentMaxWidth)
    }

    static func itemColumnWidth(plainTitleWidths: [CGFloat], groupTitleWidths: [CGFloat], headingWidth: CGFloat) -> CGFloat {
        let plain = plainTitleWidths.max() ?? 0
        let group = (groupTitleWidths.max() ?? 0) + chevronAllowance
        return min(itemColumnCap, max(iconColumn + max(plain, group), iconColumn + headingWidth))
    }

    static func showsOnColumnWidth(valueWidths: [CGFloat], headingWidth: CGFloat) -> CGFloat {
        max(valueWidths.max() ?? 0, headingWidth)
    }

    static func containsColumnWidth(tableWidth: CGFloat, item: CGFloat, showsOn: CGFloat) -> CGFloat {
        tableWidth - 2 * inset - handleColumn - 2 * columnSpacing - item - showsOn
    }

    static func showInColumnWidth(titleWidths: [CGFloat], headingWidth: CGFloat) -> CGFloat {
        max((titleWidths.max() ?? 0) + popUpChrome, headingWidth)
    }

    static func appTextColumnWidth(tableWidth: CGFloat, enable: CGFloat, showIn: CGFloat) -> CGFloat {
        tableWidth - 2 * inset - iconSize - 2 * iconGap - enable - columnSpacing - showIn
    }
}
