import AppKit
import SwiftUI

enum WelcomePage: Int, CaseIterable {
    case welcome
    case cursorLook
    case accessibility
    case screenRecording
    case rightClickMenu
    case menuBar
    case support
    case allSet

    var title: String {
        switch self {
        case .welcome: return String(localized: "Welcome to MaCursor")
        case .cursorLook: return String(localized: "Cursor Look")
        case .accessibility: return String(localized: "Accessibility")
        case .screenRecording: return String(localized: "Screen Recording")
        case .rightClickMenu: return String(localized: "Right-Click Menu")
        case .support: return String(localized: "Help Writronic keep growing")
        case .menuBar: return String(localized: "Menu Bar")
        case .allSet: return String(localized: "You’re All Set")
        }
    }

    var features: [WelcomeFeature] {
        switch self {
        case .welcome: return [.showMenuBarIcon]
        case .cursorLook: return [.cursorTrails, .cursorShadow]
        case .accessibility: return [.focusOnHover, .cursorGestures, .cursorShaker]
        case .screenRecording: return [.cursorTranslator, .cursorCapture]
        case .rightClickMenu: return [.rightClickMenu]
        case .support, .menuBar, .allSet: return []
        }
    }

    var isCentred: Bool {
        self == .support || self == .allSet
    }

    func shows(menuBar: Bool) -> Bool {
        self != .menuBar || menuBar
    }

    func next(menuBar: Bool) -> WelcomePage? {
        Self.allCases.first { $0.rawValue > rawValue && $0.shows(menuBar: menuBar) }
    }

    func previous(menuBar: Bool) -> WelcomePage? {
        Self.allCases.last { $0.rawValue < rawValue && $0.shows(menuBar: menuBar) }
    }

    func shown(menuBar: Bool) -> WelcomePage {
        shows(menuBar: menuBar) ? self : next(menuBar: menuBar) ?? self
    }

    static func shown(menuBar: Bool, current: WelcomePage) -> [WelcomePage] {
        allCases.filter { $0.shows(menuBar: menuBar) || $0 == current }
    }

    var warnsOnClose: Bool {
        self != .allSet
    }

    static func resumed(operations: MACPreferences.Operations = .live) -> WelcomePage? {
        (MACPreferences.value(forKey: MACPreferences.welcomePageKey, operations: operations) as? NSNumber).flatMap { WelcomePage(rawValue: $0.intValue) }
    }

    static func showsAtLaunch(operations: MACPreferences.Operations = .live) -> Bool {
        !MACPreferences.flag(MACPreferences.welcomeShownKey, operations: operations) || resumed(operations: operations) != nil
    }

    func save(operations: MACPreferences.Operations = .live) {
        MACPreferences.set(NSNumber(value: rawValue), forKey: MACPreferences.welcomePageKey, operations: operations)
    }

    static func clearSaved(operations: MACPreferences.Operations = .live) {
        MACPreferences.set(nil, forKey: MACPreferences.welcomePageKey, operations: operations)
    }
}

enum WelcomeLayout {
    static let styleMask: NSWindow.StyleMask = [.titled, .closable]
    static let frameSize = NSSize(width: 1075, height: 694)
    static let columnWidth: CGFloat = 640
    static let padding: CGFloat = 28
    static let menuBarCardHeight: CGFloat = 380

    static var contentSize: NSSize {
        NSWindow.contentRect(forFrameRect: NSRect(origin: .zero, size: frameSize), styleMask: styleMask).size
    }
}

struct WelcomeSnapshot {
    var access = WelcomeAccessState()
    var stored: Set<WelcomeFeature> = []
    var rightClickMenuBusy = false
    var rightClickMenuError: String?
    var finderPane = SystemSettingsPane.finderExtensions()

    var rightClickMenuLocked: Bool {
        rightClickMenuBusy || (access.translocated && !stored.contains(.rightClickMenu))
    }

    var showsMenuBarPage: Bool {
        access.helperInstalled && stored.contains(.showMenuBarIcon)
    }

    var showsCommandNote: Bool {
        finderPane == .command && !access.granted.contains(.finderExtension) && !access.translocated
    }

    func isOn(_ feature: WelcomeFeature) -> Bool {
        FocusFollowsMouseConfig.isOn(enabled: stored.contains(feature), trusted: access.isUsable(feature))
    }

    func menuBarRows(_ features: [WelcomeFeature]) -> (items: [MACMenuBarItem: Bool], captureRows: [MACMenuBarCaptureRow: Bool]) {
        var items: [MACMenuBarItem: Bool] = [:]
        var captureRows: [MACMenuBarCaptureRow: Bool] = [:]
        for feature in features {
            for item in feature.menuBarItems { items[item] = isOn(feature) }
            for row in feature.menuBarCaptureRows { captureRows[row] = isOn(feature) }
        }
        return (items, captureRows)
    }

