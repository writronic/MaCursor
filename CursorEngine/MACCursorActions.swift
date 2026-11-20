import AppKit

struct MACCursorImageOperations {
    var makeContext: (Int, Int) -> CGContext? = { MACCursorShadow.makeContext(width: $0, height: $1) }
    var crop: (CGImage, CGRect) -> CGImage? = { $0.cropping(to: $1) }

    struct Layout {
        let scale: Int
        let width: Int
        let frameHeight: Int
        let isSheet: Bool
    }

    private static func withinTolerance(_ actual: Int, _ nominal: CGFloat, _ scale: Int) -> Bool {
        abs(CGFloat(actual) - nominal * CGFloat(scale)) <= 0.5 * CGFloat(scale)
    }

    static func layout(of image: CGImage, frameCount: Int, pointSize: CGSize) -> Layout? {
        let rounded = (CGFloat(image.width) / pointSize.width).rounded()
        guard rounded >= 1, rounded <= 16 else { return nil }
        let scale = Int(rounded)
        guard withinTolerance(image.width, pointSize.width, scale) else { return nil }
        if frameCount > 1, image.height % frameCount == 0 {
            let height = image.height / frameCount
            if height > 0, withinTolerance(height, pointSize.height, scale) {
                return Layout(scale: scale, width: image.width, frameHeight: height, isSheet: true)
            }
        }
        guard withinTolerance(image.height, pointSize.height, scale) else { return nil }
        return Layout(scale: scale, width: image.width, frameHeight: image.height, isSheet: false)
    }
}

@MainActor
struct MACCursorActions {
    struct ApplyContext {
        let identifiers: Set<String>
        let shadow: Bool
        let leftHanded: Bool
        let renderScale: Float
        let padCursorCanvas: Bool
    }

    struct Registration {
        let identifier: String
        let frameCount: UInt
        let frameDuration: CGFloat
        let hotSpot: CGPoint
        let size: CGSize
        let images: [CGImage]
    }

    struct Operations {
        let register: (Registration) -> Bool
        let activate: (String) -> Void
        let unregisterAll: () -> Void
        let selectCore: (Int32) -> Void
        let selectArrow: () -> Void
        let dockOverride: (Bool) -> Void
        let getScale: () -> Float?
        let setScale: (Float) -> Bool
        let isTahoe: () -> Bool
        let tahoeAliases: (String) -> [String]
        let browserAliases: (String) -> [String]
        let readFile: (String) -> Data?
        let defaultPath: () -> String
        let readPreference: (String) -> Any?
        let writePreference: (Any?, String) -> Void

        static var live: Operations {
            Operations(register: { cursor in
                var name = Array(cursor.identifier.utf8CString)
                var seed: Int32 = 0
                return name.withUnsafeMutableBufferPointer {
                    CGSRegisterCursorWithImages(CGSMainConnectionID(), $0.baseAddress, true, true,
                                                cursor.size, cursor.hotSpot, cursor.frameCount,
                                                cursor.frameDuration, cursor.images as CFArray, &seed) == .success
                }
            }, activate: { identifier in
                var name = Array(identifier.utf8CString)
                var seed: Int32 = 0
                name.withUnsafeMutableBufferPointer {
                    _ = CGSSetRegisteredCursor(CGSMainConnectionID(), $0.baseAddress, &seed)
                }
            }, unregisterAll: { _ = CoreCursorUnregisterAll(CGSMainConnectionID()) },
            selectCore: { _ = CoreCursorSet(CGSMainConnectionID(), $0) },
            selectArrow: { _ = CGSSetSystemDefinedCursor(CGSMainConnectionID(), 0) },
            dockOverride: { CGSSetDockCursorOverride(CGSMainConnectionID(), $0) },
            getScale: {
                var scale: Float = 1
                return CGSGetCursorScale(CGSMainConnectionID(), &scale) == .success ? scale : nil
            }, setScale: { CGSSetCursorScale(CGSMainConnectionID(), $0) == .success },
            isTahoe: { MACCursorDefinitions.isTahoeOrLater },
            tahoeAliases: { MACCursorDefinitions.isTahoeOrLater ? MACCursorDefinitions.tahoeAliases(for: $0) : [] },
            browserAliases: { MACCursorDefinitions.browserAliasMap[$0] ?? [] },
            readFile: { try? Data(contentsOf: URL(fileURLWithPath: $0)) },
            defaultPath: { MACCursorCapture.systemDefaultPath },
            readPreference: { MACPreferences.value(forKey: $0) },
            writePreference: { MACPreferences.set($0, forKey: $1) })
        }
    }

