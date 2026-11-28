import AppKit

extension Notification.Name {
    nonisolated static let MACCursorHighlightDidChange = Notification.Name("MACCursorHighlightDidChange")
    nonisolated static let MACCursorMagnifierShowAccessWindow = Notification.Name("MACCursorMagnifierShowAccessWindow")
}

enum CursorHighlightLook: String, Codable, CaseIterable {
    case ripple, ring, pulse, circle, burst

    var drawsLine: Bool {
        self == .ripple || self == .ring || self == .pulse
    }

    var duration: TimeInterval {
        switch self {
        case .ripple: return CursorHighlight.ringLife + 2 * CursorHighlight.ringGap
        case .burst: return CursorHighlight.burstLife
        case .ring, .pulse, .circle: return CursorHighlight.ringLife
        }
    }
}

struct CursorHighlightConfig: Codable, Equatable {
    static let sizes = 50...600
    static let dims = 10...90
    static let edges = 0...200
    static let rippleSizes = 10...200
    static let grows = 1.0...6.0
    static let lineWidths = 1...12
    static let opacities = 10...100
    static let flashlightDim: CGFloat = 0.95
    static let zooms = 1.5...6.0
    static let lenses = 120...520

    var enabled = false
    var spotlight = false
    var flashlight = false
    var size = 200
    var dim = 60
    var edge = 40
    var color: UInt32 = 0x000000
    var ripple = true
    var look = CursorHighlightLook.ripple
    var rippleSize = 40
    var grow = 3.0
    var lineWidth = 3
    var opacity = 80
    var leftColor: UInt32 = 0x007AFF
    var rightColor: UInt32 = 0xFF9500
    var shortcut: KeyboardShortcutData?
    var magnifier = false
    var zoom = 2.0
    var lens = 240
    var magnifierKey: KeyboardShortcutData?
    var spotlightKey: KeyboardShortcutData?
    var spotlightClick = CursorGestureTrigger()
    var flashlightKey: KeyboardShortcutData?
    var flashlightClick = CursorGestureTrigger()
    var magnifierClick = CursorGestureTrigger()

    private static var triggerRows: [(id: UInt32, key: WritableKeyPath<CursorHighlightConfig, KeyboardShortcutData?>,
                                      click: WritableKeyPath<CursorHighlightConfig, CursorGestureTrigger>, flag: WritableKeyPath<CursorHighlightConfig, Bool>)] {
        [(CursorHighlight.spotlightHotKeyID, \.spotlightKey, \.spotlightClick, \.spotlight),
         (CursorHighlight.flashlightHotKeyID, \.flashlightKey, \.flashlightClick, \.flashlight),
         (CursorMagnifier.hotKeyID, \.magnifierKey, \.magnifierClick, \.magnifier)]
    }

    var keys: [KeyboardShortcutData] { keys(besides: nil) }

    func keys(besides field: WritableKeyPath<CursorHighlightConfig, KeyboardShortcutData?>?) -> [KeyboardShortcutData] {
        ([\.shortcut] + Self.triggerRows.map(\.key)).filter { $0 != field }.compactMap { self[keyPath: $0] }
    }

    var triggers: [CursorGestureTrigger] { Self.triggerRows.map { self[keyPath: $0.click] } }

    var showsMagnifier: Bool { enabled && magnifier }

    var hotKeys: [(id: UInt32, key: KeyboardShortcutData)] {
        guard enabled else { return [] }
        return Self.triggerRows.compactMap { row in
            self[keyPath: row.key].flatMap { MACCaptureShortcutIsAllowed($0.modifierFlagsRaw, $0.keyCode) ? (row.id, $0) : nil }
        }
    }

    var clicks: [(id: UInt32, trigger: CursorGestureTrigger)] {
        guard enabled else { return [] }
        return Self.triggerRows.map { ($0.id, self[keyPath: $0.click]) }.filter { CursorTranslator.usable($0.trigger) }
    }

