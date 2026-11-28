import AppKit
import Metal

extension Notification.Name {
    nonisolated static let MACCursorTrailsDidChange = Notification.Name("MACCursorTrailsDidChange")
}

enum CursorTrailsPalette: String, Codable, CaseIterable {
    case match, blaze, lime, jade, lagoon, cobalt, orchid, cherry, electric, twilight, prism, graphite

    var stops: [UInt32] {
        switch self {
        case .match: return []
        case .blaze: return [0xF2A33A, 0xE8601C, 0xB3261E]
        case .lime: return [0xE3D54A, 0x8CCB4A, 0x2E9E5B]
        case .jade: return [0x38B26A, 0x1FA68F, 0x1E88A8]
        case .lagoon: return [0x1FB5B0, 0x2D9CDB, 0x3B6FD8]
        case .cobalt: return [0x2F6FED, 0x5B5BE0, 0x7E48D4]
        case .orchid: return [0x7E48D4, 0xC14FC4, 0xE8559A]
        case .cherry: return [0xE8559A, 0xE04060, 0xC62828]
        case .electric: return [0x18C8E8, 0x7B6CF6, 0xC93BB5]
        case .twilight: return [0xF08A3C, 0xB13FA8, 0x4F46C8]
        case .prism: return [0xE5484D, 0xF0A020, 0x3FB950, 0x2F81F7, 0x8957E5]
        case .graphite: return [0xA3ABB8, 0x818B99, 0x5C6676]
        }
    }

    var colors: [CGColor] {
        stops.map { Self.color(at: 0, stops: [$0], alpha: 1) }
    }

    static func rgb(_ hex: UInt32) -> [CGFloat] {
        [CGFloat(hex >> 16 & 0xFF) / 255, CGFloat(hex >> 8 & 0xFF) / 255, CGFloat(hex & 0xFF) / 255]
    }

    static func color(at place: CGFloat, stops: [UInt32], alpha: CGFloat) -> CGColor {
        let stops = stops.isEmpty ? [graphite.stops[1]] : stops
        let position = min(max(place, 0), 1) * CGFloat(stops.count - 1)
        let low = Int(position)
        let high = min(low + 1, stops.count - 1)
        let t = position - CGFloat(low)
        let from = rgb(stops[low])
        let to = rgb(stops[high])
        return CGColor(srgbRed: from[0] + (to[0] - from[0]) * t, green: from[1] + (to[1] - from[1]) * t,
                       blue: from[2] + (to[2] - from[2]) * t, alpha: alpha)
    }

    static func luminance(_ rgb: [CGFloat]) -> CGFloat {
        let linear = linear(rgb)
        return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
    }

    static func matchStops(_ image: CGImage?) -> [UInt32] {
        let side = 32
        guard let image, let context = MACCursorShadow.makeContext(width: side, height: side) else { return graphite.stops }
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let data = context.data else { return graphite.stops }
        let bytes = data.bindMemory(to: UInt8.self, capacity: context.bytesPerRow * side)
        var buckets = [(sum: [CGFloat], count: Int)](repeating: ([0, 0, 0], 0), count: 12)
        var opaque = 0
        for row in 0..<side {
            for column in 0..<side {
                let pixel = bytes + row * context.bytesPerRow + column * 4
                guard pixel[0] >= 128 else { continue }
                opaque += 1
                let rgb = (1...3).map { min(CGFloat(pixel[$0]) / CGFloat(pixel[0]), 1) }
                let color = NSColor(srgbRed: rgb[0], green: rgb[1], blue: rgb[2], alpha: 1)
                guard color.saturationComponent > 0.25, color.brightnessComponent > 0.2 else { continue }
                let hue = Int(color.hueComponent * 12) % 12
                buckets[hue].sum = zip(buckets[hue].sum, rgb).map { $0 + $1 }
                buckets[hue].count += 1
            }
        }
        let kept = buckets.filter { $0.count > 0 && Double($0.count) >= 0.03 * Double(opaque) }
            .sorted { $0.count > $1.count }
            .prefix(4)
            .map { bucket in bucket.sum.map { $0 / CGFloat(bucket.count) } }
            .sorted { luminance($0) > luminance($1) }
        guard let head = kept.last else { return graphite.stops }
        return (kept.dropLast() + [clampedHead(head)]).map(hex)
    }

    @MainActor
    static func matchStops(themeAt path: String?) -> [UInt32] {
        matchStops(MACMenuBarThumbnailImageForThemeAtPath(path)?.cgImage(forProposedRect: nil, context: nil, hints: nil))
    }

    private static func linear(_ rgb: [CGFloat]) -> [CGFloat] {
        rgb.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
    }

    private static func clampedHead(_ rgb: [CGFloat]) -> [CGFloat] {
        let lum = luminance(rgb)
        var linear = linear(rgb)
        if lum < 0.11 {
            linear = linear.map { $0 + (1 - $0) * (0.11 - lum) / (1 - lum) }
        } else if lum > 0.29 {
            linear = linear.map { $0 * 0.29 / lum }
        }
        return linear.map { $0 <= 0.0031308 ? $0 * 12.92 : 1.055 * pow($0, 1 / 2.4) - 0.055 }
    }

    private static func hex(_ rgb: [CGFloat]) -> UInt32 {
        rgb.reduce(0) { $0 << 8 | UInt32((min(max($1, 0), 1) * 255).rounded()) }
    }
}

enum CursorTrailsStyle: String, Codable, CaseIterable {
    case line, cursorCopies, star, bubble, neon, snow, heart, lightning, magic, customParticles

    static let pause: TimeInterval = 0.1

