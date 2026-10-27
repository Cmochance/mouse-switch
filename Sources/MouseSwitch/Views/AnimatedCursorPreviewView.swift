import SwiftUI
import AppKit

/// Displays a live animated preview of a `ParsedCursor` with checkerboard transparency background
/// and an optional Hotspot `(X, Y)` crosshair marker.
struct AnimatedCursorPreviewView: View {
    let cursor: ParsedCursor
    var displaySize: CGFloat = 56
    var showHotspot: Bool = true

    @State private var currentFrameIndex: Int = 0
    @State private var decodedFrames: [NSImage] = []

    var body: some View {
        ZStack {
            // Subtle transparency checkerboard background
            CheckerboardBackground()
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                )

            if !decodedFrames.isEmpty {
                let safeIdx = min(decodedFrames.count - 1, max(0, currentFrameIndex))
                Image(nsImage: decodedFrames[safeIdx])
                    .interpolation(.high)
                    .resizable()
                    .scaledToFit()
                    .frame(width: displaySize - 10, height: displaySize - 10)
            }

            // Hotspot crosshair indicator
            if showHotspot && cursor.pixelWidth > 0 && cursor.pixelHeight > 0 {
                let innerSize = displaySize - 10
                let offsetX = (CGFloat(cursor.hotspotX) / CGFloat(cursor.pixelWidth) - 0.5) * innerSize
                let offsetY = (CGFloat(cursor.hotspotY) / CGFloat(cursor.pixelHeight) - 0.5) * innerSize

                ZStack {
                    Circle()
                        .strokeBorder(Color.red.opacity(0.9), lineWidth: 1.5)
                        .frame(width: 7, height: 7)
                    Circle()
                        .fill(Color.red)
                        .frame(width: 2.5, height: 2.5)
                }
                .offset(x: offsetX, y: offsetY)
                .help("热点坐标 (Hotspot): (\(Int(cursor.hotspotX)), \(Int(cursor.hotspotY))) px")
            }
        }
        .frame(width: displaySize, height: displaySize)
        .onAppear {
            reloadFrames()
        }
        .onChange(of: cursor.id) { _ in
            reloadFrames()
        }
        .onChange(of: cursor.framePNGs) { _ in
            reloadFrames()
        }
        .task(id: "\(cursor.id)-\(cursor.frameDuration)-\(decodedFrames.count)") {
            guard decodedFrames.count > 1 else { return }
            let intervalNs = UInt64(max(0.02, cursor.frameDuration) * 1_000_000_000)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: intervalNs)
                if !Task.isCancelled && decodedFrames.count > 1 {
                    currentFrameIndex = (currentFrameIndex + 1) % decodedFrames.count
                }
            }
        }
    }

    private func reloadFrames() {
        let cgImages = cursor.decodeCGImages()
        decodedFrames = cgImages.map {
            NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height))
        }
        currentFrameIndex = 0
    }
}

struct CheckerboardBackground: View {
    var squareSize: CGFloat = 6

    var body: some View {
        Canvas { context, size in
            let rows = Int(ceil(size.height / squareSize))
            let cols = Int(ceil(size.width / squareSize))

            let light = Color(nsColor: .controlBackgroundColor).opacity(0.7)
            let dark = Color.secondary.opacity(0.14)

            for r in 0..<rows {
                for c in 0..<cols {
                    let rect = CGRect(
                        x: CGFloat(c) * squareSize,
                        y: CGFloat(r) * squareSize,
                        width: squareSize,
                        height: squareSize
                    )
                    context.fill(
                        Path(rect),
                        with: .color(((r + c) % 2 == 0) ? light : dark)
                    )
                }
            }
        }
    }
}
