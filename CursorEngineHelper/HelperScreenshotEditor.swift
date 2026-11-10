import AppKit
import Combine
import UniformTypeIdentifiers

private enum CursorScreenshotCanvasMetrics {
    static let minimumContent = NSSize(width: 867, height: 322)
    static let openingContent = NSSize(width: 981, height: 460)
    static let screenHeightShare: CGFloat = 0.9
    static let pictureMargin: CGFloat = 30
    static let shadowOffset: CGFloat = 8
    static let shadowBlur: CGFloat = 30
    static let textBoxWidth: CGFloat = 200
    static let textBoxSlack: CGFloat = 12
    static let textBoxInset: CGFloat = 2
    static let copiedFlash: TimeInterval = 1
    static let dragFileGrace: TimeInterval = 60
    static let dragThumbnailSide: CGFloat = 256
}

final class CursorScreenshotEditorCanvas: NSView, NSTextFieldDelegate {
    let model: CursorScreenshotEditorModel
    private var flattened: CGImage?
    private var flattenedEdit: CursorScreenshotEdit?
    private var flattenedSize = CGSize.zero
    private var base: CGImage?
    private var baseCrop = CGRect.null
    private var baseSize = CGSize.zero
    private var baseFill = CursorScreenshotCropFill.transparent
    private var baseBurns = 0
    private var shownCrop: CGRect?
    private var shownSelection: Int?
    private var lastDraftArea = CGRect.null
    private var textBox: NSTextField?
    private let emoji = CursorScreenshotBarButton(label: MenuBarL("Emoji"), parts: [.icon(.smile, 20)])
    private var shownScale: CGFloat = 0
    private var shownPlacement = CGRect.zero
    private var panStart: (window: NSPoint, origin: NSPoint)?
    private(set) var isPanning = false

    init(model: CursorScreenshotEditorModel) {
        self.model = model
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel(MenuBarL("Cursor Capture"))
        emoji.fill = .controlAccentColor
        emoji.tint = .white
        emoji.isHidden = true
        emoji.onPress = { NSApp.orderFrontCharacterPalette(nil) }
        addSubview(emoji)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }

    var canvasPlacement: CGRect {
        let shown = model.shownLayout.size
        let wide = shown.width * scale
        let high = shown.height * scale
        return CGRect(x: ((bounds.width - wide) / 2).rounded(), y: ((bounds.height - high) / 2).rounded(), width: wide, height: high)
    }

    var placement: CGRect {
        let layout = model.shownLayout
        let whole = canvasPlacement
        return CGRect(x: whole.minX + layout.content.minX * scale, y: whole.minY + layout.content.minY * scale, width: layout.content.width * scale, height: layout.content.height * scale)
    }

    private var scale: CGFloat { model.viewScale }

    private func picturePoint(_ event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        let frame = placement
        let area = model.shownArea
        return CGPoint(x: area.minX + (point.x - frame.minX) / max(scale, 0.0001), y: area.minY + (point.y - frame.minY) / max(scale, 0.0001))
    }

    func viewRect(_ rect: CGRect) -> CGRect {
        let frame = placement
        let area = model.shownArea
        return CGRect(x: frame.minX + (rect.minX - area.minX) * scale, y: frame.minY + (rect.minY - area.minY) * scale,
                      width: rect.width * scale, height: rect.height * scale)
    }

    private func draftArea() -> CGRect {
        guard let draft = model.draft else { return .null }
        let reach = draft.size * model.picture.scale * CursorScreenshotEditorLook.arrowHeadLength * scale + 2
        return viewRect(draft.rect).insetBy(dx: -reach, dy: -reach)
    }

    private func redrawDraft() {
        let area = draftArea()
        setNeedsDisplay(area.union(lastDraftArea))
        lastDraftArea = area
    }

    func modelDidChange() {
        syncZoom()
        syncTextBox()
        if flattenedEdit != model.shownEdit || shownCrop != model.cropDraft || shownSelection != model.selection || model.typing != nil || model.isGrabbing { needsDisplay = true }
        window?.invalidateCursorRects(for: self)
    }

    func syncZoom(around anchor: NSPoint? = nil) {
        guard let scroll = enclosingScrollView else { return }
        let look = CursorScreenshotCanvasMetrics.self
        let room = scroll.contentSize
        model.setViewport(CGSize(width: room.width - look.pictureMargin * 2, height: room.height - look.pictureMargin * 2), cropView: room)
        let clip = scroll.contentView
        let visible = clip.bounds
        let spot = anchor ?? NSPoint(x: visible.midX, y: visible.midY)
        let area = model.shownArea
        let reach = model.cropDraft ?? area
        let span = model.shownLayout.size
        let wanted = NSSize(width: max(room.width, ceil(max(abs(reach.minX - area.midX), abs(reach.maxX - area.midX), span.width / 2) * scale * 2) + look.pictureMargin * 2),
                            height: max(room.height, ceil(max(abs(reach.minY - area.midY), abs(reach.maxY - area.midY), span.height / 2) * scale * 2) + look.pictureMargin * 2))
        if frame.size != wanted {
            setFrameSize(wanted)
            needsDisplay = true
        }
        let placed = placement
        if shownScale > 0, shownScale != scale {
            let across = (spot.x - shownPlacement.minX) / shownScale
            let down = (spot.y - shownPlacement.minY) / shownScale
            let origin = NSPoint(x: placed.minX + across * scale - (spot.x - visible.minX), y: placed.minY + down * scale - (spot.y - visible.minY))
            clip.scroll(to: clip.constrainBoundsRect(NSRect(origin: origin, size: visible.size)).origin)
            scroll.reflectScrolledClipView(clip)
            needsDisplay = true
        } else if model.isCropping, shownScale == scale, placed.origin != shownPlacement.origin {
            let origin = NSPoint(x: visible.minX + placed.minX - shownPlacement.minX, y: visible.minY + placed.minY - shownPlacement.minY)
            clip.scroll(to: clip.constrainBoundsRect(NSRect(origin: origin, size: visible.size)).origin)
            scroll.reflectScrolledClipView(clip)
        }
        if shownPlacement != placed { placeTextBox() }
        shownScale = scale
        shownPlacement = placed
    }

