import SwiftUI
import AppKit

struct WindowRoleAccessor: NSViewRepresentable {
    let role: ModalWindowRole

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            register(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        register(nsView.window)
    }

    private func register(_ window: NSWindow?) {
        guard let window else { return }
        ModalWindowCoordinator.shared.register(window, as: role)
    }
}

struct MainWindowHoldAccessor: NSViewRepresentable {
    let onHold: @MainActor @Sendable () -> Void

    func makeNSView(context: Context) -> HoldView {
        HoldView(onHold: onHold)
    }

    func updateNSView(_ nsView: HoldView, context: Context) {}

    final class HoldView: NSView {
        private let onHold: @MainActor @Sendable () -> Void

        init(onHold: @escaping @MainActor @Sendable () -> Void) {
            self.onHold = onHold
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, ModalWindowCoordinator.shared.holdMainWindowIfNeeded(window) else { return }
            let onHold = onHold
            DispatchQueue.main.async { onHold() }
        }
    }
}