    static let shared = MACCursorActions(operations: .live)
    let operations: Operations
    var imageOperations = MACCursorImageOperations()

    private func context(identifiers: Set<String>, shadow: Bool) -> ApplyContext {
        let padCursorCanvas = (operations.readPreference(MACPreferences.padCursorCanvasKey) as? NSNumber)?.boolValue ?? false
        return ApplyContext(identifiers: identifiers, shadow: shadow,
                            leftHanded: (operations.readPreference(MACPreferences.handednessKey) as? NSNumber)?.boolValue ?? false,
                            renderScale: (operations.readPreference(MACPreferences.cursorScaleKey) as? NSNumber)?.floatValue ?? 0,
                            padCursorCanvas: operations.isTahoe() && padCursorCanvas)
    }

    private func register(_ cursor: Registration, context: ApplyContext) -> Bool {
        guard cursor.frameCount >= 1, cursor.frameCount <= MACCursorDefinitions.maxFrameCount,
              operations.register(cursor) else { return false }
        operations.activate(cursor.identifier)
        for alias in operations.tahoeAliases(cursor.identifier) + operations.browserAliases(cursor.identifier)
            where !context.identifiers.contains(alias) {
            let aliased = Registration(identifier: alias, frameCount: cursor.frameCount,
                                       frameDuration: cursor.frameDuration, hotSpot: cursor.hotSpot,
                                       size: cursor.size, images: cursor.images)
            if operations.register(aliased) { operations.activate(alias) }
        }
        return true
    }

    func applyCursor(_ cursor: [String: Any], identifier: String, restore: Bool, context: ApplyContext) -> Bool {
        var hotSpot = CGPoint(x: (cursor[MACCursorDefinitions.hotSpotXKey] as? NSNumber)?.doubleValue ?? 0,
                              y: (cursor[MACCursorDefinitions.hotSpotYKey] as? NSNumber)?.doubleValue ?? 0)
        var size = CGSize(width: (cursor[MACCursorDefinitions.pointsWideKey] as? NSNumber)?.doubleValue ?? 0,
                          height: (cursor[MACCursorDefinitions.pointsHighKey] as? NSNumber)?.doubleValue ?? 0)
        let excluded = ["com.apple.cursor.29", "com.apple.cursor.33", "com.apple.cursor.35",
                        "com.apple.cursor.37", "com.apple.cursor.30", "com.apple.cursor.34"]
        let flip = context.leftHanded && !restore && !excluded.contains(identifier)
        if flip { hotSpot.x = size.width - hotSpot.x - 1 }
        let declaredSize = size
        if size.width > MACCursorDefinitions.maxPointSize || size.height > MACCursorDefinitions.maxPointSize {
            let excess = max(size.width, size.height) / MACCursorDefinitions.maxPointSize
            size.width /= excess
            size.height /= excess
            hotSpot.x /= excess
            hotSpot.y /= excess
        }
        if context.renderScale >= MACCursorDefinitions.minCursorScale, context.renderScale < 1 {
            size.width *= CGFloat(context.renderScale)
            size.height *= CGFloat(context.renderScale)
            hotSpot.x *= CGFloat(context.renderScale)
            hotSpot.y *= CGFloat(context.renderScale)
        }
        var images: [CGImage] = []
        for object in cursor[MACCursorDefinitions.representationsKey] as? [Any] ?? [] {
            let source: CGImage
            let rep: NSBitmapImageRep
            if CFGetTypeID(object as CFTypeRef) == CGImage.typeID {
                source = object as! CGImage
                rep = NSBitmapImageRep(cgImage: source).retaggedSRGBSpace
            } else if let data = object as? Data, let bitmap = NSBitmapImageRep(data: data) {
                rep = bitmap.retaggedSRGBSpace
                guard let image = rep.cgImage else { return false }
                source = image
            } else {
                return false
            }
            if flip {
                guard let context = imageOperations.makeContext(rep.pixelsWide, rep.pixelsHigh),
                      let image = rep.cgImage else { return false }
                context.translateBy(x: CGFloat(rep.pixelsWide), y: 0)
                context.scaleBy(x: -1, y: 1)
                context.draw(image, in: CGRect(x: 0, y: 0, width: rep.pixelsWide, height: rep.pixelsHigh))
                guard let flipped = context.makeImage() else { return false }
                images.append(flipped)
            } else {
                images.append(source)
            }
        }
        var frameCount = (cursor[MACCursorDefinitions.frameCountKey] as? NSNumber)?.uintValue ?? 0
        var frameDuration = CGFloat((cursor[MACCursorDefinitions.frameDurationKey] as? NSNumber)?.doubleValue ?? 0)
        images = Self.prepareImages(images, size: size, frameCount: &frameCount,
                                    frameDuration: &frameDuration, operations: imageOperations)
        let renderScale = declaredSize.width > 0 ? size.width / declaredSize.width : 1
        if context.shadow, let shadowed = MACCursorShadow.shadowedImages(images, frameCount: frameCount, pointSize: declaredSize) {
            MACCursorShadow.adjustRegistration(size: &size, hotSpot: &hotSpot, margins: shadowed.margins, scale: renderScale)
            images = shadowed.images
        }
        if context.padCursorCanvas, !restore, renderScale > 0 {
            let pointSize = CGSize(width: size.width / renderScale, height: size.height / renderScale)
            if let padded = Self.paddedCursorCanvas(images, frameCount: frameCount, pointSize: pointSize,
                                                   operations: imageOperations) {
                let paddedSize = CGSize(width: padded.size.width * renderScale, height: padded.size.height * renderScale)
                let registration = Registration(identifier: identifier, frameCount: frameCount,
                                                frameDuration: frameDuration, hotSpot: hotSpot,
                                                size: paddedSize, images: padded.images)
                if register(registration, context: context) { return true }
            }
        }
        return register(Registration(identifier: identifier, frameCount: frameCount,
                                      frameDuration: frameDuration, hotSpot: hotSpot, size: size, images: images), context: context)
    }

