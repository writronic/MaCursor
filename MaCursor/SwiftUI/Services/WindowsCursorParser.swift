import AppKit

struct WindowsCursorParser {
    
    
    struct CursorData {
        let images: [ImageEntry]
        let hotspot: CGPoint
        
        struct ImageEntry {
            let image: NSBitmapImageRep
            let width: Int
            let height: Int
        }
    }
    
    struct AnimatedCursorData {
        let frames: [CursorData]
        let frameRate: Double
        let perFrameRates: [Double]?
        let sequence: [Int]?
        let stepCount: Int
        let title: String?
        let author: String?
    }
    
    enum FileType {
        case cur
        case ani
        case unknown
    }
    
    enum ParseError: LocalizedError {
        case invalidHeader(String)
        case unsupportedFormat(String)
        case corruptedImageData(String)
        case truncatedFile
        
        var errorDescription: String? {
            switch self {
            case .invalidHeader(let detail): return "Invalid header: \(detail)"
            case .unsupportedFormat(let detail): return "Unsupported format: \(detail)"
            case .corruptedImageData(let detail): return "Corrupted image data: \(detail)"
            case .truncatedFile: return "File is truncated or incomplete"
            }
        }
    }
    
    
    static func fileType(of data: Data) -> FileType {
        guard data.count >= 4 else { return .unknown }
        
        if data.count >= 12 {
            let riff = String(data: data[0..<4], encoding: .ascii)
            let acon = String(data: data[8..<12], encoding: .ascii)
            if riff == "RIFF" && acon == "ACON" {
                return .ani
            }
        }
        
        let reserved = readUInt16(data, offset: 0)
        let idType = readUInt16(data, offset: 2)
        if reserved == 0 && idType == 2 {
            return .cur
        }
        
        return .unknown
    }
    
    
    static func parseCUR(_ data: Data) throws -> CursorData {
        guard data.count >= 6 else { throw ParseError.truncatedFile }
        
        let reserved = readUInt16(data, offset: 0)
        let idType = readUInt16(data, offset: 2)
        let idCount = readUInt16(data, offset: 4)
        
        guard reserved == 0 else {
            throw ParseError.invalidHeader("Reserved field is not 0")
        }
        guard idType == 2 else {
            throw ParseError.invalidHeader("idType is \(idType), expected 2 for CUR")
        }
        guard idCount > 0 else {
            throw ParseError.invalidHeader("No image entries in CUR file")
        }
        
        let headerSize = 6
        let entrySize = 16
        let requiredSize = headerSize + Int(idCount) * entrySize
        guard data.count >= requiredSize else { throw ParseError.truncatedFile }
        
        var entries: [(width: Int, height: Int, hotspotX: Int, hotspotY: Int,
                        dataSize: Int, dataOffset: Int, bitCount: Int)] = []
        
        for i in 0..<Int(idCount) {
            let entryOffset = headerSize + i * entrySize
            
            var width = Int(data[entryOffset])
            var height = Int(data[entryOffset + 1])
            if width == 0 { width = 256 }
            if height == 0 { height = 256 }
            
            let hotspotX = Int(readUInt16(data, offset: entryOffset + 4))
            let hotspotY = Int(readUInt16(data, offset: entryOffset + 6))
            let dataSize = Int(readUInt32(data, offset: entryOffset + 8))
            let dataOffset = Int(readUInt32(data, offset: entryOffset + 12))
            
            let bitCount: Int
            if dataOffset + 14 < data.count {
                bitCount = Int(readUInt16(data, offset: dataOffset + 14))
            } else {
                bitCount = 0
            }
            
            entries.append((width, height, hotspotX, hotspotY, dataSize, dataOffset, bitCount))
        }
        
        entries.sort { lhs, rhs in
            let areaL = lhs.width * lhs.height
            let areaR = rhs.width * rhs.height
            if areaL != areaR { return areaL > areaR }
            return lhs.bitCount > rhs.bitCount
        }
        
        var imageEntries: [CursorData.ImageEntry] = []
        
        for entry in entries {
            guard entry.dataOffset + entry.dataSize <= data.count else { continue }
            let imageData = data[entry.dataOffset..<(entry.dataOffset + entry.dataSize)]
            
            if let rep = try? decodeImageData(Data(imageData), expectedWidth: entry.width, expectedHeight: entry.height) {
                imageEntries.append(CursorData.ImageEntry(
                    image: rep,
                    width: rep.pixelsWide,
                    height: rep.pixelsHigh
                ))
            }
        }
        
        guard !imageEntries.isEmpty else {
            throw ParseError.corruptedImageData("No valid images found in CUR file")
        }
        
        let bestEntry = entries[0]
        let hotspot = CGPoint(x: bestEntry.hotspotX, y: bestEntry.hotspotY)
        
        return CursorData(images: imageEntries, hotspot: hotspot)
    }
    
    
    static func parseANI(_ data: Data) throws -> AnimatedCursorData {
        guard data.count >= 12 else { throw ParseError.truncatedFile }
        
        guard String(data: data[0..<4], encoding: .ascii) == "RIFF" else {
            throw ParseError.invalidHeader("Not a RIFF file")
        }
        guard String(data: data[8..<12], encoding: .ascii) == "ACON" else {
            throw ParseError.invalidHeader("RIFF type is not ACON")
        }
        
        var aniHeader: ANIHeader?
        var rateTable: [UInt32]?
        var seqTable: [UInt32]?
        var frames: [CursorData] = []
        var title: String?
        var author: String?
        
        try parseRIFFChunks(data: data, start: 12, end: data.count) { chunkID, chunkData in
            switch chunkID {
            case "anih":
                aniHeader = try parseANIHeader(chunkData)
                
            case "rate":
                rateTable = parseUInt32Array(chunkData)
                
            case "seq ":
                seqTable = parseUInt32Array(chunkData)
                
            case "INAM":
                title = parseZString(chunkData)
                
            case "IART":
                author = parseZString(chunkData)
                
            case "icon":
                if let cursorData = try? parseCUR(chunkData) {
                    frames.append(cursorData)
                }
                
            default:
                break
            }
        }
        
        guard let header = aniHeader else {
            throw ParseError.invalidHeader("Missing anih header in ANI file")
        }
        guard !frames.isEmpty else {
            throw ParseError.corruptedImageData("No valid frames found in ANI file")
        }
        
        let defaultFrameRate = Double(header.jifRate) / 60.0
        
        let perFrameRates = rateTable?.map { Double($0) / 60.0 }
        
        let sequence = seqTable?.map { Int($0) }
        
        return AnimatedCursorData(
            frames: frames,
            frameRate: defaultFrameRate > 0 ? defaultFrameRate : 1.0 / 60.0,
            perFrameRates: perFrameRates,
            sequence: sequence,
            stepCount: Int(header.cSteps),
            title: title,
            author: author
        )
    }
    
    
    private struct ANIHeader {
        let cbSizeof: UInt32
        let cFrames: UInt32
        let cSteps: UInt32
        let cx: UInt32
        let cy: UInt32
        let cBitCount: UInt32
        let cPlanes: UInt32
        let jifRate: UInt32
        let flags: UInt32
    }
    
