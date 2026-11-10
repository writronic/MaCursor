import AppKit

enum CursorScreenshotEditorPalette {
    private static func shade(_ light: NSColor, _ dark: NSColor) -> NSColor {
        NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light }
    }

    private static func gray(_ value: CGFloat) -> NSColor {
        NSColor(srgbRed: value / 255, green: value / 255, blue: value / 255, alpha: 1)
    }

    private static func black(_ alpha: CGFloat) -> NSColor { NSColor(srgbRed: 0, green: 0, blue: 0, alpha: alpha) }
    private static func white(_ alpha: CGFloat) -> NSColor { NSColor(srgbRed: 1, green: 1, blue: 1, alpha: alpha) }

    static let background = shade(gray(255), gray(30))
    static let foreground = shade(black(0.85), white(0.85))
    static let barStart = shade(gray(214), gray(40))
    static let barEnd = shade(gray(232), gray(50))
    static let separator = shade(black(0.10), white(0.12))
    static let capsule = shade(black(0.06), white(0.08))
    static let button = shade(gray(255), white(0.12))
    static let muted = shade(black(0.50), white(0.55))
    static let edge = shade(black(0.26), white(0.25))
    static let hover = shade(black(0.10), white(0.14))
    static let panel = shade(gray(245), gray(44))
    static let panelSide = shade(gray(232), gray(54))
    static let panelEdge = shade(.clear, white(0.14))
    static let shadow = shade(black(0.25), black(0.5))
    static let sub = shade(black(0.60), white(0.55))
    static let well = shade(black(0.10), white(0.10))
    static let rule = shade(NSColor(srgbRed: 26 / 255, green: 26 / 255, blue: 26 / 255, alpha: 0.15), NSColor(srgbRed: 230 / 255, green: 230 / 255, blue: 230 / 255, alpha: 0.15))
    static let backgroundPanel = shade(gray(246), gray(40))
    static let label = shade(black(0.65), white(0.70))
}

enum CursorScreenshotEditorMetrics {
    static let topBarHeight: CGFloat = 40
    static let bottomBarHeight: CGFloat = 44
    static let controlHeight: CGFloat = 26
    static let roundButtonWidth: CGFloat = 36
    static let groupGap: CGFloat = 6
    static let sectionGap: CGFloat = 12
    static let capsuleHeight: CGFloat = 24
    static let toolWidth: CGFloat = 35
    static let smallestToolWidth: CGFloat = 22
    static let toolHeight: CGFloat = 24
    static let dividerHeight: CGFloat = 14
    static let propertyWidth: CGFloat = 40
    static let sliderWidth: CGFloat = 84
    static let smallestSliderWidth: CGFloat = 54
    static let saveWidth: CGFloat = 77
    static let doneWidth: CGFloat = 51
    static let saveDoneGap: CGFloat = 10
    static let topBarSide: CGFloat = 4
    static let topBarItemHeight: CGFloat = 26
    static let zoomWidth: CGFloat = 70
    static let dragWidth: CGFloat = 116
    static let dragHeight: CGFloat = 31
    static let bottomLeft: CGFloat = 7
    static let bottomRight: CGFloat = 10
    static let titlePadding: CGFloat = 9
    static let partGap: CGFloat = 4
    static let toolIcon: CGFloat = 16
    static let roundIcon: CGFloat = 20
    static let actionIcon: CGFloat = 18
    static let chevron: CGFloat = 9
    static let grip: CGFloat = 10
    static let swatch: CGFloat = 14
    static let sizeLine: CGFloat = 16
    static let tick: CGFloat = 16
    static let textStyleLetter: CGFloat = 16
    @MainActor static let textFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    @MainActor static let doneFont = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
    @MainActor static let zoomFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    @MainActor static let dragFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    static let smallestBarWidth: CGFloat = 740
    static let barWidthInSmallestWindow: CGFloat = 778

    static func sizeSampleWidth(_ size: CGFloat) -> CGFloat {
        min(max(size * 0.3, 1), 6)
    }
}

enum CursorScreenshotEditorIcon: CaseIterable {
    case crop, addImage, background, select, box, filledBox, oval, line, arrow, pen, text, pixelate, spotlight, highlight, number, undo, redo, share, pin, copy, chevron, grip, close, back, plus, pipette
    case locked, unlocked, smile, drop, dropLocked, moon, shapeRectangle, shapeRounded, shapeOval, arrowStandard, arrowFancy, arrowCurved, arrowDouble
    case swap, rotate, flip, check

    private static func lines(_ path: CGMutablePath, _ pieces: [[(CGFloat, CGFloat)]], closed: Bool = false) {
        for piece in pieces {
            path.addLines(between: piece.map { CGPoint(x: $0.0, y: $0.1) })
            if closed { path.closeSubpath() }
        }
    }

    private static func roundedBox(_ path: CGMutablePath, _ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ radius: CGFloat) {
        path.addRoundedRect(in: CGRect(x: x, y: y, width: width, height: height), cornerWidth: radius, cornerHeight: radius)
    }

    var box: CGSize {
        switch self {
        case .chevron: return CGSize(width: 10, height: 10)
        case .grip: return CGSize(width: 12, height: 14)
        default: return CGSize(width: 20, height: 20)
        }
    }

    private var macOS14Symbol: String? {
        switch self {
        case .addImage: return "photo.badge.plus"
        case .shapeRounded: return "button.horizontal"
        default: return nil
        }
    }

