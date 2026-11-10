import AppKit

private enum CursorScreenshotColorMetrics {
    static let closedSize = NSSize(width: 52, height: 400)
    static let openSize = NSSize(width: 316, height: 400)
    static let corner: CGFloat = 20
    static let swatch: CGFloat = 24
    static let pitch: CGFloat = 34
    static let firstCenterY: CGFloat = 26
    static let paletteX: CGFloat = 26
    static let myColorsX: CGFloat = 60
    static let footY: CGFloat = 374
    static let ringGap: CGFloat = 3
    static let sideX: CGFloat = 86
    static let sideInset: CGFloat = 10
    static let sideWidth: CGFloat = 220
    static let spectrumHeight: CGFloat = 158
    static let controlX: CGFloat = 106
    static let sliderWidth: CGFloat = 144
    static let sliderHeight: CGFloat = 10
    static let hueY: CGFloat = 188
    static let alphaY: CGFloat = 206
    static let previewX: CGFloat = 258
    static let previewSize: CGFloat = 28
    static let hexY: CGFloat = 229
    static let fieldHeight: CGFloat = 22
    static let captionGap: CGFloat = 4
    static let numbersY: CGFloat = 275
    static let numberWidth: CGFloat = 38
    static let numberPitch: CGFloat = 46
    static let alphaX: CGFloat = 248
    static let hairlineY: CGFloat = 325
    static let addY: CGFloat = 341
    static let addWidth: CGFloat = 180
    static let addHeight: CGFloat = 33
    static let pipetteX: CGFloat = 264
    static let knob: CGFloat = 14
    static let checker: CGFloat = 4
    static let reopenGuard: TimeInterval = 0.3
}

final class CursorScreenshotSwatch: CursorScreenshotBarButton {
    var color: CursorScreenshotColor? { didSet { needsDisplay = true } }
    var isCurrent = false { didSet { needsDisplay = true } }
    var isWheel = false

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let look = CursorScreenshotColorMetrics.self
        if isInside {
            CursorScreenshotEditorPalette.hover.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
        }
        let side = look.swatch
        let spot = CGRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2, width: side, height: side)
        if isWheel {
            return CursorScreenshotSwatchWheel.draw(in: spot, on: context)
        }
        guard let color else {
            let empty = NSBezierPath(ovalIn: spot.insetBy(dx: 0.5, dy: 0.5))
            empty.setLineDash([2, 2], count: 2, phase: 0)
            CursorScreenshotEditorPalette.edge.setStroke()
            empty.stroke()
            return
        }
        context.setFillColor(color.cgColor)
        context.fillEllipse(in: spot)
        if color.isNearWhite {
            CursorScreenshotEditorPalette.separator.setStroke()
            NSBezierPath(ovalIn: spot.insetBy(dx: 0.5, dy: 0.5)).stroke()
        } else if color.isNearBlack {
            CursorScreenshotEditorPalette.edge.setStroke()
            NSBezierPath(ovalIn: spot.insetBy(dx: 0.5, dy: 0.5)).stroke()
        }
        if isCurrent {
            var ring = color
            ring.alpha = 0.35
            context.setStrokeColor(color.isNearBlack ? CursorScreenshotEditorPalette.edge.cgColor : ring.cgColor)
            context.setLineWidth(look.ringGap)
            context.strokeEllipse(in: spot.insetBy(dx: -look.ringGap, dy: -look.ringGap))
        }
    }
}

final class CursorScreenshotColorField: NSView {
    enum Mode { case spectrum, hue, alpha }

    let mode: Mode
    var hue: CGFloat = 0 { didSet { needsDisplay = true } }
    var saturation: CGFloat = 1 { didSet { needsDisplay = true } }
    var brightness: CGFloat = 1 { didSet { needsDisplay = true } }
    var alpha: CGFloat = 1 { didSet { needsDisplay = true } }
    var onPick: (() -> Void)?
    var onHold: ((Bool) -> Void)?

    init(mode: Mode, label: String) {
        self.mode = mode
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.slider)
        setAccessibilityLabel(label)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    private var knobCenter: CGPoint {
        switch mode {
        case .spectrum: return CGPoint(x: saturation * bounds.width, y: (1 - brightness) * bounds.height)
        case .hue: return CGPoint(x: hue * bounds.width, y: bounds.midY)
        case .alpha: return CGPoint(x: alpha * bounds.width, y: bounds.midY)
        }
    }

