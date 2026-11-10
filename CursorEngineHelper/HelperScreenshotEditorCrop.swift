import AppKit

enum CursorScreenshotCropLook {
    static let canvas = NSColor(srgbRed: 0x6F / 255, green: 0x6F / 255, blue: 0x6F / 255, alpha: 1)
    static let shade = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.75)
    static let gridLine = NSColor(srgbRed: 0xD9 / 255, green: 0xD9 / 255, blue: 0xD9 / 255, alpha: 1)
    static let handleEdge = NSColor(srgbRed: 0x1A / 255, green: 0x1A / 255, blue: 0x1A / 255, alpha: 0.3)
    static let checkerDark = NSColor(srgbRed: 0xCC / 255, green: 0xCC / 255, blue: 0xCC / 255, alpha: 1)
    static let handleEdgeWidth: CGFloat = 8
    static let handleWidth: CGFloat = 4
    static let handleArm: CGFloat = 14
    static let smallHandleArm: CGFloat = 6
    static let smallBoxSide: CGFloat = 70
    static let tinyBoxSide: CGFloat = 20
    static let barGap: CGFloat = 10
    static let bottomGap: CGFloat = 20
    static let ratioWidth: CGFloat = 115
    static let ratioPadding: CGFloat = 10
    static let boxWidth: CGFloat = 50
    static let boxHeight: CGFloat = 22
    static let boxRadius: CGFloat = 4
    static let swapSide: CGFloat = 20
    static let boxGap: CGFloat = 5
    static let sectionGap: CGFloat = 13
    static let fillGap: CGFloat = 18
    static let fillWidth: CGFloat = 40
    static let groupGap: CGFloat = 20
    static let ruleHeight: CGFloat = 16
    static let labelGap: CGFloat = 11
    static let pillPadding: CGFloat = 9
    static let cancelWidth: CGFloat = 61
    static let applyWidth: CGFloat = 49
    static let endGap: CGFloat = 10
    static let leastGapShare: CGFloat = 0.3
    static let hintGap: CGFloat = 8
    static let tickGap: CGFloat = 6
    static let checkerSide: CGFloat = 4
    static let menuDot: CGFloat = 14
    static let trackpadZoomStep: CGFloat = 1.07
    static let wheelZoomStep: CGFloat = 1.2
    static let panelSize = NSSize(width: 350, height: 185)
    static let panelInset: CGFloat = 12
    @MainActor static let boxFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    @MainActor static let labelFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    @MainActor static let hintFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)

    static func drawCheckers(in rect: CGRect, on context: CGContext) {
        context.saveGState()
        context.clip(to: rect)
        context.setFillColor(NSColor.white.cgColor)
        context.fill(rect)
        context.setFillColor(checkerDark.cgColor)
        var row = 0
        var y = rect.minY
        while y < rect.maxY {
            var x = rect.minX + (row % 2 == 0 ? 0 : checkerSide)
            while x < rect.maxX {
                context.fill(CGRect(x: x, y: y, width: checkerSide, height: checkerSide))
                x += checkerSide * 2
            }
            y += checkerSide
            row += 1
        }
        context.restoreGState()
    }

    static func drawSwatch(_ color: NSColor?, in rect: CGRect, on context: CGContext) {
        context.saveGState()
        context.addEllipse(in: rect)
        context.clip()
        drawCheckersIfSeeThrough(color, in: rect, on: context)
        if let color {
            context.setFillColor(color.cgColor)
            context.fill(rect)
        }
        context.restoreGState()
        context.setStrokeColor(CursorScreenshotEditorPalette.edge.cgColor)
        context.setLineWidth(1)
        context.strokeEllipse(in: rect.insetBy(dx: 0.5, dy: 0.5))
    }

    private static func drawCheckersIfSeeThrough(_ color: NSColor?, in rect: CGRect, on context: CGContext) {
        if (color?.alphaComponent ?? 0) < 1 { drawCheckers(in: rect, on: context) }
    }

    static func drawTick(_ on: Bool, in rect: CGRect, on context: CGContext) {
        let shape = NSBezierPath(roundedRect: rect, xRadius: boxRadius, yRadius: boxRadius)
        if on {
            NSColor.controlAccentColor.setFill()
            shape.fill()
            CursorScreenshotEditorIcon.check.draw(in: rect, color: .white, on: context)
        } else {
            CursorScreenshotEditorPalette.button.setFill()
            shape.fill()
            CursorScreenshotEditorPalette.edge.setStroke()
            NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: boxRadius, yRadius: boxRadius).stroke()
        }
    }
}