    func pressed(_ id: UInt32) -> CursorHighlightConfig? {
        guard enabled, let row = Self.triggerRows.first(where: { $0.id == id }) else { return nil }
        var next = self
        if row.flag == \CursorHighlightConfig.flashlight, !spotlight {
            next.spotlight = true
            next.flashlight = true
        } else {
            next[keyPath: row.flag].toggle()
        }
        return next
    }

    func heldElsewhere(_ candidate: KeyboardShortcutData, besides field: WritableKeyPath<CursorHighlightConfig, KeyboardShortcutData?>,
                       favorites: Any? = MACPreferences.value(forKey: MACPreferences.favoriteCursorsKey),
                       shaker: CursorShakerConfig = .load(), capture: CursorScreenshotConfig = .load(), board: CursorBoardConfig = .load(),
                       translator: CursorTranslatorConfig = .load()) -> Bool {
        let held = MACFavoriteKeys(favorites) + [shaker.shortcut, translator.shortcut].compactMap { $0 } + capture.keys(besides: nil) + board.keys(besides: nil)
        return CursorScreenshot.refuses(candidate, held: held + keys(besides: field))
    }

    func isTaken(_ next: CursorTrigger, key field: WritableKeyPath<CursorHighlightConfig, KeyboardShortcutData?>, click: WritableKeyPath<CursorHighlightConfig, CursorGestureTrigger>,
                 favorites: Any? = MACPreferences.value(forKey: MACPreferences.favoriteCursorsKey),
                 shaker: CursorShakerConfig = .load(), capture: CursorScreenshotConfig = .load(), board: CursorBoardConfig = .load(),
                 translator: CursorTranslatorConfig = .load()) -> Bool {
        let clicks = [capture.wholeScreenClick, capture.areaClick, capture.repeatClick, capture.textClick, capture.selfTimerClick, translator.trigger]
            + board.triggers + Self.triggerRows.filter { $0.click != click }.map { self[keyPath: $0.click] }
        return (next.key != self[keyPath: field]
                && next.key.map { heldElsewhere($0, besides: field, favorites: favorites, shaker: shaker, capture: capture, board: board, translator: translator) } == true)
            || (next.click != self[keyPath: click] && CursorScreenshot.refuses(next.click, held: clicks))
    }

    var lightSize: CGFloat { CGFloat(size) / (flashlight ? 2 : 1) }

    var dimAlpha: CGFloat { flashlight ? Self.flashlightDim : CGFloat(dim) / 100 }

    var side: CGFloat { lightSize + 2 * CGFloat(edge) }

    var showsSpotlight: Bool { enabled && spotlight }

    var showsRipple: Bool { enabled && ripple }

