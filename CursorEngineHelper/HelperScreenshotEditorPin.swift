import AppKit

private enum CursorScreenshotPinMetrics {
    static let screenShare: CGFloat = 0.5
    static let closeSize: CGFloat = 20
    static let closeIcon: CGFloat = 14
    static let closeInset: CGFloat = 5
}

final class CursorScreenshotPinView: NSView {
    private let image: CGImage
    let closeButton = CursorScreenshotBarButton(label: MenuBarL("Close"), parts: [.icon(.close, CursorScreenshotPinMetrics.closeIcon)])

    init(image: CGImage, size: NSSize, close: @escaping () -> Void) {
        self.image = image
        super.init(frame: NSRect(origin: .zero, size: size))
        let look = CursorScreenshotPinMetrics.self
        closeButton.frame = CGRect(x: look.closeInset, y: look.closeInset, width: look.closeSize, height: look.closeSize)
        closeButton.fill = .white
        closeButton.tint = .black
        closeButton.onPress = close
        addSubview(closeButton)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel(MenuBarL("Pin"))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.interpolationQuality = .high
        CursorScreenshotRender.draw(image, in: bounds, on: context)
    }
}

@MainActor
final class CursorScreenshotPin: NSObject, NSWindowDelegate {
    private static var open: [CursorScreenshotPin] = []
    private let panel: NSPanel

    static func placed(_ image: CGImage, scale: CGFloat, on screen: CGRect) -> CGRect {
        let room = CGSize(width: screen.width * CursorScreenshotPinMetrics.screenShare, height: screen.height * CursorScreenshotPinMetrics.screenShare)
        let size = CursorScreenshotRender.placed(CGSize(width: image.width, height: image.height), in: room, backing: scale).size
        return CGRect(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2, width: size.width, height: size.height)
    }

    static func show(_ image: CGImage, scale: CGFloat, on screen: NSScreen?) {
        let area = (screen ?? NSScreen.main)?.visibleFrame ?? CGRect(x: 0, y: 0, width: image.width, height: image.height)
        open.append(CursorScreenshotPin(image: image, frame: placed(image, scale: scale, on: area)))
    }

    private init(image: CGImage, frame: CGRect) {
        panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.contentView = CursorScreenshotPinView(image: image, size: frame.size) { [weak self] in self?.panel.close() }
        panel.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        Self.open.removeAll { $0 === self }
    }
}
