import AppKit
import Sparkle
import SwiftUI

extension SettingsFileEffects {
    @MainActor static func app(library: LibraryViewModel, appearanceManager: AppearanceManager, updater: SPUUpdater?) -> SettingsFileEffects {
        SettingsFileEffects { groups in
            if groups.contains(.general) {
                let mode = (MACPreferences.value(forKey: MACPreferences.appearanceModeKey) as? NSNumber)?.intValue ?? 0
                appearanceManager.currentMode = AppearanceMode(rawValue: mode) ?? .system
                updater?.automaticallyChecksForUpdates = MACPreferences.flag(SettingsFileGroup.automaticChecksKey)
                NotificationCenter.default.post(name: .cursorIdentifiersChanged, object: nil)
                FollowReduceMotionSection.notifyHelper()
            }
            if groups.contains(.cursorControl) {
                AutoSwitchConfig.notifyHelper()
                NotificationCenter.default.post(name: .macAutoSwitchConfigDidChange, object: nil)
                FocusFollowsMouseConfig.notifyHelper()
                CursorShakerConfig.notifyHelper()
                let scale = CursorScaleInput.clamp((MACPreferences.value(forKey: MACPreferences.cursorScaleKey) as? NSNumber)?.doubleValue ?? 1)
                CursorService.setScale(Float(max(1.0, scale)))
                if let applied = library.cursorThemes.first(where: { $0.isApplied }) {
                    library.apply(applied)
                } else {
                    CursorService.restoreAll()
                }
                NotificationCenter.default.post(name: .hideTahoeCursorsChanged, object: nil)
            }
            if groups.contains(.cursorCapture) { CursorScreenshotConfig.notifyHelper() }
            if groups.contains(.cursorBoard) { CursorBoardConfig.notifyHelper() }
            if groups.contains(.cursorTranslator) { CursorTranslatorConfig.notifyHelper() }
            if groups.contains(.cursorGestures) { CursorGesturesConfig.notifyHelper() }
            if groups.contains(.cursorTrails) { CursorTrailsConfig.notifyHelper() }
            if groups.contains(.cursorHighlight) { CursorHighlightConfig.notifyHelper() }
            if groups.contains(.rightClickMenu) { FinderExtensionManager.shared.refresh() }
            if groups.contains(.shortcut) { ShortcutManager.shared.notifyConfigChanged() }
            DistributedNotificationCenter.default().postNotificationName(.MACMenuBarDidChange, object: nil, userInfo: nil, deliverImmediately: true)
            MainWindowRouter.shared.reloadPage()
        }
    }
}

enum SettingsPageTab: Int, CaseIterable {
    case general, about

    @MainActor static var selected = SettingsPageTab.general

    var title: String {
        switch self {
        case .general: return String(localized: "General")
        case .about: return String(localized: "About")
        }
    }
}

struct SettingsPageView: View {
    var updater: SPUUpdater?

    @State private var tab = SettingsPageTab.selected

    var body: some View {
        FeaturePageFrame(header: { EmptyView() }, tabs: {
            FeatureTabList(titles: SettingsPageTab.allCases.map(\.title), styles: FeatureTabCatalog.styles(for: .settings), label: String(localized: "Settings"),
                           selection: Binding(get: { tab.rawValue },
                                              set: { tab = SettingsPageTab(rawValue: $0) ?? .general; SettingsPageTab.selected = tab }))
        }, pane: {
            switch tab {
            case .general: GeneralSettingsView(updater: updater)
            case .about: AboutSettingsView()
            }
        })
    }
}

struct GeneralSettingsView: View {
    var updater: SPUUpdater?

    @EnvironmentObject private var appearanceManager: AppearanceManager
    @EnvironmentObject private var languageManager: LanguageManager
    @EnvironmentObject private var library: LibraryViewModel

    @State private var showResetConfirmation = false
    @State private var showRestartAlert = false
    @ObservedObject private var helperManager = HelperToolManager.shared
    @State private var showMenuBarIcon = MACPreferences.flag(MACPreferences.showMenuBarIconKey)
    @State private var showCursorIdentifiers = MACPreferences.showCursorIdentifiers
    @State private var panelBackground = MACMenuBarPanelBackgroundLevel(MACPreferences.value(forKey: MACPreferences.menuBarPanelBackgroundKey))

