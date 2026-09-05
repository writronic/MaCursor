import AppKit
import SwiftUI

@objc(MACMenuBarPanelHost)
@MainActor
final class MenuBarPanelHost: NSObject {
    @objc static func makeViewController() -> NSViewController {
        let host = NSHostingController(rootView: MenuBarPanelView(model: MenuBarPanelModel.shared))
        host.sizingOptions = [.preferredContentSize]
        return host
    }

    @objc static func reload() {
        MenuBarPanelModel.shared.reload()
    }
}
