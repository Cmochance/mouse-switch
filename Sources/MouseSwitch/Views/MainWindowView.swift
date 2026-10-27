import SwiftUI
import UniformTypeIdentifiers

struct MainWindowView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var isDropTargeted = false

    private let gridColumns = [
        GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 12)
    ]

    var body: some View {
        NavigationSplitView {
            sidebarContent
                .navigationSplitViewColumnWidth(min: 230, ideal: 250, max: 300)
        } detail: {
            detailContent
        }
        .frame(minWidth: 960, minHeight: 660)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleFileProviders(providers) { urls in
                viewModel.handleImportedURLs(urls)
            }
        }
        .sheet(item: $viewModel.editingRole) { role in
            if let theme = viewModel.selectedTheme,
               let existingCursor = theme.cursor(for: role) {
                let binding = Binding<ParsedCursor>(
                    get: {
                        viewModel.selectedTheme?.cursor(for: role) ?? existingCursor
                    },
                    set: { updated in
                        var t = viewModel.selectedTheme ?? theme
                        t.setCursor(updated, for: role)
                        viewModel.selectedTheme = t
                    }
                )
                CursorRoleEditorSheet(
                    role: role,
                    cursor: binding,
                    onClose: { viewModel.editingRole = nil }
                )
            }
        }
    }

    // MARK: - Sidebar

    private var sidebarContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    viewModel.promptImportDialog()
                } label: {
                    Label("导入 Windows 光标包 / 文件", systemImage: "square.and.arrow.down.on.square")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                HStack(spacing: 6) {
                    Button {
                        viewModel.createBlankTheme()
                    } label: {
                        Label("新建空白", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.small)

                    Button {
                        viewModel.createAndImportDemoPack(silent: false)
                    } label: {
                        Label("生成示例包", systemImage: "wand.and.stars")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.small)
                }
            }
            .padding(12)

            Divider()

            Text("已保存的光标主题 (\(viewModel.themes.count))")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 4)

            List(selection: $viewModel.selectedThemeID) {
                ForEach(viewModel.themes) { theme in
                    HStack(spacing: 10) {
                        if let arrowCursor = theme.cursor(for: .arrow) {
                            AnimatedCursorPreviewView(
                                cursor: arrowCursor,
                                displaySize: 34,
                                showHotspot: false
                            )
                        } else {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.secondary.opacity(0.15))
                                .frame(width: 34, height: 34)
                                .overlay(
                                    Image(systemName: "cursorarrow")
                                        .foregroundColor(.secondary)
                                )
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(theme.name)
                                    .font(.body.weight(.medium))
                                    .lineLimit(1)
                                if viewModel.activeThemeID == theme.id {
                                    Text("使用中")
                                        .font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Capsule().fill(Color.green.opacity(0.2)))
                                        .foregroundColor(.green)
                                }
                            }
                            Text("\(theme.assignedRolesCount) 个光标 · \(theme.animatedRolesCount) 个动画")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 3)
                    .tag(theme.id)
                    .contextMenu {
                        Button("立即应用到 MacBook") {
                            viewModel.applyTheme(theme)
                        }
                        Button("导出为 .cape 文件...") {
                            viewModel.selectedThemeID = theme.id
                            viewModel.promptExportCape()
                        }
                        Divider()
                        Button("删除主题", role: .destructive) {
                            viewModel.deleteTheme(theme)
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Toggle("休眠唤醒后自动保持光标", isOn: $viewModel.keepAliveOnWake)
                    .font(.caption)
                    .toggleStyle(.switch)
                    .controlSize(.mini)

                Button {
                    viewModel.revealSampleWindowsPackInFinder()
                } label: {
                    Label("在 Finder 查看示例 .cur/.ani/.inf", systemImage: "folder")
                        .font(.caption)
                }
                .buttonStyle(.link)

                Button(role: .destructive) {
                    viewModel.restoreSystemDefaultCursor()
                } label: {
                    Label("一键恢复 Mac 系统默认光标", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(12)
        }
    }

    // MARK: - Detail Content

    @ViewBuilder
    private var detailContent: some View {
        if let theme = viewModel.selectedTheme {
            VStack(spacing: 0) {
                themeHeaderBar(theme: theme)
                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        dropBannerView

                        LazyVGrid(columns: gridColumns, spacing: 12) {
                            ForEach(CursorRole.allCases) { role in
                                CursorRoleCardView(
                                    role: role,
                                    cursor: theme.cursor(for: role),
                                    onSelectFile: {
                                        viewModel.promptSelectCursorForRole(role)
                                    },
                                    onDropFile: { url in
                                        viewModel.assignSingleCursorFile(url: url, to: role)
                                    },
                                    onEditHotspot: {
                                        viewModel.editingRole = role
                                    },
                                    onClear: {
                                        viewModel.removeCursorForRole(role)
                                    }
                                )
                            }
                        }
                    }
                    .padding(16)
                }

                Divider()

                VStack(spacing: 8) {
                    CursorTestSandboxView()
                    statusBarView
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(nsColor: .windowBackgroundColor))
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "cursorarrow.rays")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                Text("将 Windows 光标文件夹 (.cur / .ani / install.inf) 拖入此处")
                    .font(.title3.weight(.medium))
                Button("选择文件或文件夹导入") {
                    viewModel.promptImportDialog()
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func themeHeaderBar(theme: CursorTheme) -> some View {
        let nameBinding = Binding<String>(
            get: { viewModel.selectedTheme?.name ?? theme.name },
            set: { newName in
                var updated = viewModel.selectedTheme ?? theme
                updated.name = newName
                viewModel.selectedTheme = updated
            }
        )

        let sizeBinding = Binding<Double>(
            get: { viewModel.selectedTheme?.targetPointSize ?? theme.targetPointSize },
            set: { newSize in
                var updated = viewModel.selectedTheme ?? theme
                updated.targetPointSize = newSize
                viewModel.selectedTheme = updated
            }
        )

        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    TextField("主题名称", text: nameBinding)
                        .font(.title3.weight(.semibold))
                        .textFieldStyle(.plain)
                        .frame(minWidth: 180, maxWidth: 320)

                    if viewModel.activeThemeID == theme.id {
                        Label("当前正在 MacBook 上生效", systemImage: "checkmark.seal.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.green.opacity(0.14)))
                    }
                }

                Text("已配置 \(theme.assignedRolesCount)/\(CursorRole.allCases.count) 种角色 · \(theme.animatedRolesCount) 个动画光标 · 自动生成 1x/2x Retina 垂直精灵图")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Picker("渲染尺寸", selection: sizeBinding) {
                ForEach(CursorPointSizePreset.allCases) { preset in
                    Text(preset.label).tag(preset.rawValue)
                }
            }
            .frame(width: 210)
            .help("调整应用到 MacBook 时的逻辑点尺寸（自动生成 2x Retina 高清图层并同步缩放热点坐标）")

            Button {
                viewModel.promptExportCape()
            } label: {
                Label("导出 .cape", systemImage: "square.and.arrow.up")
            }
            .help("导出为兼容 Mousecape 的标准 .cape 属性列表文件")

            Button {
                viewModel.restoreSystemDefaultCursor()
            } label: {
                Label("恢复默认", systemImage: "arrow.uturn.backward")
            }

            Button {
                viewModel.applySelectedThemeToMac()
            } label: {
                Label("立即应用到 MacBook", systemImage: "bolt.fill")
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var dropBannerView: some View {
        HStack(spacing: 12) {
            Image(systemName: isDropTargeted ? "arrow.down.doc.fill" : "sparkles")
                .font(.title3)
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("支持直接拖入：Windows 光标文件夹、install.inf、单个或多个 .cur / .ani 文件，或 macOS .cape 文件")
                    .font(.callout.weight(.medium))
                Text("你也可以将单个 .cur / .ani 文件直接拖到下方任意一个角色卡片上进行单独替换，或点击「热点/帧率」微调点击位置。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isDropTargeted ? Color.accentColor.opacity(0.15) : Color.accentColor.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            isDropTargeted ? Color.accentColor : Color.accentColor.opacity(0.25),
                            style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                        )
                )
        )
    }

    private var statusBarView: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(viewModel.isStatusError ? Color.red : Color.green)
                .frame(width: 8, height: 8)
            Text(viewModel.statusMessage)
                .font(.caption)
                .foregroundColor(viewModel.isStatusError ? .red : .secondary)
                .lineLimit(1)
            Spacer()
            Text("SkyLight CoreGraphics 引擎已就绪")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Individual Cursor Role Card

private struct CursorRoleCardView: View {
    let role: CursorRole
    let cursor: ParsedCursor?
    var onSelectFile: () -> Void
    var onDropFile: (URL) -> Void
    var onEditHotspot: () -> Void
    var onClear: () -> Void

    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: role.systemIcon)
                    .foregroundColor(.accentColor)
                    .frame(width: 16)
                Text(role.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                if let cursor = cursor {
                    Text(cursor.isAnimated ? "ANI \(cursor.frameCount)帧" : "CUR 静态")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(cursor.isAnimated ? Color.purple.opacity(0.18) : Color.blue.opacity(0.15))
                        )
                        .foregroundColor(cursor.isAnimated ? .purple : .blue)
                } else {
                    Text("未设置")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 12) {
                if let cursor = cursor {
                    AnimatedCursorPreviewView(
                        cursor: cursor,
                        displaySize: 60,
                        showHotspot: true
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(cursor.sourceFileName)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Text("尺寸: \(cursor.pixelWidth)×\(cursor.pixelHeight) px")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Text("热点: (\(Int(cursor.hotspotX)), \(Int(cursor.hotspotY)))")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        HStack(spacing: 6) {
                            Button("热点/帧率") {
                                onEditHotspot()
                            }
                            .controlSize(.mini)

                            Button("更换") {
                                onSelectFile()
                            }
                            .controlSize(.mini)

                            Button(role: .destructive) {
                                onClear()
                            } label: {
                                Image(systemName: "trash")
                            }
                            .controlSize(.mini)
                        }
                        .padding(.top, 2)
                    }
                } else {
                    Button {
                        onSelectFile()
                    } label: {
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                .frame(width: 60, height: 60)
                                .overlay(
                                    Image(systemName: "plus.circle")
                                        .font(.title3)
                                        .foregroundColor(.secondary)
                                )
                            VStack(alignment: .leading, spacing: 3) {
                                Text("点击选择或拖入")
                                    .font(.caption.weight(.medium))
                                Text(".cur 或 .ani 文件")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text("保持系统默认")
                                    .font(.caption2)
                                    .foregroundColor(.secondary.opacity(0.8))
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            isTargeted ? Color.accentColor : (cursor != nil ? Color.primary.opacity(0.12) : Color.primary.opacity(0.06)),
                            lineWidth: isTargeted ? 2 : 1
                        )
                )
        )
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleFileProviders(providers) { urls in
                if let first = urls.first {
                    onDropFile(first)
                }
            }
        }
    }
}

// MARK: - Drag & Drop URL Extractor

private func handleFileProviders(_ providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) -> Bool {
    guard !providers.isEmpty else { return false }
    let group = DispatchGroup()
    let lock = NSLock()
    var collectedURLs: [URL] = []

    for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
        group.enter()
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            defer { group.leave() }
            if let data = item as? Data,
               let url = URL(dataRepresentation: data, relativeTo: nil) {
                lock.lock()
                collectedURLs.append(url)
                lock.unlock()
            } else if let url = item as? URL {
                lock.lock()
                collectedURLs.append(url)
                lock.unlock()
            }
        }
    }

    group.notify(queue: .main) {
        if !collectedURLs.isEmpty {
            completion(collectedURLs)
        }
    }
    return true
}