    private var symbol: String? {
        if #available(macOS 14, *), let newer = macOS14Symbol { return newer }
        switch self {
        case .crop: return "crop"
        case .addImage: return "photo"
        case .background: return "rectangle.inset.filled"
        case .select: return "cursorarrow"
        case .box: return "rectangle"
        case .filledBox: return "rectangle.fill"
        case .oval: return "oval"
        case .line: return "line.diagonal"
        case .arrow: return "arrow.up.right"
        case .pen: return "pencil"
        case .text: return "textformat"
        case .spotlight: return "dot.viewfinder"
        case .highlight: return "highlighter"
        case .number: return "number.circle"
        case .undo: return "arrow.uturn.backward"
        case .redo: return "arrow.uturn.forward"
        case .share: return "square.and.arrow.up"
        case .pin: return "pin"
        case .copy: return "doc.on.doc"
        case .chevron: return "chevron.down"
        case .grip: return "line.3.horizontal"
        case .close: return "xmark"
        case .back: return "chevron.left"
        case .plus: return "plus"
        case .pipette: return "eyedropper"
        case .locked: return "lock.fill"
        case .unlocked: return "lock.open.fill"
        case .smile: return "face.smiling"
        case .drop: return "drop.fill"
        case .moon: return "moon.fill"
        case .swap: return "arrow.left.and.right"
        case .rotate: return "rotate.left"
        case .flip: return "flip.horizontal"
        case .check: return "checkmark"
        case .dropLocked: return "eye.slash"
        case .shapeRectangle: return "rectangle"
        case .shapeOval: return "oval"
        case .pixelate, .shapeRounded, .arrowStandard, .arrowFancy, .arrowCurved, .arrowDouble: return nil
        }
    }

    private var symbolFit: CGFloat {
        switch self {
        case .dropLocked, .shapeOval: return 0.8
        case .shapeRounded: return 0.97
        default: return 1
        }
    }

    private func symbolWeight(_ height: CGFloat) -> NSFont.Weight {
        if self == .check || height < 9.5 { return .black }
        if height < 13 { return .heavy }
        if height < 17 { return .bold }
        if height < 19 { return .semibold }
        return .medium
    }

    private var paths: (stroke: CGPath, fill: CGPath?) {
        let stroke = CGMutablePath()
        let extra = CGMutablePath()
        switch self {
        case .shapeRounded:
            Self.roundedBox(extra, 0.85, 2.8, 18.3, 14.4, 4.6)
            Self.roundedBox(extra, 2.85, 4.8, 14.3, 10.4, 2.6)
            return (stroke, extra)
        case .arrowStandard:
            Self.lines(stroke, [[(18, 10), (7, 10)]])
            Self.lines(extra, [[(2, 10), (8, 6.5), (8, 13.5)]], closed: true)
            return (stroke, extra)
        case .arrowFancy:
            Self.lines(extra, [[(2, 10), (8, 6), (7, 9), (18, 10), (7, 11), (8, 14)]], closed: true)
            return (extra, extra)
        case .arrowCurved:
            stroke.move(to: CGPoint(x: 18, y: 13))
            stroke.addQuadCurve(to: CGPoint(x: 2.5, y: 13), control: CGPoint(x: 10, y: 3))
            Self.lines(stroke, [[(3, 7.5), (2.5, 13), (8, 12.5)]])
        case .arrowDouble:
            stroke.move(to: CGPoint(x: 17.5, y: 13))
            stroke.addQuadCurve(to: CGPoint(x: 2.5, y: 13), control: CGPoint(x: 10, y: 3))
            Self.lines(stroke, [[(3, 7.5), (2.5, 13), (8, 12.5)], [(17, 7.5), (17.5, 13), (12, 12.5)]])
        default:
            break
        }
        return (stroke, nil)
    }