    nonisolated static func paddedCursorCanvas(_ images: [CGImage], frameCount: UInt, pointSize: CGSize,
                                              operations: MACCursorImageOperations = MACCursorImageOperations())
        -> (size: CGSize, images: [CGImage])? {
        let minimum: CGFloat = 96
        guard pointSize.width.isFinite, pointSize.height.isFinite,
              pointSize.width > 0, pointSize.height > 0,
              pointSize.width < minimum || pointSize.height < minimum,
              frameCount >= 1, frameCount <= MACCursorDefinitions.maxFrameCount else { return nil }

        let size = CGSize(width: max(minimum, pointSize.width), height: max(minimum, pointSize.height))
        let count = Int(frameCount)
        let layouts = images.compactMap { MACCursorImageOperations.layout(of: $0, frameCount: count, pointSize: pointSize) }
        guard layouts.count == images.count, let first = layouts.first,
              layouts.allSatisfy({ $0.isSheet == first.isSheet }),
              first.isSheet || count == 1 || images.count == count else { return nil }

        let framesPerImage = first.isSheet ? count : 1
        var output: [CGImage] = []
        for (image, layout) in zip(images, layouts) {
            let width = max(layout.width, Int((size.width * CGFloat(layout.scale)).rounded()))
            let frameHeight = max(layout.frameHeight, Int((size.height * CGFloat(layout.scale)).rounded()))
            guard let bitmap = operations.makeContext(width, frameHeight * framesPerImage) else { return nil }
            bitmap.clear(CGRect(x: 0, y: 0, width: width, height: frameHeight * framesPerImage))
            bitmap.interpolationQuality = .none
            for index in 0..<framesPerImage {
                let frame = first.isSheet
                    ? operations.crop(image, CGRect(x: 0, y: index * layout.frameHeight,
                                                    width: layout.width, height: layout.frameHeight))
                    : image
                guard let frame else { return nil }
                // CGContext uses a bottom-left origin. Keep each frame's artwork anchored at its top left.
                let y = (framesPerImage - index) * frameHeight - layout.frameHeight
                bitmap.draw(frame, in: CGRect(x: 0, y: y, width: layout.width, height: layout.frameHeight))
            }
            guard let padded = bitmap.makeImage() else { return nil }
            output.append(padded)
        }
        return (size, output)
    }

