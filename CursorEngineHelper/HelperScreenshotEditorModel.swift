import AppKit
import Combine
import CoreImage
import UniformTypeIdentifiers

enum CursorScreenshotEditorLook {
    static let digitColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    static let highlightAlpha: CGFloat = 0.4
    static let highlightLinePad: CGFloat = 0.1
    static let highlightLineCorner: CGFloat = 0.18
    static let textLineReachPoints: CGFloat = 4
    static let blockPoints: CGFloat = 8
    static let arrowHeadLength: CGFloat = 3.5
    static let arrowHeadWidth: CGFloat = 3.5
    static let smallestDrag: CGFloat = 3
    static let undoLevels = 50
    static let straightenLengthPoints: CGFloat = 24
    static let straightenDegrees: CGFloat = 10
    static let smallestCropPoints: CGFloat = 10
    static let cropOutsideShare: CGFloat = 0.5
    static let cropSnapPoints: CGFloat = 10
    static let cropKeySnapPoints: CGFloat = 4
    static let cropBigKeySnapPoints: CGFloat = 10
    static let cropLineReachPoints: CGFloat = 7.5
    static let cropLineLengthPoints: CGFloat = 20
    static let cropLineStep = 13
    static let cropCornerGrip: CGFloat = 30
    static let cropEdgeGripAcross: CGFloat = 20
    static let cropEdgeGripAlong: CGFloat = 30
    static let cropStripAcross: CGFloat = 10
    static let cropStripTrim: CGFloat = 45
    static let cropFitShare: CGFloat = 0.8
    static let cropFitTrim: CGFloat = 60
    static let cropFitTrimAbove: CGFloat = 100
    static let cropSizeLimit = 99999
    static let myColorSlots = 10
    static let handleReachPoints: CGFloat = 11
    static let markReachPoints: CGFloat = 4
    static let selectedReachPoints: CGFloat = 6
    static let snapPoints: CGFloat = 7
    static let copyOffsetPoints: CGFloat = 8
    static let dropBandPoints: CGFloat = 100
    static let largestImageSide = 16384
    static let nudgePoints: CGFloat = 1
    static let bigNudgePoints: CGFloat = 10
    static let penStepPoints: CGFloat = 5
    static let penSmoothFrom = 6
    static let spotlightCornerPoints: CGFloat = 10
    static let spotlightCornerFactor: CGFloat = 1.52866483
    static let filledCornerPoints: CGFloat = 5
    static let firstDim: CGFloat = 45
    static let dimRange: ClosedRange<CGFloat> = 5...90
    static let strengthRange: ClosedRange<CGFloat> = 3...30
    static let curveBend: CGFloat = 0.25
    static let smallestTextWidthPoints: CGFloat = 20
    static let largestStartingNumber = 999
    static let newTextWidthPoints: CGFloat = 100
    static let textBoxCharacterLimit = 61
    static let outlineShare: CGFloat = 0.2
    static let contrastAgainstWhite: CGFloat = 1.6
    static let tintShare: CGFloat = 0.92
}

enum CursorScreenshotArrowStyle: String, CaseIterable, Codable, Sendable {
    case standard, fancy, curved, double

    var isCurved: Bool { self == .curved || self == .double }
}

enum CursorScreenshotSpotlightShape: String, CaseIterable, Codable, Sendable {
    case rectangle, rounded, oval
}

enum CursorScreenshotRedactionStyle: String, CaseIterable, Codable, Sendable {
    case pixelate, secureBlur, blur, blackOut
}

enum CursorScreenshotTextStyle: String, CaseIterable, Codable, Sendable {
    case standard, rounded, outlined, mono, box, monoBox, roundedBox

    var hasBox: Bool { self == .box || self == .monoBox || self == .roundedBox }

    func font(ofSize size: CGFloat) -> NSFont {
        switch self {
        case .mono, .monoBox:
            return NSFont.monospacedSystemFont(ofSize: size, weight: .bold)
        case .rounded, .roundedBox:
            let bold = NSFont.boldSystemFont(ofSize: size)
            return bold.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? bold
        case .standard, .outlined, .box:
            return NSFont.boldSystemFont(ofSize: size)
        }
    }

    func boxShape(lineHeight: CGFloat, characters: Int) -> (extraWidth: CGFloat, height: CGFloat, radius: CGFloat) {
        let long = characters >= CursorScreenshotEditorLook.textBoxCharacterLimit
        switch (self, long) {
        case (.box, false): return (1.1 * lineHeight, 1.4 * lineHeight, 1.4 * lineHeight * 0.125)
        case (.box, true): return (lineHeight, 1.5 * lineHeight, 1.5 * lineHeight * 0.125)
        case (.monoBox, false): return (1.1 * lineHeight, 1.4 * lineHeight, 0)
        case (.monoBox, true): return (0.5 * lineHeight, 1.15 * lineHeight, 0)
        case (_, false): return (1.1 * lineHeight, 1.4 * lineHeight, 1.4 * lineHeight / 2)
        case (_, true): return (1.1 * lineHeight, 1.6 * lineHeight, 1.6 * lineHeight / 2.5)
        }
    }

    func shapeColor(behind color: CursorScreenshotColor) -> CursorScreenshotColor {
        let look = CursorScreenshotEditorLook.self
        let standsOut = color.contrastAgainstWhite > look.contrastAgainstWhite
        guard self == .box || self == .roundedBox else {
            return CursorScreenshotColor(hex: standsOut ? "FFFFFF" : "000000") ?? color
        }
        if color.hex == "000000" { return CursorScreenshotColor(red: 1, green: 1, blue: 1) }
        if color.hex == "FFFFFF" { return CursorScreenshotColor(red: 0, green: 0, blue: 0) }
        let target: CGFloat = standsOut ? 1 : 0
        let mix = { (part: CGFloat) in part + (target - part) * look.tintShare }
        return CursorScreenshotColor(red: mix(color.red), green: mix(color.green), blue: mix(color.blue), alpha: color.alpha)
    }
}

enum CursorScreenshotNumberStyle: String, CaseIterable, Codable, Sendable {
    case digits, upper, roman, lower

    func label(_ number: Int) -> String {
        switch self {
        case .digits: return String(number)
        case .upper: return Self.letters(number)
        case .lower: return Self.letters(number).lowercased()
        case .roman: return Self.roman(number)
        }
    }

    private static func letters(_ number: Int) -> String {
        var left = max(number, 1)
        var text = ""
        while left > 0 {
            left -= 1
            text = String(UnicodeScalar(UInt8(65 + left % 26))) + text
            left /= 26
        }
        return text
    }

    private static func roman(_ number: Int) -> String {
        guard (1...3999).contains(number) else { return String(number) }
        let steps = [(1000, "M"), (900, "CM"), (500, "D"), (400, "CD"), (100, "C"), (90, "XC"), (50, "L"), (40, "XL"), (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")]
        var left = number
        var text = ""
        for (value, letters) in steps {
            while left >= value {
                text += letters
                left -= value
            }
        }
        return text
    }
}

struct CursorScreenshotShared: Equatable, Sendable {
    var dim = CursorScreenshotEditorLook.firstDim
    var redaction = CursorScreenshotRedactionStyle.pixelate
    var strength = CursorScreenshotEditorLook.blockPoints
    var dimArea: CGRect?
}

enum CursorScreenshotMarkHandle: Equatable, Sendable {
    case topLeft, topRight, bottomLeft, bottomRight, start, end, control, textLeft, textRight, textWidth
}

struct CursorScreenshotColor: Codable, Equatable, Sendable {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
    var alpha: CGFloat = 1

    static let first = CursorScreenshotColor(hex: "FF383C") ?? CursorScreenshotColor(red: 1, green: 0, blue: 0)
    static let palette = ["000000", "FF383C", "FF8B00", "FFE100", "40D652", "2ECFC2", "007AFF", "8A52FF", "FF2E6B", "FFFFFF"].compactMap { CursorScreenshotColor(hex: $0) }

    init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init?(hex text: String, alpha: CGFloat = 1) {
        let digits = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        guard digits.count == 6, digits.allSatisfy(\.isHexDigit), let value = Int(digits, radix: 16) else { return nil }
        self.init(red: CGFloat(value >> 16 & 255) / 255, green: CGFloat(value >> 8 & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: alpha)
    }

    init(hue: CGFloat, saturation: CGFloat, brightness: CGFloat, alpha: CGFloat = 1) {
        let sector = (hue.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1) * 6
        let part = sector - floor(sector)
        let low = brightness * (1 - saturation)
        let falling = brightness * (1 - saturation * part)
        let rising = brightness * (1 - saturation * (1 - part))
        let parts: (CGFloat, CGFloat, CGFloat)
        switch Int(sector) {
        case 0: parts = (brightness, rising, low)
        case 1: parts = (falling, brightness, low)
        case 2: parts = (low, brightness, rising)
        case 3: parts = (low, falling, brightness)
        case 4: parts = (rising, low, brightness)
        default: parts = (brightness, low, falling)
        }
        self.init(red: parts.0, green: parts.1, blue: parts.2, alpha: alpha)
    }

    var cgColor: CGColor { CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }

    var hex: String {
        String(format: "%02X%02X%02X", byte(red), byte(green), byte(blue))
    }

    var hsb: (hue: CGFloat, saturation: CGFloat, brightness: CGFloat) {
        let top = max(red, green, blue)
        let spread = top - min(red, green, blue)
        guard spread > 0 else { return (0, 0, top) }
        let sector: CGFloat
        switch top {
        case red: sector = (green - blue) / spread
        case green: sector = (blue - red) / spread + 2
        default: sector = (red - green) / spread + 4
        }
        return (((sector / 6) + 1).truncatingRemainder(dividingBy: 1), spread / top, top)
    }

    var isNearWhite: Bool { red > 0.9 && green > 0.9 && blue > 0.9 }

    var isNearBlack: Bool { red < 0.1 && green < 0.1 && blue < 0.1 }

    func sameShade(as other: CursorScreenshotColor) -> Bool {
        hex == other.hex
    }

    var contrastAgainstWhite: CGFloat {
        let linear = { (part: CGFloat) in part <= 0.03928 ? part / 12.92 : pow((part + 0.055) / 1.055, 2.4) }
        return 1.05 / (0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue) + 0.05)
    }

    private func byte(_ part: CGFloat) -> Int {
        Int((min(max(part, 0), 1) * 255).rounded())
    }

    fileprivate var checked: CursorScreenshotColor {
        let clamp = { (part: CGFloat) in part.isFinite ? min(max(part, 0), 1) : 1 }
        return CursorScreenshotColor(red: clamp(red), green: clamp(green), blue: clamp(blue), alpha: clamp(alpha))
    }
}

enum CursorScreenshotSizeKind: Sendable {
    case thickness, highlight, text, number

    var values: [CGFloat] {
        switch self {
        case .thickness: return [1, 3, 7, 10, 15, 25]
        case .highlight: return [1, 3, 7, 9, 10, 15, 25]
        case .text: return [10, 13, 16, 20, 24, 30, 36, 48, 72, 96, 144, 216, 288]
        case .number: return [11, 14, 20, 24, 31, 45]
        }
    }
}

enum CursorScreenshotTool: String, CaseIterable, Codable, Sendable {
    case select, box, filledBox, oval, line, arrow, pen, text, pixelate, spotlight, highlight, number, image

    static let allCases: [CursorScreenshotTool] = [.select, .box, .filledBox, .oval, .line, .arrow, .pen, .text, .pixelate, .spotlight, .highlight, .number]

    var letter: String {
        switch self {
        case .select: return "v"
        case .box: return "r"
        case .filledBox: return "f"
        case .oval: return "e"
        case .line: return "l"
        case .arrow: return "a"
        case .pen: return "d"
        case .text: return "t"
        case .pixelate: return "p"
        case .spotlight: return "h"
        case .highlight: return "m"
        case .number: return "c"
        case .image: return ""
        }
    }

    var hasColor: Bool {
        switch self {
        case .box, .filledBox, .oval, .line, .arrow, .pen, .text, .highlight, .number: return true
        case .select, .pixelate, .spotlight, .image: return false
        }
    }

    var sizeKind: CursorScreenshotSizeKind? {
        switch self {
        case .box, .oval, .line, .arrow, .pen: return .thickness
        case .highlight: return .highlight
        case .text: return .text
        case .number: return .number
        case .select, .filledBox, .pixelate, .spotlight, .image: return nil
        }
    }
}

struct CursorScreenshotEditorChoices: Codable, Equatable, Sendable {
    static func startingNumber(typed: String) -> Int? {
        let digits = typed.filter { $0.isASCII && $0.isNumber }
        guard !digits.isEmpty, (Int(digits) ?? .max) >= 1 else { return nil }
        return Int(digits) ?? .max
    }

    var tool = CursorScreenshotTool.arrow
    var color = CursorScreenshotColor.first
    var thickness: CGFloat = 7
    var highlight: CGFloat = 9
    var text: CGFloat = 30
    var number: CGFloat = 24
    var myColors: [CursorScreenshotColor] = []
    var pickerOpen = false
    var arrowStyle = CursorScreenshotArrowStyle.standard
    var spotlightShape = CursorScreenshotSpotlightShape.rounded
    var textStyle = CursorScreenshotTextStyle.standard
    var numberStyle = CursorScreenshotNumberStyle.digits
    var startingNumber = 1
    var dim = CursorScreenshotEditorLook.firstDim
    var redaction = CursorScreenshotRedactionStyle.pixelate
    var strength = CursorScreenshotEditorLook.blockPoints
    var canvasLocked = true
    var snapsCrop = true

    static func decoded(from data: Data?) -> CursorScreenshotEditorChoices {
        guard let data, var choices = try? JSONDecoder().decode(CursorScreenshotEditorChoices.self, from: data) else { return CursorScreenshotEditorChoices() }
        let look = CursorScreenshotEditorLook.self
        choices.dim = min(max(choices.dim.isFinite ? choices.dim : look.firstDim, look.dimRange.lowerBound), look.dimRange.upperBound)
        choices.strength = min(max(choices.strength.isFinite ? choices.strength : look.blockPoints, look.strengthRange.lowerBound), look.strengthRange.upperBound)
        choices.startingNumber = min(max(choices.startingNumber, 1), look.largestStartingNumber)
        choices.color = choices.color.checked
        choices.myColors = Array(choices.myColors.prefix(CursorScreenshotEditorLook.myColorSlots)).map(\.checked)
        let wholeRange = { (size: CGFloat, kind: CursorScreenshotSizeKind) in
            min(max(size.isFinite ? size : 1, kind.values[0]), kind.values[kind.values.count - 1])
        }
        choices.thickness = wholeRange(choices.thickness, .thickness)
        choices.highlight = wholeRange(choices.highlight, .highlight)
        choices.text = wholeRange(choices.text, .text)
        choices.number = wholeRange(choices.number, .number)
        return choices
    }

    static func load() -> CursorScreenshotEditorChoices {
        CFPreferencesSynchronize(MACPreferences.domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        return decoded(from: MACPreferences.value(forKey: MACPreferences.cursorScreenshotMarkupKey) as? Data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        MACPreferences.set(data, forKey: MACPreferences.cursorScreenshotMarkupKey)
    }

    func size(of kind: CursorScreenshotSizeKind) -> CGFloat {
        switch kind {
        case .thickness: return thickness
        case .highlight: return highlight
        case .text: return text
        case .number: return number
        }
    }
}

enum CursorScreenshotZoom {
    static let stops: [CGFloat] = [0.1, 0.25, 0.5, 1, 2, 4, 8, 16, 32]
    static let cropStops: [CGFloat] = [0.25, 0.5, 1, 2, 4, 8, 16]
    static let menuStops: [CGFloat] = [0.5, 1, 2, 4]
    static let tooClose: CGFloat = 0.1

    static func clamped(_ zoom: CGFloat, cropping: Bool = false) -> CGFloat {
        let stops = cropping ? cropStops : stops
        return min(max(zoom, stops[0]), stops[stops.count - 1])
    }

    static func stepped(from zoom: CGFloat, up: Bool, cropping: Bool = false) -> CGFloat {
        let stops = cropping ? cropStops : stops
        let next = up ? stops.first { $0 - zoom >= tooClose - 0.0001 } : stops.last { zoom - $0 >= tooClose - 0.0001 }
        return next ?? (up ? max(zoom, stops[stops.count - 1]) : min(zoom, stops[0]))
    }
}

struct CursorScreenshotMark: Equatable, Sendable {
    var tool: CursorScreenshotTool
    var start: CGPoint
    var end: CGPoint
    var path: [CGPoint] = []
    var text = ""
    var number = 0
    var color = CursorScreenshotColor.first
    var size: CGFloat = 7
    var arrowStyle = CursorScreenshotArrowStyle.standard
    var reversed = false
    var control: CGPoint?
    var shape = CursorScreenshotSpotlightShape.rounded
    var textStyle = CursorScreenshotTextStyle.standard
    var wrap: CGFloat = 0
    var numberStyle = CursorScreenshotNumberStyle.digits
    var image: CursorScreenshotPicture?
    var isTextLine = false

    var rect: CGRect {
        let ends = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
        let bend = tool == .arrow && arrowStyle.isCurved ? [curve] : []
        return (path + bend).reduce(ends) { $0.union(CGRect(origin: $1, size: .zero)) }
    }

    var curve: CGPoint {
        if let control { return control }
        let bend = CursorScreenshotEditorLook.curveBend
        return CGPoint(x: (start.x + end.x) / 2 + (end.y - start.y) * bend, y: (start.y + end.y) / 2 - (end.x - start.x) * bend)
    }

    var isBigEnough: Bool {
        let smallest = CursorScreenshotEditorLook.smallestDrag
        switch tool {
        case .arrow, .line: return hypot(end.x - start.x, end.y - start.y) >= smallest
        case .highlight: return max(rect.width, rect.height) >= smallest
        case .pen: return true
        default: return rect.width >= smallest && rect.height >= smallest
        }
    }

    func moved(by delta: CGPoint) -> CursorScreenshotMark {
        let shift = { (point: CGPoint) in CGPoint(x: point.x + delta.x, y: point.y + delta.y) }
        var mark = self
        mark.start = shift(start)
        mark.end = shift(end)
        mark.path = path.map(shift)
        mark.control = control.map(shift)
        return mark
    }
}

struct CursorScreenshotCloseRequest {
    let next: @MainActor () -> Void
    let cancelled: @MainActor () -> Void
}

struct CursorScreenshotCloseQueue {
    private var newest: CursorScreenshotCloseRequest?
    private var isAsking = false

    var isWaiting: Bool { newest != nil }

    func closesAtOnce(isDirty: Bool, hasSheet: Bool) -> Bool {
        !isDirty && !hasSheet && !isWaiting
    }

    func waitsForSheet(hasSheet: Bool) -> Bool {
        hasSheet && !isAsking
    }

    mutating func start(_ request: CursorScreenshotCloseRequest, asking: Bool = true) {
        newest = request
        isAsking = asking
    }

    mutating func joined(_ request: CursorScreenshotCloseRequest) -> CursorScreenshotCloseRequest {
        guard let older = newest else { return request }
        newest = request
        return older
    }

    mutating func end() -> CursorScreenshotCloseRequest? {
        defer {
            newest = nil
            isAsking = false
        }
        return newest
    }
}

enum CursorScreenshotCropFill: Equatable, Sendable {
    case transparent, auto, color(CursorScreenshotColor)

    static let white = CursorScreenshotCropFill.color(CursorScreenshotColor(red: 1, green: 1, blue: 1))
    static let gray = CursorScreenshotCropFill.color(CursorScreenshotColor(red: 0.5, green: 0.5, blue: 0.5))
    static let black = CursorScreenshotCropFill.color(CursorScreenshotColor(red: 0, green: 0, blue: 0))

    func resolved(for picture: CursorScreenshotPicture) -> CursorScreenshotColor? {
        switch self {
        case .transparent: return nil
        case .auto: return picture.autoFill
        case .color(let color): return color
        }
    }
}

struct CursorScreenshotEdit: Equatable, Sendable {
    var marks: [CursorScreenshotMark] = []
    var crop: CGRect
    var shared = CursorScreenshotShared()
    var fill = CursorScreenshotCropFill.transparent
    var outputScale: CGFloat = 1
    var burns = 0
    var background = CursorScreenshotBackgroundStyle()
    var balance = CursorScreenshotBalance()
    var backdrop: CGImage?
    var presetID: String?
    var chosenBackgroundValue = false

    var outputSize: CGSize { Self.output(of: crop.size, scale: outputScale) }

    static func output(of size: CGSize, scale: CGFloat) -> CGSize {
        CGSize(width: max((size.width * scale).rounded(), 1), height: max((size.height * scale).rounded(), 1))
    }

    var hasBackground: Bool {
        background.fill != .none || background.padding > 0 || background.corners > 0 || background.shadow > 0 || background.inset > 0 || !balance.isZero
    }

    mutating func spreadDim() {
        shared.dimArea = background.fill.isOpaque ? crop : nil
    }

    func layout(of box: CGSize? = nil, scale: CGFloat) -> CursorScreenshotCanvasLayout {
        CursorScreenshotCanvasLayout(content: box ?? crop.size, style: background, balance: balance, scale: scale)
    }

    fileprivate func effect(on picture: CursorScreenshotPicture) -> CursorScreenshotEdit {
        var kept = self
        kept.presetID = nil
        kept.chosenBackgroundValue = false
        if !marks.contains(where: { $0.tool == .spotlight }) { kept.shared.dim = 0 }
        if !marks.contains(where: { $0.tool == .pixelate }) {
            kept.shared.redaction = .pixelate
            kept.shared.strength = 0
        }
        if !picture.hasTransparency, background.inset == 0, balance.isZero, CGRect(origin: .zero, size: picture.size).contains(crop) { kept.fill = .transparent }
        if background.padding == 0 {
            kept.background.alignment = CursorScreenshotBackgroundStyle().alignment
            kept.background.ratio = CursorScreenshotBackgroundStyle().ratio
        }
        return kept
    }
}

enum CursorScreenshotBackgroundLook {
    static let shadowDrop: CGFloat = 0.4
    static let shadowBlur: CGFloat = 1.2
    static let shadowAlpha: CGFloat = 0.006
    static let panelWidth: CGFloat = 250
    static let slideTime: TimeInterval = 0.3
    static let slideStep: TimeInterval = 1.0 / 60
    static let nameFieldSize = CGSize(width: 350, height: 20)

    static func grownFrame(_ frame: CGRect, contentHeight: CGFloat, needed: CGFloat, visible: CGRect) -> CGRect {
        guard contentHeight < needed else { return frame }
        let bottom = max(frame.minY - (needed - contentHeight), min(visible.minY, frame.minY))
        return CGRect(x: frame.minX, y: bottom, width: frame.width, height: frame.maxY - bottom)
    }

    static func fittedFont(_ title: String, font: NSFont, width: CGFloat, padding: CGFloat) -> NSFont {
        var fitted = font
        while fitted.pointSize > 1, ceil(NSAttributedString(string: title, attributes: [.font: fitted]).size().width) + padding * 2 > width {
            fitted = fitted.withSize(fitted.pointSize - 0.25)
        }
        return fitted
    }

    @MainActor static func sliderLabel(_ word: String, font: NSFont) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: word)
        label.isSelectable = false
        label.font = font
        return label
    }

    static func fittedFont(wrapping word: String, font: NSFont, room: CGSize) -> NSFont {
        var fitted = font
        let parts = word.split(separator: " ").map(String.init).filter { $0.lowercased() != $0.uppercased() }
        while fitted.pointSize > 1 {
            let high = NSAttributedString(string: word, attributes: [.font: fitted]).boundingRect(with: CGSize(width: room.width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading]).height
            let wide = parts.map { ceil(NSAttributedString(string: $0, attributes: [.font: fitted]).size().width) }.max() ?? 0
            if high <= room.height, wide <= room.width { break }
            fitted = fitted.withSize(fitted.pointSize - 0.25)
        }
        return fitted
    }
}

enum CursorScreenshotCropSizeLayout {
    static func labelWidth(_ measured: [CGFloat]) -> CGFloat {
        max(60, ceil(measured.max() ?? 0))
    }

    static func flattenRow(box: CGSize, note: CGSize, width: CGFloat) -> (box: CGPoint, note: CGPoint) {
        let side: CGFloat = 20
        let beside = side + box.width + 6
        guard beside + note.width > width - side else { return (CGPoint(x: side, y: 90), CGPoint(x: beside, y: 91)) }
        return (CGPoint(x: side, y: 82), CGPoint(x: side + 18, y: 100))
    }
}

enum CursorScreenshotColorPlace {
    static func kept(_ frame: CGRect, inside visible: CGRect) -> CGRect {
        CGRect(x: min(max(frame.minX, visible.minX), visible.maxX - frame.width), y: min(max(frame.minY, visible.minY), visible.maxY - frame.height), width: frame.width, height: frame.height)
    }
}

extension CursorScreenshotBackdropFill {
    var drawsWithoutImage: Bool {
        switch self {
        case .none, .color, .gradient: return true
        default: return false
        }
    }

    var plainColor: CursorScreenshotColor? {
        guard case .color(let hex, let alpha) = self else { return nil }
        return CursorScreenshotColor(hex: hex, alpha: alpha)
    }
}

@MainActor
enum CursorScreenshotSystemColors {
    private static weak var owner: NSObject?
    private static var pressMonitor: Any?
    private(set) static var press = 0

    static func color(of panel: NSColorPanel) -> CursorScreenshotColor? {
        guard let color = panel.color.usingColorSpace(.sRGB) else { return nil }
        return CursorScreenshotColor(red: color.redComponent, green: color.greenComponent, blue: color.blueComponent, alpha: color.alphaComponent)
    }

    static func take(for target: NSObject, action: Selector, current: CursorScreenshotColor?) {
        let panel = NSColorPanel.shared
        owner = target
        if pressMonitor == nil {
            pressMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyDown]) { event in
                MainActor.assumeIsolated { press += 1 }
                return event
            }
        }
        panel.setTarget(nil)
        panel.setAction(nil)
        panel.showsAlpha = true
        panel.isContinuous = true
        if !holds(current, panel) { panel.color = .white }
        panel.setTarget(target)
        panel.setAction(action)
    }