final class CursorScreenshotBarGroup: NSView {
    override var isFlipped: Bool { true }
}

extension CursorScreenshotEditorCanvas {
    func drawCropBack(_ box: CGRect, in dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        CursorScreenshotCropLook.canvas.setFill()
        dirtyRect.fill()
        let fill = model.cropFill.resolved(for: model.picture)
        if (fill?.alpha ?? 0) < 1 { CursorScreenshotCropLook.drawCheckers(in: box, on: context) }
        if let fill {
            context.setFillColor(fill.cgColor)
            context.fill(box)
        }
    }

    func drawCropFrame(_ box: CGRect, over picture: CGRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let look = CursorScreenshotCropLook.self
        let shaded = NSBezierPath(rect: picture)
        let kept = picture.intersection(box)
        if !kept.isNull { shaded.append(NSBezierPath(rect: kept)) }
        shaded.windingRule = .evenOdd
        look.shade.setFill()
        shaded.fill()

        look.gridLine.setFill()
        for share in [CGFloat(1) / 3, CGFloat(2) / 3] {
            CGRect(x: (box.minX + box.width * share).rounded(), y: box.minY, width: 1, height: box.height).fill()
            CGRect(x: box.minX, y: (box.minY + box.height * share).rounded(), width: box.width, height: 1).fill()
        }
        NSColor.white.setStroke()
        let border = NSBezierPath(rect: box.insetBy(dx: -0.5, dy: -0.5))
        border.lineWidth = 1
        border.stroke()

        let shortest = min(box.width, box.height)
        let arm = shortest < look.tinyBoxSide ? 0 : shortest < look.smallBoxSide ? look.smallHandleArm : look.handleArm
        let path = CGMutablePath()
        for (x, y, across, down) in [(box.minX, box.minY, arm, arm), (box.maxX, box.minY, -arm, arm), (box.minX, box.maxY, arm, -arm), (box.maxX, box.maxY, -arm, -arm)] {
            path.addLines(between: [CGPoint(x: x + across, y: y), CGPoint(x: x, y: y), CGPoint(x: x, y: y + down)])
        }
        if shortest >= look.smallBoxSide {
            let half = look.handleArm / 2
            path.addLines(between: [CGPoint(x: box.midX - half, y: box.minY), CGPoint(x: box.midX + half, y: box.minY)])
            path.addLines(between: [CGPoint(x: box.midX - half, y: box.maxY), CGPoint(x: box.midX + half, y: box.maxY)])
            path.addLines(between: [CGPoint(x: box.minX, y: box.midY - half), CGPoint(x: box.minX, y: box.midY + half)])
            path.addLines(between: [CGPoint(x: box.maxX, y: box.midY - half), CGPoint(x: box.maxX, y: box.midY + half)])
        }
        context.saveGState()
        context.setLineCap(.round)
        context.setLineJoin(.round)
        for (color, width) in [(look.handleEdge, look.handleEdgeWidth), (NSColor.white, look.handleWidth)] {
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(width)
            context.addPath(path)
            context.strokePath()
        }
        context.restoreGState()
    }

    func addCropCursorRects(_ box: CGRect) {
        for grip in CursorScreenshotCropHandle.grips(of: box, unit: 1) {
            addCursorRect(grip.area, cursor: Self.cropCursor(grip.handle))
        }
    }

    private static func cropCursor(_ handle: CursorScreenshotCropHandle) -> NSCursor {
        if #available(macOS 15, *) {
            switch handle {
            case .topLeft: return .frameResize(position: .topLeft, directions: .all)
            case .top: return .frameResize(position: .top, directions: .all)
            case .topRight: return .frameResize(position: .topRight, directions: .all)
            case .right: return .frameResize(position: .right, directions: .all)
            case .bottomRight: return .frameResize(position: .bottomRight, directions: .all)
            case .bottom: return .frameResize(position: .bottom, directions: .all)
            case .bottomLeft: return .frameResize(position: .bottomLeft, directions: .all)
            case .left: return .frameResize(position: .left, directions: .all)
            case .whole: return .arrow
            }
        }
        switch handle {
        case .left, .right: return .resizeLeftRight
        case .top, .bottom: return .resizeUpDown
        case .whole: return .arrow
        default: return .crosshair
        }
    }
}