    func draw(in rect: CGRect, color: NSColor, on context: CGContext) {
        if self == .pixelate {
            let side = rect.height
            let square = CGRect(x: rect.midX - side / 2, y: rect.minY, width: side, height: side)
            context.saveGState()
            context.addPath(CGPath(roundedRect: square, cornerWidth: side * 3 / 16, cornerHeight: side * 3 / 16, transform: nil))
            context.clip()
            let strong = color.cgColor
            for faint in [false, true] {
                context.setFillColor(faint ? strong.copy(alpha: strong.alpha * 0.35) ?? strong : strong)
                for index in 0..<16 where (index / 4 + index % 4) % 2 == (faint ? 0 : 1) {
                    context.fill(CGRect(x: square.minX + CGFloat(index % 4) * side / 4, y: square.minY + CGFloat(index / 4) * side / 4, width: side / 4, height: side / 4))
                }
            }
            context.restoreGState()
            return
        }
        if let symbol {
            let fit = symbolFit
            let point = rect.height * 0.8 * fit
            guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: point, weight: symbolWeight(rect.height * fit))) else { return }
            let badge = self == .addImage && symbol == "photo"
            let size = badge ? CGSize(width: (image.size.width + point * 0.15).rounded(.up), height: (image.size.height + point * 0.16).rounded(.up)) : image.size
            let frame = CGRect(x: (rect.midX - size.width / 2).rounded(), y: (rect.midY - size.height / 2).rounded(), width: size.width, height: size.height)
            context.saveGState()
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance {
                image.draw(in: CGRect(origin: frame.origin, size: image.size), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                if badge {
                    let centre = CGPoint(x: frame.minX + point * 1.25, y: frame.minY + point * 0.86)
                    context.setBlendMode(.clear)
                    context.fillEllipse(in: CGRect(x: centre.x - point * 0.33, y: centre.y - point * 0.33, width: point * 0.66, height: point * 0.66))
                    context.setBlendMode(.normal)
                    guard let plus = NSImage(systemSymbolName: "plus.circle.fill", accessibilityDescription: nil)?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: point * 0.48, weight: symbolWeight(rect.height * 0.5))) else { return }
                    plus.draw(in: CGRect(x: centre.x - plus.size.width / 2, y: centre.y - plus.size.height / 2, width: plus.size.width, height: plus.size.height), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                }
            }
            context.setBlendMode(.sourceIn)
            context.setFillColor(color.cgColor)
            context.fill(frame)
            context.endTransparencyLayer()
            context.restoreGState()
            return
        }
        let shapes = paths
        let fit = rect.width / box.width
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.minY)
        context.scaleBy(x: fit, y: fit)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setStrokeColor(color.cgColor)
        context.setFillColor(color.cgColor)
        if let fill = shapes.fill {
            context.addPath(fill)
            context.fillPath(using: .evenOdd)
        }
        context.setLineWidth(1.8 / fit)
        context.addPath(shapes.stroke)
        context.strokePath()
        context.restoreGState()
    }

    static func drawSizeLine(_ width: CGFloat, in rect: CGRect, color: NSColor, on context: CGContext) {
        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(width)
        context.setLineCap(.round)
        context.move(to: CGPoint(x: rect.minX + rect.width * 0.2, y: rect.maxY - rect.height * 0.2))
        context.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.2, y: rect.minY + rect.height * 0.2))
        context.strokePath()
        context.restoreGState()
    }
}

class CursorScreenshotBarButton: NSControl {
    enum Part {
        case icon(CursorScreenshotEditorIcon, CGFloat)
        case title(String, NSFont)
        case swatch(NSColor)
        case sizeLine(CGFloat)
        case fillSwatch(NSColor?)
        case tick(Bool)
    }

    var parts: [Part] = [] { didSet { needsDisplay = true } }
    var spreads = false
    var sidePadding: CGFloat = 0
    var partGap = CursorScreenshotEditorMetrics.partGap
    var fill: NSColor? { didSet { needsDisplay = true } }
    var outline: NSColor?
    var hoverFill: NSColor?
    var tint = CursorScreenshotEditorPalette.foreground { didSet { needsDisplay = true } }
    var onPress: (() -> Void)?
    var isOn = false { didSet { if isOn != oldValue { needsDisplay = true } } }
    private(set) var isInside = false
    private(set) var isHeld = false
    private var tracker: NSTrackingArea?

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override var isEnabled: Bool { didSet { needsDisplay = true } }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    init(label: String, parts: [Part] = []) {
        self.parts = parts
        super.init(frame: .zero)
        toolTip = label
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(label)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracker { removeTrackingArea(tracker) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracker = area
    }

    override func mouseEntered(with event: NSEvent) {
        isInside = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isInside = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        isHeld = true
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isHeld else { return }
        isHeld = false
        needsDisplay = true
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onPress?() }
    }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        onPress?()
        return true
    }

    func releaseHold() {
        isHeld = false
        needsDisplay = true
    }

    private func width(of part: Part) -> CGFloat {
        switch part {
        case .icon(let icon, let size): return size * icon.box.width / icon.box.height
        case .title(let text, let font): return ceil(NSAttributedString(string: text, attributes: [.font: font]).size().width)
        case .swatch, .fillSwatch: return CursorScreenshotEditorMetrics.swatch
        case .sizeLine: return CursorScreenshotEditorMetrics.sizeLine
        case .tick: return CursorScreenshotEditorMetrics.tick
        }
    }

    var fittingWidth: CGFloat {
        parts.reduce(0) { $0 + width(of: $1) } + CGFloat(max(parts.count - 1, 0)) * partGap + CursorScreenshotEditorMetrics.titlePadding * 2
    }

    private var currentFill: NSColor? {
        if isOn { return .controlAccentColor }
        if isEnabled, isHeld || isInside, let hoverFill { return hoverFill }
        return fill
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.setAlpha(isEnabled ? 1 : 0.4)
        let radius = bounds.height / 2
        if let currentFill {
            currentFill.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        }
        if let outline {
            outline.setStroke()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius - 0.5, yRadius: radius - 0.5).stroke()
        }
        let color = isOn ? NSColor.white : tint
        let widths = parts.map(width(of:))
        let total = widths.reduce(0, +) + CGFloat(max(parts.count - 1, 0)) * partGap
        var x = spreads ? sidePadding : ((bounds.width - total) / 2).rounded()
        let room = bounds.width - sidePadding * 2 - widths.reduce(0, +)
        let gap = spreads && parts.count > 1 ? room / CGFloat(parts.count - 1) : partGap
        for (index, part) in parts.enumerated() {
            let high: CGFloat
            switch part {
            case .icon(let icon, let size):
                high = size
                let rect = CGRect(x: x, y: ((bounds.height - high) / 2).rounded(), width: widths[index], height: high)
                let small = icon == .chevron || icon == .grip
                icon.draw(in: rect, color: small && !isOn ? CursorScreenshotEditorPalette.muted : color, on: context)
            case .title(let text, let font):
                let line = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
                high = line.size().height
                line.draw(at: CGPoint(x: x, y: ((bounds.height - high) / 2).rounded()))
            case .swatch(let swatch):
                high = widths[index]
                CursorScreenshotCropLook.drawSwatch(swatch, in: CGRect(x: x, y: ((bounds.height - high) / 2).rounded(), width: high, height: high), on: context)
            case .sizeLine(let weight):
                high = widths[index]
                CursorScreenshotEditorIcon.drawSizeLine(weight, in: CGRect(x: x, y: ((bounds.height - high) / 2).rounded(), width: high, height: high), color: color, on: context)
            case .fillSwatch(let swatch):
                high = widths[index]
                let ring = CGRect(x: x, y: ((bounds.height - high) / 2).rounded(), width: high, height: high)
                CursorScreenshotCropLook.drawSwatch(swatch, in: ring, on: context)
            case .tick(let on):
                high = widths[index]
                let box = CGRect(x: x, y: ((bounds.height - high) / 2).rounded(), width: high, height: high)
                CursorScreenshotCropLook.drawTick(on, in: box, on: context)
            }
            x += widths[index] + gap
        }
        context.restoreGState()
    }
}