    private func pick(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let across = min(max(point.x / max(bounds.width, 1), 0), 1)
        let down = min(max(point.y / max(bounds.height, 1), 0), 1)
        switch mode {
        case .spectrum:
            saturation = across
            brightness = 1 - down
        case .hue: hue = across
        case .alpha: alpha = across
        }
        onPick?()
    }

    override func mouseDown(with event: NSEvent) {
        onHold?(true)
        pick(event)
    }

    override func mouseDragged(with event: NSEvent) { pick(event) }
    override func mouseUp(with event: NSEvent) { onHold?(false) }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let look = CursorScreenshotColorMetrics.self
        let pure = NSColor(cgColor: CursorScreenshotColor(hue: hue, saturation: 1, brightness: 1).cgColor) ?? .red
        let shown = NSColor(cgColor: CursorScreenshotColor(hue: hue, saturation: saturation, brightness: brightness).cgColor) ?? .red
        switch mode {
        case .spectrum:
            pure.setFill()
            bounds.fill()
            NSGradient(starting: .white, ending: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0))?.draw(in: bounds, angle: 0)
            NSGradient(starting: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0), ending: .black)?.draw(in: bounds, angle: 90)
        case .hue:
            let shape = NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2)
            let stops = (0...6).map { NSColor(cgColor: CursorScreenshotColor(hue: CGFloat($0) / 6, saturation: 1, brightness: 1).cgColor) ?? .red }
            NSGradient(colors: stops)?.draw(in: shape, angle: 0)
        case .alpha:
            context.saveGState()
            NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).addClip()
            NSColor.white.setFill()
            bounds.fill()
            NSColor(white: 0.8, alpha: 1).setFill()
            for row in 0..<Int(ceil(bounds.height / look.checker)) {
                for column in 0..<Int(ceil(bounds.width / look.checker)) where (row + column) % 2 == 0 {
                    CGRect(x: CGFloat(column) * look.checker, y: CGFloat(row) * look.checker, width: look.checker, height: look.checker).fill()
                }
            }
            NSGradient(starting: shown.withAlphaComponent(0), ending: shown)?.draw(in: bounds, angle: 0)
            context.restoreGState()
        }
        let center = knobCenter
        let knob = CGRect(x: center.x - look.knob / 2, y: center.y - look.knob / 2, width: look.knob, height: look.knob)
        NSColor.white.setFill()
        NSBezierPath(ovalIn: knob).fill()
        (mode == .hue ? pure : shown).setFill()
        NSBezierPath(ovalIn: knob.insetBy(dx: 2, dy: 2)).fill()
    }
}

final class CursorScreenshotColorFieldCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        var line = super.drawingRect(forBounds: rect)
        let spare = line.height - cellSize(forBounds: rect).height
        if spare > 0 {
            line.origin.y += (spare / 2).rounded()
            line.size.height -= spare
        }
        return line
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(withFrame: drawingRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: drawingRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate, event: event)
    }
}

final class CursorScreenshotColorTextField: NSTextField {
    override class var cellClass: AnyClass? {
        get { CursorScreenshotColorFieldCell.self }
        set {}
    }

    override func draw(_ dirtyRect: NSRect) {
        CursorScreenshotEditorPalette.separator.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5).fill()
        super.draw(dirtyRect)
    }
}

final class CursorScreenshotColorView: NSView, NSTextFieldDelegate {
    private let model: CursorScreenshotEditorModel
    private(set) var palette: [CursorScreenshotSwatch] = []
    private(set) var slots: [CursorScreenshotSwatch] = []
    let wheel = CursorScreenshotSwatch(label: MenuBarL("More Colors"))
    let back = CursorScreenshotBarButton(label: MenuBarL("Fewer Colors"), parts: [.icon(.back, 14)])
    let spectrum = CursorScreenshotColorField(mode: .spectrum, label: MenuBarL("Color"))
    let hueBar = CursorScreenshotColorField(mode: .hue, label: MenuBarL("Hue"))
    let alphaBar = CursorScreenshotColorField(mode: .alpha, label: MenuBarL("Alpha"))
    let hexField = CursorScreenshotColorTextField(string: "")
    let redField = CursorScreenshotColorTextField(string: "")
    let greenField = CursorScreenshotColorTextField(string: "")
    let blueField = CursorScreenshotColorTextField(string: "")
    let alphaField = CursorScreenshotColorTextField(string: "")
    let pipette = CursorScreenshotBarButton(label: MenuBarL("Pick a Color"), parts: [.icon(.pipette, 20)])
    let add = CursorScreenshotBarButton(label: MenuBarL("Add to My Colors"))
    var onResize: ((Bool) -> Void)?
    var onSample: (() -> Void)?
    private var sideViews: [NSView] = []

