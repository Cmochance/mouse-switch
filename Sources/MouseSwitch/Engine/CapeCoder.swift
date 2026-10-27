import Foundation
import CoreGraphics
import ImageIO

/// Handles vertical Sprite Sheet composition for macOS WindowServer and `.cape` (Mousecape Plist) import/export.
public enum CapeCoder {

    struct CompiledCursorPayload {
        let pointWidth: Double
        let pointHeight: Double
        let hotspotX: Double
        let hotspotY: Double
        let frameCount: Int
        let frameDuration: Double
        /// Multi-scale vertical sprite sheets (`[1x, 2x]`)
        let representations: [CGImage]
        let representationPNGs: [Data]
    }

    /// Compiles a `ParsedCursor` into macOS multi-scale (`1x` and `2x` Retina) vertical sprite sheets
    static func compileCursor(
        _ cursor: ParsedCursor,
        targetPointSize: Double
    ) -> CompiledCursorPayload? {
        let frames = cursor.decodeCGImages()
        guard !frames.isEmpty else { return nil }

        let clampedFrames = Array(frames.prefix(WinCursorParser.maxMacOSFrames))
        let frameCount = clampedFrames.count

        // Calculate proportional point dimensions preserving aspect ratio
        let origW = Double(max(1, cursor.pixelWidth))
        let origH = Double(max(1, cursor.pixelHeight))
        let aspect = origW / origH

        let pointW: Double
        let pointH: Double
        if aspect >= 1.0 {
            pointW = targetPointSize
            pointH = max(8.0, (targetPointSize / aspect).rounded())
        } else {
            pointH = targetPointSize
            pointW = max(8.0, (targetPointSize * aspect).rounded())
        }

        let scaleX = pointW / origW
        let scaleY = pointH / origH

        // CoreGraphics requires hotspot strictly within [0, pointSize)
        let hotX = min(pointW - 0.5, max(0.0, cursor.hotspotX * scaleX))
        let hotY = min(pointH - 0.5, max(0.0, cursor.hotspotY * scaleY))

        let duration = frameCount > 1 ? max(0.016, cursor.frameDuration) : 0.0

        // Build 1x and 2x (Retina HiDPI) vertical sprite sheets
        guard let sheet1x = buildVerticalSpriteSheet(
            frames: clampedFrames,
            framePixelWidth: Int(pointW.rounded()),
            framePixelHeight: Int(pointH.rounded())
        ),
        let sheet2x = buildVerticalSpriteSheet(
            frames: clampedFrames,
            framePixelWidth: Int((pointW * 2.0).rounded()),
            framePixelHeight: Int((pointH * 2.0).rounded())
        ),
        let png1x = ParsedCursor.encodePNG(sheet1x),
        let png2x = ParsedCursor.encodePNG(sheet2x) else {
            return nil
        }

        return CompiledCursorPayload(
            pointWidth: pointW,
            pointHeight: pointH,
            hotspotX: hotX,
            hotspotY: hotY,
            frameCount: frameCount,
            frameDuration: duration,
            representations: [sheet1x, sheet2x],
            representationPNGs: [png1x, png2x]
        )
    }

    /// Renders `frames` stacked vertically from top (frame 0) to bottom (frame N-1)
    static func buildVerticalSpriteSheet(
        frames: [CGImage],
        framePixelWidth: Int,
        framePixelHeight: Int
    ) -> CGImage? {
        guard !frames.isEmpty, framePixelWidth > 0, framePixelHeight > 0 else { return nil }
        let totalHeight = framePixelHeight * frames.count
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let ctx = CGContext(
            data: nil,
            width: framePixelWidth,
            height: totalHeight,
            bitsPerComponent: 8,
            bytesPerRow: framePixelWidth * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        ctx.interpolationQuality = .high

        // Note: CGContext has origin at bottom-left, while macOS cursor sprite sheets
        // order frame 0 at the TOP of the image and frame N-1 at the BOTTOM.
        for (idx, frame) in frames.enumerated() {
            let yOrigin = CGFloat(frames.count - 1 - idx) * CGFloat(framePixelHeight)
            let rect = CGRect(
                x: 0,
                y: yOrigin,
                width: CGFloat(framePixelWidth),
                height: CGFloat(framePixelHeight)
            )
            ctx.draw(frame, in: rect)
        }

        return ctx.makeImage()
    }

    // MARK: - Export to `.cape` (Mousecape compatible Plist)

    static func exportCapeData(from theme: CursorTheme) throws -> Data {
        var cursorsDict: [String: Any] = [:]

        // If user provided Wait but not AppStarting, or vice versa, keep them mapped cleanly
        for role in CursorRole.allCases {
            guard let parsed = theme.cursor(for: role),
                  let compiled = compileCursor(parsed, targetPointSize: theme.targetPointSize) else {
                continue
            }

            let entryDict: [String: Any] = [
                "FrameCount": compiled.frameCount,
                "FrameDuration": compiled.frameDuration,
                "HotSpotX": compiled.hotspotX,
                "HotSpotY": compiled.hotspotY,
                "PointsWide": compiled.pointWidth,
                "PointsHigh": compiled.pointHeight,
                "Representations": compiled.representationPNGs
            ]

            for macID in role.macOSIdentifiers {
                cursorsDict[macID] = entryDict
            }
        }

        let cleanID = theme.name
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: ".")

        let rootPlist: [String: Any] = [
            "Author": theme.author.isEmpty ? "MouseSwitch" : theme.author,
            "CapeName": theme.name,
            "CapeVersion": theme.version,
            "Cloud": false,
            "Cursors": cursorsDict,
            "HiDPI": true,
            "Identifier": "com.mouseswitch.cape.\(cleanID.isEmpty ? "custom" : cleanID)",
            "MinimumVersion": 2.0,
            "Version": 2.0
        ]

        return try PropertyListSerialization.data(
            fromPropertyList: rootPlist,
            format: .xml,
            options: 0
        )
    }