@MainActor
enum CursorScreenshotCropMenus {
    static func title(_ item: CursorScreenshotCropRatioItem) -> String {
        switch item {
        case .custom: return MenuBarL("Custom Ratio")
        case .freeform: return MenuBarL("Freeform")
        case .original: return MenuBarL("Original Ratio")
        case .square: return MenuBarL("1 : 1 (Square)")
        case .fiveFour: return "5 : 4 (10 : 8)"
        case .sevenFive: return "7 : 5"
        case .fourThree: return "4 : 3"
        case .threeTwo: return "3 : 2 (6 : 4)"
        case .sixteenNine: return "16 : 9"
        }
    }

    static func ratio(for model: CursorScreenshotEditorModel, pickCustom: @escaping () -> Void) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let current = model.cropRatio.item(for: model.picture.size)
        let add = { (item: CursorScreenshotCropRatioItem, run: @escaping () -> Void) in
            let row = CursorScreenshotMenuItem(title: title(item), run: run)
            row.state = item == current ? .on : .off
            menu.addItem(row)
        }
        add(.custom, pickCustom)
        add(.freeform) { [weak model] in model?.pickRatio(.freeform) }
        menu.addItem(.separator())
        for item in [CursorScreenshotCropRatioItem.original] + CursorScreenshotCropRatioItem.named {
            add(item) { [weak model] in model?.pickRatio(item) }
        }
        return menu
    }

    private static func dot(_ color: NSColor?) -> NSImage {
        let side = CursorScreenshotCropLook.menuDot
        return NSImage(size: NSSize(width: side, height: side), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            CursorScreenshotCropLook.drawSwatch(color, in: rect, on: context)
            return true
        }
    }

    private static func wheel() -> NSImage {
        let side = CursorScreenshotCropLook.menuDot
        return NSImage(size: NSSize(width: side, height: side), flipped: true) { rect in
            let middle = CGPoint(x: rect.midX, y: rect.midY)
            let wedges = 12
            for wedge in 0..<wedges {
                let path = NSBezierPath()
                path.move(to: middle)
                let start = CGFloat(wedge) / CGFloat(wedges) * 360
                path.appendArc(withCenter: middle, radius: rect.width / 2, startAngle: start, endAngle: start + 360 / CGFloat(wedges) + 1)
                path.close()
                NSColor(calibratedHue: CGFloat(wedge) / CGFloat(wedges), saturation: 0.8, brightness: 1, alpha: 1).setFill()
                path.fill()
            }
            return true
        }
    }

    private static func color(_ fill: CursorScreenshotCropFill, on model: CursorScreenshotEditorModel) -> NSColor? {
        fill.resolved(for: model.picture).flatMap { NSColor(cgColor: $0.cgColor) }
    }

    static func fill(for model: CursorScreenshotEditorModel, pickCustom: @escaping () -> Void) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let add = { (title: String, fill: CursorScreenshotCropFill) in
            let row = CursorScreenshotMenuItem(title: title, image: dot(color(fill, on: model))) { [weak model] in model?.setCropFill(fill) }
            row.state = model.cropFill == fill ? .on : .off
            menu.addItem(row)
        }
        add(MenuBarL("Transparent"), .transparent)
        menu.addItem(.separator())
        if model.picture.autoFill != nil {
            add(MenuBarL("Auto"), .auto)
            menu.addItem(.separator())
        }
        add(MenuBarL("White"), .white)
        add(MenuBarL("Gray"), .gray)
        add(MenuBarL("Black"), .black)
        menu.addItem(.separator())
        let custom = CursorScreenshotMenuItem(title: MenuBarL("Custom Color…"), image: wheel(), run: pickCustom)
        if case .color = model.cropFill, ![.white, .gray, .black].contains(model.cropFill) { custom.state = .on }
        menu.addItem(custom)
        return menu
    }
}