    private static func parseANIHeader(_ data: Data) throws -> ANIHeader {
        guard data.count >= 36 else { throw ParseError.truncatedFile }
        return ANIHeader(
            cbSizeof:  readUInt32(data, offset: 0),
            cFrames:   readUInt32(data, offset: 4),
            cSteps:    readUInt32(data, offset: 8),
            cx:        readUInt32(data, offset: 12),
            cy:        readUInt32(data, offset: 16),
            cBitCount: readUInt32(data, offset: 20),
            cPlanes:   readUInt32(data, offset: 24),
            jifRate:   readUInt32(data, offset: 28),
            flags:     readUInt32(data, offset: 32)
        )
    }
    
    private static func parseRIFFChunks(
        data: Data,
        start: Int,
        end: Int,
        handler: (String, Data) throws -> Void
    ) throws {
        var offset = start
        
        while offset + 8 <= end {
            guard let chunkID = String(data: data[offset..<(offset + 4)], encoding: .ascii) else {
                offset += 2
                continue
            }
            let chunkSize = Int(readUInt32(data, offset: offset + 4))
            let chunkDataStart = offset + 8
            let chunkDataEnd = min(chunkDataStart + chunkSize, end)
            
            guard chunkDataEnd <= data.count else { break }
            
            if chunkID == "LIST" {
                if chunkSize >= 4 {
                    let listType = String(data: data[chunkDataStart..<(chunkDataStart + 4)], encoding: .ascii) ?? ""
                    try parseRIFFChunks(data: data, start: chunkDataStart + 4, end: chunkDataEnd, handler: handler)
                    _ = listType
                }
            } else {
                let chunkData = Data(data[chunkDataStart..<chunkDataEnd])
                try handler(chunkID, chunkData)
            }
            
            offset = chunkDataEnd
            if chunkSize % 2 != 0 { offset += 1 }
        }
    }
    