    var body: some View {
        Form {
            if let explainer = FeatureTabCatalog.styles(for: .settings)[SettingsPageTab.general.rawValue].explainer {
                ExplainerSection(explainer)
            }

            FeatureSection("Appearance") {
                Picker("Appearance", selection: $appearanceManager.currentMode) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Label(mode.label, systemImage: mode.icon)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .searchAnchor("setAppearance")

                Toggle("Show Cursor Identifiers", isOn: $showCursorIdentifiers)
                    .onChangeCompat(of: showCursorIdentifiers) { newValue in
                        MACPreferences.setFlag(newValue, forKey: MACPreferences.showCursorIdentifiersKey)
                        NotificationCenter.default.post(name: .cursorIdentifiersChanged, object: nil)
                    }
                    .searchAnchor("setIdentifiers")
            }

            CursorCanvasPaddingSection {
                if let applied = library.cursorThemes.first(where: { $0.isApplied }) {
                    library.apply(applied)
                }
            }

            FollowReduceMotionSection()

            FeatureSection("Language") {
                Picker("Language", selection: $languageManager.currentLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName)
                            .tag(language)
                    }
                }
                .searchAnchor("setLanguage")
            }

            FeatureSection("Helper Tool") {
                HelperToolStatusView()
                    .searchAnchor("setHelper")
            }