    static func load() -> CursorHighlightConfig {
        CFPreferencesSynchronize(MACPreferences.domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        guard let data = MACPreferences.value(forKey: MACPreferences.cursorHighlightKey) as? Data,
              let config = try? JSONDecoder().decode(CursorHighlightConfig.self, from: data) else { return CursorHighlightConfig() }
        return config
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        MACPreferences.set(data, forKey: MACPreferences.cursorHighlightKey)
        CursorHighlightConfig.notifyHelper()
    }

    static func notifyHelper() {
        DistributedNotificationCenter.default().postNotificationName(.MACCursorHighlightDidChange, object: nil,
                                                                     userInfo: nil, deliverImmediately: true)
    }

    static func set(_ key: WritableKeyPath<CursorHighlightConfig, Bool>, _ value: Bool) {
        var config = load()
        guard config[keyPath: key] != value else { return }
        config[keyPath: key] = value
        config.save()
    }

    func canSet(_ key: WritableKeyPath<CursorHighlightConfig, Bool>) -> Bool {
        key == \CursorHighlightConfig.enabled || enabled && (key != \CursorHighlightConfig.flashlight || spotlight)
    }
}

extension CursorHighlightConfig {
    init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func flag(_ key: CodingKeys, _ fallback: Bool) -> Bool {
            (try? container.decode(Bool.self, forKey: key)) ?? fallback
        }
        func clamped(_ key: CodingKeys, to range: ClosedRange<Int>, or fallback: Int) -> Int {
            min(max((try? container.decode(Int.self, forKey: key)) ?? fallback, range.lowerBound), range.upperBound)
        }
        func colour(_ key: CodingKeys, or fallback: UInt32) -> UInt32 {
            (try? container.decode(UInt32.self, forKey: key)).flatMap { $0 <= 0xFFFFFF ? $0 : nil } ?? fallback
        }
        enabled = flag(.enabled, enabled)
        spotlight = flag(.spotlight, spotlight)
        flashlight = flag(.flashlight, flashlight)
        size = clamped(.size, to: Self.sizes, or: size)
        dim = clamped(.dim, to: Self.dims, or: dim)
        edge = clamped(.edge, to: Self.edges, or: edge)
        color = colour(.color, or: color)
        ripple = flag(.ripple, ripple)
        look = (try? container.decode(CursorHighlightLook.self, forKey: .look)) ?? look
        rippleSize = clamped(.rippleSize, to: Self.rippleSizes, or: rippleSize)
        let grown = (try? container.decode(Double.self, forKey: .grow)).flatMap { $0.isFinite ? $0 : nil } ?? grow
        grow = (min(max(grown, Self.grows.lowerBound), Self.grows.upperBound) * 2).rounded() / 2
        lineWidth = clamped(.lineWidth, to: Self.lineWidths, or: lineWidth)
        opacity = clamped(.opacity, to: Self.opacities, or: opacity)
        leftColor = colour(.leftColor, or: leftColor)
        rightColor = colour(.rightColor, or: rightColor)
        shortcut = try? container.decode(KeyboardShortcutData.self, forKey: .shortcut)
        magnifier = flag(.magnifier, magnifier)
        let zoomed = (try? container.decode(Double.self, forKey: .zoom)).flatMap { $0.isFinite ? $0 : nil } ?? zoom
        zoom = (min(max(zoomed, Self.zooms.lowerBound), Self.zooms.upperBound) * 2).rounded() / 2
        lens = clamped(.lens, to: Self.lenses, or: lens)
        magnifierKey = try? container.decode(KeyboardShortcutData.self, forKey: .magnifierKey)
        spotlightKey = try? container.decode(KeyboardShortcutData.self, forKey: .spotlightKey)
        spotlightClick = (try? container.decode(CursorGestureTrigger.self, forKey: .spotlightClick)) ?? spotlightClick
        flashlightKey = try? container.decode(KeyboardShortcutData.self, forKey: .flashlightKey)
        flashlightClick = (try? container.decode(CursorGestureTrigger.self, forKey: .flashlightClick)) ?? flashlightClick
        magnifierClick = (try? container.decode(CursorGestureTrigger.self, forKey: .magnifierClick)) ?? magnifierClick
    }
}

struct CursorHighlightSpotlight: Equatable {
    let hole: CGRect
    let bands: [CGRect]

    static func layout(tip: CGPoint, side: CGFloat, window: CGRect, scale: CGFloat) -> CursorHighlightSpotlight {
        func snapped(_ value: CGFloat) -> CGFloat { (value * scale).rounded() / scale }
        let hole = CGRect(x: snapped(tip.x - window.minX - side / 2), y: snapped(tip.y - window.minY - side / 2), width: side, height: side)
        let bounds = CGRect(origin: .zero, size: window.size)
        let shown = hole.intersection(bounds)
        guard !shown.isNull, !shown.isEmpty else { return CursorHighlightSpotlight(hole: hole, bands: [bounds, .zero, .zero, .zero]) }
        return CursorHighlightSpotlight(hole: hole, bands: [
            CGRect(x: 0, y: 0, width: bounds.width, height: shown.minY),
            CGRect(x: 0, y: shown.maxY, width: bounds.width, height: bounds.height - shown.maxY),
            CGRect(x: 0, y: shown.minY, width: shown.minX, height: shown.height),
            CGRect(x: shown.maxX, y: shown.minY, width: bounds.width - shown.maxX, height: shown.height),
        ])
    }