final class CursorScreenshotCropWell: NSView {
    let field = NSTextField()

    init(label: String) {
        super.init(frame: .zero)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.alignment = .center
        field.usesSingleLineMode = true
        field.lineBreakMode = .byClipping
        field.cell?.isScrollable = true
        field.setAccessibilityLabel(label)
        addSubview(field)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func layout() {
        super.layout()
        field.font = CursorScreenshotCropLook.boxFont
        let high = ceil(field.intrinsicContentSize.height)
        field.frame = CGRect(x: 0, y: ((bounds.height - high) / 2).rounded(), width: bounds.width, height: high)
    }

    override func draw(_ dirtyRect: NSRect) {
        CursorScreenshotEditorPalette.well.setFill()
        let radius = CursorScreenshotCropLook.boxRadius
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
    }
}

final class CursorScreenshotCropRule: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        CursorScreenshotEditorPalette.rule.setFill()
        bounds.fill(using: .sourceOver)
    }
}

final class CursorScreenshotCropTopBar: NSView, NSTextFieldDelegate {
    private let model: CursorScreenshotEditorModel
    let ratio = CursorScreenshotBarButton(label: MenuBarL("Ratio"))
    let widthBox = CursorScreenshotCropWell(label: MenuBarL("Ratio Width"))
    let swap = CursorScreenshotBarButton(label: MenuBarL("Swap Width and Height"), parts: [.icon(.swap, CursorScreenshotEditorMetrics.toolIcon)])
    let heightBox = CursorScreenshotCropWell(label: MenuBarL("Ratio Height"))
    let fill = CursorScreenshotBarButton(label: MenuBarL("Fill Color"))
    private let firstRule = CursorScreenshotCropRule()
    let rotate = CursorScreenshotBarButton(label: MenuBarL("Rotate"), parts: [.icon(.rotate, CursorScreenshotEditorMetrics.actionIcon)])
    let flip = CursorScreenshotBarButton(label: MenuBarL("Flip"), parts: [.icon(.flip, CursorScreenshotEditorMetrics.actionIcon)])
    private let secondRule = CursorScreenshotCropRule()
    private let sizeLabel = NSTextField(labelWithString: MenuBarL("Image size:"))
    let sizeButton = CursorScreenshotBarButton(label: MenuBarL("Image size:"))
    let cancel = CursorScreenshotBarButton(label: MenuBarL("Cancel"))
    let apply = CursorScreenshotBarButton(label: MenuBarL("Crop"))