    static let dot: CGImage? = {
        guard let context = MACCursorShadow.makeContext(width: 48, height: 48) else { return nil }
        let colors = [CGFloat(1), 1, 0].map { CGColor(srgbRed: 1, green: 1, blue: 1, alpha: $0) } as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 0.4, 1]) {
            context.drawRadialGradient(gradient, startCenter: CGPoint(x: 24, y: 24), startRadius: 0,
                                       endCenter: CGPoint(x: 24, y: 24), endRadius: 24, options: [])
        }
        return context.makeImage()
    }()

    static let starShape = art { $0.addLines(between: points(5, outer: 22, inner: 9)) }

    static let twinkle = art { $0.addLines(between: points(4, outer: 22, inner: 5)) }

    static let ring = art { context in
        context.setLineWidth(4)
        context.strokeEllipse(in: CGRect(x: 4, y: 4, width: 40, height: 40))
        context.addEllipse(in: CGRect(x: 13, y: 29, width: 6, height: 6))
    }

    static let flake = art { context in
        context.setLineWidth(3.5)
        context.setLineCap(.round)
        for arm in 0..<6 {
            let angle = CGFloat(arm) * .pi / 3 + .pi / 2
            func spot(_ length: CGFloat, _ turn: CGFloat = 0) -> CGPoint {
                CGPoint(x: 24 + length * cos(angle + turn), y: 24 + length * sin(angle + turn))
            }
            context.addLines(between: [CGPoint(x: 24, y: 24), spot(21)])
            context.addLines(between: [spot(19, -0.35), spot(13), spot(19, 0.35)])
        }
        context.strokePath()
    }

    static let heartShape = art { context in
        context.fillEllipse(in: CGRect(x: 5, y: 21, width: 20, height: 20))
        context.fillEllipse(in: CGRect(x: 23, y: 21, width: 20, height: 20))
        context.addLines(between: [CGPoint(x: 6.3, y: 26), CGPoint(x: 24, y: 5), CGPoint(x: 41.7, y: 26), CGPoint(x: 24, y: 31)])
    }

    static let bolt = art {
        $0.addLines(between: [CGPoint(x: 30, y: 46), CGPoint(x: 12, y: 22), CGPoint(x: 23, y: 22), CGPoint(x: 16, y: 2),
                              CGPoint(x: 36, y: 28), CGPoint(x: 25, y: 28), CGPoint(x: 34, y: 46)])
    }

    private static func art(_ draw: (CGContext) -> Void) -> CGImage? {
        guard let context = MACCursorShadow.makeContext(width: 48, height: 48) else { return nil }
        let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        context.setFillColor(white)
        context.setStrokeColor(white)
        draw(context)
        if !context.isPathEmpty {
            context.closePath()
            context.fillPath()
        }
        return context.makeImage()
    }

    private static func points(_ count: Int, outer: CGFloat, inner: CGFloat) -> [CGPoint] {
        (0..<2 * count).map { index in
            let length = index.isMultiple(of: 2) ? outer : inner
            let angle = .pi / 2 + CGFloat(index) * .pi / CGFloat(count)
            return CGPoint(x: 24 + length * cos(angle), y: 24 + length * sin(angle))
        }
    }

    var recipe: CursorTrailsRecipe? {
        switch self {
        case .line, .cursorCopies, .customParticles: return nil
        case .star: return CursorTrailsRecipe(art: Self.starShape, rate: 30, speed: 25, speedRange: 15, spinRange: 4, size: 1.2, sizeRange: 0.4)
        case .bubble: return CursorTrailsRecipe(art: Self.ring, rate: 20, speed: 15, speedRange: 8, heading: .pi / 2, spread: .pi / 4, lift: 15, size: 1.2, sizeRange: 0.5)
        case .neon: return CursorTrailsRecipe(rate: 60, speed: 6, speedRange: 6, size: 1, sizeRange: 0.3, additive: true)
        case .snow: return CursorTrailsRecipe(art: Self.flake, rate: 25, speed: 10, speedRange: 8, heading: -.pi / 2, spread: .pi, lift: -40, spinRange: 1.5,
                                              size: 1.1, sizeRange: 0.4)
        case .heart: return CursorTrailsRecipe(art: Self.heartShape, rate: 25, speed: 20, speedRange: 8, heading: .pi / 2, spread: .pi / 4, lift: 30, size: 1.1, sizeRange: 0.3)
        case .lightning: return CursorTrailsRecipe(art: Self.bolt, rate: 40, speed: 30, speedRange: 20, spinRange: 10, size: 1, sizeRange: 0.4, flicker: 0.6)
        case .magic: return CursorTrailsRecipe(art: Self.twinkle, rate: 35, speed: 15, speedRange: 10, spinRange: 3, size: 0.4, sizeRange: 0.3, grow: 0.6, mirrored: true)
        }
    }
}

struct CursorTrailsRecipe {
    var art = CursorTrailsStyle.dot
    var rate = 40.0
    var speed: CGFloat = 10
    var speedRange: CGFloat = 10
    var heading: CGFloat = 0
    var spread: CGFloat = 2 * .pi
    var lift: CGFloat = 0
    var spin: CGFloat = 0
    var spinRange: CGFloat = 0
    var size: CGFloat = 1
    var sizeRange: CGFloat = 0.5
    var grow: CGFloat = 0
    var mirrored = false
    var flicker: CGFloat = 0
    var additive = false
    var offset = CGVector.zero
    var life: TimeInterval?
    var lifeRange: TimeInterval = 0
    var liftX: CGFloat = 0
    var latitude: CGFloat = 0
    var latitudeRange: CGFloat = 0
    var fades: Bool?
    var color: UInt32?
    var curve = CursorTrailsSizeCurve.steady
    var keepsColors = false

    func looks(_ stops: [UInt32]) -> [(color: UInt32, size: CGFloat, grow: CGFloat)] {
        (color.map { [$0] } ?? stops).flatMap { color in
            [(color, size, grow)] + (mirrored ? [(color, size + grow, -grow)] : [])
        }
    }
}

enum CursorTrailsEchoesColors: String, Codable, CaseIterable {
    case glow, style
}

enum CursorTrailsSizeCurve: String, Codable, CaseIterable {
    case steady, grow, shrink, smallBigSmall, bigSmallBig

    var curved: Bool { self == .smallBigSmall || self == .bigSmallBig }

    func factor(_ t: CGFloat) -> CGFloat {
        switch self {
        case .steady, .grow, .shrink: return 1
        case .smallBigSmall: return 0.25 + 0.75 * sin(.pi * t)
        case .bigSmallBig: return 1 - 0.75 * sin(.pi * t)
        }
    }
}

final class CursorTrailsArtCache<Key: Hashable>: @unchecked Sendable {
    private let lock = NSLock()
    private var arts: [Key: CGImage] = [:]

    subscript(key: Key) -> CGImage? { lock.withLock { arts[key] } }

    func keep(_ art: CGImage, for key: Key) -> CGImage {
        lock.withLock {
            if let kept = arts[key] { return kept }
            if arts.count >= CursorTrailsPicture.artCap { arts.removeAll() }
            arts[key] = art
            return art
        }
    }
}

enum CursorTrailsPicture: String, Codable, CaseIterable {
    case softDot, star, bubble, snowflake, heart, bolt, twinkle, symbol, image

    static let imageSide = 48
    static let imageLimit = 12 * 1024
    static let artCap = CursorTrailsCustomStyle.styleCap * CursorTrailsLayer.layerCap * 2

    private static let symbols = CursorTrailsArtCache<String>()
    private static let images = CursorTrailsArtCache<Data>()

    static func validImage(_ data: Data?) -> Data? {
        guard let data, data.count <= imageLimit, data.suffix(8).elementsEqual([0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82]),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetType(source) as String? == "public.png",
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              properties[kCGImagePropertyPixelWidth] as? Int == imageSide,
              properties[kCGImagePropertyPixelHeight] as? Int == imageSide else { return nil }
        return data
    }

    static func imageArt(_ data: Data?) -> CGImage? {
        guard let data else { return nil }
        if let art = images[data] { return art }
        guard validImage(data) != nil, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let picture = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let context = MACCursorShadow.makeContext(width: imageSide, height: imageSide) else { return nil }
        context.draw(picture, in: CGRect(x: 0, y: 0, width: imageSide, height: imageSide))
        guard let art = context.makeImage() else { return nil }
        return images.keep(art, for: data)
    }

