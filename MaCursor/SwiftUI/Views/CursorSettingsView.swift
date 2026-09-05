import SwiftUI
import AppKit
import Combine
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
                        guard newValue != MACPreferences.flag(MACPreferences.cursorShadowKey) else { return }
                        MACPreferences.setFlag(newValue, forKey: MACPreferences.cursorShadowKey)
                        reapplyActiveThemeIfNeeded()
                    }

                Text("When enabled, a soft drop shadow is drawn under the cursor, similar to the pointer shadow on Windows. The shadow appears while a cursor theme is applied.")
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
                                    .frame(width: 122, alignment: .leading)

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
                                .frame(maxWidth: 170)

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
                                        .frame(width: 150, alignment: .leading)

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
                                    .frame(maxWidth: 170)
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
                                        .frame(width: 118, alignment: .leading)

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
                                    .frame(maxWidth: 170)
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

    private var focusFollowsMouseBinding: Binding<Bool> {
        Binding(
            get: {
                FocusFollowsMouseConfig.isOn(enabled: focusFollowsMouse.enabled,
                                             trusted: ffmUsable)
            },
            set: { _ in
                switch FocusFollowsMouseConfig.toggleAction(enabled: focusFollowsMouse.enabled,
                                                            helperInstalled: helperManager.isInstalled,
                                                            trusted: ffmUsable) {
                case .enable:
                    FocusFollowsMouseConfig.setEnabled(true)
                case .requestAccess:
                    FocusFollowsMouseAccessWindowController.shared.present()
                case .disable:
                    FocusFollowsMouseConfig.setEnabled(false)
                case .ignore:
                    break
                }
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
            get: { autoSwitch.themeIdentifier(for: role) },
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
                guard let bundleID = rule.bundleIdentifier else { return rule.themeIdentifier }
                return autoSwitch.appRule(forBundleIdentifier: bundleID)?.themeIdentifier
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
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url else { return }
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
            get: { autoSwitch.rule(for: role).themeIdentifier },
            set: { newValue in
                var rule = autoSwitch.rule(for: role)
                rule.themeIdentifier = newValue
                autoSwitch.setRule(rule, for: role)
                autoSwitch.save()
            }
        )
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

final class FocusFollowsMouseAccessWindowController: NSWindowController, NSWindowDelegate {
    static let shared = FocusFollowsMouseAccessWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        window.title = String(localized: "Focus on Hover")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false

        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        guard let window else { return }
        if !window.isVisible {
            let content = NSHostingController(rootView: FocusFollowsMouseAccessView())
            window.contentViewController = content
            window.setContentSize(content.view.fittingSize)
        }
        attach(window, to: anchorWindow())
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismiss() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window else { return }
        window.parent?.removeChildWindow(window)
    }

    private func anchorWindow() -> NSWindow? {
        if let settings = SettingsWindowController.shared.window, settings.isVisible { return settings }
        return NSApp.windows.first { $0.isVisible && $0.canBecomeMain && $0 !== window }
    }

    private func attach(_ window: NSWindow, to parent: NSWindow?) {
        guard let parent, parent !== window, parent.isVisible else {
            window.center()
            return
        }
        parent.removeChildWindow(window)
        let visibleFrame = parent.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? parent.frame
        window.setFrameOrigin(ModalWindowPlacement.centeredOrigin(
            size: window.frame.size,
            over: parent.frame,
            constrainedTo: visibleFrame
        ))
        parent.addChildWindow(window, ordered: .above)
    }
}

private struct FocusFollowsMouseAccessView: View {
    @State private var trusted: Bool = FocusFollowsMouseConfig.accessibilityTrusted
    @State private var didRequest = false
    private let waitTicker = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                .resizable()
                .frame(width: 76, height: 76)

            Text("Allow Accessibility Access")
                .font(.title2.weight(.semibold))

            Text("MaCursorHelper needs Accessibility access to bring the window under the mouse pointer to the front. Choose Allow for Accessibility, then turn on MaCursorHelper in Privacy & Security → Accessibility.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if trusted {
                Label("Access granted", systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(Color.green)
            } else if didRequest {
                Text("Waiting for access. This window updates as soon as MaCursorHelper is allowed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if trusted {
                Button("Let’s Go!") {
                    FocusFollowsMouseConfig.setEnabled(true)
                    FocusFollowsMouseAccessWindowController.shared.dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
            } else {
                HStack(spacing: 12) {
                    Button("Not Now") {
                        FocusFollowsMouseConfig.setEnabled(false)
                        FocusFollowsMouseAccessWindowController.shared.dismiss()
                    }
                    .controlSize(.large)

                    Button("Allow for Accessibility") {
                        didRequest = true
                        FocusFollowsMouseConfig.requestAccessibility()
                    }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
                }
            }
        }
        .padding(28)
        .frame(width: 460)
        .onAppear {
            FocusFollowsMouseConfig.notifyHelper()
            trusted = FocusFollowsMouseConfig.accessibilityTrusted
        }
        .onReceive(DistributedNotificationCenter.default().publisher(for: .MACFocusFollowsMouseStatusDidChange)) { _ in
            trusted = FocusFollowsMouseConfig.accessibilityTrusted
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            FocusFollowsMouseConfig.notifyHelper()
            trusted = FocusFollowsMouseConfig.accessibilityTrusted
        }
        .onReceive(waitTicker) { _ in
            guard !trusted,
                  FocusFollowsMouseAccessWindowController.shared.window?.isVisible == true else { return }
            FocusFollowsMouseConfig.notifyHelper()
            trusted = FocusFollowsMouseConfig.accessibilityTrusted
        }
    }
}