    init(model: CursorScreenshotEditorModel, actions: CursorScreenshotEditorActions) {
        self.model = model
        super.init(frame: .zero)
        let look = CursorScreenshotEditorMetrics.self
        for button in [ratio, fill, rotate, flip, sizeButton, cancel] {
            button.fill = CursorScreenshotEditorPalette.button
            button.outline = CursorScreenshotEditorPalette.separator
        }
        swap.hoverFill = CursorScreenshotEditorPalette.hover
        apply.fill = .controlAccentColor
        apply.tint = .white
        apply.parts = [.title(MenuBarL("Crop"), look.doneFont)]
        cancel.parts = [.title(MenuBarL("Cancel"), look.textFont)]
        ratio.spreads = true
        ratio.sidePadding = CursorScreenshotCropLook.ratioPadding
        ratio.partGap = 6
        sizeButton.spreads = true
        sizeButton.sidePadding = CursorScreenshotCropLook.pillPadding
        sizeLabel.font = CursorScreenshotCropLook.labelFont
        sizeLabel.textColor = CursorScreenshotEditorPalette.sub
        for view in [ratio, widthBox, swap, heightBox, fill, firstRule, rotate, flip, secondRule, sizeLabel, sizeButton, cancel, apply] as [NSView] {
            addSubview(view)
        }
        widthBox.field.delegate = self
        heightBox.field.delegate = self
        widthBox.field.nextKeyView = heightBox.field
        heightBox.field.nextKeyView = widthBox.field
        ratio.onPress = { [weak self] in
            guard let self else { return }
            let menu = CursorScreenshotCropMenus.ratio(for: self.model) { [weak self] in self?.window?.makeFirstResponder(self?.widthBox.field) }
            menu.popUp(positioning: menu.items.first { $0.state == .on }, at: NSPoint(x: 0, y: self.ratio.bounds.height), in: self.ratio)
        }
        swap.onPress = { [weak model] in model?.swapRatio() }
        fill.onPress = { [weak self] in
            guard let self else { return }
            let menu = CursorScreenshotCropMenus.fill(for: self.model) { [weak self] in self?.openColorPanel() }
            menu.popUp(positioning: menu.items.first { $0.state == .on }, at: NSPoint(x: 0, y: self.fill.bounds.height), in: self.fill)
        }
        rotate.onPress = { actions.turn(.rotate) }
        flip.onPress = { actions.turn(.flip) }
        sizeButton.onPress = { [weak self] in self?.openSizePanel() }
        cancel.onPress = { [weak model] in model?.cancelCrop() }
        apply.onPress = { [weak model] in model?.applyCrop() }
        refresh()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { true }

    func refresh() {
        guard model.isCropping else {
            if widthBox.field.currentEditor() != nil || heightBox.field.currentEditor() != nil { window?.makeFirstResponder(nil) }
            return closeColorPanel()
        }
        let look = CursorScreenshotEditorMetrics.self
        let chevron = CursorScreenshotBarButton.Part.icon(.chevron, look.chevron)
        ratio.parts = [.title(CursorScreenshotCropMenus.title(model.cropRatio.item(for: model.picture.size)), look.textFont), chevron]
        let shown = { (value: Int?) in value.map(String.init) ?? "" }
        if widthBox.field.stringValue != shown(model.cropRatio.width) { widthBox.field.stringValue = shown(model.cropRatio.width) }
        if heightBox.field.stringValue != shown(model.cropRatio.height) { heightBox.field.stringValue = shown(model.cropRatio.height) }
        fill.parts = [.fillSwatch(model.cropFill.resolved(for: model.picture).flatMap { NSColor(cgColor: $0.cgColor) }), chevron]
        CursorScreenshotSystemColors.follow(model.cropFill.resolved(for: model.picture), for: self, action: #selector(colorPicked(_:)))
        sizeButton.parts = [.title(sizeTitle(model.cropOutputSize), look.textFont), chevron]
        needsLayout = true
    }

    private var rows: [(view: NSView, width: CGFloat, height: CGFloat, gap: CGFloat)] {
        let look = CursorScreenshotCropLook.self
        let bar = CursorScreenshotEditorMetrics.self
        let high = bar.controlHeight
        return [
            (ratio, max(look.ratioWidth, ratio.fittingWidth), high, look.sectionGap),
            (widthBox, look.boxWidth, look.boxHeight, look.boxGap),
            (swap, look.swapSide, look.swapSide, look.boxGap),
            (heightBox, look.boxWidth, look.boxHeight, look.fillGap),
            (fill, look.fillWidth, high, look.groupGap),
            (firstRule, 1, look.ruleHeight, look.groupGap),
            (rotate, bar.roundButtonWidth, high, look.barGap),
            (flip, bar.roundButtonWidth, high, look.groupGap),
            (secondRule, 1, look.ruleHeight, look.groupGap),
            (sizeLabel, ceil(sizeLabel.intrinsicContentSize.width), ceil(sizeLabel.intrinsicContentSize.height), look.labelGap),
            (sizeButton, sizeButton.fittingWidth, high, look.endGap)
        ]
    }

    private var endWidth: CGFloat {
        let look = CursorScreenshotCropLook.self
        return max(look.cancelWidth, cancel.fittingWidth) + look.endGap + max(look.applyWidth, apply.fittingWidth) + CursorScreenshotEditorMetrics.topBarSide
    }

    private func sizeTitle(_ size: CGSize) -> String {
        String(format: MenuBarL("%lld × %lld px"), Int64(size.width), Int64(size.height))
    }

    var leastWidth: CGFloat {
        let look = CursorScreenshotCropLook.self
        let sample = CursorScreenshotBarButton(label: "")
        let widest = { (titles: [String]) -> CGFloat in
            titles.reduce(0) { most, title in
                sample.parts = [.title(title, CursorScreenshotEditorMetrics.textFont), .icon(.chevron, CursorScreenshotEditorMetrics.chevron)]
                return max(most, sample.fittingWidth)
            }
        }
        let limit = CursorScreenshotEditorLook.cropSizeLimit
        let ratioWidth = widest(([.custom, .freeform, .original] + CursorScreenshotCropRatioItem.named).map(CursorScreenshotCropMenus.title))
        return rows.reduce(endWidth) { sum, row in
            let width = row.view === ratio ? max(look.ratioWidth, ratioWidth) : row.view === sizeButton ? widest([sizeTitle(CGSize(width: limit, height: limit))]) : row.width
            return sum + width + row.gap * look.leastGapShare
        }
    }

    override func layout() {
        super.layout()
        let look = CursorScreenshotCropLook.self
        let bar = CursorScreenshotEditorMetrics.self
        let middle = bounds.height / 2
        let place = { (view: NSView, x: CGFloat, width: CGFloat, height: CGFloat) in
            view.frame = CGRect(x: x, y: (middle - height / 2).rounded(), width: width, height: height)
        }
        let line = rows
        let gaps = line.reduce(0) { $0 + $1.gap }
        let room = bounds.width - endWidth - line.reduce(0) { $0 + $1.width }
        let share = min(max(room / max(gaps, 1), look.leastGapShare), 1)
        var x: CGFloat = 0
        for row in line {
            place(row.view, x, row.width, row.height)
            x += row.width + row.gap * share
        }
        let applyWidth = max(look.applyWidth, apply.fittingWidth)
        let cancelWidth = max(look.cancelWidth, cancel.fittingWidth)
        let applyX = bounds.width - bar.topBarSide - applyWidth
        place(apply, applyX, applyWidth, bar.controlHeight)
        place(cancel, applyX - look.endGap - cancelWidth, cancelWidth, bar.controlHeight)
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        let digits = String(field.stringValue.filter(\.isASCII).filter(\.isNumber).prefix(String(CursorScreenshotEditorLook.cropSizeLimit).count))
        if field.stringValue != digits { field.stringValue = digits }
        model.setRatio(width: Int(widthBox.field.stringValue), height: Int(heightBox.field.stringValue))
    }

    private func openColorPanel() {
        CursorScreenshotSystemColors.take(for: self, action: #selector(colorPicked(_:)), current: model.cropFill.resolved(for: model.picture))
        NSColorPanel.shared.orderFront(nil)
    }

    func closeColorPanel() {
        CursorScreenshotSystemColors.close(for: self)
    }

    @objc private func colorPicked(_ sender: NSColorPanel) {
        guard let color = CursorScreenshotSystemColors.color(of: sender) else { return }
        model.setCropFill(.color(color))
    }

    func makeSizePanel(close: @escaping () -> Void) -> CursorScreenshotCropSizePanel {
        CursorScreenshotCropSizePanel(base: model.cropOutputSize) { [weak model] request in
            if let request, model?.resize(request) == false { NSSound.beep() }
            close()
        }
    }

    private func openSizePanel() {
        let popover = NSPopover()
        popover.behavior = .transient
        let panel = makeSizePanel { [weak popover] in popover?.close() }
        let holder = NSViewController()
        holder.view = panel
        popover.contentViewController = holder
        popover.contentSize = CursorScreenshotCropLook.panelSize
        popover.show(relativeTo: sizeButton.bounds, of: sizeButton, preferredEdge: .maxY)
        panel.window?.makeFirstResponder(panel.widthField)
    }
}

final class CursorScreenshotCropBottomParts: NSView {
    private let model: CursorScreenshotEditorModel
    let snap = CursorScreenshotBarButton(label: MenuBarL("Snap to edges"))
    let hint = NSTextField(labelWithString: "")
    let revert = CursorScreenshotBarButton(label: MenuBarL("Revert to Original"))

    init(model: CursorScreenshotEditorModel) {
        self.model = model
        super.init(frame: .zero)
        let look = CursorScreenshotEditorMetrics.self
        snap.partGap = CursorScreenshotCropLook.tickGap
        snap.setAccessibilityRole(.checkBox)
        snap.onPress = { [weak model] in
            guard let model else { return }
            model.setSnapsCrop(!model.choices.snapsCrop)
        }
        hint.font = CursorScreenshotCropLook.hintFont
        hint.textColor = CursorScreenshotEditorPalette.sub
        revert.fill = CursorScreenshotEditorPalette.button
        revert.outline = CursorScreenshotEditorPalette.separator
        revert.parts = [.title(MenuBarL("Revert to Original"), look.textFont)]
        revert.onPress = { [weak model] in model?.revertCrop() }
        for view in [snap, hint, revert] as [NSView] { addSubview(view) }
        refresh()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    func refresh() {
        let snaps = model.choices.snapsCrop
        snap.parts = [.tick(snaps), .title(MenuBarL("Snap to edges"), CursorScreenshotEditorMetrics.textFont)]
        snap.setAccessibilityValue(snaps)
        let words = snaps ? MenuBarL("Hold Command ⌘ to disable snapping.") : MenuBarL("Hold ⌘ to turn snapping on.")
        if hint.stringValue != words { hint.stringValue = words }
        revert.isHidden = !model.cropCutsThePicture
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let bar = CursorScreenshotEditorMetrics.self
        let middle = bounds.height / 2
        let place = { (view: NSView, x: CGFloat, width: CGFloat, height: CGFloat) in
            view.frame = CGRect(x: x, y: (middle - height / 2).rounded(), width: width, height: height)
        }
        let snapWidth = snap.fittingWidth - bar.titlePadding * 2
        place(snap, 0, snapWidth, bar.controlHeight)
        let size = hint.intrinsicContentSize
        place(hint, snapWidth + CursorScreenshotCropLook.hintGap, ceil(size.width), ceil(size.height))
        let revertWidth = revert.fittingWidth
        place(revert, bounds.width - revertWidth, revertWidth, bar.controlHeight)
    }
}

final class CursorScreenshotCropSizePanel: NSView, NSTextFieldDelegate {
    private(set) var request: CursorScreenshotCropResize
    private let finish: (CursorScreenshotCropResize?) -> Void
    private let widthLabel = NSTextField(labelWithString: MenuBarL("Width:"))
    private let heightLabel = NSTextField(labelWithString: MenuBarL("Height:"))
    let widthField = NSTextField()
    let heightField = NSTextField()
    let lock = CursorScreenshotBarButton(label: MenuBarL("Keep Proportions"))
    let unit = NSPopUpButton(frame: .zero, pullsDown: false)
    let flatten = NSButton(checkboxWithTitle: MenuBarL("Flatten Marks"), target: nil, action: nil)
    private let note = NSTextField(labelWithString: MenuBarL("(Cannot be undone)"))
    private let divider = NSBox()
    let cancel = NSButton(title: MenuBarL("Cancel"), target: nil, action: nil)
    let resize = NSButton(title: MenuBarL("Resize"), target: nil, action: nil)

    init(base: CGSize, finish: @escaping (CursorScreenshotCropResize?) -> Void) {
        request = CursorScreenshotCropResize(base: base)
        self.finish = finish
        super.init(frame: NSRect(origin: .zero, size: CursorScreenshotCropLook.panelSize))
        for (field, label) in [(widthField, MenuBarL("Width:")), (heightField, MenuBarL("Height:"))] {
            field.alignment = .right
            field.delegate = self
            field.setAccessibilityLabel(label)
        }
        widthField.nextKeyView = heightField
        heightField.nextKeyView = widthField
        unit.addItems(withTitles: [MenuBarL("pixels"), MenuBarL("percent")])
        unit.target = self
        unit.action = #selector(unitPicked)
        lock.onPress = { [weak self] in
            guard let self else { return }
            self.request.setLocked(!self.request.locked)
            self.show()
        }
        flatten.target = self
        flatten.action = #selector(flattenPicked)
        note.textColor = .secondaryLabelColor
        divider.boxType = .separator
        cancel.bezelStyle = .rounded
        cancel.controlSize = .regular
        cancel.keyEquivalent = "\u{1b}"
        cancel.target = self
        cancel.action = #selector(cancelPressed)
        resize.bezelStyle = .rounded
        resize.keyEquivalent = "\r"
        resize.target = self
        resize.action = #selector(resizePressed)
        for view in [widthLabel, heightLabel, widthField, heightField, lock, unit, flatten, note, divider, cancel, resize] as [NSView] {
            addSubview(view)
        }
        show()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    private func show() {
        widthField.stringValue = String(request.shownWidth)
        heightField.stringValue = String(request.shownHeight)
        widthField.placeholderString = widthField.stringValue
        heightField.placeholderString = heightField.stringValue
        lock.parts = [.icon(request.locked ? .locked : .unlocked, CursorScreenshotEditorMetrics.toolIcon)]
        flatten.state = request.flattens ? .on : .off
        flatten.isEnabled = !request.isFlattenForced
    }

    override func layout() {
        super.layout()
        let side: CGFloat = 20
        let inset = CursorScreenshotCropLook.panelInset
        widthLabel.sizeToFit()
        heightLabel.sizeToFit()
        let labelWidth = CursorScreenshotCropSizeLayout.labelWidth([widthLabel.frame.width, heightLabel.frame.width])
        let fieldX = inset + labelWidth + 6
        let fieldWidth: CGFloat = 160 - labelWidth
        let fieldHeight: CGFloat = 21
        widthLabel.frame = CGRect(x: inset, y: 21, width: labelWidth, height: fieldHeight)
        heightLabel.frame = CGRect(x: inset, y: 51, width: labelWidth, height: fieldHeight)
        widthLabel.alignment = .right
        heightLabel.alignment = .right
        widthField.frame = CGRect(x: fieldX, y: 20, width: fieldWidth, height: fieldHeight)
        heightField.frame = CGRect(x: fieldX, y: 50, width: fieldWidth, height: fieldHeight)
        lock.frame = CGRect(x: fieldX + fieldWidth + 16, y: 35, width: 24, height: 24)
        unit.sizeToFit()
        unit.frame = CGRect(x: fieldX + fieldWidth + 44, y: 34, width: bounds.width - inset - (fieldX + fieldWidth + 44), height: unit.frame.height)
        flatten.sizeToFit()
        note.sizeToFit()
        let row = CursorScreenshotCropSizeLayout.flattenRow(box: flatten.frame.size, note: note.frame.size, width: bounds.width)
        flatten.frame.origin = row.box
        note.frame.origin = row.note
        divider.frame = CGRect(x: side, y: 124, width: bounds.width - side * 2, height: 1)
        let buttonHeight: CGFloat = 24
        let resizeWidth = max(64, resize.intrinsicContentSize.width)
        let cancelWidth = max(66, cancel.intrinsicContentSize.width)
        resize.frame = CGRect(x: bounds.width - side - resizeWidth, y: 141, width: resizeWidth, height: buttonHeight)
        cancel.frame = CGRect(x: resize.frame.minX - 8 - cancelWidth, y: 141, width: cancelWidth, height: buttonHeight)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.setStroke()
        let bracket = NSBezierPath()
        let x = widthField.frame.maxX + 4
        bracket.move(to: CGPoint(x: x, y: widthField.frame.midY))
        bracket.line(to: CGPoint(x: x + 10, y: widthField.frame.midY))
        bracket.line(to: CGPoint(x: x + 10, y: heightField.frame.midY))
        bracket.line(to: CGPoint(x: x, y: heightField.frame.midY))
        bracket.stroke()
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        let digits = String(field.stringValue.filter(\.isASCII).filter(\.isNumber).prefix(String(CursorScreenshotEditorLook.cropSizeLimit).count))
        if field.stringValue != digits { field.stringValue = digits }
        if field === widthField {
            request.setWidth(Int(digits))
            if request.locked { heightField.stringValue = String(request.shownHeight) }
        } else {
            request.setHeight(Int(digits))
            if request.locked { widthField.stringValue = String(request.shownWidth) }
        }
    }

    @objc private func unitPicked() {
        request.setPercent(unit.indexOfSelectedItem == 1)
        show()
    }

    @objc private func flattenPicked() {
        request.flatten = flatten.state == .on
    }

    @objc private func cancelPressed() {
        finish(nil)
    }

    @objc private func resizePressed() {
        finish(request)
    }
}