    func applyTheme(atPath path: String) -> Bool {
        guard let data = operations.readFile(path), let theme = Self.theme(from: data) else {
            print("Could not read a valid Cape at \(path)")
            return false
        }
        return applyTheme(theme)
    }

    func applyTheme(_ theme: NSDictionary) -> Bool {
        autoreleasepool {
            let cursors = theme[MACCursorDefinitions.cursorsKey] as? NSDictionary ?? [:]
            let shadow = (operations.readPreference(MACPreferences.cursorShadowKey) as? NSNumber)?.boolValue ?? false
            operations.unregisterAll()
            for index in 0...MACCursorDefinitions.maxCoreCursorID { operations.selectCore(index) }
            if let data = operations.readFile(operations.defaultPath()), let defaults = Self.theme(from: data),
               let baseline = defaults[MACCursorDefinitions.cursorsKey] as? NSDictionary {
                let context = context(identifiers: Set(baseline.allKeys.compactMap { $0 as? String }), shadow: shadow)
                for case let key as String in baseline.keyEnumerator() {
                    if let cursor = baseline[key] as? [String: Any] { _ = applyCursor(cursor, identifier: key, restore: true, context: context) }
                }
            }
            let context = context(identifiers: Set(cursors.allKeys.compactMap { $0 as? String }), shadow: shadow)
            for case let key as String in cursors.keyEnumerator() {
                if let cursor = cursors[key] as? [String: Any], applyCursor(cursor, identifier: key, restore: false, context: context) { continue }
                print("Failed to hook identifier \(key), continuing with remaining cursors")
            }
            for case let key as String in cursors.keyEnumerator() {
                operations.activate(key)
                for alias in operations.browserAliases(key) { operations.activate(alias) }
            }
            operations.writePreference(theme[MACCursorDefinitions.identifierKey], MACPreferences.appliedCursorKey)
            finalizeApply(scaleBump: MACCursorDefinitions.refreshScaleBumpSmall)
            return true
        }
    }

    func resetAllCursors() throws {
        guard let data = operations.readFile(operations.defaultPath()) else {
            throw Self.resetError(-1, "System default cursor file not found. Please restart the app to regenerate it.")
        }
        guard let theme = Self.theme(from: data) else {
            throw Self.resetError(-2, "System default cursor file is corrupted.")
        }
        guard let cursors = theme[MACCursorDefinitions.cursorsKey] as? [String: Any], !cursors.isEmpty else {
            throw Self.resetError(-3, "System default cursor file contains no cursor data.")
        }
        operations.unregisterAll()
        for index in 0...MACCursorDefinitions.maxCoreCursorID { operations.selectCore(index) }
        let context = context(identifiers: Set(cursors.keys), shadow: false)
        for (key, value) in cursors {
            if let cursor = value as? [String: Any], applyCursor(cursor, identifier: key, restore: true, context: context) { continue }
            print("Failed to restore cursor: \(key)")
        }
        operations.selectArrow()
        if operations.isTahoe() {
            operations.dockOverride(false)
            nudgePreferredScale(MACCursorDefinitions.refreshScaleBumpSmall)
        }
        operations.writePreference(nil, MACPreferences.appliedCursorKey)
    }

