import AppKit

struct WindowsCursorImporter {
    
    
    static func importCUR(from url: URL) throws -> MCCursorSwift {
        let data = try Data(contentsOf: url)
        let parsed = try WindowsCursorParser.parseCUR(data)
        return buildCursor(from: parsed, filename: url.deletingPathExtension().lastPathComponent)
    }
    
    static func importANI(from url: URL) throws -> MCCursorSwift {
        let data = try Data(contentsOf: url)
        let parsed = try WindowsCursorParser.parseANI(data)
        return buildAnimatedCursor(from: parsed, filename: url.deletingPathExtension().lastPathComponent)
    }
    
    static func importFile(from url: URL) throws -> MCCursorSwift {
        let data = try Data(contentsOf: url)
        let type = WindowsCursorParser.fileType(of: data)
        
        switch type {
        case .cur:
            let parsed = try WindowsCursorParser.parseCUR(data)
            return buildCursor(from: parsed, filename: url.deletingPathExtension().lastPathComponent)
        case .ani:
            let parsed = try WindowsCursorParser.parseANI(data)
            return buildAnimatedCursor(from: parsed, filename: url.deletingPathExtension().lastPathComponent)
        case .unknown:
            throw WindowsCursorParser.ParseError.unsupportedFormat("Not a .cur or .ani file")
        }
    }
    
    
    static func importAsTheme(from urls: [URL], themeName: String? = nil) -> CursorLibrary {
        let library = CursorLibrary()
        
        let resolvedName: String
        if let name = themeName, !name.isEmpty {
            resolvedName = name
        } else if urls.count == 1 {
            resolvedName = urls[0].deletingPathExtension().lastPathComponent
        } else {
            let folder = urls[0].deletingLastPathComponent().lastPathComponent
            resolvedName = folder.isEmpty ? "Imported Cursors" : folder
        }
        
        library.undoManager.disableUndoRegistration()
        library.name = resolvedName
        library.identifier = CursorLibrary.generateIdentifier(from: resolvedName)
        library.undoManager.enableUndoRegistration()
        
        for url in urls {
            do {
                let cursor = try importFile(from: url)
                library.addCursor(cursor)
            } catch {
                NSLog("WindowsCursorImporter: Failed to import \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        
        return library
    }
    
    
    static func parseForRepresentation(from url: URL) throws -> (image: NSBitmapImageRep, hotspot: CGPoint, frameCount: Int, frameDuration: Double) {
        let data = try Data(contentsOf: url)
        let type = WindowsCursorParser.fileType(of: data)
        
        switch type {
        case .cur:
            let parsed = try WindowsCursorParser.parseCUR(data)
            guard let best = parsed.images.first else {
                throw WindowsCursorParser.ParseError.corruptedImageData("No images in CUR file")
            }
            return (best.image, parsed.hotspot, 1, 1.0)
            
        case .ani:
            let parsed = try WindowsCursorParser.parseANI(data)
            let result = buildSpriteSheet(from: parsed)
            return (result.spriteSheet, result.hotspot, result.frameCount, result.frameDuration)
            
        case .unknown:
            throw WindowsCursorParser.ParseError.unsupportedFormat("Not a .cur or .ani file")
        }
    }
    
    
    private static func buildCursor(from parsed: WindowsCursorParser.CursorData, filename: String) -> MCCursorSwift {
        let cursor = MCCursorSwift()
        cursor.identifier = ""
        cursor.frameCount = 1
        cursor.frameDuration = 1.0
        cursor.hotSpot = NSPoint(x: parsed.hotspot.x, y: parsed.hotspot.y)
        
        let (rep1x, rep2x) = selectBestRepresentations(from: parsed.images)
        
        if let rep = rep1x {
            cursor.setRepresentation(rep, for: .scale100)
            cursor.size = NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        }
        
        if let rep = rep2x {
            cursor.setRepresentation(rep, for: .scale200)
        }
        
        return cursor
    }
    
    
    private static func buildAnimatedCursor(from parsed: WindowsCursorParser.AnimatedCursorData, filename: String) -> MCCursorSwift {
        let cursor = MCCursorSwift()
        cursor.identifier = ""
        
        let result = buildSpriteSheet(from: parsed)
        
        cursor.frameCount = UInt(result.frameCount)
        cursor.frameDuration = result.frameDuration
        cursor.hotSpot = NSPoint(x: result.hotspot.x, y: result.hotspot.y)
        
        cursor.setRepresentation(result.spriteSheet, for: .scale100)
        cursor.size = result.frameSize
        
        return cursor
    }
    
    private struct SpriteSheetResult {
        let spriteSheet: NSBitmapImageRep
        let hotspot: CGPoint
        let frameCount: Int
        let frameDuration: Double
        let frameSize: NSSize
    }
    
    private static func buildSpriteSheet(from parsed: WindowsCursorParser.AnimatedCursorData) -> SpriteSheetResult {
        let orderedFrames: [WindowsCursorParser.CursorData]
        if let seq = parsed.sequence {
            orderedFrames = seq.compactMap { idx in
                idx < parsed.frames.count ? parsed.frames[idx] : nil
            }
        } else {
            orderedFrames = parsed.frames
        }
        
        guard !orderedFrames.isEmpty else {
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 4, bitsPerPixel: 32
            )!
            return SpriteSheetResult(
                spriteSheet: rep, hotspot: .zero,
                frameCount: 1, frameDuration: 1.0,
                frameSize: NSSize(width: 1, height: 1)
            )
        }
        
        let frameReps: [NSBitmapImageRep] = orderedFrames.compactMap { frame in
            let (rep1x, _) = selectBestRepresentations(from: frame.images)
            return rep1x
        }
        
        guard !frameReps.isEmpty else {
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 4, bitsPerPixel: 32
            )!
            return SpriteSheetResult(
                spriteSheet: rep, hotspot: .zero,
                frameCount: 1, frameDuration: 1.0,
                frameSize: NSSize(width: 1, height: 1)
            )
        }
        
        let spriteSheet = composeSpriteSheetRaw(frames: frameReps)
        
        let hotspot = orderedFrames[0].hotspot
        
        let frameWidth = frameReps[0].pixelsWide
        let frameHeight = frameReps[0].pixelsHigh
        
        let frameDuration: Double
        if let rates = parsed.perFrameRates, !rates.isEmpty {
            frameDuration = rates.reduce(0, +) / Double(rates.count)
        } else {
            frameDuration = parsed.frameRate
        }
        
        return SpriteSheetResult(
            spriteSheet: spriteSheet,
            hotspot: hotspot,
            frameCount: frameReps.count,
            frameDuration: max(frameDuration, 0.01),
            frameSize: NSSize(width: frameWidth, height: frameHeight)
        )
    }
    
    private static func composeSpriteSheetRaw(frames: [NSBitmapImageRep]) -> NSBitmapImageRep {
        guard !frames.isEmpty else {
            return NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 4, bitsPerPixel: 32
            )!
        }
        if frames.count == 1 { return frames[0] }
        
        let width = frames[0].pixelsWide
        let totalHeight = frames.reduce(0) { $0 + $1.pixelsHigh }
        let dstRowBytes = width * 4
        
        guard let sheet = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: totalHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: .alphaNonpremultiplied,
            bytesPerRow: dstRowBytes,
            bitsPerPixel: 32
        ), let dstBase = sheet.bitmapData else {
            return MCCursorSwift.composeRepresentation(withFrames: frames) ?? frames[0]
        }
        