final class CursorScreenshotDragButton: CursorScreenshotBarButton, NSDraggingSource {
    var makeFile: (() -> URL?)?
    var thumbnail: (() -> NSImage?)?
    private var pressPoint: NSPoint?
    private(set) var isDragging = false

    static let startDistance: CGFloat = 4

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        pressPoint = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard let pressPoint, !isDragging, isEnabled else { return }
        guard hypot(event.locationInWindow.x - pressPoint.x, event.locationInWindow.y - pressPoint.y) >= Self.startDistance else { return }
        guard let file = makeFile?() else {
            self.pressPoint = nil
            releaseHold()
            return NSSound.beep()
        }
        isDragging = true
        let item = NSDraggingItem(pasteboardWriter: file as NSURL)
        let picture = thumbnail?() ?? NSImage(size: bounds.size)
        let high = min(bounds.height * 2, picture.size.height)
        let wide = picture.size.height > 0 ? high * picture.size.width / picture.size.height : bounds.width
        let start = convert(event.locationInWindow, from: nil)
        item.setDraggingFrame(CGRect(x: start.x - wide / 2, y: start.y - high / 2, width: wide, height: high), contents: picture)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        pressPoint = nil
        if isDragging {
            finishDrag()
        } else {
            super.mouseUp(with: event)
        }
    }

    func finishDrag() {
        isDragging = false
        pressPoint = nil
        releaseHold()
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        finishDrag()
    }
}

struct CursorScreenshotEditorActions {
    var saveAs: () -> Void = {}
    var done: () -> Void = {}
    var copy: () -> Void = {}
    var pin: () -> Void = {}
    var share: (NSView) -> Void = { _ in }
    var makeDragFile: () -> URL? = { nil }
    var openColors: (NSView) -> Void = { _ in }
    var turn: (CursorScreenshotCropTurn) -> Void = { _ in }
    var takeImage: () -> Void = {}
    var pasteImage: () -> Void = {}
    var chooseImage: () -> Void = {}
    var toggleBackground: () -> Void = {}
    var chooseWallpaper: () -> Void = {}
    var namePreset: (@escaping (String) -> Void) -> Void = { _ in }
    var confirmDeletePreset: (@escaping () -> Void) -> Void = { _ in }
}

final class CursorScreenshotMenuItem: NSMenuItem {
    private let run: () -> Void

    init(title: String, image: NSImage? = nil, key: String = "", run: @escaping () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(press), keyEquivalent: key)
        target = self
        self.image = image
        #if compiler(>=6.4)
        if image != nil, #available(macOS 27, *) { preferredImageVisibility = .visible }
        #endif
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func press() {
        run()
    }
}

@MainActor
enum CursorScreenshotEditorMenus {
    static func percent(_ zoom: CGFloat) -> String {
        String(format: MenuBarL("%lld%%"), Int64((zoom * 100).rounded()))
    }

    static func points(_ size: CGFloat) -> String {
        String(format: MenuBarL("%lld pt"), Int64(size.rounded()))
    }

    private static func lineSample(_ size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: 23, height: 30), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let width = CursorScreenshotEditorMetrics.sizeSampleWidth(size)
            CursorScreenshotEditorIcon.drawSizeLine(width, in: rect.insetBy(dx: 0, dy: 3), color: .black, on: context)
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func letterSample(_ size: CGFloat) -> NSImage {
        let line = NSAttributedString(string: "Aa", attributes: [.font: NSFont.systemFont(ofSize: min(max(size * 0.6, 9), 26)), .foregroundColor: NSColor.black])
        let measured = line.size()
        let image = NSImage(size: NSSize(width: ceil(measured.width), height: ceil(measured.height)), flipped: false) { _ in
            line.draw(at: .zero)
            return true
        }
        image.isTemplate = true
        return image
    }

    static func sampleThickness(_ value: CGFloat, kind: CursorScreenshotSizeKind?) -> CGFloat {
        guard kind == .number, let row = CursorScreenshotSizeKind.number.values.firstIndex(of: value) else { return value }
        return CursorScreenshotSizeKind.thickness.values[row]
    }