    public static func exportCape(theme: CursorTheme, to url: URL) throws {
        let data = try exportCapeData(from: theme)
        try data.write(to: url, options: .atomic)
    }

    // MARK: - Import from `.cape`

    public static func importCape(from url: URL) throws -> CursorTheme {
        let data = try Data(contentsOf: url)
        guard let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let cursorsDict = plist["Cursors"] as? [String: [String: Any]] else {
            throw ThemeImportError.invalidCapeFile("缺少 Cursors 字典结构")
        }

        let capeName = (plist["CapeName"] as? String) ?? url.deletingPathExtension().lastPathComponent
        let author = (plist["Author"] as? String) ?? "Mousecape"
        let version = (plist["CapeVersion"] as? Double) ?? 1.0

        var theme = CursorTheme(
            name: capeName,
            author: author,
            version: version
        )

        var detectedPointSizes: [Double] = []

        for (macID, cursorEntry) in cursorsDict {
            guard let role = CursorRole.fromMacOSIdentifier(macID),
                  theme.cursor(for: role) == nil else {
                continue
            }

            let frameCount = max(1, (cursorEntry["FrameCount"] as? Int) ?? 1)
            let frameDuration = (cursorEntry["FrameDuration"] as? Double) ?? 0.0
            let hotX = (cursorEntry["HotSpotX"] as? Double) ?? 0.0
            let hotY = (cursorEntry["HotSpotY"] as? Double) ?? 0.0
            let pointsWide = (cursorEntry["PointsWide"] as? Double) ?? 24.0
            let pointsHigh = (cursorEntry["PointsHigh"] as? Double) ?? 24.0

            guard let reps = cursorEntry["Representations"] as? [Data],
                  !reps.isEmpty else {
                continue
            }

            // Pick highest-resolution representation (typically 2x)
            let repImages: [CGImage] = reps.compactMap { repData in
                guard let src = CGImageSourceCreateWithData(repData as CFData, nil) else { return nil }
                return CGImageSourceCreateImageAtIndex(src, 0, nil)
            }
            guard let bestSheet = repImages.max(by: { $0.width < $1.width }) else {
                continue
            }

            let frameW = bestSheet.width
            let frameH = max(1, bestSheet.height / frameCount)

            var framePNGs: [Data] = []
            for i in 0..<frameCount {
                // Sprite sheet stacks frame 0 at TOP, frame N-1 at BOTTOM.
                // CGImage.cropping origin is bottom-left, so invert Y to restore original frame order.
                let cropRect = CGRect(
                    x: 0,
                    y: (frameCount - 1 - i) * frameH,
                    width: frameW,
                    height: frameH
                )
                if let cropped = bestSheet.cropping(to: cropRect),
                   let png = ParsedCursor.encodePNG(cropped) {
                    framePNGs.append(png)
                }
            }

            guard !framePNGs.isEmpty else { continue }

            let scaleX = pointsWide > 0 ? Double(frameW) / pointsWide : 1.0
            let scaleY = pointsHigh > 0 ? Double(frameH) / pointsHigh : 1.0

            let parsed = ParsedCursor(
                sourceFileName: "\(macID).cape",
                framePNGs: framePNGs,
                pixelWidth: frameW,
                pixelHeight: frameH,
                hotspotX: hotX * scaleX,
                hotspotY: hotY * scaleY,
                frameDuration: frameDuration
            )

            theme.setCursor(parsed, for: role)
            detectedPointSizes.append(max(pointsWide, pointsHigh))
        }

        if let firstSize = detectedPointSizes.first {
            theme.targetPointSize = firstSize
        }

        guard theme.assignedRolesCount > 0 else {
            throw ThemeImportError.invalidCapeFile("未能从 .cape 中匹配到任何标准光标")
        }

        return theme
    }
}
