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

    var body: some View {
        VStack(alignment: .leading, spacing: PanelMetrics.sectionSpacing) {
            header
            themesSection
            activeAppSection
            quickControlsSection
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
                ThemeCard(name: theme.name,
                          image: model.thumbnail(forTheme: theme.id),
                          isApplied: model.visibleIdentifier == theme.id) {
                    model.apply(theme: theme.id)
                }
            }
        }
        .padding(2)
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
                    Picker(MenuBarL("Cursor for this app"), selection: frontRuleBinding) {
                        Text(MenuBarL("None")).tag("")
                        ForEach(model.appRuleChoices) { theme in
                            Text(theme.name).tag(theme.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .font(.system(size: 11))
                } else {
                    Text(MenuBarL("No app in front"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Toggle(MenuBarL("Per-App Themes"), isOn: binding(model.switchByApp, model.setSwitchByApp))
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
                Toggle(MenuBarL("Cursor Shadow"), isOn: binding(model.cursorShadow, model.setCursorShadow))
                Toggle(MenuBarL("Focus on Hover"), isOn: focusFollowsMouseBinding)
                if model.focusFollowsMouse && !model.accessibilityTrusted {
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
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .font(.system(size: 12))
            .panelCard()
        }
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
}

private struct ThemeCard: View {
    let name: String
    let image: NSImage?
    let isApplied: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    if let image {
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
                Text(name)
                    .font(.system(size: 10.5))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: 72)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isApplied ? Color.accentColor.opacity(0.14) : Color.primary.opacity(hovering ? 0.09 : 0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isApplied ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
            .overlay(alignment: .topTrailing) {
                if isApplied {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.accentColor)
                        .padding(4)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(name)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isApplied ? .isSelected : [])
    }
}

private struct PanelCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(10)
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
    func panelCard() -> some View {
        modifier(PanelCard())
    }
}
