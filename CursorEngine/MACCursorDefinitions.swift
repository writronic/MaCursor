import AppKit

@objc(MACCursorDefinitions)
final class MACCursorDefinitions: NSObject {
    static let maxFrameCount: UInt = 24
    static let maxImportFrameCount: UInt = 128
    static let dumpScale: Float = 16
    static let refreshScaleBumpSmall: Float = 0.1
    static let refreshScaleBumpLarge: Float = 0.3
    static let maxCursorScale: Float = 32
    static let minCursorScale: Float = 0.5
    static let maxDefaultCursorScale: Float = 16
    static let maxPointSize: CGFloat = 128
    @objc static let basePointSize: CGFloat = 32
    static let windowDismissDelay: TimeInterval = 0.05
    static let maxCoreCursorID: Int32 = 43
    static let isTahoeOrLater = ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26
    static let macBookNeoModels: Set<String> = ["Mac17,5"]
    static let hardwareModel: String = {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &bytes, &size, nil, 0) == 0 else { return "" }
        return bytes.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
    }()
    static let isMacBookNeoOnTahoe = isTahoeOrLater && isMacBookNeo(model: hardwareModel)

    static func isMacBookNeo(model: String) -> Bool {
        macBookNeoModels.contains(model)
    }

    static let defaultCursors = [
        "com.apple.coregraphics.Arrow",
        "com.apple.coregraphics.IBeam",
        "com.apple.coregraphics.IBeamXOR",
        "com.apple.coregraphics.Alias",
        "com.apple.coregraphics.Copy",
        "com.apple.coregraphics.Move",
        "com.apple.coregraphics.ArrowCtx",
        "com.apple.coregraphics.Wait",
        "com.apple.coregraphics.Empty",
        "com.apple.coregraphics.ArrowS",
        "com.apple.coregraphics.IBeamS"
    ]

    @objc static let cursorsKey        = "Cursors"
    @objc static let creatorKey        = "Creator"
    @objc static let hiDPIKey          = "HiDPI"
    @objc static let identifierKey     = "Identifier"
    @objc static let themeNameKey      = "ThemeName"
    @objc static let themeVersionKey   = "ThemeVersion"
    @objc static let uuidKey           = "UUID"

    @objc static let frameCountKey       = "FrameCount"
    @objc static let frameDurationKey    = "FrameDuration"
    @objc static let hotSpotXKey         = "HotSpotX"
    @objc static let hotSpotYKey         = "HotSpotY"
    @objc static let pointsWideKey       = "PointsWide"
    @objc static let pointsHighKey       = "PointsHigh"
    @objc static let representationsKey  = "Representations"

    static let hiddenCursorAliases: Set<String> = [
        "com.apple.coregraphics.ArrowS",
        "com.apple.coregraphics.IBeamS",
    ]

    static let redundantCursorAliases: Set<String> = [
        "com.apple.cursor.0",
        "com.apple.cursor.1",
    ]

    static let cursorMap: [String: String] = [
        "com.apple.coregraphics.Arrow":    "Arrow",
        "com.apple.coregraphics.IBeam":    "IBeam",
        "com.apple.coregraphics.IBeamXOR": "IBeamXOR",
        "com.apple.coregraphics.Alias":    "Alias",
        "com.apple.coregraphics.Copy":     "Copy",
        "com.apple.coregraphics.Move":     "Move",
        "com.apple.coregraphics.ArrowCtx": "Ctx Arrow",
        "com.apple.coregraphics.Wait":     "Wait",
        "com.apple.coregraphics.Empty":    "Empty",
        "com.apple.cursor.0":  "Arrow",
        "com.apple.cursor.1":  "IBeam",
        "com.apple.cursor.2":  "Link",
        "com.apple.cursor.3":  "Forbidden",
        "com.apple.cursor.4":  "Busy",
        "com.apple.cursor.5":  "Copy Drag",
        "com.apple.cursor.7":  "Crosshair",
        "com.apple.cursor.8":  "Crosshair 2",
        "com.apple.cursor.9":  "Camera 2",
        "com.apple.cursor.10": "Camera",
        "com.apple.cursor.11": "Closed",
        "com.apple.cursor.12": "Open",
        "com.apple.cursor.13": "Pointing",
        "com.apple.cursor.14": "Counting Up",
        "com.apple.cursor.15": "Counting Down",
        "com.apple.cursor.16": "Counting Up/Down",
        "com.apple.cursor.17": "Resize W",
        "com.apple.cursor.18": "Resize E",
        "com.apple.cursor.19": "Resize W-E",
        "com.apple.cursor.20": "Cell XOR",
        "com.apple.cursor.21": "Resize N",
        "com.apple.cursor.22": "Resize S",
        "com.apple.cursor.23": "Resize N-S",
        "com.apple.cursor.24": "Ctx Menu",
        "com.apple.cursor.25": "Poof",
        "com.apple.cursor.26": "IBeam H.",
        "com.apple.cursor.27": "Window E",
        "com.apple.cursor.28": "Window E-W",
        "com.apple.cursor.29": "Window NE",
        "com.apple.cursor.30": "Window NE-SW",
        "com.apple.cursor.31": "Window N",
        "com.apple.cursor.32": "Window N-S",
        "com.apple.cursor.33": "Window NW",
        "com.apple.cursor.34": "Window NW-SE",
        "com.apple.cursor.35": "Window SE",
        "com.apple.cursor.36": "Window S",
        "com.apple.cursor.37": "Window SW",
        "com.apple.cursor.38": "Window W",
        "com.apple.cursor.39": "Resize Square",
        "com.apple.cursor.40": "Help",
        "com.apple.cursor.41": "Cell",
        "com.apple.cursor.42": "Zoom In",
        "com.apple.cursor.43": "Zoom Out",
        "com.apple.coregraphics.ArrowS": "Arrow (Tahoe)",
        "com.apple.coregraphics.IBeamS": "IBeam (Tahoe)",
    ]

    static func tahoeAliases(for identifier: String) -> [String] {
        let map: [String: [String]] = [
        "com.apple.coregraphics.Arrow":  ["com.apple.coregraphics.ArrowS"],
        "com.apple.coregraphics.IBeam":  ["com.apple.coregraphics.IBeamS"],
        "com.apple.coregraphics.ArrowS": ["com.apple.coregraphics.Arrow"],
        "com.apple.coregraphics.IBeamS": ["com.apple.coregraphics.IBeam"],
        ]
        return map[identifier] ?? []
    }

    private static let reverseMap: [String: String] = {
        var map = [String: String]()
        for (key, value) in cursorMap {
            map[value] = key
        }
        return map
    }()

    @objc static func nameForIdentifier(_ identifier: String) -> String {
        return cursorMap[identifier] ?? "Unknown"
    }

    static func isKnownIdentifier(_ identifier: String) -> Bool {
        return cursorMap[identifier] != nil
    }

    static func identifierForName(_ name: String) -> String? {
        return reverseMap[name]
    }

    static let browserAliasMap: [String: [String]] = [
        "com.apple.coregraphics.Arrow":    [ "com.apple.cursor.0" ],
        "com.apple.cursor.0":              [ "com.apple.coregraphics.Arrow" ],
        "com.apple.coregraphics.IBeam":    [ "com.apple.cursor.1" ],
        "com.apple.cursor.1":              [ "com.apple.coregraphics.IBeam" ],
        "com.apple.coregraphics.Alias":    [ "com.apple.cursor.2" ],
        "com.apple.cursor.2":              [ "com.apple.coregraphics.Alias" ],
        "com.apple.cursor.3":              [ "com.apple.coregraphics.NotAllowed" ],
        "com.apple.coregraphics.Wait":     [ "com.apple.cursor.4" ],
        "com.apple.cursor.4":              [ "com.apple.coregraphics.Wait" ],
        "com.apple.coregraphics.Copy":     [ "com.apple.cursor.5" ],
        "com.apple.cursor.5":              [ "com.apple.coregraphics.Copy" ],
        "com.apple.cursor.7":              [ "com.apple.cursor.20" ],
        "com.apple.cursor.8":              [ "com.apple.cursor.20" ],
        "com.apple.cursor.20":             [ "com.apple.cursor.7" ],
        "com.apple.cursor.9":              [ "com.apple.coregraphics.ScreenshotWindow" ],
        "com.apple.cursor.10":             [ "com.apple.coregraphics.ScreenshotSelection" ],
        "com.apple.cursor.11":             [ "com.apple.coregraphics.ClosedHand" ],
        "com.apple.cursor.12":             [ "com.apple.coregraphics.OpenHand" ],
        "com.apple.cursor.13":             [ "com.apple.coregraphics.PointingHand" ],
        "com.apple.cursor.14":             [ "com.apple.coregraphics.CountingUpHand" ],
        "com.apple.cursor.15":             [ "com.apple.coregraphics.CountingDownHand" ],
        "com.apple.cursor.16":             [ "com.apple.coregraphics.CountingUpAndDownHand" ],
        "com.apple.cursor.17":             [ "com.apple.coregraphics.ResizeLeft" ],
        "com.apple.cursor.18":             [ "com.apple.coregraphics.ResizeRight" ],
        "com.apple.cursor.19":             [ "com.apple.coregraphics.ResizeLeftRight" ],
        "com.apple.cursor.21":             [ "com.apple.coregraphics.ResizeUp" ],
        "com.apple.cursor.22":             [ "com.apple.coregraphics.ResizeDown" ],
        "com.apple.cursor.23":             [ "com.apple.coregraphics.ResizeUpDown" ],
        "com.apple.cursor.24":             [ "com.apple.coregraphics.ArrowCtx" ],
        "com.apple.coregraphics.ArrowCtx": [ "com.apple.cursor.24" ],
        "com.apple.cursor.25":             [ "com.apple.coregraphics.Poof" ],
        "com.apple.cursor.26":             [ "com.apple.coregraphics.IBeamH" ],
        "com.apple.cursor.27":             [ "com.apple.coregraphics.WindowResizeEast" ],
        "com.apple.cursor.28":             [ "com.apple.coregraphics.WindowResizeEastWest" ],
        "com.apple.cursor.29":             [ "com.apple.coregraphics.WindowResizeNortheast" ],
        "com.apple.cursor.30":             [ "com.apple.coregraphics.WindowResizeNortheastSouthwest" ],
        "com.apple.cursor.31":             [ "com.apple.coregraphics.WindowResizeNorth" ],
        "com.apple.cursor.32":             [ "com.apple.coregraphics.WindowResizeNorthSouth" ],
        "com.apple.cursor.33":             [ "com.apple.coregraphics.WindowResizeNorthwest" ],
        "com.apple.cursor.34":             [ "com.apple.coregraphics.WindowResizeNorthwestSoutheast" ],
        "com.apple.cursor.35":             [ "com.apple.coregraphics.WindowResizeSoutheast" ],
        "com.apple.cursor.36":             [ "com.apple.coregraphics.WindowResizeSouth" ],
        "com.apple.cursor.37":             [ "com.apple.coregraphics.WindowResizeSouthwest" ],
        "com.apple.cursor.38":             [ "com.apple.coregraphics.WindowResizeWest" ],
        "com.apple.coregraphics.Move":     [ "com.apple.cursor.39" ],
        "com.apple.cursor.39":             [ "com.apple.coregraphics.Move" ],
        "com.apple.cursor.40":             [ "com.apple.coregraphics.Help" ],
        "com.apple.cursor.41":             [ "com.apple.coregraphics.Cell" ],
        "com.apple.cursor.42":             [ "com.apple.coregraphics.ZoomIn" ],
        "com.apple.cursor.43":             [ "com.apple.coregraphics.ZoomOut" ],
    ]

    @discardableResult
    static func resolvePreferredScale(_ preference: NSNumber?, _ output: UnsafeMutablePointer<Float>?) -> Bool {
        guard let value = preference?.floatValue, !value.isNaN, value > 0, value != 1 else { return false }
        output?.pointee = value < 1 || value > maxDefaultCursorScale ? 1 : value
        return true
    }
}

extension NSBitmapImageRep {
    @objc var retaggedSRGBSpace: NSBitmapImageRep {
        let targetSpace: NSColorSpace = colorSpace.numberOfColorComponents == 1 ? .genericGamma22Gray : .sRGB
        return retagging(with: targetSpace) ?? self
    }

    @objc var ensuredSRGBSpace: NSBitmapImageRep {
        let targetSpace: NSColorSpace = colorSpace.numberOfColorComponents == 1 ? .genericGamma22Gray : .sRGB
        return converting(to: targetSpace, renderingIntent: .default) ?? self
    }
}