    static func hole(_ config: CursorHighlightConfig, scale: CGFloat) -> CGImage? {
        let pixels = Int((config.side * scale).rounded())
        guard let context = MACCursorShadow.makeContext(width: pixels, height: pixels) else { return nil }
        let dim = CursorTrailsPalette.color(at: 0, stops: [config.color], alpha: config.dimAlpha)
        let middle = CGPoint(x: CGFloat(pixels) / 2, y: CGFloat(pixels) / 2)
        let light = config.lightSize / 2 * scale
        context.setFillColor(dim)
        context.fill(CGRect(x: 0, y: 0, width: pixels, height: pixels))
        guard config.edge > 0 else {
            context.setBlendMode(.copy)
            context.setFillColor(CursorTrailsPalette.color(at: 0, stops: [config.color], alpha: 0))
            context.fillEllipse(in: CGRect(x: middle.x - light, y: middle.y - light, width: 2 * light, height: 2 * light))
            return context.makeImage()
        }
        let colors = [CursorTrailsPalette.color(at: 0, stops: [config.color], alpha: 0), dim] as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1]) else { return nil }
        context.setBlendMode(.copy)
        context.drawRadialGradient(gradient, startCenter: middle, startRadius: light, endCenter: middle,
                                   endRadius: light + CGFloat(config.edge) * scale, options: [.drawsBeforeStartLocation])
        return context.makeImage()
    }
}

struct CursorHighlightRipple: Equatable {
    let point: CGPoint
    let time: TimeInterval
    let right: Bool

    func frame(_ config: CursorHighlightConfig) -> CGRect {
        let side = CGFloat(config.rippleSize) * config.grow + CGFloat(config.lineWidth)
        return CGRect(x: point.x - side / 2, y: point.y - side / 2, width: side, height: side)
    }

    func picture(at now: TimeInterval, config: CursorHighlightConfig, scale: CGFloat) -> CGImage? {
        let age = now - time
        guard age >= 0, age <= config.look.duration else { return nil }
        let pixels = Int((frame(config).width * scale).rounded(.up))
        guard let context = MACCursorShadow.makeContext(width: pixels, height: pixels) else { return nil }
        let middle = CGPoint(x: CGFloat(pixels) / 2, y: CGFloat(pixels) / 2)
        let hex = right ? config.rightColor : config.leftColor
        let opacity = CGFloat(config.opacity) / 100
        let small = CGFloat(config.rippleSize) / 2 * scale
        let big = small * config.grow
        func eased(_ time: TimeInterval, _ life: TimeInterval) -> CGFloat {
            1 - pow(1 - CGFloat(time / life), 2)
        }
        func disc(_ radius: CGFloat) -> CGRect {
            CGRect(x: middle.x - radius, y: middle.y - radius, width: 2 * radius, height: 2 * radius)
        }
        func ring(_ radius: CGFloat, fade: CGFloat) {
            guard radius > 0.5 else { return }
            context.setStrokeColor(CursorTrailsPalette.color(at: 0, stops: [hex], alpha: opacity * fade))
            context.setLineWidth(CGFloat(config.lineWidth) * scale)
            context.strokeEllipse(in: disc(radius))
        }
        let life = CursorHighlight.ringLife
        switch config.look {
        case .ring:
            ring(small + (big - small) * eased(age, life), fade: 1 - CGFloat(age / life))
        case .ripple:
            for wave in 0..<3 {
                let time = age - Double(wave) * CursorHighlight.ringGap
                guard (0...life).contains(time) else { continue }
                ring(small + (big - small) * eased(time, life), fade: 1 - CGFloat(time / life))
            }
        case .pulse:
            ring(big * (1 - eased(age, life)), fade: 1 - CGFloat(age / life))
        case .circle:
            context.setFillColor(CursorTrailsPalette.color(at: 0, stops: [hex], alpha: 0.35 * opacity * (1 - CGFloat(age / life))))
            context.fillEllipse(in: disc(small + (big - small) * eased(age, life)))
        case .burst:
            let burst = CursorHighlight.burstLife
            let colors = [CGFloat(1), 0].map { CursorTrailsPalette.color(at: 0, stops: [hex], alpha: $0 * opacity * (1 - CGFloat(age / burst))) } as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1]) else { return nil }
            context.drawRadialGradient(gradient, startCenter: middle, startRadius: 0, endCenter: middle,
                                       endRadius: small + (big - small) * eased(age, burst), options: [])
        }
        return context.makeImage()
    }
}