    static func follow(_ current: CursorScreenshotColor?, for target: NSObject, action: Selector) {
        guard owner === target else { return }
        take(for: target, action: action, current: current)
    }

    static func close(for target: NSObject) {
        guard owner === target else { return }
        owner = nil
        if let pressMonitor { NSEvent.removeMonitor(pressMonitor) }
        pressMonitor = nil
        NSColorPanel.shared.setTarget(nil)
        NSColorPanel.shared.setAction(nil)
        NSColorPanel.shared.close()
    }

    private static func holds(_ color: CursorScreenshotColor?, _ panel: NSColorPanel) -> Bool {
        guard let color, let held = self.color(of: panel) else { return false }
        return held.sameShade(as: color) && held.alpha == color.alpha
    }
}

struct CursorScreenshotBalance: Equatable, Sendable {
    var top: CGFloat = 0
    var left: CGFloat = 0
    var bottom: CGFloat = 0
    var right: CGFloat = 0

    var isZero: Bool { top == 0 && left == 0 && bottom == 0 && right == 0 }

    static let sampleStepPoints: CGFloat = 2
    static let sameBelow = 14

    static func from(borders: CursorScreenshotBalance) -> CursorScreenshotBalance {
        let sides = [borders.top, borders.left, borders.bottom, borders.right]
        guard sides.filter({ $0 > 0 }).count >= 2, let largest = sides.max() else { return CursorScreenshotBalance() }
        let extra = { (side: CGFloat) in side > 0 ? largest - side : 0 }
        return CursorScreenshotBalance(top: extra(borders.top), left: extra(borders.left), bottom: extra(borders.bottom), right: extra(borders.right))
    }

    static func borders(pixels: UnsafePointer<UInt8>, bytesPerRow: Int, width: Int, height: Int, step: Int) -> CursorScreenshotBalance {
        let spot = { (x: Int, y: Int) in pixels + y * bytesPerRow + x * 4 }
        let same = { (one: UnsafePointer<UInt8>, two: UnsafePointer<UInt8>) in (0..<4).allSatisfy { abs(Int(one[$0]) - Int(two[$0])) < sameBelow } }
        let plainRow = { (y: Int) in stride(from: 0, to: width, by: step).allSatisfy { same(spot($0, y), spot(0, y)) } }
        let plainColumn = { (x: Int) in stride(from: 0, to: height, by: step).allSatisfy { same(spot(x, $0), spot(x, 0)) } }
        let count = { (lines: [Int], plain: (Int) -> Bool) in CGFloat(lines.firstIndex { !plain($0) } ?? lines.count) }
        let top = count(Array(0..<height), plainRow)
        guard Int(top) < height else { return CursorScreenshotBalance() }
        return CursorScreenshotBalance(top: top, left: count(Array(0..<width), plainColumn),
                                       bottom: count(Array((0..<height).reversed()), plainRow), right: count(Array((0..<width).reversed()), plainColumn))
    }

    static func measured(_ image: CGImage, crop: CGRect, scale: CGFloat) -> CursorScreenshotBalance {
        let area = crop.integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard !area.isEmpty, let piece = image.cropping(to: area),
              let context = CursorScreenshotPicture.context(width: piece.width, height: piece.height, space: CursorScreenshotPicture.sRGB),
              let bytes = context.data else { return CursorScreenshotBalance() }
        context.draw(piece, in: CGRect(x: 0, y: 0, width: piece.width, height: piece.height))
        return from(borders: borders(pixels: bytes.assumingMemoryBound(to: UInt8.self), bytesPerRow: context.bytesPerRow, width: piece.width, height: piece.height,
                                     step: max(Int(sampleStepPoints * scale), 1)))
    }
}

struct CursorScreenshotCanvasLayout: Equatable, Sendable {
    let size: CGSize
    let frame: CGRect
    let content: CGRect
    let radius: CGFloat

    static let centreRowShare: CGFloat = 0.6

    init(content contentSize: CGSize, style: CursorScreenshotBackgroundStyle, balance: CursorScreenshotBalance, scale: CGFloat) {
        let inset = style.inset * scale
        let box = CGSize(width: contentSize.width + balance.left + balance.right + inset * 2, height: contentSize.height + balance.top + balance.bottom + inset * 2)
        let margins = Self.margins(around: box, padding: style.padding * scale, alignment: style.alignment, ratio: style.ratio.shape)
        size = CGSize(width: box.width + margins.left + margins.right, height: box.height + margins.top + margins.bottom)
        frame = CGRect(origin: CGPoint(x: margins.left, y: margins.top), size: box)
        content = CGRect(origin: CGPoint(x: margins.left + inset + balance.left, y: margins.top + inset + balance.top), size: contentSize)
        radius = style.corners / 100 * min(box.width, box.height) * 0.5
    }

    static func margins(around box: CGSize, padding: CGFloat, alignment: Int, ratio: CGFloat?) -> (left: CGFloat, right: CGFloat, top: CGFloat, bottom: CGFloat) {
        let (column, row) = (alignment % 3, alignment / 3)
        guard let ratio, padding > 0 else {
            let across = [(0, padding), (padding, padding), (padding, 0)][column]
            var down = [(0, padding), (padding, padding), (padding, 0)][row]
            if column == 1, row == 0 { down = (0, (padding * centreRowShare).rounded()) }
            if column == 1, row == 2 { down = ((padding * centreRowShare).rounded(), 0) }
            return (across.0, across.1, down.0, down.1)
        }
        let wide = (max(box.width + padding * 2, (box.height + padding * 2) * ratio)).rounded()
        let high = (max(box.height + padding * 2, (box.width + padding * 2) / ratio)).rounded()
        let left = ((wide - box.width) * CGFloat(column) / 2).rounded()
        let top = ((high - box.height) * CGFloat(row) / 2).rounded()
        return (left, wide - box.width - left, top, high - box.height - top)
    }
}

extension CursorScreenshotBackgroundStyle {
    static let firstShadow: CGFloat = 28

    func withAutoValues(forPoints size: CGSize) -> CursorScreenshotBackgroundStyle {
        var style = self
        let short = min(size.width, size.height)
        let average = ((size.width + size.height) / 2).rounded(.down)
        if shadow == 0 { style.shadow = Self.firstShadow }
        style.corners = short < 100 ? 30 : short < 300 ? 15 : 8
        if padding == 0 { style.padding = min((average < 500 ? average / 12 + 50 : average / 13 + 30).rounded(.down), Self.paddingRange.upperBound) }
        return style
    }
}

enum CursorScreenshotBackdrops {
    static let colors = ["121212", "FFFFFF", "E33345", "F78521", "F2A81A", "178F52", "0D8CE8", "8A38F5", nil, "383838", "EBEBEB", "FABDB5", "FFC470", "FADE8F", "A1E8BA", "A8D6FA", "D6B5FA"] as [String?]
    static let gradients: [(angle: CGFloat, stops: [String])] = [
        (135, ["2F6FED", "5B5BE0", "7E48D4"]), (135, ["F2A33A", "E8601C", "B3261E"]), (135, ["E3D54A", "8CCB4A", "2E9E5B"]), (135, ["1FB5B0", "2D9CDB", "3B6FD8"]),
        (135, ["7E48D4", "C14FC4", "E8559A"]), (135, ["A3ABB8", "818B99", "5C6676"]), (135, ["FBE9C6", "F6D3A1", "EFB58A"]), (135, ["E6F0FA", "C9DDF2", "AEC7E8"]),
        (135, ["E4F7E6", "BFEBD0", "9ADCC4"]), (135, ["FBE3EC", "F5C6D8", "E9A9C9"]), (160, ["2A2F5E", "6A3F86", "C45C7E"]), (160, ["0F1626", "1E2A44", "34466E"])
    ]
    static let thumbnailSide = 256
    static let blurSide = 1600
    static let wallpaperSide = 6500
    static let blurShare: CGFloat = 0.04
    static let darkCover: CGFloat = 0.75
    static let grey: CGFloat = 0.5

    static func gradientLine(angle: CGFloat, in rect: CGRect) -> (start: CGPoint, end: CGPoint) {
        let turn = angle * .pi / 180
        let (across, down) = (sin(turn), -cos(turn))
        let half = (abs(rect.width * sin(turn)) + abs(rect.height * cos(turn))) / 2
        return (CGPoint(x: rect.midX - across * half, y: rect.midY - down * half), CGPoint(x: rect.midX + across * half, y: rect.midY + down * half))
    }

    static func decoded(_ url: URL, side: Int) -> CGImage? {
        CursorScreenshotImageSource.image(from: CGImageSourceCreateWithURL(url as CFURL, nil), side: side)
    }

    static func blurred(_ image: CGImage, dark: Bool) -> CGImage? {
        let shrink = min(CGFloat(blurSide) / CGFloat(max(image.width, image.height)), 1)
        let input = CIImage(cgImage: image).transformed(by: CGAffineTransform(scaleX: shrink, y: shrink))
        let whole = input.extent
        let radius = ((whole.width + whole.height) / 2 * blurShare).rounded(.down)
        let ground = CIImage(color: CIColor(red: grey, green: grey, blue: grey)).cropped(to: whole.insetBy(dx: -radius * 3, dy: -radius * 3))
        var output = input.clampedToExtent().composited(over: ground).applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius]).cropped(to: whole)
        if dark { output = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: darkCover)).cropped(to: whole).composited(over: output) }
        let space = CursorScreenshotPicture.sRGB
        return CIContext(options: [.cacheIntermediates: false, .workingColorSpace: space]).createCGImage(output, from: whole, format: .RGBA8, colorSpace: space)
    }
}

struct CursorScreenshotBackdropSource: Sendable {
    var wallpaperFolder: URL?
    var desktop: URL?

    private func file(_ id: String) -> URL? {
        UUID(uuidString: id) == nil ? nil : wallpaperFolder?.appendingPathComponent(id, isDirectory: false)
    }

    func image(for fill: CursorScreenshotBackdropFill, picture: CGImage) -> CGImage? {
        let look = CursorScreenshotBackdrops.self
        switch fill {
        case .none, .color, .gradient: return nil
        case .wallpaper(let id): return file(id).flatMap { look.decoded($0, side: look.wallpaperSide) }
        case .desktop: return desktop.flatMap { look.decoded($0, side: look.wallpaperSide) }
        case .blurredDesktop: return desktop.flatMap { look.decoded($0, side: look.blurSide) }.flatMap { look.blurred($0, dark: false) }
        case .blurredPicture: return look.blurred(picture, dark: false)
        case .blurredPictureDark: return look.blurred(picture, dark: true)
        }
    }

    func wallpaperThumbnail(_ id: String) -> CGImage? {
        file(id).flatMap { CursorScreenshotBackdrops.decoded($0, side: CursorScreenshotBackdrops.thumbnailSide) }
    }

