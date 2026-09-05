import SwiftUI

struct AboutSettingsView: View {
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }


    private var yearString: String {
        String(Calendar.current.component(.year, from: Date()))
    }

    var body: some View {
        VStack(spacing: 0) {
            if let appIcon = NSApp.applicationIconImage {
                Image(nsImage: appIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
            }

            Text("MaCursor")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .padding(.top, 16)

            Text("Version \(appVersion)")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .padding(.top, 10)

            Text("Cursor Control for macOS")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .padding(.top, 8)

            Spacer()
                .frame(height: 40)

            VStack(spacing: 6) {
                Text("Made with ❤️")
                    .font(.system(size: 16, weight: .semibold))

                Text("Copyright © \(yearString) Writronic. All rights reserved.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)

                AboutActionButtons(fontSize: 13)
                    .padding(.top, 12)
            }

            Spacer()
                .frame(height: 40)

            Text("GPL-3.0")
                .font(.system(size: 14))
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("About")
    }
}

struct AboutWindowView: View {
    @State private var aboutWindow: NSWindow?

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }


    private var yearString: String {
        String(Calendar.current.component(.year, from: Date()))
    }

    var body: some View {
        VStack(spacing: 14) {
            if let appIcon = NSApp.applicationIconImage {
                Image(nsImage: appIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
            }

            Text("MaCursor")
                .font(.system(size: 24, weight: .bold, design: .rounded))

            VStack(spacing: 6) {
                Text("Version \(appVersion)")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                Text("Cursor Control for macOS")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()
                .frame(height: 10)

            VStack(spacing: 6) {
                Text("Made with ❤️")
                    .font(.system(size: 14, weight: .semibold))

                Text("Copyright © \(yearString) Writronic. All rights reserved.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                AboutActionButtons(fontSize: 12)
                    .padding(.top, 8)
            }

            Spacer()
                .frame(height: 5)

            Text("GPL-3.0")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 32)
        .frame(minWidth: 360, minHeight: 320)
        .background(AboutWindowAccessor(window: $aboutWindow))
        .background(WindowRoleAccessor(role: .modal))
        .overlay {
            Button("") { aboutWindow?.close() }
                .keyboardShortcut(.cancelAction)
                .frame(width: 0, height: 0)
                .opacity(0)
                .allowsHitTesting(false)
        }
    }
}

private struct AboutActionButtons: View {
    let fontSize: CGFloat

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { buttons }
            VStack(spacing: 8) { buttons }
        }
        .font(.system(size: fontSize))
    }

    @ViewBuilder
    private var buttons: some View {
        Button("Visit Website") {
            NSWorkspace.shared.open(MACConstants.websiteURL)
        }
        .buttonStyle(.bordered)

        Button {
            NSWorkspace.shared.open(MACConstants.donateURL)
        } label: {
            Label("Donate", systemImage: "heart.fill")
        }
        .buttonStyle(.borderedProminent)
    }
}

private struct AboutWindowAccessor: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            self.window = view.window
            Self.lockWindowSize(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        self.window = nsView.window
        Self.lockWindowSize(nsView.window)
    }

    private static func lockWindowSize(_ window: NSWindow?) {
        if #unavailable(macOS 15) {
            window?.lockSizeAsLegacyAboutWindow()
        }
    }
}
