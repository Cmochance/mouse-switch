import Foundation
import CoreGraphics
import ImageIO

enum CursorParseError: LocalizedError {
    case invalidHeader(String)
    case noValidFrames
    case unsupportedDIBFormat(String)
    case corruptedData(String)

    var errorDescription: String? {
        switch self {
        case .invalidHeader(let msg): return "无效的光标文件头: \(msg)"
        case .noValidFrames: return "未能在光标文件中解析出有效图像帧"
        case .unsupportedDIBFormat(let msg): return "不支持的位图格式: \(msg)"
        case .corruptedData(let msg): return "光标文件数据损坏: \(msg)"
        }
    }
}

/// Binary reader helper for little-endian Windows structures
struct BinaryReader {
    let data: Data
    private(set) var offset: Int = 0

    init(data: Data, offset: Int = 0) {
        self.data = data
        self.offset = offset
    }

    var remaining: Int {
        max(0, data.count - offset)
    }

    mutating func seek(to newOffset: Int) throws {
        guard newOffset >= 0 && newOffset <= data.count else {
            throw CursorParseError.corruptedData("偏移量越界 (\(newOffset) / \(data.count))")
        }
        offset = newOffset
    }

    mutating func skip(_ count: Int) throws {
        try seek(to: offset + count)
    }

    mutating func readUInt8() throws -> UInt8 {
        guard offset + 1 <= data.count else {
            throw CursorParseError.corruptedData("读取 UInt8 越界")
        }
        let val = data[data.startIndex + offset]
        offset += 1
        return val
    }

    mutating func readUInt16LE() throws -> UInt16 {
        guard offset + 2 <= data.count else {
            throw CursorParseError.corruptedData("读取 UInt16 越界")
        }
        let b0 = UInt16(data[data.startIndex + offset])
        let b1 = UInt16(data[data.startIndex + offset + 1])
        offset += 2
        return b0 | (b1 << 8)
    }

    mutating func readInt16LE() throws -> Int16 {
        Int16(bitPattern: try readUInt16LE())
    }

    mutating func readUInt32LE() throws -> UInt32 {
        guard offset + 4 <= data.count else {
            throw CursorParseError.corruptedData("读取 UInt32 越界")
        }
        let b0 = UInt32(data[data.startIndex + offset])
        let b1 = UInt32(data[data.startIndex + offset + 1])
        let b2 = UInt32(data[data.startIndex + offset + 2])
        let b3 = UInt32(data[data.startIndex + offset + 3])
        offset += 4
        return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
    }

    mutating func readInt32LE() throws -> Int32 {
        Int32(bitPattern: try readUInt32LE())
    }

    mutating func readFourCC() throws -> String {
        guard offset + 4 <= data.count else {
            throw CursorParseError.corruptedData("读取 FourCC 越界")
        }
        let slice = data.subdata(in: (data.startIndex + offset)..<(data.startIndex + offset + 4))
        offset += 4
        return String(bytes: slice, encoding: .ascii) ?? "????"
    }

    mutating func readBytes(_ count: Int) throws -> Data {
        guard count >= 0, offset + count <= data.count else {
            throw CursorParseError.corruptedData("读取 \(count) 字节越界")
        }
        let slice = data.subdata(in: (data.startIndex + offset)..<(data.startIndex + offset + count))
        offset += count
        return slice
    }
}

/// Pure-Swift parser for Windows `.cur` (static) and `.ani` (animated RIFF ACON) cursor files.
enum WinCursorParser {
    /// Maximum hardware cursor animation frames supported by macOS `CGSRegisterCursorWithImages`
    static let maxMacOSFrames = 24

    /// Auto-detect and parse `.cur`, `.ani`, or `.ico` file from URL
    static func parse(fileURL: URL) throws -> ParsedCursor {
        let data = try Data(contentsOf: fileURL)
        return try parse(data: data, fileName: fileURL.lastPathComponent)
    }