    func zoom(by amount: CGFloat, around spot: NSPoint) {
        model.setZoom(model.zoom * (1 + amount))
        syncZoom(around: spot)
    }

    override func magnify(with event: NSEvent) {
        zoom(by: event.magnification, around: convert(event.locationInWindow, from: nil))
    }

    override func scrollWheel(with event: NSEvent) {
        guard model.isCropping, event.modifierFlags.contains(.command), event.scrollingDeltaY != 0 else { return super.scrollWheel(with: event) }
        let step = event.hasPreciseScrollingDeltas ? CursorScreenshotCropLook.trackpadZoomStep : CursorScreenshotCropLook.wheelZoomStep
        model.setZoom(event.scrollingDeltaY > 0 ? model.zoom * step : model.zoom / step)
        syncZoom(around: convert(event.locationInWindow, from: nil))
    }

    func setPanning(_ panning: Bool) {
        guard isPanning != panning else { return }
        isPanning = panning
        if !panning { panStart = nil }
        window?.invalidateCursorRects(for: self)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        placeTextBox()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        placeTextBox()
    }

    override func mouseDown(with event: NSEvent) {
        if isPanning, let clip = enclosingScrollView?.contentView {
            panStart = (event.locationInWindow, clip.bounds.origin)
            window?.invalidateCursorRects(for: self)
            return
        }
        if model.isCropping { window?.makeFirstResponder(nil) }
        model.beginDrag(at: picturePoint(event), flags: event.modifierFlags)
        syncTextBox()
        redrawDraft()
        if flattenedEdit != model.shownEdit || shownSelection != model.selection { needsDisplay = true }
        if model.isGrabbing { window?.invalidateCursorRects(for: self) }
    }

    override func mouseDragged(with event: NSEvent) {
        if let panStart, let scroll = enclosingScrollView {
            let clip = scroll.contentView
            let origin = NSPoint(x: panStart.origin.x - (event.locationInWindow.x - panStart.window.x), y: panStart.origin.y + (event.locationInWindow.y - panStart.window.y))
            clip.scroll(to: clip.constrainBoundsRect(NSRect(origin: origin, size: clip.bounds.size)).origin)
            scroll.reflectScrolledClipView(clip)
            return
        }
        model.updateDrag(to: picturePoint(event), flags: event.modifierFlags, spaceHeld: isPanning)
        if model.isCropping {
            syncZoom()
            needsDisplay = true
            return
        }
        if model.isGrabbing || !model.drawsDraftOnTop { needsDisplay = true }
        redrawDraft()
    }

    override func mouseUp(with event: NSEvent) {
        if panStart != nil {
            panStart = nil
            window?.invalidateCursorRects(for: self)
            return
        }
        model.updateDrag(to: picturePoint(event), flags: event.modifierFlags, spaceHeld: isPanning)
        model.endDrag()
        lastDraftArea = .null
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    override func resetCursorRects() {
        if isPanning { return addCursorRect(visibleRect, cursor: panStart == nil ? .openHand : .closedHand) }
        if model.isGrabbing { return addCursorRect(visibleRect, cursor: .closedHand) }
        if let box = model.cropDraft { return addCropCursorRects(viewRect(box)) }
        switch model.tool {
        case .text: addCursorRect(placement, cursor: .iBeam)
        case .select: break
        default: addCursorRect(placement, cursor: .crosshair)
        }
        addMarkCursorRects()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let frame = placement
        let whole = canvasPlacement
        let cropBox = model.cropDraft.map(viewRect)
        let framed = model.shownEdit.hasBackground
        if let cropBox {
            drawCropBack(cropBox, in: dirtyRect)
        } else if !whole.contains(dirtyRect) {
            let look = CursorScreenshotCanvasMetrics.self
            CursorScreenshotEditorPalette.background.setFill()
            dirtyRect.fill()
            context.saveGState()
            if !framed { context.setShadow(offset: CGSize(width: 0, height: look.shadowOffset), blur: look.shadowBlur, color: CursorScreenshotEditorPalette.shadow.cgColor) }
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(whole)
            context.restoreGState()
            if framed {
                CursorScreenshotEditorPalette.separator.setStroke()
                NSBezierPath(rect: whole.insetBy(dx: -0.5, dy: -0.5)).stroke()
            }
        } else {
            NSColor.white.setFill()
            dirtyRect.fill()
        }
        let crop = model.shownArea
        let device = abs(context.userSpaceToDeviceSpaceTransform.a)
        let size = CGSize(width: min((frame.width * device).rounded(), crop.width), height: min((frame.height * device).rounded(), crop.height))
        if flattened == nil || flattenedEdit != model.shownEdit || flattenedSize != size { flatten(size: size) }
        if framed, let flattened {
            context.saveGState()
            if scale * device > 1 { context.interpolationQuality = .none }
            CursorScreenshotRender.draw(flattened, in: whole, on: context)
            context.restoreGState()
        }
        context.saveGState()
        context.translateBy(x: frame.minX, y: frame.minY)
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -crop.minX, y: -crop.minY)
        if scale * device > 1 { context.interpolationQuality = .none }
        if !framed, let flattened { CursorScreenshotRender.draw(flattened, in: crop, on: context) }
        if let draft = model.draft, model.drawsDraftOnTop {
            context.clip(to: crop)
            CursorScreenshotRender.render(model.picture, marks: [draft], shared: model.shared, drawsImage: false, on: context)
        }
        if let typing = model.typing { CursorScreenshotRender.drawTextBacking(typing, picture: model.picture, on: context) }
        context.restoreGState()
        shownCrop = model.cropDraft
        shownSelection = model.selection
        if let cropBox { drawCropFrame(cropBox, over: frame) }
        drawGuidesAndSelection(on: context)
    }

