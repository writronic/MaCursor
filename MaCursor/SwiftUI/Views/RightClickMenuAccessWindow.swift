import Combine
import SwiftUI

final class AccessWindowController: NSWindowController, NSWindowDelegate {
    static let rightClickMenu = AccessWindowController(title: String(localized: "Right-Click Menu")) {
        NSHostingController(rootView: RightClickMenuAccessView())
    }

    private let makeContent: () -> NSViewController

    init(title: String, content: @escaping () -> NSViewController) {
        makeContent = content
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        window.title = title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.useMacOS27Background()
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        guard let window else { return }
        if !window.isVisible {
            let content = makeContent()
            window.contentViewController = content
            window.setContentSize(content.view.fittingSize)
        }
        attach(window, to: anchorWindow())
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func reanchor() {
        guard let window, window.isVisible,
              let modal = ModalWindowCoordinator.shared.activeModalWindow, modal.isVisible,
              window.parent !== modal else { return }
        attach(window, to: modal)
    }

    func dismiss() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window else { return }
        window.parent?.removeChildWindow(window)
    }

    private func anchorWindow() -> NSWindow? {
        if let modal = ModalWindowCoordinator.shared.activeModalWindow, modal.isVisible { return modal }
        return NSApp.windows.first { $0.isVisible && $0.canBecomeMain && $0 !== window }
    }

    private func attach(_ window: NSWindow, to parent: NSWindow?) {
        guard let parent, parent !== window, parent.isVisible else {
            window.center()
            return
        }
        window.parent?.removeChildWindow(window)
        let visibleFrame = parent.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? parent.frame
        window.setFrameOrigin(ModalWindowPlacement.centeredOrigin(
            size: window.frame.size,
            over: parent.frame,
            constrainedTo: visibleFrame
        ))
        parent.addChildWindow(window, ordered: .above)
    }
}

struct FinderExtensionAccessControls: View {
    @ObservedObject private var manager = FinderExtensionManager.shared

    var body: some View {
        Group {
            switch SystemSettingsPane.finderExtensions() {
            case .extensions:
                Text("Enable MaCursorFinder in System Settings to add MaCursor’s shortcuts to Finder’s right-click menu.")
            case .fileProviders:
                Text("Turn on MaCursorFinder in System Settings → General → Login Items & Extensions → Extensions → File Providers.")
            case .command:
                Text("macOS 15.0 and 15.1 cannot turn on Finder extensions from System Settings. Copy the command and run it in Terminal.")
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

        if SystemSettingsPane.finderExtensions() == .command {
            Button("Copy Command") { manager.copyCommand() }
        } else {
            Button("Open System Settings") { manager.openSystemSettings() }
        }
    }
}

private struct RightClickMenuAccessView: View {
    @ObservedObject private var manager = FinderExtensionManager.shared
    @State private var step = RightClickMenuState.accessStep(election: FinderExtensionManager.shared.election)
    @State private var errorMessage: String?
    private let waitTicker = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        let shown = manager.election == .elected ? step : .finderExtension
        AccessDialog(title: Text("Right-Click Menu")) {
            VStack(spacing: 4) {
                Text(shown.progress)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(shown.title)
                    .font(.headline)
            }

            switch shown {
            case .finderExtension:
                if manager.election == .elected {
                    Label("Access granted", systemImage: "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.green)
                } else {
                    FinderExtensionAccessControls()
                }
            case .fullDiskAccess:
                Text("MaCursor needs Full Disk Access. Turn on MaCursor in System Settings, then quit and reopen MaCursor if macOS asks.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if manager.settings.hasFullDiskAccess {
                    Label("Access granted", systemImage: "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.green)
                } else {
                    Button("Open System Settings") { manager.openFullDiskAccessSettings() }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if shown == .fullDiskAccess {
                if manager.settings.hasFullDiskAccess {
                    Button("Let’s Go!") {
                        do {
                            if try manager.setEnabled(true) {
                                AccessWindowController.rightClickMenu.dismiss()
                            }
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                }
            } else if manager.election == .elected {
                Button("Continue") { step = .fullDiskAccess }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .onAppear {
            MACPreferences.setFlag(true, forKey: MACPreferences.fullDiskAccessAskedKey)
            manager.refresh()
        }
        .onReceive(waitTicker) { _ in
            guard AccessWindowController.rightClickMenu.window?.isVisible == true else { return }
            manager.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            guard AccessWindowController.rightClickMenu.window?.isVisible == true else { return }
            manager.refresh()
        }
        .onReceive(ModalWindowCoordinator.shared.activeModalDidChange) { _ in
            AccessWindowController.rightClickMenu.reanchor()
        }
    }
}

struct AccessDialog<Content: View>: View {
    let title: Text
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                .resizable()
                .frame(width: 76, height: 76)

            title
                .font(.title2.weight(.semibold))

            content
        }
        .controlSize(.large)
        .multilineTextAlignment(.center)
        .padding(28)
        .frame(width: 460)
    }
}