    static func imageData(from picture: CGImage) -> Data? {
        let side = CGFloat(imageSide)
        guard picture.width > 0, picture.height > 0, let context = MACCursorShadow.makeContext(width: imageSide, height: imageSide) else { return nil }
        let fit = side / CGFloat(max(picture.width, picture.height))
        let size = CGSize(width: CGFloat(picture.width) * fit, height: CGFloat(picture.height) * fit)
        context.interpolationQuality = .high
        context.draw(picture, in: CGRect(x: (side - size.width) / 2, y: (side - size.height) / 2, width: size.width, height: size.height))
        let data = NSMutableData()
        guard let square = context.makeImage(),
              let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, square, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return validImage(data as Data)
    }

    func art(symbol name: String, image: Data? = nil) -> CGImage? {
        switch self {
        case .softDot: return CursorTrailsStyle.dot
        case .star: return CursorTrailsStyle.starShape
        case .bubble: return CursorTrailsStyle.ring
        case .snowflake: return CursorTrailsStyle.flake
        case .heart: return CursorTrailsStyle.heartShape
        case .bolt: return CursorTrailsStyle.bolt
        case .twinkle: return CursorTrailsStyle.twinkle
        case .symbol: return Self.symbolArt(name) ?? CursorTrailsStyle.dot
        case .image: return Self.imageArt(image) ?? CursorTrailsStyle.dot
        }
    }

    static func symbolArt(_ name: String) -> CGImage? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let art = symbols[name] { return art }
        guard !name.isEmpty,
              let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 40, weight: .regular)),
              let picture = symbol.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = MACCursorShadow.makeContext(width: 48, height: 48) else { return nil }
        let fit = 44 / CGFloat(max(picture.width, picture.height, 1))
        let size = CGSize(width: CGFloat(picture.width) * fit, height: CGFloat(picture.height) * fit)
        context.draw(picture, in: CGRect(x: (48 - size.width) / 2, y: (48 - size.height) / 2, width: size.width, height: size.height))
        context.setBlendMode(.sourceIn)
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 48, height: 48))
        guard let art = context.makeImage() else { return nil }
        return symbols.keep(art, for: name)
    }
}

struct CursorTrailsLayer: Codable, Equatable {
    static let layerCap = 8
    static let nameLimit = 30
    static let symbolLimit = 100

    private static var limits: [(key: WritableKeyPath<CursorTrailsLayer, Double>, range: ClosedRange<Double>)] { [
        (\.offsetX, -100...100), (\.offsetY, -100...100), (\.birthRate, 1...120), (\.lifetime, 0.1...3), (\.lifetimeRange, 0...2),
        (\.angle, 0...360), (\.angleRange, 0...360), (\.latitude, 0...180), (\.latitudeRange, 0...180), (\.velocity, 0...300), (\.velocityRange, 0...300),
        (\.xAcceleration, -500...500), (\.yAcceleration, -500...500), (\.size, 2...48), (\.sizeRange, 0...48), (\.spin, -720...720), (\.spinRange, 0...1440),
    ] }

    var name = ""
    var enabled = true
    var offsetX = 0.0
    var offsetY = 0.0
    var birthRate = 80.0
    var lifetime = 0.8
    var lifetimeRange = 0.25
    var angle = 0.0
    var angleRange = 360.0
    var latitude = 0.0
    var latitudeRange = 0.0
    var velocity = 90.0
    var velocityRange = 40.0
    var xAcceleration = 0.0
    var yAcceleration = 0.0
    var picture = CursorTrailsPicture.softDot
    var symbol = ""
    var usesCard = true
    var color: UInt32 = 0x2F81F7
    var size = 12.0
    var sizeRange = 12.0
    var spin = 0.0
    var spinRange = 0.0
    var fade = true
    var sizeCurve = CursorTrailsSizeCurve.steady
    var image: Data?

    static func limit(_ key: WritableKeyPath<CursorTrailsLayer, Double>) -> ClosedRange<Double> {
        limits.first { $0.key == key }?.range ?? 0...0
    }

    func clamped() -> CursorTrailsLayer {
        var layer = self
        for (key, range) in Self.limits {
            layer[keyPath: key] = min(max(layer[keyPath: key], range.lowerBound), range.upperBound)
        }
        layer.lifetimeRange = min(layer.lifetimeRange, 2 * layer.lifetime)
        layer.sizeRange = min(layer.sizeRange, 2 * layer.size)
        layer.name = String(name.prefix(Self.nameLimit))
        layer.symbol = String(symbol.prefix(Self.symbolLimit))
        layer.color = min(color, 0xFFFFFF)
        return layer
    }

    func recipe(length: Int, fade: Bool) -> CursorTrailsRecipe {
        let stretch = Double(length) / Double(CursorTrailsConfig.defaultLength)
        let degree = CGFloat.pi / 180
        let start = sizeCurve == .grow ? 0.25 : 1.0
        let grow = sizeCurve == .grow ? 0.75 * size : sizeCurve == .shrink ? -0.75 * size : 0
        let keepsColors = picture == .image && CursorTrailsPicture.imageArt(image) != nil
        return CursorTrailsRecipe(art: picture.art(symbol: symbol, image: image), rate: birthRate, speed: velocity, speedRange: velocityRange, heading: angle * degree,
                                  spread: angleRange * degree, lift: yAcceleration, spin: spin * degree, spinRange: spinRange * degree, size: start * size / 12,
                                  sizeRange: start * sizeRange / 12, grow: grow / 12, offset: CGVector(dx: offsetX, dy: offsetY), life: lifetime * stretch,
                                  lifeRange: lifetimeRange * stretch, liftX: xAcceleration, latitude: latitude * degree, latitudeRange: latitudeRange * degree,
                                  fades: fade && self.fade, color: keepsColors ? 0xFFFFFF : usesCard ? nil : color, curve: sizeCurve, keepsColors: keepsColors)
    }
}

extension CursorTrailsLayer {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var layer = CursorTrailsLayer()
        func read<Value: Decodable>(_ key: CodingKeys, _ path: WritableKeyPath<CursorTrailsLayer, Value>) {
            if let value = try? container.decode(Value.self, forKey: key) { layer[keyPath: path] = value }
        }
        read(.name, \.name)
        read(.enabled, \.enabled)
        read(.offsetX, \.offsetX)
        read(.offsetY, \.offsetY)
        read(.birthRate, \.birthRate)
        read(.lifetime, \.lifetime)
        read(.lifetimeRange, \.lifetimeRange)
        read(.angle, \.angle)
        read(.angleRange, \.angleRange)
        read(.latitude, \.latitude)
        read(.latitudeRange, \.latitudeRange)
        read(.velocity, \.velocity)
        read(.velocityRange, \.velocityRange)
        read(.xAcceleration, \.xAcceleration)
        read(.yAcceleration, \.yAcceleration)
        read(.picture, \.picture)
        read(.symbol, \.symbol)
        read(.usesCard, \.usesCard)
        read(.color, \.color)
        read(.size, \.size)
        read(.sizeRange, \.sizeRange)
        read(.spin, \.spin)
        read(.spinRange, \.spinRange)
        read(.fade, \.fade)
        read(.sizeCurve, \.sizeCurve)
        layer.image = CursorTrailsPicture.validImage(try? container.decode(Data.self, forKey: .image))
        self = layer.clamped()
    }
}

