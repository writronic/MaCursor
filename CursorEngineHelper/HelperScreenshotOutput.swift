import Accelerate
import AppKit
import libwebp

extension CursorScreenshotOutput {
    static let borderAlpha: CGFloat = 0.25

    func apply(_ image: CGImage, scale: CGFloat) -> CGImage {
        let shrinks = scalesTo1x && scale > 1
        guard shrinks || convertsToSRGB || addsBorder, let sRGB = CGColorSpace(name: CGColorSpace.sRGB) else { return image }
        let width = shrinks ? max(Int((CGFloat(image.width) / scale).rounded()), 1) : image.width
        let height = shrinks ? max(Int((CGFloat(image.height) / scale).rounded()), 1) : image.height
        let edge = addsBorder ? 1 : 0
        let make = { (space: CGColorSpace) in
            CGContext(data: nil, width: width + 2 * edge, height: height + 2 * edge, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        }
        let own = convertsToSRGB ? nil : image.colorSpace.flatMap(make)
        guard let context = own ?? make(sRGB) else { return image }
        let inside = CGRect(x: edge, y: edge, width: width, height: height)
        if addsBorder {
            context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: Self.borderAlpha))
            context.fill(CGRect(x: 0, y: 0, width: context.width, height: context.height))
            context.clear(inside)
        }
        context.interpolationQuality = .high
        context.draw(image, in: inside)
        return context.makeImage() ?? image
    }

    func encode(_ image: CGImage, scale: CGFloat, density: CGFloat? = nil, as format: CursorScreenshotFormat) -> Data? {
        format.data(of: apply(image, scale: scale), scale: shownScale(scale) * (density ?? scale) / scale)
    }
}

extension CursorScreenshotFormat {
    static let lossyQuality: CGFloat = 0.9

    static func writable(among types: [String]) -> [CursorScreenshotFormat] {
        allCases.filter { types.contains($0.rawValue) }
    }

    static var writable: [CursorScreenshotFormat] {
        writable(among: (CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []) + [webp.rawValue])
    }

    func data(of image: CGImage, scale: CGFloat) -> Data? {
        if self == .webp { return CursorScreenshotWebP.data(of: image) }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, rawValue as CFString, 1, nil) else { return nil }
        var properties: [CFString: Any] = [kCGImagePropertyDPIWidth: 72 * scale, kCGImagePropertyDPIHeight: 72 * scale]
        if self != .png { properties[kCGImageDestinationLossyCompressionQuality] = Self.lossyQuality }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}

enum CursorScreenshotWindowPicture {
    static func finished(_ image: CGImage, window: CursorScreenshotWindow, shadowed: Bool) -> CGImage {
        guard shadowed else {
            return image.cropping(to: CursorScreenshotBox.pixels(of: window.shown, in: window.frame, width: image.width, height: image.height)) ?? image
        }
        return lit(image).flatMap { image.cropping(to: $0) } ?? image
    }

    private static func lit(_ image: CGImage) -> CGRect? {
        let width = image.width
        let height = image.height
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let bytes = data.assumingMemoryBound(to: UInt8.self)
        var left = width, right = -1, top = height, bottom = -1
        for y in 0..<height {
            let row = bytes + y * width * 4
            for x in 0..<width where row[x * 4 + 3] > 0 {
                left = min(left, x)
                right = max(right, x)
                top = min(top, y)
                bottom = max(bottom, y)
            }
        }
        guard right >= left else { return nil }
        return CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1)
    }
}

enum CursorScreenshotWebP {
    static let quality: Float = 90
    static let largestSide = 16383

    static func data(of image: CGImage) -> Data? {
        let width = image.width
        let height = image.height
        guard max(width, height) <= largestSide, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let pixels = context.data else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var buffer = vImage_Buffer(data: pixels, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: width * 4)
        guard vImageUnpremultiplyData_RGBA8888(&buffer, &buffer, vImage_Flags(kvImageNoFlags)) == kvImageNoError else { return nil }
        var output: UnsafeMutablePointer<UInt8>?
        let size = WebPEncodeRGBA(pixels.assumingMemoryBound(to: UInt8.self), Int32(width), Int32(height), Int32(width * 4), quality, &output)
        defer { WebPFree(output) }
        guard size > 0, let output else { return nil }
        return Data(bytes: output, count: size)
    }
}
