import Foundation
import CoreGraphics
import AppKit

/// Generates genuine binary Windows `.cur`, `.ani` (RIFF ACON), and `install.inf` files
/// for instant testing, demonstration, and verification of the Windows-to-macOS pipeline.
enum DemoWinCursorPackGenerator {

    /// Writes a complete sample Windows cursor pack ("CyberNeon Windows Pack") to the given directory
    /// and returns the directory URL.
    static func generateSampleWindowsPack(in targetDir: URL) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: targetDir, withIntermediateDirectories: true)

        // 1. Normal Select (normal.cur) - Neon cyan pointer arrow with dark glow border
        let arrowImg = renderArrowCursor(
            size: 64,
            fillColor: CGColor(red: 0.05, green: 0.92, blue: 0.98, alpha: 1.0),
            strokeColor: CGColor(red: 0.06, green: 0.12, blue: 0.25, alpha: 1.0)
        )
        let arrowCur = try buildCURData(from: [arrowImg], hotspotX: 6, hotspotY: 6)
        try arrowCur.write(to: targetDir.appendingPathComponent("normal.cur"))

        // 2. Link Select (link.cur) - Neon magenta/violet pointer with badge
        let linkImg = renderHandLinkCursor(size: 64)
        let linkCur = try buildCURData(from: [linkImg], hotspotX: 18, hotspotY: 8)
        try linkCur.write(to: targetDir.appendingPathComponent("link.cur"))

        // 3. Text Select (ibeam.cur) - Crisp glowing cyan I-Beam
        let ibeamImg = renderIBeamCursor(size: 64)
        let ibeamCur = try buildCURData(from: [ibeamImg], hotspotX: 32, hotspotY: 32)
        try ibeamCur.write(to: targetDir.appendingPathComponent("ibeam.cur"))

        // 4. Precision Select (cross.cur) - Precision crosshair
        let crossImg = renderCrosshairCursor(size: 64)
        let crossCur = try buildCURData(from: [crossImg], hotspotX: 32, hotspotY: 32)
        try crossCur.write(to: targetDir.appendingPathComponent("cross.cur"))

        // 5. Unavailable (unavail.cur) - Red neon prohibition sign
        let noImg = renderNotAllowedCursor(size: 64)
        let noCur = try buildCURData(from: [noImg], hotspotX: 32, hotspotY: 32)
        try noCur.write(to: targetDir.appendingPathComponent("unavail.cur"))

        // 6. Animated Busy Spinner (busy.ani) - 12-frame rotating neon ring (RIFF ACON)
        var busyFrames: [CGImage] = []
        for i in 0..<12 {
            let angle = (Double(i) / 12.0) * (.pi * 2.0)
            busyFrames.append(renderAnimatedRingCursor(size: 64, angle: angle, withArrow: false))
        }
        let busyAni = try buildANIData(frames: busyFrames, hotspotX: 32, hotspotY: 32, jiffiesPerFrame: 3)
        try busyAni.write(to: targetDir.appendingPathComponent("busy.ani"))

        // 7. Animated Working in Background (work.ani) - 12-frame arrow + spinning mini ring
        var workFrames: [CGImage] = []
        for i in 0..<12 {
            let angle = (Double(i) / 12.0) * (.pi * 2.0)
            workFrames.append(renderAnimatedRingCursor(size: 64, angle: angle, withArrow: true))
        }
        let workAni = try buildANIData(frames: workFrames, hotspotX: 6, hotspotY: 6, jiffiesPerFrame: 3)
        try workAni.write(to: targetDir.appendingPathComponent("work.ani"))

        // 8. Vertical Resize (vert.cur) & Horizontal Resize (horz.cur)
        let nsImg = renderResizeCursor(size: 64, horizontal: false)
        let nsCur = try buildCURData(from: [nsImg], hotspotX: 32, hotspotY: 32)
        try nsCur.write(to: targetDir.appendingPathComponent("vert.cur"))

        let weImg = renderResizeCursor(size: 64, horizontal: true)
        let weCur = try buildCURData(from: [weImg], hotspotX: 32, hotspotY: 32)
        try weCur.write(to: targetDir.appendingPathComponent("horz.cur"))

        // 9. Standard Windows `install.inf` file
        let infContent = """
        ; CyberNeon Windows Cursor Theme - Sample Install Script
        [Version]
        signature="$CHICAGO$"

        [DefaultInstall]
        CopyFiles = Scheme.Cur
        AddReg    = Scheme.Reg

        [DestinationDirs]
        Scheme.Cur = 10,"%CUR_DIR%"

        [Scheme.Reg]
        HKCU,"Control Panel\\Cursors\\Schemes","%SCHEME_NAME%",0x00020000,"%10%\\%CUR_DIR%\\%pointer%,%10%\\%CUR_DIR%\\%help%,%10%\\%CUR_DIR%\\%work%,%10%\\%CUR_DIR%\\%busy%,%10%\\%CUR_DIR%\\%cross%,%10%\\%CUR_DIR%\\%Text%,%10%\\%CUR_DIR%\\%Hand%,%10%\\%CUR_DIR%\\%unavailiable%,%10%\\%CUR_DIR%\\%Vert%,%10%\\%CUR_DIR%\\%Horz%,%10%\\%CUR_DIR%\\%Dgn1%,%10%\\%CUR_DIR%\\%Dgn2%,%10%\\%CUR_DIR%\\%move%,%10%\\%CUR_DIR%\\%alternate%,%10%\\%CUR_DIR%\\%link%"

        [Strings]
        CUR_DIR       = "Cursors\\CyberNeon"
        SCHEME_NAME   = "CyberNeon 赛博霓虹 (Win示例包)"
        pointer       = "normal.cur"
        work          = "work.ani"
        busy          = "busy.ani"
        cross         = "cross.cur"
        Text          = "ibeam.cur"
        unavailiable  = "unavail.cur"
        Vert          = "vert.cur"
        Horz          = "horz.cur"
        link          = "link.cur"
        """
        try infContent.write(to: targetDir.appendingPathComponent("install.inf"), atomically: true, encoding: .utf8)

        return targetDir
    }

    // MARK: - Binary .CUR & .ANI Builders

    /// Encodes `CGImage` frames into a classic Windows `.cur` file (`wType = 2`) using standard 32-bit BGRA DIB + 1-bit AND mask
    static func buildCURData(from images: [CGImage], hotspotX: UInt16, hotspotY: UInt16, useDIB: Bool = true) throws -> Data {
        var out = Data()
        let count = UInt16(images.count)

        // ICONDIR header (6 bytes)
        out.appendUInt16LE(0)     // idReserved = 0
        out.appendUInt16LE(2)     // idType = 2 (.CUR)
        out.appendUInt16LE(count) // idCount

        var payloads: [Data] = []
        for img in images {
            if useDIB, let dib = encode32BitDIBSlice(from: img) {
                payloads.append(dib)
            } else if let png = ParsedCursor.encodePNG(img) {
                payloads.append(png)
            } else {
                throw CursorParseError.corruptedData("无法编码光标位图数据")
            }
        }

        var currentOffset = 6 + (16 * images.count)
        for (i, img) in images.enumerated() {
            let payload = payloads[i]
            let wByte = img.width >= 256 ? UInt8(0) : UInt8(img.width)
            let hByte = img.height >= 256 ? UInt8(0) : UInt8(img.height)

            out.append(wByte)
            out.append(hByte)
            out.append(0) // bColorCount
            out.append(0) // bReserved
            out.appendUInt16LE(hotspotX)
            out.appendUInt16LE(hotspotY)
            out.appendUInt32LE(UInt32(payload.count))
            out.appendUInt32LE(UInt32(currentOffset))

            currentOffset += payload.count
        }

        for payload in payloads {
            out.append(payload)
        }

        return out
    }

    /// Encodes a `CGImage` into a genuine Windows Cursor DIB (`BITMAPINFOHEADER` + bottom-up 32-bit BGRA XOR mask + 1-bit AND mask)
    private static func encode32BitDIBSlice(from image: CGImage) -> Data? {
        let w = image.width
        let h = image.height
        guard w > 0 && h > 0 else { return nil }

        // Render top-down RGBA8888 pixels
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &rgba,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        let xorRowBytes = w * 4
        let andRowBytes = ((w + 31) / 32) * 4
        let imageSize = (xorRowBytes + andRowBytes) * h

        var dib = Data(capacity: 40 + imageSize)
        // BITMAPINFOHEADER (40 bytes)
        dib.appendUInt32LE(40)                // biSize
        dib.appendUInt32LE(UInt32(w))         // biWidth
        dib.appendUInt32LE(UInt32(h * 2))     // biHeight (doubled for XOR + AND masks)
        dib.appendUInt16LE(1)                 // biPlanes
        dib.appendUInt16LE(32)                // biBitCount = 32-bit BGRA
        dib.appendUInt32LE(0)                 // biCompression = BI_RGB
        dib.appendUInt32LE(UInt32(imageSize)) // biSizeImage
        dib.appendUInt32LE(0)                 // biXPelsPerMeter
        dib.appendUInt32LE(0)                 // biYPelsPerMeter
        dib.appendUInt32LE(0)                 // biClrUsed
        dib.appendUInt32LE(0)                 // biClrImportant

        // Bottom-up 32-bit BGRA (unpremultiplied) XOR mask
        for dibRow in 0..<h {
            let srcY = h - 1 - dibRow
            let rowStart = srcY * w * 4
            for x in 0..<w {
                let idx = rowStart + x * 4
                let pr = UInt16(rgba[idx])
                let pg = UInt16(rgba[idx + 1])
                let pb = UInt16(rgba[idx + 2])
                let a  = UInt16(rgba[idx + 3])
                let r: UInt8 = a > 0 ? UInt8(min(255, (pr * 255) / a)) : 0
                let g: UInt8 = a > 0 ? UInt8(min(255, (pg * 255) / a)) : 0
                let b: UInt8 = a > 0 ? UInt8(min(255, (pb * 255) / a)) : 0
                dib.append(b)
                dib.append(g)
                dib.append(r)
                dib.append(UInt8(a))
            }
        }

        // Bottom-up 1-bit AND mask (bit=1 when fully transparent, bit=0 when opaque)
        for dibRow in 0..<h {
            let srcY = h - 1 - dibRow
            let rowStart = srcY * w * 4
            var rowBytes = [UInt8](repeating: 0, count: andRowBytes)
            for x in 0..<w {
                let a = rgba[rowStart + x * 4 + 3]
                if a == 0 {
                    rowBytes[x >> 3] |= UInt8(1 << (7 - (x & 7)))
                }
            }
            dib.append(contentsOf: rowBytes)
        }

        return dib
    }

    /// Encodes `CGImage` frames into a binary Windows `.ani` (RIFF ACON) animated cursor file
    static func buildANIData(
        frames: [CGImage],
        hotspotX: UInt16,
        hotspotY: UInt16,
        jiffiesPerFrame: UInt32
    ) throws -> Data {
        let curFrames = try frames.map { try buildCURData(from: [$0], hotspotX: hotspotX, hotspotY: hotspotY) }

        // Build `anih` chunk (36 bytes payload)
        var anihPayload = Data()
        let numFrames = UInt32(curFrames.count)
        anihPayload.appendUInt32LE(36)              // cbSize
        anihPayload.appendUInt32LE(numFrames)       // cFrames
        anihPayload.appendUInt32LE(numFrames)       // cSteps
        anihPayload.appendUInt32LE(0)               // iWidth
        anihPayload.appendUInt32LE(0)               // iHeight
        anihPayload.appendUInt32LE(32)              // iBitCount
        anihPayload.appendUInt32LE(1)               // cPlanes
        anihPayload.appendUInt32LE(jiffiesPerFrame) // iDispRate
        anihPayload.appendUInt32LE(1)               // bfAttributes (AF_ICON = 1)

        // Build `LIST` (`fram`) chunk containing `icon` subchunks
        var framPayload = Data()
        framPayload.appendFourCC("fram")
        for curData in curFrames {
            framPayload.appendFourCC("icon")
            framPayload.appendUInt32LE(UInt32(curData.count))
            framPayload.append(curData)
            if (curData.count & 1) == 1 {
                framPayload.append(0) // 2-byte word alignment
            }
        }

        var aconBody = Data()
        aconBody.appendFourCC("ACON")
        aconBody.appendFourCC("anih")
        aconBody.appendUInt32LE(UInt32(anihPayload.count))
        aconBody.append(anihPayload)

        aconBody.appendFourCC("LIST")
        aconBody.appendUInt32LE(UInt32(framPayload.count))
        aconBody.append(framPayload)

        var riff = Data()
        riff.appendFourCC("RIFF")
        riff.appendUInt32LE(UInt32(aconBody.count))
        riff.append(aconBody)
        return riff
    }

    // MARK: - Vector Drawing Helpers for Demo Cursors

    private static func makeContext(size: Int) -> CGContext {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        // Flip to top-left origin for intuitive cursor drawing
        ctx.translateBy(x: 0, y: CGFloat(size))
        ctx.scaleBy(x: 1.0, y: -1.0)
        return ctx
    }

    private static func renderArrowCursor(size: Int, fillColor: CGColor, strokeColor: CGColor) -> CGImage {
        let ctx = makeContext(size: size)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 6, y: 6))
        path.addLine(to: CGPoint(x: 6, y: 50))
        path.addLine(to: CGPoint(x: 18, y: 39))
        path.addLine(to: CGPoint(x: 27, y: 55))
        path.addLine(to: CGPoint(x: 34, y: 51))
        path.addLine(to: CGPoint(x: 25, y: 35))
        path.addLine(to: CGPoint(x: 41, y: 35))
        path.closeSubpath()

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 2), blur: 5, color: fillColor)
        ctx.addPath(path)
        ctx.setFillColor(fillColor)
        ctx.fillPath()
        ctx.restoreGState()

        ctx.addPath(path)
        ctx.setStrokeColor(strokeColor)
        ctx.setLineWidth(3.0)
        ctx.setLineJoin(.round)
        ctx.strokePath()

        return ctx.makeImage()!
    }

    private static func renderHandLinkCursor(size: Int) -> CGImage {
        let ctx = makeContext(size: size)
        let magenta = CGColor(red: 0.96, green: 0.24, blue: 0.78, alpha: 1.0)
        let dark = CGColor(red: 0.14, green: 0.05, blue: 0.22, alpha: 1.0)

        let path = CGMutablePath()
        path.move(to: CGPoint(x: 18, y: 8))
        path.addLine(to: CGPoint(x: 18, y: 42))
        path.addLine(to: CGPoint(x: 28, y: 33))
        path.addLine(to: CGPoint(x: 44, y: 33))
        path.closeSubpath()

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 2), blur: 5, color: magenta)
        ctx.addPath(path)
        ctx.setFillColor(magenta)
        ctx.fillPath()
        ctx.restoreGState()

        ctx.addPath(path)
        ctx.setStrokeColor(dark)
        ctx.setLineWidth(3.0)
        ctx.setLineJoin(.round)
        ctx.strokePath()

        // Glowing link ring at tip
        let ringRect = CGRect(x: 11, y: 3, width: 14, height: 14)
        ctx.setStrokeColor(CGColor(red: 1.0, green: 0.85, blue: 0.2, alpha: 1.0))
        ctx.setLineWidth(2.5)
        ctx.strokeEllipse(in: ringRect)

        return ctx.makeImage()!
    }

    private static func renderIBeamCursor(size: Int) -> CGImage {
        let ctx = makeContext(size: size)
        let cyan = CGColor(red: 0.08, green: 0.92, blue: 0.98, alpha: 1.0)
        let dark = CGColor(red: 0.05, green: 0.12, blue: 0.22, alpha: 1.0)

        let path = CGMutablePath()
        path.move(to: CGPoint(x: 22, y: 12))
        path.addLine(to: CGPoint(x: 42, y: 12))
        path.move(to: CGPoint(x: 32, y: 12))
        path.addLine(to: CGPoint(x: 32, y: 52))
        path.move(to: CGPoint(x: 22, y: 52))
        path.addLine(to: CGPoint(x: 42, y: 52))

        ctx.addPath(path)
        ctx.setStrokeColor(dark)
        ctx.setLineWidth(6.0)
        ctx.setLineCap(.round)
        ctx.strokePath()

        ctx.addPath(path)
        ctx.setStrokeColor(cyan)
        ctx.setLineWidth(3.0)
        ctx.setLineCap(.round)
        ctx.strokePath()

        return ctx.makeImage()!
    }

    private static func renderCrosshairCursor(size: Int) -> CGImage {
        let ctx = makeContext(size: size)
        let green = CGColor(red: 0.18, green: 0.98, blue: 0.52, alpha: 1.0)
        let dark = CGColor(red: 0.05, green: 0.18, blue: 0.10, alpha: 1.0)

        let path = CGMutablePath()
        path.move(to: CGPoint(x: 32, y: 8))
        path.addLine(to: CGPoint(x: 32, y: 56))
        path.move(to: CGPoint(x: 8, y: 32))
        path.addLine(to: CGPoint(x: 56, y: 32))

        ctx.addPath(path)
        ctx.setStrokeColor(dark)
        ctx.setLineWidth(5.0)
        ctx.setLineCap(.round)
        ctx.strokePath()

        ctx.addPath(path)
        ctx.setStrokeColor(green)
        ctx.setLineWidth(2.5)
        ctx.setLineCap(.round)
        ctx.strokePath()

        ctx.strokeEllipse(in: CGRect(x: 22, y: 22, width: 20, height: 20))
        return ctx.makeImage()!
    }

    private static func renderNotAllowedCursor(size: Int) -> CGImage {
        let ctx = makeContext(size: size)
        let red = CGColor(red: 1.0, green: 0.25, blue: 0.35, alpha: 1.0)
        let rect = CGRect(x: 12, y: 12, width: 40, height: 40)

        ctx.setStrokeColor(red)
        ctx.setLineWidth(5.0)
        ctx.strokeEllipse(in: rect)

        ctx.move(to: CGPoint(x: 18, y: 18))
        ctx.addLine(to: CGPoint(x: 46, y: 46))
        ctx.strokePath()
        return ctx.makeImage()!
    }

    private static func renderResizeCursor(size: Int, horizontal: Bool) -> CGImage {
        let ctx = makeContext(size: size)
        let cyan = CGColor(red: 0.1, green: 0.9, blue: 1.0, alpha: 1.0)
        let dark = CGColor(red: 0.05, green: 0.12, blue: 0.24, alpha: 1.0)

        if horizontal {
            ctx.translateBy(x: 32, y: 32)
            ctx.rotate(by: .pi / 2.0)
            ctx.translateBy(x: -32, y: -32)
        }

        let path = CGMutablePath()
        path.move(to: CGPoint(x: 32, y: 8))
        path.addLine(to: CGPoint(x: 22, y: 20))
        path.move(to: CGPoint(x: 32, y: 8))
        path.addLine(to: CGPoint(x: 42, y: 20))
        path.move(to: CGPoint(x: 32, y: 8))
        path.addLine(to: CGPoint(x: 32, y: 56))
        path.move(to: CGPoint(x: 32, y: 56))
        path.addLine(to: CGPoint(x: 22, y: 44))
        path.move(to: CGPoint(x: 32, y: 56))
        path.addLine(to: CGPoint(x: 42, y: 44))

        ctx.addPath(path)
        ctx.setStrokeColor(dark)
        ctx.setLineWidth(6.0)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.strokePath()

        ctx.addPath(path)
        ctx.setStrokeColor(cyan)
        ctx.setLineWidth(3.0)
        ctx.strokePath()

        return ctx.makeImage()!
    }

    private static func renderAnimatedRingCursor(size: Int, angle: Double, withArrow: Bool) -> CGImage {
        let ctx = makeContext(size: size)

        if withArrow {
            let miniArrow = CGMutablePath()
            miniArrow.move(to: CGPoint(x: 6, y: 6))
            miniArrow.addLine(to: CGPoint(x: 6, y: 38))
            miniArrow.addLine(to: CGPoint(x: 15, y: 30))
            miniArrow.addLine(to: CGPoint(x: 28, y: 30))
            miniArrow.closeSubpath()

            ctx.addPath(miniArrow)
            ctx.setFillColor(CGColor(red: 0.08, green: 0.92, blue: 0.98, alpha: 1.0))
            ctx.fillPath()
            ctx.addPath(miniArrow)
            ctx.setStrokeColor(CGColor(red: 0.05, green: 0.12, blue: 0.25, alpha: 1.0))
            ctx.setLineWidth(2.5)
            ctx.strokePath()
        }

        let center = withArrow ? CGPoint(x: 42, y: 42) : CGPoint(x: 32, y: 32)
        let radius: CGFloat = withArrow ? 14.0 : 20.0

        // Background track ring
        ctx.setStrokeColor(CGColor(red: 0.15, green: 0.25, blue: 0.45, alpha: 0.5))
        ctx.setLineWidth(5.0)
        ctx.strokeEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))

        // Rotating neon arc
        ctx.setStrokeColor(CGColor(red: 0.05, green: 0.95, blue: 1.0, alpha: 1.0))
        ctx.setLineWidth(5.0)
        ctx.setLineCap(.round)
        ctx.addArc(
            center: center,
            radius: radius,
            startAngle: CGFloat(angle),
            endAngle: CGFloat(angle + .pi * 1.15),
            clockwise: false
        )
        ctx.strokePath()

        // Secondary accent arc
        ctx.setStrokeColor(CGColor(red: 0.98, green: 0.28, blue: 0.82, alpha: 1.0))
        ctx.addArc(
            center: center,
            radius: radius,
            startAngle: CGFloat(angle + .pi * 1.3),
            endAngle: CGFloat(angle + .pi * 1.75),
            clockwise: false
        )
        ctx.strokePath()

        return ctx.makeImage()!
    }
}

private extension Data {
    mutating func appendUInt16LE(_ value: UInt16) {
        let le = value.littleEndian
        Swift.withUnsafeBytes(of: le) { append(contentsOf: $0) }
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        let le = value.littleEndian
        Swift.withUnsafeBytes(of: le) { append(contentsOf: $0) }
    }

    mutating func appendFourCC(_ fourCC: String) {
        if let ascii = fourCC.data(using: .ascii), ascii.count == 4 {
            append(ascii)
        }
    }
}