    private nonisolated static func resetError(_ code: Int, _ message: String) -> NSError {
        NSError(domain: "com.writronic.macursor.engine", code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private nonisolated static func theme(from data: Data) -> NSDictionary? {
        (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? NSDictionary
    }

    func finalizeApply(scaleBump: Float) {
        operations.dockOverride(true)
        nudgePreferredScale(scaleBump)
        operations.selectArrow()
    }

    private func nudgePreferredScale(_ bump: Float) {
        let live = operations.getScale()
        var scale: Float = 1
        if live == MACCursorDefinitions.dumpScale || !MACCursorDefinitions.resolvePreferredScale(operations.readPreference(MACPreferences.cursorScaleKey) as? NSNumber, &scale) {
            guard let live else { return }
            scale = live
        }
        _ = operations.setScale(scale + bump)
        _ = operations.setScale(scale)
    }

    func cursorScale() -> Float { operations.getScale() ?? 1 }

    func defaultCursorScale() -> Float {
        var scale: Float = 1
        MACCursorDefinitions.resolvePreferredScale(operations.readPreference(MACPreferences.cursorScaleKey) as? NSNumber, &scale)
        return scale
    }

    @discardableResult
    func setCursorScale(_ scale: Float) -> Bool {
        guard scale.isFinite, scale >= MACCursorDefinitions.minCursorScale, scale <= MACCursorDefinitions.maxCursorScale else { return false }
        return operations.setScale(scale)
    }

    @discardableResult
    func assertPreferredCursorScale() -> Bool {
        guard operations.getScale() != MACCursorDefinitions.dumpScale else { return false }
        var scale: Float = 1
        guard MACCursorDefinitions.resolvePreferredScale(operations.readPreference(MACPreferences.cursorScaleKey) as? NSNumber, &scale) else { return false }
        return setCursorScale(scale)
    }

    nonisolated static func prepareImages(_ input: [CGImage], size: CGSize, frameCount: inout UInt,
                                          frameDuration: inout CGFloat,
                                          operations: MACCursorImageOperations = MACCursorImageOperations()) -> [CGImage] {
        guard !input.isEmpty, frameCount >= 2, let originalFrames = Int(exactly: frameCount) else { return input }
        var images = input
        var count = originalFrames
        var duration = frameDuration
        let cap = Int(MACCursorDefinitions.maxFrameCount)
        if images.count == count, size.width > 0, size.height > 0 {
            let width = images[0].width
            let height = images[0].height
            let target = size.width / size.height
            let flatAspect = CGFloat(width) / CGFloat(height)
            let stripAspect = CGFloat(width) * CGFloat(count) / CGFloat(height)
            if images.allSatisfy({ $0.width == width && $0.height == height }),
               abs(flatAspect - target) <= 0.05 * target, abs(stripAspect - target) > 0.05 * target,
               height <= Int.max / count, let context = operations.makeContext(width, height * count) {
                context.clear(CGRect(x: 0, y: 0, width: width, height: height * count))
                for (index, image) in images.enumerated() {
                    context.draw(image, in: CGRect(x: 0, y: (count - 1 - index) * height, width: width, height: height))
                }
                if let strip = context.makeImage() { images = [strip] }
            }
        }
        if images.count != count {
            let mismatched = images.filter { $0.height % count != 0 }.count
            if mismatched > 0 { print("\(mismatched) of \(images.count) representation heights not divisible by frame count \(count)") }
        }
        var rebuilt = false
        if count > cap {
            var sheets: [CGImage] = []
            for image in images {
                let height = image.height / count
                guard height > 0, height <= Int.max / cap,
                      let context = operations.makeContext(image.width, height * cap) else { break }
                context.clear(CGRect(x: 0, y: 0, width: image.width, height: height * cap))
                var complete = true
                for index in 0..<cap {
                    let source = Int(UInt(index) * UInt(count) / UInt(cap))
                    guard let frame = operations.crop(image, CGRect(x: 0, y: source * height, width: image.width, height: height)) else {
                        complete = false
                        break
                    }
                    context.draw(frame, in: CGRect(x: 0, y: (cap - 1 - index) * height, width: image.width, height: height))
                }
                guard complete, let sheet = context.makeImage() else { break }
                sheets.append(sheet)
            }
            if sheets.count == images.count {
                duration = duration * CGFloat(count) / CGFloat(cap)
                count = cap
                images = sheets
                rebuilt = true
            }
        }
        if !rebuilt, count > cap, images[0].height / count > 0 {
            var split: [CGImage] = []
            for image in images {
                let height = image.height / count
                guard height > 0 else { break }
                for index in 0..<count {
                    guard let frame = operations.crop(image, CGRect(x: 0, y: index * height, width: image.width, height: height)) else { break }
                    split.append(frame)
                }
            }
            if images.count <= Int.max / count, split.count == count * images.count {
                images = Array(split.suffix(count))
            }
        }
        if images.count > cap {
            let originalCount = images.count
            images = (0..<cap).map { images[$0 * originalCount / cap] }
            duration = duration * CGFloat(originalCount) / CGFloat(cap)
            count = cap
        }
        frameCount = UInt(count)
        frameDuration = duration
        return images
    }
}