    static func size(for model: CursorScreenshotEditorModel) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let kind = model.propertyTool.sizeKind
        for value in model.sizeValues {
            let usesLine = kind != .text
            let item = CursorScreenshotMenuItem(title: usesLine ? "" : points(value), image: usesLine ? lineSample(sampleThickness(value, kind: kind)) : letterSample(value)) { [weak model] in model?.setSize(value) }
            item.setAccessibilityLabel(points(value))
            menu.addItem(item)
        }
        return menu
    }

    static func zoom(for model: CursorScreenshotEditorModel) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(CursorScreenshotMenuItem(title: MenuBarL("Zoom In"), key: "+") { [weak model] in model?.stepZoom(up: true) })
        menu.addItem(CursorScreenshotMenuItem(title: MenuBarL("Zoom Out"), key: "-") { [weak model] in model?.stepZoom(up: false) })
        menu.addItem(.separator())
        menu.addItem(CursorScreenshotMenuItem(title: MenuBarL("Fit Canvas"), key: "1") { [weak model] in model?.zoomToFit() })
        menu.addItem(.separator())
        for stop in CursorScreenshotZoom.menuStops {
            menu.addItem(CursorScreenshotMenuItem(title: percent(stop), key: stop == 1 ? "0" : "") { [weak model] in model?.setZoom(stop) })
        }
        return menu
    }
}

final class CursorScreenshotToolCapsule: NSView {
    private let model: CursorScreenshotEditorModel
    private(set) var toolButtons: [(tool: CursorScreenshotTool, button: CursorScreenshotBarButton)] = []
    let undo = CursorScreenshotBarButton(label: MenuBarL("Undo"), parts: [.icon(.undo, CursorScreenshotEditorMetrics.toolIcon)])
    let redo = CursorScreenshotBarButton(label: MenuBarL("Redo"), parts: [.icon(.redo, CursorScreenshotEditorMetrics.toolIcon)])

    private static let icons: [CursorScreenshotTool: CursorScreenshotEditorIcon] = [
        .select: .select, .box: .box, .filledBox: .filledBox, .oval: .oval, .line: .line, .arrow: .arrow, .pen: .pen, .text: .text,
        .pixelate: .pixelate, .spotlight: .spotlight, .highlight: .highlight, .number: .number
    ]

    private static func label(_ tool: CursorScreenshotTool) -> String {
        switch tool {
        case .select: return MenuBarL("Select")
        case .box: return MenuBarL("Box")
        case .filledBox: return MenuBarL("Filled Box")
        case .oval: return MenuBarL("Oval")
        case .line: return MenuBarL("Line")
        case .arrow: return MenuBarL("Arrow")
        case .pen: return MenuBarL("Pen")
        case .text: return MenuBarL("Text")
        case .pixelate: return MenuBarL("Pixelate")
        case .spotlight: return MenuBarL("Spotlight")
        case .highlight: return MenuBarL("Highlight")
        case .number: return MenuBarL("Number")
        case .image: return MenuBarL("Add Image")
        }
    }