    private func flatten(size: CGSize) {
        var shown = model.shownEdit
        let crop = shown.crop
        flattenedEdit = shown
        flattenedSize = size
        flattened = nil
        guard size.width >= 1, size.height >= 1 else { return }
        if base == nil || baseCrop != crop || baseSize != size || baseFill != shown.fill || baseBurns != shown.burns {
            base = CursorScreenshotRender.scene(model.picture, marks: [], shared: shown.shared, crop: crop, size: size, fill: shown.fill.resolved(for: model.picture))
            baseCrop = crop
            baseSize = size
            baseFill = shown.fill
            baseBurns = shown.burns
        }
        shown.spreadDim()
        flattened = CursorScreenshotRender.scene(model.picture, marks: shown.marks, shared: shown.shared, crop: crop, size: size, base: base)
        if shown.hasBackground { flattened = flattened.flatMap { CursorScreenshotRender.composed($0, picture: model.picture, edit: shown, factor: size.width / crop.width) } }
    }

    private func syncTextBox() {
        guard let typing = model.typing else {
            textBox?.removeFromSuperview()
            textBox = nil
            emoji.isHidden = true
            return
        }
        let font = CursorScreenshotRender.textFont(ofSize: typing.size * model.picture.scale, style: typing.textStyle)
        if let textBox {
            textBox.font = font
            textBox.textColor = NSColor(cgColor: typing.color.cgColor)
            placeTextBox()
        } else {
            let field = NSTextField(string: typing.text)
            field.isBordered = false
            field.drawsBackground = false
            field.focusRingType = .none
            field.usesSingleLineMode = typing.wrap == 0
            field.lineBreakMode = typing.wrap == 0 ? .byClipping : .byWordWrapping
            field.alignment = .left
            field.font = font
            field.cell?.isScrollable = typing.wrap == 0
            field.cell?.wraps = typing.wrap > 0
            field.textColor = NSColor(cgColor: typing.color.cgColor)
            field.delegate = self
            field.setAccessibilityLabel(MenuBarL("Text"))
            addSubview(field)
            textBox = field
            placeTextBox()
            window?.makeFirstResponder(field)
        }
        emoji.isHidden = false
        setTextDirection()
    }

    private func setTextDirection() {
        guard let field = textBox, let typing = model.typing else { return }
        let rightToLeft = CursorScreenshotRender.isRightToLeft(typing.text)
        let direction: NSWritingDirection = rightToLeft ? .rightToLeft : .natural
        field.alignment = CursorScreenshotRender.fieldAlignment(typing)
        field.baseWritingDirection = direction
        field.currentEditor()?.baseWritingDirection = direction
    }

    private func placeTextBox() {
        guard let field = textBox, let typing = model.typing, let font = field.font, scale > 0 else { return }
        let look = CursorScreenshotCanvasMetrics.self
        let measured = NSAttributedString(string: typing.text, attributes: [.font: font]).size().width * scale + look.textBoxSlack
        let layout = CursorScreenshotRender.textLayout(typing, scale: model.picture.scale)
        let height = typing.wrap > 0 ? layout.frame.height * scale + look.textBoxSlack : (field.cell?.cellSize.height ?? font.pointSize) * scale
        let width = typing.wrap > 0 ? typing.wrap * scale + look.textBoxInset * 2 * scale : max(look.textBoxWidth, measured)
        field.setFrameSize(NSSize(width: ceil(width), height: ceil(height)))
        field.setBoundsSize(NSSize(width: field.frame.width / scale, height: field.frame.height / scale))
        let start = viewPoint(typing.start)
        let baseline = start.y + font.ascender * scale
        field.setFrameOrigin(NSPoint(x: start.x - look.textBoxInset * scale, y: baseline - field.firstBaselineOffsetFromTop * scale))
        let size = CursorScreenshotSelectionLook.emojiSize
        emoji.frame = CGRect(x: viewRect(layout.frame).midX - size / 2, y: start.y - CursorScreenshotSelectionLook.emojiGap - size, width: size, height: size)
    }

    func controlTextDidChange(_ notification: Notification) {
        model.setTypedText(textBox?.stringValue ?? "")
        setTextDirection()
        placeTextBox()
        needsDisplay = true
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        model.commitText()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        model.cancelText()
        return true
    }
}

final class CursorScreenshotEditorView: NSView {
    let model: CursorScreenshotEditorModel
    let canvas: CursorScreenshotEditorCanvas
    let scroll = NSScrollView()
    let topBar: CursorScreenshotEditorTopBar
    let bottomBar: CursorScreenshotEditorBottomBar
    let dropZone = CursorScreenshotDropZoneView()
    let panel: CursorScreenshotBackgroundPanel
    private(set) var panelShare: CGFloat = 0
    private var panelTarget: CGFloat = 0
    private var slideTimer: Timer?
    private var watcher: AnyCancellable?
    private var barsCropping = false

    init(model: CursorScreenshotEditorModel, actions: CursorScreenshotEditorActions) {
        self.model = model
        canvas = CursorScreenshotEditorCanvas(model: model)
        topBar = CursorScreenshotEditorTopBar(model: model, actions: actions)
        bottomBar = CursorScreenshotEditorBottomBar(model: model, actions: actions)
        panel = CursorScreenshotBackgroundPanel(model: model, actions: actions)
        if model.isBackgroundOpen {
            panelShare = 1
            panelTarget = 1
            model.prepareBackdrops()
        }
        super.init(frame: .zero)
        scroll.documentView = canvas
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        addSubview(scroll)
        addSubview(dropZone)
        addSubview(panel)
        addSubview(bottomBar)
        registerForDraggedTypes([.fileURL])
        watcher = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    func refresh() {
        canvas.modelDidChange()
        topBar.refresh()
        bottomBar.refresh()
        panel.refresh()
        syncPanel()
        if barsCropping != model.isCropping {
            barsCropping = model.isCropping
            needsDisplay = true
        }
    }

    private func syncPanel() {
        let target: CGFloat = model.isBackgroundOpen ? 1 : 0
        guard target != panelTarget else {
            if model.isCropping != panel.isHidden { needsLayout = true }
            return
        }
        panelTarget = target
        slideTimer?.invalidate()
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            panelShare = target
            needsLayout = true
            return
        }
        let start = panelShare
        let began = Date()
        let timer = Timer(timeInterval: CursorScreenshotBackgroundLook.slideStep, repeats: true) { [weak self] timer in
            let finished = MainActor.assumeIsolated { () -> Bool in
                guard let self else { return true }
                let done = min(Date().timeIntervalSince(began) / CursorScreenshotBackgroundLook.slideTime, 1)
                self.panelShare = start + (target - start) * (done * done * (3 - 2 * done))
                self.needsLayout = true
                self.layoutSubtreeIfNeeded()
                return done >= 1
            }
            if finished { timer.invalidate() }
        }
        RunLoop.main.add(timer, forMode: .common)
        slideTimer = timer
    }

