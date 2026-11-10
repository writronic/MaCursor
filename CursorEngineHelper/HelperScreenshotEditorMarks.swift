import AppKit

enum CursorScreenshotSelectionLook {
    static let bandWidth: CGFloat = 3
    static let bandAlpha: CGFloat = 0.5
    static let discSize: CGFloat = 15
    static let discRing: CGFloat = 2
    static let squareSize: CGFloat = 9
    static let squareRing: CGFloat = 1.5
    static let guideWidth: CGFloat = 1
    static let emojiSize: CGFloat = 28
    static let emojiGap: CGFloat = 10
    static let squareDrop: CGFloat = 6
}

extension CursorScreenshotEditorCanvas {
    func viewPoint(_ point: CGPoint) -> CGPoint {
        viewRect(CGRect(origin: point, size: .zero)).origin
    }

    func drawGuidesAndSelection(on context: CGContext) {
        let look = CursorScreenshotSelectionLook.self
        let frame = placement
        NSColor.controlAccentColor.setFill()
        for x in model.guides.across {
            CGRect(x: viewPoint(CGPoint(x: x, y: 0)).x - look.guideWidth / 2, y: frame.minY, width: look.guideWidth, height: frame.height).fill()
        }
        for y in model.guides.down {
            CGRect(x: frame.minX, y: viewPoint(CGPoint(x: 0, y: y)).y - look.guideWidth / 2, width: frame.width, height: look.guideWidth).fill()
        }
        guard let mark = model.typing ?? model.selectedMark else { return }
        let scale = model.picture.scale
        var toView = CGAffineTransform(translationX: frame.minX, y: frame.minY).scaledBy(x: model.viewScale, y: model.viewScale).translatedBy(x: -model.shownArea.minX, y: -model.shownArea.minY)
        if let band = CursorScreenshotRender.outline(mark, scale: scale).copy(using: &toView) {
            let wide = band.copy(strokingWithWidth: look.bandWidth, lineCap: .round, lineJoin: .round, miterLimit: 10)
            context.saveGState()
            context.setFillColor(NSColor.controlAccentColor.withAlphaComponent(look.bandAlpha).cgColor)
            context.addPath(wide)
            context.fillPath()
            context.restoreGState()
        }
        for (handle, point) in CursorScreenshotRender.handles(of: mark, scale: scale) {
            let spot = viewPoint(point)
            if handle == .textWidth {
                let middle = CGPoint(x: spot.x, y: spot.y + look.squareDrop)
                NSColor.white.setFill()
                NSBezierPath(rect: CGRect(x: middle.x - look.squareSize / 2, y: middle.y - look.squareSize / 2, width: look.squareSize, height: look.squareSize)).fill()
                NSColor.controlAccentColor.setFill()
                let inner = look.squareSize - look.squareRing * 2
                NSBezierPath(rect: CGRect(x: middle.x - inner / 2, y: middle.y - inner / 2, width: inner, height: inner)).fill()
            } else {
                NSColor.white.setFill()
                NSBezierPath(ovalIn: CGRect(x: spot.x - look.discSize / 2, y: spot.y - look.discSize / 2, width: look.discSize, height: look.discSize)).fill()
                NSColor.controlAccentColor.setFill()
                let inner = look.discSize - look.discRing * 2
                NSBezierPath(ovalIn: CGRect(x: spot.x - inner / 2, y: spot.y - inner / 2, width: inner, height: inner)).fill()
            }
        }
    }

    func addMarkCursorRects() {
        guard !model.isCropping, !model.isCanvasLockedTool, model.draft == nil else { return }
        let scale = model.picture.scale
        let frame = placement
        for mark in model.marks where model.tool == .select || mark.tool != .image || mark == model.selectedMark {
            if CursorScreenshotRender.isHitAcrossBox(mark.tool) {
                addOpenHand(viewRect(CursorScreenshotRender.bounds(of: mark, scale: scale)), in: frame)
            } else {
                addOpenHandAlongStroke(of: mark, in: frame)
            }
        }
        guard let mark = model.selectedMark else { return }
        let side = CursorScreenshotEditorLook.handleReachPoints
        for (_, point) in CursorScreenshotRender.handles(of: mark, scale: scale) {
            let spot = viewPoint(point)
            addCursorRect(CGRect(x: spot.x - side, y: spot.y - side, width: side * 2, height: side * 2), cursor: .crosshair)
        }
    }