    init(model: CursorScreenshotEditorModel) {
        self.model = model
        super.init(frame: .zero)
        for tool in CursorScreenshotTool.allCases {
            let button = CursorScreenshotBarButton(label: Self.label(tool), parts: [.icon(Self.icons[tool] ?? .select, CursorScreenshotEditorMetrics.toolIcon)])
            button.hoverFill = CursorScreenshotEditorPalette.hover
            button.onPress = { [weak model] in model?.pick(tool) }
            toolButtons.append((tool, button))
            addSubview(button)
        }
        for (button, action) in [(undo, { [weak model] in model?.undo() }), (redo, { [weak model] in model?.redo() })] as [(CursorScreenshotBarButton, () -> Void)] {
            button.hoverFill = CursorScreenshotEditorPalette.hover
            button.onPress = action
            addSubview(button)
        }
        refresh()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    private var buttons: [CursorScreenshotBarButton] { toolButtons.map(\.button) + [undo, redo] }

    func refresh() {
        for (tool, button) in toolButtons { button.isOn = model.tool == tool }
        undo.isEnabled = model.canUndo
        redo.isEnabled = model.canRedo
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let look = CursorScreenshotEditorMetrics.self
        let count = CGFloat(buttons.count)
        let wide = ((bounds.width - 2 - 12) / count).rounded(.down)
        var x: CGFloat = 1
        for (index, button) in buttons.enumerated() {
            button.frame = CGRect(x: x, y: ((bounds.height - look.toolHeight) / 2).rounded(), width: wide, height: look.toolHeight)
            x += wide + (index < 12 ? 1 : 0)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.height / 2
        CursorScreenshotEditorPalette.capsule.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        let look = CursorScreenshotEditorMetrics.self
        CursorScreenshotEditorPalette.edge.setFill()
        let order = toolButtons.map(\.tool)
        for index in 0..<12 {
            let picked = model.tool == order[index] || (index + 1 < order.count && model.tool == order[index + 1])
            if picked { continue }
            let right = buttons[index].frame.maxX
            CGRect(x: right, y: ((bounds.height - look.dividerHeight) / 2).rounded(), width: 1, height: look.dividerHeight).fill()
        }
    }
}

final class CursorScreenshotEditorTopBar: NSView {
    private let model: CursorScreenshotEditorModel
    private let actions: CursorScreenshotEditorActions
    let crop = CursorScreenshotBarButton(label: MenuBarL("Crop"), parts: [.icon(.crop, CursorScreenshotEditorMetrics.roundIcon)])
    let addImage = CursorScreenshotBarButton(label: MenuBarL("Add Image"), parts: [.icon(.addImage, CursorScreenshotEditorMetrics.roundIcon)])
    let background = CursorScreenshotBarButton(label: MenuBarL("Background"), parts: [.icon(.background, CursorScreenshotEditorMetrics.roundIcon)])
    let capsule: CursorScreenshotToolCapsule
    let color = CursorScreenshotBarButton(label: MenuBarL("Color"))
    let size = CursorScreenshotBarButton(label: MenuBarL("Size"))
    let arrowStyle = CursorScreenshotBarButton(label: MenuBarL("Arrow Style"))
    let textStyle = CursorScreenshotBarButton(label: MenuBarL("Text Style"))
    let shape = CursorScreenshotBarButton(label: MenuBarL("Spotlight Shape"))
    let redaction = CursorScreenshotBarButton(label: MenuBarL("Pixelate Style"))
    let numberSettings = CursorScreenshotBarButton(label: MenuBarL("Number Settings"))
    let lock = CursorScreenshotBarButton(label: MenuBarL("Unlock Canvas"))
    let dimSlider = CursorScreenshotEditorSlider(label: MenuBarL("Spotlight Opacity"), range: CursorScreenshotEditorLook.dimRange, value: CursorScreenshotEditorLook.firstDim, first: CursorScreenshotEditorLook.firstDim)
    let strengthSlider = CursorScreenshotEditorSlider(label: MenuBarL("Pixelate Strength"), range: CursorScreenshotEditorLook.strengthRange, value: CursorScreenshotEditorLook.blockPoints, first: CursorScreenshotEditorLook.blockPoints)
    let saveAs = CursorScreenshotBarButton(label: MenuBarL("Save as…"))
    let done = CursorScreenshotBarButton(label: MenuBarL("Done Editing"))
    let cropBar: CursorScreenshotCropTopBar
    private let normal = CursorScreenshotBarGroup()

    init(model: CursorScreenshotEditorModel, actions: CursorScreenshotEditorActions) {
        self.model = model
        self.actions = actions
        capsule = CursorScreenshotToolCapsule(model: model)
        cropBar = CursorScreenshotCropTopBar(model: model, actions: actions)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.init(1), for: .horizontal)
        widthAnchor.constraint(greaterThanOrEqualToConstant: CursorScreenshotEditorMetrics.smallestBarWidth).isActive = true
        heightAnchor.constraint(equalToConstant: CursorScreenshotEditorMetrics.topBarItemHeight).isActive = true
        addSubview(normal)
        addSubview(cropBar)
        crop.fill = CursorScreenshotEditorPalette.button
        addSubview(crop)
        for button in [addImage, background, color, size, arrowStyle, textStyle, shape, redaction, numberSettings, lock, saveAs] {
            button.fill = CursorScreenshotEditorPalette.button
            normal.addSubview(button)
        }
        normal.addSubview(dimSlider)
        normal.addSubview(strengthSlider)
        dimSlider.onSlide = { [weak model] in model?.setDim($0) }
        strengthSlider.onSlide = { [weak model] in model?.setStrength($0) }
        for slider in [dimSlider, strengthSlider] { slider.onHold = { [weak model] in model?.holdChange($0) } }
        for (button, menu) in [(arrowStyle, CursorScreenshotEditorChoiceMenus.arrow), (textStyle, CursorScreenshotEditorChoiceMenus.textStyle), (shape, CursorScreenshotEditorChoiceMenus.shape),
                               (redaction, CursorScreenshotEditorChoiceMenus.redaction), (numberSettings, CursorScreenshotEditorChoiceMenus.numberSettings)] as [(CursorScreenshotBarButton, (CursorScreenshotEditorModel) -> NSMenu)] {
            button.onPress = { [weak self, weak button] in
                guard let self, let button else { return }
                let opened = menu(self.model)
                opened.popUp(positioning: opened.items.first, at: NSPoint(x: 0, y: button.bounds.height), in: button)
            }
        }
        lock.onPress = { [weak model] in
            guard let model else { return }
            model.setCanvasLocked(!model.choices.canvasLocked)
        }
        done.fill = .controlAccentColor
        done.tint = .white
        normal.addSubview(done)
        normal.addSubview(capsule)
        addImage.onPress = { [weak self] in
            guard let self else { return }
            let menu = CursorScreenshotEditorMenus.addImage(actions: self.actions)
            menu.popUp(positioning: menu.items.first, at: NSPoint(x: 0, y: self.addImage.bounds.height + CursorScreenshotDropLook.menuGap), in: self.addImage)
        }
        background.onPress = actions.toggleBackground
        crop.onPress = { [weak model] in
            guard let model else { return }
            if model.isCropping { model.applyCrop() } else { model.openCrop() }
        }
        saveAs.parts = [.title(MenuBarL("Save as…"), CursorScreenshotEditorMetrics.textFont)]
        saveAs.onPress = actions.saveAs
        done.parts = [.title(MenuBarL("Done Editing"), CursorScreenshotEditorMetrics.doneFont)]
        done.onPress = actions.done
        color.onPress = { [weak self] in
            guard let self else { return }
            self.actions.openColors(self.color)
        }
        size.onPress = { [weak self] in
            guard let self else { return }
            let menu = CursorScreenshotEditorMenus.size(for: self.model)
            menu.popUp(positioning: menu.items.first, at: NSPoint(x: 0, y: self.size.bounds.height), in: self.size)
        }
        refresh()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: CursorScreenshotEditorMetrics.topBarItemHeight) }

