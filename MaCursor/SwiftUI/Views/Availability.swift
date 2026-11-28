import SwiftUI

enum SystemSettingsPane {
    enum FinderExtensions {
        case extensions
        case fileProviders
        case command
    }

    static func finderExtensions(on version: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion) -> FinderExtensions {
        if version.majorVersion == 15 && version.minorVersion < 2 { return .command }
        if version.majorVersion > 15 || (version.majorVersion == 15 && version.minorVersion >= 2) { return .fileProviders }
        return .extensions
    }

    static func screenRecordingHasAudio(on version: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion) -> Bool {
        version.majorVersion >= 14
    }
}

enum ScreenCaptureSupport {
    static func controlsWindowShadow(on version: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion) -> Bool {
        version.majorVersion >= 14
    }
}

extension View {
    @ViewBuilder
    func onChangeCompat<V: Equatable>(of value: V, perform action: @escaping (V) -> Void) -> some View {
        if #available(macOS 14, *) {
            onChange(of: value) { _, newValue in action(newValue) }
        } else {
            onChange(of: value, perform: action)
        }
    }

    func toolbarTitleItem(_ title: LocalizedStringKey, placement: ToolbarItemPlacement = .automatic) -> some View {
        toolbarTitleItem(Text(title), placement: placement)
    }

    @ViewBuilder
    func toolbarTitleItem(_ title: Text, placement: ToolbarItemPlacement = .automatic, gap: CGFloat = 0) -> some View {
        if #available(macOS 26, *) {
            toolbar {
                ToolbarItem(placement: placement) { title.font(.title3.weight(.semibold)).padding(.leading, gap) }
                    .sharedBackgroundVisibility(.hidden)
            }
        } else {
            toolbar {
                ToolbarItem(placement: placement) { title.font(.headline) }
            }
        }
    }

    @ViewBuilder
    func focusEffectDisabledCompat() -> some View {
        if #available(macOS 14, *) {
            focusEffectDisabled()
        } else {
            self
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

extension NSWindow {
    func useMacOS27Background() {
        if #unavailable(macOS 27) { backgroundColor = .windowFill }
    }
}

extension NSColor {
    static var secondaryFill: NSColor {
        if #available(macOS 14, *) {
            return .secondarySystemFill
        }
        return .quaternaryLabelColor
    }

    static func fixedGrey(_ value: CGFloat) -> NSColor {
        NSColor(srgbRed: value / 255, green: value / 255, blue: value / 255, alpha: 1)
    }

    static func olderMacOSLook(_ system: NSColor, light: NSColor, dark: NSColor,
                               increaseContrast: @escaping () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast }) -> NSColor {
        NSColor(name: nil) { appearance in
            if increaseContrast() { return system }
            return appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }

    static func macOS27(_ system: NSColor, light: NSColor, dark: NSColor) -> NSColor {
        if #available(macOS 27, *) { return system }
        return olderMacOSLook(system, light: light, dark: dark)
    }

    static let windowFill = macOS27(.windowBackgroundColor, light: fixedGrey(255), dark: fixedGrey(30))
}

extension Color {
    static var quaternaryFill: Color {
        if #available(macOS 14, *) {
            return Color(nsColor: .quaternarySystemFill)
        }
        return Color(nsColor: .olderMacOSLook(.quaternaryLabelColor, light: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 7 / 255), dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 7 / 255)))
    }
}