    private static func parseUInt32Array(_ data: Data) -> [UInt32] {
        var result: [UInt32] = []
        var offset = 0
        while offset + 4 <= data.count {
            result.append(readUInt32(data, offset: offset))
            offset += 4
        }
        return result
    }
    
    private static func parseZString(_ data: Data) -> String? {
        if let nullIdx = data.firstIndex(of: 0) {
            return String(data: data[data.startIndex..<nullIdx], encoding: .utf8)
                ?? String(data: data[data.startIndex..<nullIdx], encoding: .ascii)
        }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii)
    }
    
    
    private static func decodeImageData(_ data: Data, expectedWidth: Int, expectedHeight: Int) throws -> NSBitmapImageRep {
        if data.count >= 8 && data[data.startIndex] == 0x89
            && data[data.startIndex + 1] == 0x50
            && data[data.startIndex + 2] == 0x4E
            && data[data.startIndex + 3] == 0x47
        {
            return try decodePNG(data)
        }
        
        return try decodeBMPDIB(data, expectedWidth: expectedWidth, expectedHeight: expectedHeight)
    }
    
    private static func decodePNG(_ data: Data) throws -> NSBitmapImageRep {
        guard let rep = NSBitmapImageRep(data: data) else {
            throw ParseError.corruptedImageData("Failed to decode PNG data")
        }
        return rep
    }
    
    private static func decodeBMPDIB(_ data: Data, expectedWidth: Int, expectedHeight: Int) throws -> NSBitmapImageRep {
        guard data.count >= 40 else { throw ParseError.truncatedFile }
        
        let biSize = Int(readUInt32(data, offset: 0))
        let biWidth = Int(Int32(bitPattern: readUInt32(data, offset: 4)))
        let biBitCount = Int(readUInt16(data, offset: 14))
        let biCompression = readUInt32(data, offset: 16)
        
        let biHeight = Int(Int32(bitPattern: readUInt32(data, offset: 8)))
        let actualHeight = abs(biHeight) / 2
        let actualWidth = biWidth > 0 ? biWidth : expectedWidth
        
        if biBitCount == 32 && biCompression == 0 {
            return try decode32bppBGRA(data, headerSize: biSize, width: actualWidth, height: actualHeight)
        }
        
        return try decodeBMPViaFullFile(data, expectedWidth: actualWidth, expectedHeight: actualHeight, biBitCount: biBitCount, headerSize: biSize)
    }
    
    private static func decode32bppBGRA(_ data: Data, headerSize: Int, width: Int, height: Int) throws -> NSBitmapImageRep {
        guard width > 0 && height > 0 else {
            throw ParseError.corruptedImageData("Invalid dimensions: \(width)x\(height)")
        }
        
        let rowBytes = width * 4
        let xorDataSize = rowBytes * height
        
        guard headerSize + xorDataSize <= data.count else {
            throw ParseError.truncatedFile
        }
        
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: .alphaNonpremultiplied,
            bytesPerRow: rowBytes,
            bitsPerPixel: 32
        ) else {
            throw ParseError.corruptedImageData("Failed to create bitmap rep")
        }
        
        guard let bitmapData = rep.bitmapData else {
            throw ParseError.corruptedImageData("Failed to get bitmap data pointer")
        }
        
        var hasAnyAlpha = false
        
        for y in 0..<height {
            let srcRow = height - 1 - y
            let srcOffset = data.startIndex + headerSize + srcRow * rowBytes
            let dstOffset = y * rowBytes
            
            for x in 0..<width {
                let srcPixel = srcOffset + x * 4
                guard srcPixel + 3 < data.endIndex else { continue }
                
                let b = data[srcPixel]
                let g = data[srcPixel + 1]
                let r = data[srcPixel + 2]
                let a = data[srcPixel + 3]
                
                if a > 0 { hasAnyAlpha = true }
                
                let dstIdx = dstOffset + x * 4
                bitmapData[dstIdx]     = r
                bitmapData[dstIdx + 1] = g
                bitmapData[dstIdx + 2] = b
                bitmapData[dstIdx + 3] = a
            }
        }
        
        if !hasAnyAlpha {
            let andMaskRowBytes = ((width + 31) / 32) * 4
            let andMaskStart = data.startIndex + headerSize + xorDataSize
            let andMaskSize = andMaskRowBytes * height
            
            if andMaskStart + andMaskSize <= data.endIndex {
                for y in 0..<height {
                    let srcRow = height - 1 - y
                    let maskOffset = andMaskStart + srcRow * andMaskRowBytes
                    let dstOffset = y * rowBytes
                    
                    for x in 0..<width {
                        let byteIdx = maskOffset + x / 8
                        guard byteIdx < data.endIndex else { continue }
                        let bitIdx = 7 - (x % 8)
                        let isTransparent = (data[byteIdx] >> bitIdx) & 1
                        
                        let dstIdx = dstOffset + x * 4
                        bitmapData[dstIdx + 3] = isTransparent == 1 ? 0 : 255
                    }
                }
            } else {
                for y in 0..<height {
                    let dstOffset = y * rowBytes
                    for x in 0..<width {
                        bitmapData[dstOffset + x * 4 + 3] = 255
                    }
                }
            }
        }
        
        return rep
    }
    
    private static func decodeBMPViaFullFile(_ data: Data, expectedWidth: Int, expectedHeight: Int, biBitCount: Int, headerSize: Int) throws -> NSBitmapImageRep {
        var mutableData = Data(data)
        
        let actualHeight = Int32(expectedHeight)
        withUnsafeBytes(of: actualHeight.littleEndian) { bytes in
            mutableData.replaceSubrange(8..<12, with: bytes)
        }
        
        let colorTableEntries: Int
        if biBitCount <= 8 {
            let biClrUsed = Int(readUInt32(data, offset: 32))
            colorTableEntries = biClrUsed > 0 ? biClrUsed : (1 << biBitCount)
        } else {
            colorTableEntries = 0
        }
        let colorTableSize = colorTableEntries * 4
        
        let pixelDataOffset = 14 + headerSize + colorTableSize
        
        let rowBits = expectedWidth * biBitCount
        let rowBytes = ((rowBits + 31) / 32) * 4
        let pixelDataSize = rowBytes * expectedHeight
        
        let xorDataEnd = headerSize + colorTableSize + pixelDataSize
        if xorDataEnd < mutableData.count {
            mutableData = mutableData[mutableData.startIndex..<(mutableData.startIndex + xorDataEnd)]
        }
        
        var bmpFile = Data()
        bmpFile.append(contentsOf: [0x42, 0x4D])
        
        let fileSize = UInt32(14 + mutableData.count)
        appendLEUInt32(&bmpFile, fileSize)
        
        appendLEUInt16(&bmpFile, 0)
        appendLEUInt16(&bmpFile, 0)
        
        appendLEUInt32(&bmpFile, UInt32(pixelDataOffset))
        
        bmpFile.append(mutableData)
        
        guard let rep = NSBitmapImageRep(data: bmpFile) else {
            throw ParseError.corruptedImageData("NSBitmapImageRep failed to decode BMP")
        }
        
        return rep
    }
    
    
    private static func readUInt16(_ data: Data, offset: Int) -> UInt16 {
        let idx = data.startIndex + offset
        guard idx + 1 < data.endIndex else { return 0 }
        return UInt16(data[idx]) | (UInt16(data[idx + 1]) << 8)
    }
    
    private static func readUInt32(_ data: Data, offset: Int) -> UInt32 {
        let idx = data.startIndex + offset
        guard idx + 3 < data.endIndex else { return 0 }
        return UInt32(data[idx])
            | (UInt32(data[idx + 1]) << 8)
            | (UInt32(data[idx + 2]) << 16)
            | (UInt32(data[idx + 3]) << 24)
    }
    
    private static func appendLEUInt16(_ data: inout Data, _ value: UInt16) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }
    
    private static func appendLEUInt32(_ data: inout Data, _ value: UInt32) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }
}
