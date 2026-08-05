import SwiftUI

struct CursorSettingsView: View {
    @Environment(LibraryViewModel.self) private var library

    @State private var cursorScaleValue: Double = CursorSettingsView.initialScale()
    @State private var scaleText: String = CursorScaleInput.format(CursorSettingsView.initialScale())
    @FocusState private var scaleFieldFocused: Bool

    @State private var hideTahoeCursors: Bool = MACPreferences.hideTahoeCursors
    @State private var isLeftHanded: Bool = MACPreferences.isLeftHanded
    @State private var cursorShadow: Bool = MACPreferences.flag(MACPreferences.cursorShadowKey)

    @State private var helperManager = HelperToolManager.shared
    @State private var autoSwitch: AutoSwitchConfig = AutoSwitchConfig.load()
    @State private var showTimeCollisionNotice = false

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
                            .onChange(of: scaleText) { _, newValue in
                                let sanitized = CursorScaleInput.sanitize(newValue)
                                if sanitized != newValue {
                                    scaleText = sanitized
                                }
                            }
                            .onSubmit {
                                commitScaleText()
                            }
                            .onChange(of: scaleFieldFocused) { _, focused in
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
                        .onChange(of: cursorScaleValue) { _, newValue in
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
                    .onChange(of: hideTahoeCursors) { _, newValue in
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
                .onChange(of: isLeftHanded) { _, newValue in
                    MACPreferences.setFlag(newValue, forKey: MACPreferences.handednessKey)
                    reapplyActiveThemeIfNeeded()
                }

                Toggle("Cursor Shadow", isOn: $cursorShadow)
                    .onChange(of: cursorShadow) { _, newValue in
                        guard newValue != MACPreferences.flag(MACPreferences.cursorShadowKey) else { return }
                        MACPreferences.setFlag(newValue, forKey: MACPreferences.cursorShadowKey)
                        reapplyActiveThemeIfNeeded()
                    }

                Text("When enabled, a soft drop shadow is drawn under the cursor, similar to the pointer shadow on Windows. The shadow appears while a cursor theme is applied.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Toggle("Custom cursor color", isOn: $autoSwitch.colorAdjustmentEnabled)
                    .onChange(of: autoSwitch.colorAdjustmentEnabled) { _, _ in
                        autoSwitch.save()
                    }

                if autoSwitch.colorAdjustmentEnabled {
                    ColorPicker("Base color", selection: cursorColorBinding, supportsOpacity: false)

                    Toggle("Follow system accent color", isOn: $autoSwitch.followsSystemAccent)
                        .onChange(of: autoSwitch.followsSystemAccent) { _, _ in
                            autoSwitch.save()
                        }

                    if autoSwitch.followsSystemAccent {
                        HStack {
                            Text("Accent adaptivity")

                            Slider(value: $autoSwitch.accentAdaptivity, in: 0...1) { editing in
                                if !editing {
                                    autoSwitch.save()
                                }
                            }

                            Text(autoSwitch.accentAdaptivity, format: .percent.precision(.fractionLength(0)))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 42, alignment: .trailing)
                        }
                    }

                    Text("The cursor fill follows your chosen color and, optionally, the macOS accent color. White outlines and shadows stay unchanged.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Section("Automatic Switching") {
                if !helperManager.isInstalled {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)

                        Text("Automatic switching requires the Helper Tool. You can install it from General → Helper Tool.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle("Switch cursor automatically", isOn: $autoSwitch.enabled)
                    .onChange(of: autoSwitch.enabled) { _, _ in
                        autoSwitch.save()
                    }

                if autoSwitch.enabled {
                    Toggle("Follow system appearance", isOn: $autoSwitch.followsSystemAppearance)
                        .onChange(of: autoSwitch.followsSystemAppearance) { _, _ in
                            showTimeCollisionNotice = false
                            autoSwitch.save()
                        }

                    if !autoSwitch.followsSystemAppearance {
                        Picker("Time Format", selection: $autoSwitch.use24HourTime) {
                            Text("AM/PM").tag(false)
                            Text("24 hours").tag(true)
                        }
                        .pickerStyle(.radioGroup)
                        .onChange(of: autoSwitch.use24HourTime) { _, _ in
                            autoSwitch.save()
                        }
                    }

                    ForEach(ScheduleRole.allCases) { role in
                        HStack(spacing: 10) {
                            Label(
                                autoSwitch.followsSystemAppearance ? role.appearanceLabel : role.label,
                                systemImage: role.icon
                            )
                            .frame(width: 118, alignment: .leading)

                            if !autoSwitch.followsSystemAppearance {
                                TimeOfDayField(
                                    minutes: timeBinding(for: role),
                                    use24Hour: autoSwitch.use24HourTime
                                )
                            }

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

                    if showTimeCollisionNotice && !autoSwitch.followsSystemAppearance {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)

                            Text("Day mode and Night mode must start at different times, so the time was moved by one minute.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if autoSwitch.followsSystemAppearance {
                    Text("Pick a cursor theme for Light and Dark mode. MaCursor follows the macOS appearance automatically.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    Text("Pick a time and a cursor theme for each mode. MaCursor switches at those times and keeps that theme until the next one.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Cursor Control")
        .onAppear {
            helperManager.refreshStatus()
            autoSwitch = AutoSwitchConfig.load()
        }
        .onReceive(NotificationCenter.default.publisher(for: .cursorSettingsDidReset)) { _ in
            cursorScaleValue = CursorSettingsView.initialScale()
            scaleText = CursorScaleInput.format(cursorScaleValue)
            isLeftHanded = MACPreferences.isLeftHanded
            hideTahoeCursors = MACPreferences.hideTahoeCursors
            cursorShadow = MACPreferences.flag(MACPreferences.cursorShadowKey)
            autoSwitch = AutoSwitchConfig.load()
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

    private var cursorColorBinding: Binding<Color> {
        Binding(
            get: { Color(nsColor: CursorColorHex.color(from: autoSwitch.baseColorHex)) },
            set: { newValue in
                guard let hex = CursorColorHex.hex(from: NSColor(newValue)) else { return }
                autoSwitch.baseColorHex = hex
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