private struct CursorTrailsSkipped: Decodable {
    init(from decoder: Decoder) throws {}
}

private extension UnkeyedDecodingContainer {
    mutating func decodeList<Item: Decodable>(_ type: Item.Type, cap: Int) -> [Item] {
        var items: [Item] = []
        while !isAtEnd, items.count < cap {
            if let item = try? decode(Item.self) {
                items.append(item)
            } else if (try? decodeNil()) != true, (try? decode(CursorTrailsSkipped.self)) == nil {
                break
            }
        }
        return items
    }
}

struct CursorTrailsCustomStyle: Codable, Equatable, Identifiable {
    static let styleCap = 20
    static let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    var id = UUID()
    var name = ""
    var layers = [CursorTrailsLayer()]

    init(id: UUID = UUID(), name: String = "", layers: [CursorTrailsLayer] = [CursorTrailsLayer()]) {
        self.id = id
        self.name = name
        self.layers = layers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = String(((try? container.decode(String.self, forKey: .name)) ?? "").prefix(CursorTrailsLayer.nameLimit))
        var list = try? container.nestedUnkeyedContainer(forKey: .layers)
        layers = list?.decodeList(CursorTrailsLayer.self, cap: CursorTrailsLayer.layerCap) ?? []
        if layers.isEmpty { layers = [CursorTrailsLayer()] }
    }
}

extension CAEmitterLayer {
    var emitterChildren: [CAEmitterLayer] {
        (sublayers ?? []).compactMap { $0 as? CAEmitterLayer }
    }
}

enum CursorTrailsStart: String, Codable, CaseIterable {
    case hotSpot, center, custom
}

struct CursorTrailsConfig: Codable, Equatable {
    static let lengths = 2...11
    static let defaultLength = 6
    static let widths = 2...12
    static let defaultWidth = 6
    static let startDistances = 0...300
    static let hasMetal = !MTLCopyAllDevices().isEmpty

    var enabled = false
    var useGPU = true
    var fade = true
    var style = CursorTrailsStyle.line
    var palette = CursorTrailsPalette.match
    var length = CursorTrailsConfig.defaultLength
    var width = CursorTrailsConfig.defaultWidth
    var glow = false
    var echoesColors = CursorTrailsEchoesColors.glow
    var customStyles = [CursorTrailsCustomStyle(id: CursorTrailsCustomStyle.firstID)]
    var customStyle = CursorTrailsCustomStyle.firstID
    var startDistance = 0
    var start = CursorTrailsStart.hotSpot
    var spot = CGPoint(x: 0.5, y: 0.5)

    private var inUse: Int {
        customStyles.firstIndex { $0.id == customStyle } ?? 0
    }

    var styleInUse: CursorTrailsCustomStyle {
        customStyles[inUse]
    }

    var layers: [CursorTrailsLayer] {
        get { customStyles[inUse].layers }
        set { customStyles[inUse].layers = newValue }
    }

    mutating func put(_ style: CursorTrailsCustomStyle) {
        if let index = customStyles.firstIndex(where: { $0.id == style.id }) {
            customStyles[index] = style
        } else if customStyles.count < CursorTrailsCustomStyle.styleCap {
            customStyles.append(style)
        }
    }

    mutating func deleteStyle(_ id: UUID) {
        guard customStyles.count > 1 else { return }
        customStyles.removeAll { $0.id == id }
        if !customStyles.contains(where: { $0.id == customStyle }) { customStyle = customStyles[0].id }
    }

    var lifetime: TimeInterval {
        guard style == .customParticles else { return Double(length) / 10 }
        let stretch = Double(length) / Double(Self.defaultLength)
        return layers.filter(\.enabled).map { ($0.lifetime + $0.lifetimeRange / 2) * stretch }.max() ?? 0
    }

    var recipes: [CursorTrailsRecipe]? {
        guard style == .customParticles else { return style.recipe.map { [$0] } }
        return layers.filter(\.enabled).map { $0.recipe(length: length, fade: fade) }
    }

    mutating func addLayer() -> Int {
        guard layers.count < CursorTrailsLayer.layerCap else { return layers.count - 1 }
        layers.append(CursorTrailsLayer())
        return layers.count - 1
    }

    mutating func duplicateLayer(at index: Int) -> Int {
        guard layers.count < CursorTrailsLayer.layerCap, layers.indices.contains(index) else { return index }
        layers.insert(layers[index], at: index + 1)
        return index + 1
    }

    mutating func deleteLayer(at index: Int) -> Int {
        guard layers.count > 1, layers.indices.contains(index) else { return index }
        layers.remove(at: index)
        return min(index, layers.count - 1)
    }

    func layerEmitters(under emitter: CAEmitterLayer, stops: [UInt32]) -> [CAEmitterLayer]? {
        guard style == .customParticles else { return nil }
        return (recipes ?? []).enumerated().map { index, recipe in
            let child = CAEmitterLayer()
            child.frame = emitter.bounds
            child.contentsScale = emitter.contentsScale
            child.emitterCells = cells(recipe, stops: stops)
            child.seed = UInt32(index) &* 7919
            child.birthRate = 0
            return child
        }
    }

    func aim(_ children: [CAEmitterLayer], at point: CGPoint) {
        for (child, layer) in zip(children, layers.filter(\.enabled)) {
            child.emitterPosition = CGPoint(x: point.x + layer.offsetX, y: point.y + layer.offsetY)
            child.birthRate = 1
        }
    }

    func recolour(_ children: [CAEmitterLayer], stops: [UInt32]) {
        for (child, recipe) in zip(children, recipes ?? []) {
            child.emitterCells = cells(recipe, stops: stops)
        }
    }

    var curves: Bool { style == .customParticles && layers.contains { $0.enabled && $0.sizeCurve.curved } }

    var emits: Bool { (style.recipe != nil || style == .customParticles) && useGPU && Self.hasMetal && !curves }

    var drawsCopies: Bool { style == .cursorCopies }

    func lead(_ tip: CGPoint, on copy: CursorTrailsCopy?) -> CGPoint {
        guard start != .hotSpot, let copy else { return tip }
        let shift = copy.shift(to: start == .center ? CGPoint(x: 0.5, y: 0.5) : spot)
        return CGPoint(x: tip.x + shift.dx, y: tip.y + shift.dy)
    }

    func painted(_ copy: CursorTrailsCopy, stops: [UInt32]) -> CursorTrailsCopy {
        drawsCopies && echoesColors == .style ? copy.tinted(stops, count: length) : copy
    }