enum CursorMagnifierStep: Equatable {
    case stop, hide, ask, show
}

enum CursorMagnifier {
    static let hotKeyID = CursorShaker.hotKeyID - 10

    static func step(_ config: CursorHighlightConfig, before: CursorHighlightConfig, paused: Bool, hidden: Bool, shown: Bool, allowed: @autoclosure () -> Bool) -> CursorMagnifierStep {
        guard config.showsMagnifier else { return .stop }
        guard !paused, !hidden else { return .hide }
        guard shown || allowed() else { return before.showsMagnifier ? .hide : .ask }
        return .show
    }
    static let click = CursorGestureTrigger(keys: NSEvent.ModifierFlags([.control, .option, .command]).rawValue, button: 1, device: .both)
    static let ring: CGFloat = 3
    static let pictureIndex = 0
    static let ringIndex = 1

    static func frame(pointer: CGPoint, lens: CGFloat) -> CGRect {
        CGRect(x: pointer.x - lens / 2, y: pointer.y - lens / 2, width: lens, height: lens)
    }

    static func source(pointer: CGPoint, lens: CGFloat, zoom: Double, display: CGRect) -> CGRect {
        let span = lens / CGFloat(zoom)
        let width = min(span / display.width, 1)
        let height = min(span / display.height, 1)
        return CGRect(x: min(max((pointer.x - display.minX - span / 2) / display.width, 0), 1 - width),
                      y: min(max((pointer.y - display.minY - span / 2) / display.height, 0), 1 - height), width: width, height: height)
    }

    static func filled(_ config: CursorHighlightConfig, capture: CursorScreenshotConfig = .load(), board: CursorBoardConfig = .load(),
                       translator: CursorTranslatorConfig = .load()) -> CursorHighlightConfig {
        var next = config
        if next.magnifier, next.magnifierKey == nil, next.magnifierClick.button == nil,
           !next.isTaken(CursorTrigger(key: nil, click: click), key: \.magnifierKey, click: \.magnifierClick, capture: capture, board: board, translator: translator) {
            next.magnifierClick = click
        }
        return next
    }

    static func layers() -> CALayer {
        let root = CALayer()
        root.shadowColor = CGColor(gray: 0, alpha: 1)
        root.shadowOpacity = 0.45
        root.shadowRadius = 6
        root.shadowOffset = .zero
        let picture = CALayer()
        picture.masksToBounds = true
        picture.contentsGravity = .resize
        picture.magnificationFilter = .nearest
        let edge = CALayer()
        edge.borderColor = CGColor(gray: 1, alpha: 0.9)
        edge.borderWidth = ring
        root.addSublayer(picture)
        root.addSublayer(edge)
        return root
    }

    static func paint(_ root: CALayer, contents: Any?) {
        guard let parts = root.sublayers, parts.count > ringIndex else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        parts[pictureIndex].contents = contents
        CATransaction.commit()
    }