    var menuBarSwitches: [WelcomeFeature: Bool] {
        Dictionary(uniqueKeysWithValues: WelcomeFeature.allCases.filter { !$0.menuBarItems.isEmpty || !$0.menuBarCaptureRows.isEmpty }.map { ($0, isOn($0)) })
    }

    func menuBarRowsToMatch(since synced: [WelcomeFeature: Bool]) -> [WelcomeFeature] {
        let switches = menuBarSwitches
        return WelcomeFeature.allCases.filter { switches[$0] != nil && switches[$0] != synced[$0] }
    }
}

struct WelcomeContent: View {
    let page: WelcomePage
    let snapshot: WelcomeSnapshot
    let toggle: (WelcomeFeature) -> Void
    let grant: (WelcomeAccess) -> Void
    let turn: (WelcomePage?) -> Void
    let pressMain: () -> Void
    var preferences: MACPreferences.Operations = .live

    var body: some View {
        VStack(spacing: 16) {
            WelcomePageView(page: page, snapshot: snapshot, toggle: toggle, grant: grant, preferences: preferences)
                .frame(maxHeight: .infinity, alignment: page.isCentred ? .center : .top)
            bottomRow
        }
        .padding(WelcomeLayout.padding)
        .controlSize(.large)
        .frame(width: WelcomeLayout.contentSize.width)
        .frame(minHeight: WelcomeLayout.contentSize.height)
    }

    private var bottomRow: some View {
        let previous = page.previous(menuBar: snapshot.showsMenuBarPage)
        return HStack(spacing: 0) {
            Button("Back") { turn(previous) }
                .disabled(previous == nil)
                .fixedSize()
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 0) {
                ForEach(WelcomePage.shown(menuBar: snapshot.showsMenuBarPage, current: page), id: \.self) { page in
                    dot(page)
                }
            }
            .accessibilityHidden(true)
            Button(action: pressMain) {
                ZStack {
                    Text("Next").hidden()
                    Text("Let’s Go!").hidden()
                    mainButtonLabel
                }
            }
            .keyboardShortcut(.defaultAction)
            .fixedSize()
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var mainButtonLabel: Text {
        page == .allSet ? Text("Let’s Go!") : Text("Next")
    }

    private func dot(_ page: WelcomePage) -> some View {
        let current = page == self.page
        return Circle()
            .fill(current ? Color.accentColor : Color.primary.opacity(0.45))
            .frame(width: current ? 10 : 7, height: current ? 10 : 7)
            .frame(width: 20, height: 20)
    }
}

struct WelcomePageView: View {
    static let starURL = URL(string: "https://github.com/writronic/MaCursor")!

    let page: WelcomePage
    let snapshot: WelcomeSnapshot
    let toggle: (WelcomeFeature) -> Void
    let grant: (WelcomeAccess) -> Void
    var preferences: MACPreferences.Operations = .live

    var body: some View {
        VStack(spacing: 16) {
            switch page {
            case .welcome: welcomeBody
            case .cursorLook: cursorLookBody
            case .accessibility: accessibilityBody
            case .screenRecording: screenRecordingBody
            case .rightClickMenu: rightClickMenuBody
            case .support: supportBody
            case .menuBar: menuBarBody
            case .allSet: allSetBody
            }
        }
        .multilineTextAlignment(.center)
        .frame(width: WelcomeLayout.columnWidth)
    }

    private var appIcon: some View {
        Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
            .resizable()
            .frame(width: 76, height: 76)
            .accessibilityHidden(true)
    }

    private func title(_ page: WelcomePage) -> some View {
        Text(page.title)
            .font(.title2.weight(.semibold))
            .accessibilityAddTraits(.isHeader)
    }