    private func addOpenHand(_ rect: CGRect, in frame: CGRect) {
        let shown = rect.intersection(frame)
        if !shown.isEmpty { addCursorRect(shown, cursor: .openHand) }
    }

    private func addOpenHandAlongStroke(of mark: CursorScreenshotMark, in frame: CGRect) {
        let look = CursorScreenshotEditorLook.self
        let scale = model.picture.scale
        let zoom = model.viewScale
        let area = model.shownArea
        let reach = mark == model.selectedMark ? look.selectedReachPoints : look.markReachPoints
        let side = (mark.size * scale * zoom / 2 + reach) / 2.squareRoot()
        let step = side / zoom / 2
        let outline = CursorScreenshotRender.outline(mark, scale: scale)
        var spots = [outline.currentPoint]
        outline.copy(dashingWithPhase: 0, lengths: [step, step]).applyWithBlock { element in
            if element.pointee.type == .moveToPoint { spots.append(element.pointee.points[0]) }
        }
        for spot in spots {
            let at = CGPoint(x: frame.minX + (spot.x - area.minX) * zoom, y: frame.minY + (spot.y - area.minY) * zoom)
            addOpenHand(CGRect(x: at.x - side, y: at.y - side, width: side * 2, height: side * 2), in: frame)
        }
    }
}

final class CursorScreenshotEditorSlider: NSControl {
    var range: ClosedRange<CGFloat>
    var value: CGFloat { didSet { if value != oldValue { needsDisplay = true } } }
    var first: CGFloat?
    var onSlide: ((CGFloat) -> Void)?
    var onHold: ((Bool) -> Void)?

    private static let knob: CGFloat = 14
    private static let track: CGFloat = 4
    private static let dot: CGFloat = 3
    private static let keyStep: CGFloat = 1