    static func load(operations: MACPreferences.Operations = .live) -> CursorTrailsConfig {
        operations.synchronize(MACPreferences.domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        guard let data = MACPreferences.value(forKey: MACPreferences.cursorTrailsKey, operations: operations) as? Data,
              let config = try? JSONDecoder().decode(CursorTrailsConfig.self, from: data) else { return CursorTrailsConfig() }
        return config
    }

    func save(operations: MACPreferences.Operations = .live) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        MACPreferences.set(data, forKey: MACPreferences.cursorTrailsKey, operations: operations)
        CursorTrailsConfig.notifyHelper()
    }

    static func notifyHelper() {
        DistributedNotificationCenter.default().postNotificationName(.MACCursorTrailsDidChange, object: nil,
                                                                     userInfo: nil, deliverImmediately: true)
    }

    static func isOn(enabled: Bool, running: Bool) -> Bool {
        enabled && running
    }

    func canSet(_ key: WritableKeyPath<CursorTrailsConfig, Bool>) -> Bool {
        key == \CursorTrailsConfig.enabled || enabled && (key != \CursorTrailsConfig.useGPU || Self.hasMetal)
    }

    static func toggledValue(enabled: Bool, helperInstalled: Bool, running: Bool) -> Bool? {
        guard helperInstalled else { return nil }
        if isOn(enabled: enabled, running: running) { return false }
        return running ? true : nil
    }

    func particles(stops: [UInt32]) -> [CAEmitterCell] {
        style.recipe.map { cells($0, stops: stops) } ?? []
    }

    func cells(_ recipe: CursorTrailsRecipe, stops: [UInt32]) -> [CAEmitterCell] {
        guard let art = recipe.art else { return [] }
        let life = recipe.life ?? lifetime
        let fades = recipe.fades ?? fade
        let tilts = recipe.latitudeRange > 0 ? (0..<5).map { recipe.latitude + recipe.latitudeRange * (CGFloat($0) / 4 - 0.5) } : [recipe.latitude]
        let looks = recipe.looks(stops)
        let unit = CGFloat(width) / 24
        return looks.flatMap { look in
            tilts.map { tilt in
                let cell = CAEmitterCell()
                cell.contents = art
                cell.color = CursorTrailsPalette.color(at: 0, stops: [look.color], alpha: 1 - recipe.flicker / 2)
                cell.birthRate = Float(recipe.rate) / Float(looks.count * tilts.count)
                cell.lifetime = Float(life)
                cell.lifetimeRange = Float(recipe.lifeRange)
                cell.alphaSpeed = fades ? -1 / Float(life) : 0
                cell.alphaRange = Float(recipe.flicker)
                cell.scale = unit * look.size
                cell.scaleRange = unit * recipe.sizeRange
                cell.scaleSpeed = unit * look.grow / life
                cell.velocity = recipe.speed
                cell.velocityRange = recipe.speedRange
                cell.emissionLongitude = recipe.heading
                cell.emissionRange = recipe.spread < 2 * .pi ? recipe.spread / 2 : recipe.spread
                cell.emissionLatitude = tilt
                cell.xAcceleration = recipe.liftX
                cell.yAcceleration = recipe.lift
                cell.spin = recipe.spin
                cell.spinRange = recipe.spinRange
                return cell
            }
        }
    }

    func glowLayer(at tip: CGPoint, in frame: CGRect, stops: [UInt32]) -> CALayer {
        let side = CGFloat(width) * 8
        let layer = CAGradientLayer()
        layer.type = .radial
        layer.colors = [CGFloat(1), 0.5, 0].map { CursorTrailsPalette.color(at: $0, stops: stops, alpha: $0 * 0.7) }
        layer.startPoint = CGPoint(x: 0.5, y: 0.5)
        layer.endPoint = CGPoint(x: 1, y: 1)
        layer.frame = CGRect(x: tip.x - frame.minX - side / 2, y: tip.y - frame.minY - side / 2, width: side, height: side)
        return layer
    }
}

extension CursorTrailsConfig {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func clamped(_ key: CodingKeys, to range: ClosedRange<Int>, or fallback: Int) -> Int {
            min(max((try? container.decode(Int.self, forKey: key)) ?? fallback, range.lowerBound), range.upperBound)
        }
        enabled = (try? container.decode(Bool.self, forKey: .enabled)) ?? false
        useGPU = (try? container.decode(Bool.self, forKey: .useGPU)) ?? true
        fade = (try? container.decode(Bool.self, forKey: .fade)) ?? true
        style = (try? container.decode(CursorTrailsStyle.self, forKey: .style)) ?? .line
        palette = (try? container.decode(CursorTrailsPalette.self, forKey: .palette)) ?? .match
        length = clamped(.length, to: Self.lengths, or: Self.defaultLength)
        width = clamped(.width, to: Self.widths, or: Self.defaultWidth)
        glow = (try? container.decode(Bool.self, forKey: .glow)) ?? false
        echoesColors = (try? container.decode(CursorTrailsEchoesColors.self, forKey: .echoesColors)) ?? .glow
        var list = try? container.nestedUnkeyedContainer(forKey: .customStyles)
        customStyles = []
        for style in list?.decodeList(CursorTrailsCustomStyle.self, cap: CursorTrailsCustomStyle.styleCap) ?? [] where !customStyles.contains(where: { $0.id == style.id }) {
            customStyles.append(style)
        }
        if customStyles.isEmpty { customStyles = [CursorTrailsCustomStyle(id: CursorTrailsCustomStyle.firstID)] }
        let chosen = try? container.decode(UUID.self, forKey: .customStyle)
        customStyle = customStyles.first { $0.id == chosen }?.id ?? customStyles[0].id
        startDistance = clamped(.startDistance, to: Self.startDistances, or: 0)
        start = (try? container.decode(CursorTrailsStart.self, forKey: .start)) ?? .hotSpot
        let place = (try? container.decode(CGPoint.self, forKey: .spot)) ?? CGPoint(x: 0.5, y: 0.5)
        spot = CGPoint(x: min(max(place.x, 0), 1), y: min(max(place.y, 0), 1))
    }
}

struct CursorTrailsSample: Equatable {
    let point: CGPoint
    let time: TimeInterval

    static func interval(framesPerSecond fps: Int) -> TimeInterval {
        1 / Double(fps > 0 ? min(fps, 60) : 60)
    }

    static func advance(_ samples: [CursorTrailsSample], to tip: CGPoint, at now: TimeInterval,
                        length: TimeInterval) -> [CursorTrailsSample] {
        var samples = samples
        if samples.last.map({ MACFFMMovementExceedsThreshold($0.point, tip, 0.5) }) ?? true {
            samples.append(CursorTrailsSample(point: tip, time: now))
        }
        return samples.filter { now - $0.time < length }
    }
}

struct CursorTrailsGate {
    private var start: CGPoint?
    private var last: CGPoint?
    private var movedAt = -TimeInterval.infinity
    private var open = false

    mutating func admits(_ tip: CGPoint, at now: TimeInterval, distance: Int) -> Bool {
        guard distance > 0 else { return true }
        guard last.map({ MACFFMMovementExceedsThreshold($0, tip, 0.5) }) ?? true else { return open }
        if now - movedAt >= CursorTrailsStyle.pause {
            start = last ?? tip
            open = false
        }
        last = tip
        movedAt = now
        open = open || MACFFMMovementExceedsThreshold(start ?? tip, tip, CGFloat(distance))
        return open
    }