    private static func name(_ index: Int) -> String {
        switch index {
        case 0: return MenuBarL("Black")
        case 1: return MenuBarL("Red")
        case 2: return MenuBarL("Orange")
        case 3: return MenuBarL("Yellow")
        case 4: return MenuBarL("Green")
        case 5: return MenuBarL("Teal")
        case 6: return MenuBarL("Blue")
        case 7: return MenuBarL("Purple")
        case 8: return MenuBarL("Pink")
        default: return MenuBarL("White")
        }
    }

    init(model: CursorScreenshotEditorModel) {
        self.model = model
        super.init(frame: NSRect(origin: .zero, size: model.choices.pickerOpen ? CursorScreenshotColorMetrics.openSize : CursorScreenshotColorMetrics.closedSize))
        let look = CursorScreenshotColorMetrics.self
        for (index, color) in CursorScreenshotColor.palette.enumerated() {
            let swatch = CursorScreenshotSwatch(label: Self.name(index))
            swatch.color = color
            swatch.onPress = { [weak self] in self?.choose(color) }
            swatch.frame = spotFrame(x: look.paletteX, index: index)
            palette.append(swatch)
            addSubview(swatch)
        }
        for index in 0..<CursorScreenshotEditorLook.myColorSlots {
            let slot = CursorScreenshotSwatch(label: MenuBarL("My Colors"))
            slot.onPress = { [weak self] in
                guard let self, self.model.choices.myColors.indices.contains(index) else { return }
                self.choose(self.model.choices.myColors[index])
            }
            slot.frame = spotFrame(x: look.myColorsX, index: index)
            slots.append(slot)
            addSubview(slot)
        }
        wheel.isWheel = true
        wheel.frame = CGRect(x: look.paletteX - look.swatch / 2, y: look.footY - look.swatch / 2, width: look.swatch, height: look.swatch)
        wheel.onPress = { [weak self] in self?.setOpen(true) }
        addSubview(wheel)
        back.frame = CGRect(x: look.myColorsX - look.swatch / 2, y: look.footY - look.swatch / 2, width: look.swatch, height: look.swatch)
        back.outline = CursorScreenshotEditorPalette.separator
        back.onPress = { [weak self] in self?.setOpen(false) }
        addSubview(back)
        spectrum.frame = CGRect(x: look.sideX, y: look.sideInset, width: look.sideWidth, height: look.spectrumHeight)
        hueBar.frame = CGRect(x: look.controlX, y: look.hueY, width: look.sliderWidth, height: look.sliderHeight)
        alphaBar.frame = CGRect(x: look.controlX, y: look.alphaY, width: look.sliderWidth, height: look.sliderHeight)
        for field in [spectrum, hueBar, alphaBar] {
            field.onPick = { [weak self] in self?.pickedFromFields() }
            field.onHold = { [weak self] in self?.model.holdChange($0) }
            addSubview(field)
            sideViews.append(field)
        }
        hexField.frame = CGRect(x: look.controlX, y: look.hexY, width: look.sliderWidth, height: look.fieldHeight)
        let numbers: [(NSTextField, CGFloat, String)] = [
            (redField, look.controlX, MenuBarL("R")),
            (greenField, look.controlX + look.numberPitch, MenuBarL("G")),
            (blueField, look.controlX + look.numberPitch * 2, MenuBarL("B")),
            (alphaField, look.alphaX, MenuBarL("Alpha"))
        ]
        for (field, x, caption) in numbers {
            field.frame = CGRect(x: x, y: look.numbersY, width: look.numberWidth, height: look.fieldHeight)
            install(field, caption: caption)
        }
        install(hexField, caption: MenuBarL("Hex"))
        pipette.frame = CGRect(x: look.pipetteX, y: look.hexY - 3, width: look.previewSize, height: look.previewSize)
        pipette.hoverFill = CursorScreenshotEditorPalette.hover
        pipette.onPress = { [weak self] in self?.onSample?() }
        addSubview(pipette)
        sideViews.append(pipette)
        add.frame = CGRect(x: look.controlX, y: look.addY, width: look.addWidth, height: look.addHeight)
        add.fill = .controlAccentColor
        add.tint = .white
        add.parts = [.icon(.plus, 16), .title(MenuBarL("Add to My Colors"), CursorScreenshotBackgroundLook.fittedFont(MenuBarL("Add to My Colors"), font: .systemFont(ofSize: NSFont.systemFontSize, weight: .medium), width: look.addWidth - 16 - add.partGap, padding: 4))]
        add.onPress = { [weak self] in
            guard let self else { return }
            self.model.addToMyColors(self.model.shownColor)
            self.refresh()
        }
        addSubview(add)
        sideViews.append(add)
        sideViews += slots + [back]
        refresh()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    private func spotFrame(x: CGFloat, index: Int) -> CGRect {
        let look = CursorScreenshotColorMetrics.self
        let side = look.swatch + look.ringGap * 3
        return CGRect(x: x - side / 2, y: look.firstCenterY + CGFloat(index) * look.pitch - side / 2, width: side, height: side)
    }

    private func install(_ field: NSTextField, caption: String) {
        let look = CursorScreenshotColorMetrics.self
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.alignment = .center
        field.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        field.textColor = CursorScreenshotEditorPalette.foreground
        field.delegate = self
        field.setAccessibilityLabel(caption)
        field.cell?.usesSingleLineMode = true
        addSubview(field)
        sideViews.append(field)
        let label = NSTextField(labelWithString: caption)
        label.font = CursorScreenshotBackgroundLook.fittedFont(caption, font: .systemFont(ofSize: NSFont.labelFontSize), width: field.frame.width, padding: 1.5)
        label.textColor = CursorScreenshotEditorPalette.muted
        label.alignment = .center
        label.frame = CGRect(x: field.frame.minX, y: field.frame.maxY + look.captionGap, width: field.frame.width, height: 14)
        addSubview(label)
        sideViews.append(label)
    }

    private func choose(_ color: CursorScreenshotColor) {
        model.setColor(color)
        loadFields(from: color)
        refresh()
    }

    private func setOpen(_ open: Bool) {
        model.setPickerOpen(open)
        setFrameSize(open ? CursorScreenshotColorMetrics.openSize : CursorScreenshotColorMetrics.closedSize)
        refresh()
        onResize?(open)
    }

    private func loadFields(from color: CursorScreenshotColor) {
        let parts = color.hsb
        if parts.saturation > 0, parts.brightness > 0 { hueBar.hue = parts.hue }
        if parts.brightness > 0 { spectrum.saturation = parts.saturation }
        spectrum.brightness = parts.brightness
        alphaBar.alpha = color.alpha
        syncFields()
    }

    private func syncFields() {
        spectrum.hue = hueBar.hue
        hueBar.saturation = 1
        hueBar.brightness = 1
        alphaBar.hue = hueBar.hue
        alphaBar.saturation = spectrum.saturation
        alphaBar.brightness = spectrum.brightness
    }

    private func pickedFromFields() {
        syncFields()
        model.setColor(CursorScreenshotColor(hue: hueBar.hue, saturation: spectrum.saturation, brightness: spectrum.brightness, alpha: alphaBar.alpha))
        refresh()
    }

    func refresh() {
        let current = model.shownColor
        if current != CursorScreenshotColor(hue: hueBar.hue, saturation: spectrum.saturation, brightness: spectrum.brightness, alpha: alphaBar.alpha) { loadFields(from: current) }
        for swatch in palette { swatch.isCurrent = swatch.color?.sameShade(as: current) == true }
        for (index, slot) in slots.enumerated() {
            slot.color = model.choices.myColors.indices.contains(index) ? model.choices.myColors[index] : nil
            slot.isCurrent = slot.color?.sameShade(as: current) == true
        }
        let open = model.choices.pickerOpen
        for view in sideViews { view.isHidden = !open }
        for (field, text) in [(hexField, current.hex), (redField, String(Int((current.red * 255).rounded()))), (greenField, String(Int((current.green * 255).rounded()))),
                              (blueField, String(Int((current.blue * 255).rounded()))), (alphaField, String(Int((current.alpha * 100).rounded())))] where field.currentEditor() == nil {
            field.stringValue = text
        }
        needsDisplay = true
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        var color = model.shownColor
        let text = field.stringValue
        if field === hexField {
            color = CursorScreenshotColor(hex: text, alpha: color.alpha) ?? color
        } else if let number = Int(text.trimmingCharacters(in: .whitespaces)) {
            let part = CGFloat(min(max(number, 0), 255)) / 255
            switch field {
            case redField: color.red = part
            case greenField: color.green = part
            case blueField: color.blue = part
            default: color.alpha = CGFloat(min(max(number, 0), 100)) / 100
            }
        }
        choose(color)
    }

    override func draw(_ dirtyRect: NSRect) {
        let look = CursorScreenshotColorMetrics.self
        CursorScreenshotEditorPalette.panel.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: look.corner, yRadius: look.corner).fill()
        CursorScreenshotEditorPalette.panelEdge.setStroke()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: look.corner - 0.5, yRadius: look.corner - 0.5).stroke()
        guard model.choices.pickerOpen else {
            CursorScreenshotEditorPalette.separator.setFill()
            CGRect(x: look.paletteX - 6, y: look.footY - 22, width: 12, height: 1).fill()
            return
        }
        CursorScreenshotEditorPalette.panelSide.setFill()
        CGRect(x: look.sideX, y: look.sideInset, width: look.sideWidth, height: bounds.height - look.sideInset * 2).fill()
        NSColor(cgColor: model.shownColor.cgColor)?.setFill()
        NSBezierPath(ovalIn: CGRect(x: look.previewX, y: look.hueY, width: look.previewSize, height: look.previewSize)).fill()
        CursorScreenshotEditorPalette.separator.setFill()
        CGRect(x: look.controlX, y: look.hairlineY, width: look.addWidth, height: 1).fill()
    }
}

