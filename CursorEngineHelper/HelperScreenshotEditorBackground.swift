import AppKit

private enum CursorScreenshotPanelMetrics {
    static let sideInset: CGFloat = 12
    static let topInset: CGFloat = 12
    static let sectionGap: CGFloat = 12
    static let captionHeight: CGFloat = 14
    static let captionGap: CGFloat = 4
    static let swatch: CGFloat = 16
    static let colorColumns = 9
    static let tileColumns = 6
    static let tileGap: CGFloat = 5
    static let tileHeight: CGFloat = 30
    static let tileRadius: CGFloat = 6
    static let pillHeight: CGFloat = 24
    static let rowHeight: CGFloat = 28
    static let leastLabelWidth: CGFloat = 54
    static let leastSliderWidth: CGFloat = 96
    static let rowGap: CGFloat = 8
    static let valueWidth: CGFloat = 26
    static let gridWidth: CGFloat = 86
    static let gridPadding: CGFloat = 2
    static let gridGap: CGFloat = 2
    static let gridTileHeight: CGFloat = 20
    static let gridRadius: CGFloat = 8
    static let gridTileRadius: CGFloat = 6
    static let gridDot: CGFloat = 5
    static let columnGap: CGFloat = 14
    static let chipGap: CGFloat = 6
    static let chipPadding: CGFloat = 12
    static let leastChipWidth: CGFloat = 48
    static let smallButton: CGFloat = 20
    static let ringGap: CGFloat = 1.5
    static let ringWidth: CGFloat = 2
    static let removeSide: CGFloat = 14
    static let panelWidth = CursorScreenshotBackgroundLook.panelWidth
    static let columnWidth = panelWidth - sideInset * 2 - gridWidth - columnGap
    @MainActor static let bodyFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
    @MainActor static let captionFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
    @MainActor static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
    @MainActor static let wordFont = NSFont.systemFont(ofSize: NSFont.labelFontSize, weight: .medium)
}

final class CursorScreenshotBackdropTile: CursorScreenshotBarButton {
    enum Kind { case swatch, tile, wheel, add }

    let backdrop: CursorScreenshotBackdropFill
    let kind: Kind
    var isCurrent = false {
        didSet {
            if isCurrent != oldValue { superview?.needsDisplay = true }
        }
    }
    var thumbnail: CGImage? {
        didSet {
            if thumbnail !== oldValue {
                wordIsLight = thumbnail.map(Self.isDark) ?? false
                needsDisplay = true
            }
        }
    }
    var word: String?
    var onRemove: (() -> Void)?
    var onDropFile: ((URL) -> Void)?
    private var wordIsLight = false

    var radius: CGFloat { kind == .tile || kind == .add ? CursorScreenshotPanelMetrics.tileRadius : bounds.height / 2 }