        var yOffset = 0
        for frame in frames {
            let frameHeight = frame.pixelsHigh
            let srcRowBytes = frame.bytesPerRow
            
            if let srcBase = frame.bitmapData {
                for row in 0..<frameHeight {
                    let srcRow = srcBase.advanced(by: row * srcRowBytes)
                    let dstRow = dstBase.advanced(by: (yOffset + row) * dstRowBytes)
                    memcpy(dstRow, srcRow, min(dstRowBytes, srcRowBytes))
                }
            }
            
            yOffset += frameHeight
        }
        
        return sheet
    }
    
    
    private static func selectBestRepresentations(
        from images: [WindowsCursorParser.CursorData.ImageEntry]
    ) -> (rep1x: NSBitmapImageRep?, rep2x: NSBitmapImageRep?) {
        guard !images.isEmpty else { return (nil, nil) }
        
        let img32 = images.first { $0.width == 32 && $0.height == 32 }
        let img64 = images.first { $0.width == 64 && $0.height == 64 }
        
        let usable = images.filter { $0.width > 16 || $0.height > 16 }
        
        let rep1x: NSBitmapImageRep?
        let rep2x: NSBitmapImageRep?
        
        if let img32 {
            rep1x = img32.image
            rep2x = img64?.image
        } else if let first = usable.first {
            rep1x = first.image
            rep2x = nil
        } else {
            rep1x = images.first?.image
            rep2x = nil
        }
        
        return (rep1x, rep2x)
    }
}
