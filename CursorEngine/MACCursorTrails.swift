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
    case line, softDots, cursorCopies

    static let pause: TimeInterval = 0.1

    static let dot: CGImage? = {
        guard let context = MACCursorShadow.makeContext(width: 48, height: 48) else { return nil }
        if let gradient = gradient(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)) {
            context.drawRadialGradient(gradient, startCenter: CGPoint(x: 24, y: 24), startRadius: 0,
                                       endCenter: CGPoint(x: 24, y: 24), endRadius: 24, options: [])
        }
        return context.makeImage()
    }()

    static func gradient(_ color: CGColor) -> CGGradient? {
        let colors = [CGFloat(1), 1, 0].compactMap { color.copy(alpha: $0) } as CFArray
        return CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 0.4, 1])
    }
}

enum CursorTrailsEchoesColors: String, Codable, CaseIterable {
    case glow, style
}

struct CursorTrailsConfig: Codable, Equatable {
    static let lengths = 2...11
    static let defaultLength = 6
    static let widths = 2...12
    static let defaultWidth = 6
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

    var lifetime: TimeInterval { Double(length) / 10 }

    var emits: Bool { style == .softDots && useGPU && Self.hasMetal }

    var drawsCopies: Bool { style == .cursorCopies }

    func painted(_ copy: CursorTrailsCopy, stops: [UInt32]) -> CursorTrailsCopy {
        echoesColors == .style ? copy.tinted(stops, count: length) : copy
    }

    static func load() -> CursorTrailsConfig {
        CFPreferencesSynchronize(MACPreferences.domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        guard let data = MACPreferences.value(forKey: MACPreferences.cursorTrailsKey) as? Data,
              let config = try? JSONDecoder().decode(CursorTrailsConfig.self, from: data) else { return CursorTrailsConfig() }
        return config
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        MACPreferences.set(data, forKey: MACPreferences.cursorTrailsKey)
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
        guard style == .softDots, let art = CursorTrailsStyle.dot else { return [] }
        return stops.map { stop in
            let cell = CAEmitterCell()
            cell.contents = art
            cell.color = CursorTrailsPalette.color(at: 0, stops: [stop], alpha: 1)
            cell.birthRate = 40 / Float(stops.count)
            cell.lifetime = Float(lifetime)
            cell.alphaSpeed = fade ? -1 / Float(lifetime) : 0
            cell.scale = CGFloat(width) / 24
            cell.scaleRange = cell.scale / 2
            cell.velocity = 10
            cell.velocityRange = cell.velocity
            cell.emissionRange = 2 * .pi
            return cell
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

struct CursorTrailsCopy {
    let image: CGImage
    let size: CGSize
    let hotSpot: CGPoint
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
        let area = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        copy.tints = (0..<count).map { age in
            guard let context = MACCursorShadow.makeContext(width: image.width, height: image.height) else { return image }
            context.draw(image, in: area)
            context.setBlendMode(.sourceIn)
            context.setFillColor(CursorTrailsPalette.color(at: 1 - CGFloat(age) / CGFloat(max(count - 1, 1)), stops: stops, alpha: 1))
            context.fill(area)
            return context.makeImage() ?? image
        }
        return copy
    }

    static func advance(_ samples: [CursorTrailsSample], to tip: CGPoint, at now: TimeInterval, count: Int) -> [CursorTrailsSample] {
        let kept = Array((samples + [CursorTrailsSample(point: tip, time: now)]).suffix(count + 1))
        let caughtUp = kept.count > count && !kept.contains { MACFFMMovementExceedsThreshold($0.point, tip, 0.5) }
        return caughtUp ? [] : kept
    }

    var pictures: [CGImage] { tints.isEmpty ? [image] : tints }

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
    static let rate = 40.0

    let start: CGPoint
    let drift: CGVector
    let time: TimeInterval
    let radius: CGFloat
    let gradient: CGGradient

    func spot(at now: TimeInterval) -> CGPoint {
        CGPoint(x: start.x + drift.dx * (now - time), y: start.y + drift.dy * (now - time))
    }

    func alpha(at now: TimeInterval, lifetime: TimeInterval, fade: Bool) -> CGFloat {
        fade ? CGFloat(max(1 - (now - time) / lifetime, 0)) : 1
    }

    static func advance(_ dots: [CursorTrailsDot], spawningAt tip: CGPoint?, at now: TimeInterval, lifetime: TimeInterval,
                        width: Int, stops: [UInt32]) -> [CursorTrailsDot] {
        let due = tip == nil ? 0 : dots.last.map { min(Int(now * rate) - Int($0.time * rate), 2) } ?? 1
        let born = (0..<max(due, 0)).compactMap { _ -> CursorTrailsDot? in
            let color = CursorTrailsPalette.color(at: 0, stops: stops.randomElement().map { [$0] } ?? [], alpha: 1)
            guard let tip, let gradient = CursorTrailsStyle.gradient(color) else { return nil }
            let angle = CGFloat.random(in: 0..<2 * .pi)
            let speed = CGFloat.random(in: 0...20)
            return CursorTrailsDot(start: tip, drift: CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed), time: now,
                                   radius: CGFloat(width) * .random(in: 0.5...1.5), gradient: gradient)
        }
        return (dots + born).filter { now - $0.time < lifetime }
    }

    static func step(_ samples: [CursorTrailsSample], _ dots: [CursorTrailsDot], to tip: CGPoint, at now: TimeInterval, lifetime: TimeInterval,
                     width: Int, stops: [UInt32]) -> (samples: [CursorTrailsSample], dots: [CursorTrailsDot]) {
        let samples = CursorTrailsSample.advance(samples, to: tip, at: now, length: lifetime + CursorTrailsStyle.pause)
        let moving = samples.last.map { now - $0.time < CursorTrailsStyle.pause } ?? false
        return (samples, advance(dots, spawningAt: moving ? tip : nil, at: now, lifetime: lifetime, width: width, stops: stops))
    }

    static func picture(_ dots: [CursorTrailsDot], at now: TimeInterval, lifetime: TimeInterval, fade: Bool,
                        in screen: CGRect, scale: CGFloat) -> (frame: CGRect, image: CGImage)? {
        let area = dots.reduce(CGRect.null) {
            let spot = $1.spot(at: now)
            return $0.union(CGRect(x: spot.x - $1.radius, y: spot.y - $1.radius, width: 2 * $1.radius, height: 2 * $1.radius))
        }
        return CursorTrailsPiece.picture(area, in: screen, scale: scale) { context in
            for dot in dots {
                let spot = dot.spot(at: now)
                context.setAlpha(dot.alpha(at: now, lifetime: lifetime, fade: fade))
                context.drawRadialGradient(dot.gradient, startCenter: spot, startRadius: 0, endCenter: spot, endRadius: dot.radius, options: [])
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