    var panelNeedsHeight: CGFloat {
        panel.fittingHeight + topHeight + CursorScreenshotEditorMetrics.bottomBarHeight
    }

    private var topHeight: CGFloat {
        guard let window else { return CursorScreenshotEditorMetrics.topBarHeight }
        return max(bounds.height - window.contentLayoutRect.height, 0)
    }

    override func layout() {
        super.layout()
        let look = CursorScreenshotEditorMetrics.self
        let top = topHeight
        let high = max(bounds.height - top - look.bottomBarHeight, 0)
        let width = CursorScreenshotBackgroundLook.panelWidth
        let shift = model.isCropping ? 0 : (width * panelShare).rounded()
        scroll.frame = CGRect(x: shift, y: top, width: max(bounds.width - shift, 0), height: high)
        panel.frame = CGRect(x: shift - width, y: top, width: width, height: high)
        panel.isHidden = shift == 0
        dropZone.frame = scroll.frame
        bottomBar.frame = CGRect(x: 0, y: bounds.height - look.bottomBarHeight, width: bounds.width, height: look.bottomBarHeight)
        canvas.syncZoom()
        bottomBar.refresh()
    }

    override func draw(_ dirtyRect: NSRect) {
        let look = CursorScreenshotEditorMetrics.self
        let top = topHeight
        let upper = CGRect(x: 0, y: 0, width: bounds.width, height: top)
        let lower = CGRect(x: 0, y: bounds.height - look.bottomBarHeight, width: bounds.width, height: look.bottomBarHeight)
        if model.isCropping {
            CursorScreenshotEditorPalette.background.setFill()
            upper.fill()
            lower.fill()
        } else {
            let gradient = NSGradient(starting: CursorScreenshotEditorPalette.barStart, ending: CursorScreenshotEditorPalette.barEnd)
            gradient?.draw(in: upper, angle: 0)
            gradient?.draw(in: lower, angle: 0)
        }
        CursorScreenshotEditorPalette.separator.setFill()
        CGRect(x: 0, y: top - 1, width: bounds.width, height: 1).fill(using: .sourceOver)
        CGRect(x: 0, y: lower.minY, width: bounds.width, height: 1).fill(using: .sourceOver)
    }

    private func takesDrop(_ drop: NSDraggingInfo) -> Bool {
        !model.isCropping && window?.attachedSheet == nil && !(drop.draggingSource is CursorScreenshotDragButton) && CursorScreenshotImageSource.holdsFile(drop.draggingPasteboard)
    }

    private func dropEdge(_ drop: NSDraggingInfo) -> CursorScreenshotImageEdge? {
        CursorScreenshotImageEdge.near(dropZone.convert(drop.draggingLocation, from: nil), in: dropZone.bounds.size)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggingUpdated(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard takesDrop(sender) else {
            dropZone.edge = nil
            return []
        }
        dropZone.edge = dropEdge(sender)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        dropZone.edge = nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard takesDrop(sender) else { return false }
        let files = CursorScreenshotImageSource.files(on: sender.draggingPasteboard)
        let edge = dropEdge(sender)
        let visible = canvas.visiblePictureArea
        dropZone.edge = nil
        Task { [model] in
            if await !model.addImages(from: files, edge: edge, visible: visible) { NSSound.beep() }
        }
        return true
    }
}

@MainActor
final class CursorScreenshotEditor: NSObject, NSWindowDelegate, NSApplicationDelegate {
    private static var current: CursorScreenshotEditor?
    private static var previousApp: NSRunningApplication?
    static var imageSource: ((@escaping @MainActor (CGImage?) -> Void) -> Void)?
    private nonisolated static let reader = CursorTranslatorReader()

    private let model: CursorScreenshotEditorModel
    private let name: CursorScreenshotFileName
    private let window: NSWindow
    private let colors: CursorScreenshotColorPopup
    private var root: CursorScreenshotEditorView?
    private var toolbarDelegate: CursorScreenshotEditorToolbar?
    private var keyMonitor: Any?
    private let dragFolder = CursorScreenshotEditor.dragFolders?.appendingPathComponent(UUID().uuidString, isDirectory: true)
    private var closing = CursorScreenshotCloseQueue()
    private var afterSheet: (@MainActor () -> Void)?

    static let dragFolders = CursorScreenshotController.dragFolder?.deletingLastPathComponent().appendingPathComponent(CursorScreenshot.editorDragFolder, isDirectory: true)

    static func open(_ image: CGImage, scale: CGFloat, name: CursorScreenshotFileName) {
        open(scale: scale, name: name) { CursorScreenshotPicture(image, scale: $0) }
    }

    private static func open(scale: CGFloat, name: CursorScreenshotFileName? = nil, reading read: @escaping @Sendable (CGFloat) -> CursorScreenshotPicture?) {
        Task {
            let picture = await Task.detached(priority: .userInitiated) { read(scale) }.value
            guard let picture else { return NSSound.beep() }
            show(picture, name: name ?? freshName(scale: picture.scale))
        }
    }

    private static func freshName(scale: CGFloat) -> CursorScreenshotFileName {
        let config = CursorScreenshotConfig.load()
        let name = config.naming.name(CursorScreenshotNameContext(date: Date()), scale: scale, output: config.output)
        CursorScreenshotConfig.spent(name)
        return name
    }

    private static var chooser: NSOpenPanel?