    func thumbnails(wallpapers: [String], picture: CGImage) -> [CursorScreenshotBackdropFill: CGImage] {
        let look = CursorScreenshotBackdrops.self
        var found: [CursorScreenshotBackdropFill: CGImage] = [:]
        for id in wallpapers { found[.wallpaper(id)] = wallpaperThumbnail(id) }
        found[.desktop] = desktop.flatMap { look.decoded($0, side: look.thumbnailSide) }
        for fill in [CursorScreenshotBackdropFill.blurredDesktop, .blurredPicture, .blurredPictureDark] { found[fill] = image(for: fill, picture: picture) }
        return found
    }

    func addWallpaper(from url: URL) -> String? {
        let look = CursorScreenshotBackdrops.self
        let id = UUID().uuidString
        guard let target = file(id), let folder = wallpaperFolder, let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let found = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let wide = found[kCGImagePropertyPixelWidth] as? Int, let high = found[kCGImagePropertyPixelHeight] as? Int,
              look.decoded(url, side: look.thumbnailSide) != nil,
              (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)) != nil else { return nil }
        if max(wide, high) <= look.wallpaperSide { return (try? FileManager.default.copyItem(at: url, to: target)) == nil ? nil : id }
        let format: CursorScreenshotFormat = url.pathExtension.lowercased() == "png" ? .png : .jpeg
        guard let data = look.decoded(url, side: look.wallpaperSide).flatMap({ format.data(of: $0, scale: 1) }), (try? data.write(to: target, options: .atomic)) != nil else { return nil }
        return id
    }

    func removeWallpaper(_ id: String) {
        if let target = file(id) { try? FileManager.default.removeItem(at: target) }
    }
}

final class CursorScreenshotCovers: @unchecked Sendable {
    private let lock = NSLock()
    private var kept: [(style: CursorScreenshotRedactionStyle, strength: CGFloat, unit: CGFloat, cover: (image: CGImage, rect: CGRect))] = []
    private static let keptMost = 3

    func cover(_ style: CursorScreenshotRedactionStyle, _ strength: CGFloat, unit: CGFloat, making make: () -> (image: CGImage, rect: CGRect)?) -> (image: CGImage, rect: CGRect)? {
        lock.lock()
        defer { lock.unlock() }
        if let found = kept.first(where: { $0.style == style && $0.strength == strength && $0.unit == unit }) { return found.cover }
        guard let made = make() else { return nil }
        kept.append((style, strength, unit, made))
        if kept.count > Self.keptMost { kept.removeFirst() }
        return made
    }
}

struct CursorScreenshotPicture: Sendable {
    let image: CGImage
    let blocks: CGImage
    let scale: CGFloat
    let density: CGFloat
    let autoFill: CursorScreenshotColor?
    let hasTransparency: Bool
    private let covers = CursorScreenshotCovers()

    var size: CGSize { CGSize(width: image.width, height: image.height) }
    var space: CGColorSpace { Self.space(of: image) }
    var block: Int { Int(CursorScreenshotEditorLook.blockPoints * scale) }
    var firstFill: CursorScreenshotCropFill { hasTransparency ? .transparent : autoFill == nil ? .white : .auto }

    init?(_ image: CGImage, scale: CGFloat = 1, density: CGFloat? = nil) {
        let block = Int(CursorScreenshotEditorLook.blockPoints * max(scale, 1))
        guard let blocks = Self.grid(of: image, block: block) else { return nil }
        self.image = image
        self.blocks = blocks
        self.scale = max(scale, 1)
        self.density = density ?? self.scale
        let colors = Self.colors(in: blocks)
        autoFill = colors.common
        hasTransparency = colors.seesThrough
    }

    private static func colors(in grid: CGImage) -> (common: CursorScreenshotColor?, seesThrough: Bool) {
        guard let context = context(width: grid.width, height: grid.height, space: sRGB), let bytes = context.data else { return (nil, false) }
        context.draw(grid, in: CGRect(x: 0, y: 0, width: grid.width, height: grid.height))
        let row = context.bytesPerRow
        let pixels = bytes.assumingMemoryBound(to: UInt8.self)
        var counts: [Int: (count: Int, red: Int, green: Int, blue: Int)] = [:]
        var seesThrough = false
        for y in 0..<grid.height {
            for x in 0..<grid.width {
                let at = pixels + y * row + x * 4
                guard at[3] == 255 else {
                    seesThrough = true
                    continue
                }
                let (red, green, blue) = (Int(at[0]), Int(at[1]), Int(at[2]))
                let key = (red >> 4) << 8 | (green >> 4) << 4 | blue >> 4
                var bucket = counts[key] ?? (0, 0, 0, 0)
                bucket.count += 1
                bucket.red += red
                bucket.green += green
                bucket.blue += blue
                counts[key] = bucket
            }
        }
        let ranked = counts.sorted { $0.value.count != $1.value.count ? $0.value.count > $1.value.count : $0.key < $1.key }.map(\.value)
        guard let pick = ranked.count > 1 ? ranked[1] : ranked.first else { return (nil, seesThrough) }
        let share = { (part: Int) in CGFloat(part) / CGFloat(pick.count) / 255 }
        return (CursorScreenshotColor(red: share(pick.red), green: share(pick.green), blue: share(pick.blue)), seesThrough)
    }

    private static func grid(of image: CGImage, block: Int) -> CGImage? {
        let columns = (image.width + block - 1) / block
        let rows = (image.height + block - 1) / block
        guard let context = context(width: columns, height: rows, space: space(of: image)) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: columns, height: rows))
        return context.makeImage()
    }

    func cover(_ shared: CursorScreenshotShared, shrunk: CGFloat = 1) -> (image: CGImage, rect: CGRect)? {
        let unit = shrunk < 1 ? scale * pow(2, (log2(1 / shrunk) * 8).rounded(.up) / 8) : scale
        return covers.cover(shared.redaction, shared.strength, unit: unit) {
            let pushed = shared.strength + max(shared.strength - 20, 0)
            let base = (min(pushed, 40) / 2).rounded(.down) * 2
            switch shared.redaction {
            case .pixelate:
                let side = max(Int((shared.strength * unit).rounded()), 1)
                let grid = side == block ? blocks : Self.grid(of: image, block: side)
                return grid.map { ($0, CGRect(x: 0, y: 0, width: $0.width * side, height: $0.height * side)) }
            case .secureBlur:
                let side = max(Int((base + 4) / 1.5 * unit), 1)
                guard let grid = Self.grid(of: image, block: side) else { return nil }
                let rise = CGFloat(image.height - grid.height * side)
                let wide = CIImage(cgImage: grid).samplingNearest().transformed(by: CGAffineTransform(scaleX: CGFloat(side), y: CGFloat(side)).concatenating(CGAffineTransform(translationX: 0, y: rise)))
                return blurred(wide, radius: (base / 1.5 + 3) * unit)
            case .blur:
                return blurred(CIImage(cgImage: image), radius: (base / 2 + 2) * unit)
            case .blackOut:
                return nil
            }
        }
    }

    private func blurred(_ input: CIImage, radius: CGFloat) -> (image: CGImage, rect: CGRect)? {
        let whole = CGRect(origin: .zero, size: size)
        let output = input.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: min(radius, max(size.width, size.height))]).cropped(to: whole)
        return CIContext(options: [.cacheIntermediates: false]).createCGImage(output, from: whole, format: .RGBA8, colorSpace: space).map { ($0, whole) }
    }

    static var sRGB: CGColorSpace { CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB() }

    static func context(width: Int, height: Int, space: CGColorSpace) -> CGContext? {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    private static func space(of image: CGImage) -> CGColorSpace {
        if let space = image.colorSpace, space.model == .rgb, space.supportsOutput { return space }
        return sRGB
    }
}

extension CursorScreenshotPicture: Equatable {
    static func == (one: CursorScreenshotPicture, two: CursorScreenshotPicture) -> Bool {
        one.image === two.image
    }
}

enum CursorScreenshotImageEdge: CaseIterable, Sendable {
    case top, bottom, left, right

    static func near(_ point: CGPoint, in size: CGSize) -> CursorScreenshotImageEdge? {
        let distances: [(edge: CursorScreenshotImageEdge, away: CGFloat)] = [(.top, point.y), (.bottom, size.height - point.y), (.left, point.x), (.right, size.width - point.x)]
        guard let nearest = distances.min(by: { $0.away < $1.away }), nearest.away <= CursorScreenshotEditorLook.dropBandPoints else { return nil }
        return nearest.edge
    }

    static func centred(_ size: CGSize, in area: CGRect) -> CGRect {
        CGRect(x: (area.midX - size.width / 2).rounded(), y: (area.midY - size.height / 2).rounded(), width: size.width, height: size.height)
    }

    func landing(of size: CGSize, beside crop: CGRect) -> CGRect {
        let centredAcross = (crop.midX - size.width / 2).rounded()
        let centredDown = (crop.midY - size.height / 2).rounded()
        switch self {
        case .top: return CGRect(x: centredAcross, y: crop.minY - size.height, width: size.width, height: size.height)
        case .bottom: return CGRect(x: centredAcross, y: crop.maxY, width: size.width, height: size.height)
        case .left: return CGRect(x: crop.minX - size.width, y: centredDown, width: size.width, height: size.height)
        case .right: return CGRect(x: crop.maxX, y: centredDown, width: size.width, height: size.height)
        }
    }
}

enum CursorScreenshotImageSource {
    static let fileTypes: [UTType] = [.jpeg, .png, .heic, .heif, .webP]
    private static let dataTypes = (fileTypes + [.tiff]).map { NSPasteboard.PasteboardType($0.identifier) }
    private static var fileOptions: [NSPasteboard.ReadingOptionKey: Any] {
        [.urlReadingFileURLsOnly: true, .urlReadingContentsConformToTypes: fileTypes.map(\.identifier)]
    }

    static func holdsFile(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.canReadObject(forClasses: [NSURL.self], options: fileOptions)
    }

    static func holdsImage(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.availableType(from: [.fileURL]) != nil ? holdsFile(pasteboard) : pasteboard.availableType(from: dataTypes) != nil
    }

    static func offersImage(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.availableType(from: [.fileURL] + dataTypes) != nil
    }

    static func files(on pasteboard: NSPasteboard) -> [URL] {
        pasteboard.readObjects(forClasses: [NSURL.self], options: fileOptions) as? [URL] ?? []
    }

    static func data(on pasteboard: NSPasteboard) -> Data? {
        pasteboard.availableType(from: dataTypes).flatMap { pasteboard.data(forType: $0) }
    }

    static let wallpaperTypes = fileTypes + [.tiff]

    static func holdsWallpaper(_ pasteboard: NSPasteboard) -> Bool {
        !wallpapers(on: pasteboard).isEmpty
    }

    static func wallpapers(on pasteboard: NSPasteboard) -> [URL] {
        pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true, .urlReadingContentsConformToTypes: wallpaperTypes.map(\.identifier)]) as? [URL] ?? []
    }

    static func image(from source: CGImageSource?, side: Int) -> CGImage? {
        guard let source, let found = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let wide = found[kCGImagePropertyPixelWidth] as? Int, let high = found[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                                               kCGImageSourceShouldCacheImmediately: true,
                                                               kCGImageSourceThumbnailMaxPixelSize: min(max(wide, high), side)] as CFDictionary)
    }

    static func picture(from source: CGImageSource?, scale: CGFloat) -> CursorScreenshotPicture? {
        image(from: source, side: CursorScreenshotEditorLook.largestImageSide).flatMap { CursorScreenshotPicture($0, scale: taggedScale(of: source) ?? scale) }
    }

    private static func taggedScale(of source: CGImageSource?) -> CGFloat? {
        guard let source, let found = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let wide = (found[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue, let high = (found[kCGImagePropertyDPIHeight] as? NSNumber)?.doubleValue,
              wide.isFinite, high.isFinite, wide > 0, high > 0 else { return nil }
        return CGFloat(max(wide, high) / 72)
    }
}

enum CursorScreenshotCropHandle: CaseIterable, Sendable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left, whole

    var movesLeft: Bool { self == .topLeft || self == .left || self == .bottomLeft }
    var movesRight: Bool { self == .topRight || self == .right || self == .bottomRight }
    var movesTop: Bool { self == .topLeft || self == .top || self == .topRight }
    var movesBottom: Bool { self == .bottomLeft || self == .bottom || self == .bottomRight }
    private var isCorner: Bool { (movesLeft || movesRight) && (movesTop || movesBottom) }

    static func grips(of rect: CGRect, unit: CGFloat) -> [(handle: CursorScreenshotCropHandle, area: CGRect)] {
        let look = CursorScreenshotEditorLook.self
        let corner = look.cropCornerGrip * unit
        let across = look.cropEdgeGripAcross * unit
        let along = look.cropEdgeGripAlong * unit
        let strip = look.cropStripAcross * unit
        let trim = look.cropStripTrim * unit
        let around = { (x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) in CGRect(x: x - width / 2, y: y - height / 2, width: width, height: height) }
        var grips: [(handle: CursorScreenshotCropHandle, area: CGRect)] = [
            (.topLeft, around(rect.minX, rect.minY, corner, corner)), (.topRight, around(rect.maxX, rect.minY, corner, corner)),
            (.bottomLeft, around(rect.minX, rect.maxY, corner, corner)), (.bottomRight, around(rect.maxX, rect.maxY, corner, corner)),
            (.top, around(rect.midX, rect.minY, along, across)), (.bottom, around(rect.midX, rect.maxY, along, across)),
            (.left, around(rect.minX, rect.midY, across, along)), (.right, around(rect.maxX, rect.midY, across, along))
        ]
        if rect.width > trim {
            grips.append((.top, around(rect.midX, rect.minY, rect.width - trim, strip)))
            grips.append((.bottom, around(rect.midX, rect.maxY, rect.width - trim, strip)))
        }
        if rect.height > trim {
            grips.append((.left, around(rect.minX, rect.midY, strip, rect.height - trim)))
            grips.append((.right, around(rect.maxX, rect.midY, strip, rect.height - trim)))
        }
        return grips
    }

    static func hit(_ point: CGPoint, on rect: CGRect, unit: CGFloat) -> CursorScreenshotCropHandle? {
        if let grip = grips(of: rect, unit: unit).first(where: { $0.area.contains(point) }) { return grip.handle }
        return rect.contains(point) ? .whole : nil
    }

    func resized(_ rect: CGRect, to target: CGPoint, ratio: CGFloat?, fromCentre: Bool, smallest: CGFloat, within reach: CGRect = .infinite) -> CGRect {
        var (minX, minY, maxX, maxY) = (rect.minX, rect.minY, rect.maxX, rect.maxY)
        if fromCentre {
            let wide = max(abs(target.x - rect.midX), smallest / 2)
            let high = max(abs(target.y - rect.midY), smallest / 2)
            if movesLeft || movesRight { (minX, maxX) = (rect.midX - wide, rect.midX + wide) }
            if movesTop || movesBottom { (minY, maxY) = (rect.midY - high, rect.midY + high) }
        } else {
            if movesLeft { minX = min(target.x, maxX - smallest) }
            if movesRight { maxX = max(target.x, minX + smallest) }
            if movesTop { minY = min(target.y, maxY - smallest) }
            if movesBottom { maxY = max(target.y, minY + smallest) }
        }
        guard let ratio, ratio > 0 else { return CGRect(x: minX.rounded(), y: minY.rounded(), width: (maxX - minX).rounded(), height: (maxY - minY).rounded()) }
        var wide = maxX - minX
        var high = maxY - minY
        if isCorner {
            if wide / ratio >= high { high = wide / ratio } else { wide = high * ratio }
        } else if movesLeft || movesRight {
            high = wide / ratio
        } else {
            wide = high * ratio
        }
        let leastHigh = max(smallest, smallest / ratio)
        if high < leastHigh {
            high = leastHigh
            wide = high * ratio
        }
        let roomAcross = fromCentre || (!movesLeft && !movesRight) ? 2 * min(rect.midX - reach.minX, reach.maxX - rect.midX) : movesLeft ? maxX - reach.minX : reach.maxX - minX
        let roomDown = fromCentre || (!movesTop && !movesBottom) ? 2 * min(rect.midY - reach.minY, reach.maxY - rect.midY) : movesTop ? maxY - reach.minY : reach.maxY - minY
        let share = min(roomAcross / wide, roomDown / high)
        if share < 1 {
            wide = (wide * share + 0.001).rounded(.down)
            high = (high * share + 0.001).rounded(.down)
        }
        let x: CGFloat
        let y: CGFloat
        if fromCentre || (!movesLeft && !movesRight) { x = rect.midX - wide / 2 } else { x = movesLeft ? maxX - wide : minX }
        if fromCentre || (!movesTop && !movesBottom) { y = rect.midY - high / 2 } else { y = movesTop ? maxY - high : minY }
        return CGRect(x: x.rounded(), y: y.rounded(), width: wide.rounded(), height: high.rounded())
    }
}

enum CursorScreenshotCropSnap {
    static func line(in image: CGImage, near edge: CGFloat, along: CGFloat, vertical: Bool, reach: CGFloat, length: CGFloat) -> CGFloat? {
        let (lengthAcross, lengthAlong) = vertical ? (image.width, image.height) : (image.height, image.width)
        let low = max(Int((edge - reach).rounded(.down)), 0)
        let high = min(Int((edge + reach).rounded(.up)), lengthAcross)
        let first = max(Int((along - length / 2).rounded(.down)), 0)
        let last = min(Int((along + length / 2).rounded(.up)), lengthAlong)
        guard high - low >= 2, last > first else { return nil }
        let (wide, tall) = vertical ? (high - low, last - first) : (last - first, high - low)
        let strip = vertical ? CGRect(x: low, y: first, width: wide, height: tall) : CGRect(x: first, y: low, width: wide, height: tall)
        guard let piece = image.cropping(to: strip),
              let context = CursorScreenshotPicture.context(width: wide, height: tall, space: CursorScreenshotPicture.sRGB), let bytes = context.data else { return nil }
        context.draw(piece, in: CGRect(x: 0, y: 0, width: wide, height: tall))
        let pixels = bytes.assumingMemoryBound(to: UInt8.self)
        let row = context.bytesPerRow
        let steps = { (line: Int) -> Bool in
            for spot in 0..<(last - first) {
                let (after, before) = vertical ? (pixels + spot * row + (line - low) * 4, pixels + spot * row + (line - low - 1) * 4)
                                               : (pixels + (line - low) * row + spot * 4, pixels + (line - low - 1) * row + spot * 4)
                for part in 0..<3 where abs(Int(after[part]) - Int(before[part])) > CursorScreenshotEditorLook.cropLineStep { return true }
            }
            return false
        }
        let middle = Int(edge.rounded())
        for distance in 0...(high - low) {
            for line in [middle + distance, middle - distance] where line > low && line < high && steps(line) { return CGFloat(line) }
        }
        return nil
    }
}