    init(label: String, range: ClosedRange<CGFloat>, value: CGFloat, first: CGFloat?) {
        self.range = range
        self.value = value
        self.first = first
        super.init(frame: .zero)
        toolTip = label
        setAccessibilityElement(true)
        setAccessibilityRole(.slider)
        setAccessibilityLabel(label)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func accessibilityValue() -> Any? { Int(value.rounded()) }

    override func accessibilityPerformIncrement() -> Bool {
        slide(to: value + Self.keyStep)
        return true
    }

    override func accessibilityPerformDecrement() -> Bool {
        slide(to: value - Self.keyStep)
        return true
    }

    private func share(of value: CGFloat) -> CGFloat {
        (value - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    private func spot(of value: CGFloat) -> CGFloat {
        Self.knob / 2 + (bounds.width - Self.knob) * share(of: value)
    }

    private func slide(to wanted: CGFloat) {
        let clamped = min(max(wanted, range.lowerBound), range.upperBound)
        value = clamped
        onSlide?(clamped)
    }

    private func follow(_ event: NSEvent) {
        let x = convert(event.locationInWindow, from: nil).x
        let room = max(bounds.width - Self.knob, 1)
        slide(to: range.lowerBound + (x - Self.knob / 2) / room * (range.upperBound - range.lowerBound))
    }

    override func mouseDown(with event: NSEvent) {
        onHold?(true)
        follow(event)
    }

    override func mouseDragged(with event: NSEvent) {
        follow(event)
    }

    override func mouseUp(with event: NSEvent) {
        onHold?(false)
    }

    override func draw(_ dirtyRect: NSRect) {
        let middle = (bounds.height / 2).rounded()
        let line = CGRect(x: Self.knob / 2, y: middle - Self.track / 2, width: bounds.width - Self.knob, height: Self.track)
        CursorScreenshotEditorPalette.capsule.setFill()
        NSBezierPath(roundedRect: line, xRadius: Self.track / 2, yRadius: Self.track / 2).fill()
        let at = spot(of: value)
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: CGRect(x: line.minX, y: line.minY, width: max(at - line.minX, 0), height: Self.track), xRadius: Self.track / 2, yRadius: Self.track / 2).fill()
        if let first {
            CursorScreenshotEditorPalette.muted.setFill()
            NSBezierPath(ovalIn: CGRect(x: spot(of: first) - Self.dot / 2, y: middle + Self.knob / 2 + 1, width: Self.dot, height: Self.dot)).fill()
        }
        let knob = CGRect(x: at - Self.knob / 2, y: middle - Self.knob / 2, width: Self.knob, height: Self.knob)
        CursorScreenshotEditorPalette.edge.setStroke()
        NSColor.white.setFill()
        NSBezierPath(ovalIn: knob).fill()
        NSBezierPath(ovalIn: knob.insetBy(dx: 0.5, dy: 0.5)).stroke()
    }
}

final class CursorScreenshotStartingNumberRow: NSView, NSTextFieldDelegate {
    private let model: CursorScreenshotEditorModel
    let field = NSTextField(string: "")
    let stepper = NSStepper()

    private static let size = NSSize(width: 230, height: 28)

    init(model: CursorScreenshotEditorModel) {
        self.model = model
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        let label = NSTextField(labelWithString: MenuBarL("Starting Number:"))
        field.alignment = .center
        field.delegate = self
        field.integerValue = model.choices.startingNumber
        field.setAccessibilityLabel(MenuBarL("Starting Number:"))
        stepper.minValue = 1
        stepper.maxValue = Double(CursorScreenshotEditorLook.largestStartingNumber)
        stepper.integerValue = model.choices.startingNumber
        stepper.target = self
        stepper.action = #selector(stepped)
        stepper.setAccessibilityLabel(MenuBarL("Starting Number:"))
        let row = NSStackView(views: [label, field, stepper])
        row.orientation = .horizontal
        row.spacing = 6
        row.edgeInsets = NSEdgeInsets(top: 2, left: 14, bottom: 2, right: 10)
        row.frame = bounds
        row.autoresizingMask = [.width, .height]
        field.widthAnchor.constraint(equalToConstant: 44).isActive = true
        addSubview(row)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func stepped() {
        field.integerValue = stepper.integerValue
        model.setStartingNumber(stepper.integerValue)
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let typed = CursorScreenshotEditorChoices.startingNumber(typed: field.stringValue) else { return }
        model.setStartingNumber(typed)
        let kept = model.choices.startingNumber
        stepper.integerValue = kept
        if kept != typed { field.integerValue = kept }
    }
}

@MainActor
enum CursorScreenshotEditorChoiceMenus {
    static func arrowWord(_ style: CursorScreenshotArrowStyle) -> String {
        switch style {
        case .standard: return MenuBarL("Standard")
        case .fancy: return MenuBarL("Fancy")
        case .curved: return MenuBarL("Curved")
        case .double: return MenuBarL("Double")
        }
    }

    static func arrowIcon(_ style: CursorScreenshotArrowStyle) -> CursorScreenshotEditorIcon {
        switch style {
        case .standard: return .arrowStandard
        case .fancy: return .arrowFancy
        case .curved: return .arrowCurved
        case .double: return .arrowDouble
        }
    }

    static func shapeWord(_ shape: CursorScreenshotSpotlightShape) -> String {
        switch shape {
        case .rectangle: return MenuBarL("Rectangle")
        case .rounded: return MenuBarL("Rounded Rectangle")
        case .oval: return MenuBarL("Oval")
        }
    }

    static func shapeIcon(_ shape: CursorScreenshotSpotlightShape) -> CursorScreenshotEditorIcon {
        switch shape {
        case .rectangle: return .shapeRectangle
        case .rounded: return .shapeRounded
        case .oval: return .shapeOval
        }
    }

    static func redactionWord(_ style: CursorScreenshotRedactionStyle) -> String {
        switch style {
        case .pixelate: return MenuBarL("Pixelate")
        case .secureBlur: return MenuBarL("Secure Blur")
        case .blur: return MenuBarL("Blur")
        case .blackOut: return MenuBarL("Black Out")
        }
    }

    static func redactionIcon(_ style: CursorScreenshotRedactionStyle) -> CursorScreenshotEditorIcon {
        switch style {
        case .pixelate: return .pixelate
        case .secureBlur: return .dropLocked
        case .blur: return .drop
        case .blackOut: return .moon
        }
    }

    static func textWord(_ style: CursorScreenshotTextStyle) -> String {
        switch style {
        case .standard: return MenuBarL("Standard")
        case .rounded: return MenuBarL("Rounded")
        case .outlined: return MenuBarL("Outlined")
        case .mono: return MenuBarL("Mono")
        case .box: return MenuBarL("Box")
        case .monoBox: return MenuBarL("Mono Box")
        case .roundedBox: return MenuBarL("Rounded Box")
        }
    }

    private static func iconImage(_ icon: CursorScreenshotEditorIcon) -> NSImage {
        let side = CursorScreenshotEditorMetrics.toolIcon
        let image = NSImage(size: NSSize(width: side, height: side), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            icon.draw(in: rect, color: .black, on: context)
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func textSample(_ style: CursorScreenshotTextStyle, current: Bool) -> NSImage {
        let word = MenuBarL("Text")
        let font = style.font(ofSize: NSFont.systemFontSize)
        let ink: NSColor = current ? .labelColor : .secondaryLabelColor
        let measured = NSAttributedString(string: word, attributes: [.font: font]).size()
        let size = NSSize(width: ceil(measured.width) + 12, height: 20)
        return NSImage(size: size, flipped: false) { rect in
            let at = CGPoint(x: (rect.width - measured.width) / 2, y: (rect.height - measured.height) / 2)
            if style.hasBox {
                ink.setFill()
                let radius = style == .monoBox ? 0 : style == .box ? 4 : rect.height / 2
                NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
                NSAttributedString(string: word, attributes: [.font: font, .foregroundColor: NSColor.windowBackgroundColor]).draw(at: at)
            } else if style == .outlined {
                NSAttributedString(string: word, attributes: [.font: font, .strokeColor: ink, .strokeWidth: 6]).draw(at: at)
            } else {
                NSAttributedString(string: word, attributes: [.font: font, .foregroundColor: ink]).draw(at: at)
            }
            return true
        }
    }

    static func arrow(for model: CursorScreenshotEditorModel) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for style in CursorScreenshotArrowStyle.allCases {
            menu.addItem(CursorScreenshotMenuItem(title: arrowWord(style), image: iconImage(arrowIcon(style))) { [weak model] in model?.setArrowStyle(style) })
        }
        return menu
    }

    static func shape(for model: CursorScreenshotEditorModel) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for shape in CursorScreenshotSpotlightShape.allCases {
            let item = CursorScreenshotMenuItem(title: "", image: iconImage(shapeIcon(shape))) { [weak model] in model?.setSpotlightShape(shape) }
            item.setAccessibilityLabel(shapeWord(shape))
            menu.addItem(item)
        }
        return menu
    }

    static func redaction(for model: CursorScreenshotEditorModel) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for style in CursorScreenshotRedactionStyle.allCases {
            menu.addItem(CursorScreenshotMenuItem(title: redactionWord(style), image: iconImage(redactionIcon(style))) { [weak model] in model?.setRedaction(style) })
        }
        return menu
    }

    static func textStyle(for model: CursorScreenshotEditorModel) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for style in CursorScreenshotTextStyle.allCases {
            let sample = textSample(style, current: style == model.shownTextStyle)
            menu.addItem(CursorScreenshotMenuItem(title: textWord(style), image: sample) { [weak model] in model?.setTextStyle(style) })
        }
        return menu
    }

    static func numberSettings(for model: CursorScreenshotEditorModel) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let rows: [(CursorScreenshotNumberStyle, String)] = [(.digits, "1, 2, 3, 4 …"), (.upper, "A, B, C, D …"), (.roman, "I, II, III, IV …"), (.lower, "a, b, c, d …")]
        for (style, title) in rows {
            let item = CursorScreenshotMenuItem(title: title) { [weak model] in model?.setNumberStyle(style) }
            item.state = style == model.shownNumberStyle ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let starting = NSMenuItem()
        starting.view = CursorScreenshotStartingNumberRow(model: model)
        menu.addItem(starting)
        menu.addItem(.separator())
        let sizes = NSMenu()
        sizes.autoenablesItems = false
        for value in CursorScreenshotSizeKind.number.values {
            let item = CursorScreenshotMenuItem(title: CursorScreenshotEditorMenus.points(value)) { [weak model] in model?.setSize(value) }
            item.state = value == model.size ? .on : .off
            sizes.addItem(item)
        }
        let holder = NSMenuItem(title: MenuBarL("Size:"), action: nil, keyEquivalent: "")
        holder.submenu = sizes
        menu.addItem(holder)
        return menu
    }
}