    private static func chooseFile(prompt: String, then use: @escaping @MainActor (URL) -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        guard chooser == nil else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = CursorScreenshotImageSource.fileTypes
        panel.prompt = MenuBarL(prompt)
        chooser = panel
        panel.begin { answer in
            chooser = nil
            guard answer == .OK, let url = panel.url else { return }
            use(url)
        }
    }

    static func openFile() {
        chooseFile(prompt: "Open") { url in
            open(scale: screenUnderMouse?.backingScaleFactor ?? 1) {
                CursorScreenshotImageSource.picture(from: CGImageSourceCreateWithURL(url as CFURL, nil), scale: $0)
            }
        }
    }

    static func openClipboard() {
        let board = NSPasteboard.general
        let file = CursorScreenshotImageSource.files(on: board).first
        let data = file == nil ? CursorScreenshotImageSource.data(on: board) : nil
        open(scale: screenUnderMouse?.backingScaleFactor ?? 1) { scale in
            let source = file.flatMap { CGImageSourceCreateWithURL($0 as CFURL, nil) } ?? data.flatMap { CGImageSourceCreateWithData($0 as CFData, nil) }
            return CursorScreenshotImageSource.picture(from: source, scale: scale)
        }
    }

    static func pinFile() {
        chooseFile(prompt: "Pin") { url in
            let screen = screenUnderMouse
            let scale = screen?.backingScaleFactor ?? 1
            let output = CursorScreenshotConfig.load().output
            Task {
                let image = await Task.detached(priority: .userInitiated) {
                    CursorScreenshotImageSource.image(from: CGImageSourceCreateWithURL(url as CFURL, nil), side: CursorScreenshotEditorLook.largestImageSide)
                        .map { output.apply($0, scale: scale) }
                }.value
                guard let image else { return NSSound.beep() }
                CursorScreenshotPin.show(image, scale: output.shownScale(scale), on: screen)
            }
        }
    }

    private static var screenUnderMouse: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
    }

    static func closeThen(_ next: @escaping @MainActor () -> Void) -> Bool {
        current?.closeThen(next) ?? true
    }