enum CursorScreenshotCropTurn: Sendable {
    case rotate, flip
}

enum CursorScreenshotCropRatioItem: Sendable {
    case custom, freeform, original, square, fiveFour, sevenFive, fourThree, threeTwo, sixteenNine

    static let named: [CursorScreenshotCropRatioItem] = [.square, .fiveFour, .sevenFive, .fourThree, .threeTwo, .sixteenNine]

    func numbers(for size: CGSize) -> (width: Int, height: Int)? {
        switch self {
        case .custom, .freeform: return nil
        case .original: return CursorScreenshotCropRatio.reduced(Int(size.width), Int(size.height))
        case .square: return (1, 1)
        case .fiveFour: return (5, 4)
        case .sevenFive: return (7, 5)
        case .fourThree: return (4, 3)
        case .threeTwo: return (3, 2)
        case .sixteenNine: return (16, 9)
        }
    }
}

struct CursorScreenshotCropRatio: Equatable, Sendable {
    var width: Int?
    var height: Int?

    static func reduced(_ width: Int, _ height: Int) -> (width: Int, height: Int) {
        var (large, small) = (max(width, 1), max(height, 1))
        while small > 0 { (large, small) = (small, large % small) }
        return (max(width, 1) / large, max(height, 1) / large)
    }

    var locked: (width: Int, height: Int)? {
        guard let width, let height, width > 0, height > 0 else { return nil }
        return (width, height)
    }

    func item(for size: CGSize) -> CursorScreenshotCropRatioItem {
        guard let locked else { return .freeform }
        let short = Self.reduced(locked.width, locked.height)
        let same = { (item: CursorScreenshotCropRatioItem) in item.numbers(for: size).map { $0 == short } ?? false }
        return CursorScreenshotCropRatioItem.named.first(where: same) ?? (same(.original) ? .original : .custom)
    }

    static func box(_ width: Int, _ height: Int, in size: CGSize) -> CGRect {
        let wide = max(min(size.width, size.height * CGFloat(width) / CGFloat(height)).rounded(.down), 1)
        let high = max((wide * CGFloat(height) / CGFloat(width)).rounded(.down), 1)
        return CGRect(x: ((size.width - wide) / 2).rounded(.down), y: ((size.height - high) / 2).rounded(.down), width: wide, height: high)
    }
}

struct CursorScreenshotCropResize: Equatable, Sendable {
    let base: CGSize
    private(set) var pixels: CGSize
    private(set) var locked = true
    private(set) var inPercent = false
    var flatten = false

    init(base: CGSize) {
        self.base = base
        pixels = base
    }

    var isFlattenForced: Bool { !locked }
    var flattens: Bool { flatten || !locked }
    var shownWidth: Int { shown(pixels.width, of: base.width) }
    var shownHeight: Int { shown(pixels.height, of: base.height) }
    var isUnchanged: Bool { pixels == base && !flattens }

    private func shown(_ value: CGFloat, of whole: CGFloat) -> Int {
        Int((inPercent ? value / max(whole, 1) * 100 : value).rounded())
    }

    private func toPixels(_ typed: Int, of whole: CGFloat) -> CGFloat {
        let limit = CGFloat(CursorScreenshotEditorLook.largestImageSide)
        return min(max((inPercent ? CGFloat(typed) / 100 * whole : CGFloat(typed)).rounded(), 1), limit)
    }

    mutating func setWidth(_ typed: Int?) {
        pixels.width = typed.map { toPixels($0, of: base.width) } ?? base.width
        if locked { pixels.height = max((pixels.width * base.height / max(base.width, 1)).rounded(), 1) }
        keepLockedShapeInLimit()
    }

    mutating func setHeight(_ typed: Int?) {
        pixels.height = typed.map { toPixels($0, of: base.height) } ?? base.height
        if locked { pixels.width = max((pixels.height * base.width / max(base.height, 1)).rounded(), 1) }
        keepLockedShapeInLimit()
    }

    private mutating func keepLockedShapeInLimit() {
        let over = max(pixels.width, pixels.height) / CGFloat(CursorScreenshotEditorLook.largestImageSide)
        guard locked, over > 1 else { return }
        pixels = CGSize(width: max((pixels.width / over).rounded(), 1), height: max((pixels.height / over).rounded(), 1))
    }

    mutating func setLocked(_ locked: Bool) {
        self.locked = locked
        if !locked { flatten = true }
    }

    mutating func setPercent(_ percent: Bool) {
        inPercent = percent
    }
}

enum CursorScreenshotRender {
    static func draw(_ picture: CGImage, in rect: CGRect, on context: CGContext) {
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(picture, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }

    static func render(_ picture: CursorScreenshotPicture, marks: [CursorScreenshotMark], shared: CursorScreenshotShared = CursorScreenshotShared(), drawsImage: Bool = true, on context: CGContext) {
        let whole = CGRect(origin: .zero, size: picture.size)
        if drawsImage { draw(picture.image, in: whole, on: context) }
        let images = marks.filter { $0.tool == .image }
        for mark in images {
            if let image = mark.image { draw(image.image, in: mark.rect, on: context) }
        }
        let holes = marks.filter { $0.tool == .spotlight }
        if !holes.isEmpty { drawDim(holes, over: [shared.dimArea ?? images.reduce(whole) { $0.union($1.rect) }], picture: picture, shared: shared, on: context) }
        for mark in marks {
            switch mark.tool {
            case .arrow: drawArrow(mark, stroke: mark.size * picture.scale, on: context)
            case .box, .oval, .line, .pen: drawStroke(mark, color: mark.color, picture: picture, on: context)
            case .filledBox: drawFilled(mark, picture: picture, on: context)
            case .pixelate:
                let covered = drawCover(mark, picture: picture, images: images, shared: shared, on: context)
                if !holes.isEmpty && !covered.isEmpty { drawDim(holes, over: covered, picture: picture, shared: shared, on: context) }
            case .text: drawText(mark, picture: picture, on: context)
            case .number: drawNumber(mark, picture: picture, on: context)
            case .highlight:
                var color = mark.color
                color.alpha *= CursorScreenshotEditorLook.highlightAlpha
                context.saveGState()
                context.setBlendMode(.multiply)
                if mark.isTextLine {
                    drawLineBox(mark, color: color, picture: picture, on: context)
                } else {
                    drawStroke(mark, color: color, picture: picture, on: context)
                }
                context.restoreGState()
            case .select, .spotlight, .image: break
            }
        }
    }

    static func scene(_ picture: CursorScreenshotPicture, marks: [CursorScreenshotMark], shared: CursorScreenshotShared, crop: CGRect, size: CGSize, base: CGImage? = nil, fill: CursorScreenshotColor? = nil) -> CGImage? {
        guard let context = CursorScreenshotPicture.context(width: Int(size.width), height: Int(size.height), space: picture.space) else { return nil }
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: size.width / crop.width, y: -size.height / crop.height)
        context.translateBy(x: -crop.minX, y: -crop.minY)
        context.interpolationQuality = .high
        if let fill {
            context.setFillColor(fill.cgColor)
            context.fill(crop)
        }
        if let base { draw(base, in: crop, on: context) }
        render(picture, marks: marks, shared: shared, drawsImage: base == nil, on: context)
        return context.makeImage()
    }

    static func exported(_ picture: CursorScreenshotPicture, marks: [CursorScreenshotMark], shared: CursorScreenshotShared = CursorScreenshotShared(), crop: CGRect? = nil) -> CGImage? {
        let area = crop ?? CGRect(origin: .zero, size: picture.size)
        return scene(picture, marks: marks, shared: shared, crop: area, size: area.size)
    }

    static func exported(_ picture: CursorScreenshotPicture, edit: CursorScreenshotEdit) -> CGImage? {
        let fill = edit.fill.resolved(for: picture)
        var spread = edit
        spread.spreadDim()
        let inner = scene(picture, marks: edit.marks, shared: spread.shared, crop: edit.crop, size: edit.outputSize, fill: fill)
        return edit.hasBackground ? inner.flatMap { composed($0, picture: picture, edit: edit, factor: edit.outputScale) } : inner
    }

    static func exported(_ image: CGImage, style: CursorScreenshotBackgroundStyle, scale: CGFloat, source: CursorScreenshotBackdropSource) -> CGImage? {
        guard let picture = CursorScreenshotPicture(image, scale: scale) else { return nil }
        var edit = CursorScreenshotEdit(crop: CGRect(origin: .zero, size: picture.size))
        edit.fill = picture.firstFill
        edit.background = style
        edit.backdrop = source.image(for: style.fill, picture: image)
        if edit.backdrop == nil, !style.fill.drawsWithoutImage { edit.background.fill = .none }
        if style.autoBalance { edit.balance = CursorScreenshotBalance.measured(image, crop: edit.crop, scale: picture.scale) }
        return exported(picture, edit: edit)
    }