            FeatureSection("Menu Bar", footer: "Shows a MaCursor icon in the menu bar for quick access. If it does not appear, open System Settings and look in the Menu Bar section.") {
                Toggle("Show Menu Bar Icon", isOn: $showMenuBarIcon)
                    .disabled(!helperManager.isInstalled)
                    .onChangeCompat(of: showMenuBarIcon) { newValue in
                        GeneralSettingsView.setShowMenuBarIcon(newValue)
                    }
                    .searchAnchor("setMenuIcon")

                if !helperManager.isInstalled {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)

                        Text("The menu bar icon is provided by the Helper Tool. Install it above to use it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if showMenuBarIcon && helperManager.isInstalled {
                FeatureSection {
                    MenuBarItemsSettingsView()
                } footer: {
                    MenuBarItemsSettingsView.caption
                }
            }

            FeatureSection(footer: "Sets how see-through the menu bar panel is: the middle of the slider is the standard frosted glass, the minimum is clear, the maximum is solid.") {
                HStack(spacing: 12) {
                    Text("Panel Background")
                    Slider(value: $panelBackground, in: 0...1)
                        .accessibilityLabel("Panel Background")
                    Text(panelBackground, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
                .disabled(!helperManager.isInstalled || !showMenuBarIcon)
                .onChangeCompat(of: panelBackground) { newValue in
                    MACPreferences.set(NSNumber(value: newValue), forKey: MACPreferences.menuBarPanelBackgroundKey)
                }
                .searchAnchor("setPanelBg")
            }

            if let updater = updater {
                FeatureSection("Software Updates") {
                    Toggle("Automatically check for updates", isOn: Binding(
                        get: { updater.automaticallyChecksForUpdates },
                        set: { updater.automaticallyChecksForUpdates = $0 }
                    ))
                    .searchAnchor("setUpdates")
                }
            }

            SettingsFileSection()

            FeatureSection("Reset Settings") {
                HStack {
                    Text("Reset all settings to default values (cannot be undone)")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        showResetConfirmation = true
                    } label: {
                        Text("Reset")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(.red, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
                .searchAnchor("setReset")
            }
        }
        .formStyle(.grouped)
        .alert("Reset All Settings?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                performFullReset()
            }
        } message: {
            Text("This will remove all cursor themes, restore system cursors, and reset every preference to its default value. This action cannot be undone.")
        }
        .alert("Restart Required", isPresented: $showRestartAlert) {
            Button("Restart Now") {
                languageManager.restartApp()
            }
            Button("Later", role: .cancel) { }
        } message: {
            Text("The language change will take effect after restarting MaCursor.")
        }
        .onChangeCompat(of: languageManager.needsRestart) { needsRestart in
            if needsRestart {
                showRestartAlert = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .cursorSettingsDidReset)) { _ in
            showMenuBarIcon = MACPreferences.flag(MACPreferences.showMenuBarIconKey)
            showCursorIdentifiers = MACPreferences.showCursorIdentifiers
            panelBackground = MACMenuBarPanelBackgroundLevel(nil)
        }
    }


    static func setShowMenuBarIcon(_ shown: Bool) {
        MACPreferences.setFlag(shown, forKey: MACPreferences.showMenuBarIconKey)
        DistributedNotificationCenter.default().postNotificationName(
            .MACMenuBarDidChange,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    private func performFullReset() {
        var errors: [any Error] = []
        do {
            try library.removeAllThemes()
        } catch {
            errors.append(error)
        }

        CursorService.setScale(CursorService.defaultScale())

        for key in MACPreferences.resetKeys {
            MACPreferences.set(nil, forKey: key)
        }
        CursorTranslatorService.allCases.forEach { CursorTranslatorKeychain.set("", for: $0) }
        CursorScreenshot.removeCopiedFiles(support: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
                                           group: FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: RightClickMenuSettings.appGroupIdentifier))
        CursorBoardStore(root: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(CursorBoard.folder, isDirectory: true)).removeAll()
        CursorBoardConfig.notifyHelper()
        AutoSwitchConfig.notifyHelper()
        FocusFollowsMouseConfig.notifyHelper()
        CursorTrailsConfig.notifyHelper()
        CursorHighlightConfig.notifyHelper()
        CursorGesturesConfig.notifyHelper()
        CursorShakerConfig.notifyHelper()
        CursorScreenshotConfig.notifyHelper()
        CursorTranslatorConfig.notifyHelper()
        ShortcutManager.shared.notifyConfigChanged()

        do {
            try FinderExtensionManager.shared.resetSettings()
        } catch {
            errors.append(error)
        }

        appearanceManager.currentMode = .system
        languageManager.currentLanguage = .system
        languageManager.needsRestart = false
        UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()

        UserDefaults.standard.removeObject(forKey: "SUEnableAutomaticChecks")

        MACPreferences.set(NSNumber(value: 1.0), forKey: MACPreferences.cursorScaleKey)
        CursorService.setScale(1.0)
        CursorService.restoreAll()

        NotificationCenter.default.post(name: .cursorSettingsDidReset, object: nil)

        let helperManager = HelperToolManager.shared
        var uninstall: (@Sendable () async -> Void)?
        if helperManager.isInstalled {
            uninstall = { try? await helperManager.uninstall() }
        }
        Task { [errors, uninstall] in
            await WelcomePage.relaunch(afterReset: errors, uninstallingHelper: uninstall,
                                       present: { NSApp.presentError($0) }, relaunch: { languageManager.restartApp() })
        }
    }

}

struct HelperToolStatusView: View {
    @ObservedObject private var helperManager = HelperToolManager.shared
    @State private var errorMessage: String?
    @State private var isProcessing: Bool = false
    private let showsUninstall: Bool

    init(showsUninstall: Bool = true) {
        self.showsUninstall = showsUninstall
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(helperManager.isRunning ? .green : (helperManager.isInstalled ? .orange : .secondary))
                        .frame(width: 8, height: 8)

                    Text(helperManager.statusDescription)
                        .font(.callout)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Spacer()

            if showsUninstall || !helperManager.isInstalled {
                Button(helperManager.isInstalled ? "Uninstall" : "Install") {
                    Task {
                        isProcessing = true
                        defer { isProcessing = false }
                        do {
                            try await helperManager.toggle()
                            errorMessage = nil
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
                .controlSize(.small)
                .disabled(isProcessing)
            }
        }
        .onAppear {
            helperManager.refreshStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            helperManager.refreshStatus()
        }
    }
}

@MainActor
final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: &$canCheckForUpdates)
    }
}

struct CheckForUpdatesView: View {
    @ObservedObject private var checkForUpdatesViewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        self.checkForUpdatesViewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button("Check for Updates…", action: updater.checkForUpdates)
            .disabled(!checkForUpdatesViewModel.canCheckForUpdates)
    }
}
