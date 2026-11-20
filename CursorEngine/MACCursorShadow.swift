import AppKit

enum MACCursorShadow {
    struct Parameters {
        let offsetX: CGFloat
        let offsetY: CGFloat
        let blur: CGFloat
        let alpha: CGFloat
        let supportRadius: CGFloat

        static let standard = Parameters(offsetX: 2, offsetY: 2, blur: 3, alpha: 0.30, supportRadius: 8)
    }

    struct Margins {
        let left: CGFloat
        let top: CGFloat
        let right: CGFloat
        let bottom: CGFloat
    }

    static func margins(for params: Parameters) -> Margins {
        Margins(left: max(0, params.supportRadius - params.offsetX),
                top: max(0, params.supportRadius - params.offsetY),
                right: max(0, params.supportRadius + params.offsetX),
                bottom: max(0, params.supportRadius + params.offsetY))
    }

    static func adjustRegistration(size: inout CGSize, hotSpot: inout CGPoint, margins: Margins, scale: CGFloat) {
        size.width += (margins.left + margins.right) * scale
        size.height += (margins.top + margins.bottom) * scale
        hotSpot.x += margins.left * scale
        hotSpot.y += margins.top * scale
    }

    static func makeContext(width: Int, height: Int) -> CGContext? {
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                         bytesPerRow: 0, space: space,
                         bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)
    }

    static func shadowedImages(_ images: [CGImage], frameCount: UInt, pointSize: CGSize,
                               params: Parameters = .standard) -> (images: [CGImage], margins: Margins)? {
        guard !images.isEmpty, frameCount >= 1, frameCount <= MACCursorDefinitions.maxFrameCount,
              pointSize.width.isFinite, pointSize.height.isFinite,
              pointSize.width > 0, pointSize.height > 0,
              params.supportRadius.isFinite, params.supportRadius >= 0,
              params.blur.isFinite, params.blur >= 0,
              params.offsetX.isFinite, params.offsetY.isFinite, params.alpha.isFinite else { return nil }
        let count = Int(frameCount)
        let margins = margins(for: params)
        let layouts = images.compactMap { MACCursorImageOperations.layout(of: $0, frameCount: count, pointSize: pointSize) }
        guard layouts.count == images.count, let first = layouts.first,
              layouts.allSatisfy({ $0.isSheet == first.isSheet }),
              first.isSheet || count == 1 || images.count == count else { return nil }
        var output: [CGImage] = []
        for (source, layout) in zip(images, layouts) {
            let padding = [margins.left, margins.top, margins.right, margins.bottom].map {
                Int(exactly: ($0 * CGFloat(layout.scale)).rounded())
            }
            guard let left = padding[0], let top = padding[1],
                  let right = padding[2], let bottom = padding[3],
                  left <= Int.max - layout.width, right <= Int.max - layout.width - left,
                  top <= Int.max - layout.frameHeight, bottom <= Int.max - layout.frameHeight - top else { return nil }
            let width = layout.width + left + right
            let height = layout.frameHeight + top + bottom
            let frames = layout.isSheet ? count : 1
            guard height <= Int.max / frames else { return nil }
            var shadowedFrames: [CGImage] = []
            for index in 0..<frames {
                let frame = layout.isSheet
                    ? source.cropping(to: CGRect(x: 0, y: index * layout.frameHeight,
                                                width: layout.width, height: layout.frameHeight))
                    : source
                guard let frame, let context = makeContext(width: width, height: height),
                      let space = context.colorSpace,
                      let color = CGColor(colorSpace: space, components: [0, 0, 0, params.alpha]) else { return nil }
                context.clear(CGRect(x: 0, y: 0, width: width, height: height))
                context.setShadow(offset: CGSize(width: params.offsetX * CGFloat(layout.scale),
                                                  height: -params.offsetY * CGFloat(layout.scale)),
                                  blur: params.blur * CGFloat(layout.scale), color: color)
                context.interpolationQuality = .none
                context.draw(frame, in: CGRect(x: left, y: bottom, width: layout.width, height: layout.frameHeight))
                guard let shadowed = context.makeImage() else { return nil }
                shadowedFrames.append(shadowed)
            }
            if layout.isSheet {
                guard let context = makeContext(width: width, height: height * count) else { return nil }
                context.clear(CGRect(x: 0, y: 0, width: width, height: height * count))
                for (index, frame) in shadowedFrames.enumerated() {
                    context.draw(frame, in: CGRect(x: 0, y: (count - 1 - index) * height, width: width, height: height))
                }
                guard let sheet = context.makeImage() else { return nil }
                output.append(sheet)
            } else {
                output.append(shadowedFrames[0])
            }
        }
        return (output, margins)
    }
}
