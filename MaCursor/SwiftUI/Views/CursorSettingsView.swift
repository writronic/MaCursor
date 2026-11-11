import SwiftUI
import AppKit
import Combine
import Security
import UniformTypeIdentifiers

struct CursorSettingsView: View {
    @EnvironmentObject private var library: LibraryViewModel

    @State private var cursorScaleValue: Double = CursorSettingsView.initialScale()
    @State private var scaleText: String = CursorScaleInput.format(CursorSettingsView.initialScale())
    @FocusState private var scaleFieldFocused: Bool

    @State private var hideTahoeCursors: Bool = MACPreferences.hideTahoeCursors
    @State private var isLeftHanded: Bool = MACPreferences.isLeftHanded
    @State private var cursorShadow: Bool = MACPreferences.flag(MACPreferences.cursorShadowKey)

    @ObservedObject private var helperManager = HelperToolManager.shared
    @State private var autoSwitch: AutoSwitchConfig = AutoSwitchConfig.load()
    @State private var showTimeCollisionNotice = false
    @State private var showDuplicateAppNotice = false

    @State private var focusFollowsMouse: FocusFollowsMouseConfig = FocusFollowsMouseConfig.load()
    @State private var ffmAccessibilityTrusted: Bool = FocusFollowsMouseConfig.accessibilityTrusted

    var body: some View {
        Form {
            Section("Appearance") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Cursor Scale")
                        Spacer()
                        TextField("", text: $scaleText)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .frame(width: 64)
                            .focused($scaleFieldFocused)
                            .onChangeCompat(of: scaleText) { newValue in
                                let sanitized = CursorScaleInput.sanitize(newValue)
                                if sanitized != newValue {
                                    scaleText = sanitized
                                }
                            }
                            .onSubmit {
                                commitScaleText()
                            }
                            .onChangeCompat(of: scaleFieldFocused) { focused in
                                if !focused {
                                    commitScaleText()
                                }
                            }
                            .accessibilityLabel("Cursor Scale")
                        Text(verbatim: "×")
                            .foregroundStyle(.secondary)
                    }

                    Slider(value: sliderBinding, in: CursorScaleInput.range) { editing in
                        if !editing {
                            reapplyForCursorScale()
                        }
                    }
                        .labelsHidden()
                        .onChangeCompat(of: cursorScaleValue) { newValue in
                            MACPreferences.set(NSNumber(value: newValue), forKey: MACPreferences.cursorScaleKey)
                            CursorService.setScale(Float(max(1.0, newValue)))
                            let formatted = CursorScaleInput.format(newValue)
                            if scaleFieldFocused {
                                DispatchQueue.main.async {
                                    scaleText = formatted
                                }
                            } else {
                                scaleText = formatted
                            }
                        }
                        .accessibilityValue(String(format: "%.2f×", cursorScaleValue))
                }
                .onAppear {
                    scaleText = CursorScaleInput.format(cursorScaleValue)
                }

                Toggle("Hide Tahoe cursors", isOn: $hideTahoeCursors)
                    .onChangeCompat(of: hideTahoeCursors) { newValue in
                        MACPreferences.setFlag(newValue, forKey: MACPreferences.hideTahoeCursorsKey)
                        NotificationCenter.default.post(name: .hideTahoeCursorsChanged, object: nil)
                    }

                Text("When enabled, Tahoe-specific cursor variants (ArrowS, IBeamS) are hidden. Removing a cursor will also remove its Tahoe counterpart.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Picker("Mouse Hand", selection: $isLeftHanded) {
                    Text("Left Hand").tag(true)
                    Text("Right Hand").tag(false)
                }
                .pickerStyle(.radioGroup)
                .onChangeCompat(of: isLeftHanded) { newValue in
                    guard newValue != MACPreferences.isLeftHanded else { return }
                    MACPreferences.setFlag(newValue, forKey: MACPreferences.handednessKey)
                    reapplyActiveThemeIfNeeded()
                }

                Toggle("Cursor Shadow", isOn: $cursorShadow)
                    .onChangeCompat(of: cursorShadow) { newValue in
                        CursorSettingsView.setCursorShadow(newValue, library: library)
                    }