    mutating func frame(_ tip: CGPoint, at now: TimeInterval, distance: Int, samples: [CursorTrailsSample], lead: CGPoint? = nil) -> (spot: CGPoint, births: Bool) {
        let lead = lead ?? tip
        return admits(tip, at: now, distance: distance) ? (lead, true) : (samples.last?.point ?? lead, false)
    }
}

struct CursorTrailsCopy {
    let image: CGImage
    let size: CGSize
    let hotSpot: CGPoint
    var mirrored = false
    var tints: [CGImage] = []

    init?(theme: [AnyHashable: Any]?, scale: Double, leftHanded: Bool) {
        let cursors = theme?[MACCursorDefinitions.cursorsKey] as? [AnyHashable: Any]
        guard let entry = ["com.apple.coregraphics.Arrow", "com.apple.coregraphics.ArrowS"].lazy
                .compactMap({ cursors?[$0] as? [AnyHashable: Any] })
                .first(where: { !(($0[MACCursorDefinitions.representationsKey] as? [Any]) ?? []).isEmpty }),
              let strip = (entry[MACCursorDefinitions.representationsKey] as? [Any]).flatMap(MACSharpestRepresentation)?.image else { return nil }
        func number(_ key: String) -> CGFloat { CGFloat((entry[key] as? NSNumber)?.doubleValue ?? 0) }
        let frames = max((entry[MACCursorDefinitions.frameCountKey] as? NSNumber)?.intValue ?? 1, 1)
        let declared = CGSize(width: number(MACCursorDefinitions.pointsWideKey), height: number(MACCursorDefinitions.pointsHighKey))
        guard declared.width > 0, declared.height > 0,
              let frame = strip.cropping(to: CGRect(x: 0, y: 0, width: strip.width, height: max(strip.height / frames, 1))) else { return nil }
        var hot = CGPoint(x: number(MACCursorDefinitions.hotSpotXKey), y: number(MACCursorDefinitions.hotSpotYKey))
        var picture = frame
        if leftHanded {
            hot.x = declared.width - hot.x - 1
            guard let context = MACCursorShadow.makeContext(width: frame.width, height: frame.height) else { return nil }
            context.translateBy(x: CGFloat(frame.width), y: 0)
            context.scaleBy(x: -1, y: 1)
            context.draw(frame, in: CGRect(x: 0, y: 0, width: frame.width, height: frame.height))
            guard let flipped = context.makeImage() else { return nil }
            picture = flipped
            mirrored = true
        }
        let fit = min(MACCursorDefinitions.maxPointSize / max(declared.width, declared.height), 1) * CGFloat(scale > 0 ? scale : 1)
        image = picture
        size = CGSize(width: declared.width * fit, height: declared.height * fit)
        hotSpot = CGPoint(x: hot.x * fit, y: hot.y * fit)
    }

    init?(theme: [AnyHashable: Any]?, baseline: @autoclosure () -> [AnyHashable: Any]?, scale: Double, leftHanded: Bool) {
        guard let copy = CursorTrailsCopy(theme: theme, scale: scale, leftHanded: leftHanded)
                ?? CursorTrailsCopy(theme: baseline(), scale: scale, leftHanded: false) else { return nil }
        self = copy
    }

    func tinted(_ stops: [UInt32], count: Int) -> CursorTrailsCopy {
        var copy = self
        copy.tints = (0..<count).map { age in
            Self.tint(image, CursorTrailsPalette.color(at: 1 - CGFloat(age) / CGFloat(max(count - 1, 1)), stops: stops, alpha: 1)) ?? image
        }
        return copy
    }

    static func tint(_ image: CGImage, _ color: CGColor) -> CGImage? {
        let area = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        guard let context = MACCursorShadow.makeContext(width: image.width, height: image.height) else { return nil }
        context.draw(image, in: area)
        context.setBlendMode(.sourceIn)
        context.setFillColor(color)
        context.fill(area)
        return context.makeImage()
    }

    static func advance(_ samples: [CursorTrailsSample], to tip: CGPoint, at now: TimeInterval, count: Int) -> [CursorTrailsSample] {
        let kept = Array((samples + [CursorTrailsSample(point: tip, time: now)]).suffix(count + 1))
        let caughtUp = kept.count > count && !kept.contains { MACFFMMovementExceedsThreshold($0.point, tip, 0.5) }
        return caughtUp ? [] : kept
    }

    var pictures: [CGImage] { tints.isEmpty ? [image] : tints }

    func shift(to spot: CGPoint) -> CGVector {
        CGVector(dx: (mirrored ? 1 - spot.x : spot.x) * size.width - hotSpot.x, dy: hotSpot.y - spot.y * size.height)
    }

    func frame(at spot: CGPoint) -> CGRect {
        CGRect(x: spot.x - hotSpot.x, y: spot.y + hotSpot.y - size.height, width: size.width, height: size.height)
    }

    func sprites(_ samples: [CursorTrailsSample], tip: CGPoint, fade: Bool) -> [CursorTrailsSprite] {
        samples.enumerated().filter { MACFFMMovementExceedsThreshold($0.element.point, tip, 0.5) }.map { index, sample in
            CursorTrailsSprite(frame: frame(at: sample.point), alpha: fade ? CGFloat(index + 1) / CGFloat(samples.count) : 1,
                               picture: tints.isEmpty ? 0 : min(max(samples.count - 2 - index, 0), tints.count - 1))
        }
    }

    func picture(_ samples: [CursorTrailsSample], tip: CGPoint, fade: Bool, in screen: CGRect, scale: CGFloat) -> (frame: CGRect, image: CGImage)? {
        let sprites = sprites(samples, tip: tip, fade: fade)
        let pictures = pictures
        return CursorTrailsPiece.picture(sprites.reduce(CGRect.null) { $0.union($1.frame) }, in: screen, scale: scale) { context in
            for sprite in sprites {
                context.setAlpha(sprite.alpha)
                context.draw(pictures[sprite.picture], in: sprite.frame)
            }
        }
    }

    static func bgra(_ picture: CGImage) -> Data? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: picture.width, height: picture.height, bitsPerComponent: 8, bytesPerRow: picture.width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
              let data = context.data else { return nil }
        context.draw(picture, in: CGRect(x: 0, y: 0, width: picture.width, height: picture.height))
        return Data(bytes: data, count: context.bytesPerRow * picture.height)
    }
}

struct CursorTrailsSprite: Equatable {
    let frame: CGRect
    let alpha: CGFloat
    let picture: Int