    private static func show(_ picture: CursorScreenshotPicture, name: CursorScreenshotFileName) {
        if let current, current.closing.waitsForSheet(hasSheet: current.window.attachedSheet != nil) {
            current.afterSheet = { show(picture, name: name) }
            return
        }
        guard closeThen({ show(picture, name: name) }) else { return }
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp = front }
        current = CursorScreenshotEditor(picture: picture, name: name)
    }

    static func makeWindow(frame: NSRect) -> NSWindow {
        let window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = MenuBarL("Cursor Capture")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.toolbarStyle = .unifiedCompact
        window.contentMinSize = CursorScreenshotCanvasMetrics.minimumContent
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        return window
    }

    static func backdropSource(for screen: NSScreen?) -> CursorScreenshotBackdropSource {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return CursorScreenshotBackdropSource(wallpaperFolder: support?.appendingPathComponent(CursorScreenshot.wallpaperFolder, isDirectory: true),
                                              desktop: screen.flatMap { NSWorkspace.shared.desktopImageURL(for: $0) })
    }

    static func install(_ root: CursorScreenshotEditorView, in window: NSWindow) -> CursorScreenshotEditorToolbar {
        let delegate = CursorScreenshotEditorToolbar(bar: root.topBar)
        let toolbar = NSToolbar(identifier: "CursorScreenshotEditor")
        toolbar.delegate = delegate
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        window.toolbar = toolbar
        window.contentView = root
        window.contentMinSize.width = CursorScreenshotCanvasMetrics.minimumContent.width + root.topBar.wordRoom
        let missing = window.contentMinSize.width - window.frame.width
        if missing > 0 { window.setFrame(window.frame.insetBy(dx: -missing / 2, dy: 0), display: window.isVisible) }
        if root.model.isBackgroundOpen { growForPanel(root, in: window) }
        return delegate
    }

    private static func growForPanel(_ root: CursorScreenshotEditorView, in window: NSWindow) {
        guard let visible = (window.screen ?? screenUnderMouse)?.visibleFrame else { return }
        window.setFrame(CursorScreenshotBackgroundLook.grownFrame(window.frame, contentHeight: root.bounds.height, needed: root.panelNeedsHeight, visible: visible), display: window.isVisible)
    }

    static func editMenu() -> NSMenu {
        let edit = NSMenu()
        let keys: [(Selector, String, NSEvent.ModifierFlags)] = [
            (Selector(("undo:")), "z", [.command]), (Selector(("redo:")), "z", [.command, .shift]),
            (#selector(NSText.cut(_:)), "x", [.command]), (#selector(NSText.copy(_:)), "c", [.command]),
            (#selector(NSText.paste(_:)), "v", [.command]), (#selector(NSText.selectAll(_:)), "a", [.command])
        ]
        for (action, key, flags) in keys {
            let item = NSMenuItem(title: "", action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = flags
            edit.addItem(item)
        }
        let holder = NSMenuItem()
        holder.submenu = edit
        let menu = NSMenu()
        menu.addItem(holder)
        return menu
    }

    private init(picture: CursorScreenshotPicture, name: CursorScreenshotFileName) {
        self.name = name
        model = CursorScreenshotEditorModel(picture: picture, choices: .load(), library: CursorScreenshotConfig.load().background, backdropSource: Self.backdropSource(for: Self.screenUnderMouse), textLineSource: { source in
            let image = source.image
            let larger = await Task.detached(priority: .userInitiated) { CursorScreenshot.forReading(image, pointScale: source.scale) }.value
            guard let seen = await Self.reader.read(larger) else {
                await CursorTranslatorReader.warm()
                return nil
            }
            return seen.lines.map { CursorTranslator.imageRect($0.box, width: image.width, height: image.height) }
        })
        model.libraryChanged = { CursorScreenshotConfig.changeBackground($0) }
        model.output = { CursorScreenshotConfig.load().output }
        model.clipboard = { [name] in (CursorScreenshotConfig.load().clipboard, CursorScreenshotController.clipboardFolder, name) }
        window = Self.makeWindow(frame: Self.frame(for: picture))
        colors = CursorScreenshotColorPopup(model: model)
        super.init()
        var actions = CursorScreenshotEditorActions()
        actions.saveAs = { [weak self] in self?.saveAs() }
        actions.done = { [weak self] in self?.window.performClose(nil) }
        actions.copy = { [weak self] in self?.copyPicture() }
        actions.pin = { [weak self] in self?.pinPicture() }
        actions.share = { [weak self] anchor in self?.sharePicture(from: anchor) }
        actions.makeDragFile = { [weak self] in self?.makeDragFile() }
        actions.openColors = { [weak self] anchor in self?.colors.toggle(under: anchor) }
        actions.turn = { [weak self] turn in self?.turnPicture(turn) }
        actions.takeImage = { [weak self] in self?.takeImage() }
        actions.pasteImage = { [weak self] in self?.pasteImage() }
        actions.chooseImage = { [weak self] in self?.chooseImage() }
        actions.toggleBackground = { [weak self] in self?.toggleBackground() }
        actions.chooseWallpaper = { [weak self] in self?.chooseWallpaper() }
        actions.namePreset = { [weak self] in self?.askPresetName($0) }
        actions.confirmDeletePreset = { [weak self] in self?.askDeletePreset($0) }
        let root = CursorScreenshotEditorView(model: model, actions: actions)
        root.bottomBar.drag.thumbnail = { [weak self] in self?.dragThumbnail() }
        self.root = root
        toolbarDelegate = Self.install(root, in: window)
        window.delegate = self
        NSApp.mainMenu = Self.editMenu()
        NSApp.delegate = self
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private static func frame(for picture: CursorScreenshotPicture) -> NSRect {
        let look = CursorScreenshotCanvasMetrics.self
        guard let screen = screenUnderMouse else {
            return NSRect(origin: .zero, size: look.minimumContent)
        }
        let visible = screen.visibleFrame
        let bars = CursorScreenshotEditorMetrics.topBarHeight + CursorScreenshotEditorMetrics.bottomBarHeight + look.pictureMargin * 2
        let room = CGSize(width: visible.width - look.pictureMargin * 2, height: visible.height * look.screenHeightShare - bars)
        let shown = CursorScreenshotRender.placed(picture.size, in: room, backing: picture.scale).size
        let size = NSSize(width: min(max(shown.width + look.pictureMargin * 2, look.openingContent.width), visible.width),
                          height: min(max(shown.height + bars, look.openingContent.height), visible.height))
        return NSRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2, width: size.width, height: size.height)
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard event.window === window, window.attachedSheet == nil else { return undoFromColors(event) }
        if event.type == .keyUp {
            if event.characters == " " { root?.canvas.setPanning(false) }
            return event
        }
        let fieldEditor = (window.firstResponder as? NSTextView).flatMap { $0.isFieldEditor ? $0 : nil }
        let letter = event.characters(byApplyingModifiers: .command)
        guard let action = CursorScreenshotEditorAction.forKey(letter: letter, typed: event.characters, flags: event.modifierFlags,
                                                               editingText: fieldEditor != nil, cropping: model.cropDraft != nil,
                                                               hasSelection: model.selectedMark != nil, hasCopy: model.hasCopiedMark,
                                                               hasImage: letter?.lowercased() == "v" && model.clipboardImageWins()) else { return event }
        switch action {
        case .undo:
            if let fieldEditor {
                fieldEditor.undoManager?.undo()
                fieldEditor.didChangeText()
            } else {
                model.undo()
            }
        case .redo:
            if let fieldEditor {
                fieldEditor.undoManager?.redo()
                fieldEditor.didChangeText()
            } else {
                model.redo()
            }
        case .close: window.performClose(nil)
        case .cut: NSApp.sendAction(#selector(NSText.cut(_:)), to: fieldEditor, from: nil)
        case .copy: NSApp.sendAction(#selector(NSText.copy(_:)), to: fieldEditor, from: nil)
        case .paste: NSApp.sendAction(#selector(NSText.paste(_:)), to: fieldEditor, from: nil)
        case .selectAll: NSApp.sendAction(#selector(NSText.selectAll(_:)), to: fieldEditor, from: nil)
        case .apply:
            if model.selectedMark?.tool == .text { model.editSelectedText() } else {
                guard model.cropDraft != nil else { return event }
                model.applyCrop()
            }
        case .cancel:
            if model.selectedMark != nil { model.deselect() } else {
                guard model.cropDraft != nil else { return event }
                model.cancelCrop()
            }
        case .deleteMark: model.deleteSelected()
        case .duplicateMark: model.duplicateSelected()
        case .copyMark: model.copySelected()
        case .pasteMark: model.pasteMark()
        case .nudge(let x, let y): model.nudgeSelected(x: x, y: y)
        case .tool(let tool): model.pick(tool)
        case .sizeUp: model.stepSize(up: true)
        case .sizeDown: model.stepSize(up: false)
        case .pickSize(let number): model.pickSize(number: number)
        case .zoomIn: model.stepZoom(up: true)
        case .zoomOut: model.stepZoom(up: false)
        case .zoomFit: model.zoomToFit()
        case .zoomActual: model.setZoom(1)
        case .saveAs:
            model.applyCrop()
            saveAs()
        case .copyPicture:
            model.applyCrop()
            copyPicture()
        case .pan: root?.canvas.setPanning(true)
        case .openCrop: model.openCrop()
        case .nudgeCrop(let x, let y, let big, let resizes): model.nudgeCrop(x: x, y: y, big: big, resizes: resizes)
        case .takeImage: takeImage()
        case .chooseImage: chooseImage()
        case .pasteImage: pasteImage()
        case .toggleBackground: toggleBackground()
        }
        return nil
    }

    private func undoFromColors(_ event: NSEvent) -> NSEvent? {
        guard event.type == .keyDown, let popup = event.window as? CursorScreenshotColorPanel else { return event }
        let fieldUndo = (popup.firstResponder as? NSTextView).flatMap { $0.isFieldEditor ? $0.undoManager : nil }
        guard fieldUndo?.canUndo != true, fieldUndo?.canRedo != true else { return event }
        switch CursorScreenshotEditorAction.forKey(letter: event.characters(byApplyingModifiers: .command), flags: event.modifierFlags) {
        case .undo: model.undo()
        case .redo: model.redo()
        default: return event
        }
        (popup.contentView as? CursorScreenshotColorView)?.refresh()
        return nil
    }

    private func toggleBackground() {
        let opening = !model.isBackgroundOpen
        if opening, let root { Self.growForPanel(root, in: window) }
        model.setBackgroundOpen(opening)
    }

    private func chooseWallpaper() {
        guard window.attachedSheet == nil else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = CursorScreenshotImageSource.wallpaperTypes
        panel.prompt = MenuBarL("Open")
        panel.beginSheetModal(for: window) { [self] answer in
            guard answer == .OK, let file = panel.url else { return }
            Task {
                if await !model.addWallpaper(from: file) { NSSound.beep() }
            }
        }
    }

    private func askPresetName(_ done: @escaping (String) -> Void) {
        guard window.attachedSheet == nil else { return }
        let first = MenuBarL("My preset")
        let field = NSTextField(string: first)
        field.frame = NSRect(origin: .zero, size: CursorScreenshotBackgroundLook.nameFieldSize)
        let alert = NSAlert()
        alert.messageText = MenuBarL("Add New Preset…")
        alert.accessoryView = field
        alert.addButton(withTitle: MenuBarL("Save"))
        alert.addButton(withTitle: MenuBarL("Cancel")).keyEquivalent = "\u{1b}"
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { answer in
            guard answer == .alertFirstButtonReturn else { return }
            let typed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            done(typed.isEmpty ? first : typed)
        }
    }

    private func askDeletePreset(_ done: @escaping () -> Void) {
        guard window.attachedSheet == nil else { return }
        let alert = NSAlert()
        alert.messageText = MenuBarL("Delete this preset?")
        alert.addButton(withTitle: MenuBarL("Delete")).hasDestructiveAction = true
        alert.addButton(withTitle: MenuBarL("Cancel")).keyEquivalent = "\u{1b}"
        alert.beginSheetModal(for: window) { answer in
            if answer == .alertFirstButtonReturn { done() }
        }
    }

    private func takeImage() {
        colors.close()
        model.addCapture(show: { [window] in
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }, source: { done in
            guard let source = Self.imageSource else { return done(nil) }
            source(done)
        })
    }

    private func pasteImage() {
        Task {
            if await !model.pasteImage() { NSSound.beep() }
        }
    }

    private func chooseImage() {
        guard window.attachedSheet == nil else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = CursorScreenshotImageSource.fileTypes
        panel.prompt = MenuBarL("Open")
        panel.beginSheetModal(for: window) { [self] answer in
            guard answer == .OK else { return }
            let files = panel.urls
            Task {
                if await !model.addImages(from: files) { NSSound.beep() }
            }
        }
    }

    private func turnPicture(_ turn: CursorScreenshotCropTurn) {
        guard model.burnLosesEdits, CursorScreenshotConfig.load().warnsBeforeFlatten else { return model.turn(turn) }
        guard window.attachedSheet == nil else { return }
        let alert = NSAlert()
        alert.messageText = turn == .rotate ? MenuBarL("Rotate image?") : MenuBarL("Flip image?")
        alert.informativeText = MenuBarL("This burns every mark into the picture, so you can no longer edit them. You cannot undo this.")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = MenuBarL("Don't ask again")
        alert.addButton(withTitle: turn == .rotate ? MenuBarL("Flatten and Rotate") : MenuBarL("Flatten and Flip"))
        alert.addButton(withTitle: MenuBarL("Cancel")).keyEquivalent = "\u{1b}"
        alert.beginSheetModal(for: window) { [self] answer in
            guard answer == .alertFirstButtonReturn else { return }
            if alert.suppressionButton?.state == .on { CursorScreenshotConfig.stopWarningBeforeFlatten() }
            model.turn(turn)
        }
    }

    private func closeThen(_ next: @escaping @MainActor () -> Void, cancelled: @escaping @MainActor () -> Void = {}) -> Bool {
        guard !closing.closesAtOnce(isDirty: model.isDirty, hasSheet: window.attachedSheet != nil) else {
            window.close()
            return true
        }
        askBeforeClosing(then: next, cancelled: cancelled)
        return false
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !closing.closesAtOnce(isDirty: model.isDirty, hasSheet: window.attachedSheet != nil) else { return true }
        if !answerPending { askBeforeClosing {} }
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let closed = closeThen({ sender.reply(toApplicationShouldTerminate: true) }, cancelled: { sender.reply(toApplicationShouldTerminate: false) })
        return closed ? .terminateNow : .terminateLater
    }

    func windowDidResignKey(_ notification: Notification) {
        root?.canvas.setPanning(false)
    }

    func windowDidEndSheet(_ notification: Notification) {
        guard let next = afterSheet else { return }
        afterSheet = nil
        Task { next() }
    }

    func windowWillClose(_ notification: Notification) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        colors.close()
        root?.topBar.cropBar.closeColorPanel()
        root?.panel.closeColorPanel()
        model.noteClosing()
        model.remembered.save()
        NSApp.mainMenu = nil
        NSApp.delegate = nil
        if let dragFolder {
            DispatchQueue.main.asyncAfter(deadline: .now() + CursorScreenshotCanvasMetrics.dragFileGrace) { try? FileManager.default.removeItem(at: dragFolder) }
        }
        Self.current = nil
        Task {
            guard Self.current == nil else { return }
            if NSApp.isActive, let previous = Self.previousApp, !previous.isTerminated { previous.activate(options: []) }
            Self.previousApp = nil
        }
    }

    private func askBeforeClosing(then next: @escaping @MainActor () -> Void, cancelled: @escaping @MainActor () -> Void = {}) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        let request = CursorScreenshotCloseRequest(next: next, cancelled: cancelled)
        guard !answerPending else { return closing.joined(request).cancelled() }
        closing.start(request)
        let alert = NSAlert()
        alert.messageText = MenuBarL("Unsaved Changes")
        alert.informativeText = MenuBarL("Your changes will be discarded if you don't save them.")
        alert.addButton(withTitle: MenuBarL("Save"))
        alert.addButton(withTitle: MenuBarL("Don't Save")).hasDestructiveAction = true
        alert.addButton(withTitle: MenuBarL("Cancel")).keyEquivalent = "\u{1b}"
        alert.beginSheetModal(for: window) { [self] answer in
            switch answer {
            case .alertFirstButtonReturn:
                savePicture(then: closeAndGoOn, cancelled: stayOpen)
            case .alertSecondButtonReturn:
                closeAndGoOn()
            default:
                stayOpen()
            }
        }
    }

    private var answerPending: Bool {
        closing.isWaiting || window.attachedSheet != nil
    }

    private func closeAndGoOn() {
        let finished = closing.end()
        window.close()
        finished?.next()
    }

    private func stayOpen() {
        closing.end()?.cancelled()
    }

    private func copyPicture() {
        let staysOpen = NSEvent.modifierFlags.contains(.option)
        Task {
            guard await model.copy() else { return NSSound.beep() }
            guard staysOpen || answerPending else {
                model.noteKept()
                return window.close()
            }
            guard let button = root?.bottomBar.copy else { return }
            button.parts = [.title("✓", CursorScreenshotEditorMetrics.textFont)]
            DispatchQueue.main.asyncAfter(deadline: .now() + CursorScreenshotCanvasMetrics.copiedFlash) {
                MainActor.assumeIsolated { button.parts = [.icon(.copy, CursorScreenshotEditorMetrics.actionIcon)] }
            }
        }
    }

    private func pinPicture() {
        let screen = window.screen
        let scale = model.output().shownScale(model.picture.scale)
        Task {
            await model.flattenedOnce { [self] image in
                guard let image else { return NSSound.beep() }
                CursorScreenshotPin.show(image, scale: scale, on: screen)
                guard !answerPending else { return }
                model.noteKept()
                window.close()
            }
        }
    }

    private func sharePicture(from anchor: NSView) {
        Task {
            guard let made = await model.encoded(), let dragFolder,
                  let file = try? CursorScreenshot.dragFile(made.data, as: made.format, name: name, in: dragFolder) else { return NSSound.beep() }
            NSSharingServicePicker(items: [file]).show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        }
    }

    private func makeDragFile() -> URL? {
        guard let made = model.encodedNow(), let dragFolder, let file = try? CursorScreenshot.dragFile(made.data, as: made.format, name: name, in: dragFolder) else { return nil }
        return file
    }

    private func dragThumbnail() -> NSImage? {
        let side = CursorScreenshotCanvasMetrics.dragThumbnailSide
        let size = CursorScreenshotRender.placed(model.cropOutputSize, in: CGSize(width: side, height: side), backing: model.picture.scale).size
        guard let image = CursorScreenshotRender.exported(model.picture, edit: model.edit) else { return nil }
        return NSImage(cgImage: image, size: size)
    }

    private func saveAs() {
        guard !closing.isWaiting else { return }
        closing.start(CursorScreenshotCloseRequest(next: {}, cancelled: {}), asking: false)
        savePicture(then: closeAndGoOn, cancelled: stayOpen)
    }

    private func savePicture(then done: @escaping @MainActor () -> Void, cancelled: @escaping @MainActor () -> Void = {}) {
        model.commitText()
        let panel = NSSavePanel()
        let format = model.output().format
        let chooser = CursorScreenshotFormatChooser(panel: panel, format: format)
        panel.accessoryView = chooser.view
        panel.allowedContentTypes = [UTType(format.rawValue) ?? .png]
        panel.canCreateDirectories = true
        let folder = CursorScreenshotConfig.load().folderURL
        panel.nameFieldStringValue = name.freeFile(as: format, in: folder)
        panel.directoryURL = folder
        panel.beginSheetModal(for: window) { [self] answer in
            guard answer == .OK, let url = panel.url else { return cancelled() }
            Task {
                if await model.save(to: url, as: chooser.format) {
                    done()
                } else {
                    NSSound.beep()
                    cancelled()
                }
            }
        }
    }
}

@MainActor
final class CursorScreenshotFormatChooser: NSObject {
    let view: NSView
    private let menu: NSPopUpButton
    private let formats = CursorScreenshotFormat.writable
    private weak var panel: NSSavePanel?

    private static func title(_ format: CursorScreenshotFormat) -> String {
        switch format {
        case .jpeg: return MenuBarL("JPEG Image")
        case .png: return MenuBarL("PNG Image")
        case .heic: return MenuBarL("HEIC Image")
        case .webp: return MenuBarL("WebP Image")
        }
    }

    var format: CursorScreenshotFormat {
        formats.indices.contains(menu.indexOfSelectedItem) ? formats[menu.indexOfSelectedItem] : .png
    }

    init(panel: NSSavePanel, format: CursorScreenshotFormat) {
        self.panel = panel
        let label = NSTextField(labelWithString: MenuBarL("Format:"))
        menu = NSPopUpButton(frame: .zero, pullsDown: false)
        menu.addItems(withTitles: formats.map(Self.title))
        menu.selectItem(at: formats.firstIndex(of: format) ?? formats.firstIndex(of: .png) ?? 0)
        let row = NSStackView(views: [label, menu])
        row.orientation = .horizontal
        row.spacing = 8
        row.edgeInsets = NSEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        row.layoutSubtreeIfNeeded()
        row.setFrameSize(row.fittingSize)
        view = row
        super.init()
        menu.target = self
        menu.action = #selector(formatPicked)
    }

    @objc private func formatPicked() {
        guard let panel, let type = UTType(format.rawValue) else { return }
        panel.allowedContentTypes = [type]
        let name = panel.nameFieldStringValue as NSString
        let known = Set(CursorScreenshotFormat.allCases.map(\.fileExtension) + ["jpeg"])
        let base = known.contains(name.pathExtension.lowercased()) ? name.deletingPathExtension : name as String
        panel.nameFieldStringValue = "\(base).\(format.fileExtension)"
    }
}
