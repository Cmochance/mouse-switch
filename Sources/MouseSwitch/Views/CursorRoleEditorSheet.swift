import SwiftUI

/// Interactive modal editor allowing the user to click directly on a magnified cursor canvas
/// to fine-tune Hotspot `(X, Y)` coordinates and animation frame duration.
struct CursorRoleEditorSheet: View {
    let role: CursorRole
    @Binding var cursor: ParsedCursor
    var onClose: () -> Void

    private let canvasSize: CGFloat = 180

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(role.displayName, systemImage: role.systemIcon)
                    .font(.headline)
                Spacer()
                Text(cursor.sourceFileName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            HStack(alignment: .top, spacing: 20) {
                VStack(spacing: 8) {
                    ZStack {
                        AnimatedCursorPreviewView(
                            cursor: cursor,
                            displaySize: canvasSize,
                            showHotspot: true
                        )
                        // Allow clicking on canvas to pick hotspot directly
                        Color.clear
                            .frame(width: canvasSize - 10, height: canvasSize - 10)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        let inner = canvasSize - 10
                                        let normX = min(1.0, max(0.0, value.location.x / inner))
                                        let normY = min(1.0, max(0.0, value.location.y / inner))
                                        cursor.hotspotX = (normX * Double(cursor.pixelWidth)).rounded()
                                        cursor.hotspotY = (normY * Double(cursor.pixelHeight)).rounded()
                                    }
                            )
                    }
                    Text("提示：直接在上方画布点击或拖动即可定位红点（点击热点）")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    GroupBox("点击热点坐标 (像素)") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("X: \(Int(cursor.hotspotX)) px")
                                    .frame(width: 75, alignment: .leading)
                                Slider(
                                    value: $cursor.hotspotX,
                                    in: 0...Double(max(1, cursor.pixelWidth - 1)),
                                    step: 1
                                )
                            }
                            HStack {
                                Text("Y: \(Int(cursor.hotspotY)) px")
                                    .frame(width: 75, alignment: .leading)
                                Slider(
                                    value: $cursor.hotspotY,
                                    in: 0...Double(max(1, cursor.pixelHeight - 1)),
                                    step: 1
                                )
                            }
                            HStack(spacing: 8) {
                                Button("左上角 (0,0)") {
                                    cursor.hotspotX = 0
                                    cursor.hotspotY = 0
                                }
                                .controlSize(.small)

                                Button("正中心") {
                                    cursor.hotspotX = Double(cursor.pixelWidth / 2)
                                    cursor.hotspotY = Double(cursor.pixelHeight / 2)
                                }
                                .controlSize(.small)
                            }
                        }
                        .padding(6)
                    }

                    if cursor.frameCount > 1 {
                        GroupBox("动画参数 (\(cursor.frameCount) 帧)") {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(String(format: "单帧时长: %.0f ms", cursor.frameDuration * 1000))
                                        .frame(width: 115, alignment: .leading)
                                    Slider(
                                        value: $cursor.frameDuration,
                                        in: 0.016...0.250
                                    )
                                }
                                Text(String(format: "约 %.1f FPS · 总周期 %.2f 秒", 1.0 / max(0.016, cursor.frameDuration), cursor.frameDuration * Double(cursor.frameCount)))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(6)
                        }
                    }

                    GroupBox("映射的 macOS 系统标识符") {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(role.macOSIdentifiers, id: \.self) { id in
                                Text(id)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                    }
                }
            }

            HStack {
                Spacer()
                Button("完成") {
                    onClose()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 540)
    }
}