    static func quads(_ sprites: [CursorTrailsSprite]) -> [CursorTrailsVertex] {
        sprites.enumerated().flatMap { index, sprite in
            let depth = Float(sprites.count - index) / Float(sprites.count + 1)
            return [CGPoint(x: sprite.frame.minX, y: sprite.frame.maxY), CGPoint(x: sprite.frame.maxX, y: sprite.frame.maxY),
                    CGPoint(x: sprite.frame.minX, y: sprite.frame.minY), CGPoint(x: sprite.frame.maxX, y: sprite.frame.minY)].map {
                CursorTrailsVertex(position: SIMD4(Float($0.x), Float($0.y), depth, 1), color: SIMD4(repeating: Float(sprite.alpha)))
            }
        }
    }
}

struct CursorTrailsDot {
    let start: CGPoint
    let drift: CGVector
    let time: TimeInterval
    let radius: CGFloat
    let art: CGImage
    var lift: CGFloat = 0
    var grow: CGFloat = 0
    var spin: CGFloat = 0
    var shine: CGFloat = 1
    var additive = false
    var layer = 0
    var life: TimeInterval?
    var span: TimeInterval?
    var fades: Bool?
    var liftX: CGFloat = 0
    var curve = CursorTrailsSizeCurve.steady

    static let coneWidth: CGFloat = 0.36
    static let areaCap: CGFloat = 220 * 33.6 * 33.6

    var peak: CGFloat { max(radius, radius + grow) }

    func spot(at now: TimeInterval) -> CGPoint {
        let age = now - time
        return CGPoint(x: start.x + drift.dx * age + liftX * age * age / 2, y: start.y + drift.dy * age + lift * age * age / 2)
    }

    func size(at now: TimeInterval, lifetime: TimeInterval) -> CGFloat {
        let t = CGFloat((now - time) / (span ?? lifetime))
        return max((radius + grow * t) * curve.factor(min(max(t, 0), 1)), 0)
    }

    func box(at now: TimeInterval, lifetime: TimeInterval) -> CGRect {
        let spot = spot(at: now)
        let side = size(at: now, lifetime: lifetime) * (spin == 0 ? 1 : 2.squareRoot())
        return CGRect(x: spot.x - side, y: spot.y - side, width: 2 * side, height: 2 * side)
    }

    func alpha(at now: TimeInterval, lifetime: TimeInterval, fade: Bool) -> CGFloat {
        (fades ?? fade) ? max(shine - CGFloat((now - time) / (span ?? lifetime)), 0) : shine
    }

    static func advance(_ dots: [CursorTrailsDot], spawningAt tip: CGPoint?, at now: TimeInterval, lifetime: TimeInterval,
                        width: Int, stops: [UInt32], recipe: CursorTrailsRecipe = CursorTrailsRecipe(), layer: Int = 0) -> [CursorTrailsDot] {
        func ticks(_ time: TimeInterval) -> Int { Int((time * recipe.rate).rounded(.down)) }
        let first = recipe.life == nil || ticks(now) > ticks(now - 1.0 / 60) ? 1 : 0
        let due = tip == nil ? 0 : dots.last { $0.layer == layer }.map { min(ticks(now) - ticks($0.time), 2) } ?? first
        let looks = recipe.looks(stops.isEmpty ? [CursorTrailsPalette.graphite.stops[1]] : stops)
        let born = (0..<max(due, 0)).compactMap { _ -> CursorTrailsDot? in
            guard let tip, let look = looks.randomElement(), let white = recipe.art,
                  let art = recipe.keepsColors ? white : CursorTrailsCopy.tint(white, CursorTrailsPalette.color(at: 0, stops: [look.color], alpha: 1)) else { return nil }
            let cone = recipe.spread / 2
            let cut = 1 - exp(-1 / (2 * coneWidth * coneWidth))
            let polar = min(coneWidth * cone * (-2 * log(1 - cut * .random(in: 0..<1))).squareRoot(), cone)
            let along = recipe.spread < 2 * .pi ? cos(polar) : .random(in: -1...1)
            let around = CGFloat.random(in: 0..<2 * .pi)
            let side = (1 - along * along).squareRoot()
            let tilt = recipe.latitudeRange > 0 ? recipe.latitude + recipe.latitudeRange * (CGFloat(Int.random(in: 0..<5)) / 4 - 0.5) : recipe.latitude
            let ahead = along * cos(tilt) - side * sin(around) * sin(tilt)
            let aside = side * cos(around)
            let speed = recipe.speed + .random(in: -recipe.speedRange / 2...recipe.speedRange / 2)
            let (x, y) = (cos(recipe.heading), sin(recipe.heading))
            return CursorTrailsDot(start: CGPoint(x: tip.x + recipe.offset.dx, y: tip.y + recipe.offset.dy),
                                   drift: CGVector(dx: (ahead * x - aside * y) * speed, dy: (ahead * y + aside * x) * speed), time: now,
                                   radius: CGFloat(width) * (look.size + .random(in: -recipe.sizeRange / 2...recipe.sizeRange / 2)), art: art,
                                   lift: recipe.lift, grow: CGFloat(width) * look.grow,
                                   spin: recipe.spin + .random(in: -recipe.spinRange / 2...recipe.spinRange / 2),
                                   shine: .random(in: 1 - recipe.flicker...1), additive: recipe.additive, layer: layer,
                                   life: recipe.life.map { $0 + .random(in: -recipe.lifeRange / 2...recipe.lifeRange / 2) }, span: recipe.life,
                                   fades: recipe.fades, liftX: recipe.liftX, curve: recipe.curve)
        }
        return (dots + born).filter { now - $0.time < ($0.life ?? lifetime) }
    }

    static func step(_ samples: [CursorTrailsSample], _ dots: [CursorTrailsDot], to tip: CGPoint, at now: TimeInterval, lifetime: TimeInterval,
                     width: Int, stops: [UInt32], recipes: [CursorTrailsRecipe] = [CursorTrailsRecipe()]) -> (samples: [CursorTrailsSample], dots: [CursorTrailsDot]) {
        let samples = CursorTrailsSample.advance(samples, to: tip, at: now, length: lifetime + CursorTrailsStyle.pause)
        let moving = samples.last.map { now - $0.time < CursorTrailsStyle.pause } ?? false
        var all = dots.filter { now - $0.time < ($0.life ?? lifetime) }
        var covered = all.reduce(0) { $0 + 4 * $1.peak * $1.peak }
        let demand = recipes.reduce(CGFloat(0)) { total, recipe in
            let peak = recipe.size + max(recipe.grow, 0)
            return total + CGFloat(recipe.rate * (recipe.life ?? lifetime)) * 4 * CGFloat(width * width) * (peak * peak + recipe.sizeRange * recipe.sizeRange / 12)
        }
        let share = Double(min(1, areaCap / demand))
        for (layer, recipe) in recipes.enumerated() {
            let before = all.count
            var thinned = recipe
            thinned.rate *= share
            all = advance(all, spawningAt: moving && covered < areaCap ? tip : nil, at: now, lifetime: lifetime, width: width, stops: stops, recipe: thinned, layer: layer)
            covered += all[before...].reduce(0) { $0 + 4 * $1.peak * $1.peak }
        }
        return (samples, all)
    }

