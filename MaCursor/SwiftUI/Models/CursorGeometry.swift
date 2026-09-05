import AppKit
import CoreGraphics
import Foundation

enum CursorGeometry {
    static let basePointSize = Int(MACBaseCursorPointSize)
    static let ladder: [UInt] = [100, 200, 500, 1000]
    static let maxPointSize = Int(MACMaxCursorPointSize)

    static var baseSize: CGSize {
        CGSize(width: basePointSize, height: basePointSize)
    }

    static func multiplier(forScaleValue scale: UInt) -> Int {
        max(1, Int(scale) / 100)
    }

    static func pixelWidth(forScaleValue scale: UInt, pointWidth: Int = basePointSize) -> Int {
        max(1, pointWidth * multiplier(forScaleValue: scale))
    }

    static func scaleValue(forPixelWidth width: Int, pointWidth: Int = basePointSize) -> UInt {
        guard width > 0, pointWidth > 0 else { return 100 }
        let ratio = Double(width) / Double(pointWidth)
        var best: UInt = 100
        var bestDistance = Double.greatestFiniteMagnitude
        for scale in ladder {
            let distance = abs(ratio - Double(multiplier(forScaleValue: scale)))
            if distance < bestDistance || (distance == bestDistance && scale > best) {
                best = scale
                bestDistance = distance
            }
        }
        return best
    }

    static func normalizedPointWidth(_ width: CGFloat) -> Int {
        guard width.isFinite, width > 0 else { return basePointSize }
        return Int(width.rounded())
    }

    static func framePixelHeight(of rep: NSBitmapImageRep, frameCount: Int) -> Int? {
        guard rep.pixelsWide > 0, rep.pixelsHigh > 0 else { return nil }
        let height = rep.pixelsHigh / max(1, frameCount)
        return height > 0 ? height : nil
    }

    static func pointSize(of rep: NSBitmapImageRep, scaleValue scale: UInt, frameCount: Int) -> CGSize? {
        guard let framePixels = framePixelHeight(of: rep, frameCount: frameCount) else { return nil }
        let divisor = Double(multiplier(forScaleValue: scale))
        let width = (Double(rep.pixelsWide) / divisor).rounded()
        let height = (Double(framePixels) / divisor).rounded()
        guard width >= 1, height >= 1 else { return nil }
        return CGSize(width: width, height: height)
    }

    static func pointHeight(of rep: NSBitmapImageRep, pointWidth: CGFloat, frameCount: Int) -> CGFloat? {
        guard pointWidth > 0,
              let framePixels = framePixelHeight(of: rep, frameCount: frameCount) else { return nil }
        let height = Double(pointWidth) * Double(framePixels) / Double(rep.pixelsWide)
        guard height >= 1 else { return nil }
        return CGFloat(height)
    }

    static func baseSize(matchingAspectOf rep: NSBitmapImageRep, frameCount: Int) -> CGSize {
        let width = Double(basePointSize)
        let frames = max(1, frameCount)
        guard rep.pixelsWide > 0, rep.pixelsHigh > 0 else { return baseSize }
        let frameHeight = Double(rep.pixelsHigh) / Double(frames)
        let aspect = frameHeight / Double(rep.pixelsWide)
        guard aspect.isFinite, aspect > 0 else { return baseSize }
        let height = max(1.0, (width * aspect).rounded())
        return CGSize(width: width, height: height)
    }
}

public enum EditorScale: Int, CaseIterable, Sendable, Identifiable {
    case x1 = 1
    case x2 = 2
    case x5 = 5
    case x10 = 10

    public var id: Int { rawValue }
    public var pixelSize: PixelSize { PixelSize(square: CursorGeometry.basePointSize * rawValue) }
    public var label: String { "\(rawValue)x" }
}

enum ImageScaler {
    static func rgbaContext(width: Int, height: Int) throws -> CGContext {
        guard width > 0, height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil,
                                  width: width,
                                  height: height,
                                  bitsPerComponent: 8,
                                  bytesPerRow: 0,
                                  space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else {
            throw CursorReadError.unsupportedImage("cannot create \(width)x\(height) RGBA context")
        }
        ctx.interpolationQuality = .high
        return ctx
    }

    static func padScale(_ image: CGImage, to size: PixelSize) throws -> CGImage {
        let ctx = try rgbaContext(width: size.width, height: size.height)
        let xRatio = Double(size.width) / Double(image.width)
        let yRatio = Double(size.height) / Double(image.height)
        let scale = min(xRatio, yRatio)
        let w = Double(image.width) * scale
        let h = Double(image.height) * scale
        let rect = CGRect(x: (Double(size.width) - w) / 2,
                          y: (Double(size.height) - h) / 2,
                          width: w, height: h)
        ctx.draw(image, in: rect)
        guard let out = ctx.makeImage() else {
            throw CursorReadError.unsupportedImage("padScale composition failed")
        }
        return out
    }

    static func crop(_ image: CGImage, to rect: CGRect) throws -> CGImage {
        guard let out = image.cropping(to: rect) else {
            throw CursorReadError.unsupportedImage("crop \(rect) failed")
        }
        return out
    }

    static func makeImage(rgba: [UInt8], width: Int, height: Int) throws -> CGImage {
        guard width > 0, height > 0, rgba.count == width * height * 4,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(rgba) as CFData),
              let image = CGImage(width: width,
                                  height: height,
                                  bitsPerComponent: 8,
                                  bitsPerPixel: 32,
                                  bytesPerRow: width * 4,
                                  space: space,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                                  provider: provider,
                                  decode: nil,
                                  shouldInterpolate: false,
                                  intent: .defaultIntent)
        else {
            throw CursorReadError.unsupportedImage("cannot build \(width)x\(height) RGBA image")
        }
        return image
    }
}
