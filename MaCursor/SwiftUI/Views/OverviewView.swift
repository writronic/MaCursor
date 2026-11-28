import SwiftUI

struct OverviewView: View {
    @ObservedObject private var library: LibraryViewModel
    private let snapshot: OverviewSnapshot
    private let openThemes: () -> Void
    private let open: (OverviewCard) -> Void
    private let toggle: (OverviewCard) -> Void
    private let openGallery: () -> Void

    init(library: LibraryViewModel, snapshot: OverviewSnapshot, openThemes: @escaping () -> Void,
         open: @escaping (OverviewCard) -> Void, toggle: @escaping (OverviewCard) -> Void, openGallery: @escaping () -> Void) {
        self.library = library
        self.snapshot = snapshot
        self.openThemes = openThemes
        self.open = open
        self.toggle = toggle
        self.openGallery = openGallery
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Overview")
                    .font(.system(size: 26, weight: .bold))
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                if let line = snapshot.welcome.access.helperLine {
                    Group {
                        if line == .install {
                            Text("Install the Helper Tool to use the switches on this page.")
                        } else {
                            Text("The Helper Tool is not running. Quit and reopen MaCursor to start it.")
                        }
                    }
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
                }
                header(String(localized: "Cursor Themes"))
                    .padding(.top, 18)
                HStack(spacing: OverviewCard.spacing) {
                    hero
                    gallery
                }
                ForEach(OverviewSection.allCases, id: \.self) { section in
                    header(section.title)
                        .padding(.top, 24)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: OverviewCard.minWidth), spacing: OverviewCard.spacing, alignment: .top)], spacing: OverviewCard.spacing) {
                        ForEach(section.cards, id: \.self) { card in
                            OverviewCardView(card: card, snapshot: snapshot, open: open, toggle: toggle)
                        }
                    }
                }
            }
            .padding(.top, 12)
            .padding(.horizontal, 26)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .lineLimit(1)
            .accessibilityAddTraits(.isHeader)
            .frame(height: 22)
            .padding(.leading, 2)
            .padding(.bottom, 8)
    }

    private var hero: some View {
        let applied = library.cursorThemes.first { $0.id == library.appliedThemeId }
        return HStack(spacing: 12) {
            Group {
                if let applied {
                    CursorThemeRowView(cursorTheme: applied)
                    Text("Applied")
                        .font(.system(size: 12))
                        .foregroundStyle(.green)
                        .fixedSize()
                } else {
                    Text("System cursors")
                        .font(.system(size: 15, weight: .semibold))
                    Spacer(minLength: 0)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: OverviewCard.heroHeight)
        .background {
            Button(action: openThemes) {
                OverviewCardBackground()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Cursor Themes"))
            .accessibilityValue(applied?.name ?? String(localized: "System cursors"))
        }
    }

    private var gallery: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Theme Gallery")
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Text("Find more cursor themes and add them to your library.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            Button("Browse Gallery…", action: openGallery)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: OverviewCard.heroHeight)
        .background {
            Button(action: openGallery) {
                OverviewCardBackground()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Theme Gallery"))
            .accessibilityHint(String(localized: "Find more cursor themes and add them to your library."))
        }
    }
}

struct OverviewCardView: View {
    let card: OverviewCard
    let snapshot: OverviewSnapshot
    let open: (OverviewCard) -> Void
    let toggle: (OverviewCard) -> Void

    var body: some View {
        content
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .background {
                Button { open(card) } label: {
                    OverviewCardBackground()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(card.title)
                .accessibilityValue(snapshot.statusText(card) ?? "")
            }
            .overlay(alignment: .topTrailing) {
            if card.hasSwitch {
                Toggle(card.title, isOn: Binding(get: { snapshot.isOn(card) }, set: { _ in toggle(card) }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .disabled(snapshot.isLocked(card))
                    .padding(OverviewCard.padding)
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(card.title)
                .font(.headline)
                .lineLimit(1)
            if let status = snapshot.statusText(card) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                        .frame(width: 12)
                    Text(status)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(nsColor: snapshot.statusIsError(card) ? .systemRed : .secondaryLabelColor))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)
            }
        }
        .padding(OverviewCard.padding)
        .padding(.top, FeaturePageLayout.tile + 6)
        .frame(maxWidth: .infinity, minHeight: OverviewCard.height, alignment: .topLeading)
        .overlay(alignment: .topLeading) {
            FeatureTile(symbol: card.symbol, tint: card.tint, large: false)
                .padding(OverviewCard.padding)
        }
    }
}

private struct OverviewCardBackground: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        shape
            .fill(Color.boxFill)
            .overlay(shape.strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
            .contentShape(shape)
    }
}
