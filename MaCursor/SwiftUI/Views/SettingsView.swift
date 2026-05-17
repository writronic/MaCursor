import SwiftUI
import AppKit
import Sparkle

import SwiftUI
import AppKit

private class SettingsPanel: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        close()
    }
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case general  = "General"
    case shortcut = "Shortcut"
    case about    = "About"
    
    var id: String { rawValue }
    
    var localizedName: String {
        switch self {
        case .general:  return String(localized: "General")
        case .shortcut: return String(localized: "Shortcut")
        case .about:    return String(localized: "About")
        }
    }
    
    var icon: String {
        switch self {
        case .general:  return "gear"
        case .shortcut: return "star"
        case .about:    return "info.circle"
        }
    }
}

struct SettingsSidebarView: View {
    @Binding var selectedTab: SettingsTab
    
    var body: some View {
        List(SettingsTab.allCases, selection: $selectedTab) { tab in
            Label(tab.localizedName, systemImage: tab.icon)
                .tag(tab)
        }
        .listStyle(.sidebar)
        .contentMargins(.top, 12, for: .scrollContent)
    }
}

final class SettingsWindowController: NSWindowController, NSToolbarDelegate {
    static let shared = SettingsWindowController()
    
    private let splitVC = NSSplitViewController()
    private static let sidebarTrackingID = NSToolbarItem.Identifier("sidebarTracking")
    
    private var library: LibraryViewModel?
    private var appearanceManager: AppearanceManager?
    private var languageManager: LanguageManager?
    private var updater: SPUUpdater?
    
    private var selectedTab: SettingsTab = .general {
        didSet {
            updateDetailView()
        }
    }
    
    private init() {
        let window = SettingsPanel(
            contentRect: NSRect(x: 0, y: 0, width: 750, height: 475),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        
        window.titleVisibility = .hidden
        window.title = String(localized: "Settings")
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("SettingsWindow")
        
        let toolbar = NSToolbar(identifier: "SettingsSplitToolbar")
        toolbar.showsBaselineSeparator = false
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        
        super.init(window: window)
        
        toolbar.delegate = self
        
        let sidebarVC = NSHostingController(rootView: AnyView(EmptyView()))
        let detailVC = NSHostingController(rootView: AnyView(EmptyView()))
        
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarVC)
        sidebarItem.canCollapse = false
        sidebarItem.minimumThickness = 160
        sidebarItem.maximumThickness = 160
        sidebarItem.allowsFullHeightLayout = true
        
        let detailItem = NSSplitViewItem(viewController: detailVC)
        
        splitVC.splitViewItems = [sidebarItem, detailItem]
        splitVC.splitView.dividerStyle = .thin
        
        window.contentViewController = splitVC
        
        let windowSize = NSSize(width: 750, height: 475)
        window.setContentSize(windowSize)
        window.minSize = windowSize
        window.maxSize = windowSize
        
        updateSidebarView()
        updateDetailView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func configure(library: LibraryViewModel, appearanceManager: AppearanceManager, languageManager: LanguageManager, updater: SPUUpdater? = nil) {
        self.library = library
        self.appearanceManager = appearanceManager
        self.languageManager = languageManager
        self.updater = updater
        updateDetailView()
    }
    
    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.center()
    }
    
    
    private func updateSidebarView() {
        let sidebarView = SettingsSidebarView(selectedTab: Binding(
            get: { self.selectedTab },
            set: { self.selectedTab = $0 }
        ))
        
        if let vc = splitVC.splitViewItems[0].viewController as? NSHostingController<AnyView> {
            vc.rootView = AnyView(sidebarView)
        }
    }
    
    private func updateDetailView() {
        guard let library = library, let appearanceManager = appearanceManager, let languageManager = languageManager else { return }
        
        var detailView: AnyView
        switch selectedTab {
        case .general:
            detailView = AnyView(GeneralSettingsView(updater: updater))
        case .shortcut:
            detailView = AnyView(ShortcutSettingsView())
        case .about:
            detailView = AnyView(AboutSettingsView())
        }
        
        let injectedView = AnyView(
            detailView
                .environment(library)
                .environment(appearanceManager)
                .environment(languageManager)
                .frame(minWidth: 265, maxWidth: .infinity, minHeight: 350, maxHeight: .infinity)
        )
        
        if let vc = splitVC.splitViewItems[1].viewController as? NSHostingController<AnyView> {
            vc.rootView = injectedView
        }
    }
    
    
    func toolbar(_ toolbar: NSToolbar,
                 itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if itemIdentifier == Self.sidebarTrackingID {
            return NSTrackingSeparatorToolbarItem(
                identifier: itemIdentifier,
                splitView: splitVC.splitView,
                dividerIndex: 0
            )
        }
        return nil
    }
    
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.sidebarTrackingID]
    }
    
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }
}