    static func paint(_ fill: CursorScreenshotBackdropFill, image: CGImage?, in rect: CGRect, on context: CGContext) {
        context.saveGState()
        context.clip(to: rect)
        switch fill {
        case .none:
            break
        case .color(let hex, let alpha):
            context.setFillColor((CursorScreenshotColor(hex: hex, alpha: alpha) ?? CursorScreenshotColor(red: 0, green: 0, blue: 0, alpha: 0)).cgColor)
            context.fill(rect)
        case .gradient(let index):
            let gradient = CursorScreenshotBackdrops.gradients[index]
            let colors = gradient.stops.compactMap { CursorScreenshotColor(hex: $0)?.cgColor } as CFArray
            let line = CursorScreenshotBackdrops.gradientLine(angle: gradient.angle, in: rect)
            if let made = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 0.5, 1]) {
                context.drawLinearGradient(made, start: line.start, end: line.end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            }
        case .wallpaper, .desktop, .blurredDesktop, .blurredPicture, .blurredPictureDark:
            guard let image else { break }
            let cover = max(rect.width / CGFloat(image.width), rect.height / CGFloat(image.height))
            let wide = CGFloat(image.width) * cover
            let high = CGFloat(image.height) * cover
            context.interpolationQuality = .high
            draw(image, in: CGRect(x: rect.midX - wide / 2, y: rect.midY - high / 2, width: wide, height: high), on: context)
        }
        context.restoreGState()
    }

    static func composed(_ content: CGImage, picture: CursorScreenshotPicture, edit: CursorScreenshotEdit, factor: CGFloat) -> CGImage? {
        let layout = edit.layout(scale: picture.scale)
        let size = CursorScreenshotEdit.output(of: layout.size, scale: factor)
        guard let context = CursorScreenshotPicture.context(width: Int(size.width), height: Int(size.height), space: picture.space) else { return nil }
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: size.width / layout.size.width, y: -size.height / layout.size.height)
        let style = edit.background
        let whole = CGRect(origin: .zero, size: layout.size)
        paint(style.fill, image: edit.backdrop, in: whole, on: context)
        let holes = style.fill.isOpaque ? edit.marks.filter { $0.tool == .spotlight } : []
        let shift = CGPoint(x: layout.content.minX - edit.crop.minX, y: layout.content.minY - edit.crop.minY)
        let dim = { (areas: [CGRect]) in
            guard !holes.isEmpty else { return }
            context.saveGState()
            context.translateBy(x: shift.x, y: shift.y)
            drawDim(holes, over: areas.map { $0.offsetBy(dx: -shift.x, dy: -shift.y) }, picture: picture, shared: edit.shared, on: context)
            context.restoreGState()
        }
        dim([whole])
        let unit = picture.scale * factor
        context.saveGState()
        if style.shadow > 0 {
            context.setShadow(offset: CGSize(width: 0, height: -style.shadow * CursorScreenshotBackgroundLook.shadowDrop * unit), blur: style.shadow * CursorScreenshotBackgroundLook.shadowBlur * unit,
                              color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: style.shadow * CursorScreenshotBackgroundLook.shadowAlpha))
        }
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.addPath(CGPath(roundedRect: layout.frame, cornerWidth: layout.radius, cornerHeight: layout.radius, transform: nil))
        context.clip()
        if let fill = edit.fill.resolved(for: picture) {
            context.setFillColor(fill.cgColor)
            context.fill(layout.frame)
        }
        draw(content, in: layout.content, on: context)
        let (frame, inner) = (layout.frame, layout.content)
        dim([CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: inner.minY - frame.minY), CGRect(x: frame.minX, y: inner.maxY, width: frame.width, height: frame.maxY - inner.maxY),
             CGRect(x: frame.minX, y: inner.minY, width: inner.minX - frame.minX, height: inner.height), CGRect(x: inner.maxX, y: inner.minY, width: frame.maxX - inner.maxX, height: inner.height)].filter { !$0.isEmpty })
        context.endTransparencyLayer()
        context.restoreGState()
        return context.makeImage()
    }

    static func turned(_ image: CGImage, _ turn: CursorScreenshotCropTurn, space: CGColorSpace) -> CGImage? {
        let (width, height) = (CGFloat(image.width), CGFloat(image.height))
        let size = turn == .rotate ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
        guard let context = CursorScreenshotPicture.context(width: Int(size.width), height: Int(size.height), space: space) else { return nil }
        switch turn {
        case .rotate:
            context.translateBy(x: height, y: 0)
            context.rotate(by: .pi / 2)
        case .flip:
            context.translateBy(x: width, y: 0)
            context.scaleBy(x: -1, y: 1)
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    static func outline(_ mark: CursorScreenshotMark, scale: CGFloat) -> CGPath {
        let path = CGMutablePath()
        switch mark.tool {
        case .oval: path.addEllipse(in: mark.rect)
        case .line: path.addLines(between: [mark.start, mark.end])
        case .arrow:
            path.move(to: mark.start)
            if mark.arrowStyle.isCurved {
                path.addQuadCurve(to: mark.end, control: mark.curve)
            } else {
                path.addLine(to: mark.end)
            }
        case .pen: return penPath(mark.path + [mark.end])
        case .highlight: path.addLines(between: mark.path)
        case .spotlight: return spotlightPath(mark, scale: scale)
        case .number: path.addEllipse(in: bounds(of: mark, scale: scale))
        case .text: path.addRect(bounds(of: mark, scale: scale))
        default: path.addRect(mark.rect)
        }
        return path
    }

    static func penPath(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        var kept: [CGPoint] = []
        for point in points where kept.last != point { kept.append(point) }
        guard let first = kept.first else { return path }
        path.move(to: first)
        guard kept.count >= CursorScreenshotEditorLook.penSmoothFrom else {
            path.addLine(to: first)
            for point in kept.dropFirst() { path.addLine(to: point) }
            return path
        }
        var run = [first]
        for point in kept.dropFirst() {
            run.append(point)
            guard run.count == 5 else { continue }
            let joint = CGPoint(x: (run[2].x + run[4].x) / 2, y: (run[2].y + run[4].y) / 2)
            path.addCurve(to: joint, control1: run[1], control2: run[2])
            run = [joint, run[4]]
        }
        for point in run.dropFirst() { path.addLine(to: point) }
        return path
    }

    static func spotlightPath(_ mark: CursorScreenshotMark, scale: CGFloat) -> CGPath {
        let rect = mark.rect
        switch mark.shape {
        case .rectangle: return CGPath(rect: rect, transform: nil)
        case .oval: return CGPath(ellipseIn: rect, transform: nil)
        case .rounded:
            let look = CursorScreenshotEditorLook.self
            let radius = min(look.spotlightCornerPoints * scale, min(rect.width, rect.height) / 2 / look.spotlightCornerFactor)
            return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        }
    }

    static func bounds(of mark: CursorScreenshotMark, scale: CGFloat) -> CGRect {
        switch mark.tool {
        case .text:
            let layout = textLayout(mark, scale: scale)
            return layout.lines.reduce(layout.frame) { $1.box.map($0.union) ?? $0 }
        case .number:
            let diameter = mark.size * scale
            return CGRect(x: mark.start.x - diameter / 2, y: mark.start.y - diameter / 2, width: diameter, height: diameter)
        case .filledBox, .pixelate, .spotlight, .image:
            return mark.rect
        default:
            let side = mark.size * scale / 2
            return mark.rect.insetBy(dx: -side, dy: -side)
        }
    }

    static func isHitAcrossBox(_ tool: CursorScreenshotTool) -> Bool {
        switch tool {
        case .filledBox, .pixelate, .spotlight, .text, .number, .image: return true
        default: return false
        }
    }

    static func isHit(_ mark: CursorScreenshotMark, at point: CGPoint, reach: CGFloat, scale: CGFloat) -> Bool {
        if isHitAcrossBox(mark.tool) {
            return bounds(of: mark, scale: scale).insetBy(dx: -reach, dy: -reach).contains(point)
        }
        return outline(mark, scale: scale).copy(strokingWithWidth: mark.size * scale + reach * 2, lineCap: .round, lineJoin: .round, miterLimit: 10).contains(point)
    }

    static func handles(of mark: CursorScreenshotMark, scale: CGFloat) -> [(handle: CursorScreenshotMarkHandle, point: CGPoint)] {
        switch mark.tool {
        case .box, .filledBox, .oval, .pixelate, .spotlight, .image:
            let rect = mark.rect
            return [(.topLeft, CGPoint(x: rect.minX, y: rect.minY)), (.topRight, CGPoint(x: rect.maxX, y: rect.minY)),
                    (.bottomLeft, CGPoint(x: rect.minX, y: rect.maxY)), (.bottomRight, CGPoint(x: rect.maxX, y: rect.maxY))]
        case .line:
            return [(.start, mark.start), (.end, mark.end)]
        case .arrow:
            return [(.start, mark.start), (.end, mark.end)] + (mark.arrowStyle.isCurved ? [(.control, mark.curve)] : [])
        case .text:
            let frame = textLayout(mark, scale: scale).frame
            return [(.textLeft, CGPoint(x: frame.minX, y: frame.midY)), (.textRight, CGPoint(x: frame.maxX, y: frame.midY)), (.textWidth, CGPoint(x: frame.maxX, y: frame.maxY))]
        case .pen, .highlight, .number, .select:
            return []
        }
    }

    static func placed(_ pixels: CGSize, in bounds: CGSize, backing: CGFloat) -> CGRect {
        guard pixels.width > 0, pixels.height > 0 else { return .zero }
        let scale = min(bounds.width / pixels.width, bounds.height / pixels.height, 1 / max(backing, 1))
        let width = pixels.width * scale
        let height = pixels.height * scale
        return CGRect(x: ((bounds.width - width) / 2).rounded(), y: ((bounds.height - height) / 2).rounded(), width: width, height: height)
    }

    static func dragFrame(_ pixels: CGSize, in bounds: CGSize, backing: CGFloat, around point: CGPoint) -> CGRect {
        let size = placed(pixels, in: bounds, backing: backing).size
        return CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height)
    }

    static func textFont(ofSize size: CGFloat, style: CursorScreenshotTextStyle = .standard) -> NSFont {
        style.font(ofSize: size)
    }

    static func isRightToLeft(_ text: String) -> Bool {
        guard let strong = text.unicodeScalars.first(where: { $0.properties.isAlphabetic }) else { return false }
        return (0x0590...0x08FF).contains(strong.value) || (0xFB1D...0xFDFF).contains(strong.value) || (0xFE70...0xFEFF).contains(strong.value)
    }

    private static func isCentredInItsBox(_ mark: CursorScreenshotMark) -> Bool {
        (mark.textStyle == .box || mark.textStyle == .roundedBox) && mark.text.count < CursorScreenshotEditorLook.textBoxCharacterLimit
    }

    static func fieldAlignment(_ mark: CursorScreenshotMark) -> NSTextAlignment {
        guard mark.wrap > 0 else { return .left }
        if isCentredInItsBox(mark) { return .center }
        return isRightToLeft(mark.text) ? .right : .left
    }

    static func textLayout(_ mark: CursorScreenshotMark, scale: CGFloat) -> (font: NSFont, lines: [(line: CTLine, baseline: CGPoint, box: CGRect?)], frame: CGRect) {
        let font = textFont(ofSize: mark.size * scale, style: mark.textStyle)
        let height = font.ascender - font.descender
        let setter = typesetter(mark, attributes: [.font: font, NSAttributedString.Key(kCTForegroundColorAttributeName as String): mark.color.cgColor])
        let length = (mark.text as NSString).length
        var made: [(line: CTLine, width: CGFloat)] = []
        var at = 0
        while at < length {
            let count = mark.wrap > 0 ? CTTypesetterSuggestLineBreak(setter, at, Double(mark.wrap)) : length - at
            guard count > 0 else { break }
            let line = CTTypesetterCreateLine(setter, CFRange(location: at, length: count))
            made.append((line, CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil) - CTLineGetTrailingWhitespaceWidth(line))))
            at += count
        }
        let width = mark.wrap > 0 ? mark.wrap : made.map(\.width).max() ?? 0
        let centred = isCentredInItsBox(mark)
        let rightToLeft = isRightToLeft(mark.text)
        let shape = mark.textStyle.boxShape(lineHeight: height, characters: mark.text.count)
        let lines = made.enumerated().map { index, item -> (line: CTLine, baseline: CGPoint, box: CGRect?) in
            let inset = centred ? (width - item.width) / 2 : (rightToLeft ? width - item.width : 0)
            let top = mark.start.y + CGFloat(index) * height
            let box = CGRect(x: mark.start.x + inset - shape.extraWidth / 2, y: top + height / 2 - shape.height / 2, width: item.width + shape.extraWidth, height: shape.height)
            return (item.line, CGPoint(x: mark.start.x + inset, y: top + font.ascender), mark.textStyle.hasBox ? box : nil)
        }
        return (font, lines, CGRect(x: mark.start.x, y: mark.start.y, width: width, height: height * CGFloat(max(made.count, 1))))
    }

    private static func typesetter(_ mark: CursorScreenshotMark, attributes: [NSAttributedString.Key: Any]) -> CTTypesetter {
        CTTypesetterCreateWithAttributedString(NSAttributedString(string: mark.text, attributes: attributes))
    }

    private static func line(_ text: String, font: NSFont, color: CGColor) -> CTLine {
        CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
            .font: font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color
        ]))
    }

    private static func draw(_ line: CTLine, baseline: CGPoint, on context: CGContext) {
        context.saveGState()
        context.translateBy(x: baseline.x, y: baseline.y)
        context.scaleBy(x: 1, y: -1)
        context.textMatrix = .identity
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()
    }

    private static func drawText(_ mark: CursorScreenshotMark, picture: CursorScreenshotPicture, on context: CGContext) {
        drawTextBacking(mark, picture: picture, on: context)
        for item in textLayout(mark, scale: picture.scale).lines { draw(item.line, baseline: item.baseline, on: context) }
    }

    static func drawTextBacking(_ mark: CursorScreenshotMark, picture: CursorScreenshotPicture, on context: CGContext) {
        let layout = textLayout(mark, scale: picture.scale)
        let shape = mark.textStyle.shapeColor(behind: mark.color)
        if mark.textStyle.hasBox {
            let radius = mark.textStyle.boxShape(lineHeight: layout.font.ascender - layout.font.descender, characters: mark.text.count).radius
            context.saveGState()
            context.setFillColor(shape.cgColor)
            for box in layout.lines.compactMap(\.box) {
                context.addPath(CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil))
                context.fillPath()
            }
            context.restoreGState()
        }
        guard mark.textStyle == .outlined else { return }
        let setter = typesetter(mark, attributes: [.font: layout.font,
                                                   NSAttributedString.Key(kCTStrokeWidthAttributeName as String): CursorScreenshotEditorLook.outlineShare * 100,
                                                   NSAttributedString.Key(kCTStrokeColorAttributeName as String): shape.cgColor])
        context.saveGState()
        context.setLineCap(.round)
        context.setLineJoin(.round)
        for item in layout.lines {
            let range = CTLineGetStringRange(item.line)
            draw(CTTypesetterCreateLine(setter, range), baseline: item.baseline, on: context)
        }
        context.restoreGState()
    }

    private static func drawNumber(_ mark: CursorScreenshotMark, picture: CursorScreenshotPicture, on context: CGContext) {
        let diameter = mark.size * picture.scale
        context.saveGState()
        context.setFillColor(mark.color.cgColor)
        context.fillEllipse(in: CGRect(x: mark.start.x - diameter / 2, y: mark.start.y - diameter / 2, width: diameter, height: diameter))
        context.restoreGState()
        let label = mark.numberStyle.label(mark.number)
        var size = diameter / 2
        var digit = line(label, font: NSFont.boldSystemFont(ofSize: size), color: CursorScreenshotEditorLook.digitColor)
        let room = diameter * 0.8
        let wide = CTLineGetBoundsWithOptions(digit, .useGlyphPathBounds).width
        if wide > room {
            size *= room / wide
            digit = line(label, font: NSFont.boldSystemFont(ofSize: size), color: CursorScreenshotEditorLook.digitColor)
        }
        let ink = CTLineGetBoundsWithOptions(digit, .useGlyphPathBounds)
        draw(digit, baseline: CGPoint(x: mark.start.x - ink.midX, y: mark.start.y + ink.midY), on: context)
    }

    private static func drawStroke(_ mark: CursorScreenshotMark, color: CursorScreenshotColor, picture: CursorScreenshotPicture, on context: CGContext) {
        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(mark.size * picture.scale)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.addPath(outline(mark, scale: picture.scale))
        context.strokePath()
        context.restoreGState()
    }

    private static func drawLineBox(_ mark: CursorScreenshotMark, color: CursorScreenshotColor, picture: CursorScreenshotPicture, on context: CGContext) {
        let high = mark.size * picture.scale
        let box = CGRect(x: min(mark.start.x, mark.end.x), y: mark.start.y - high / 2, width: abs(mark.end.x - mark.start.x), height: high)
        let corner = min(high * CursorScreenshotEditorLook.highlightLineCorner, box.width / 2)
        context.setFillColor(color.cgColor)
        context.addPath(CGPath(roundedRect: box, cornerWidth: corner, cornerHeight: corner, transform: nil))
        context.fillPath()
    }

    private static func drawFilled(_ mark: CursorScreenshotMark, picture: CursorScreenshotPicture, on context: CGContext) {
        let rect = mark.rect
        let radius = min(CursorScreenshotEditorLook.filledCornerPoints * picture.scale, min(rect.width, rect.height) / 2)
        context.saveGState()
        context.setFillColor(mark.color.cgColor)
        context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.fillPath()
        context.restoreGState()
    }

    private static func drawDim(_ holes: [CursorScreenshotMark], over areas: [CGRect], picture: CursorScreenshotPicture, shared: CursorScreenshotShared, on context: CGContext) {
        context.saveGState()
        context.clip(to: areas)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: shared.dim / 100))
        context.fill(areas)
        context.setBlendMode(.clear)
        for hole in holes {
            context.addPath(spotlightPath(hole, scale: picture.scale))
            context.fillPath()
        }
        context.endTransparencyLayer()
        context.restoreGState()
    }

    private static func drawArrow(_ mark: CursorScreenshotMark, stroke: CGFloat, on context: CGContext) {
        let (from, to) = mark.reversed ? (mark.end, mark.start) : (mark.start, mark.end)
        let length = hypot(to.x - from.x, to.y - from.y)
        guard length > 0 else { return }
        let along = CGPoint(x: (to.x - from.x) / length, y: (to.y - from.y) / length)
        let head = min(stroke * CursorScreenshotEditorLook.arrowHeadLength, length * 0.6)
        let side = head / CursorScreenshotEditorLook.arrowHeadLength * CursorScreenshotEditorLook.arrowHeadWidth / 2
        let base = CGPoint(x: to.x - along.x * head, y: to.y - along.y * head)
        context.saveGState()
        context.setStrokeColor(mark.color.cgColor)
        context.setFillColor(mark.color.cgColor)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        switch mark.arrowStyle {
        case .standard:
            context.setLineWidth(min(stroke, side))
            context.move(to: from)
            context.addLine(to: base)
            context.strokePath()
            context.move(to: to)
            context.addLine(to: CGPoint(x: base.x - along.y * side, y: base.y + along.x * side))
            context.addLine(to: CGPoint(x: base.x + along.y * side, y: base.y - along.x * side))
            context.closePath()
            context.fillPath()
        case .fancy:
            let neck = CGPoint(x: to.x - along.x * head * 0.72, y: to.y - along.y * head * 0.72)
            let waist = min(stroke, side) / 2
            let across = { (spot: CGPoint, by: CGFloat) in CGPoint(x: spot.x - along.y * by, y: spot.y + along.x * by) }
            context.addLines(between: [from, across(neck, waist), across(base, side), to, across(base, -side), across(neck, -waist)])
            context.closePath()
            context.fillPath()
        case .curved, .double:
            context.setLineWidth(stroke)
            context.addPath(outline(mark, scale: 1))
            let barb = { (tip: CGPoint, behind: CGPoint) in
                let away = hypot(tip.x - behind.x, tip.y - behind.y)
                guard away > 0 else { return }
                let back = CGPoint(x: (tip.x - behind.x) / away, y: (tip.y - behind.y) / away)
                let root = CGPoint(x: tip.x - back.x * head, y: tip.y - back.y * head)
                context.move(to: CGPoint(x: root.x - back.y * side, y: root.y + back.x * side))
                context.addLine(to: tip)
                context.addLine(to: CGPoint(x: root.x + back.y * side, y: root.y - back.x * side))
            }
            barb(to, mark.curve)
            if mark.arrowStyle == .double { barb(from, mark.curve) }
            context.strokePath()
        }
        context.restoreGState()
    }

    private static func drawCover(_ mark: CursorScreenshotMark, picture: CursorScreenshotPicture, images: [CursorScreenshotMark], shared: CursorScreenshotShared, on context: CGContext) -> [CGRect] {
        let box = mark.rect.integral
        let sources = [(picture, CGRect(origin: .zero, size: picture.size))] + images.compactMap { image in image.image.map { ($0, image.rect) } }
        var covered: [CGRect] = []
        for (source, placed) in sources {
            let area = box.intersection(placed)
            guard !area.isEmpty else { continue }
            context.saveGState()
            context.setShouldAntialias(false)
            context.interpolationQuality = .none
            context.setBlendMode(.copy)
            context.clip(to: area)
            let across = placed.width / source.size.width
            let down = placed.height / source.size.height
            if let cover = source.cover(shared, shrunk: min(across, down, 1)) {
                draw(cover.image, in: CGRect(x: placed.minX + cover.rect.minX * across, y: placed.minY + cover.rect.minY * down, width: cover.rect.width * across, height: cover.rect.height * down), on: context)
            } else {
                context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
                context.fill(area)
            }
            context.restoreGState()
            covered.append(area)
        }
        return covered
    }
}

enum CursorScreenshotEditorAction: Equatable {
    case undo, redo, close, cut, copy, paste, selectAll, apply, cancel
    case tool(CursorScreenshotTool), sizeUp, sizeDown, pickSize(Int), zoomIn, zoomOut, zoomFit, zoomActual, saveAs, copyPicture, pan
    case deleteMark, duplicateMark, copyMark, pasteMark, nudge(x: CGFloat, y: CGFloat)
    case openCrop, nudgeCrop(x: CGFloat, y: CGFloat, big: Bool, resizes: Bool)
    case takeImage, chooseImage, pasteImage, toggleBackground

    private static func cropAction(_ key: String?, held: NSEvent.ModifierFlags) -> CursorScreenshotEditorAction? {
        if key == " ", held.isEmpty { return .pan }
        guard held.subtracting([.shift, .command, .option]).isEmpty else { return nil }
        let look = CursorScreenshotEditorLook.self
        let big = held.contains(.shift)
        let step = big ? look.bigNudgePoints : look.nudgePoints
        let resizes = !held.isDisjoint(with: [.command, .option])
        switch key {
        case "\u{F700}": return .nudgeCrop(x: 0, y: -step, big: big, resizes: resizes)
        case "\u{F701}": return .nudgeCrop(x: 0, y: step, big: big, resizes: resizes)
        case "\u{F702}": return .nudgeCrop(x: -step, y: 0, big: big, resizes: resizes)
        case "\u{F703}": return .nudgeCrop(x: step, y: 0, big: big, resizes: resizes)
        default: return nil
        }
    }

    private static func markAction(_ key: String?, held: NSEvent.ModifierFlags, hasSelection: Bool, hasCopy: Bool) -> CursorScreenshotEditorAction? {
        let look = CursorScreenshotEditorLook.self
        switch (key, held) {
        case ("v", [.command]) where hasCopy: return .pasteMark
        case ("c", [.command]) where hasSelection: return .copyMark
        case ("d", [.command]) where hasSelection: return .duplicateMark
        case ("\u{7f}", []) where hasSelection, ("\u{F728}", []) where hasSelection: return .deleteMark
        default: break
        }
        guard hasSelection, held.subtracting(.shift).isEmpty else { return nil }
        let step = held.contains(.shift) ? look.bigNudgePoints : look.nudgePoints
        switch key {
        case "\u{F700}": return .nudge(x: 0, y: -step)
        case "\u{F701}": return .nudge(x: 0, y: step)
        case "\u{F702}": return .nudge(x: -step, y: 0)
        case "\u{F703}": return .nudge(x: step, y: 0)
        default: return nil
        }
    }

    static func forKey(letter: String?, typed: String? = nil, flags: NSEvent.ModifierFlags, editingText: Bool = false, cropping: Bool = false,
                       hasSelection: Bool = false, hasCopy: Bool = false, hasImage: Bool = false) -> CursorScreenshotEditorAction? {
        let key = letter?.lowercased()
        let held = flags.intersection([.command, .shift, .option, .control])
        switch (key, held) {
        case ("z", [.command]): return .undo
        case ("z", [.command, .shift]): return .redo
        case ("w", [.command]): return .close
        case ("x", [.command]) where editingText: return .cut
        case ("c", [.command]) where editingText: return .copy
        case ("v", [.command]) where editingText: return .paste
        case ("a", [.command]) where editingText: return .selectAll
        case ("\r", []), ("\u{3}", []): return .apply
        case ("\u{1b}", []): return .cancel
        default: break
        }
        guard !editingText else { return nil }
        switch (key, held) {
        case ("s", [.command]), ("s", [.command, .shift]): return .saveAs
        case ("c", [.command, .shift]): return .copyPicture
        case ("=", [.command]), ("=", [.command, .shift]), ("+", [.command]), ("+", [.command, .shift]): return .zoomIn
        case ("-", [.command]): return .zoomOut
        case ("1", [.command]): return .zoomFit
        case ("0", [.command]): return .zoomActual
        default: break
        }
        guard !cropping else { return cropAction(key, held: held) }
        switch (key, held) {
        case ("i", [.command]): return .chooseImage
        case ("i", [.command, .shift]): return .takeImage
        case ("v", [.command]) where hasImage: return .pasteImage
        default: break
        }
        if let action = markAction(key, held: held, hasSelection: hasSelection, hasCopy: hasCopy) { return action }
        guard held.subtracting(.shift).isEmpty else { return nil }
        switch typed ?? key {
        case "=", "+": return .sizeUp
        case "-": return .sizeDown
        case let digit? where digit.count == 1 && "123456789".contains(digit): return .pickSize(Int(digit) ?? 1)
        default: break
        }
        guard held.isEmpty else { return nil }
        if key == " " { return .pan }
        if key == "k" { return .openCrop }
        if key == "b" { return .toggleBackground }
        return CursorScreenshotTool.allCases.first { $0.letter == key }.map { .tool($0) }
    }
}

@MainActor
final class CursorScreenshotEditorModel: ObservableObject {
    @Published private(set) var picture: CursorScreenshotPicture
    @Published var tool: CursorScreenshotTool {
        didSet { toolChanged(from: oldValue) }
    }
    @Published private(set) var edit: CursorScreenshotEdit
    @Published private(set) var typing: CursorScreenshotMark?
    @Published private(set) var cropDraft: CGRect?
    @Published private(set) var cropFill: CursorScreenshotCropFill
    @Published private(set) var cropRatio = CursorScreenshotCropRatio()
    @Published private(set) var choices: CursorScreenshotEditorChoices
    @Published private(set) var zoomChoice: CGFloat?
    @Published private(set) var fitZoom: CGFloat = 1
    @Published private(set) var selection: Int?
    @Published private(set) var guides: (across: [CGFloat], down: [CGFloat]) = ([], [])
    @Published private(set) var library: CursorScreenshotBackgroundLibrary
    @Published private(set) var backdropThumbnails: [CursorScreenshotBackdropFill: CGImage] = [:]
    var libraryChanged: ((inout CursorScreenshotBackgroundLibrary) -> Void) -> Void = { _ in }
    var output: () -> CursorScreenshotOutput = { CursorScreenshotOutput() }
    var clipboard: () -> (mode: CursorScreenshotClipboardMode, folder: URL?, name: CursorScreenshotFileName) = {
        (.imageOnly, nil, CursorScreenshotFileName(stem: "", number: nil, retina: false))
    }
    private let backdropSource: CursorScreenshotBackdropSource
    private let textLineSource: @Sendable (CursorScreenshotPicture) async -> [CGRect]?
    private var textLines: [ObjectIdentifier: (image: CGImage, lines: [CGRect])] = [:]
    private var backdropImages: [CursorScreenshotBackdropFill: CGImage] = [:]
    private var backdropsStarted = false
    private var backdropsTask: Task<Void, Never>?
    private(set) var draft: CursorScreenshotMark?
    private var cropPress: CropPress?
    private var zoomBeforeCrop: CGFloat?
    private var saved: CursorScreenshotEdit
    private var undoStack: [CursorScreenshotEdit] = []
    private var redoStack: [CursorScreenshotEdit] = []
    private var viewport = CGSize.zero
    private var cropView = CGSize.zero
    private var grab: Grab?
    private var penAcross: Bool?
    private var retyping: (before: CursorScreenshotEdit, index: Int)?
    private var newTextClickY: CGFloat?
    private var lastChange: String?
    private var isHoldingChange = false
    private var isFlattening = false
    private static var copiedMark: CursorScreenshotMark?
    private static var copiedAt: Int?