    static func place(_ root: CALayer, pointer: CGPoint, config: CursorHighlightConfig, display: CGRect, scale: CGFloat) {
        guard let parts = root.sublayers, parts.count > ringIndex else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let lens = CGFloat(config.lens)
        let bounds = CGRect(x: 0, y: 0, width: lens, height: lens)
        root.frame = frame(pointer: CGPoint(x: pointer.x - display.minX, y: pointer.y - display.minY), lens: lens)
        root.shadowPath = CGPath(ellipseIn: bounds, transform: nil)
        for part in parts {
            part.frame = bounds
            part.cornerRadius = lens / 2
            part.contentsScale = scale
        }
        parts[pictureIndex].contentsRect = source(pointer: pointer, lens: lens, zoom: config.zoom, display: display)
        CATransaction.commit()
    }
}

enum CursorHighlight {
    static let hotKeyID = CursorShaker.hotKeyID - 9
    static let spotlightHotKeyID = CursorShaker.hotKeyID - 11
    static let flashlightHotKeyID = CursorShaker.hotKeyID - 12
    static let ringLife: TimeInterval = 0.5
    static let ringGap: TimeInterval = 0.12
    static let burstLife: TimeInterval = 0.35
    static let bands = 0..<4
    static let holeIndex = 4
    static let ripplesIndex = 5

    static func hidesForMotion(follows: Bool, reduceMotion: Bool) -> Bool {
        follows && reduceMotion
    }

    static var followsReduceMotion: Bool {
        MACPreferences.flag(MACPreferences.followReduceMotionKey)
    }

    static func tree() -> CALayer {
        let root = CALayer()
        for _ in 0...ripplesIndex {
            let part = CALayer()
            part.isHidden = true
            root.addSublayer(part)
        }
        root.sublayers?[ripplesIndex].isHidden = false
        return root
    }

    static func paint(_ root: CALayer, config: CursorHighlightConfig, hole: CGImage?) {
        guard let parts = root.sublayers, parts.count > ripplesIndex else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let dim = CursorTrailsPalette.color(at: 0, stops: [config.color], alpha: config.dimAlpha)
        for band in bands { parts[band].backgroundColor = dim }
        parts[holeIndex].contents = hole
        CATransaction.commit()
    }

    static func place(_ root: CALayer, tip: CGPoint?, window: CGRect, scale: CGFloat, side: CGFloat) {
        guard let parts = root.sublayers, parts.count > ripplesIndex else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let tip {
            let layout = CursorHighlightSpotlight.layout(tip: tip, side: side, window: window, scale: scale)
            for band in bands {
                parts[band].frame = layout.bands[band]
                parts[band].isHidden = layout.bands[band].isEmpty
            }
            parts[holeIndex].frame = layout.hole
            parts[holeIndex].contentsScale = scale
            parts[holeIndex].isHidden = layout.bands[0] == CGRect(origin: .zero, size: window.size)
        } else {
            parts[..<ripplesIndex].forEach { $0.isHidden = true }
        }
        CATransaction.commit()
    }

    static func show(_ ripples: [CursorHighlightRipple], at now: TimeInterval, in root: CALayer, window: CGRect, scale: CGFloat,
                     config: CursorHighlightConfig) {
        guard let parts = root.sublayers, parts.count > ripplesIndex else { return }
        let holder = parts[ripplesIndex]
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        var shown = holder.sublayers ?? []
        while shown.count > ripples.count { shown.removeLast().removeFromSuperlayer() }
        while shown.count < ripples.count {
            let layer = CALayer()
            holder.addSublayer(layer)
            shown.append(layer)
        }
        for (layer, ripple) in zip(shown, ripples) {
            layer.frame = ripple.frame(config).offsetBy(dx: -window.minX, dy: -window.minY)
            layer.contentsScale = scale
            layer.contents = ripple.picture(at: now, config: config, scale: scale)
        }
        CATransaction.commit()
    }
}
