import SwiftUI

extension Color {
    static let pageFill = Color(nsColor: .macOS27(systemPageFill, light: .fixedGrey(235), dark: .fixedGrey(30)))

    private static let systemPageFill = NSColor(name: nil) { appearance in
        guard appearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua else { return .windowBackgroundColor }
        var page = NSColor.windowBackgroundColor
        appearance.performAsCurrentDrawingAppearance {
            guard let window = NSColor.windowBackgroundColor.usingColorSpace(.sRGB),
                  let fill = NSColor.secondaryFill.usingColorSpace(.sRGB) else { return }
            let mix = { (under: CGFloat, over: CGFloat) in under + (over - under) * fill.alphaComponent }
            page = NSColor(srgbRed: mix(window.redComponent, fill.redComponent), green: mix(window.greenComponent, fill.greenComponent),
                           blue: mix(window.blueComponent, fill.blueComponent), alpha: 1)
        }
        return page
    }

    static let boxFill = Color(nsColor: .macOS27(.underPageBackgroundColor, light: .fixedGrey(246), dark: .fixedGrey(40)))
}

struct FeatureTile: View {
    let symbol: String
    let tint: FeatureTint
    let large: Bool

    var body: some View {
        let side = large ? FeaturePageLayout.boxTile : FeaturePageLayout.tile
        Image(systemName: symbol)
            .font(.system(size: large ? FeaturePageLayout.boxTileSymbol : FeaturePageLayout.tileSymbol))
            .foregroundStyle(.white)
            .frame(width: side, height: side)
            .background(tint.color, in: RoundedRectangle(cornerRadius: large ? FeaturePageLayout.boxTileRadius : FeaturePageLayout.tileRadius,
                                                         style: .continuous))
            .accessibilityHidden(true)
    }
}

struct FeatureTabList: View {
    private let titles: [String]
    private let styles: [FeatureTabStyle]
    private let label: String
    @Binding private var selection: Int
    @Environment(\.colorScheme) private var colorScheme

    private var selectedFill: Color {
        colorScheme == .dark ? Color(nsColor: .quaternaryLabelColor) : Color.primary.opacity(0.08)
    }

    init(titles: [String], styles: [FeatureTabStyle], label: String, selection: Binding<Int>) {
        self.titles = titles
        self.styles = styles
        self.label = label
        _selection = selection
    }