    private struct Grab {
        let index: Int
        let handle: CursorScreenshotMarkHandle?
        let press: CGPoint
        let original: CursorScreenshotMark
        let before: CursorScreenshotEdit
        let isCopy: Bool
    }

    private struct CropPress {
        let handle: CursorScreenshotCropHandle
        var point: CGPoint
        var box: CGRect
        var acrossOnly: Bool?
    }

    init(picture: CursorScreenshotPicture, choices: CursorScreenshotEditorChoices = CursorScreenshotEditorChoices(),
         library: CursorScreenshotBackgroundLibrary = CursorScreenshotBackgroundLibrary(), backdropSource: CursorScreenshotBackdropSource = CursorScreenshotBackdropSource(),
         textLineSource: @escaping @Sendable (CursorScreenshotPicture) async -> [CGRect]? = { _ in [] }) {
        self.picture = picture
        self.choices = choices
        self.library = library
        self.backdropSource = backdropSource
        self.textLineSource = textLineSource
        tool = choices.tool
        let fill = picture.firstFill
        cropFill = fill
        var untouched = CursorScreenshotEdit(crop: CGRect(origin: .zero, size: picture.size))
        untouched.shared = CursorScreenshotShared(dim: choices.dim, redaction: choices.redaction, strength: choices.strength)
        untouched.fill = fill
        edit = untouched
        saved = untouched
        if tool == .highlight { startReadingTextLines() }
    }

    var marks: [CursorScreenshotMark] { edit.marks }
    var crop: CGRect { edit.crop }
    var shared: CursorScreenshotShared { edit.shared }
    var isCropping: Bool { cropDraft != nil }
    var shownArea: CGRect { isCropping ? wholePicture : crop }
    var wholePicture: CGRect { marks.reduce(CGRect(origin: .zero, size: picture.size)) { $1.tool == .image ? $0.union($1.rect) : $0 } }
    var cropOutputSize: CGSize { CursorScreenshotEdit.output(of: edit.layout(of: (cropDraft ?? crop).size, scale: picture.scale).size, scale: edit.outputScale) }
    var shownLayout: CursorScreenshotCanvasLayout { shownEdit.layout(of: shownArea.size, scale: picture.scale) }
    var isBackgroundOpen: Bool { library.isOpen }
    var presetID: String? { edit.presetID }
    var shownPreset: CursorScreenshotPreset? { library.presets.first { $0.id == presetID } ?? (edit.hasBackground ? library.presets.first { $0.style == edit.background } : nil) }
    var isPresetChanged: Bool { shownPreset.map { $0.style != edit.background } ?? false }
    var cropCutsThePicture: Bool { cropDraft.map { !$0.contains(wholePicture) } ?? false }
    var burnLosesEdits: Bool { !undoStack.isEmpty }
    var isDirty: Bool { edit.effect(on: picture) != saved.effect(on: picture) || typing?.text.isEmpty == false }
    var canUndo: Bool { isFree && !undoStack.isEmpty }
    var canRedo: Bool { isFree && !redoStack.isEmpty }
    var nextNumber: Int { marks.filter { $0.tool == .number }.map { $0.number + 1 }.max().map { max($0, choices.startingNumber) } ?? choices.startingNumber }
    var zoom: CGFloat { zoomChoice ?? fitZoom }
    var viewScale: CGFloat { zoom / picture.scale }
    var selectedMark: CursorScreenshotMark? { selection.flatMap { marks.indices.contains($0) ? marks[$0] : nil } }
    var propertyTool: CursorScreenshotTool { typing?.tool ?? selectedMark?.tool ?? tool }
    var shownColor: CursorScreenshotColor { (typing ?? selectedMark)?.color ?? choices.color }
    var shownTextStyle: CursorScreenshotTextStyle { (typing ?? selectedMark)?.textStyle ?? choices.textStyle }
    var shownArrowStyle: CursorScreenshotArrowStyle { selectedMark?.tool == .arrow ? selectedMark?.arrowStyle ?? choices.arrowStyle : choices.arrowStyle }
    var shownSpotlightShape: CursorScreenshotSpotlightShape { selectedMark?.tool == .spotlight ? selectedMark?.shape ?? choices.spotlightShape : choices.spotlightShape }
    var shownNumberStyle: CursorScreenshotNumberStyle { selectedMark?.tool == .number ? selectedMark?.numberStyle ?? choices.numberStyle : choices.numberStyle }
    var isGrabbing: Bool { grab != nil }
    var hasCopiedMark: Bool { Self.copiedMark != nil }
    var isCanvasLockedTool: Bool { (tool == .pen || tool == .highlight) && choices.canvasLocked }

    var size: CGFloat? {
        guard let kind = propertyTool.sizeKind else { return nil }
        return (typing ?? selectedMark)?.size ?? choices.size(of: kind)
    }

    var sizeValues: [CGFloat] { propertyTool.sizeKind?.values ?? [] }

    var shownEdit: CursorScreenshotEdit {
        if isCropping {
            var shown = edit
            shown.crop = wholePicture
            shown.fill = cropFill
            shown.background = CursorScreenshotBackgroundStyle()
            shown.balance = CursorScreenshotBalance()
            shown.backdrop = nil
            return shown
        }
        guard let draft, draft.tool == .spotlight || (draft.tool == .pixelate && marks.contains { $0.tool == .spotlight || $0.tool == .image }) else { return edit }
        var shown = edit
        shown.marks.append(draft)
        return shown
    }

    var drawsDraftOnTop: Bool { shownEdit.marks.count == marks.count }

    var remembered: CursorScreenshotEditorChoices {
        var kept = choices
        kept.tool = tool
        kept.dim = edit.shared.dim
        kept.redaction = edit.shared.redaction
        kept.strength = edit.shared.strength
        return kept
    }

    private var isFree: Bool { draft == nil && typing == nil && cropDraft == nil && grab == nil }
    private var pointUnit: CGFloat { 1 / max(viewScale, 0.0001) }

    func pick(_ tool: CursorScreenshotTool) {
        self.tool = tool
    }

    func setColor(_ color: CursorScreenshotColor) {
        choices.color = color
        typing?.color = color
        changeSelected("color") { $0.color = color }
    }

    func setSize(_ value: CGFloat) {
        guard let kind = propertyTool.sizeKind else { return }
        switch kind {
        case .thickness: choices.thickness = value
        case .highlight: choices.highlight = value
        case .text: choices.text = value
        case .number: choices.number = value
        }
        typing?.size = value
        keepNewTextInside()
        changeSelected("size") { $0.size = value }
    }

    func setArrowStyle(_ style: CursorScreenshotArrowStyle) {
        choices.arrowStyle = style
        changeSelected("arrow") { $0.arrowStyle = style }
    }

    func setSpotlightShape(_ shape: CursorScreenshotSpotlightShape) {
        choices.spotlightShape = shape
        changeSelected("shape") { $0.shape = shape }
    }

    func setTextStyle(_ style: CursorScreenshotTextStyle) {
        choices.textStyle = style
        typing?.textStyle = style
        keepNewTextInside()
        changeSelected("text style") { $0.textStyle = style }
    }

    func setNumberStyle(_ style: CursorScreenshotNumberStyle) {
        choices.numberStyle = style
        changeSelected("number style") { $0.numberStyle = style }
    }

    func setStartingNumber(_ number: Int) {
        choices.startingNumber = min(max(number, 1), CursorScreenshotEditorLook.largestStartingNumber)
    }

    func setCanvasLocked(_ locked: Bool) {
        choices.canvasLocked = locked
    }

    func setDim(_ percent: CGFloat) {
        let look = CursorScreenshotEditorLook.self
        let dim = min(max(percent, look.dimRange.lowerBound), look.dimRange.upperBound)
        guard dim != edit.shared.dim else { return }
        commitText()
        if marks.contains(where: { $0.tool == .spotlight }) { recordOnce("dim") }
        edit.shared.dim = dim
    }

    func setRedaction(_ style: CursorScreenshotRedactionStyle) {
        guard style != edit.shared.redaction else { return }
        commitText()
        if marks.contains(where: { $0.tool == .pixelate }) { recordOnce("redaction") }
        edit.shared.redaction = style
    }

    func setStrength(_ strength: CGFloat) {
        let look = CursorScreenshotEditorLook.self
        let whole = min(max(strength.rounded(), look.strengthRange.lowerBound), look.strengthRange.upperBound)
        guard whole != edit.shared.strength else { return }
        commitText()
        if marks.contains(where: { $0.tool == .pixelate }) { recordOnce("strength") }
        edit.shared.strength = whole
    }

    func setBackgroundOpen(_ open: Bool) {
        changeLibrary { $0.isOpen = open }
        if open { prepareBackdrops() }
    }

    @discardableResult
    func prepareBackdrops() -> Task<Void, Never>? {
        guard !backdropsStarted else { return backdropsTask }
        backdropsStarted = true
        let source = backdropSource
        let ids = library.wallpapers
        let image = picture.image
        backdropsTask = Task {
            let found = await Task.detached(priority: .userInitiated) { source.thumbnails(wallpapers: ids, picture: image) }.value
            for fill in [CursorScreenshotBackdropFill.blurredDesktop, .blurredPicture, .blurredPictureDark] { backdropImages[fill] = found[fill] }
            backdropThumbnails.merge(found) { _, new in new }
            if picture.image !== image { refreshPictureBackdrops() }
            let gone = ids.filter { found[.wallpaper($0)] == nil }
            if !gone.isEmpty { changeLibrary { $0.wallpapers.removeAll { gone.contains($0) } } }
        }
        return backdropsTask
    }

    private func changeLibrary(_ change: (inout CursorScreenshotBackgroundLibrary) -> Void) {
        change(&library)
        libraryChanged(change)
    }

    private func backdropImage(_ fill: CursorScreenshotBackdropFill) async -> CGImage? {
        guard !fill.drawsWithoutImage else { return nil }
        if let kept = backdropImages[fill] { return kept }
        let source = backdropSource
        let image = picture.image
        let made = await Task.detached(priority: .userInitiated) { source.image(for: fill, picture: image) }.value
        if picture.image !== image { return await backdropImage(fill) }
        backdropImages[fill] = made
        return made
    }

    private func refreshPictureBackdrops() {
        for fill in [CursorScreenshotBackdropFill.blurredPicture, .blurredPictureDark] {
            backdropImages[fill] = nil
            guard edit.background.fill == fill || backdropThumbnails[fill] != nil else { continue }
            let made = backdropSource.image(for: fill, picture: picture.image)
            backdropImages[fill] = made
            if backdropThumbnails[fill] != nil { backdropThumbnails[fill] = made }
            if edit.background.fill == fill { edit.backdrop = made }
        }
    }

    @discardableResult
    func pickBackdrop(_ fill: CursorScreenshotBackdropFill) async -> Bool {
        let image = await backdropImage(fill)
        guard fill.drawsWithoutImage || image != nil else { return false }
        setBackdrop(fill, image: image)
        return true
    }

    func pickColor(_ color: CursorScreenshotColor) {
        setBackdrop(.color(color.hex, color.alpha), image: nil, group: "panel colour \(CursorScreenshotSystemColors.press)")
    }

    private func setBackdrop(_ fill: CursorScreenshotBackdropFill, image: CGImage?, group: String? = nil) {
        commitText()
        var next = edit
        next.background.fill = fill
        next.backdrop = image
        guard next.effect(on: picture) != edit.effect(on: picture) else { return }
        if let group { recordOnce(group, repeats: true) } else { record() }
        edit = next
        runAutoValues()
        refit()
    }

    private func runAutoValues() {
        guard edit.background.fill != .none, !edit.chosenBackgroundValue else { return }
        let points = CGSize(width: crop.width / picture.scale, height: crop.height / picture.scale)
        edit.background = edit.background.withAutoValues(forPoints: points)
    }

    func setBackgroundValue(_ field: WritableKeyPath<CursorScreenshotBackgroundStyle, CGFloat>, _ value: CGFloat, range: ClosedRange<CGFloat>) {
        let whole = min(max(value.rounded(), range.lowerBound), range.upperBound)
        guard whole != edit.background[keyPath: field] else { return }
        commitText()
        recordOnce("\(field)")
        edit.background[keyPath: field] = whole
        edit.chosenBackgroundValue = true
        refit()
    }

    func setBackgroundAlignment(_ place: Int) {
        guard place != edit.background.alignment, (0..<9).contains(place) else { return }
        changeBackgroundPlace { $0.alignment = place }
    }

    func setBackgroundRatio(_ ratio: CursorScreenshotBackdropRatio) {
        guard ratio != edit.background.ratio else { return }
        changeBackgroundPlace { $0.ratio = ratio }
    }

    private func changeBackgroundPlace(_ change: (inout CursorScreenshotBackgroundStyle) -> Void) {
        commitText()
        var next = edit
        change(&next.background)
        if next.effect(on: picture) != edit.effect(on: picture) {
            record()
            next.chosenBackgroundValue = true
        }
        edit = next
        refit()
    }

    func setAutoBalance(_ on: Bool) async {
        guard on else {
            guard !edit.balance.isZero || edit.background.autoBalance else { return }
            commitText()
            record()
            edit.background.autoBalance = false
            edit.balance = CursorScreenshotBalance()
            edit.chosenBackgroundValue = true
            return refit()
        }
        let measured = await measuredBalance()
        guard !measured.isZero else { return }
        commitText()
        record()
        edit.balance = measured
        edit.background.autoBalance = true
        edit.chosenBackgroundValue = true
        refit()
    }

    private func measuredBalance() async -> CursorScreenshotBalance {
        let image = picture.image
        let area = crop
        let scale = picture.scale
        return await Task.detached(priority: .userInitiated) { CursorScreenshotBalance.measured(image, crop: area, scale: scale) }.value
    }

    private func refreshAfterCrop() {
        runAutoValues()
        guard edit.background.autoBalance else { return }
        edit.balance = CursorScreenshotBalance.measured(picture.image, crop: crop, scale: picture.scale)
        if edit.balance.isZero { edit.background.autoBalance = false }
    }

    func clearBackground() {
        guard edit.hasBackground || presetID != nil else { return }
        commitText()
        record()
        let ratio = edit.background.ratio
        edit.background = CursorScreenshotBackgroundStyle(ratio: ratio)
        edit.balance = CursorScreenshotBalance()
        edit.backdrop = nil
        edit.presetID = nil
        edit.chosenBackgroundValue = false
        refit()
    }

    func applyPreset(_ preset: CursorScreenshotPreset) async {
        await applyStyle(preset.style)
        edit.presetID = preset.id
    }

    func applyPrevious() async {
        guard let previous = library.previous else { return }
        await applyStyle(previous)
        edit.presetID = nil
    }

    private func applyStyle(_ style: CursorScreenshotBackgroundStyle) async {
        let image = await backdropImage(style.fill)
        let balance = style.autoBalance ? await measuredBalance() : CursorScreenshotBalance()
        commitText()
        var next = edit
        next.background = style
        next.backdrop = image
        next.balance = balance
        if !style.fill.drawsWithoutImage, image == nil { next.background.fill = .none }
        if balance.isZero { next.background.autoBalance = false }
        next.chosenBackgroundValue = true
        if next.effect(on: picture) != edit.effect(on: picture) { record() }
        edit = next
        refit()
    }

    func addPreset(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let preset = CursorScreenshotPreset(id: UUID().uuidString, name: trimmed, style: edit.background)
        guard !trimmed.isEmpty else { return }
        changeLibrary { $0.presets.append(preset) }
        edit.presetID = preset.id
    }

    func saveShownPreset() {
        guard let id = shownPreset?.id, library.presets.contains(where: { $0.id == id }) else { return }
        let style = edit.background
        changeLibrary { kept in
            if let index = kept.presets.firstIndex(where: { $0.id == id }) { kept.presets[index].style = style }
        }
        edit.presetID = id
    }

    func deleteShownPreset() {
        guard let id = shownPreset?.id else { return }
        changeLibrary {
            $0.presets.removeAll { $0.id == id }
            if $0.defaultPreset == id { $0.defaultPreset = nil }
        }
        edit.presetID = nil
    }

    func setDefaultPreset(_ id: String?) {
        changeLibrary { $0.defaultPreset = id }
    }

    func noteKept() {
        saved = edit
    }

    func noteClosing() {
        guard saved.background.padding > 0 else { return }
        let style = saved.background
        changeLibrary { $0.previous = style }
    }

    func addWallpaper(from url: URL) async -> Bool {
        guard library.wallpapers.count < CursorScreenshotBackgroundLibrary.wallpaperLimit else { return false }
        let source = backdropSource
        let added = await Task.detached(priority: .userInitiated) { source.addWallpaper(from: url).map { (id: $0, thumbnail: source.wallpaperThumbnail($0)) } }.value
        guard let added, library.wallpapers.count < CursorScreenshotBackgroundLibrary.wallpaperLimit else {
            if let added { source.removeWallpaper(added.id) }
            return false
        }
        changeLibrary { $0.wallpapers.append(added.id) }
        backdropThumbnails[.wallpaper(added.id)] = added.thumbnail
        return await pickBackdrop(.wallpaper(added.id))
    }

    func removeWallpaper(_ id: String) {
        backdropSource.removeWallpaper(id)
        changeLibrary { $0.wallpapers.removeAll { $0 == id } }
        backdropThumbnails[.wallpaper(id)] = nil
        backdropImages[.wallpaper(id)] = nil
    }

    func deselect() {
        select(nil)
    }

    func deleteSelected() {
        guard grab == nil, let index = selection, marks.indices.contains(index) else { return }
        record()
        edit.marks.remove(at: index)
        select(nil)
    }

