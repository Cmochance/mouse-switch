import SwiftUI
import AppKit

/// Interactive cursor test strip where users can immediately hover over different zones
/// to verify how their applied macOS cursors look and feel across cursor states.
struct CursorTestSandboxView: View {
    @State private var sampleText: String = "在此输入或悬停测试文本光标 (IBeam)"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("实时光标测试沙盒（应用后将鼠标移入下方各区域即可体验效果）", systemImage: "sparkles.rectangle.stack")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                Spacer()
            }

            HStack(spacing: 10) {
                CursorHoverPill(
                    title: "普通箭头",
                    subtitle: "Arrow",
                    icon: "cursorarrow",
                    cursor: .arrow
                )

                TextField("测试文本输入", text: $sampleText)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 160, maxWidth: 220)

                CursorHoverPill(
                    title: "超链接手型",
                    subtitle: "PointingHand",
                    icon: "hand.point.up.left",
                    cursor: .pointingHand
                )

                CursorHoverPill(
                    title: "十字精确",
                    subtitle: "Crosshair",
                    icon: "plus.viewfinder",
                    cursor: .crosshair
                )

                CursorHoverPill(
                    title: "禁止操作",
                    subtitle: "NotAllowed",
                    icon: "nosign",
                    cursor: .operationNotAllowed
                )

                CursorHoverPill(
                    title: "上下缩放",
                    subtitle: "ResizeNS",
                    icon: "arrow.up.and.down",
                    cursor: .resizeUpDown
                )

                CursorHoverPill(
                    title: "左右缩放",
                    subtitle: "ResizeWE",
                    icon: "arrow.left.and.right",
                    cursor: .resizeLeftRight
                )
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

private struct CursorHoverPill: View {
    let title: String
    let subtitle: String
    let icon: String
    let cursor: NSCursor

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(isHovering ? .accentColor : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.medium))
                Text(subtitle)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isHovering ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(isHovering ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
        )
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