    private func note(_ text: Text) -> some View {
        text
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func helperNote(_ install: Text) -> some View {
        if let line = snapshot.access.helperLine {
            note(line == .install ? install : Text("The Helper Tool is not running. Quit and reopen MaCursor to start it."))
        }
    }

    @ViewBuilder
    private var welcomeBody: some View {
        appIcon
        title(.welcome)
        Text("Cursor Control for macOS")
            .font(.headline)
        Text("MaCursor gives you control over system cursors on macOS. On the next pages you can turn on extra features, or skip them.")
            .fixedSize(horizontal: false, vertical: true)
        VStack(alignment: .leading, spacing: 8) {
            HelperToolStatusView(showsUninstall: false)
                .frame(minHeight: 28)
            note(Text("The Helper Tool starts when you log in. It keeps your cursors after a restart and runs most features on the next pages. Install it now, or later in Settings → General."))
        }
        .multilineTextAlignment(.leading)
        .padding(RightClickMenuLayout.inset)
        .rightClickMenuCard()
        card(.showMenuBarIcon)
        if !snapshot.access.helperInstalled {
            note(Text("The menu bar icon is provided by the Helper Tool. Install it above to use it."))
        }
    }

    @ViewBuilder
    private var cursorLookBody: some View {
        appIcon
        title(.cursorLook)
        card(.cursorTrails)
        card(.cursorShadow)
        helperNote(Text("Install the Helper Tool on the first page to use Cursor Trails."))
    }

    @ViewBuilder
    private var accessibilityBody: some View {
        appIcon
        title(.accessibility)
        note(Text("Features on this page need Accessibility access for MaCursorHelper. If it is missing, choose Grant Permission to open System Settings."))
        card(.focusOnHover)
        card(.cursorGestures)
        card(.cursorShaker)
        helperNote(Text("Install the Helper Tool to use the switches on this page."))
    }

    @ViewBuilder
    private var screenRecordingBody: some View {
        appIcon
        title(.screenRecording)
        note(Text("Features on this page need Screen Recording access for MaCursor. Cursor Translator also needs Accessibility access for MaCursorHelper. If access is missing, choose Grant Permission to open System Settings."))
        card(.cursorTranslator)
        card(.cursorCapture)
        helperNote(Text("Install the Helper Tool to use the switches on this page."))
    }

    @ViewBuilder
    private var rightClickMenuBody: some View {
        appIcon
        title(.rightClickMenu)
        note(Text("This feature needs the Finder extension and Full Disk Access for MaCursor. If either is missing, choose Grant Permission to open System Settings."))
        card(.rightClickMenu)
        if snapshot.showsCommandNote {
            note(Text("macOS 15.0 and 15.1 cannot turn on Finder extensions from System Settings. Copy the command and run it in Terminal."))
        }
        if snapshot.access.translocated {
            note(Text("Move MaCursor to the Applications folder to use the Right-Click Menu."))
        }
        if let error = snapshot.rightClickMenuError {
            note(Text(error))
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var supportBody: some View {
        appIcon
        title(.support)
        Text("If you would like to support development, you can donate on the Writronic website.")
            .fixedSize(horizontal: false, vertical: true)
        Button {
            NSWorkspace.shared.open(MACConstants.donateURL)
        } label: {
            Label("Donate", systemImage: "heart.fill")
        }
        .buttonStyle(.borderedProminent)
        note(Text("Thank you for being here."))
        note(Text("A star on GitHub also helps more people find MaCursor, and it means a lot."))
        Button {
            NSWorkspace.shared.open(Self.starURL)
        } label: {
            Label("Give a Star", systemImage: "star")
        }
    }

    @ViewBuilder
    private var menuBarBody: some View {
        appIcon
        title(.menuBar)
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                MenuBarItemsSettingsView(preferences: preferences)
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(RightClickMenuLayout.inset)
        }
        .frame(height: WelcomeLayout.menuBarCardHeight)
        .rightClickMenuCard()
        note(MenuBarItemsSettingsView.caption)
    }

    @ViewBuilder
    private var allSetBody: some View {
        Image(systemName: "checkmark.circle.fill")
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, Color(nsColor: .systemGreen))
            .font(.system(size: 64))
            .accessibilityHidden(true)
        title(.allSet)
        Text("You can change any of this later in Settings.")
            .fixedSize(horizontal: false, vertical: true)
    }

    private func card(_ feature: WelcomeFeature) -> some View {
        let usable = snapshot.access.isUsable(feature)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(feature.title)
                    Text(feature.caption)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Toggle(feature.title, isOn: Binding(
                    get: { snapshot.isOn(feature) },
                    set: { _ in toggle(feature) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .disabled(!usable || (feature == .rightClickMenu && snapshot.rightClickMenuLocked))
            }
            .frame(minHeight: 32)
            if !feature.accesses.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(feature.accesses, id: \.self) { access in
                        line(access, on: feature)
                    }
                }
            }
        }
        .multilineTextAlignment(.leading)
        .padding(RightClickMenuLayout.inset)
        .rightClickMenuCard()
    }

    private func line(_ access: WelcomeAccess, on feature: WelcomeFeature) -> some View {
        let granted = snapshot.access.granted.contains(access)
        return HStack(spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(nsColor: granted ? .systemGreen : .systemRed))
                    .frame(width: 8, height: 8)
                Text(access.title)
                    .font(.callout)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(access.title))
            .accessibilityValue(granted ? Text("Access granted") : Text("Access not granted"))
            Spacer(minLength: 0)
            if snapshot.access.showsGrant(access, on: feature) {
                Button { grant(access) } label: {
                    WelcomeGrant.of(access, pane: snapshot.finderPane) == .copyCommand ? Text("Copy Command") : Text("Grant Permission")
                }
                .controlSize(.regular)
            }
        }
        .frame(minHeight: 22)
    }
}
