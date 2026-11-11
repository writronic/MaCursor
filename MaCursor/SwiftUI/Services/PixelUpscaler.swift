import AppKit
import CoreML

enum PixelUpscaler {
    enum UpscaleError: Error, Equatable {
        case noModel
        case unexpectedModel
        case unreadablePicture
    }

    struct Strip: Sendable, Equatable {
        let rgba: [UInt8]
        let width: Int
        let height: Int
        let frameCount: Int
    }

    static let bundledModelURL = Bundle.main.url(forResource: "upscale", withExtension: "mlmodelc")

    static func strip(of rep: NSBitmapImageRep, frameCount: Int) -> Strip? {
        let frames = max(1, frameCount)
        guard rep.pixelsWide > 0, rep.pixelsHigh > 0, rep.pixelsHigh.isMultiple(of: frames),
              let image = rep.cgImage, let rgba = try? ImageScaler.straightRGBA(of: image) else { return nil }
        return Strip(rgba: rgba, width: rep.pixelsWide, height: rep.pixelsHigh, frameCount: frames)
    }

    static func image(of strip: Strip) throws -> NSBitmapImageRep {
        NSBitmapImageRep(cgImage: try ImageScaler.makeImage(rgba: strip.rgba, width: strip.width, height: strip.height))
    }

    static func doubled(_ strips: [Strip], modelURL: URL?) throws -> [Strip] {
        let network = try Network(contentsOf: modelURL)
        return try strips.map { try doubled($0, network: network) }
    }

    static func doubled(_ strip: Strip, network: Network) throws -> Strip {
        let frameHeight = strip.height / strip.frameCount
        let frameBytes = strip.width * frameHeight * 4
        guard strip.rgba.count == frameBytes * strip.frameCount, frameBytes > 0 else { throw UpscaleError.unreadablePicture }
        let frames = stride(from: 0, to: strip.rgba.count, by: frameBytes).map { Array(strip.rgba[$0..<$0 + frameBytes]) }
        let shadowSides = allowedShadowSides(frames.map { shadowSideCounts($0, width: strip.width, height: frameHeight) }
            .reduce([0, 0, 0, 0]) { zip($0, $1).map(+) })
        var rgba: [UInt8] = []
        rgba.reserveCapacity(strip.rgba.count * 4)
        for frame in frames {
            rgba += try doubledFrame(frame, width: strip.width, height: frameHeight, shadowSides: shadowSides, network: network)
        }
        return Strip(rgba: rgba, width: strip.width * 2, height: strip.height * 2, frameCount: strip.frameCount)
    }

    private static func doubledFrame(_ rgba: [UInt8], width: Int, height: Int, shadowSides: [Bool],
                                     network: Network) throws -> [UInt8] {
        let colours = withoutColourSpecks(try network.doubled(filledColours(rgba, width: width, height: height),
                                                              width: width, height: height),
                                          source: rgba, width: width, height: height)
        let modelAlphas = try network.doubled(stride(from: 3, to: rgba.count, by: 4).map { SIMD3(repeating: Float(rgba[$0]) / 255) },
                                              width: width, height: height).map(\.y)
        let alphas = softenedShadows(modelAlphas, source: rgba, width: width, height: height, allowedSides: shadowSides)
        var doubled = [UInt8](repeating: 0, count: rgba.count * 4)
        for (index, colour) in colours.enumerated() where alphas[index] >= 1.0 / 255 {
            doubled[index * 4] = byte(colour.x)
            doubled[index * 4 + 1] = byte(colour.y)
            doubled[index * 4 + 2] = byte(colour.z)
            doubled[index * 4 + 3] = byte(alphas[index])
        }
        return doubled
    }