    init(label: String, backdrop: CursorScreenshotBackdropFill = .none, kind: Kind) {
        self.backdrop = backdrop
        self.kind = kind
        super.init(label: label)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func isDark(_ image: CGImage) -> Bool {
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CursorScreenshotPicture.sRGB,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return Int(pixel[0]) + Int(pixel[1]) + Int(pixel[2]) < 3 * 128
    }

    private var removeArea: CGRect {
        let side = CursorScreenshotPanelMetrics.removeSide
        return CGRect(x: bounds.maxX - side, y: 0, width: side, height: side)
    }

    override func mouseUp(with event: NSEvent) {
        if let onRemove, removeArea.contains(convert(event.locationInWindow, from: nil)) {
            releaseHold()
            return onRemove()
        }
        super.mouseUp(with: event)
    }

    func acceptDrops() {
        registerForDraggedTypes([.fileURL])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        isEnabled && CursorScreenshotImageSource.holdsWallpaper(sender.draggingPasteboard) ? .copy : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggingEntered(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let file = CursorScreenshotImageSource.wallpapers(on: sender.draggingPasteboard).first else { return false }
        onDropFile?(file)
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.setAlpha(isEnabled ? 1 : 0.4)
        let shape = CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)
        switch kind {
        case .add:
            let edge = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
            edge.setLineDash([3, 3], count: 2, phase: 0)
            CursorScreenshotEditorPalette.edge.setStroke()
            edge.stroke()
            let side: CGFloat = 12
            CursorScreenshotEditorIcon.plus.draw(in: CGRect(x: ((bounds.width - side) / 2).rounded(), y: ((bounds.height - side) / 2).rounded(), width: side, height: side), color: tint, on: context)
        case .wheel:
            CursorScreenshotSwatchWheel.draw(in: bounds, on: context)
        case .swatch, .tile:
            context.saveGState()
            context.addPath(shape)
            context.clip()
            if case .color(_, let alpha) = backdrop, alpha < 1 { CursorScreenshotCropLook.drawCheckers(in: bounds, on: context) }
            CursorScreenshotRender.paint(backdrop, image: thumbnail, in: bounds, on: context)
            context.restoreGState()
            context.addPath(CGPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), cornerWidth: radius - 0.5, cornerHeight: radius - 0.5, transform: nil))
            context.setStrokeColor(CursorScreenshotEditorPalette.separator.cgColor)
            context.setLineWidth(1)
            context.strokePath()
        }
        if let word {
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            style.lineBreakMode = .byWordWrapping
            let room = bounds.insetBy(dx: 4, dy: 0)
            let font = CursorScreenshotBackgroundLook.fittedFont(wrapping: word, font: CursorScreenshotPanelMetrics.wordFont, room: room.size)
            let line = NSAttributedString(string: word, attributes: [.font: font, .paragraphStyle: style,
                                                                     .foregroundColor: wordIsLight ? NSColor.white : NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.85)])
            let used = line.boundingRect(with: CGSize(width: room.width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading])
            line.draw(with: CGRect(x: room.minX, y: ((bounds.height - used.height) / 2).rounded(), width: room.width, height: used.height), options: [.usesLineFragmentOrigin, .usesFontLeading])
        }
        if onRemove != nil, isInside {
            let spot = removeArea.insetBy(dx: 1, dy: 1)
            NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.7).setFill()
            NSBezierPath(ovalIn: spot).fill()
            CursorScreenshotEditorIcon.close.draw(in: spot, color: .white, on: context)
        }
        context.restoreGState()
    }
}

enum CursorScreenshotSwatchWheel {
    private static let steps = 60

    static func draw(in rect: CGRect, on context: CGContext) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        for step in 0..<steps {
            let start = CGFloat(step) / CGFloat(steps)
            context.setFillColor(CursorScreenshotColor(hue: start, saturation: 1, brightness: 1).cgColor)
            context.move(to: center)
            context.addArc(center: center, radius: rect.width / 2, startAngle: start * 2 * .pi, endAngle: (start + 1.5 / CGFloat(steps)) * 2 * .pi, clockwise: false)
            context.closePath()
            context.fillPath()
        }
    }
}

final class CursorScreenshotAlignmentTile: CursorScreenshotBarButton {
    override func draw(_ dirtyRect: NSRect) {
        let look = CursorScreenshotPanelMetrics.self
        if isOn {
            NSColor.controlAccentColor.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: look.gridTileRadius, yRadius: look.gridTileRadius).fill()
        }
        (isOn ? NSColor.white : CursorScreenshotEditorPalette.muted).setFill()
        let dot = look.gridDot
        NSBezierPath(ovalIn: CGRect(x: ((bounds.width - dot) / 2).rounded(), y: ((bounds.height - dot) / 2).rounded(), width: dot, height: dot)).fill()
    }
}

final class CursorScreenshotBackgroundPage: NSView {
    var tiles: () -> [CursorScreenshotBackdropTile] = { [] }
    var grid: CGRect = .zero
    var rules: [CGFloat] = []

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let look = CursorScreenshotPanelMetrics.self
        CursorScreenshotEditorPalette.separator.setFill()
        for y in rules { CGRect(x: look.sideInset, y: y, width: bounds.width - look.sideInset * 2, height: 1).fill(using: .sourceOver) }
        CursorScreenshotEditorPalette.capsule.setFill()
        NSBezierPath(roundedRect: grid, xRadius: look.gridRadius, yRadius: look.gridRadius).fill()
        NSColor.controlAccentColor.setStroke()
        for tile in tiles() where tile.isCurrent && !tile.isHidden {
            let reach = look.ringGap + look.ringWidth / 2
            let ring = NSBezierPath(roundedRect: tile.frame.insetBy(dx: -reach, dy: -reach), xRadius: tile.radius + reach, yRadius: tile.radius + reach)
            ring.lineWidth = look.ringWidth
            ring.stroke()
        }
    }
}