    var body: some View {
        VStack(spacing: FeaturePageLayout.rowGap) {
            ForEach(Array(zip(titles, styles).enumerated()), id: \.offset) { index, item in
                row(index, title: item.0, style: item.1)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    private func row(_ index: Int, title: String, style: FeatureTabStyle) -> some View {
        let selected = index == selection
        let separated = !selected && index + 1 != selection && index < titles.count - 1
        let shape = RoundedRectangle(cornerRadius: FeaturePageLayout.rowRadius, style: .continuous)
        return Button { selection = index } label: {
            HStack(spacing: FeaturePageLayout.rowSpacing) {
                FeatureTile(symbol: style.symbol, tint: style.tint, large: false)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(style.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, FeaturePageLayout.rowPadding)
            .frame(height: FeaturePageLayout.rowHeight)
            .background(selected ? selectedFill : .clear, in: shape)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            if separated {
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(height: 1)
                    .padding(.leading, FeaturePageLayout.rowPadding + FeaturePageLayout.tile + FeaturePageLayout.rowSpacing)
                    .padding(.trailing, FeaturePageLayout.rowPadding)
                    .offset(y: FeaturePageLayout.rowGap / 2 + 0.5)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct FeatureOnOffBox: View {
    private let title: String
    private let subtitle: String?
    private let symbol: String
    private let tint: FeatureTint
    @Binding private var isOn: Bool

    init(title: String, subtitle: String?, symbol: String, tint: FeatureTint, isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.tint = tint
        _isOn = isOn
    }

    var body: some View {
        HStack(spacing: FeaturePageLayout.gap) {
            FeatureTile(symbol: symbol, tint: tint, large: true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .frame(minHeight: FeaturePageLayout.boxMinHeight)
        .background(Color.boxFill, in: RoundedRectangle(cornerRadius: FeaturePageLayout.boxRadius, style: .continuous))
    }
}

struct ExplainerCard: View {
    private let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        ExplainerText(text: text)
            .padding(.vertical, 11)
            .padding(.horizontal, 14)
            .background(Color.boxFill, in: RoundedRectangle(cornerRadius: FeaturePageLayout.cardRadius, style: .continuous))
    }
}

struct ExplainerSection: View {
    private let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Section {
            ExplainerText(text: text)
        }
    }
}

struct FeatureSection<Content: View, Footer: View>: View {
    private let title: LocalizedStringKey?
    private let note: LocalizedStringKey?
    private let footer: Footer
    private let rowFloor: Bool
    private let content: Content

    init(_ title: LocalizedStringKey? = nil, note: LocalizedStringKey? = nil, rowFloor: Bool = true,
         @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.title = title
        self.note = note
        self.footer = footer()
        self.rowFloor = rowFloor
        self.content = content()
    }

    var body: some View {
        if let title {
            Section {
                rows
            } header: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                    if let note {
                        Text(note)
                            .font(.system(size: 11))
                    }
                }
                .foregroundStyle(.secondary)
            } footer: {
                footer
            }
        } else {
            Section {
                rows
            } footer: {
                footer
            }
        }
    }

    @ViewBuilder
    private var rows: some View {
        if rowFloor {
            Group { content }
                .frame(minHeight: FeaturePageLayout.formRowFloor)
        } else {
            content
        }
    }
}

extension FeatureSection where Footer == Text? {
    init(_ title: LocalizedStringKey? = nil, note: LocalizedStringKey? = nil, footer: LocalizedStringKey? = nil, rowFloor: Bool = true,
         @ViewBuilder content: () -> Content) {
        self.init(title, note: note, rowFloor: rowFloor, content: content, footer: { footer.map { Text($0) } })
    }
}

struct FeatureRowLabel<Note: View>: View {
    private let title: LocalizedStringKey
    private let note: Note

    init(_ title: LocalizedStringKey, @ViewBuilder note: () -> Note) {
        self.title = title
        self.note = note()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            note
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

extension View {
    func featureNotice() -> some View {
        padding(.vertical, 12)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.boxFill, in: RoundedRectangle(cornerRadius: FeaturePageLayout.cardRadius, style: .continuous))
    }
}

private struct ExplainerText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FeaturePageFrame<Header: View, Tabs: View, Pane: View>: View {
    private let header: Header
    private let tabs: Tabs?
    private let pane: Pane

    init(@ViewBuilder header: () -> Header, @ViewBuilder tabs: () -> Tabs?, @ViewBuilder pane: () -> Pane) {
        self.header = header()
        self.tabs = tabs()
        self.pane = pane()
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, FeaturePageLayout.sideMargin)
                .padding(.top, FeaturePageLayout.gap)
            HStack(spacing: 0) {
                if let tabs {
                    tabs
                        .frame(width: FeaturePageLayout.listWidth)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .padding(.leading, FeaturePageLayout.listLeading)
                        .padding(.trailing, FeaturePageLayout.listTrailing)
                    Divider()
                }
                pane
                    .scrollContentBackground(.hidden)
                    .padding(.top, FeaturePageLayout.paneTopInset - FeaturePageLayout.formTopInset)
                    .clipped()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.top, FeaturePageLayout.gap)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

extension FeaturePageFrame where Tabs == EmptyView {
    init(@ViewBuilder header: () -> Header, @ViewBuilder pane: () -> Pane) {
        self.header = header()
        self.tabs = nil
        self.pane = pane()
    }
}
