import SwiftUI

private enum PanelMetrics {
    static let width: CGFloat = 320
    static let padding: CGFloat = 12
    static let sectionSpacing: CGFloat = 12
    static let cardRadius: CGFloat = 10
    static let gridColumns = 3
    static let gridSpacing: CGFloat = 8
    static let gridMaxHeight: CGFloat = 220
    static let gridInlineLimit = 6
    static let thumbnail: CGFloat = 32
}

struct MenuBarPanelView: View {
    @ObservedObject var model: MenuBarPanelModel
    @AppStorage("MACMenuBarCursorTrailsExpanded") private var trailsExpanded = true
    @AppStorage("MACMenuBarFocusOnHoverExpanded") private var ffmDelayExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: PanelMetrics.sectionSpacing) {
            header
            themesSection
            activeAppSection
            quickControlsSection
            cursorTrailsSection
        }
        .padding(PanelMetrics.padding)
        .frame(width: PanelMetrics.width)
        .background(Color(nsColor: .windowBackgroundColor).opacity(model.panelBackdropAlpha))
    }

    private var header: some View {
        HStack(spacing: 8) {
            if let brand = model.brandImage {
                Image(nsImage: brand)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .foregroundStyle(.primary)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: "MaCursor")
                    .font(.system(size: 13, weight: .semibold))
                Text(currentCursorCaption)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                if let overrideCaption {
                    Text(overrideCaption)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if let image = model.thumbnail(forTheme: model.visibleIdentifier) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)
            } else if model.visibleIdentifier == nil {
                Image(systemName: "cursorarrow")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)
            }
            if #available(macOS 14, *) {
                restoreButton.buttonStyle(.accessoryBar)
            } else {
                restoreButton.buttonStyle(.borderless)
            }
        }
    }

    private var restoreButton: some View {
        Button {
            model.restoreSystemCursors()
        } label: {
            Label(MenuBarL("Restore"), systemImage: "arrow.counterclockwise")
                .labelStyle(.iconOnly)
        }
        .help(MenuBarL("Restore system cursors"))
    }

    private var currentCursorCaption: String {
        let name = model.visibleThemeName ?? MenuBarL("System cursors")
        return "\(MenuBarL("Current Cursor")): \(name)"
    }

    private var overrideCaption: String? {
        guard let override = model.overrideIdentifier, let app = model.frontDisplayName else { return nil }
        return "\(app) → \(model.name(forTheme: override) ?? override)"
    }

    private var themesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(MenuBarL("Cursor Themes"))
            if model.themes.isEmpty {
                emptyThemes(MenuBarL("No cursor themes yet"), caption: nil)
            } else if model.favoriteThemes.isEmpty {
                emptyThemes(MenuBarL("No favorite themes yet"),
                            caption: MenuBarL("Mark themes as favorites in MaCursor to show them here."))
            } else if model.favoriteThemes.count <= PanelMetrics.gridInlineLimit {
                themeGrid
            } else {
                ScrollView(.vertical) {
                    themeGrid
                }
                .frame(height: PanelMetrics.gridMaxHeight)
            }
        }
    }

    private var themeGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: PanelMetrics.gridSpacing),
                                 count: PanelMetrics.gridColumns),
                  spacing: PanelMetrics.gridSpacing) {
            ForEach(model.favoriteThemes) { theme in
                ThemeCard(name: theme.name, isApplied: model.visibleIdentifier == theme.id) {
                    model.apply(theme: theme.id)
                } preview: {
                    ZStack {
                        if let image = model.thumbnail(forTheme: theme.id) {
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFit()
                        } else {
                            Image(systemName: "cursorarrow.rays")
                                .font(.system(size: 20, weight: .regular))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: PanelMetrics.thumbnail, height: PanelMetrics.thumbnail)
                }
            }
        }
    }

    private func emptyThemes(_ title: String, caption: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            if let caption {
                Text(caption)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelCard()
    }

    private var activeAppSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(MenuBarL("Active App"))
            VStack(alignment: .leading, spacing: 8) {
                if let name = model.frontDisplayName {
                    HStack(spacing: 8) {
                        if let icon = model.frontIcon {
                            Image(nsImage: icon)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 24, height: 24)
                                .accessibilityHidden(true)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(name)
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                            Text(activeAppCaption)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    HStack(spacing: 8) {
                        Text(MenuBarL("Cursor for this app"))
                            .font(.system(size: 12))
                        Spacer(minLength: 8)
                        Picker(MenuBarL("Cursor for this app"), selection: frontRuleBinding) {
                            Text(MenuBarL("None")).tag("")
                            ForEach(model.appRuleChoices) { theme in
                                Text(theme.name).tag(theme.id)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .font(.system(size: 11))
                    }
                    if model.cursorGestures.enabled && model.accessibilityTrusted {
                        Toggle(isOn: binding(model.ignoresFrontApp, model.ignoreFrontApp)) {
                            Text(MenuBarL("Ignore Cursor Gestures")).frame(maxWidth: .infinity, alignment: .leading)
                        }
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .font(.system(size: 12))
                    }
                } else {
                    Text(MenuBarL("No app in front"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Toggle(isOn: binding(model.switchByApp, model.setSwitchByApp)) {
                    Text(MenuBarL("Per-App Themes")).frame(maxWidth: .infinity, alignment: .leading)
                }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .font(.system(size: 12))
            }
            .panelCard()
        }
    }

    private var activeAppCaption: String {
        if model.switchByApp, let rule = model.frontRuleThemeIdentifier, let name = model.name(forTheme: rule) {
            return String(format: MenuBarL("Uses %@"), name)
        }
        return MenuBarL("Uses the current cursor")
    }

    private var frontRuleBinding: Binding<String> {
        Binding(
            get: {
                let rule = model.frontRuleThemeIdentifier ?? ""
                return model.appRuleChoices.contains { $0.id == rule } ? rule : ""
            },
            set: { model.setFrontAppRule($0.isEmpty ? nil : $0) }
        )
    }

    private var quickControlsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(MenuBarL("Quick Controls"))
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(MenuBarL("Cursor Scale"))
                        .font(.system(size: 12))
                    Spacer()
                    Text(verbatim: scaleLabel)
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: scaleBinding,
                       in: MACMenuBarMinCursorScale...MACMenuBarMaxCursorScale,
                       step: 0.1) { editing in
                    if !editing { model.commitCursorScale() }
                }
                .controlSize(.small)
                .accessibilityLabel(MenuBarL("Cursor Scale"))
                .accessibilityValue(scaleLabel)
                Toggle(isOn: binding(model.cursorShadow, model.setCursorShadow)) {
                    Text(MenuBarL("Cursor Shadow")).frame(maxWidth: .infinity, alignment: .leading)
                }
                Toggle(isOn: focusFollowsMouseBinding) {
                    Text(MenuBarL("Focus on Hover")).frame(maxWidth: .infinity, alignment: .leading)
                }
                if model.focusFollowsMouse && model.accessibilityTrusted {
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { ffmDelayExpanded.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8.5, weight: .bold))
                                .foregroundStyle(.secondary)
                                .rotationEffect(.degrees(ffmDelayExpanded ? 90 : 0))
                                .accessibilityHidden(true)
                            Text(MenuBarL("Focus Delay"))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if ffmDelayExpanded {
                        delaySlider
                    }
                }
                Toggle(isOn: cursorGesturesBinding) {
                    Text(MenuBarL("Cursor Gestures")).frame(maxWidth: .infinity, alignment: .leading)
                }
                Toggle(isOn: cursorTranslatorBinding) {
                    Text(MenuBarL("Cursor Translator")).frame(maxWidth: .infinity, alignment: .leading)
                }
                Toggle(isOn: cursorShakerBinding) {
                    Text(MenuBarL("Cursor Shaker")).frame(maxWidth: .infinity, alignment: .leading)
                }
                if model.cursorShaker.enabled && model.accessibilityTrusted {
                    HStack(spacing: 8) {
                        Text(MenuBarL("Stop After"))
                        Spacer(minLength: 8)
                        Picker(MenuBarL("Stop After"), selection: Binding(get: { model.cursorShaker.stopAfter }, set: { model.setCursorShakerStopAfter($0) })) {
                            Text(MenuBarL("Never")).tag(nil as Int?)
                            ForEach(CursorShakerConfig.stopTimes, id: \.self) { minutes in
                                Text(CursorShakerConfig.stopLabel(minutes)).tag(minutes as Int?)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .font(.system(size: 11))
                    }
                }
                if (model.focusFollowsMouse || model.cursorGestures.enabled || model.cursorShaker.enabled || model.cursorTranslator.enabled) && !model.accessibilityTrusted {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(MenuBarL("Needs Accessibility access"))
                            .foregroundStyle(.secondary)
                        Button(MenuBarL("Open System Settings")) {
                            model.openAccessibilitySettings()
                        }
                        .buttonStyle(.link)
                    }
                    .font(.system(size: 10))
                }
                if model.cursorTranslator.enabled && model.accessibilityTrusted && !model.screenRecording {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(MenuBarL("Needs Screen Recording access"))
                            .foregroundStyle(.secondary)
                        Button(MenuBarL("Open System Settings")) {
                            CursorTranslatorConfig.requestScreenRecording()
                        }
                        .buttonStyle(.link)
                    }
                    .font(.system(size: 10))
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .font(.system(size: 12))
            .panelCard()
        }
    }

    private var cursorTrailsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { trailsExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(trailsExpanded ? 90 : 0))
                        .accessibilityHidden(true)
                    sectionTitle(MenuBarL("Cursor Trails"))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if trailsExpanded {
                VStack(spacing: 0) {
                    trailsRow(MenuBarL("Cursor Trails"), icon: "cursorarrow.motionlines", key: \.enabled, isOn: model.cursorTrails.enabled)
                    Divider().padding(.leading, 41).padding(.trailing, 10)
                    trailsRow(MenuBarL("Use Graphics Hardware"), icon: "cpu", key: \.useGPU, isOn: model.cursorTrails.useGPU && CursorTrailsConfig.hasMetal)
                    Divider().padding(.leading, 41).padding(.trailing, 10)
                    trailsRow(MenuBarL("Fade"), icon: "circle.lefthalf.filled", key: \.fade, isOn: model.cursorTrails.fade)
                    Divider().padding(.leading, 41).padding(.trailing, 10)
                    trailsRow(MenuBarL("Glow when still"), icon: "sun.max", key: \.glow, isOn: model.cursorTrails.glow)
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .panelCard(padding: 0)
            }
        }
    }

    private func trailsRow(_ title: String, icon: String, key: WritableKeyPath<CursorTrailsConfig, Bool>, isOn: Bool) -> some View {
        let enabled = model.cursorTrails.canSet(key)
        return Toggle(isOn: binding(isOn) { model.setCursorTrails(key, $0) }) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(nsColor: !enabled ? .tertiaryLabelColor : isOn ? .controlAccentColor : .secondaryLabelColor))
                    .frame(width: 22)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(enabled ? .primary : .tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .disabled(!enabled)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var scaleBinding: Binding<Double> {
        Binding(
            get: { model.cursorScale },
            set: { model.previewCursorScale($0) }
        )
    }

    private var scaleLabel: String {
        model.cursorScale.formatted(.number.precision(.fractionLength(2)).grouping(.never)) + "×"
    }

    private func milliseconds(_ value: Double) -> String {
        Duration.milliseconds(value).formatted(.units(allowed: [.milliseconds], width: .abbreviated))
    }

    private var delaySlider: some View {
        let label = String(format: MenuBarL("Delay window focus for %@"), milliseconds(model.ffmDelayMs))
        return VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Slider(value: $model.ffmDelayMs, in: 0...1000, step: 50) { editing in
                if !editing { model.commitFocusFollowsMouseDelay() }
            }
            .accessibilityLabel(label)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .kerning(0.5)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
    }

    private func binding(_ value: Bool, _ update: @escaping (Bool) -> Void) -> Binding<Bool> {
        Binding(get: { value }, set: { update($0) })
    }

    private var focusFollowsMouseBinding: Binding<Bool> {
        Binding(
            get: { model.focusFollowsMouse && model.accessibilityTrusted },
            set: { _ in model.toggleFocusFollowsMouse() }
        )
    }

    private var cursorGesturesBinding: Binding<Bool> {
        Binding(
            get: { model.cursorGestures.enabled && model.accessibilityTrusted },
            set: { _ in model.toggleCursorGestures() }
        )
    }

    private var cursorTranslatorBinding: Binding<Bool> {
        Binding(
            get: { model.cursorTranslator.enabled && model.accessibilityTrusted && model.screenRecording },
            set: { _ in model.toggleCursorTranslator() }
        )
    }

    private var cursorShakerBinding: Binding<Bool> {
        Binding(
            get: { model.cursorShaker.enabled && model.accessibilityTrusted },
            set: { _ in model.toggleCursorShaker() }
        )
    }
}

private struct PanelCard: ViewModifier {
    let padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: PanelMetrics.cardRadius, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: PanelMetrics.cardRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.7)
            )
    }
}

private extension View {
    func panelCard(padding: CGFloat = 10) -> some View {
        modifier(PanelCard(padding: padding))
    }
}