@MainActor
enum CursorScreenshotBackgroundWords {
    static func color(_ index: Int) -> String {
        switch index {
        case 0: return MenuBarL("Black")
        case 1: return MenuBarL("White")
        case 2: return MenuBarL("Red")
        case 3: return MenuBarL("Orange")
        case 4: return MenuBarL("Yellow")
        case 5: return MenuBarL("Green")
        case 6: return MenuBarL("Blue")
        case 7: return MenuBarL("Violet")
        case 8: return MenuBarL("Transparent")
        case 9: return MenuBarL("Dark gray")
        case 10: return MenuBarL("Light gray")
        case 11: return MenuBarL("Pale red")
        case 12: return MenuBarL("Pale orange")
        case 13: return MenuBarL("Pale yellow")
        case 14: return MenuBarL("Pale green")
        case 15: return MenuBarL("Pale blue")
        default: return MenuBarL("Pale violet")
        }
    }

    static func gradient(_ index: Int) -> String {
        switch index {
        case 0: return MenuBarL("Cobalt")
        case 1: return MenuBarL("Blaze")
        case 2: return MenuBarL("Lime")
        case 3: return MenuBarL("Lagoon")
        case 4: return MenuBarL("Orchid")
        case 5: return MenuBarL("Graphite")
        case 6: return MenuBarL("Sand")
        case 7: return MenuBarL("Mist")
        case 8: return MenuBarL("Mint")
        case 9: return MenuBarL("Rose")
        case 10: return MenuBarL("Dusk")
        default: return MenuBarL("Night")
        }
    }

    static func place(_ index: Int) -> String {
        switch index {
        case 0: return MenuBarL("Top left")
        case 1: return MenuBarL("Top")
        case 2: return MenuBarL("Top right")
        case 3: return MenuBarL("Left")
        case 4: return MenuBarL("Center")
        case 5: return MenuBarL("Right")
        case 6: return MenuBarL("Bottom left")
        case 7: return MenuBarL("Bottom")
        default: return MenuBarL("Bottom right")
        }
    }

    static func preset(_ preset: CursorScreenshotPreset) -> String {
        switch preset.id {
        case "clean": return MenuBarL("Clean")
        case "soft": return MenuBarL("Soft")
        case "wide": return MenuBarL("Wide")
        default: return preset.name
        }
    }

    static func ratio(_ ratio: CursorScreenshotBackdropRatio) -> String {
        ratio == .auto ? MenuBarL("Auto") : ratio.rawValue
    }
}

@MainActor
enum CursorScreenshotBackgroundMenus {
    static func ratio(for model: CursorScreenshotEditorModel) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for ratio in CursorScreenshotBackdropRatio.allCases {
            if ratio == .fourFive { menu.addItem(.separator()) }
            let item = CursorScreenshotMenuItem(title: CursorScreenshotBackgroundWords.ratio(ratio)) { [weak model] in model?.setBackgroundRatio(ratio) }
            item.state = model.edit.background.ratio == ratio ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    static func presets(for model: CursorScreenshotEditorModel, actions: CursorScreenshotEditorActions) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let previous = CursorScreenshotMenuItem(title: MenuBarL("Apply Previous Settings")) { [weak model] in
            Task { await model?.applyPrevious() }
        }
        previous.isEnabled = model.library.previous != nil
        menu.addItem(previous)
        menu.addItem(.separator())
        let defaults = NSMenu()
        defaults.autoenablesItems = false
        let heading = NSMenuItem(title: MenuBarL("Automatically apply preset to all screenshots:"), action: nil, keyEquivalent: "")
        heading.isEnabled = false
        defaults.addItem(heading)
        defaults.addItem(.separator())
        let none = CursorScreenshotMenuItem(title: MenuBarL("None")) { [weak model] in model?.setDefaultPreset(nil) }
        none.state = model.library.defaultPreset == nil ? .on : .off
        defaults.addItem(none)
        for preset in model.library.presets {
            let item = CursorScreenshotMenuItem(title: CursorScreenshotBackgroundWords.preset(preset)) { [weak model] in model?.setDefaultPreset(preset.id) }
            item.state = model.library.defaultPreset == preset.id ? .on : .off
            defaults.addItem(item)
        }
        let holder = NSMenuItem(title: MenuBarL("Default Preset"), action: nil, keyEquivalent: "")
        holder.submenu = defaults
        menu.addItem(holder)
        menu.addItem(.separator())
        menu.addItem(CursorScreenshotMenuItem(title: MenuBarL("Add New Preset…")) { [weak model] in
            actions.namePreset { name in model?.addPreset(named: name) }
        })
        if model.isPresetChanged {
            menu.addItem(CursorScreenshotMenuItem(title: MenuBarL("Save changes")) { [weak model] in model?.saveShownPreset() })
        }
        if model.shownPreset != nil {
            menu.addItem(CursorScreenshotMenuItem(title: MenuBarL("Delete Preset")) { [weak model] in
                actions.confirmDeletePreset { model?.deleteShownPreset() }
            })
        }
        return menu
    }
}