    static func filledColours(_ rgba: [UInt8], width: Int, height: Int) -> [SIMD3<Float>] {
        let count = width * height
        var colours: [SIMD3<Float>] = (0..<count).map { index in
            let red = Float(rgba[index * 4])
            let green = Float(rgba[index * 4 + 1])
            let blue = Float(rgba[index * 4 + 2])
            return SIMD3<Float>(red, green, blue) / 255
        }
        var filled = (0..<count).map { rgba[$0 * 4 + 3] != 0 }
        func eachNeighbour(of index: Int, _ body: (Int) -> Void) {
            let x = index % width
            let y = index / width
            for row in max(0, y - 1)...min(height - 1, y + 1) {
                for column in max(0, x - 1)...min(width - 1, x + 1) { body(row * width + column) }
            }
        }
        var ring: [Int] = []
        var queued = filled
        func queueClearNeighbours(of index: Int) {
            eachNeighbour(of: index) { neighbour in
                guard !queued[neighbour] else { return }
                queued[neighbour] = true
                ring.append(neighbour)
            }
        }
        (0..<count).filter { filled[$0] }.forEach(queueClearNeighbours)
        while !ring.isEmpty {
            for index in ring {
                var sum = SIMD3<Float>.zero
                var found: Float = 0
                eachNeighbour(of: index) { neighbour in
                    guard filled[neighbour] else { return }
                    sum += colours[neighbour]
                    found += 1
                }
                colours[index] = sum / found
            }
            let current = ring
            ring = []
            current.forEach { filled[$0] = true }
            current.forEach(queueClearNeighbours)
        }
        return colours
    }

    static let speckMargin: Float = 8.0 / 255