    static func picture(_ dots: [CursorTrailsDot], at now: TimeInterval, lifetime: TimeInterval, fade: Bool,
                        in screen: CGRect, scale: CGFloat) -> (frame: CGRect, image: CGImage)? {
        let area = dots.reduce(CGRect.null) { $0.union($1.box(at: now, lifetime: lifetime)) }
        return CursorTrailsPiece.picture(area, in: screen, scale: scale) { context in
            for dot in dots {
                let spot = dot.spot(at: now)
                let side = dot.size(at: now, lifetime: lifetime)
                let square = CGRect(x: -side, y: -side, width: 2 * side, height: 2 * side)
                context.saveGState()
                context.setAlpha(dot.alpha(at: now, lifetime: lifetime, fade: fade))
                if dot.additive { context.setBlendMode(.plusLighter) }
                context.translateBy(x: spot.x, y: spot.y)
                context.rotate(by: dot.spin * CGFloat(now - dot.time))
                context.draw(dot.art, in: square)
                context.restoreGState()
            }
        }
    }
}

struct CursorTrailsVertex: Equatable {
    var position: SIMD4<Float>
    var color: SIMD4<Float>
}

struct CursorTrailsPiece {
    let start: CGPoint
    let control: CGPoint
    let end: CGPoint
    let life: CGFloat
    let width: CGFloat
    let color: CGColor

    static func line(_ samples: [CursorTrailsSample], tip: CGPoint, at now: TimeInterval, length: TimeInterval,
                     width: CGFloat, fade: Bool, stops: [UInt32]) -> [CursorTrailsPiece] {
        guard samples.count > 1 else { return [] }
        let points = samples.dropLast().map(\.point) + [tip]
        let last = points.count - 1
        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
        return points.indices.map { index in
            let life = CGFloat(1 - (now - samples[index].time) / length)
            return CursorTrailsPiece(start: index == 0 ? points[0] : mid(points[index - 1], points[index]),
                                     control: points[index],
                                     end: index == last ? points[last] : mid(points[index], points[index + 1]),
                                     life: life,
                                     width: width * life,
                                     color: CursorTrailsPalette.color(at: CGFloat(index) / CGFloat(last), stops: stops, alpha: fade ? life : 1))
        }
    }

    func path(origin: CGPoint) -> CGPath {
        let shift = CGAffineTransform(translationX: -origin.x, y: -origin.y)
        let path = CGMutablePath()
        path.move(to: start, transform: shift)
        path.addQuadCurve(to: end, control: control, transform: shift)
        return path
    }

    static func picture(_ pieces: [CursorTrailsPiece], in screen: CGRect, scale: CGFloat) -> (frame: CGRect, image: CGImage)? {
        let area = pieces.reduce(CGRect.null) {
            $0.union($1.path(origin: .zero).boundingBoxOfPath.insetBy(dx: -$1.width / 2 - 1, dy: -$1.width / 2 - 1))
        }
        return picture(area, in: screen, scale: scale) { context in
            context.setBlendMode(.copy)
            for (index, piece) in pieces.enumerated() {
                context.addPath(piece.path(origin: .zero))
                context.setLineCap(index == pieces.count - 1 ? .butt : .round)
                context.setLineWidth(piece.width)
                context.setStrokeColor(piece.color)
                context.strokePath()
            }
        }
    }

    static func picture(_ area: CGRect, in screen: CGRect, scale: CGFloat, draw: (CGContext) -> Void) -> (frame: CGRect, image: CGImage)? {
        let bounds = area.intersection(screen).integral
        guard !bounds.isEmpty,
              let context = MACCursorShadow.makeContext(width: Int(bounds.width * scale), height: Int(bounds.height * scale)) else { return nil }
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -bounds.minX, y: -bounds.minY)
        draw(context)
        return context.makeImage().map { (frame: bounds.offsetBy(dx: -screen.minX, dy: -screen.minY), image: $0) }
    }

    static func frame(_ strip: [CursorTrailsVertex], in screen: CGRect, scale: CGFloat, atLeast floor: CGSize = .zero) -> CGRect? {
        guard let first = strip.first?.position else { return nil }
        let low = strip.reduce(first) { pointwiseMin($0, $1.position) }
        let high = strip.reduce(first) { pointwiseMax($0, $1.position) }
        let line = CGRect(x: CGFloat(low.x) - 1, y: CGFloat(low.y) - 1, width: CGFloat(high.x - low.x) + 2, height: CGFloat(high.y - low.y) + 2)
            .intersection(screen)
        guard !line.isEmpty else { return nil }
        let x = (line.minX * scale).rounded(.down) / scale
        let y = (line.minY * scale).rounded(.down) / scale
        let size = CGSize(width: min(max(((line.maxX - x) / 64).rounded(.up) * 64, floor.width), screen.width),
                          height: min(max(((line.maxY - y) / 64).rounded(.up) * 64, floor.height), screen.height))
        return CGRect(origin: CGPoint(x: max(min(x, screen.maxX - size.width), screen.minX) - screen.minX,
                                      y: max(min(y, screen.maxY - size.height), screen.minY) - screen.minY), size: size)
    }

    static func strip(_ pieces: [CursorTrailsPiece], steps: Int = 5) -> [CursorTrailsVertex] {
        let values = pieces.map { piece -> SIMD8<Float> in
            let rgba = (piece.color.components ?? []).map { Float($0) }
            return SIMD8<Float>(Float(piece.life), Float(piece.width), rgba[0], rgba[1], rgba[2], rgba[3], 0, 0)
        }
        var points: [(spot: SIMD2<Float>, value: SIMD8<Float>)] = []
        for (index, piece) in pieces.enumerated() {
            let from = (values[max(index - 1, 0)] + values[index]) / 2
            let to = (values[index] + values[min(index + 1, pieces.count - 1)]) / 2
            for step in (index == 0 ? 0 : 1)...steps {
                let t = CGFloat(step) / CGFloat(steps)
                let u = 1 - t
                let x = u * u * piece.start.x + 2 * u * t * piece.control.x + t * t * piece.end.x
                let y = u * u * piece.start.y + 2 * u * t * piece.control.y + t * t * piece.end.y
                points.append((SIMD2(Float(x), Float(y)), from + (to - from) * Float(t)))
            }
        }
        points.reverse()
        var strip: [CursorTrailsVertex] = []
        for (index, point) in points.enumerated() {
            let along = points[min(index + 1, points.count - 1)].spot - points[max(index - 1, 0)].spot
            let length = (along * along).sum().squareRoot()
            let normal = length > 0 ? SIMD2(-along.y, along.x) * (point.value[1] / 2 / length) : .zero
            let color = SIMD4(point.value[2], point.value[3], point.value[4], 1) * point.value[5]
            func corner(_ spot: SIMD2<Float>) -> CursorTrailsVertex {
                CursorTrailsVertex(position: SIMD4(spot.x, spot.y, 1 - point.value[0], 1), color: color)
            }
            strip.append(corner(point.spot + normal))
            strip.append(corner(point.spot - normal))
        }
        return strip
    }
}