    func duplicateSelected() {
        guard grab == nil, let mark = selectedMark else { return }
        place(mark)
    }

    func copySelected(on pasteboard: NSPasteboard = .general) {
        Self.copiedMark = selectedMark
        Self.copiedAt = pasteboard.changeCount
    }

    func pasteMark() {
        guard grab == nil, let mark = Self.copiedMark else { return }
        place(mark)
    }

    func clipboardImageWins(on pasteboard: NSPasteboard = .general) -> Bool {
        CursorScreenshotImageSource.holdsImage(pasteboard) && (Self.copiedMark == nil || Self.copiedAt != pasteboard.changeCount)
    }

    @discardableResult
    func addImages(_ images: [CursorScreenshotPicture], edge: CursorScreenshotImageEdge? = .bottom, visible: CGRect? = nil) -> Bool {
        guard !images.isEmpty else { return false }
        commitText()
        applyCrop()
        endDrag()
        record()
        let step = CursorScreenshotEditorLook.copyOffsetPoints * picture.scale
        for (index, image) in images.enumerated() {
            let shift = CGFloat(index) * step
            let box = edge?.landing(of: image.size, beside: crop) ?? CursorScreenshotImageEdge.centred(image.size, in: visible ?? crop).offsetBy(dx: shift, dy: shift)
            var mark = CursorScreenshotMark(tool: .image, start: box.origin, end: CGPoint(x: box.maxX, y: box.maxY))
            mark.image = image
            edit.marks.insert(mark, at: 0)
            edit.crop = crop.union(box)
        }
        select(0)
        refit()
        if tool == .highlight { startReadingTextLines() }
        return true
    }

    func addImages(from files: [URL], edge: CursorScreenshotImageEdge? = .bottom, visible: CGRect? = nil) async -> Bool {
        let scale = picture.scale
        let found = await Task.detached(priority: .userInitiated) {
            files.compactMap { CursorScreenshotImageSource.picture(from: CGImageSourceCreateWithURL($0 as CFURL, nil), scale: scale) }
        }.value
        return addImages(found, edge: edge, visible: visible)
    }

    func pasteImage(from pasteboard: NSPasteboard = .general) async -> Bool {
        let files = CursorScreenshotImageSource.files(on: pasteboard)
        guard files.isEmpty else { return await addImages(from: files) }
        guard let data = CursorScreenshotImageSource.data(on: pasteboard) else { return false }
        let scale = picture.scale
        let found = await Task.detached(priority: .userInitiated) {
            CursorScreenshotImageSource.picture(from: CGImageSourceCreateWithData(data as CFData, nil), scale: scale)
        }.value
        return addImages(found.map { [$0] } ?? [])
    }

    func addCapture(show: @escaping @MainActor () -> Void, source: (@escaping @MainActor (CGImage?) -> Void) -> Void) {
        commitText()
        applyCrop()
        source { [weak self] image in
            if let self, let image, let picture = CursorScreenshotPicture(image, scale: self.picture.scale) { self.addImages([picture]) }
            show()
        }
    }

    func nudgeSelected(x: CGFloat, y: CGFloat) {
        let delta = CGPoint(x: x * picture.scale, y: y * picture.scale)
        changeSelected("nudge", repeats: true) { mark in
            let moved = mark.moved(by: delta)
            if CursorScreenshotRender.bounds(of: moved, scale: picture.scale).intersects(crop) { mark = moved }
        }
    }

    func editSelectedText() {
        guard grab == nil, let index = selection, let mark = selectedMark, mark.tool == .text else { return }
        retyping = (edit, index)
        edit.marks.remove(at: index)
        select(nil)
        typing = mark
    }

    private func place(_ mark: CursorScreenshotMark) {
        let step = CursorScreenshotEditorLook.copyOffsetPoints * picture.scale
        var copy = mark.moved(by: CGPoint(x: step, y: step))
        let area = CursorScreenshotRender.bounds(of: copy, scale: picture.scale)
        if !area.intersects(crop) { copy = copy.moved(by: CGPoint(x: crop.midX - area.midX, y: crop.midY - area.midY)) }
        record()
        select(insert(copy))
        if tool == .highlight { startReadingTextLines() }
    }

    private func insert(_ mark: CursorScreenshotMark) -> Int {
        let at = mark.tool == .image ? marks.lastIndex { $0.tool == .image }.map { $0 + 1 } ?? 0 : marks.count
        edit.marks.insert(mark, at: at)
        return at
    }

    private func select(_ index: Int?) {
        lastChange = nil
        if selection != index { selection = index }
    }

    private func changeSelected(_ key: String, repeats: Bool = false, _ change: (inout CursorScreenshotMark) -> Void) {
        guard grab == nil, let index = selection, marks.indices.contains(index) else { return }
        var mark = marks[index]
        change(&mark)
        guard mark != marks[index] else { return }
        recordOnce("\(key) \(index)", repeats: repeats)
        edit.marks[index] = mark
    }

    func holdChange(_ held: Bool) {
        isHoldingChange = held
        lastChange = nil
    }

    private func recordOnce(_ key: String, repeats: Bool = false) {
        if lastChange != key { record() }
        lastChange = repeats || isHoldingChange ? key : nil
    }

    func stepSize(up: Bool) {
        guard let current = size else { return }
        if let next = up ? sizeValues.first(where: { $0 > current }) : sizeValues.last(where: { $0 < current }) { setSize(next) }
    }

    func pickSize(number: Int) {
        if sizeValues.indices.contains(number - 1) { setSize(sizeValues[number - 1]) }
    }

    func setPickerOpen(_ open: Bool) {
        choices.pickerOpen = open
    }

    func addToMyColors(_ color: CursorScreenshotColor) {
        guard !choices.myColors.contains(color) else { return }
        choices.myColors.append(color)
        if choices.myColors.count > CursorScreenshotEditorLook.myColorSlots { choices.myColors.removeFirst() }
    }

    func setViewport(_ room: CGSize, cropView: CGSize? = nil) {
        viewport = room
        self.cropView = cropView ?? room
        refit()
    }

    func setZoom(_ zoom: CGFloat) {
        zoomChoice = CursorScreenshotZoom.clamped(zoom, cropping: isCropping)
    }

    func zoomToFit() {
        zoomChoice = nil
    }

    func stepZoom(up: Bool) {
        zoomChoice = CursorScreenshotZoom.stepped(from: zoom, up: up, cropping: isCropping)
    }

    func beginDrag(at point: CGPoint, flags: NSEvent.ModifierFlags = []) {
        guard typing == nil else { return commitText() }
        if let cropDraft {
            cropPress = CursorScreenshotCropHandle.hit(point, on: cropDraft, unit: pointUnit).map { CropPress(handle: $0, point: point, box: cropDraft) }
            return
        }
        lastChange = nil
        if grabMark(at: point, flags: flags) { return }
        if selection != nil { return select(nil) }
        let start = inside(point)
        penAcross = nil
        switch tool {
        case .text:
            guard crop.contains(point) else { return }
            var mark = newMark(.text, start: start, end: start, size: choices.text)
            mark.end.y -= CursorScreenshotRender.textLayout(mark, scale: picture.scale).frame.height / 2
            typing = mark
            newTextClickY = nil
            keepNewTextInside()
            newTextClickY = typing?.start.y == mark.end.y ? nil : start.y
        case .number:
            guard crop.contains(point) else { return }
            var mark = newMark(.number, start: start, end: start, size: choices.number)
            mark.number = nextNumber
            add(mark)
        case .highlight:
            var mark = newMark(.highlight, start: start, end: start, size: choices.highlight)
            if let line = textLine(at: point) {
                mark.isTextLine = true
                mark.start.y = line.midY
                mark.end.y = line.midY
                mark.size = line.height * (1 + 2 * CursorScreenshotEditorLook.highlightLinePad) / picture.scale
            }
            mark.path = [mark.start]
            draft = mark
            startReadingTextLines()
        case .pen:
            var mark = newMark(.pen, start: start, end: start, size: choices.thickness)
            mark.path = [start]
            draft = mark
        case .arrow, .box, .filledBox, .oval, .line, .pixelate, .spotlight:
            var mark = newMark(tool, start: start, end: start, size: choices.thickness)
            mark.reversed = tool == .arrow && flags.contains(.option)
            draft = mark
        case .select, .image:
            break
        }
    }

    func updateDrag(to point: CGPoint, flags: NSEvent.ModifierFlags = [], spaceHeld: Bool = false) {
        if cropPress != nil { return dragCrop(to: point, flags: flags, spaceHeld: spaceHeld) }
        if let grab { return dragGrab(grab, to: point, flags: flags) }
        guard var mark = draft else { return }
        let end = inside(point)
        let shift = flags.contains(.shift)
        switch mark.tool {
        case .highlight where mark.isTextLine:
            mark.end.x = end.x
            mark.path = [mark.start, mark.end]
        case .highlight:
            mark.end = end
            mark.path.append(end)
        case .pen:
            mark.end = drawnPenPoint(end, on: &mark, straight: shift)
        case .line, .arrow:
            mark.end = shift ? keptInside(Self.onEighth(end, from: mark.start), from: mark.start, in: crop) : end
        case .box, .filledBox, .oval, .pixelate, .spotlight:
            mark.end = shift ? keptInside(Self.square(end, from: mark.start), from: mark.start, in: crop) : end
        default:
            mark.end = end
        }
        draft = mark
    }

    func endDrag() {
        cropPress = nil
        if let grab { return finishGrab(grab) }
        guard let finished = draft else { return }
        draft = nil
        guard finished.isBigEnough else { return }
        add(finished.tool == .highlight ? straightened(finished) : finished)
        if finished.tool == .pixelate { select(marks.count - 1) }
    }

    func readTextLines() async {
        let sources = [picture] + marks.compactMap(\.image)
        for source in sources where textLines[ObjectIdentifier(source.image)] == nil {
            let id = ObjectIdentifier(source.image)
            textLines[id] = (source.image, [])
            textLines[id] = await textLineSource(source).map { (source.image, $0) }
        }
    }

    private func startReadingTextLines() {
        Task { await readTextLines() }
    }

    private func textLine(at point: CGPoint) -> CGRect? {
        let reach = CursorScreenshotEditorLook.textLineReachPoints * pointUnit
        let nearest = { (lines: [CGRect]) in
            lines.filter { $0.intersects(self.crop) && $0.insetBy(dx: -reach, dy: -reach).contains(point) }.min { abs($0.midY - point.y) < abs($1.midY - point.y) }
        }
        if let top = marks.last(where: { $0.tool == .image && $0.rect.contains(point) }), let image = top.image {
            let across = top.rect.width / image.size.width
            let down = top.rect.height / image.size.height
            return nearest((textLines[ObjectIdentifier(image.image)]?.lines ?? []).map {
                CGRect(x: top.rect.minX + $0.minX * across, y: top.rect.minY + $0.minY * down, width: $0.width * across, height: $0.height * down)
            })
        }
        return nearest(textLines[ObjectIdentifier(picture.image)]?.lines ?? [])
    }

    func setTypedText(_ text: String) {
        typing?.text = text
        keepNewTextInside()
    }

    private func keepNewTextInside() {
        guard retyping == nil, var mark = typing else { return }
        mark.start = mark.end
        if let newTextClickY { mark.start.y = newTextClickY - CursorScreenshotRender.textLayout(mark, scale: picture.scale).frame.height / 2 }
        let room = mark.start.x + CursorScreenshotEditorLook.newTextWidthPoints * picture.scale
        let area = CursorScreenshotRender.bounds(of: mark, scale: picture.scale)
        let reach = max(area.maxX, room)
        mark.start.x = max(mark.start.x + min(crop.maxX - reach, 0), crop.minX + mark.start.x - area.minX)
        mark.start.y = max(mark.start.y + min(crop.maxY - area.maxY, 0), crop.minY + mark.start.y - area.minY)
        typing = mark
    }

    func commitText() {
        guard var mark = typing else { return }
        typing = nil
        let back = retyping
        retyping = nil
        mark.text = mark.text.components(separatedBy: .newlines).joined(separator: " ")
        guard let back else {
            guard !mark.text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            return add(mark)
        }
        if !mark.text.trimmingCharacters(in: .whitespaces).isEmpty { edit.marks.insert(mark, at: min(back.index, marks.count)) }
        guard edit != back.before else { return }
        pushUndo(back.before)
    }

    func cancelText() {
        typing = nil
        if let back = retyping { edit = back.before }
        retyping = nil
    }

    private func newMark(_ tool: CursorScreenshotTool, start: CGPoint, end: CGPoint, size: CGFloat) -> CursorScreenshotMark {
        var mark = CursorScreenshotMark(tool: tool, start: start, end: end, color: choices.color, size: size)
        mark.arrowStyle = choices.arrowStyle
        mark.shape = choices.spotlightShape
        mark.textStyle = choices.textStyle
        mark.numberStyle = choices.numberStyle
        return mark
    }

    private func grabMark(at point: CGPoint, flags: NSEvent.ModifierFlags) -> Bool {
        guard !isCanvasLockedTool else { return false }
        let look = CursorScreenshotEditorLook.self
        let scale = picture.scale
        if let index = selection, let mark = selectedMark {
            let reach = look.handleReachPoints * pointUnit
            let away = { (spot: CGPoint) in hypot(spot.x - point.x, spot.y - point.y) }
            if let hit = CursorScreenshotRender.handles(of: mark, scale: scale).filter({ away($0.point) <= reach }).min(by: { away($0.point) < away($1.point) }) {
                grab = Grab(index: index, handle: hit.handle, press: point, original: mark, before: edit, isCopy: false)
                return true
            }
            if CursorScreenshotRender.isHit(mark, at: point, reach: look.selectedReachPoints * pointUnit, scale: scale) {
                grabBody(index, press: point, flags: flags)
                return true
            }
        }
        let reach = look.markReachPoints * pointUnit
        guard inside(point) == point, let index = marks.lastIndex(where: { (tool == .select || $0.tool != .image) && CursorScreenshotRender.bounds(of: $0, scale: scale).intersects(crop) && CursorScreenshotRender.isHit($0, at: point, reach: reach, scale: scale) }) else { return false }
        grabBody(index, press: point, flags: flags)
        return true
    }

    private func grabBody(_ index: Int, press: CGPoint, flags: NSEvent.ModifierFlags) {
        let before = edit
        var at = index
        let isCopy = flags.contains(.option)
        if isCopy { at = insert(marks[index]) }
        select(at)
        grab = Grab(index: at, handle: nil, press: inside(press), original: marks[at], before: before, isCopy: isCopy)
    }

    private func dragGrab(_ grab: Grab, to point: CGPoint, flags: NSEvent.ModifierFlags) {
        guard marks.indices.contains(grab.index) else { return }
        let pressed = grab.handle.flatMap { grabbed in CursorScreenshotRender.handles(of: grab.original, scale: picture.scale).first { $0.handle == grabbed }?.point } ?? grab.press
        var target = CGPoint(x: min(max(pressed.x + (point.x - grab.press.x), min(crop.minX, pressed.x)), max(crop.maxX, pressed.x)),
                             y: min(max(pressed.y + (point.y - grab.press.y), min(crop.minY, pressed.y)), max(crop.maxY, pressed.y)))
        guard target != pressed else {
            guides = ([], [])
            edit.marks[grab.index] = grab.original
            return
        }
        let snaps = flags.isDisjoint(with: [.command, .control])
        let shift = flags.contains(.shift)
        guard let handle = grab.handle else {
            var delta = CGPoint(x: target.x - grab.press.x, y: target.y - grab.press.y)
            if shift {
                if abs(delta.x) >= abs(delta.y) { delta.y = 0 } else { delta.x = 0 }
            }
            var moved = grab.original.moved(by: delta)
            guides = ([], [])
            if snaps {
                let area = CursorScreenshotRender.bounds(of: moved, scale: picture.scale)
                let across = snapped([area.minX, area.maxX], to: edges(except: grab.index).across)
                let down = snapped([area.minY, area.maxY], to: edges(except: grab.index).down)
                moved = moved.moved(by: CGPoint(x: across?.by ?? 0, y: down?.by ?? 0))
                guides = (across.map { [$0.at] } ?? [], down.map { [$0.at] } ?? [])
            }
            let area = CursorScreenshotRender.bounds(of: moved, scale: picture.scale)
            let back = CGPoint(x: max(crop.minX + pointUnit - area.maxX, 0) + min(crop.maxX - pointUnit - area.minX, 0),
                               y: max(crop.minY + pointUnit - area.maxY, 0) + min(crop.maxY - pointUnit - area.minY, 0))
            if back.x != 0 { guides.across = [] }
            if back.y != 0 { guides.down = [] }
            edit.marks[grab.index] = moved.moved(by: back)
            return
        }
        guides = ([], [])
        if snaps, handle != .control {
            let across = snapped([target.x], to: edges(except: grab.index).across)
            let down = snapped([target.y], to: edges(except: grab.index).down)
            target = CGPoint(x: target.x + (across?.by ?? 0), y: target.y + (down?.by ?? 0))
            guides = (across.map { [$0.at] } ?? [], down.map { [$0.at] } ?? [])
        }
        edit.marks[grab.index] = resized(grab.original, handle: handle, to: target, from: pressed, shift: shift)
    }

    private func finishGrab(_ grab: Grab) {
        self.grab = nil
        guides = ([], [])
        guard marks.indices.contains(grab.index) else { return }
        if grab.isCopy && marks[grab.index] == grab.original {
            edit = grab.before
            return select(nil)
        }
        if grab.handle != nil, grab.original.tool != .text, grab.original.isBigEnough, !marks[grab.index].isBigEnough {
            edit = grab.before
            return
        }
        guard edit != grab.before else { return }
        pushUndo(grab.before)
    }

    private func edges(except index: Int) -> (across: [CGFloat], down: [CGFloat]) {
        var across: [CGFloat] = []
        var down: [CGFloat] = []
        for (at, mark) in marks.enumerated() where at != index {
            let area = CursorScreenshotRender.bounds(of: mark, scale: picture.scale)
            across += [area.minX, area.maxX]
            down += [area.minY, area.maxY]
        }
        return (across, down)
    }

    private func snapped(_ values: [CGFloat], to lines: [CGFloat]) -> (by: CGFloat, at: CGFloat)? {
        var best: (by: CGFloat, at: CGFloat)?
        let reach = CursorScreenshotEditorLook.snapPoints * pointUnit
        for value in values {
            for line in lines where abs(line - value) <= reach && abs(line - value) < abs(best?.by ?? .infinity) {
                best = (line - value, line)
            }
        }
        return best
    }