    static func withoutColourSpecks(_ doubled: [SIMD3<Float>], source rgba: [UInt8], width: Int, height: Int) -> [SIMD3<Float>] {
        let sourceChroma = (0..<width * height).map { index -> Float in
            guard rgba[index * 4 + 3] != 0 else { return -1 }
            let colour = rgba[index * 4..<index * 4 + 3]
            return Float(colour.max()! - colour.min()!) / 255
        }
        var allowed = [Float](repeating: -1, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                for row in max(0, y - 1)...min(height - 1, y + 1) {
                    for column in max(0, x - 1)...min(width - 1, x + 1) {
                        allowed[y * width + x] = max(allowed[y * width + x], sourceChroma[row * width + column])
                    }
                }
            }
        }
        return doubled.enumerated().map { index, colour in
            let limit = allowed[(index / (2 * width)) / 2 * width + (index % (2 * width)) / 2]
            let chroma = colour.max() - colour.min()
            guard limit >= 0, chroma > limit + speckMargin else { return colour }
            let luma = (colour * SIMD3(0.299, 0.587, 0.114)).sum()
            return luma + (colour - luma) * ((limit + speckMargin) / chroma)
        }
    }

    static let shadowMaxAlpha: UInt8 = 152
    static let shadowMaxLuma: Float = 0.25
    static let shadowLumaGap: Float = 0.5
    static let shadowSideRatio = 2
    static let shadowBlend: Float = 0.5
    static let shadowFullBlendAlpha: Float = 51
    static let smoothNearWeight: Float = 0.75

    static func luma(_ rgba: [UInt8], _ index: Int) -> Float {
        (0.299 * Float(rgba[index * 4]) + 0.587 * Float(rgba[index * 4 + 1]) + 0.114 * Float(rgba[index * 4 + 2])) / 255
    }

    private static func isFaintDark(_ rgba: [UInt8], _ index: Int) -> Bool {
        rgba[index * 4 + 3] > 0 && rgba[index * 4 + 3] <= shadowMaxAlpha && luma(rgba, index) <= shadowMaxLuma
    }

    static func shapeSides(of index: Int, in rgba: [UInt8], width: Int, height: Int) -> [Bool] {
        let x = index % width
        let y = index / width
        let shape = { (dx: Int, dy: Int) -> Bool in
            let column = x + dx
            let row = y + dy
            return column >= 0 && row >= 0 && column < width && row < height
                && rgba[(row * width + column) * 4 + 3] > shadowMaxAlpha
        }
        let direct = [shape(-1, 0), shape(1, 0), shape(0, -1), shape(0, 1)]
        guard !direct.contains(true) else { return direct }
        return [shape(-1, -1) || shape(-1, 1), shape(1, -1) || shape(1, 1), shape(-1, -1) || shape(1, -1), shape(-1, 1) || shape(1, 1)]
    }

    static func shadowSideCounts(_ rgba: [UInt8], width: Int, height: Int) -> [Int] {
        var counts = [0, 0, 0, 0]
        for index in 0..<width * height where isFaintDark(rgba, index) {
            for (side, isShape) in shapeSides(of: index, in: rgba, width: width, height: height).enumerated() where isShape {
                counts[side] += 1
            }
        }
        return counts
    }

    static func allowedShadowSides(_ counts: [Int]) -> [Bool] {
        (0..<4).map { counts[$0] > shadowSideRatio * counts[$0 ^ 1] }
    }

    static func isShadowPixel(_ index: Int, in rgba: [UInt8], width: Int, height: Int, allowedSides: [Bool]) -> Bool {
        guard isFaintDark(rgba, index) else { return false }
        let x = index % width
        let y = index / width
        let ownLuma = luma(rgba, index)
        var besideClear = x == 0 || y == 0 || x == width - 1 || y == height - 1
        var besideShape = false
        var shapeIsLighter = true
        for row in max(0, y - 1)...min(height - 1, y + 1) {
            for column in max(0, x - 1)...min(width - 1, x + 1) where row != y || column != x {
                let neighbour = row * width + column
                let alpha = rgba[neighbour * 4 + 3]
                if alpha == 0 { besideClear = true }
                guard alpha > shadowMaxAlpha else { continue }
                besideShape = true
                if abs(ownLuma - luma(rgba, neighbour)) < shadowLumaGap { shapeIsLighter = false }
            }
        }
        return besideClear && besideShape && shapeIsLighter
            && zip(shapeSides(of: index, in: rgba, width: width, height: height), allowedSides).allSatisfy { !$0 || $1 }
    }

    static func smoothAlpha(x: Int, y: Int, source rgba: [UInt8], width: Int, height: Int) -> Float {
        let alpha = { (column: Int, row: Int) -> Float in
            column >= 0 && row >= 0 && column < width && row < height ? Float(rgba[(row * width + column) * 4 + 3]) / 255 : 0
        }
        let near = smoothNearWeight
        let far = 1 - smoothNearWeight
        let column = x / 2
        let row = y / 2
        let side = x.isMultiple(of: 2) ? column - 1 : column + 1
        let vertical = y.isMultiple(of: 2) ? row - 1 : row + 1
        return near * near * alpha(column, row) + near * far * alpha(side, row) + near * far * alpha(column, vertical)
            + far * far * alpha(side, vertical)
    }

    static func softenedShadows(_ alphas: [Float], source rgba: [UInt8], width: Int, height: Int, allowedSides: [Bool]) -> [Float] {
        var softened = alphas
        for index in 0..<width * height where isShadowPixel(index, in: rgba, width: width, height: height, allowedSides: allowedSides) {
            let weight = shadowBlend * min(1, Float(rgba[index * 4 + 3]) / shadowFullBlendAlpha)
            for (dx, dy) in [(0, 0), (1, 0), (0, 1), (1, 1)] {
                let x = 2 * (index % width) + dx
                let y = 2 * (index / width) + dy
                let target = smoothAlpha(x: x, y: y, source: rgba, width: width, height: height)
                softened[y * 2 * width + x] += weight * (target - softened[y * 2 * width + x])
            }
        }
        return softened
    }

    private static func byte(_ value: Float) -> UInt8 {
        UInt8((min(1, max(0, value)) * 255).rounded())
    }
}

extension PixelUpscaler {
    struct Network {
        static let lostEdge = 7

        let model: MLModel
        let side: Int
        let inputType: MLMultiArrayDataType

        var tile: Int { side - 2 * Self.lostEdge }