    func refresh() {
        let look = CursorScreenshotEditorMetrics.self
        crop.isOn = model.isCropping
        background.isOn = model.isBackgroundOpen
        normal.isHidden = model.isCropping
        cropBar.isHidden = !model.isCropping
        cropBar.refresh()
        capsule.refresh()
        let tool = model.propertyTool
        color.isHidden = !tool.hasColor
        let chevron = CursorScreenshotBarButton.Part.icon(.chevron, look.chevron)
        color.parts = [.swatch(NSColor(cgColor: model.shownColor.cgColor) ?? .red), chevron]
        size.isHidden = tool.sizeKind == nil
        if let value = model.size {
            let kind = tool.sizeKind
            size.parts = kind == .text ? [.title(CursorScreenshotEditorMenus.points(value), look.dragFont), chevron]
                                       : [.sizeLine(look.sizeSampleWidth(CursorScreenshotEditorMenus.sampleThickness(value, kind: kind))), chevron]
        }
        arrowStyle.isHidden = tool != .arrow
        arrowStyle.parts = [.icon(CursorScreenshotEditorChoiceMenus.arrowIcon(model.shownArrowStyle), look.toolIcon), chevron]
        textStyle.isHidden = tool != .text
        textStyle.parts = [.title("A", NSFontManager.shared.convert(NSFont(name: "Times New Roman Bold", size: look.textStyleLetter) ?? look.textFont, toHaveTrait: .italicFontMask)), chevron]
        shape.isHidden = tool != .spotlight
        shape.parts = [.icon(CursorScreenshotEditorChoiceMenus.shapeIcon(model.shownSpotlightShape), look.toolIcon), chevron]
        redaction.isHidden = tool != .pixelate
        redaction.parts = [.icon(CursorScreenshotEditorChoiceMenus.redactionIcon(model.shared.redaction), look.toolIcon), chevron]
        numberSettings.isHidden = tool != .number
        numberSettings.parts = [.title("123", look.dragFont), chevron]
        lock.isHidden = tool != .pen && tool != .highlight
        lock.parts = [.icon(model.choices.canvasLocked ? .locked : .unlocked, look.actionIcon)]
        let lockWord = model.choices.canvasLocked ? MenuBarL("Unlock Canvas") : MenuBarL("Lock Canvas")
        lock.toolTip = lockWord
        lock.setAccessibilityLabel(lockWord)
        dimSlider.isHidden = tool != .spotlight
        dimSlider.value = model.shared.dim
        strengthSlider.isHidden = tool != .pixelate || model.shared.redaction == .blackOut
        strengthSlider.value = model.shared.strength
        needsLayout = true
    }

    var wordRoom: CGFloat {
        let look = CursorScreenshotEditorMetrics.self
        let normalRoom = max(saveAs.fittingWidth - look.saveWidth, 0) + max(done.fittingWidth - look.doneWidth, 0)
        let cropRoom = look.roundButtonWidth + CursorScreenshotCropLook.barGap + cropBar.leastWidth - look.barWidthInSmallestWindow
        return max(normalRoom, cropRoom)
    }

    override func layout() {
        super.layout()
        let look = CursorScreenshotEditorMetrics.self
        let middle = bounds.height / 2
        let place = { (view: NSView, x: CGFloat, width: CGFloat, height: CGFloat) in
            view.frame = CGRect(x: x, y: (middle - height / 2).rounded(), width: width, height: height)
        }
        normal.frame = bounds
        let cropBarX = look.roundButtonWidth + CursorScreenshotCropLook.barGap
        cropBar.frame = CGRect(x: cropBarX, y: 0, width: bounds.width - cropBarX, height: bounds.height)
        var x: CGFloat = 0
        for button in [crop, addImage, background] {
            place(button, x, look.roundButtonWidth, look.controlHeight)
            x += look.roundButtonWidth + look.groupGap
        }
        x += look.sectionGap - look.groupGap
        let doneWidth = max(look.doneWidth, done.fittingWidth)
        let saveWidth = max(look.saveWidth, saveAs.fittingWidth)
        let doneX = bounds.width - look.topBarSide - doneWidth
        let saveX = doneX - look.saveDoneGap - saveWidth
        place(done, doneX, doneWidth, look.controlHeight)
        place(saveAs, saveX, saveWidth, look.controlHeight)
        let sizeWidth = max(look.propertyWidth, model.propertyTool == .text ? size.fittingWidth - look.titlePadding : 0)
        let buttons: [(CursorScreenshotBarButton, CGFloat)] = [(color, look.propertyWidth), (size, sizeWidth), (arrowStyle, look.propertyWidth), (textStyle, look.propertyWidth), (shape, look.propertyWidth),
                                                               (redaction, look.propertyWidth), (numberSettings, max(look.propertyWidth, numberSettings.fittingWidth - look.titlePadding)), (lock, look.propertyWidth)]
        let shown = buttons.filter { !$0.0.isHidden }
        let slider = [dimSlider, strengthSlider].first { !$0.isHidden }
        let reservedButtons = shown.reduce(0) { $0 + $1.1 + look.groupGap }
        let reserved = look.sectionGap * 2 + reservedButtons + (slider == nil ? 0 : look.smallestSliderWidth)
        let toolWidth = min(look.toolWidth, max(look.smallestToolWidth, ((saveX - x - reserved - 14) / 14).rounded(.down)))
        let capsuleWidth = toolWidth * 14 + 14
        place(capsule, x, capsuleWidth, look.capsuleHeight)
        x += capsuleWidth + look.sectionGap
        var propertyX = x
        for (button, width) in shown {
            place(button, propertyX, width, look.controlHeight)
            propertyX += width + look.groupGap
        }
        if let slider {
            let room = saveX - look.sectionGap - propertyX
            place(slider, propertyX, min(look.sliderWidth, max(room, look.smallestSliderWidth)), look.controlHeight)
        }
    }
}

