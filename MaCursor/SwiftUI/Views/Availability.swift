import SwiftUI

extension View {
    @ViewBuilder
    func onChangeCompat<V: Equatable>(of value: V, perform action: @escaping (V) -> Void) -> some View {
        if #available(macOS 14, *) {
            onChange(of: value) { _, newValue in action(newValue) }
        } else {
            onChange(of: value, perform: action)
        }
    }

    @ViewBuilder
    func sidebarToggleRemoved() -> some View {
        if #available(macOS 14, *) {
            toolbar(removing: .sidebarToggle)
        } else {
            self
        }
    }

    @ViewBuilder
    func scrollContentTopMargin(_ length: CGFloat) -> some View {
        if #available(macOS 14, *) {
            contentMargins(.top, length, for: .scrollContent)
        } else {
            safeAreaInset(edge: .top, spacing: 0) { Color.clear.frame(height: length) }
        }
    }
}

struct UnavailableContent: View {
    let title: Text
    let systemImage: String
    var description: Text? = nil

    @ViewBuilder
    static func search(text: String) -> some View {
        if #available(macOS 14, *) {
            ContentUnavailableView.search(text: text)
        } else {
            UnavailableContent(title: Text("No Results for “\(text)”"), systemImage: "magnifyingglass")
        }
    }

    var body: some View {
        if #available(macOS 14, *) {
            ContentUnavailableView {
                Label { title } icon: { Image(systemName: systemImage) }
            } description: {
                if let description { description }
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                title
                    .font(.title2.bold())
                if let description {
                    description
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

extension NSWindow {
    func lockSizeAsLegacyAboutWindow() {
        styleMask.remove([.miniaturizable, .resizable])
    }
}

extension Color {
    static var quaternaryFill: Color {
        if #available(macOS 14, *) {
            return Color(nsColor: .quaternarySystemFill)
        }
        return Color(nsColor: .quaternaryLabelColor)
    }
}