        init(contentsOf url: URL?, computeUnits: MLComputeUnits = .all) throws {
            guard let url else { throw UpscaleError.noModel }
            let configuration = MLModelConfiguration()
            configuration.computeUnits = computeUnits
            guard let model = try? MLModel(contentsOf: url, configuration: configuration) else { throw UpscaleError.noModel }
            guard let input = model.modelDescription.inputDescriptionsByName["input"]?.multiArrayConstraint,
                  input.shape.count == 3, input.shape[0] == 3, input.shape[1] == input.shape[2],
                  input.shape[1].intValue > 2 * Self.lostEdge,
                  [.double, .float32].contains(input.dataType) else { throw UpscaleError.unexpectedModel }
            self.model = model
            side = input.shape[1].intValue
            inputType = input.dataType
        }

        func doubled(_ colours: [SIMD3<Float>], width: Int, height: Int) throws -> [SIMD3<Float>] {
            guard width > 0, height > 0, colours.count == width * height else { throw UpscaleError.unreadablePicture }
            let input = try MLMultiArray(shape: [3, side, side].map { NSNumber(value: $0) }, dataType: inputType)
            var doubled = [SIMD3<Float>](repeating: .zero, count: 4 * width * height)
            for top in stride(from: 0, to: height, by: tile) {
                for left in stride(from: 0, to: width, by: tile) {
                    let sample = { (x: Int, y: Int) in
                        colours[min(height - 1, max(0, top + y - Self.lostEdge)) * width
                            + min(width - 1, max(0, left + x - Self.lostEdge))]
                    }
                    switch inputType {
                    case .double: input.writePlanes(Double.self, side: side, sample)
                    default: input.writePlanes(Float.self, side: side, sample)
                    }
                    let features = try MLDictionaryFeatureProvider(dictionary: ["input": MLFeatureValue(multiArray: input)])
                    guard let output = try model.prediction(from: features).featureValue(for: "conv7")?.multiArrayValue,
                          output.shape.suffix(3).map(\.intValue) == [3, 2 * tile, 2 * tile] else {
                        throw UpscaleError.unexpectedModel
                    }
                    let rows = 2 * min(tile, height - top)
                    let columns = 2 * min(tile, width - left)
                    let place = { (x: Int, y: Int, colour: SIMD3<Float>) in
                        doubled[(2 * top + y) * 2 * width + 2 * left + x] = colour.clamped(lowerBound: .zero, upperBound: .one)
                    }
                    switch output.dataType {
                    case .double: output.readPlanes(Double.self, rows: rows, columns: columns, place)
                    case .float32: output.readPlanes(Float.self, rows: rows, columns: columns, place)
                    default: throw UpscaleError.unexpectedModel
                    }
                }
            }
            return doubled
        }
    }
}

private extension MLMultiArray {
    func writePlanes<Scalar: MLShapedArrayScalar & BinaryFloatingPoint>(_ type: Scalar.Type, side: Int,
                                                                         _ colour: (Int, Int) -> SIMD3<Float>) {
        withUnsafeMutableBufferPointer(ofType: Scalar.self) { buffer, strides in
            for y in 0..<side {
                for x in 0..<side {
                    let value = colour(x, y)
                    for channel in 0..<3 {
                        buffer[channel * strides[0] + y * strides[1] + x * strides[2]] = Scalar(value[channel])
                    }
                }
            }
        }
    }

    func readPlanes<Scalar: MLShapedArrayScalar & BinaryFloatingPoint>(_ type: Scalar.Type, rows: Int, columns: Int,
                                                                        _ place: (Int, Int, SIMD3<Float>) -> Void) {
        let planeStrides = strides.suffix(3).map(\.intValue)
        withUnsafeBufferPointer(ofType: Scalar.self) { buffer in
            for y in 0..<rows {
                for x in 0..<columns {
                    let offset = y * planeStrides[1] + x * planeStrides[2]
                    place(x, y, SIMD3(Float(buffer[offset]), Float(buffer[offset + planeStrides[0]]),
                                      Float(buffer[offset + 2 * planeStrides[0]])))
                }
            }
        }
    }
}