    /// Auto-detect and parse `.cur`, `.ani`, or `.ico` from raw `Data`
    static func parse(data: Data, fileName: String) throws -> ParsedCursor {
        guard data.count >= 12 else {
            throw CursorParseError.invalidHeader("文件过小 (\(data.count) bytes)")
        }

        // Check if RIFF ACON (.ani)
        if let magic = String(bytes: data.subdata(in: 0..<4), encoding: .ascii), magic == "RIFF" {
            return try parseANI(data: data, fileName: fileName)
        }

        // Otherwise parse as .cur / .ico
        return try parseCUR(data: data, fileName: fileName)
    }

    // MARK: - .CUR / .ICO Parser

    private struct IconDirEntry {
        let width: Int
        let height: Int
        let colorCount: UInt8
        let hotspotX: UInt16
        let hotspotY: UInt16
        let bytesInRes: Int
        let imageOffset: Int
        let isCur: Bool
    }

    static func parseCUR(data: Data, fileName: String) throws -> ParsedCursor {
        var reader = BinaryReader(data: data)
        let reserved = try reader.readUInt16LE()
        let type = try reader.readUInt16LE()
        let count = Int(try reader.readUInt16LE())

        guard reserved == 0 && (type == 1 || type == 2) && count > 0 && count <= 256 else {
            throw CursorParseError.invalidHeader("不是有效的 .cur/.ico 文件 (reserved=\(reserved), type=\(type), count=\(count))")
        }

        let isCur = (type == 2)
        var entries: [IconDirEntry] = []

        for _ in 0..<count {
            let rawW = Int(try reader.readUInt8())
            let rawH = Int(try reader.readUInt8())
            let colorCount = try reader.readUInt8()
            _ = try reader.readUInt8() // reserved
            let field4 = try reader.readUInt16LE()
            let field6 = try reader.readUInt16LE()
            let bytesInRes = Int(try reader.readUInt32LE())
            let imageOffset = Int(try reader.readUInt32LE())

            let w = rawW == 0 ? 256 : rawW
            let h = rawH == 0 ? 256 : rawH

            entries.append(
                IconDirEntry(
                    width: w,
                    height: h,
                    colorCount: colorCount,
                    hotspotX: isCur ? field4 : UInt16(w / 2),
                    hotspotY: isCur ? field6 : UInt16(h / 2),
                    bytesInRes: bytesInRes,
                    imageOffset: imageOffset,
                    isCur: isCur
                )
            )
        }

        // Sort entries: prefer reasonable cursor resolutions (32..128) with highest pixel area and largest byte payload
        let sortedEntries = entries.sorted { a, b in
            let areaA = a.width * a.height
            let areaB = b.width * b.height
            if areaA != areaB {
                return areaA > areaB
            }
            return a.bytesInRes > b.bytesInRes
        }

        for entry in sortedEntries {
            guard entry.imageOffset >= 0,
                  entry.bytesInRes > 0,
                  entry.imageOffset + entry.bytesInRes <= data.count else {
                continue
            }
            let slice = data.subdata(in: entry.imageOffset..<(entry.imageOffset + entry.bytesInRes))
            if let cgImage = try? decodeCursorImageSlice(slice, fallbackWidth: entry.width, fallbackHeight: entry.height),
               let pngData = ParsedCursor.encodePNG(cgImage) {
                let actualW = cgImage.width
                let actualH = cgImage.height
                // Scale hotspot if entry header dimensions differed from actual decoded image dimensions
                let scaleX = entry.width > 0 ? Double(actualW) / Double(entry.width) : 1.0
                let scaleY = entry.height > 0 ? Double(actualH) / Double(entry.height) : 1.0
                let hx = min(Double(actualW), max(0.0, Double(entry.hotspotX) * scaleX))
                let hy = min(Double(actualH), max(0.0, Double(entry.hotspotY) * scaleY))

                return ParsedCursor(
                    sourceFileName: fileName,
                    framePNGs: [pngData],
                    pixelWidth: actualW,
                    pixelHeight: actualH,
                    hotspotX: hx,
                    hotspotY: hy,
                    frameDuration: 0.0
                )
            }
        }

        throw CursorParseError.noValidFrames
    }