final class CursorScreenshotBackgroundPanel: NSView {
    struct Row {
        let label: NSTextField
        let slider: CursorScreenshotEditorSlider
        let value: NSTextField
        let field: WritableKeyPath<CursorScreenshotBackgroundStyle, CGFloat>
    }

    private let model: CursorScreenshotEditorModel
    private let actions: CursorScreenshotEditorActions
    private let scroll = NSScrollView()
    private let page = CursorScreenshotBackgroundPage()
    let none = CursorScreenshotBarButton(label: MenuBarL("None"))
    private let colorsCaption = NSTextField(labelWithString: MenuBarL("Colors"))
    private let gradientsCaption = NSTextField(labelWithString: MenuBarL("Gradients"))
    private let wallpapersCaption = NSTextField(labelWithString: MenuBarL("Wallpapers"))
    private let alignmentCaption = NSTextField(labelWithString: MenuBarL("Alignment"))
    private let ratioCaption = NSTextField(labelWithString: MenuBarL("Ratio"))
    private let presetsCaption = NSTextField(labelWithString: MenuBarL("Presets"))
    private(set) var colorTiles: [CursorScreenshotBackdropTile] = []
    let wheel = CursorScreenshotBackdropTile(label: MenuBarL("Custom Color…"), kind: .wheel)
    private(set) var gradientTiles: [CursorScreenshotBackdropTile] = []
    let desktop = CursorScreenshotBackdropTile(label: MenuBarL("Desktop picture"), backdrop: .desktop, kind: .tile)
    private(set) var wallpaperTiles: [CursorScreenshotBackdropTile] = []
    let addWallpaper = CursorScreenshotBackdropTile(label: MenuBarL("Add wallpaper"), kind: .add)
    private(set) var blurTiles: [CursorScreenshotBackdropTile] = []
    private(set) var rows: [Row] = []
    private(set) var placeTiles: [CursorScreenshotAlignmentTile] = []
    let ratio = CursorScreenshotBarButton(label: MenuBarL("Ratio"))
    let balance = CursorScreenshotBarButton(label: MenuBarL("Auto Balance"))
    private(set) var presetChips: [(id: String, button: CursorScreenshotBarButton)] = []
    let addPreset = CursorScreenshotBarButton(label: MenuBarL("Save as new preset"), parts: [.icon(.plus, 12)])
    let savePreset = CursorScreenshotBarButton(label: MenuBarL("Save changes"), parts: [.icon(.check, 12)])
    let presetMenu = CursorScreenshotBarButton(label: MenuBarL("Preset options"), parts: [.icon(.chevron, CursorScreenshotEditorMetrics.chevron)])

