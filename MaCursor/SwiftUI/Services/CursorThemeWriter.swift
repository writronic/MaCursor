import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct ThemeBuildResult: Sendable {
    public let cursorFileURL: URL
    public let previewURL: URL?
    public let warnings: [ImportWarning]
    public let generated2x: [String]
}

public enum CursorThemeWriter {
    public static let pointSize = CursorGeometry.basePointSize
    public static let maxFrames = 24
    public static let uuidNamespace = UUID(uuidString: "7A0F5A46-2A44-4F8E-8D1B-3C9A1F6E2B47")!

    public static func sanitizeIdentifier(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "/", with: "")
            .replacingOccurrences(of: ":", with: "")
    }

    @discardableResult
    public static func build(cursors: [String: AnimatedCursor],
                             themeName: String,
                             creator: String = "",
                             identity: ThemeIdentity? = nil,
                             outputDirectory: URL,
                             writePreview: Bool = false,
                             fillMissingScales: Bool = true,
                             hiDPI: Bool = true,
                             upscaleModelURL: URL? = nil) throws -> ThemeBuildResult {
        guard !cursors.isEmpty else { throw ThemeBuildError.emptyTheme }
        let identifier = identity?.identifier ?? sanitizeIdentifier(themeName)
        guard !identifier.isEmpty else { throw ThemeBuildError.invalidThemeName(themeName) }
        let network = upscaleModelURL.flatMap { try? PixelUpscaler.Network(contentsOf: $0) }

        var warnings: [ImportWarning] = []
        var generated2x: [String] = []
        var cursorsDict: [String: [String: Any]] = [:]
        var previewImages: [(identifier: String, image: CGImage)] = []

        for (slotIdentifier, animated) in cursors.sorted(by: { $0.key < $1.key }) {
            guard !animated.frames.isEmpty else { continue }
            let unified = try unify(animated, identifier: slotIdentifier,
                                    warnings: &warnings, fillMissingScales: fillMissingScales, network: network)
            if unified.synthesized2x { generated2x.append(slotIdentifier) }
            cursorsDict[slotIdentifier] = [
                "FrameCount": unified.frameCount,
                "FrameDuration": unified.frameDurationSeconds,
                "HotSpotX": unified.hotspot.x,
                "HotSpotY": unified.hotspot.y,
                "PointsWide": Double(pointSize),
                "PointsHigh": Double(pointSize),
                "Representations": unified.sheetPNGs,
            ]
            if !Slots.intentionallyExcludedFromCursorMap.contains(slotIdentifier) {
                previewImages.append((slotIdentifier, unified.previewImage))
            }
        }
        guard !cursorsDict.isEmpty else { throw ThemeBuildError.emptyTheme }

        let uuid = identity?.uuid
            ?? UUID(v5Namespace: uuidNamespace, name: identifier).uuidString
        let plist: [String: Any] = [
            "ThemeName": themeName,
            "ThemeVersion": identity?.version ?? Double(1.0),
            "Creator": creator,
            "HiDPI": hiDPI,
            "Identifier": identifier,
            "UUID": uuid,
            "Cursors": cursorsDict,
        ]

        let fm = FileManager.default
        try fm.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let fileURL = outputDirectory.appendingPathComponent("\(identifier).cursor")
        let data = try PropertyListSerialization.data(fromPropertyList: plist,
                                                      format: .xml, options: 0)
        try data.write(to: fileURL, options: .atomic)

        let readBack = try Data(contentsOf: fileURL)
        let issues = validateThemePlist(readBack, expectedIdentifier: identifier,
                                        expectedUUID: identity?.uuid)
        guard issues.isEmpty else {
            try? fm.removeItem(at: fileURL)
            throw ThemeBuildError.selfCheckFailed(issues)
        }

        var previewURL: URL?
        if writePreview {
            previewURL = outputDirectory.appendingPathComponent("\(identifier)-preview.png")
            try writePreviewGrid(previewImages, to: previewURL!)
        }
        return ThemeBuildResult(cursorFileURL: fileURL, previewURL: previewURL,
                                warnings: warnings, generated2x: generated2x)
    }

    private struct UnifiedCursor {
        var frameCount: Int
        var frameDurationSeconds: Double
        var hotspot: (x: Double, y: Double)
        var sheetPNGs: [Data]
        var previewImage: CGImage
        var synthesized2x: Bool
    }

    private static func unify(_ animated: AnimatedCursor, identifier: String,
                              warnings: inout [ImportWarning],
                              fillMissingScales: Bool, network: PixelUpscaler.Network?) throws -> UnifiedCursor {
        let delays = animated.frames.map(\.delayMS)
        let total = delays.reduce(0, +)

        var indexList: [Int]
        var unifiedDelayMS: Int
        if animated.frames.count == 1 || total <= 0 {
            indexList = [0]
            unifiedDelayMS = 0
        } else if let restIndex = restFrameIndex(delays: delays, total: total) {
            indexList = [restIndex]
            unifiedDelayMS = 0
            warnings.append(.init(.animationCollapsedToRestFrame(identifier: identifier)))
        } else {
            let g = delays.reduce(0, gcd)
            let quarterMean = total / delays.count / 4
            unifiedDelayMS = max(1, max(g, quarterMean))
            let count = max(1, total / unifiedDelayMS)
            var cumulative: [Int] = []
            var running = 0
            for delay in delays {
                running += delay
                cumulative.append(running)
            }
            indexList = []
            var current = 0
            for tick in 0 ..< count {
                let timeIn = tick * unifiedDelayMS
                while current < delays.count - 1, timeIn >= cumulative[current] {
                    current += 1
                }
                indexList.append(current)
            }
        }

        let frameDurationSeconds: Double
        if indexList.count > maxFrames {
            let n = indexList.count
            warnings.append(.init(.frameResample(identifier: identifier,
                                                 from: n, to: maxFrames)))
            indexList = (0 ..< maxFrames).map { indexList[$0 * n / maxFrames] }
            frameDurationSeconds = Double(unifiedDelayMS * n) / Double(maxFrames) / 1000
        } else if indexList.count == 1 {
            frameDurationSeconds = 1.0
        } else {
            frameDurationSeconds = Double(unifiedDelayMS) / 1000
        }

        let standardSizes = [PixelSize(square: pointSize), PixelSize(square: pointSize * 2),
                             PixelSize(square: pointSize * 5), PixelSize(square: pointSize * 10)]
        var emitSizes = standardSizes
        for sourceIndex in Set(indexList) {
            let cursor = animated.frames[sourceIndex].cursor
            guard !cursor.isEmpty else {
                throw ThemeBuildError.compositionFailed("\(identifier): empty frame \(sourceIndex)")
            }
            if fillMissingScales {
                emitSizes = emitSizes.filter { size in
                    cursor.images.keys.contains {
                        $0.width >= size.width && $0.height >= size.height
                    }
                }
            } else {
                emitSizes = emitSizes.filter { cursor[$0] != nil }
            }
        }
        if emitSizes.isEmpty { emitSizes = [standardSizes[0]] }

        var normalized: [Int: Cursor] = [:]
        var synthesized2x = false
        for sourceIndex in Set(indexList) {
            var cursor = animated.frames[sourceIndex].cursor
            if emitSizes.contains(standardSizes[1]), cursor[standardSizes[1]] == nil {
                synthesized2x = true
            }
            try cursor.synthesizeSizes(emitSizes)
            normalized[sourceIndex] = cursor
        }

        guard let frame0 = normalized[indexList[0]], let smallestSize = emitSizes.first,
              let base = frame0[smallestSize] else {
            throw ThemeBuildError.compositionFailed("\(identifier): missing normalized sizes")
        }
        let hotspotScale = Double(pointSize) / Double(smallestSize.width)
        let hotspot = (x: Double(base.hotspot.x) * hotspotScale,
                       y: Double(base.hotspot.y) * hotspotScale)
        let previewImage = (frame0[standardSizes[1]] ?? base).image

        var sheets: [Data] = []
        for (scaleIndex, size) in emitSizes.enumerated() {
            let px = size.width
            let frameCount = indexList.count
            let ctx = try ImageScaler.rgbaContext(width: px, height: px * frameCount)
            for (outFrame, sourceIndex) in indexList.enumerated() {
                guard let image = normalized[sourceIndex]?[size]?.image else {
                    throw ThemeBuildError.compositionFailed("\(identifier): frame \(outFrame) missing \(size)")
                }
                let y = (frameCount - 1 - outFrame) * px
                ctx.draw(image, in: CGRect(x: 0, y: y, width: px, height: px))
            }
            guard let sheet = ctx.makeImage() else {
                throw ThemeBuildError.compositionFailed("\(identifier): sheet \(scaleIndex) composition")
            }
            sheets.append(try encodePNG(sheet))
            if emitSizes == [standardSizes[0]], let network,
               let rgba = try? ImageScaler.straightRGBA(of: sheet),
               let doubled = try? PixelUpscaler.doubled(PixelUpscaler.Strip(rgba: rgba, width: px, height: px * frameCount,
                                                                             frameCount: frameCount), network: network),
               let image = try? ImageScaler.makeImage(rgba: doubled.rgba, width: doubled.width, height: doubled.height) {
                sheets.append(try encodePNG(image))
            }
        }

        return UnifiedCursor(frameCount: indexList.count,
                             frameDurationSeconds: frameDurationSeconds,
                             hotspot: hotspot,
                             sheetPNGs: sheets,
                             previewImage: previewImage,
                             synthesized2x: synthesized2x)
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int {
        var (a, b) = (abs(a), abs(b))
        while b != 0 { (a, b) = (b, a % b) }
        return a
    }

    static let restFrameShare = 0.9
    static let restFrameMinHoldMS = 10_000

    static func restFrameIndex(delays: [Int], total: Int) -> Int? {
        guard delays.count > 1, total > 0,
              let maxDelay = delays.max(), maxDelay >= restFrameMinHoldMS,
              Double(maxDelay) >= Double(total) * restFrameShare else { return nil }
        return delays.firstIndex(of: maxDelay)
    }

    private static func encodePNG(_ image: CGImage) throws -> Data {
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            out as CFMutableData, UTType.png.identifier as CFString, 1, nil) else {
            throw ThemeBuildError.compositionFailed("cannot create PNG destination")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ThemeBuildError.compositionFailed("PNG encoding failed")
        }
        return out as Data
    }

    static func validateThemePlist(_ data: Data, expectedIdentifier: String,
                                   expectedUUID: String? = nil) -> [String] {
        var issues: [String] = []
        let root: Any
        do {
            root = try PropertyListSerialization.propertyList(from: data, format: nil)
        } catch {
            return ["not a property list: \(error)"]
        }
        guard let dict = root as? [String: Any] else { return ["root is not a dictionary"] }

        if dict["ThemeName"] as? String == nil { issues.append("ThemeName missing/not a string") }
        if dict["ThemeVersion"] as? NSNumber == nil { issues.append("ThemeVersion missing/not a number") }
        if dict["Creator"] as? String == nil { issues.append("Creator missing/not a string") }
        if dict["HiDPI"] as? NSNumber == nil { issues.append("HiDPI missing/not a bool") }

        if let identifier = dict["Identifier"] as? String {
            if identifier != expectedIdentifier {
                issues.append("Identifier '\(identifier)' != expected '\(expectedIdentifier)'")
            }
        } else {
            issues.append("Identifier missing/not a string")
        }
        if let uuid = dict["UUID"] as? String {
            if uuid.isEmpty { issues.append("UUID empty") }
            if let expectedUUID {
                if uuid != expectedUUID { issues.append("UUID '\(uuid)' != expected") }
            } else {
                if uuid != uuid.uppercased() { issues.append("UUID not uppercase") }
                if UUID(uuidString: uuid) == nil { issues.append("UUID unparseable") }
            }
        } else {
            issues.append("UUID missing/not a string")
        }

        guard let cursorsDict = dict["Cursors"] as? [String: Any], !cursorsDict.isEmpty else {
            issues.append("Cursors missing/empty")
            return issues
        }
        for (identifier, value) in cursorsDict {
            guard let cursor = value as? [String: Any] else {
                issues.append("\(identifier): cursor entry is not a dictionary")
                continue
            }
            for key in ["FrameCount", "FrameDuration", "HotSpotX", "HotSpotY",
                        "PointsWide", "PointsHigh"] where cursor[key] as? NSNumber == nil {
                issues.append("\(identifier): \(key) missing/not a number")
            }
            let frameCount = (cursor["FrameCount"] as? NSNumber)?.intValue ?? 0
            if frameCount < 1 || frameCount > maxFrames {
                issues.append("\(identifier): FrameCount \(frameCount) outside 1...\(maxFrames)")
            }
            guard let reps = cursor["Representations"] as? [Data], !reps.isEmpty else {
                issues.append("\(identifier): Representations missing or empty")
                continue
            }
            var repWidths: [Int] = []
            for (index, rep) in reps.enumerated() {
                guard let source = CGImageSourceCreateWithData(rep as CFData, nil),
                      let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                        as? [CFString: Any],
                      let width = props[kCGImagePropertyPixelWidth] as? Int,
                      let height = props[kCGImagePropertyPixelHeight] as? Int else {
                    issues.append("\(identifier): rep \(index) undecodable")
                    continue
                }
                repWidths.append(width)
                if height != width * frameCount {
                    issues.append("\(identifier): rep \(index) height \(height) != width*FrameCount")
                }
            }
            let allowedWidths = Set([pointSize, pointSize * 2, pointSize * 5, pointSize * 10])
            if Set(repWidths).count != repWidths.count {
                issues.append("\(identifier): duplicate rep widths \(repWidths.sorted())")
            }
            if !Set(repWidths).isSubset(of: allowedWidths) {
                issues.append("\(identifier): rep widths \(repWidths.sorted()) outside {32, 64, 160, 320}")
            }
        }
        return issues
    }

    private static func writePreviewGrid(
        _ images: [(identifier: String, image: CGImage)], to url: URL
    ) throws {
        guard !images.isEmpty else { return }
        let slotOrder = Dictionary(uniqueKeysWithValues:
            Slots.all.enumerated().map { ($1.identifier, $0) })
        let ordered = images.sorted {
            (slotOrder[$0.identifier] ?? Int.max, $0.identifier)
                < (slotOrder[$1.identifier] ?? Int.max, $1.identifier)
        }
        let cell = 64
        let columns = Int(Double(ordered.count).squareRoot().rounded(.up))
        let rows = (ordered.count + columns - 1) / columns
        let ctx = try ImageScaler.rgbaContext(width: columns * cell, height: rows * cell)
        for (index, entry) in ordered.enumerated() {
            let column = index % columns
            let row = index / columns
            let rect = CGRect(x: column * cell, y: (rows - 1 - row) * cell,
                              width: cell, height: cell)
            ctx.draw(entry.image, in: rect)
        }
        guard let image = ctx.makeImage() else {
            throw ThemeBuildError.compositionFailed("preview composition failed")
        }
        try encodePNG(image).write(to: url, options: .atomic)
    }
}
