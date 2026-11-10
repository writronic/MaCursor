import Foundation

enum CursorScreenshotBackdropFill: Codable, Hashable, Sendable {
    case none
    case color(String, CGFloat)
    case gradient(Int)
    case wallpaper(String)
    case desktop
    case blurredDesktop
    case blurredPicture
    case blurredPictureDark

    static let gradientCount = 12
    static let transparent = CursorScreenshotBackdropFill.color("000000", 0)

    var isOpaque: Bool {
        switch self {
        case .none: return false
        case .color(_, let alpha): return alpha >= 1
        default: return true
        }
    }

    var checked: CursorScreenshotBackdropFill {
        switch self {
        case .color(let hex, let alpha):
            guard hex.count == 6, hex.allSatisfy(\.isHexDigit), alpha.isFinite else { return .none }
            return .color(hex, min(max(alpha, 0), 1))
        case .gradient(let index):
            return (0..<Self.gradientCount).contains(index) ? self : .none
        case .wallpaper(let id):
            return UUID(uuidString: id) == nil ? .none : self
        default:
            return self
        }
    }
}

enum CursorScreenshotBackdropRatio: String, Codable, CaseIterable, Sendable {
    case auto = "Auto"
    case square = "1:1"
    case fiveFour = "5:4"
    case fourThree = "4:3"
    case threeTwo = "3:2"
    case sixteenNine = "16:9"
    case fourFive = "4:5"
    case threeFour = "3:4"
    case nineSixteen = "9:16"

    var shape: CGFloat? {
        let parts = rawValue.split(separator: ":").compactMap { Double($0) }
        return parts.count == 2 ? CGFloat(parts[0] / parts[1]) : nil
    }
}

struct CursorScreenshotBackgroundStyle: Codable, Equatable, Sendable {
    static let paddingRange: ClosedRange<CGFloat> = 0...300
    static let cornersRange: ClosedRange<CGFloat> = 0...60
    static let shadowRange: ClosedRange<CGFloat> = 0...100
    static let insetRange: ClosedRange<CGFloat> = 0...100
    static let centre = 4

    var fill = CursorScreenshotBackdropFill.none
    var padding: CGFloat = 0
    var corners: CGFloat = 0
    var shadow: CGFloat = 0
    var inset: CGFloat = 0
    var alignment = Self.centre
    var ratio = CursorScreenshotBackdropRatio.auto
    var autoBalance = false

    var checked: CursorScreenshotBackgroundStyle {
        let kept = { (value: CGFloat, range: ClosedRange<CGFloat>) in value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : range.lowerBound }
        var style = self
        style.fill = fill.checked
        style.padding = kept(padding, Self.paddingRange)
        style.corners = kept(corners, Self.cornersRange)
        style.shadow = kept(shadow, Self.shadowRange)
        style.inset = kept(inset, Self.insetRange)
        if !(0..<9).contains(alignment) { style.alignment = Self.centre }
        return style
    }
}

struct CursorScreenshotPreset: Codable, Equatable, Sendable {
    var id: String
    var name: String
    var style: CursorScreenshotBackgroundStyle

    static let first = [
        CursorScreenshotPreset(id: "clean", name: "Clean", style: CursorScreenshotBackgroundStyle(fill: .color("EBEBEB", 1), padding: 40, corners: 12, shadow: 20)),
        CursorScreenshotPreset(id: "soft", name: "Soft", style: CursorScreenshotBackgroundStyle(fill: .gradient(8), padding: 83, corners: 28, shadow: 40)),
        CursorScreenshotPreset(id: "wide", name: "Wide", style: CursorScreenshotBackgroundStyle(fill: .gradient(0), padding: 60, corners: 28, shadow: 60, ratio: .sixteenNine))
    ]
}

struct CursorScreenshotBackgroundLibrary: Codable, Equatable, Sendable {
    static let wallpaperLimit = 4

    var isOpen = false
    var presets = CursorScreenshotPreset.first
    var wallpapers: [String] = []
    var defaultPreset: String?
    var previous: CursorScreenshotBackgroundStyle?

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isOpen = (try? container.decode(Bool.self, forKey: .isOpen)) ?? false
        if let saved = try? container.decode([CursorScreenshotPreset].self, forKey: .presets) {
            presets = saved.map { CursorScreenshotPreset(id: $0.id, name: $0.name, style: $0.style.checked) }
        }
        wallpapers = ((try? container.decode([String].self, forKey: .wallpapers)) ?? []).filter { UUID(uuidString: $0) != nil }
        wallpapers = Array(wallpapers.prefix(Self.wallpaperLimit))
        defaultPreset = try? container.decode(String.self, forKey: .defaultPreset)
        previous = (try? container.decode(CursorScreenshotBackgroundStyle.self, forKey: .previous))?.checked
    }
}