                Text("When enabled, a soft drop shadow is drawn under the cursor. The shadow appears while a cursor theme is applied.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Section {
                Group {
                    Toggle("Per-App Themes", isOn: switchByAppBinding)

                    if autoSwitch.switchByApp {
                        ForEach(autoSwitch.appRules) { rule in
                            HStack(spacing: 10) {
                                Image(nsImage: appIcon(for: rule))
                                    .resizable()
                                    .frame(width: 18, height: 18)

                                Text(rule.displayName ?? rule.bundleIdentifier ?? "")
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Spacer(minLength: 6)

                                Picker("", selection: appRuleThemeBinding(for: rule)) {
                                    Text("None")
                                        .tag(nil as String?)

                                    ForEach(library.cursorThemes) { theme in
                                        Text(theme.name)
                                            .tag(theme.id as String?)
                                    }
                                }
                                .labelsHidden()
                                .frame(maxWidth: 170, alignment: .trailing)

                                Button {
                                    autoSwitch.removeAppRule(id: rule.id)
                                    showDuplicateAppNotice = false
                                    autoSwitch.save()
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Remove app rule")
                            }
                        }

                        Button("Add App…") {
                            presentAppPicker()
                        }

                        if showDuplicateAppNotice {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)

                                Text("That app is already in the list.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .disabled(!helperManager.isInstalled)

                if !helperManager.isInstalled {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)

                        Text("Per-App Themes requires the Helper Tool. You can install it from General → Helper Tool.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("Each app can carry its own cursor theme. While that app is in front, MaCursor uses the theme you picked for it.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Section {
                Group {
                    Toggle("Theme Automation", isOn: $autoSwitch.enabled)
                        .onChangeCompat(of: autoSwitch.enabled) { newValue in
                            guard newValue != AutoSwitchConfig.load().enabled else { return }
                            autoSwitch.save()
                        }

                    if autoSwitch.enabled {
                        Toggle("Match system appearance", isOn: matchAppearanceBinding)

                        if autoSwitch.matchSystemAppearance {
                            ForEach(AppearanceRole.allCases) { role in
                                HStack(spacing: 10) {
                                    Label(role.label, systemImage: role.icon)
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    Spacer(minLength: 6)

                                    Picker("", selection: appearanceThemeBinding(for: role)) {
                                        Text("None")
                                            .tag(nil as String?)

                                        ForEach(library.cursorThemes) { theme in
                                            Text(theme.name)
                                                .tag(theme.id as String?)
                                        }
                                    }
                                    .labelsHidden()
                                    .frame(maxWidth: 170, alignment: .trailing)
                                }
                            }
                        } else {
                            Picker("Time Format", selection: $autoSwitch.use24HourTime) {
                                Text("AM/PM").tag(false)
                                Text("24 hours").tag(true)
                            }
                            .pickerStyle(.radioGroup)
                            .onChangeCompat(of: autoSwitch.use24HourTime) { _ in
                                autoSwitch.save()
                            }

                            ForEach(ScheduleRole.allCases) { role in
                                HStack(spacing: 10) {
                                    Label(role.label, systemImage: role.icon)
                                        .frame(width: 150, alignment: .leading)

                                    TimeOfDayField(
                                        minutes: timeBinding(for: role),
                                        use24Hour: autoSwitch.use24HourTime
                                    )

                                    Spacer(minLength: 6)

                                    Picker("", selection: themeBinding(for: role)) {
                                        Text("None")
                                            .tag(nil as String?)

                                        ForEach(library.cursorThemes) { theme in
                                            Text(theme.name)
                                                .tag(theme.id as String?)
                                        }
                                    }
                                    .labelsHidden()
                                    .frame(maxWidth: 170, alignment: .trailing)
                                }
                            }

                            if showTimeCollisionNotice {
                                HStack(spacing: 6) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange)

                                    Text("Day mode and Night mode must start at different times, so the time was moved by one minute.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .disabled(!helperManager.isInstalled)

                if !helperManager.isInstalled {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)

                        Text("Theme Automation requires the Helper Tool. You can install it from General → Helper Tool.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("Switch the cursor theme with the macOS Light and Dark appearance, or set your own day and night times.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            focusFollowsMouseSection
            CursorShakerSection()
        }
        .formStyle(.grouped)
        .navigationTitle("Cursor Control")
        .onAppear {
            helperManager.refreshStatus()
            autoSwitch = AutoSwitchConfig.load()
            focusFollowsMouse = FocusFollowsMouseConfig.load()
            ffmAccessibilityTrusted = FocusFollowsMouseConfig.accessibilityTrusted
            if helperManager.isInstalled {
                FocusFollowsMouseConfig.notifyHelper()
            }
        }
        .onReceive(DistributedNotificationCenter.default().publisher(for: .MACFocusFollowsMouseStatusDidChange)) { _ in
            focusFollowsMouse = FocusFollowsMouseConfig.load()
            ffmAccessibilityTrusted = FocusFollowsMouseConfig.accessibilityTrusted
        }
        .onReceive(NotificationCenter.default.publisher(for: .macFocusFollowsMouseConfigDidChange)) { _ in
            focusFollowsMouse = FocusFollowsMouseConfig.load()
            ffmAccessibilityTrusted = FocusFollowsMouseConfig.accessibilityTrusted
        }
        .onReceive(DistributedNotificationCenter.default().publisher(for: .MACAutoSwitchDidChange)) { _ in
            autoSwitch = AutoSwitchConfig.load()
        }
        .onReceive(DistributedNotificationCenter.default().publisher(for: .MACFocusFollowsMouseDidChange)) { _ in
            focusFollowsMouse = FocusFollowsMouseConfig.load()
            ffmAccessibilityTrusted = FocusFollowsMouseConfig.accessibilityTrusted
        }
        .onReceive(DistributedNotificationCenter.default().publisher(for: .MACCursorPreferencesDidChange)) { _ in
            let storedScale = CursorSettingsView.initialScale()
            if storedScale != cursorScaleValue {
                cursorScaleValue = storedScale
                scaleText = CursorScaleInput.format(storedScale)
            }
            isLeftHanded = MACPreferences.isLeftHanded
            cursorShadow = MACPreferences.flag(MACPreferences.cursorShadowKey)
        }
        .onReceive(NotificationCenter.default.publisher(for: .cursorSettingsDidReset)) { _ in
            cursorScaleValue = CursorSettingsView.initialScale()
            scaleText = CursorScaleInput.format(cursorScaleValue)
            isLeftHanded = MACPreferences.isLeftHanded
            hideTahoeCursors = MACPreferences.hideTahoeCursors
            cursorShadow = MACPreferences.flag(MACPreferences.cursorShadowKey)
            autoSwitch = AutoSwitchConfig.load()
            focusFollowsMouse = FocusFollowsMouseConfig.load()
            ffmAccessibilityTrusted = FocusFollowsMouseConfig.accessibilityTrusted
        }
    }

    private var ffmUsable: Bool {
        ffmAccessibilityTrusted && helperManager.isRunning
    }

    private var ffmOn: Bool { FocusFollowsMouseConfig.isOn(enabled: focusFollowsMouse.enabled, trusted: ffmUsable) }

    private var ffmDelay: Binding<Double> {
        Binding(
            get: { Double(focusFollowsMouse.delayMs) },
            set: { focusFollowsMouse.delayMs = Int($0.rounded()) }
        )
    }

    private func ffmDuration(_ milliseconds: Int) -> String {
        Duration.milliseconds(milliseconds).formatted(.units(allowed: [.milliseconds], width: .abbreviated))
    }

    private var focusFollowsMouseBinding: Binding<Bool> {
        Binding(
            get: {
                FocusFollowsMouseConfig.isOn(enabled: focusFollowsMouse.enabled,
                                             trusted: ffmUsable)
            },
            set: { _ in
                AccessWindowController.tapFocusFollowsMouse(enabled: focusFollowsMouse.enabled, trusted: ffmUsable)
            }
        )
    }

    @ViewBuilder
    private var focusFollowsMouseSection: some View {
        Section {
            Group {
                Toggle("Focus on Hover", isOn: focusFollowsMouseBinding)

                if focusFollowsMouse.enabled && !ffmAccessibilityTrusted {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)

                        Text("Accessibility access is missing. Allow MaCursorHelper in Privacy & Security → Accessibility.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer(minLength: 6)

                        Button("Open System Settings") {
                            FocusFollowsMouseConfig.requestAccessibility()
                        }
                    }
                }

                if ffmOn {
                    VStack(alignment: .leading) {
                        Text("Delay window focus for \(ffmDuration(focusFollowsMouse.delayMs))")
                        Slider(value: ffmDelay, in: 0...1000, step: 50) {
                            Text("Delay window focus for \(ffmDuration(focusFollowsMouse.delayMs))")
                        } onEditingChanged: { if !$0 { focusFollowsMouse.save() } }
                        .labelsHidden()
                    }
                }
            }
            .disabled(!helperManager.isInstalled)

            if !helperManager.isInstalled {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)

                    Text("Focus on Hover requires the Helper Tool. You can install it from General → Helper Tool.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text("When you hover over a window with the cursor, MaCursor raises it to the front and hands it the focus after a short delay.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func timeBinding(for role: ScheduleRole) -> Binding<Int> {
        Binding(
            get: { autoSwitch.rule(for: role).startMinutes },
            set: { newMinutes in
                showTimeCollisionNotice = autoSwitch.setTime(newMinutes, for: role)
                autoSwitch.save()
            }
        )
    }

    private var matchAppearanceBinding: Binding<Bool> {
        Binding(
            get: { autoSwitch.matchSystemAppearance },
            set: { newValue in
                autoSwitch.matchSystemAppearance = newValue
                if newValue {
                    autoSwitch.seedAppearanceThemesIfNeeded()
                }
                autoSwitch.save()
            }
        )
    }

    private func appearanceThemeBinding(for role: AppearanceRole) -> Binding<String?> {
        Binding(
            get: { library.theme(withId: autoSwitch.themeIdentifier(for: role))?.id },
            set: { newValue in
                autoSwitch.setThemeIdentifier(newValue, for: role)
                autoSwitch.save()
            }
        )
    }

    private var switchByAppBinding: Binding<Bool> {
        Binding(
            get: { autoSwitch.switchByApp },
            set: { newValue in
                autoSwitch.switchByApp = newValue
                if !newValue {
                    showDuplicateAppNotice = false
                }
                autoSwitch.save()
            }
        )
    }

    private func appRuleThemeBinding(for rule: AppRule) -> Binding<String?> {
        Binding(
            get: {
                guard let bundleID = rule.bundleIdentifier else { return library.theme(withId: rule.themeIdentifier)?.id }
                return library.theme(withId: autoSwitch.appRule(forBundleIdentifier: bundleID)?.themeIdentifier)?.id
            },
            set: { newValue in
                var updated = rule
                updated.themeIdentifier = newValue
                autoSwitch.setAppRule(updated)
                autoSwitch.save()
            }
        )
    }

    private func appIcon(for rule: AppRule) -> NSImage {
        if let bundleID = rule.bundleIdentifier,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSWorkspace.shared.icon(for: .applicationBundle)
    }

    private func presentAppPicker() {
        guard let url = NSOpenPanel.choose(applications: true) else { return }
        guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else { return }

        if autoSwitch.appRule(forBundleIdentifier: bundleID) != nil {
            showDuplicateAppNotice = true
            return
        }

        showDuplicateAppNotice = false
        let name = FileManager.default.displayName(atPath: url.path)
        autoSwitch.setAppRule(AppRule(themeIdentifier: nil, bundleIdentifier: bundleID, displayName: name))
        autoSwitch.save()
    }

    private func themeBinding(for role: ScheduleRole) -> Binding<String?> {
        Binding(
            get: { library.theme(withId: autoSwitch.rule(for: role).themeIdentifier)?.id },
            set: { newValue in
                var rule = autoSwitch.rule(for: role)
                rule.themeIdentifier = newValue
                autoSwitch.setRule(rule, for: role)
                autoSwitch.save()
            }
        )
    }

    static func setCursorShadow(_ on: Bool, library: LibraryViewModel) {
        guard on != MACPreferences.flag(MACPreferences.cursorShadowKey) else { return }
        MACPreferences.setFlag(on, forKey: MACPreferences.cursorShadowKey)
        if let appliedTheme = library.cursorThemes.first(where: { $0.isApplied }) {
            library.apply(appliedTheme)
        }
    }

    private func reapplyActiveThemeIfNeeded() {
        if let appliedTheme = library.cursorThemes.first(where: { $0.isApplied }) {
            library.apply(appliedTheme)
        }
    }

    private func reapplyForCursorScale() {
        if let appliedTheme = library.cursorThemes.first(where: { $0.isApplied }) {
            library.apply(appliedTheme)
        } else {
            CursorService.restoreAll()
        }
    }

    private var sliderBinding: Binding<Double> {
        Binding(
            get: { cursorScaleValue },
            set: { newValue in
                cursorScaleValue = CursorScaleInput.snapToStep(newValue)
            }
        )
    }

    private static func initialScale() -> Double {
        let stored = (MACPreferences.value(forKey: MACPreferences.cursorScaleKey) as? NSNumber)?.doubleValue ?? 1.0
        return CursorScaleInput.clamp(stored)
    }

    private func commitScaleText() {
        guard let parsed = CursorScaleInput.parse(scaleText) else {
            scaleText = CursorScaleInput.format(cursorScaleValue)
            return
        }
        let clamped = CursorScaleInput.clamp(parsed)
        scaleText = CursorScaleInput.format(clamped)
        guard abs(clamped - cursorScaleValue) > CursorScaleInput.commitEpsilon else { return }
        cursorScaleValue = clamped
        MACPreferences.set(NSNumber(value: clamped), forKey: MACPreferences.cursorScaleKey)
        CursorService.setScale(Float(max(1.0, clamped)))
        reapplyForCursorScale()
    }
}

extension NSOpenPanel {
    static func choose(applications: Bool) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = !applications
        panel.allowsMultipleSelection = false
        if applications {
            panel.allowedContentTypes = [.applicationBundle]
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
        }
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}

extension CursorTrailsPalette {
    var title: String {
        switch self {
        case .match: return String(localized: "Match Cursor Theme")
        case .blaze: return String(localized: "Blaze")
        case .lime: return String(localized: "Lime")
        case .jade: return String(localized: "Jade")
        case .lagoon: return String(localized: "Lagoon")
        case .cobalt: return String(localized: "Cobalt")
        case .orchid: return String(localized: "Orchid")
        case .cherry: return String(localized: "Cherry")
        case .electric: return String(localized: "Electric")
        case .twilight: return String(localized: "Twilight")
        case .prism: return String(localized: "Prism")
        case .graphite: return String(localized: "Graphite")
        }
    }
}

extension CursorTrailsStyle {
    var title: String {
        switch self {
        case .line: return String(localized: "Line")
        case .softDots: return String(localized: "Soft Dots")
        case .cursorCopies: return String(localized: "Echoes")
        }
    }
}

extension CursorTrailsEchoesColors {
    var title: String {
        switch self {
        case .glow: return String(localized: "Use Colors on Glow")
        case .style: return String(localized: "Use Colors with Style")
        }
    }
}

extension CursorTrailsConfig {
    @MainActor
    static func tap(_ trails: inout CursorTrailsConfig) {
        let helperManager = HelperToolManager.shared
        guard let enabled = CursorTrailsConfig.toggledValue(enabled: trails.enabled,
                                                            helperInstalled: helperManager.isInstalled,
                                                            running: helperManager.isRunning) else { return }
        trails.enabled = enabled
        trails.save()
    }
}

struct CursorTrailsSettingsView: View {
    @ObservedObject private var helperManager = HelperToolManager.shared
    @State private var trails = CursorTrailsConfig.load()

    private var cursorTrailsOn: Bool {
        CursorTrailsConfig.isOn(enabled: trails.enabled, running: helperManager.isRunning)
    }

    var body: some View {
        Form {
            Section {
                Group {
                    Toggle("Cursor Trails", isOn: Binding(
                        get: { cursorTrailsOn },
                        set: { _ in CursorTrailsConfig.tap(&trails) }
                    ))
                }
                .disabled(!helperManager.isInstalled)

                if !helperManager.isInstalled {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)

                        Text("Cursor Trails requires the Helper Tool. You can install it from General → Helper Tool.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("A trail follows the cursor as it moves and fades when it stops. The trail stays hidden while Reduce motion is on.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if cursorTrailsOn {
                Section {
                    Picker("Style", selection: Binding(
                        get: { trails.style },
                        set: {
                            trails.style = $0
                            trails.save()
                        }
                    )) {
                        ForEach(CursorTrailsStyle.allCases, id: \.self) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    .pickerStyle(.menu)

                    Slider(value: setting(\.length),
                           in: Double(CursorTrailsConfig.lengths.lowerBound)...Double(CursorTrailsConfig.lengths.upperBound),
                           step: 1) {
                        Text("Length")
                    } minimumValueLabel: {
                        Text("Short")
                    } maximumValueLabel: {
                        Text("Long")
                    }

                    Slider(value: setting(\.width),
                           in: Double(CursorTrailsConfig.widths.lowerBound)...Double(CursorTrailsConfig.widths.upperBound),
                           step: 1) {
                        Text("Width")
                    } minimumValueLabel: {
                        Text("Thin")
                    } maximumValueLabel: {
                        Text("Wide")
                    }

                    Toggle("Glow when still", isOn: Binding(
                        get: { trails.glow },
                        set: {
                            trails.glow = $0
                            trails.save()
                        }
                    ))

                    if trails.drawsCopies {
                        Picker("Colors", selection: Binding(
                            get: { trails.echoesColors },
                            set: {
                                trails.echoesColors = $0
                                trails.save()
                            }
                        )) {
                            ForEach(CursorTrailsEchoesColors.allCases, id: \.self) { choice in
                                Text(choice.title).tag(choice)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        if !trails.drawsCopies {
                            Text("Colors")
                        }
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                            ForEach(CursorTrailsPalette.allCases, id: \.self) { palette in
                                ThemeCard(name: palette.title, isApplied: trails.palette == palette) {
                                    trails.palette = palette
                                    trails.save()
                                } preview: {
                                    swatch(palette)
                                }
                            }
                        }
                    }
                } header: {
                    VStack(alignment: .leading) {
                        HStack(spacing: 10) {
                            GroupBox {
                                Toggle(isOn: Binding(
                                    get: { trails.useGPU && CursorTrailsConfig.hasMetal },
                                    set: {
                                        trails.useGPU = $0
                                        trails.save()
                                    }
                                )) {
                                    Text("Use Graphics Hardware").frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .disabled(!CursorTrailsConfig.hasMetal)
                                .padding(5)
                            }

                            GroupBox {
                                Toggle(isOn: Binding(
                                    get: { trails.fade },
                                    set: {
                                        trails.fade = $0
                                        trails.save()
                                    }
                                )) {
                                    Text("Fade").frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(5)
                            }
                        }
                        .toggleStyle(.switch)
                        .font(.body)
                        .padding(.horizontal, -10)

                        if !CursorTrailsConfig.hasMetal {
                            Text("This Mac has no Metal graphics, so the processor draws the trail.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(!helperManager.isInstalled)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Cursor Trails")
        .onAppear {
            helperManager.refreshStatus()
        }
        .onReceive(DistributedNotificationCenter.default().publisher(for: .MACCursorTrailsDidChange)) { _ in
            trails = CursorTrailsConfig.load()
        }
    }

    private func setting(_ key: WritableKeyPath<CursorTrailsConfig, Int>) -> Binding<Double> {
        Binding(
            get: { Double(trails[keyPath: key]) },
            set: { newValue in
                let value = Int(newValue.rounded())
                guard value != trails[keyPath: key] else { return }
                trails[keyPath: key] = value
                trails.save()
            }
        )
    }

    @ViewBuilder
    private func swatch(_ palette: CursorTrailsPalette) -> some View {
        if palette.colors.isEmpty {
            Image(systemName: "cursorarrow")
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 32)
        } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(LinearGradient(colors: palette.colors.map { Color(cgColor: $0) }, startPoint: .leading, endPoint: .trailing))
                .frame(height: 32)
        }
    }
}

enum CursorScreenshotTab: CaseIterable {
    case general
    case shortcuts
    case quickAccess
    case screenshots
    case advanced

    @MainActor static var selected = CursorScreenshotTab.general

    var title: String {
        switch self {
        case .general: return String(localized: "General")
        case .shortcuts: return String(localized: "Shortcuts")
        case .quickAccess: return String(localized: "Quick Access")
        case .screenshots: return String(localized: "Screenshots")
        case .advanced: return String(localized: "Advanced")
        }
    }
}

struct CursorScreenshotSettingsView: View {
    @ObservedObject private var helperManager = HelperToolManager.shared
    @State private var screenshot = CursorScreenshotConfig.load()
    @State private var screenRecording = CursorTranslatorConfig.screenRecordingAllowed
    @State private var trusted = FocusFollowsMouseConfig.accessibilityTrusted
    @State private var tab = CursorScreenshotTab.selected
    @State private var customizingName = false

    private var usable: Bool { screenRecording && helperManager.isRunning }

    private var screenshotOn: Bool { CursorScreenshotConfig.isOn(enabled: screenshot.enabled, usable: usable) }

    var body: some View {
        GeometryReader { pane in
            let column = RightClickMenuLayout.tableWidth(contentWidth: pane.size.width - 2 * RightClickMenuLayout.pageMargin)
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: RightClickMenuLayout.blockSpacing) {
                    switchCard

                    if screenshotOn {
                        TabBar(
                            titles: CursorScreenshotTab.allCases.map(\.title),
                            label: String(localized: "Cursor Capture"),
                            selection: Binding(
                                get: { CursorScreenshotTab.allCases.firstIndex(of: tab) ?? 0 },
                                set: { tab = CursorScreenshotTab.allCases[$0]; CursorScreenshotTab.selected = tab }
                            )
                        )
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(width: column)
                .padding(.leading, (pane.size.width - column) / 2)
                .padding(.top, RightClickMenuLayout.pageMargin)
                .frame(maxWidth: .infinity, alignment: .leading)

                if screenshotOn {
                    Form {
                        switch tab {
                        case .general: generalPart
                        case .shortcuts: shortcutsPart
                        case .quickAccess: quickAccessPart
                        case .screenshots: screenshotsPart
                        case .advanced: advancedPart
                        }
                    }
                    .formStyle(.grouped)
                }
            }
        }
        .navigationTitle("Cursor Capture")
        .onAppear(perform: recheck)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in recheck() }
        .onReceive(DistributedNotificationCenter.default().publisher(for: .MACCursorScreenshotDidChange)) { _ in refresh() }
        .onReceive(DistributedNotificationCenter.default().publisher(for: .MACCursorTranslatorStatusDidChange)) { _ in refresh() }
        .onReceive(DistributedNotificationCenter.default().publisher(for: .MACFocusFollowsMouseStatusDidChange)) { _ in refresh() }
    }

    @ViewBuilder private var switchCard: some View {
        Group {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Cursor Capture")
                    Text("Take a picture of your screen, with your cursor in it if you want.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Toggle("Cursor Capture", isOn: Binding(
                    get: { screenshotOn },
                    set: { _ in AccessWindowController.tapCursorScreenshot(enabled: screenshot.enabled, usable: usable) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
            }
            .padding(RightClickMenuLayout.inset)
            .frame(minHeight: RightClickMenuLayout.twoLineRowHeight)
            .rightClickMenuCard()

            if screenshot.enabled && !screenRecording {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)

                    Group {
                        if SystemSettingsPane.screenRecordingHasAudio() {
                            Text("Screen Recording access is missing. Allow MaCursor in Privacy & Security → Screen & System Audio Recording.")
                        } else {
                            Text("Screen Recording access is missing. Allow MaCursor in Privacy & Security → Screen Recording.")
                        }
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 6)

                    Button("Open System Settings") {
                        CursorTranslatorConfig.requestScreenRecording()
                    }
                }
                .padding(.horizontal, RightClickMenuLayout.inset)
            }
        }
        .disabled(!helperManager.isInstalled)

        if !helperManager.isInstalled {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)

                Text("Cursor Capture requires the Helper Tool. You can install it from General → Helper Tool.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, RightClickMenuLayout.inset)
        }
    }

    @ViewBuilder private var generalPart: some View {
        Section("Sounds") {
            Toggle("Play sounds", isOn: saving(\.playsSound))
        }
        .disabled(!helperManager.isInstalled)

        Section("Export") {
            LabeledContent("Export location") {
                HStack {
                    Label {
                        if screenshot.folder.isEmpty {
                            Text("Desktop")
                        } else {
                            Text(verbatim: FileManager.default.displayName(atPath: screenshot.folder))
                        }
                    } icon: {
                        Image(systemName: "folder")
                    }

                    Button("Choose…", action: chooseFolder)
                }
            }

            Text("Set the default save location used when saving from the Quick Access Overlay, After Capture, and other Save actions across the app.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .disabled(!helperManager.isInstalled)

        Section("After Capture") {
            Text("Decide what should happen after taking a screenshot.")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                GridRow {
                    Text("Action")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Screenshot")
                        .gridColumnAlignment(.center)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                afterCaptureRow("Show Quick Access Overlay", \.showsPreview)
                afterCaptureRow("Copy file to clipboard", \.copies)
                afterCaptureRow("Save", \.saves)
                afterCaptureRow("Open Annotate tool", \.annotates)
                afterCaptureRow("Pin to the screen", \.pins)
            }
        }
        .disabled(!helperManager.isInstalled)

        Section("Capture") {
            Toggle("Hide desktop icons while capturing", isOn: saving(\.hidesDesktopIcons))
        }
        .disabled(!helperManager.isInstalled)
    }

    private func afterCaptureRow(_ action: LocalizedStringKey, _ field: WritableKeyPath<CursorScreenshotConfig, Bool>) -> some View {
        GridRow {
            Text(action)
                .frame(maxWidth: .infinity, alignment: .leading)
            Toggle(action, isOn: saving(field))
                .labelsHidden()
                .toggleStyle(.checkbox)
        }
    }

    @ViewBuilder private var shortcutsPart: some View {
        Section("Screenshots") {
            if !screenshot.clicks.isEmpty && !trusted {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)

                    Text("Accessibility access is missing. Allow MaCursorHelper in Privacy & Security → Accessibility.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 6)

                    Button("Open System Settings") {
                        FocusFollowsMouseConfig.requestAccessibility()
                    }
                }
            }

            LabeledContent("Capture Area") { shortcut(\.areaShortcut, \.areaClick) }

            LabeledContent("Capture Previous Area") { shortcut(\.repeatShortcut, \.repeatClick) }

            LabeledContent("Capture Fullscreen") { shortcut(\.wholeScreenShortcut, \.wholeScreenClick) }

            LabeledContent("Self-Timer") { shortcut(\.selfTimerShortcut, \.selfTimerClick) }
        }
        .disabled(!helperManager.isInstalled)

        Section("OCR") {
            LabeledContent("Capture Text") { shortcut(\.textShortcut, \.textClick) }

            Text("Drag a box, and the text in it goes to your clipboard. No picture is saved.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .disabled(!helperManager.isInstalled)
    }

    @ViewBuilder private var quickAccessPart: some View {
        Section("Appearance") {
            Picker("Position on screen", selection: saving(\.previewCorner)) {
                Text("Left").tag(CursorScreenshotCorner.bottomLeft)
                Text("Right").tag(CursorScreenshotCorner.bottomRight)
            }

            Toggle("Move to active screen", isOn: saving(\.movesToActiveScreen))

            Text("Active screen is the screen where your cursor is pointing.")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Slider(value: saving(\.previewScale), in: 0.75...1.5, step: 0.25) {
                Text("Overlay size")
            }
            .accessibilityValue(Text(screenshot.previewScale, format: .percent))
        }
        .disabled(!helperManager.isInstalled)

        Section("Behavior") {
            Toggle("Auto-close", isOn: saving(\.closesAfter))

            Picker("Action", selection: saving(\.closeAction)) {
                Text("Save and Close").tag(CursorScreenshotCloseAction.saveAndClose)
                Text("Close").tag(CursorScreenshotCloseAction.close)
            }
            .disabled(!screenshot.closesAfter)

            Picker("Interval", selection: saving(\.previewSeconds)) {
                Text("5 seconds").tag(5)
                Text("10 seconds").tag(10)
                Text("15 seconds").tag(15)
                Text("30 seconds").tag(30)
                Text("1 minute").tag(60)
                Text("2 minutes").tag(120)
                Text("5 minutes").tag(300)
                Text("10 minutes").tag(600)
            }
            .disabled(!screenshot.closesAfter)
        }
        .disabled(!helperManager.isInstalled)

        Section {
            Toggle("Close after dragging", isOn: saving(\.closesAfterDrag))

            Group {
                if screenshot.closesAfterDrag {
                    Text("Hold ⌥ (option) to keep the item on Overlay after dragging.")
                } else {
                    Text("Hold ⌥ (option) to close the item from Overlay after dragging.")
                }
            }
            .font(.caption)
            .foregroundStyle(.tertiary)

            Picker("Save button behavior", selection: saving(\.saveButton)) {
                Text("Save to \"Export location\"").tag(CursorScreenshotSaveButton.exportLocation)
                Text("Ask for destination").tag(CursorScreenshotSaveButton.askForDestination)
            }

            Group {
                if screenshot.saveButton == .exportLocation {
                    Text("Press with ⌥ (option) to choose the destination.")
                } else {
                    Text("Press with ⌥ (option) to use 'Export Location' without asking.")
                }
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .disabled(!helperManager.isInstalled)
    }

    @ViewBuilder private var screenshotsPart: some View {
        Section("Output") {
            Picker("File format", selection: saving(\.output.format)) {
                ForEach(CursorScreenshotFormat.outputChoices, id: \.self) { format in
                    Text(verbatim: format.label).tag(format)
                }
            }

            Toggle("Convert to sRGB profile", isOn: saving(\.output.convertsToSRGB))

            Toggle("Scale Retina screenshots to 1x", isOn: saving(\.output.scalesTo1x))

            Toggle("Add 1px border to all screenshots", isOn: saving(\.output.addsBorder))

            Picker("Background preset", selection: saving(\.background.defaultPreset)) {
                Text("None").tag(String?.none)
                ForEach(screenshot.background.presets, id: \.id) { preset in
                    Group {
                        switch preset.id {
                        case "clean": Text("Clean")
                        case "soft": Text("Soft")
                        case "wide": Text("Wide")
                        default: Text(verbatim: preset.name)
                        }
                    }
                    .tag(Optional(preset.id))
                }
            }

            Text("Apply Background Tool preset to all screenshots. You can create presets in the editor. Hold ⇧ Shift while capturing a screenshot to disable this option.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .disabled(!helperManager.isInstalled)

        Section("Capture") {
            Picker("Self-Timer interval", selection: saving(\.delay)) {
                Text("2 Seconds").tag(2)
                Text("5 Seconds").tag(5)
                Text("10 Seconds").tag(10)
                Text("15 Seconds").tag(15)
            }

            Toggle("Show cursor on screenshots", isOn: saving(\.showsCursor))

            Text("This works in Fullscreen or Self-Timer modes only.")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Toggle("Freeze screen when taking a screenshot", isOn: saving(\.freezesScreen))
        }
        .disabled(!helperManager.isInstalled)

        Section("Window Screenshots") {
            LabeledContent("Background") {
                HStack(spacing: 12) {
                    CursorScreenshotWindowBackgroundChoice(title: "With wallpaper", value: .wallpaper, choice: saving(\.windowShot.background))
                    CursorScreenshotWindowBackgroundChoice(title: "Transparent", value: .transparent, choice: saving(\.windowShot.background))
                }
            }

            Text("Hold ⇧ Shift while taking a screenshot to capture the window with wallpaper.")
                .font(.caption)
                .foregroundStyle(.tertiary)

            if ScreenCaptureSupport.controlsWindowShadow() {
                Toggle("Capture window shadow", isOn: saving(\.windowShot.shadow))
            }

            Text("After the Capture Area shortcut, press Space to pick a window. Press Space again to draw an area.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .disabled(!helperManager.isInstalled)

        Section("Crosshair") {
            Picker("Crosshair Mode", selection: saving(\.crosshair.mode)) {
                Text("Always enabled").tag(CursorScreenshotCrosshairMode.always)
                Text("When ⌘ Command is pressed").tag(CursorScreenshotCrosshairMode.command)
                Text("Disabled").tag(CursorScreenshotCrosshairMode.disabled)
            }

            Toggle("Show magnifier", isOn: saving(\.crosshair.showsMagnifier))
                .disabled(screenshot.crosshair.mode == .disabled)

            if screenshot.crosshair.mode == .disabled {
                Text("To enable magnifier, you must enable Crosshair Mode first.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .disabled(!helperManager.isInstalled)
    }

    @ViewBuilder private var advancedPart: some View {
        Section("File Name") {
            Toggle("Ask for name after every capture", isOn: saving(\.naming.asksForName))

            LabeledContent("File name format") {
                Button("Customize…") { customizingName = true }
            }

            Toggle("Add “@2x” suffix to Retina screenshots", isOn: saving(\.naming.addsRetinaSuffix))

            Text("This option improves compatibility with displaying Retina screenshots in third-party apps.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .disabled(!helperManager.isInstalled)
        .sheet(isPresented: $customizingName, onDismiss: refresh) {
            CursorScreenshotNameSheet(opened: CursorScreenshotConfig.load().naming)
        }

        Section("Clipboard") {
            Picker("Copy to clipboard", selection: saving(\.clipboard)) {
                Text("File & Image (default)").tag(CursorScreenshotClipboardMode.fileAndImage)
                Text("Image only").tag(CursorScreenshotClipboardMode.imageOnly)
                Text("File only").tag(CursorScreenshotClipboardMode.fileOnly)
            }

            Text("Adjust this option if you've encountered any issues with pasting from clipboard or clipboard managers.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .disabled(!helperManager.isInstalled)

        Section("Capture History") {
            Picker("Keep history", selection: saving(\.keepHistory)) {
                Text("Disabled").tag(CursorScreenshotHistoryKeep.disabled)
                Text("1 day").tag(CursorScreenshotHistoryKeep.day)
                Text("3 days").tag(CursorScreenshotHistoryKeep.threeDays)
                Text("1 week").tag(CursorScreenshotHistoryKeep.week)
                Text("1 month").tag(CursorScreenshotHistoryKeep.month)
            }

            Text("You can restore old files with “Capture History” option from the menu bar.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .disabled(!helperManager.isInstalled)

        Section("Text Recognition") {
            Picker("Language", selection: saving(\.textRecognition.language)) {
                Text("Automatically Detect Language").tag(String?.none)
                Divider()
                ForEach(recognitionLanguages, id: \.self) { code in
                    Text(verbatim: recognitionName(code)).tag(Optional(code))
                }
            }

            Toggle("Keep line breaks", isOn: saving(\.textRecognition.keepsLineBreaks))

            Toggle("Keep styling", isOn: saving(\.textRecognition.keepsStyling))

            Toggle("Detect links", isOn: saving(\.textRecognition.detectsLinks))
        }
        .disabled(!helperManager.isInstalled)

        Section("Area Selection") {
            Toggle("Remember last selection", isOn: saving(\.remembersSelection))
        }
        .disabled(!helperManager.isInstalled)
    }

    private var recognitionLanguages: [String] {
        CursorScreenshot.recognitionLanguages.sorted { recognitionName($0).localizedStandardCompare(recognitionName($1)) == .orderedAscending }
    }

    private func recognitionName(_ code: String) -> String {
        switch code {
        case "ars": return String(localized: "Arabic (Najdi)")
        case "zh-Hans": return String(localized: "Chinese (Simplified)")
        case "zh-Hant": return String(localized: "Chinese (Traditional)")
        case "nb": return String(localized: "Norwegian (Bokmål)")
        case "nn": return String(localized: "Norwegian (Nynorsk)")
        default: return CursorTranslatorConfig.name(code)
        }
    }

    private func saving<Value>(_ field: WritableKeyPath<CursorScreenshotConfig, Value>) -> Binding<Value> {
        Binding(
            get: { screenshot[keyPath: field] },
            set: {
                screenshot = CursorScreenshotConfig.load()
                screenshot[keyPath: field] = $0
                screenshot.save()
            }
        )
    }

    private func shortcut(_ key: WritableKeyPath<CursorScreenshotConfig, KeyboardShortcutData?>, _ click: WritableKeyPath<CursorScreenshotConfig, CursorGestureTrigger>) -> some View {
        VStack(alignment: .trailing, spacing: 8) {
            recorder(key)

            TranslatorTriggerEditor(trigger: Binding(
                get: { screenshot[keyPath: click] },
                set: { chosen in
                    guard !CursorScreenshot.refuses(chosen, held: screenshot.clicks(besides: click)) else { return NSSound.beep() }
                    saving(click).wrappedValue = chosen
                }
            ), clicks: true)

            if screenshot[keyPath: click].button != nil && !CursorTranslator.usable(screenshot[keyPath: click]) {
                Text("Hold a key with the left or right button, so normal clicks still work.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func recorder(_ field: WritableKeyPath<CursorScreenshotConfig, KeyboardShortcutData?>) -> some View {
        KeyRecorderView(shortcut: saving(field), isTaken: { heldElsewhere($0, besides: field) },
                        isShadowed: screenshot[keyPath: field].map { heldElsewhere($0, besides: field) } ?? false)
    }

    private func heldElsewhere(_ candidate: KeyboardShortcutData, besides field: WritableKeyPath<CursorScreenshotConfig, KeyboardShortcutData?>) -> Bool {
        let data = MACPreferences.value(forKey: MACPreferences.favoriteCursorsKey) as? Data
        let slots = data.flatMap { try? JSONDecoder().decode([FavoriteCursorSlot].self, from: $0) } ?? []
        let held = slots.filter { $0.themeIdentifier != nil }.compactMap(\.shortcut) + [CursorShakerConfig.load().shortcut].compactMap { $0 } + screenshot.keys(besides: field)
        return CursorScreenshot.refuses(candidate, held: held)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = screenshot.folderURL
        guard panel.runModal() == .OK, let url = panel.url else { return }
        screenshot = CursorScreenshotConfig.load()
        screenshot.folder = url.path
        screenshot.save()
    }

    private func recheck() {
        helperManager.refreshStatus()
        refresh()
        if helperManager.isInstalled {
            CursorScreenshotConfig.notifyHelper()
        }
    }

    private func refresh() {
        screenshot = CursorScreenshotConfig.load()
        screenRecording = CursorTranslatorConfig.screenRecordingAllowed
        trusted = FocusFollowsMouseConfig.accessibilityTrusted
    }
}

struct CursorTranslatorSettingsView: View {
    @ObservedObject private var helperManager = HelperToolManager.shared
    @State private var translator = CursorTranslatorConfig.load()
    @State private var trusted = FocusFollowsMouseConfig.accessibilityTrusted
    @State private var screenRecording = CursorTranslatorConfig.screenRecordingAllowed
    @State private var gestures = CursorGesturesConfig.load()
    @State private var capture = CursorScreenshotConfig.load()
    @State private var key = ""
    @State private var server = ""
    @State private var models: [String] = []
    @State private var modelsNote: CursorTranslatorStatus?
    @State private var typingModel = false
    @FocusState private var addressFocused: Bool

    private static let customTag = ""
    private static let session = URLSession(configuration: URLSessionConfiguration.ephemeral)

    private var usable: Bool { trusted && screenRecording && helperManager.isRunning }

    private var translatorOn: Bool { CursorTranslatorConfig.isOn(enabled: translator.enabled, usable: usable) }

    private var serviceName: String { translator.service.title { String(localized: String.LocalizationValue($0)) } }

    private var keyBinding: Binding<String> {
        Binding(
            get: { key },
            set: {
                key = $0
                CursorTranslatorKeychain.set($0, for: translator.service)
            }
        )
    }

    private var modelBinding: Binding<String> {
        Binding(
            get: { translator.models[translator.service.rawValue] ?? translator.service.defaultModel },
            set: {
                typingModel = true
                translator.models[translator.service.rawValue] = $0
                translator.save()
            }
        )
    }

    private var modelChoices: [String] {
        models.isEmpty ? [translator.model(for: translator.service)] : models
    }

    private var modelChoice: Binding<String> {
        Binding(
            get: {
                let current = translator.model(for: translator.service)
                return typingModel || !modelChoices.contains(current) ? Self.customTag : current
            },
            set: {
                typingModel = $0 == Self.customTag
                guard !typingModel else { return }
                translator.models[translator.service.rawValue] = $0
                translator.save()
            }
        )
    }

    private var addressBinding: Binding<String> {
        Binding(
            get: { translator.addresses[translator.service.rawValue] ?? "" },
            set: {
                translator.addresses[translator.service.rawValue] = $0
                translator.save()
            }
        )
    }

    var body: some View {
        Form {
            Section {
                Group {
                    Toggle("Cursor Translator", isOn: Binding(
                        get: { translatorOn },
                        set: { _ in AccessWindowController.tapCursorTranslator(enabled: translator.enabled, usable: usable) }
                    ))

                    if translator.enabled && !trusted {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)

                            Text("Accessibility access is missing. Allow MaCursorHelper in Privacy & Security → Accessibility.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Spacer(minLength: 6)

                            Button("Open System Settings") {
                                FocusFollowsMouseConfig.requestAccessibility()
                            }
                        }
                    }

                    if translator.enabled && !screenRecording {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)

                            Group {
                                if SystemSettingsPane.screenRecordingHasAudio() {
                                    Text("Screen Recording access is missing. Allow MaCursor in Privacy & Security → Screen & System Audio Recording.")
                                } else {
                                    Text("Screen Recording access is missing. Allow MaCursor in Privacy & Security → Screen Recording.")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)

                            Spacer(minLength: 6)

                            Button("Open System Settings") {
                                CursorTranslatorConfig.requestScreenRecording()
                            }
                        }
                    }
                }
                .disabled(!helperManager.isInstalled)

                if !helperManager.isInstalled {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)

                        Text("Cursor Translator requires the Helper Tool. You can install it from General → Helper Tool.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("Click with the trigger to open a frame. The text inside it turns into your language and keeps up as it changes.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if translatorOn {
                Section {
                    LabeledContent("Trigger") {
                        TranslatorTriggerEditor(trigger: Binding(
                            get: { translator.trigger },
                            set: {
                                translator.trigger = $0
                                translator.save()
                            }
                        ))
                    }

                    if !CursorTranslator.usable(translator.trigger) {
                        Text("Hold a key with the right button, so normal right-clicks still work.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else if capture.clicks.contains(where: { $0.trigger.overlaps(translator.trigger) }) {
                        Text("A Cursor Capture shortcut uses the same keys and button. Cursor Capture takes it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if CursorTranslator.clashes(translator.trigger, with: gestures) {
                        Text("A Cursor Gestures trigger uses the same keys and button. Cursor Translator takes it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Picker("Frame", selection: Binding(
                        get: { translator.mode },
                        set: {
                            translator.mode = $0
                            translator.save()
                        }
                    )) {
                        Text("Frame Stays").tag(CursorTranslatorMode.stays)
                        Text("Follows the Pointer").tag(CursorTranslatorMode.follows)
                    }
                    .pickerStyle(.menu)

                    Group {
                        if translator.mode == .stays {
                            Text("Draw a frame with the trigger, or click to drop one. Drag its name tag to move it and its corner to resize it.")
                        } else {
                            Text("Click with the trigger to open a frame that moves with the pointer. It reads when the pointer rests. Click again to close it.")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Picker("Translate from", selection: Binding(
                        get: { translator.source },
                        set: {
                            translator.source = $0
                            translator.save()
                        }
                    )) {
                        Text("Detect Language").tag(String?.none)
                        Divider()
                        ForEach(CursorTranslatorConfig.sortedLanguages(), id: \.self) { language in
                            Text(CursorTranslatorConfig.name(language)).tag(Optional(language))
                        }
                    }
                    .pickerStyle(.menu)

                    Picker("Translate to", selection: Binding(
                        get: { translator.target },
                        set: {
                            translator.target = $0
                            translator.save()
                        }
                    )) {
                        Text("\(CursorTranslatorConfig.name(CursorTranslatorConfig.systemTarget)) (System Default)").tag(String?.none)
                        Divider()
                        ForEach(CursorTranslatorConfig.sortedLanguages(), id: \.self) { language in
                            Text(CursorTranslatorConfig.name(language)).tag(Optional(language))
                        }
                    }
                    .pickerStyle(.menu)

                    Picker("Translation Service", selection: Binding(
                        get: { translator.service },
                        set: {
                            translator.service = $0
                            translator.save()
                            key = CursorTranslatorKeychain.key(for: $0) ?? ""
                            server = translator.address(for: $0)
                            typingModel = false
                        }
                    )) {
                        ForEach(CursorTranslatorService.allCases.filter { $0.usable(appleTranslation: CursorTranslatorConfig.appleTranslation) }, id: \.self) { service in
                            Text(verbatim: service.title { String(localized: String.LocalizationValue($0)) })
                                .tag(service)
                        }
                    }
                    .pickerStyle(.menu)

                    if !CursorTranslatorConfig.appleTranslation {
                        Text("Apple Translation needs macOS 15 or later.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if translator.service == .apple {
                        HStack(spacing: 10) {
                            Text("Download the languages you read in Language & Region → Translation Languages…, so Apple Translation can use them.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Spacer(minLength: 6)

                            Button("Translation Languages…") {
                                CursorTranslatorConfig.open(CursorTranslatorConfig.languageSettings)
                            }
                        }
                    } else {
                        SecureField("API Key", text: keyBinding, prompt: translator.service.custom ? Text("Not needed for a local server") : nil)
                            .task(id: key) {
                                try? await Task.sleep(nanoseconds: 700_000_000)
                                guard !Task.isCancelled else { return }
                                CursorTranslatorConfig.notifyHelper()
                            }
                            .onDisappear { CursorTranslatorConfig.notifyHelper() }

                        if translator.service.custom {
                            TextField("Server Address", text: addressBinding,
                                      prompt: Text(verbatim: translator.service == .openaiCompatible ? "http://localhost:11434/v1" : "https://api.deepseek.com/anthropic"))
                                .focused($addressFocused)
                                .onSubmit { server = translator.address(for: translator.service) }
                        }

                        if !translator.service.defaultModel.isEmpty {
                            Picker("Model", selection: modelChoice) {
                                ForEach(modelChoices, id: \.self) { Text(verbatim: $0).tag($0) }
                                Divider()
                                Text("Custom Model").tag(Self.customTag)
                            }
                            .pickerStyle(.menu)
                            .task(id: [translator.service.rawValue, key, server]) { await fetchModels() }

                            if modelChoice.wrappedValue == Self.customTag {
                                TextField("Custom Model", text: modelBinding, prompt: Text(verbatim: translator.service.defaultModel))
                            }

                            if let modelsNote {
                                Text(verbatim: modelsNote.text { String(localized: String.LocalizationValue($0)) })
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Slider(value: Binding(get: { translator.look.textSize }, set: { translator.look.textSize = $0 }),
                           in: CursorTranslatorConfig.textSizes, step: 0.05) {
                        Text("Text Size")
                    } minimumValueLabel: {
                        Image(systemName: "textformat.size.smaller")
                    } maximumValueLabel: {
                        Image(systemName: "textformat.size.larger")
                    } onEditingChanged: {
                        if !$0 { translator.save() }
                    }

                    Picker("Line Spacing", selection: Binding(
                        get: { translator.look.lineSpacing },
                        set: {
                            translator.look.lineSpacing = $0
                            translator.save()
                        }
                    )) {
                        ForEach(CursorTranslatorConfig.lineSpacings, id: \.self) { spacing in
                            Text(spacing, format: .number.precision(.fractionLength(1...2))).tag(spacing)
                        }
                    }
                    .pickerStyle(.menu)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Frame Colors")
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                            ForEach(CursorTranslatorConfig.colors, id: \.self) { palette in
                                ThemeCard(name: palette.title, isApplied: translator.color == palette) {
                                    translator.color = palette
                                    translator.save()
                                } preview: {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(Color(cgColor: CursorTrailsPalette.color(at: 0, stops: [palette.frameColor], alpha: 1)))
                                        .frame(height: 32)
                                }
                            }
                        }
                    }
                }
                .disabled(!helperManager.isInstalled)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Cursor Translator")
        .onAppear {
            helperManager.refreshStatus()
            refresh()
            server = translator.address(for: translator.service)
            if helperManager.isInstalled {
                CursorTranslatorConfig.notifyHelper()
            }
        }
        .onChangeCompat(of: addressFocused) { focused in
            if !focused { server = translator.address(for: translator.service) }
        }
        .onReceive(DistributedNotificationCenter.default().publisher(for: .MACCursorTranslatorDidChange)) { _ in refresh() }
        .onReceive(DistributedNotificationCenter.default().publisher(for: .MACCursorTranslatorStatusDidChange)) { _ in refresh() }
        .onReceive(DistributedNotificationCenter.default().publisher(for: .MACFocusFollowsMouseStatusDidChange)) { _ in refresh() }
        .onReceive(DistributedNotificationCenter.default().publisher(for: .MACCursorGesturesDidChange)) { _ in refresh() }
        .onReceive(DistributedNotificationCenter.default().publisher(for: .MACCursorScreenshotDidChange)) { _ in refresh() }
    }

    private func refresh() {
        translator = CursorTranslatorConfig.load()
        trusted = FocusFollowsMouseConfig.accessibilityTrusted
        screenRecording = CursorTranslatorConfig.screenRecordingAllowed
        gestures = CursorGesturesConfig.load()
        capture = CursorScreenshotConfig.load()
        key = translator.service.online ? CursorTranslatorKeychain.key(for: translator.service) ?? "" : ""
    }

    private func fetchModels() async {
        models = []
        modelsNote = nil
        let service = translator.service
        guard let request = CursorTranslator.modelsRequest(service, key: key, address: server) else { return }
        try? await Task.sleep(nanoseconds: 700_000_000)
        guard !Task.isCancelled else { return }
        do {
            let (data, response) = try await Self.session.data(for: request)
            guard !Task.isCancelled else { return }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200..<300).contains(status) {
                models = CursorTranslator.models(data, from: service) ?? []
            } else if CursorTranslator.failure(status: status, error: nil, service: serviceName, reply: data) == .keyRefused(serviceName) {
                modelsNote = .keyRefused(serviceName)
            }
        } catch {
            guard !Task.isCancelled, CursorTranslator.failure(status: nil, error: error, service: serviceName) == .noConnection else { return }
            modelsNote = .noConnection
        }
    }
}

extension CursorTranslatorKeychain {
    static func set(_ key: String, for service: CursorTranslatorService) {
        let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            SecItemDelete(item(service) as CFDictionary)
            return
        }
        let data = Data(value.utf8)
        if SecItemUpdate(item(service) as CFDictionary, [kSecValueData as String: data] as CFDictionary) != errSecItemNotFound { return }
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Library/LoginItems/\(MACHelperBundleName).app")
        let label = "MaCursor \(service.key)"
        var app: SecTrustedApplication?
        var login: SecTrustedApplication?
        var access: SecAccess?
        guard SecTrustedApplicationCreateFromPath(nil, &app) == errSecSuccess, let app,
              SecTrustedApplicationCreateFromPath(helper.path, &login) == errSecSuccess, let login,
              SecAccessCreate(label as CFString, [app, login] as CFArray, &access) == errSecSuccess, let access else { return }
        var added = item(service)
        added[kSecValueData as String] = data
        added[kSecAttrLabel as String] = label
        added[kSecAttrAccess as String] = access
        SecItemAdd(added as CFDictionary, nil)
    }
}

private struct TimeOfDayField: View {
    @Binding var minutes: Int
    let use24Hour: Bool

    var body: some View {
        HStack(spacing: 3) {
            Picker("", selection: hourBinding) {
                ForEach(hourValues, id: \.self) { hour in
                    Text(hourLabel(hour)).tag(hour)
                }
            }
            .labelsHidden()
            .frame(width: 62)
            .accessibilityLabel("Hour")

            Text(verbatim: ":")
                .foregroundStyle(.secondary)
                .fixedSize()

            Picker("", selection: minuteBinding) {
                ForEach(0..<60, id: \.self) { minute in
                    Text(String(format: "%02d", minute)).tag(minute)
                }
            }
            .labelsHidden()
            .frame(width: 62)
            .accessibilityLabel("Minute")

            if !use24Hour {
                Picker("", selection: afternoonBinding) {
                    Text(TimeOfDay.amSymbol()).tag(false)
                    Text(TimeOfDay.pmSymbol()).tag(true)
                }
                .labelsHidden()
                .frame(width: 70)
                .accessibilityLabel("AM/PM")
            }
        }
    }

    private var hourValues: [Int] {
        use24Hour ? Array(0...23) : Array(1...12)
    }

    private func hourLabel(_ hour: Int) -> String {
        use24Hour ? String(format: "%02d", hour) : String(hour)
    }

    private var hourBinding: Binding<Int> {
        Binding(
            get: {
                use24Hour
                    ? TimeOfDay.hour24(fromMinutes: minutes)
                    : TimeOfDay.hour12(fromMinutes: minutes)
            },
            set: { newHour in
                let currentMinute = TimeOfDay.minute(fromMinutes: minutes)
                minutes = use24Hour
                    ? TimeOfDay.minutes(hour24: newHour, minute: currentMinute)
                    : TimeOfDay.minutes(hour12: newHour,
                                        minute: currentMinute,
                                        afternoon: TimeOfDay.isAfternoon(minutes: minutes))
            }
        )
    }

    private var minuteBinding: Binding<Int> {
        Binding(
            get: { TimeOfDay.minute(fromMinutes: minutes) },
            set: { newMinute in
                minutes = TimeOfDay.minutes(hour24: TimeOfDay.hour24(fromMinutes: minutes),
                                            minute: newMinute)
            }
        )
    }

    private var afternoonBinding: Binding<Bool> {
        Binding(
            get: { TimeOfDay.isAfternoon(minutes: minutes) },
            set: { newValue in
                minutes = TimeOfDay.minutes(hour12: TimeOfDay.hour12(fromMinutes: minutes),
                                            minute: TimeOfDay.minute(fromMinutes: minutes),
                                            afternoon: newValue)
            }
        )
    }
}

extension AccessWindowController {
    static let focusFollowsMouse = AccessWindowController(title: String(localized: "Focus on Hover")) {
        NSHostingController(rootView: FocusFollowsMouseAccessView())
    }
}

extension AccessWindowController {
    static func tapFocusFollowsMouse(enabled: Bool, trusted: Bool) {
        let helperManager = HelperToolManager.shared
        guard helperManager.isRunning else { return }
        switch FocusFollowsMouseConfig.toggleAction(enabled: enabled,
                                                    helperInstalled: helperManager.isInstalled,
                                                    trusted: trusted) {
        case .enable:
            FocusFollowsMouseConfig.setEnabled(true)
        case .requestAccess:
            AccessWindowController.focusFollowsMouse.present()
        case .disable:
            FocusFollowsMouseConfig.setEnabled(false)
        case .ignore:
            break
        }
    }
}

private struct FocusFollowsMouseAccessView: View {
    @State private var trusted: Bool = FocusFollowsMouseConfig.accessibilityTrusted
    @State private var didRequest = false
    private let waitTicker = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        AccessDialog(title: Text("Allow Accessibility Access")) {
            Text("MaCursorHelper needs Accessibility access to bring the window under the mouse pointer to the front. Choose Allow for Accessibility, then turn on MaCursorHelper in Privacy & Security → Accessibility.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if trusted {
                Label("Access granted", systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(Color.green)
            } else if didRequest {
                Text("Waiting for access. This window updates as soon as MaCursorHelper is allowed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if trusted {
                Button("Let’s Go!") {
                    FocusFollowsMouseConfig.setEnabled(true)
                    AccessWindowController.focusFollowsMouse.dismiss()
                }
                .keyboardShortcut(.defaultAction)
            } else {
                HStack(spacing: 12) {
                    Button("Not Now") {
                        FocusFollowsMouseConfig.setEnabled(false)
                        AccessWindowController.focusFollowsMouse.dismiss()
                    }

                    Button("Allow for Accessibility") {
                        didRequest = true
                        FocusFollowsMouseConfig.requestAccessibility()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .onAppear {
            FocusFollowsMouseConfig.notifyHelper()
            trusted = FocusFollowsMouseConfig.accessibilityTrusted
        }
        .onReceive(DistributedNotificationCenter.default().publisher(for: .MACFocusFollowsMouseStatusDidChange)) { _ in
            trusted = FocusFollowsMouseConfig.accessibilityTrusted
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            guard AccessWindowController.focusFollowsMouse.window?.isVisible == true else { return }
            FocusFollowsMouseConfig.notifyHelper()
            trusted = FocusFollowsMouseConfig.accessibilityTrusted
        }
        .onReceive(waitTicker) { _ in
            guard !trusted,
                  AccessWindowController.focusFollowsMouse.window?.isVisible == true else { return }
            FocusFollowsMouseConfig.notifyHelper()
            trusted = FocusFollowsMouseConfig.accessibilityTrusted
        }
        .onReceive(ModalWindowCoordinator.shared.activeModalDidChange) { _ in
            AccessWindowController.focusFollowsMouse.reanchor()
        }
    }
}

private struct CursorShakerSection: View {
    @ObservedObject private var helperManager = HelperToolManager.shared
    @State private var shaker = CursorShakerConfig.load()
    @State private var trusted = FocusFollowsMouseConfig.accessibilityTrusted

    private var usable: Bool { trusted && helperManager.isRunning }

    private var shakerOn: Bool { FocusFollowsMouseConfig.isOn(enabled: shaker.enabled, trusted: usable) }

    var body: some View {
        Section {
            Group {
                Toggle("Cursor Shaker", isOn: Binding(
                    get: { shakerOn },
                    set: { _ in AccessWindowController.tapCursorShaker(enabled: shaker.enabled, usable: usable) }
                ))

                if shaker.enabled && !trusted {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)

                        Text("Accessibility access is missing. Allow MaCursorHelper in Privacy & Security → Accessibility.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer(minLength: 6)

                        Button("Open System Settings") {
                            FocusFollowsMouseConfig.requestAccessibility()
                        }
                    }
                }

                if shakerOn {
                    Picker("Start After", selection: Binding(
                        get: { shaker.period },
                        set: {
                            shaker.period = $0
                            shaker.save()
                        }
                    )) {
                        ForEach(CursorShakerConfig.periods, id: \.self) { seconds in
                            Text(Duration.seconds(seconds).formatted(.units(allowed: [.seconds, .minutes], width: .abbreviated))).tag(seconds)
                        }
                    }
                    .pickerStyle(.menu)

                    Picker("Click", selection: saving(\.click)) {
                        Text("Off").tag(CursorShakerClick.off)
                        Text("Left Click").tag(CursorShakerClick.left)
                        Text("Right Click").tag(CursorShakerClick.right)
                    }
                    .pickerStyle(.menu)

                    Picker("Scroll", selection: saving(\.scroll)) {
                        Text("Off").tag(CursorShakerScroll.off)
                        Text("Down").tag(CursorShakerScroll.down)
                        Text("Down and Up").tag(CursorShakerScroll.downAndUp)
                    }
                    .pickerStyle(.menu)

                    Toggle("Switch Tabs", isOn: saving(\.switchTabs))

                    Toggle("Dim the Screen", isOn: saving(\.dim))

                    Text("Switch Tabs shows the next tab in the front app, at most once a minute. Dim the Screen makes the display darker while you are away and brings it back when you return.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Picker("Stop After", selection: Binding(
                        get: { shaker.stopAfter },
                        set: { CursorShakerConfig.setStopAfter($0); shaker = CursorShakerConfig.load() }
                    )) {
                        Text("Never").tag(nil as Int?)
                        ForEach(CursorShakerConfig.stopTimes, id: \.self) { minutes in
                            Text(CursorShakerConfig.stopLabel(minutes)).tag(minutes as Int?)
                        }
                    }
                    .pickerStyle(.menu)

                    Toggle("Stop on battery at \(0.2, format: .percent) or less", isOn: saving(\.batteryStop))

                    LabeledContent("Shortcut") {
                        KeyRecorderView(shortcut: Binding(
                            get: { shaker.shortcut },
                            set: {
                                shaker.shortcut = $0
                                shaker.save()
                            }
                        ), isTaken: slotHolds, isShadowed: shaker.shortcut.map(slotHolds) ?? false)
                    }
                }
            }
            .disabled(!helperManager.isInstalled)

            if !helperManager.isInstalled {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)

                    Text("Cursor Shaker requires the Helper Tool. You can install it from General → Helper Tool.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text("While you are away, the pointer moves one pixel and back, and the display stays on, so your apps keep showing you as active.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .onAppear {
            helperManager.refreshStatus()
            shaker = CursorShakerConfig.load()
            trusted = FocusFollowsMouseConfig.accessibilityTrusted
        }
        .onReceive(DistributedNotificationCenter.default().publisher(for: .MACCursorShakerDidChange)) { _ in
            shaker = CursorShakerConfig.load()
        }
        .onReceive(DistributedNotificationCenter.default().publisher(for: .MACFocusFollowsMouseStatusDidChange)) { _ in
            trusted = FocusFollowsMouseConfig.accessibilityTrusted
        }
    }

    private func saving<Value>(_ field: WritableKeyPath<CursorShakerConfig, Value>) -> Binding<Value> {
        Binding(
            get: { shaker[keyPath: field] },
            set: {
                shaker[keyPath: field] = $0
                shaker.save()
            }
        )
    }

    private func slotHolds(_ candidate: KeyboardShortcutData) -> Bool {
        let data = MACPreferences.value(forKey: MACPreferences.favoriteCursorsKey) as? Data
        let slots = data.flatMap { try? JSONDecoder().decode([FavoriteCursorSlot].self, from: $0) } ?? []
        return slots.filter { $0.themeIdentifier != nil }.compactMap(\.shortcut).contains {
            MACShortcutsCollide($0.keyCode, $0.modifierFlagsRaw, candidate.keyCode, candidate.modifierFlagsRaw)
        }
    }
}

extension AccessWindowController {
    static let cursorShaker = AccessWindowController(title: String(localized: "Cursor Shaker")) {
        NSHostingController(rootView: CursorShakerAccessView())
    }
}

extension AccessWindowController {
    static func tapCursorShaker(enabled: Bool, usable: Bool) {
        let helperManager = HelperToolManager.shared
        guard helperManager.isRunning else { return }
        switch FocusFollowsMouseConfig.toggleAction(enabled: enabled,
                                                    helperInstalled: helperManager.isInstalled,
                                                    trusted: usable) {
        case .enable: CursorShakerConfig.setEnabled(true)
        case .requestAccess: AccessWindowController.cursorShaker.present()
        case .disable: CursorShakerConfig.setEnabled(false)
        case .ignore: break
        }
    }
}

private struct CursorShakerAccessView: View {
    @State private var trusted = FocusFollowsMouseConfig.accessibilityTrusted
    @State private var didRequest = false
    private let waitTicker = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        AccessDialog(title: Text("Allow Accessibility Access")) {
            Text("MaCursorHelper needs Accessibility access to move the pointer while you are away. Choose Allow for Accessibility, then turn on MaCursorHelper in Privacy & Security → Accessibility.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if trusted {
                Label("Access granted", systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(Color.green)

                Button("Let’s Go!") {
                    CursorShakerConfig.setEnabled(true)
                    AccessWindowController.cursorShaker.dismiss()
                }
                .keyboardShortcut(.defaultAction)
            } else {
                if didRequest {
                    Text("Waiting for access. This window updates as soon as MaCursorHelper is allowed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 12) {
                    Button("Not Now") {
                        CursorShakerConfig.setEnabled(false)
                        AccessWindowController.cursorShaker.dismiss()
                    }

                    Button("Allow for Accessibility") {
                        didRequest = true
                        FocusFollowsMouseConfig.requestAccessibility()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .onAppear(perform: refresh)
        .onReceive(DistributedNotificationCenter.default().publisher(for: .MACFocusFollowsMouseStatusDidChange)) { _ in
            trusted = FocusFollowsMouseConfig.accessibilityTrusted
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            guard AccessWindowController.cursorShaker.window?.isVisible == true else { return }
            refresh()
        }
        .onReceive(waitTicker) { _ in
            guard !trusted, AccessWindowController.cursorShaker.window?.isVisible == true else { return }
            refresh()
        }
        .onReceive(ModalWindowCoordinator.shared.activeModalDidChange) { _ in
            AccessWindowController.cursorShaker.reanchor()
        }
    }

    private func refresh() {
        CursorShakerConfig.notifyHelper()
        trusted = FocusFollowsMouseConfig.accessibilityTrusted
    }
}

private enum CursorTranslatorAccessStep {
    case accessibility, screenRecording

    var title: String {
        switch self {
        case .accessibility: return String(localized: "Accessibility")
        case .screenRecording: return String(localized: "Screen Recording")
        }
    }

    var progress: String {
        switch self {
        case .accessibility: return String(localized: "Step 1 of 2")
        case .screenRecording: return String(localized: "Step 2 of 2")
        }
    }
}

extension AccessWindowController {
    static let cursorTranslator = AccessWindowController(title: String(localized: "Cursor Translator")) {
        NSHostingController(rootView: CursorTranslatorAccessView())
    }
}

extension AccessWindowController {
    static func tapCursorTranslator(enabled: Bool, usable: Bool) {
        let helperManager = HelperToolManager.shared
        guard helperManager.isRunning else { return }
        switch FocusFollowsMouseConfig.toggleAction(enabled: enabled,
                                                    helperInstalled: helperManager.isInstalled,
                                                    trusted: usable) {
        case .enable: CursorTranslatorConfig.setEnabled(true)
        case .requestAccess: AccessWindowController.cursorTranslator.present()
        case .disable: CursorTranslatorConfig.setEnabled(false)
        case .ignore: break
        }
    }
}

private struct CursorTranslatorAccessView: View {
    @State private var trusted = FocusFollowsMouseConfig.accessibilityTrusted
    @State private var screenRecording = CursorTranslatorConfig.screenRecordingAllowed
    @State private var step: CursorTranslatorAccessStep = FocusFollowsMouseConfig.accessibilityTrusted ? .screenRecording : .accessibility
    @State private var didRequest = false
    private let waitTicker = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        let shown = trusted ? step : .accessibility
        AccessDialog(title: Text("Cursor Translator")) {
            VStack(spacing: 4) {
                Text(shown.progress)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(shown.title)
                    .font(.headline)
            }

            switch shown {
            case .accessibility:
                Text("MaCursorHelper needs Accessibility access to see the trigger click and to keep the right-click menu of the app closed. Choose Allow for Accessibility, then turn on MaCursorHelper in Privacy & Security → Accessibility.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !trusted {
                    waiting

                    HStack(spacing: 12) {
                        Button("Not Now") {
                            CursorTranslatorConfig.setEnabled(false)
                            AccessWindowController.cursorTranslator.dismiss()
                        }

                        Button("Allow for Accessibility") {
                            didRequest = true
                            FocusFollowsMouseConfig.requestAccessibility()
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                } else {
                    granted

                    Button("Continue") {
                        didRequest = false
                        step = .screenRecording
                    }
                    .keyboardShortcut(.defaultAction)
                }
            case .screenRecording:
                Group {
                    if SystemSettingsPane.screenRecordingHasAudio() {
                        Text("MaCursor needs Screen Recording access to read the text inside the frame. Nothing is saved, and the text goes only to the Translation Service you choose. Choose Allow Screen Recording, then turn on MaCursor in Privacy & Security → Screen & System Audio Recording.")
                    } else {
                        Text("MaCursor needs Screen Recording access to read the text inside the frame. Nothing is saved, and the text goes only to the Translation Service you choose. Choose Allow Screen Recording, then turn on MaCursor in Privacy & Security → Screen Recording.")
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                if !screenRecording {
                    waiting

                    HStack(spacing: 12) {
                        Button("Not Now") {
                            CursorTranslatorConfig.setEnabled(false)
                            AccessWindowController.cursorTranslator.dismiss()
                        }

                        Button("Allow Screen Recording") {
                            didRequest = true
                            CursorTranslatorConfig.requestScreenRecording()
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                } else {
                    granted

                    Button("Let’s Go!") {
                        CursorTranslatorConfig.setEnabled(true)
                        AccessWindowController.cursorTranslator.dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .onAppear(perform: refresh)
        .onReceive(DistributedNotificationCenter.default().publisher(for: .MACFocusFollowsMouseStatusDidChange)) { _ in read() }
        .onReceive(DistributedNotificationCenter.default().publisher(for: .MACCursorTranslatorStatusDidChange)) { _ in read() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            guard AccessWindowController.cursorTranslator.window?.isVisible == true else { return }
            refresh()
        }
        .onReceive(waitTicker) { _ in
            guard !(trusted && screenRecording), AccessWindowController.cursorTranslator.window?.isVisible == true else { return }
            refresh()
        }
        .onReceive(ModalWindowCoordinator.shared.activeModalDidChange) { _ in
            AccessWindowController.cursorTranslator.reanchor()
        }
    }

    @ViewBuilder
    private var waiting: some View {
        if didRequest {
            Text("Waiting for access. This window updates as soon as MaCursorHelper is allowed.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var granted: some View {
        Label("Access granted", systemImage: "checkmark.circle.fill")
            .font(.callout)
            .foregroundStyle(Color.green)
    }

    private func refresh() {
        CursorTranslatorConfig.notifyHelper()
        read()
    }

    private func read() {
        trusted = FocusFollowsMouseConfig.accessibilityTrusted
        screenRecording = CursorTranslatorConfig.screenRecordingAllowed
    }
}

extension AccessWindowController {
    static let cursorScreenshot = AccessWindowController(title: String(localized: "Cursor Capture")) {
        NSHostingController(rootView: CursorScreenshotAccessView())
    }
}

extension AccessWindowController {
    static func tapCursorScreenshot(enabled: Bool, usable: Bool) {
        let helperManager = HelperToolManager.shared
        guard helperManager.isRunning else { return }
        switch FocusFollowsMouseConfig.toggleAction(enabled: enabled,
                                                    helperInstalled: helperManager.isInstalled,
                                                    trusted: usable) {
        case .enable: CursorScreenshotConfig.setEnabled(true)
        case .requestAccess: AccessWindowController.cursorScreenshot.present()
        case .disable: CursorScreenshotConfig.setEnabled(false)
        case .ignore: break
        }
    }
}

private struct CursorScreenshotAccessView: View {
    @State private var screenRecording = CursorTranslatorConfig.screenRecordingAllowed
    @State private var didRequest = false
    private let waitTicker = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        AccessDialog(title: Text("Cursor Capture")) {
            Text("Screen Recording")
                .font(.headline)

            Group {
                if SystemSettingsPane.screenRecordingHasAudio() {
                    Text("MaCursor needs Screen Recording access to take a picture of your screen. The picture stays on your Mac. Choose Allow Screen Recording, then turn on MaCursor in Privacy & Security → Screen & System Audio Recording.")
                } else {
                    Text("MaCursor needs Screen Recording access to take a picture of your screen. The picture stays on your Mac. Choose Allow Screen Recording, then turn on MaCursor in Privacy & Security → Screen Recording.")
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            if screenRecording {
                Label("Access granted", systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(Color.green)

                Button("Let’s Go!") {
                    CursorScreenshotConfig.setEnabled(true)
                    AccessWindowController.cursorScreenshot.dismiss()
                }
                .keyboardShortcut(.defaultAction)
            } else {
                if didRequest {
                    Text("Waiting for access. This window updates as soon as MaCursor is allowed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 12) {
                    Button("Not Now") {
                        CursorScreenshotConfig.setEnabled(false)
                        AccessWindowController.cursorScreenshot.dismiss()
                    }

                    Button("Allow Screen Recording") {
                        didRequest = true
                        CursorTranslatorConfig.requestScreenRecording()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .onAppear(perform: refresh)
        .onReceive(DistributedNotificationCenter.default().publisher(for: .MACCursorTranslatorStatusDidChange)) { _ in read() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            guard AccessWindowController.cursorScreenshot.window?.isVisible == true else { return }
            refresh()
        }
        .onReceive(waitTicker) { _ in
            guard !screenRecording, AccessWindowController.cursorScreenshot.window?.isVisible == true else { return }
            refresh()
        }
        .onReceive(ModalWindowCoordinator.shared.activeModalDidChange) { _ in
            AccessWindowController.cursorScreenshot.reanchor()
        }
    }

    private func refresh() {
        CursorScreenshotConfig.notifyHelper()
        read()
    }

    private func read() {
        screenRecording = CursorTranslatorConfig.screenRecordingAllowed
    }
}

private struct CursorScreenshotWindowBackgroundChoice: View {
    let title: LocalizedStringKey
    let value: CursorScreenshotWindowBackground
    @Binding var choice: CursorScreenshotWindowBackground

    private var tile: RoundedRectangle { RoundedRectangle(cornerRadius: 6, style: .continuous) }

    @ViewBuilder private var backdrop: some View {
        if value == .wallpaper {
            LinearGradient(colors: [Color(red: 0.36, green: 0.55, blue: 0.95), Color(red: 0.72, green: 0.42, blue: 0.86)], startPoint: .topLeading, endPoint: .bottomTrailing)
        } else {
            Canvas { context, size in
                let side: CGFloat = 6
                for row in 0..<Int((size.height / side).rounded(.up)) {
                    for column in 0..<Int((size.width / side).rounded(.up)) where (row + column).isMultiple(of: 2) {
                        context.fill(Path(CGRect(x: CGFloat(column) * side, y: CGFloat(row) * side, width: side, height: side)), with: .color(.secondary.opacity(0.25)))
                    }
                }
            }
        }
    }

    var body: some View {
        Button {
            choice = value
        } label: {
            VStack(spacing: 6) {
                backdrop
                    .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Color(nsColor: .windowBackgroundColor)).frame(width: 40, height: 26).shadow(radius: 1))
                    .frame(width: 72, height: 46)
                    .clipShape(tile)
                    .overlay(tile.strokeBorder(choice == value ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: choice == value ? 2 : 1))
                Text(title)
                    .font(.caption)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(choice == value ? .isSelected : [])
    }
}