final class CursorScreenshotColorPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        close()
    }
}

@MainActor
final class CursorScreenshotColorPopup: NSObject, NSWindowDelegate {
    private let model: CursorScreenshotEditorModel
    private var panel: CursorScreenshotColorPanel?
    private var closedAt = Date.distantPast
    private var isSampling = false
    private var sampler: NSColorSampler?

    init(model: CursorScreenshotEditorModel) {
        self.model = model
    }

    func toggle(under anchor: NSView) {
        guard panel == nil, Date().timeIntervalSince(closedAt) > CursorScreenshotColorMetrics.reopenGuard, let parent = anchor.window else { return }
        let view = CursorScreenshotColorView(model: model)
        let spot = parent.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let top = spot.minY - 4
        let left = spot.midX - CursorScreenshotColorMetrics.closedSize.width / 2
        let placed = { (frame: NSRect) in parent.screen.map { CursorScreenshotColorPlace.kept(frame, inside: $0.visibleFrame) } ?? frame }
        let made = CursorScreenshotColorPanel(contentRect: placed(NSRect(x: left, y: top - view.frame.height, width: view.frame.width, height: view.frame.height)),
                                              styleMask: [.borderless], backing: .buffered, defer: false)
        made.isOpaque = false
        made.backgroundColor = .clear
        made.hasShadow = true
        made.isReleasedWhenClosed = false
        made.hidesOnDeactivate = false
        made.delegate = self
        made.contentView = view
        view.onResize = { [weak made] _ in
            guard let made else { return }
            let size = view.frame.size
            made.setFrame(placed(NSRect(x: made.frame.minX, y: made.frame.maxY - size.height, width: size.width, height: size.height)), display: true)
            made.invalidateShadow()
        }
        view.onSample = { [weak self] in self?.sample(into: view) }
        parent.addChildWindow(made, ordered: .above)
        made.makeKeyAndOrderFront(nil)
        panel = made
    }

    func close() {
        panel?.close()
    }

    private func sample(into view: CursorScreenshotColorView) {
        isSampling = true
        let sampler = NSColorSampler()
        self.sampler = sampler
        sampler.show { [weak self, weak view] picked in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isSampling = false
                self.sampler = nil
                if let picked = picked?.usingColorSpace(.sRGB) {
                    var color = self.model.shownColor
                    color.red = picked.redComponent
                    color.green = picked.greenComponent
                    color.blue = picked.blueComponent
                    self.model.setColor(color)
                    view?.refresh()
                }
            }
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        if !isSampling { panel?.close() }
    }

    func windowWillClose(_ notification: Notification) {
        closedAt = Date()
        if let panel { panel.parent?.removeChildWindow(panel) }
        panel = nil
    }
}