final class CursorScreenshotEditorBottomBar: NSView {
    private let model: CursorScreenshotEditorModel
    let zoom = CursorScreenshotBarButton(label: MenuBarL("Zoom"))
    let drag = CursorScreenshotDragButton(label: MenuBarL("Drag Me"))
    let share = CursorScreenshotBarButton(label: MenuBarL("Share"), parts: [.icon(.share, CursorScreenshotEditorMetrics.actionIcon)])
    let pin = CursorScreenshotBarButton(label: MenuBarL("Pin"), parts: [.icon(.pin, CursorScreenshotEditorMetrics.actionIcon)])
    let copy = CursorScreenshotBarButton(label: MenuBarL("Copy"), parts: [.icon(.copy, CursorScreenshotEditorMetrics.actionIcon)])
    let cropParts: CursorScreenshotCropBottomParts

    init(model: CursorScreenshotEditorModel, actions: CursorScreenshotEditorActions) {
        self.model = model
        cropParts = CursorScreenshotCropBottomParts(model: model)
        super.init(frame: .zero)
        let look = CursorScreenshotEditorMetrics.self
        for button in [zoom, share, pin, copy] {
            button.fill = CursorScreenshotEditorPalette.button
            addSubview(button)
        }
        addSubview(cropParts)
        addSubview(drag)
        zoom.spreads = true
        zoom.sidePadding = 8
        drag.outline = CursorScreenshotEditorPalette.edge
        drag.spreads = true
        drag.sidePadding = 13
        drag.partGap = 8
        drag.parts = [.icon(.grip, look.grip), .title(MenuBarL("Drag Me"), look.dragFont), .icon(.grip, look.grip)]
        drag.onPress = actions.done
        drag.makeFile = actions.makeDragFile
        share.onPress = { [weak self] in
            guard let self else { return }
            actions.share(self.share)
        }
        pin.onPress = actions.pin
        copy.onPress = actions.copy
        zoom.onPress = { [weak self] in
            guard let self else { return }
            let menu = CursorScreenshotEditorMenus.zoom(for: self.model)
            menu.popUp(positioning: menu.items.last, at: NSPoint(x: 0, y: self.zoom.bounds.height), in: self.zoom)
        }
        refresh()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override func mouseDown(with event: NSEvent) {
        model.deselect()
        super.mouseDown(with: event)
    }

    func refresh() {
        let look = CursorScreenshotEditorMetrics.self
        zoom.outline = model.isCropping ? CursorScreenshotEditorPalette.separator : nil
        zoom.parts = [.title(CursorScreenshotEditorMenus.percent(model.zoom), look.zoomFont), .icon(.chevron, look.chevron)]
        zoom.setAccessibilityValue(CursorScreenshotEditorMenus.percent(model.zoom))
        for button in [drag, share, pin, copy] { button.isHidden = model.isCropping }
        cropParts.isHidden = !model.isCropping
        cropParts.refresh()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let look = CursorScreenshotEditorMetrics.self
        let middle = bounds.height / 2
        let place = { (view: NSView, x: CGFloat, width: CGFloat, height: CGFloat) in
            view.frame = CGRect(x: x, y: (middle - height / 2).rounded(), width: width, height: height)
        }
        place(zoom, look.bottomLeft, max(look.zoomWidth, zoom.fittingWidth), look.controlHeight)
        let partsX = zoom.frame.maxX + CursorScreenshotCropLook.bottomGap
        cropParts.frame = CGRect(x: partsX, y: 0, width: bounds.width - partsX - look.bottomRight, height: bounds.height)
        let dragWidth = max(look.dragWidth, drag.fittingWidth)
        place(drag, ((bounds.width - dragWidth) / 2).rounded(), dragWidth, look.dragHeight)
        var x = bounds.width - look.bottomRight - look.roundButtonWidth
        for button in [copy, pin, share] {
            place(button, x, look.roundButtonWidth, look.controlHeight)
            x -= look.roundButtonWidth + look.groupGap
        }
    }
}

final class CursorScreenshotEditorToolbar: NSObject, NSToolbarDelegate {
    private let bar: NSView
    private static let item = NSToolbarItem.Identifier("CursorScreenshotEditorBar")

    init(bar: NSView) {
        self.bar = bar
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.view = bar
        item.isBordered = false
        return item
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [Self.item] }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [Self.item] }
}