    private func resized(_ mark: CursorScreenshotMark, handle: CursorScreenshotMarkHandle, to point: CGPoint, from pressed: CGPoint, shift: Bool) -> CursorScreenshotMark {
        var changed = mark
        let rect = mark.rect
        let area = crop.union(CGRect(origin: pressed, size: .zero))
        switch handle {
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            let fixed = CGPoint(x: handle == .topLeft || handle == .bottomLeft ? rect.maxX : rect.minX, y: handle == .topLeft || handle == .topRight ? rect.maxY : rect.minY)
            var corner = point
            if shift != (mark.tool == .image), rect.width > 0, rect.height > 0 {
                let ratio = rect.width / rect.height
                let wide = abs(point.x - fixed.x)
                let high = abs(point.y - fixed.y)
                corner = wide / ratio >= high ? CGPoint(x: point.x, y: fixed.y + (point.y >= fixed.y ? 1 : -1) * wide / ratio)
                                              : CGPoint(x: fixed.x + (point.x >= fixed.x ? 1 : -1) * high * ratio, y: point.y)
                if mark.tool != .image { corner = keptInside(corner, from: fixed, in: area) }
            }
            changed.start = fixed
            changed.end = corner
        case .start:
            changed.start = shift ? keptInside(Self.onEighth(point, from: mark.end), from: mark.end, in: area) : point
        case .end:
            changed.end = shift ? keptInside(Self.onEighth(point, from: mark.start), from: mark.start, in: area) : point
        case .control:
            changed.control = point
        case .textLeft:
            let right = CursorScreenshotRender.textLayout(mark, scale: picture.scale).frame.maxX
            let smallest = CursorScreenshotEditorLook.smallestTextWidthPoints * picture.scale
            changed.start.x = min(point.x, right - smallest)
            changed.wrap = right - changed.start.x
        case .textRight, .textWidth:
            let smallest = CursorScreenshotEditorLook.smallestTextWidthPoints * picture.scale
            changed.wrap = max(point.x - mark.start.x, smallest)
        }
        return changed
    }

    private func drawnPenPoint(_ point: CGPoint, on mark: inout CursorScreenshotMark, straight: Bool) -> CGPoint {
        guard let last = mark.path.last else { return point }
        var kept = point
        if straight {
            let across = penAcross ?? (abs(point.x - last.x) >= abs(point.y - last.y))
            penAcross = across
            kept = across ? CGPoint(x: point.x, y: last.y) : CGPoint(x: last.x, y: point.y)
        } else {
            penAcross = nil
        }
        let step = CursorScreenshotEditorLook.penStepPoints * picture.scale
        if abs(kept.x - last.x) > step || abs(kept.y - last.y) > step { mark.path.append(kept) }
        return kept
    }

    private static func onEighth(_ point: CGPoint, from start: CGPoint) -> CGPoint {
        let length = hypot(point.x - start.x, point.y - start.y)
        let turn = (atan2(point.y - start.y, point.x - start.x) / (CGFloat.pi / 4)).rounded() / 4
        return CGPoint(x: start.x + __cospi(turn) * length, y: start.y + __sinpi(turn) * length)
    }

    private static func square(_ point: CGPoint, from start: CGPoint) -> CGPoint {
        let side = max(abs(point.x - start.x), abs(point.y - start.y))
        return CGPoint(x: start.x + (point.x >= start.x ? side : -side), y: start.y + (point.y >= start.y ? side : -side))
    }

    func openCrop() {
        guard !isCropping else { return }
        commitText()
        select(nil)
        cropRatio = CursorScreenshotCropRatio()
        zoomBeforeCrop = zoomChoice
        zoomChoice = nil
        cropDraft = crop
        refit()
    }

    func applyCrop() {
        guard let cropDraft else { return }
        keepCrop(cropDraft, outputScale: edit.outputScale)
        closeCrop()
    }

    func cancelCrop() {
        guard isCropping else { return }
        closeCrop()
    }

    private func closeCrop() {
        cropDraft = nil
        cropPress = nil
        zoomChoice = zoomBeforeCrop
        refit()
    }

    private func keepCrop(_ box: CGRect, outputScale: CGFloat) {
        var next = edit
        next.crop = box
        next.fill = cropFill
        next.outputScale = outputScale
        if next.effect(on: picture) != edit.effect(on: picture) { record() }
        edit = next
        refreshAfterCrop()
    }

    private var cropReach: CGRect {
        let outside = CursorScreenshotEditorLook.cropOutsideShare
        let whole = wholePicture
        return whole.insetBy(dx: -whole.width * outside, dy: -whole.height * outside).integral
    }

    private func setCropBox(_ box: CGRect) {
        let kept = box.intersection(cropReach)
        if !kept.isNull { cropDraft = kept }
    }

    private func moveCropBox(to box: CGRect) {
        let reach = cropReach
        cropDraft = CGRect(x: min(max(box.minX, reach.minX), reach.maxX - box.width).rounded(), y: min(max(box.minY, reach.minY), reach.maxY - box.height).rounded(), width: box.width, height: box.height)
    }

    private func snapsNow(_ flags: NSEvent.ModifierFlags) -> Bool {
        choices.snapsCrop == flags.isDisjoint(with: [.command, .control])
    }

    private func dragCrop(to point: CGPoint, flags: NSEvent.ModifierFlags, spaceHeld: Bool) {
        guard var press = cropPress else { return }
        let delta = CGPoint(x: point.x - press.point.x, y: point.y - press.point.y)
        if spaceHeld || press.handle == .whole {
            var step = delta
            if flags.contains(.shift), !spaceHeld {
                let across = press.acrossOnly ?? (abs(delta.x) >= abs(delta.y))
                if delta != .zero { press.acrossOnly = across }
                if across { step.y = 0 } else { step.x = 0 }
            }
            var box = press.box.offsetBy(dx: step.x, dy: step.y)
            if spaceHeld {
                press.box = box
                press.point = point
            } else if snapsNow(flags) {
                box = movedOntoEdges(box, reach: CursorScreenshotEditorLook.cropSnapPoints * pointUnit)
            }
            moveCropBox(to: box)
            cropPress = press
            return
        }
        let handle = press.handle
        var target = CGPoint(x: (handle.movesLeft ? press.box.minX : press.box.maxX) + delta.x, y: (handle.movesTop ? press.box.minY : press.box.maxY) + delta.y)
        if snapsNow(flags) {
            if handle.movesLeft || handle.movesRight { target.x = snappedEdge(target.x, along: point.y, vertical: true) }
            if handle.movesTop || handle.movesBottom { target.y = snappedEdge(target.y, along: point.x, vertical: false) }
        }
        let ratio = cropRatio.locked.map { CGFloat($0.width) / CGFloat($0.height) } ?? (flags.contains(.shift) ? press.box.width / max(press.box.height, 1) : nil)
        setCropBox(handle.resized(press.box, to: target, ratio: ratio, fromCentre: flags.contains(.option), smallest: smallestCropBox, within: cropReach))
    }

    private var smallestCropBox: CGFloat {
        max(CursorScreenshotEditorLook.smallestCropPoints * pointUnit, 1)
    }

    private func snappedEdge(_ value: CGFloat, along: CGFloat, vertical: Bool) -> CGFloat {
        let look = CursorScreenshotEditorLook.self
        let reach = look.cropSnapPoints * pointUnit
        let whole = wholePicture
        let edges = vertical ? [0, picture.size.width, whole.minX, whole.maxX] : [0, picture.size.height, whole.minY, whole.maxY]
        if let edge = edges.first(where: { abs(value - $0) <= reach }) { return edge }
        return CursorScreenshotCropSnap.line(in: picture.image, near: value, along: along, vertical: vertical,
                                             reach: look.cropLineReachPoints * pointUnit, length: look.cropLineLengthPoints * pointUnit) ?? value
    }

    private func movedOntoEdges(_ box: CGRect, reach: CGFloat) -> CGRect {
        let whole = wholePicture
        let nearest = { (pairs: [(CGFloat, CGFloat)]) -> CGFloat in
            pairs.map { $0.1 - $0.0 }.filter { abs($0) <= reach }.min { abs($0) < abs($1) } ?? 0
        }
        let across = nearest([(box.minX, whole.minX), (box.maxX, whole.maxX), (box.midX, whole.midX)])
        let down = nearest([(box.minY, whole.minY), (box.maxY, whole.maxY), (box.midY, whole.midY)])
        return box.offsetBy(dx: across, dy: down)
    }

    func nudgeCrop(x: CGFloat, y: CGFloat, big: Bool, resizes: Bool) {
        guard let cropDraft else { return }
        let look = CursorScreenshotEditorLook.self
        let across = x * pointUnit
        let down = y * pointUnit
        if resizes {
            let target = CGPoint(x: cropDraft.maxX + across, y: cropDraft.maxY + down)
            let ratio = cropRatio.locked.map { CGFloat($0.width) / CGFloat($0.height) }
            setCropBox(CursorScreenshotCropHandle.bottomRight.resized(cropDraft, to: target, ratio: ratio, fromCentre: false, smallest: smallestCropBox, within: cropReach))
        } else {
            var box = cropDraft.offsetBy(dx: across, dy: down)
            if choices.snapsCrop { box = movedOntoEdges(box, reach: (big ? look.cropBigKeySnapPoints : look.cropKeySnapPoints) * pointUnit) }
            moveCropBox(to: box)
        }
    }

    func pickRatio(_ item: CursorScreenshotCropRatioItem) {
        switch item {
        case .custom: return
        case .freeform: cropRatio = CursorScreenshotCropRatio()
        default:
            guard let numbers = item.numbers(for: picture.size) else { return }
            setRatio(width: numbers.width, height: numbers.height)
        }
    }

    func setRatio(width: Int?, height: Int?) {
        cropRatio = CursorScreenshotCropRatio(width: width, height: height)
        guard isCropping, let locked = cropRatio.locked else { return }
        let whole = wholePicture
        setCropBox(CursorScreenshotCropRatio.box(locked.width, locked.height, in: whole.size).offsetBy(dx: whole.minX, dy: whole.minY))
    }

    func swapRatio() {
        setRatio(width: cropRatio.height, height: cropRatio.width)
    }

    func setCropFill(_ fill: CursorScreenshotCropFill) {
        cropFill = fill
    }

    func setSnapsCrop(_ snaps: Bool) {
        choices.snapsCrop = snaps
    }

    func revertCrop() {
        guard let cropDraft else { return }
        let hadRatio = cropRatio.locked != nil
        cropRatio = CursorScreenshotCropRatio()
        cropFill = .transparent
        guard hadRatio else { return setCropBox(wholePicture) }
        setCropBox(CGRect(x: wholePicture.minX, y: cropDraft.minY, width: cropDraft.width, height: cropDraft.height))
    }

    func turn(_ turn: CursorScreenshotCropTurn) {
        guard let burned = burnedImage(size: CursorScreenshotEdit.output(of: wholePicture.size, scale: 1)), let turned = CursorScreenshotRender.turned(burned, turn, space: picture.space) else { return }
        replacePicture(with: turned, crop: nil)
    }

    @discardableResult
    func resize(_ request: CursorScreenshotCropResize) -> Bool {
        guard !request.isUnchanged else { return true }
        let box = cropDraft ?? crop
        let canvas = edit.layout(of: box.size, scale: picture.scale).size
        guard request.flattens else {
            let factor = (request.pixels.width / max(canvas.width, 1) + request.pixels.height / max(canvas.height, 1)) / 2
            keepCrop(box, outputScale: factor)
            if isCropping { closeCrop() }
            return true
        }
        let contentWidth = max(request.pixels.width - (canvas.width - box.width), 1)
        let contentHeight = max(request.pixels.height - (canvas.height - box.height), 1)
        let across = contentWidth / max(box.width, 1)
        let down = contentHeight / max(box.height, 1)
        let whole = wholePicture
        let size = CGSize(width: max((whole.width * across).rounded(), 1), height: max((whole.height * down).rounded(), 1))
        guard max(size.width, size.height) <= CGFloat(CursorScreenshotEditorLook.largestImageSide), let burned = burnedImage(size: size) else { return false }
        let scaled = CGRect(x: ((box.minX - whole.minX) * across).rounded(), y: ((box.minY - whole.minY) * down).rounded(), width: contentWidth, height: contentHeight)
        replacePicture(with: burned, crop: scaled, resized: (across + down) / 2)
        if isCropping { closeCrop() }
        return true
    }

    private func burnedImage(size: CGSize) -> CGImage? {
        CursorScreenshotRender.scene(picture, marks: edit.marks, shared: edit.shared, crop: wholePicture, size: size)
    }

    private func replacePicture(with image: CGImage, crop box: CGRect?, resized: CGFloat = 1) {
        guard let next = CursorScreenshotPicture(image, scale: picture.scale, density: picture.density * resized) else { return }
        picture = next
        textLines.removeAll()
        edit.marks = []
        edit.crop = box ?? wholePicture
        if box != nil { edit.outputScale = 1 }
        edit.burns += 1
        refreshAfterCrop()
        refreshPictureBackdrops()
        undoStack.removeAll()
        redoStack.removeAll()
        lastChange = nil
        if box == nil { cropRatio = CursorScreenshotCropRatio() }
        if isCropping { cropDraft = edit.crop }
        refit()
        if tool == .highlight { startReadingTextLines() }
    }

    func undo() {
        guard isFree, let previous = undoStack.popLast() else { return }
        redoStack.append(edit)
        step(to: previous)
    }

    func redo() {
        guard isFree, let next = redoStack.popLast() else { return }
        undoStack.append(edit)
        step(to: next)
    }

    private func step(to next: CursorScreenshotEdit) {
        if next.fill != edit.fill { cropFill = next.fill }
        edit = next
        select(nil)
        refit()
        if tool == .highlight { startReadingTextLines() }
    }

    func copy(to pasteboard: NSPasteboard = .general) async -> Bool {
        guard let made = await encoded() else { return false }
        let (mode, folder, name) = clipboard()
        return CursorScreenshot.copy(made.data, as: made.format, mode: mode, in: folder, name: name, to: pasteboard)
    }

    func save(to url: URL, as format: CursorScreenshotFormat = .png) async -> Bool {
        commitText()
        let saving = edit
        guard let data = await data(of: saving, as: format) else { return false }
        let written = await Task.detached(priority: .userInitiated) { (try? data.write(to: url, options: .atomic)) != nil }.value
        if written { saved = saving }
        return written
    }

    func flattened() async -> CGImage? {
        commitText()
        let picture = picture
        let edit = edit
        let output = self.output()
        return await Task.detached(priority: .userInitiated) {
            CursorScreenshotRender.exported(picture, edit: edit).map { output.apply($0, scale: picture.scale) }
        }.value
    }

    func flattenedOnce(_ use: @MainActor (CGImage?) -> Void) async {
        guard !isFlattening else { return }
        isFlattening = true
        defer { isFlattening = false }
        use(await flattened())
    }

    func encoded() async -> (data: Data, format: CursorScreenshotFormat)? {
        commitText()
        let format = output().format
        return await data(of: edit, as: format).map { ($0, format) }
    }

    func encodedNow() -> (data: Data, format: CursorScreenshotFormat)? {
        commitText()
        let output = self.output()
        return CursorScreenshotRender.exported(picture, edit: edit).flatMap { output.encode($0, scale: picture.scale, density: picture.density * edit.outputScale, as: output.format) }.map { ($0, output.format) }
    }

    private func refit() {
        let area = shownLayout.size
        let room = isCropping ? CGSize(width: Self.cropFitSide(cropView.width), height: Self.cropFitSide(cropView.height)) : viewport
        let shown = CursorScreenshotRender.placed(area, in: room, backing: picture.scale)
        let fit = area.width > 0 ? shown.width / area.width * picture.scale : 1
        if fit > 0, fit != fitZoom { fitZoom = fit }
    }

    private static func cropFitSide(_ side: CGFloat) -> CGFloat {
        let look = CursorScreenshotEditorLook.self
        let share = side * look.cropFitShare
        return share > look.cropFitTrimAbove ? share - look.cropFitTrim : share
    }

    private func toolChanged(from old: CursorScreenshotTool) {
        guard tool != old else { return }
        commitText()
        select(nil)
        if isCropping { closeCrop() }
        if tool == .highlight { startReadingTextLines() }
    }

    private func straightened(_ mark: CursorScreenshotMark) -> CursorScreenshotMark {
        let across = mark.end.x - mark.start.x
        let down = mark.end.y - mark.start.y
        let length = hypot(across, down)
        let slope = tan(CursorScreenshotEditorLook.straightenDegrees * .pi / 180)
        guard length >= CursorScreenshotEditorLook.straightenLengthPoints * picture.scale, abs(down) <= abs(across) * slope,
              mark.path.allSatisfy({ abs(across * ($0.y - mark.start.y) - down * ($0.x - mark.start.x)) / length <= mark.size * picture.scale / 2 }) else { return mark }
        var level = mark
        level.end.y = mark.start.y
        level.path = [level.start, level.end]
        return level
    }

    private func add(_ mark: CursorScreenshotMark) {
        record()
        edit.marks.append(mark)
    }

    private func record() {
        lastChange = nil
        pushUndo(edit)
    }

    private func pushUndo(_ snapshot: CursorScreenshotEdit) {
        undoStack.append(snapshot)
        if undoStack.count > CursorScreenshotEditorLook.undoLevels { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    private func data(of edit: CursorScreenshotEdit, as format: CursorScreenshotFormat) async -> Data? {
        let picture = picture
        let output = self.output()
        return await Task.detached(priority: .userInitiated) {
            CursorScreenshotRender.exported(picture, edit: edit).flatMap { output.encode($0, scale: picture.scale, density: picture.density * edit.outputScale, as: format) }
        }.value
    }

    private func keptInside(_ point: CGPoint, from anchor: CGPoint, in area: CGRect) -> CGPoint {
        let far = inside(point, area.union(CGRect(origin: anchor, size: .zero)))
        let share = min(point.x == anchor.x ? 1 : (far.x - anchor.x) / (point.x - anchor.x), point.y == anchor.y ? 1 : (far.y - anchor.y) / (point.y - anchor.y))
        let along = CGPoint(x: anchor.x + (point.x - anchor.x) * share, y: anchor.y + (point.y - anchor.y) * share)
        return inside(along, area.insetBy(dx: -0.01, dy: -0.01)) == along ? along : inside(point, area)
    }

    private func inside(_ point: CGPoint) -> CGPoint {
        inside(point, crop)
    }

    private func inside(_ point: CGPoint, _ area: CGRect) -> CGPoint {
        CGPoint(x: min(max(point.x, area.minX), area.maxX), y: min(max(point.y, area.minY), area.maxY))
    }
}