    /// Decode an individual image payload slice from a `.cur`/`.ico` entry (either embedded PNG or DIB BMP)
    private static func decodeCursorImageSlice(_ slice: Data, fallbackWidth: Int, fallbackHeight: Int) throws -> CGImage {
        // 1. Check PNG signature: 89 50 4E 47 0D 0A 1A 0A
        let pngSig: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        if slice.count >= 8 {
            let prefix = [UInt8](slice.prefix(8))
            if prefix == pngSig {
                if let src = CGImageSourceCreateWithData(slice as CFData, nil),
                   let img = CGImageSourceCreateImageAtIndex(src, 0, nil) {
                    return img
                }
            }
        }

        // 2. Otherwise decode DIB (BITMAPINFOHEADER + XOR bitmap + AND mask)
        return try decodeDIBSlice(slice, fallbackWidth: fallbackWidth, fallbackHeight: fallbackHeight)
    }

    /// Pure-Swift decoder for Windows Cursor/Icon DIB (`BITMAPINFOHEADER` with XOR + AND masks)
    private static func decodeDIBSlice(_ slice: Data, fallbackWidth: Int, fallbackHeight: Int) throws -> CGImage {
        var reader = BinaryReader(data: slice)
        let headerSize = Int(try reader.readUInt32LE())
        guard headerSize >= 40 && headerSize <= slice.count else {
            throw CursorParseError.unsupportedDIBFormat("DIB Header 大小异常 (\(headerSize))")
        }

        let rawWidth = Int(try reader.readInt32LE())
        let rawHeight = Int(try reader.readInt32LE())
        _ = try reader.readUInt16LE() // planes
        let bitCount = Int(try reader.readUInt16LE())
        let compression = try reader.readUInt32LE()
        _ = try reader.readUInt32LE() // sizeImage
        _ = try reader.readInt32LE()  // xPelsPerMeter
        _ = try reader.readInt32LE()  // yPelsPerMeter
        let clrUsed = Int(try reader.readUInt32LE())
        _ = try reader.readUInt32LE() // clrImportant

        let isBottomUp = rawHeight >= 0
        let width = rawWidth > 0 ? rawWidth : fallbackWidth
        // In .cur/.ico DIBs, height in header is doubled (XOR height + AND height)
        let absHeight = abs(rawHeight)
        let height = absHeight >= 2 ? (absHeight / 2) : fallbackHeight

        guard width > 0 && width <= 1024 && height > 0 && height <= 1024 else {
            throw CursorParseError.unsupportedDIBFormat("尺寸超出范围 (\(width)x\(height))")
        }

        // Seek to end of BITMAPINFOHEADER
        try reader.seek(to: headerSize)

        // Read optional bitfields if BI_BITFIELDS (compression == 3)
        var rMask: UInt32 = 0x00FF0000
        var gMask: UInt32 = 0x0000FF00
        var bMask: UInt32 = 0x000000FF
        let aMask: UInt32 = 0xFF000000
        if compression == 3 && headerSize == 40 && reader.remaining >= 12 {
            rMask = try reader.readUInt32LE()
            gMask = try reader.readUInt32LE()
            bMask = try reader.readUInt32LE()
        }

        // Read color palette for <= 8-bit DIBs
        var palette: [(r: UInt8, g: UInt8, b: UInt8)] = []
        if bitCount <= 8 {
            let numColors = clrUsed > 0 ? clrUsed : (1 << bitCount)
            for _ in 0..<numColors {
                guard reader.remaining >= 4 else { break }
                let b = try reader.readUInt8()
                let g = try reader.readUInt8()
                let r = try reader.readUInt8()
                _ = try reader.readUInt8() // reserved
                palette.append((r: r, g: g, b: b))
            }
        }

        // Row stride of XOR bitmap (padded to 32-bit / 4-byte boundary)
        let xorRowBytes = ((width * bitCount + 31) / 32) * 4
        let xorTotalBytes = xorRowBytes * height
        guard reader.remaining >= xorTotalBytes else {
            throw CursorParseError.corruptedData("XOR 位图数据不足")
        }
        let xorData = try reader.readBytes(xorTotalBytes)

        // Row stride of 1-bit AND mask (padded to 32-bit / 4-byte boundary)
        let andRowBytes = ((width + 31) / 32) * 4
        let andTotalBytes = andRowBytes * height
        let andData: Data? = reader.remaining >= andTotalBytes ? (try? reader.readBytes(andTotalBytes)) : nil

        // Helper to read 1-bit AND mask at (x, dibRow)
        func readAndBit(x: Int, dibRow: Int) -> UInt8 {
            guard let andData = andData else { return 0 }
            let byteIndex = dibRow * andRowBytes + (x >> 3)
            guard byteIndex < andData.count else { return 0 }
            let byteVal = andData[andData.startIndex + byteIndex]
            let bitOffset = 7 - (x & 7)
            return (byteVal >> bitOffset) & 1
        }

        // Output RGBA8888 buffer (top-down for CGImage)
        var rgba = [UInt8](repeating: 0, count: width * height * 4)

        // For 32-bit images, detect if the alpha channel is actually populated
        var hasNonZeroAlpha = false
        if bitCount == 32 {
            for row in 0..<height {
                let rowStart = row * xorRowBytes
                for x in 0..<width {
                    let pxOffset = rowStart + x * 4
                    let a = xorData[xorData.startIndex + pxOffset + 3]
                    if a != 0 {
                        hasNonZeroAlpha = true
                        break
                    }
                }
                if hasNonZeroAlpha { break }
            }
        }

        for y in 0..<height {
            // Top-down y (0 is top row) maps to bottom-up dibRow
            let dibRow = isBottomUp ? (height - 1 - y) : y
            let xorRowStart = dibRow * xorRowBytes
            let outRowStart = y * width * 4

            for x in 0..<width {
                let outIdx = outRowStart + x * 4
                let andBit = readAndBit(x: x, dibRow: dibRow)

                var r: UInt8 = 0
                var g: UInt8 = 0
                var b: UInt8 = 0
                var a: UInt8 = 255

                switch bitCount {
                case 32:
                    let px = xorRowStart + x * 4
                    if compression == 3 {
                        let rawVal = UInt32(xorData[xorData.startIndex + px])
                            | (UInt32(xorData[xorData.startIndex + px + 1]) << 8)
                            | (UInt32(xorData[xorData.startIndex + px + 2]) << 16)
                            | (UInt32(xorData[xorData.startIndex + px + 3]) << 24)
                        r = extractChannel(rawVal, mask: rMask)
                        g = extractChannel(rawVal, mask: gMask)
                        b = extractChannel(rawVal, mask: bMask)
                        a = hasNonZeroAlpha ? extractChannel(rawVal, mask: aMask) : (andBit == 0 ? 255 : 0)
                    } else {
                        b = xorData[xorData.startIndex + px]
                        g = xorData[xorData.startIndex + px + 1]
                        r = xorData[xorData.startIndex + px + 2]
                        let rawA = xorData[xorData.startIndex + px + 3]
                        if hasNonZeroAlpha {
                            a = rawA
                        } else {
                            a = (andBit == 0) ? 255 : 0
                        }
                    }

                case 24:
                    let px = xorRowStart + x * 3
                    b = xorData[xorData.startIndex + px]
                    g = xorData[xorData.startIndex + px + 1]
                    r = xorData[xorData.startIndex + px + 2]
                    a = (andBit == 0) ? 255 : 0

                case 16:
                    let px = xorRowStart + x * 2
                    let v = UInt16(xorData[xorData.startIndex + px]) | (UInt16(xorData[xorData.startIndex + px + 1]) << 8)
                    b = UInt8(((v & 0x001F) * 255) / 31)
                    g = UInt8((((v >> 5) & 0x001F) * 255) / 31)
                    r = UInt8((((v >> 10) & 0x001F) * 255) / 31)
                    a = (andBit == 0) ? 255 : 0

                case 8:
                    let idx = Int(xorData[xorData.startIndex + xorRowStart + x])
                    if idx < palette.count {
                        r = palette[idx].r
                        g = palette[idx].g
                        b = palette[idx].b
                    }
                    a = (andBit == 0) ? 255 : 0

                case 4:
                    let byteVal = xorData[xorData.startIndex + xorRowStart + (x >> 1)]
                    let idx = Int((x & 1) == 0 ? (byteVal >> 4) : (byteVal & 0x0F))
                    if idx < palette.count {
                        r = palette[idx].r
                        g = palette[idx].g
                        b = palette[idx].b
                    }
                    a = (andBit == 0) ? 255 : 0

                case 1:
                    let byteVal = xorData[xorData.startIndex + xorRowStart + (x >> 3)]
                    let xorBit = (byteVal >> (7 - (x & 7))) & 1
                    if andBit == 0 {
                        let idx = Int(xorBit)
                        if idx < palette.count {
                            r = palette[idx].r
                            g = palette[idx].g
                            b = palette[idx].b
                        } else {
                            let v: UInt8 = xorBit == 1 ? 255 : 0
                            r = v; g = v; b = v
                        }
                        a = 255
                    } else if xorBit == 1 {
                        // Windows monochrome XOR screen-invert pixel (e.g. I-Beam or Crosshair)
                        // Render as semi-opaque dark pixel with subtle contrast so it stays visible on macOS
                        r = 32; g = 32; b = 32; a = 220
                    } else {
                        a = 0
                    }

                default:
                    throw CursorParseError.unsupportedDIBFormat("不支持的位深: \(bitCount)-bit")
                }

                // Premultiply alpha for CGImage (.premultipliedLast)
                let af = UInt16(a)
                rgba[outIdx]     = UInt8((UInt16(r) * af + 127) / 255)
                rgba[outIdx + 1] = UInt8((UInt16(g) * af + 127) / 255)
                rgba[outIdx + 2] = UInt8((UInt16(b) * af + 127) / 255)
                rgba[outIdx + 3] = a
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let provider = CGDataProvider(data: Data(rgba) as CFData),
              let cgImage = CGImage(
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: width * 4,
                  space: colorSpace,
                  bitmapInfo: bitmapInfo,
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: true,
                  intent: .defaultIntent
              ) else {
            throw CursorParseError.corruptedData("无法创建 CGImage")
        }

        return cgImage
    }

    private static func extractChannel(_ value: UInt32, mask: UInt32) -> UInt8 {
        guard mask != 0 else { return 0 }
        let shift = mask.trailingZeroBitCount
        let maxVal = mask >> shift
        let raw = (value & mask) >> shift
        return UInt8((UInt64(raw) * 255) / UInt64(maxVal))
    }

    // MARK: - .ANI (RIFF ACON) Animated Cursor Parser

    static func parseANI(data: Data, fileName: String) throws -> ParsedCursor {
        var reader = BinaryReader(data: data)
        let riff = try reader.readFourCC()
        _ = try reader.readUInt32LE() // riffSize
        let formType = try reader.readFourCC()

        guard riff == "RIFF" && formType == "ACON" else {
            throw CursorParseError.invalidHeader("不是有效的 RIFF ACON (.ani) 文件")
        }

        var defaultJiffies: UInt32 = 6 // Default 6/60s = 0.1s per frame
        var rates: [UInt32] = []
        var sequence: [Int] = []
        var rawFrames: [ParsedCursor] = []

        func parseChunks(until endOffset: Int) throws {
            while reader.offset + 8 <= endOffset {
                let chunkID = try reader.readFourCC()
                let chunkSize = Int(try reader.readUInt32LE())
                let chunkStart = reader.offset
                let chunkEnd = min(endOffset, chunkStart + chunkSize)

                switch chunkID {
                case "anih":
                    if chunkSize >= 36 {
                        _ = try reader.readUInt32LE() // cbSize
                        _ = try reader.readUInt32LE() // cFrames
                        _ = try reader.readUInt32LE() // cSteps
                        _ = try reader.readUInt32LE() // iWidth
                        _ = try reader.readUInt32LE() // iHeight
                        _ = try reader.readUInt32LE() // iBitCount
                        _ = try reader.readUInt32LE() // cPlanes
                        let dispRate = try reader.readUInt32LE()
                        if dispRate > 0 {
                            defaultJiffies = dispRate
                        }
                    }

                case "rate":
                    let count = chunkSize / 4
                    rates.removeAll(keepingCapacity: true)
                    for _ in 0..<count {
                        if reader.offset + 4 <= chunkEnd {
                            rates.append(try reader.readUInt32LE())
                        }
                    }

                case "seq ":
                    let count = chunkSize / 4
                    sequence.removeAll(keepingCapacity: true)
                    for _ in 0..<count {
                        if reader.offset + 4 <= chunkEnd {
                            sequence.append(Int(try reader.readUInt32LE()))
                        }
                    }

                case "LIST":
                    if reader.offset + 4 <= chunkEnd {
                        let listType = try reader.readFourCC()
                        if listType == "fram" {
                            try parseChunks(until: chunkEnd)
                        }
                    }

                case "icon":
                    let iconData = data.subdata(in: chunkStart..<chunkEnd)
                    if let parsedFrame = try? parseCUR(data: iconData, fileName: fileName) {
                        rawFrames.append(parsedFrame)
                    }

                default:
                    break
                }

                // RIFF chunks are padded to 2-byte word boundaries
                let alignedEnd = chunkEnd + (chunkSize & 1)
                try reader.seek(to: min(endOffset, alignedEnd))
            }
        }

        try parseChunks(until: data.count)

        guard let firstFrame = rawFrames.first else {
            throw CursorParseError.noValidFrames
        }

        // Apply `seq ` ordering if present
        var orderedSteps: [ParsedCursor] = []
        if !sequence.isEmpty {
            for idx in sequence {
                if idx >= 0 && idx < rawFrames.count {
                    orderedSteps.append(rawFrames[idx])
                }
            }
        }
        if orderedSteps.isEmpty {
            orderedSteps = rawFrames
        }

        // Expand variable `rate` steps into uniform time slices if needed
        var expandedFrames: [Data] = []
        var baseJiffies = Double(max(1, defaultJiffies))

        if rates.count == orderedSteps.count && !rates.isEmpty {
            let cleanRates = rates.map { max(1, $0) }
            let minRate = cleanRates.min() ?? defaultJiffies
            let maxRate = cleanRates.max() ?? defaultJiffies

            if minRate == maxRate {
                baseJiffies = Double(minRate)
                expandedFrames = orderedSteps.compactMap { $0.framePNGs.first }
            } else {
                // Variable rate: expand each step proportionally up to a reasonable cap
                baseJiffies = Double(max(1, minRate))
                for (i, step) in orderedSteps.enumerated() {
                    guard let png = step.framePNGs.first else { continue }
                    let repeats = min(8, max(1, Int((Double(cleanRates[i]) / baseJiffies).rounded())))
                    for _ in 0..<repeats {
                        expandedFrames.append(png)
                    }
                }
            }
        } else {
            expandedFrames = orderedSteps.compactMap { $0.framePNGs.first }
        }

        guard !expandedFrames.isEmpty else {
            throw CursorParseError.noValidFrames
        }

        var frameDuration = max(0.016, baseJiffies / 60.0)
        let totalDuration = frameDuration * Double(expandedFrames.count)

        // macOS `CGSRegisterCursorWithImages` supports at most 24 frames in a sprite sheet.
        // Resample evenly to 24 frames if larger, preserving total animation cycle time.
        if expandedFrames.count > maxMacOSFrames {
            var resampled: [Data] = []
            for i in 0..<maxMacOSFrames {
                let srcIdx = Int((Double(i) * Double(expandedFrames.count) / Double(maxMacOSFrames)).rounded(.down))
                resampled.append(expandedFrames[min(expandedFrames.count - 1, srcIdx)])
            }
            expandedFrames = resampled
            frameDuration = max(0.016, totalDuration / Double(maxMacOSFrames))
        }

        return ParsedCursor(
            sourceFileName: fileName,
            framePNGs: expandedFrames,
            pixelWidth: firstFrame.pixelWidth,
            pixelHeight: firstFrame.pixelHeight,
            hotspotX: firstFrame.hotspotX,
            hotspotY: firstFrame.hotspotY,
            frameDuration: expandedFrames.count > 1 ? frameDuration : 0.0
        )
    }
}