    init(model: CursorScreenshotEditorModel, actions: CursorScreenshotEditorActions) {
        self.model = model
        self.actions = actions
        super.init(frame: .zero)
        scroll.documentView = page
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        addSubview(scroll)
        page.tiles = { [unowned self] in self.colorTiles + [self.wheel] + self.gradientTiles + [self.desktop] + self.wallpaperTiles + self.blurTiles }
        buildPicks()
        buildControls()
        refresh()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    private func pick(_ fill: CursorScreenshotBackdropFill) {
        Task { [model] in
            if await !model.pickBackdrop(fill) { NSSound.beep() }
        }
    }

    private func install(_ tile: CursorScreenshotBackdropTile) {
        tile.onPress = { [weak self, weak tile] in
            guard let self, let tile else { return }
            self.pick(tile.backdrop)
        }
        page.addSubview(tile)
    }

    private func buildPicks() {
        for (index, hex) in CursorScreenshotBackdrops.colors.enumerated() {
            let fill: CursorScreenshotBackdropFill = hex.map { .color($0, 1) } ?? .transparent
            let tile = CursorScreenshotBackdropTile(label: CursorScreenshotBackgroundWords.color(index), backdrop: fill, kind: .swatch)
            install(tile)
            colorTiles.append(tile)
        }
        wheel.onPress = { [weak self] in self?.openColorPanel() }
        page.addSubview(wheel)
        for index in 0..<CursorScreenshotBackdropFill.gradientCount {
            let tile = CursorScreenshotBackdropTile(label: CursorScreenshotBackgroundWords.gradient(index), backdrop: .gradient(index), kind: .tile)
            install(tile)
            gradientTiles.append(tile)
        }
        install(desktop)
        addWallpaper.onPress = { [actions] in actions.chooseWallpaper() }
        addWallpaper.acceptDrops()
        addWallpaper.onDropFile = { [model] file in
            Task {
                if await !model.addWallpaper(from: file) { NSSound.beep() }
            }
        }
        page.addSubview(addWallpaper)
        for (fill, word) in [(CursorScreenshotBackdropFill.blurredDesktop, MenuBarL("Blurred desktop")), (.blurredPicture, MenuBarL("Blurred picture")), (.blurredPictureDark, MenuBarL("Dark blur"))] {
            let tile = CursorScreenshotBackdropTile(label: word, backdrop: fill, kind: .tile)
            tile.word = word
            install(tile)
            blurTiles.append(tile)
        }
    }

    private func buildControls() {
        let look = CursorScreenshotPanelMetrics.self
        let bar = CursorScreenshotEditorMetrics.self
        for caption in [colorsCaption, gradientsCaption, wallpapersCaption, alignmentCaption, ratioCaption, presetsCaption] {
            caption.font = look.captionFont
            caption.textColor = CursorScreenshotEditorPalette.label
            caption.lineBreakMode = .byTruncatingTail
            page.addSubview(caption)
        }
        none.parts = [.title(MenuBarL("None"), look.bodyFont)]
        none.fill = CursorScreenshotEditorPalette.button
        none.outline = CursorScreenshotEditorPalette.separator
        none.onPress = { [weak model] in model?.clearBackground() }
        page.addSubview(none)
        let sliders: [(String, ClosedRange<CGFloat>, WritableKeyPath<CursorScreenshotBackgroundStyle, CGFloat>)] = [
            (MenuBarL("Padding"), CursorScreenshotBackgroundStyle.paddingRange, \.padding), (MenuBarL("Corners"), CursorScreenshotBackgroundStyle.cornersRange, \.corners),
            (MenuBarL("Shadow"), CursorScreenshotBackgroundStyle.shadowRange, \.shadow), (MenuBarL("Inset"), CursorScreenshotBackgroundStyle.insetRange, \.inset)
        ]
        for (word, range, field) in sliders {
            let label = CursorScreenshotBackgroundLook.sliderLabel(word, font: look.bodyFont)
            label.textColor = CursorScreenshotEditorPalette.foreground
            let value = NSTextField(labelWithString: "0")
            value.font = look.valueFont
            value.textColor = CursorScreenshotEditorPalette.label
            value.alignment = .right
            let slider = CursorScreenshotEditorSlider(label: word, range: range, value: range.lowerBound, first: nil)
            slider.onSlide = { [weak model] in model?.setBackgroundValue(field, $0, range: range) }
            slider.onHold = { [weak model] in model?.holdChange($0) }
            for view in [label, slider, value] as [NSView] { page.addSubview(view) }
            rows.append(Row(label: label, slider: slider, value: value, field: field))
        }
        for index in 0..<9 {
            let tile = CursorScreenshotAlignmentTile(label: CursorScreenshotBackgroundWords.place(index))
            tile.onPress = { [weak model] in model?.setBackgroundAlignment(index) }
            page.addSubview(tile)
            placeTiles.append(tile)
        }
        ratio.fill = CursorScreenshotEditorPalette.button
        ratio.outline = CursorScreenshotEditorPalette.separator
        ratio.spreads = true
        ratio.sidePadding = bar.bottomLeft
        ratio.onPress = { [weak self] in
            guard let self else { return }
            let menu = CursorScreenshotBackgroundMenus.ratio(for: self.model)
            menu.popUp(positioning: menu.items.first { $0.state == .on }, at: NSPoint(x: 0, y: self.ratio.bounds.height), in: self.ratio)
        }
        page.addSubview(ratio)
        balance.parts = [.title(MenuBarL("Auto Balance"), CursorScreenshotBackgroundLook.fittedFont(MenuBarL("Auto Balance"), font: look.bodyFont, width: look.columnWidth, padding: look.chipPadding / 2))]
        balance.fill = CursorScreenshotEditorPalette.button
        balance.outline = CursorScreenshotEditorPalette.separator
        balance.onPress = { [weak model] in
            guard let model else { return }
            Task { await model.setAutoBalance(!model.edit.background.autoBalance) }
        }
        page.addSubview(balance)
        addPreset.fill = CursorScreenshotEditorPalette.button
        addPreset.outline = CursorScreenshotEditorPalette.separator
        addPreset.onPress = { [weak model, actions] in
            actions.namePreset { name in model?.addPreset(named: name) }
        }
        savePreset.hoverFill = CursorScreenshotEditorPalette.hover
        savePreset.onPress = { [weak model] in model?.saveShownPreset() }
        presetMenu.hoverFill = CursorScreenshotEditorPalette.hover
        presetMenu.onPress = { [weak self] in
            guard let self else { return }
            let menu = CursorScreenshotBackgroundMenus.presets(for: self.model, actions: self.actions)
            menu.popUp(positioning: menu.items.first, at: NSPoint(x: 0, y: self.presetMenu.bounds.height), in: self.presetMenu)
        }
        for button in [addPreset, savePreset, presetMenu] { page.addSubview(button) }
    }

    func refresh() {
        let look = CursorScreenshotPanelMetrics.self
        let style = model.edit.background
        let thumbnails = model.backdropThumbnails
        let picks = colorTiles + gradientTiles + [desktop] + wallpaperTiles + blurTiles
        for tile in picks { tile.isCurrent = tile.backdrop == style.fill }
        if case .color = style.fill { wheel.isCurrent = !colorTiles.contains { $0.isCurrent } } else { wheel.isCurrent = false }
        CursorScreenshotSystemColors.follow(style.fill.plainColor, for: self, action: #selector(colorPicked(_:)))
        syncWallpapers()
        for tile in [desktop] + wallpaperTiles + blurTiles {
            tile.thumbnail = thumbnails[tile.backdrop]
            tile.isEnabled = tile.thumbnail != nil
        }
        addWallpaper.isHidden = model.library.wallpapers.count >= CursorScreenshotBackgroundLibrary.wallpaperLimit
        for row in rows {
            row.slider.value = style[keyPath: row.field]
            row.value.stringValue = String(Int(style[keyPath: row.field].rounded()))
        }
        for (index, tile) in placeTiles.enumerated() { tile.isOn = index == style.alignment }
        ratio.parts = [.title(CursorScreenshotBackgroundWords.ratio(style.ratio), look.bodyFont), .icon(.chevron, CursorScreenshotEditorMetrics.chevron)]
        balance.isOn = style.autoBalance
        syncPresets()
        needsLayout = true
    }

    private func syncWallpapers() {
        let ids = model.library.wallpapers
        guard wallpaperTiles.compactMap({ tile -> String? in
            if case .wallpaper(let id) = tile.backdrop { return id }
            return nil
        }) != ids else { return }
        wallpaperTiles.forEach { $0.removeFromSuperview() }
        wallpaperTiles = ids.map { id in
            let tile = CursorScreenshotBackdropTile(label: MenuBarL("Wallpaper"), backdrop: .wallpaper(id), kind: .tile)
            install(tile)
            tile.onRemove = { [weak model] in model?.removeWallpaper(id) }
            let remove = NSAccessibilityCustomAction(name: MenuBarL("Remove wallpaper")) { [weak model] in
                model?.removeWallpaper(id)
                return true
            }
            tile.setAccessibilityCustomActions([remove])
            return tile
        }
    }

    private func syncPresets() {
        let look = CursorScreenshotPanelMetrics.self
        let presets = model.library.presets
        if presetChips.map(\.id) != presets.map(\.id) {
            presetChips.forEach { $0.button.removeFromSuperview() }
            presetChips = presets.map { preset in
                let chip = CursorScreenshotBarButton(label: CursorScreenshotBackgroundWords.preset(preset))
                chip.fill = CursorScreenshotEditorPalette.button
                chip.outline = CursorScreenshotEditorPalette.separator
                chip.onPress = { [weak model] in
                    guard let model, let chosen = model.library.presets.first(where: { $0.id == preset.id }) else { return }
                    Task { await model.applyPreset(chosen) }
                }
                page.addSubview(chip)
                return (preset.id, chip)
            }
        }
        let shown = model.shownPreset?.id
        for (id, chip) in presetChips {
            guard let preset = presets.first(where: { $0.id == id }) else { continue }
            let changed = id == shown && model.isPresetChanged
            chip.parts = [.title(CursorScreenshotBackgroundWords.preset(preset) + (changed ? "*" : ""), look.bodyFont)]
            chip.isOn = id == shown
        }
        savePreset.isHidden = !model.isPresetChanged
    }

    @discardableResult
    private func placeAll() -> CGFloat {
        let look = CursorScreenshotPanelMetrics.self
        let left = look.sideInset
        let wide = look.panelWidth - left * 2
        var y = look.topInset
        none.frame = CGRect(x: left, y: y, width: wide, height: look.pillHeight)
        y += look.pillHeight + look.sectionGap
        let caption = { (field: NSTextField, x: CGFloat, width: CGFloat) in
            field.frame = CGRect(x: x, y: y, width: width, height: look.captionHeight)
        }
        caption(colorsCaption, left, wide)
        y += look.captionHeight + look.captionGap
        let colorColumn = (wide - look.tileGap * CGFloat(look.colorColumns - 1)) / CGFloat(look.colorColumns)
        for (index, tile) in (colorTiles + [wheel]).enumerated() {
            let column = CGFloat(index % look.colorColumns)
            let row = CGFloat(index / look.colorColumns)
            tile.frame = CGRect(x: (left + column * (colorColumn + look.tileGap) + (colorColumn - look.swatch) / 2).rounded(), y: y + row * (look.swatch + look.tileGap), width: look.swatch, height: look.swatch)
        }
        y += look.swatch * 2 + look.tileGap + look.sectionGap
        caption(gradientsCaption, left, wide)
        y += look.captionHeight + look.captionGap
        let tileWidth = (wide - look.tileGap * CGFloat(look.tileColumns - 1)) / CGFloat(look.tileColumns)
        let tileFrame = { (column: Int, row: Int, span: Int, top: CGFloat) in
            CGRect(x: left + CGFloat(column) * (tileWidth + look.tileGap), y: top + CGFloat(row) * (look.tileHeight + look.tileGap),
                   width: tileWidth * CGFloat(span) + look.tileGap * CGFloat(span - 1), height: look.tileHeight)
        }
        for (index, tile) in gradientTiles.enumerated() { tile.frame = tileFrame(index % look.tileColumns, index / look.tileColumns, 1, y) }
        y += look.tileHeight * 2 + look.tileGap + look.sectionGap
        caption(wallpapersCaption, left, wide)
        y += look.captionHeight + look.captionGap
        let shelf = [desktop] + wallpaperTiles + (addWallpaper.isHidden ? [] : [addWallpaper])
        for (index, tile) in shelf.enumerated() { tile.frame = tileFrame(index, 0, 1, y) }
        for (index, tile) in blurTiles.enumerated() { tile.frame = tileFrame(index * 2, 1, 2, y) }
        y += look.tileHeight * 2 + look.tileGap + look.sectionGap
        var rules = [y]
        y += 1 + look.sectionGap
        let oneLine = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        let labelWidth = min(max(look.leastLabelWidth, rows.map { ceil($0.label.sizeThatFits(oneLine).width) }.max() ?? 0), wide - look.leastSliderWidth - look.valueWidth - look.rowGap * 2)
        for row in rows {
            let middle = y + look.rowHeight / 2
            let labelHigh = ceil(row.label.sizeThatFits(NSSize(width: labelWidth, height: .greatestFiniteMagnitude)).height)
            let valueHigh = ceil(row.value.intrinsicContentSize.height)
            row.label.frame = CGRect(x: left, y: (middle - labelHigh / 2).rounded(), width: labelWidth, height: labelHigh)
            row.value.frame = CGRect(x: left + wide - look.valueWidth, y: (middle - valueHigh / 2).rounded(), width: look.valueWidth, height: valueHigh)
            let sliderX = left + labelWidth + look.rowGap
            row.slider.frame = CGRect(x: sliderX, y: y, width: left + wide - look.valueWidth - look.rowGap - sliderX, height: look.rowHeight)
            y += look.rowHeight
        }
        y += look.sectionGap
        rules.append(y)
        y += 1 + look.sectionGap
        let columnX = left + look.gridWidth + look.columnGap
        let columnWidth = look.columnWidth
        caption(alignmentCaption, left, look.gridWidth + look.columnGap)
        caption(ratioCaption, columnX, columnWidth)
        y += look.captionHeight + look.captionGap
        let gridTile = (look.gridWidth - look.gridPadding * 2 - look.gridGap * 2) / 3
        let gridHeight = look.gridPadding * 2 + look.gridTileHeight * 3 + look.gridGap * 2
        page.grid = CGRect(x: left, y: y, width: look.gridWidth, height: gridHeight)
        for (index, tile) in placeTiles.enumerated() {
            tile.frame = CGRect(x: left + look.gridPadding + CGFloat(index % 3) * (gridTile + look.gridGap), y: y + look.gridPadding + CGFloat(index / 3) * (look.gridTileHeight + look.gridGap),
                                width: gridTile, height: look.gridTileHeight)
        }
        ratio.frame = CGRect(x: columnX, y: y, width: columnWidth, height: look.pillHeight)
        balance.frame = CGRect(x: columnX, y: y + gridHeight - look.pillHeight, width: columnWidth, height: look.pillHeight)
        y += gridHeight + look.sectionGap
        rules.append(y)
        page.rules = rules
        y += 1 + look.sectionGap
        caption(presetsCaption, left, wide - look.smallButton * 2)
        presetMenu.frame = CGRect(x: left + wide - look.smallButton, y: y - 3, width: look.smallButton, height: look.smallButton)
        savePreset.frame = CGRect(x: presetMenu.frame.minX - look.smallButton, y: y - 3, width: look.smallButton, height: look.smallButton)
        y += look.captionHeight + look.captionGap
        var x = left
        for (_, chip) in presetChips {
            let width = min(max(look.leastChipWidth, chip.fittingWidth - CursorScreenshotEditorMetrics.titlePadding * 2 + look.chipPadding), wide)
            if x > left, x + width > left + wide {
                x = left
                y += look.pillHeight + look.chipGap
            }
            chip.frame = CGRect(x: x, y: y, width: width, height: look.pillHeight)
            x += width + look.chipGap
        }
        if x > left, x + look.pillHeight > left + wide {
            x = left
            y += look.pillHeight + look.chipGap
        }
        addPreset.frame = CGRect(x: x, y: y, width: look.pillHeight, height: look.pillHeight)
        y += look.pillHeight + look.topInset
        return y
    }

    var fittingHeight: CGFloat { placeAll() }

    override func layout() {
        super.layout()
        scroll.frame = bounds
        let high = placeAll()
        page.frame = CGRect(x: 0, y: 0, width: bounds.width, height: max(high, bounds.height))
        page.needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        CursorScreenshotEditorPalette.backgroundPanel.setFill()
        bounds.fill()
        CursorScreenshotEditorPalette.separator.setFill()
        CGRect(x: bounds.maxX - 1, y: 0, width: 1, height: bounds.height).fill(using: .sourceOver)
    }

    private func openColorPanel() {
        CursorScreenshotSystemColors.take(for: self, action: #selector(colorPicked(_:)), current: model.edit.background.fill.plainColor)
        NSColorPanel.shared.orderFront(nil)
    }

    func closeColorPanel() {
        CursorScreenshotSystemColors.close(for: self)
    }

    @objc private func colorPicked(_ sender: NSColorPanel) {
        guard let color = CursorScreenshotSystemColors.color(of: sender) else { return }
        model.pickColor(color)
    }
}
