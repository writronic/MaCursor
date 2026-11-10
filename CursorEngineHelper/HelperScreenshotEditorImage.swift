import AppKit

enum CursorScreenshotDropLook {
    static let menuGap: CGFloat = 8
    static let bandGray: CGFloat = 0.1
    static let bandAlpha: CGFloat = 0.7
    @MainActor static let labelFont = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
}

extension CursorScreenshotEditorMenus {
    static func addImage(actions: CursorScreenshotEditorActions) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let take = CursorScreenshotMenuItem(title: MenuBarL("Take Screenshot"), key: "i", run: actions.takeImage)
        take.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(take)
        if CursorScreenshotImageSource.holdsImage(.general) {
            menu.addItem(CursorScreenshotMenuItem(title: MenuBarL("Paste From Clipboard"), key: "v", run: actions.pasteImage))
        }
        menu.addItem(.separator())
        menu.addItem(CursorScreenshotMenuItem(title: MenuBarL("Choose From File…"), key: "i", run: actions.chooseImage))
        return menu
    }
}

extension CursorScreenshotImageEdge {
    @MainActor var word: String {
        switch self {
        case .top: return MenuBarL("Top")
        case .bottom: return MenuBarL("Bottom")
        case .left: return MenuBarL("Left")
        case .right: return MenuBarL("Right")
        }
    }
}

final class CursorScreenshotDropZoneView: NSView {
    var edge: CursorScreenshotImageEdge? {
        didSet { if edge != oldValue { needsDisplay = true } }
    }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let edge else { return }
        let look = CursorScreenshotDropLook.self
        let depth = CursorScreenshotEditorLook.dropBandPoints
        let band: CGRect
        let angle: CGFloat
        switch edge {
        case .top: (band, angle) = (CGRect(x: 0, y: 0, width: bounds.width, height: depth), 90)
        case .bottom: (band, angle) = (CGRect(x: 0, y: bounds.height - depth, width: bounds.width, height: depth), 270)
        case .left: (band, angle) = (CGRect(x: 0, y: 0, width: depth, height: bounds.height), 0)
        case .right: (band, angle) = (CGRect(x: bounds.width - depth, y: 0, width: depth, height: bounds.height), 180)
        }
        NSGradient(starting: NSColor(white: look.bandGray, alpha: look.bandAlpha), ending: .clear)?.draw(in: band, angle: angle)
        let label = NSAttributedString(string: edge.word, attributes: [.font: look.labelFont, .foregroundColor: NSColor.white])
        let size = label.size()
        label.draw(at: NSPoint(x: band.midX - size.width / 2, y: band.midY - size.height / 2))
    }
}

extension CursorScreenshotEditorCanvas {
    var visiblePictureArea: CGRect {
        let seen = visibleRect.intersection(placement)
        let area = model.shownArea
        let unit = 1 / max(model.viewScale, 0.0001)
        return CGRect(x: area.minX + (seen.minX - placement.minX) * unit, y: area.minY + (seen.minY - placement.minY) * unit, width: seen.width * unit, height: seen.height * unit)
    }
}
