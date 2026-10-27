import SwiftUI
import AppKit

@main
struct MouseSwitchEntry {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        if !args.isEmpty, shouldHandleCLI(args: args) {
            let code = runCLI(args: args)
            exit(code)
        } else {
            MouseSwitchGUIApp.main()
        }
    }

    private static func shouldHandleCLI(args: [String]) -> Bool {
        let cliFlags: Set<String> = ["--help", "-h", "--self-test", "--convert", "--apply", "--restore", "--generate-sample"]
        return args.contains { cliFlags.contains($0) }
    }

    private static func runCLI(args: [String]) -> Int32 {
        if args.contains("--help") || args.contains("-h") {
            print("""
            MouseSwitch — Windows 鼠标光标 (.cur / .ani / .inf) 转 macOS (.cape) 及系统注入工具

            用法:
              MouseSwitch                                  启动原生 macOS 图形界面应用
              MouseSwitch --convert <输入路径> [--out <输出.cape>] [--size <24|32>]
              MouseSwitch --apply <输入路径(.cur/.ani/.inf/文件夹/.cape)> [--size <24|32>]
              MouseSwitch --restore                        立即恢复 macOS 系统默认鼠标光标
              MouseSwitch --self-test                      运行端到端二进制转换与系统接口自检
            """)
            return 0
        }

        if args.contains("--restore") {
            let ok = SkyLightCursorBridge.shared.restoreSystemDefaults(silent: false)
            print(ok ? "✅ 已恢复 macOS 系统默认光标" : "❌ 恢复默认光标失败")
            return ok ? 0 : 1
        }

        if args.contains("--self-test") {
            return runSelfTest()
        }

        if let genIdx = args.firstIndex(of: "--generate-sample"), genIdx + 1 < args.count {
            let outDir = URL(fileURLWithPath: args[genIdx + 1])
            do {
                let packDir = try DemoWinCursorPackGenerator.generateSampleWindowsPack(in: outDir)
                print("✅ 已生成示例 Windows 光标包: \(packDir.path)")
                return 0
            } catch {
                fputs("❌ 生成失败: \(error.localizedDescription)\n", stderr)
                return 1
            }
        }

        var pointSize: Double = 24.0
        if let sizeIdx = args.firstIndex(of: "--size"), sizeIdx + 1 < args.count,
           let val = Double(args[sizeIdx + 1]) {
            pointSize = max(16.0, min(64.0, val))
        }

        if let convIdx = args.firstIndex(of: "--convert"), convIdx + 1 < args.count {
            let inputPath = args[convIdx + 1]
            let inputURL = URL(fileURLWithPath: inputPath)
            let outPath: String
            if let outIdx = args.firstIndex(of: "--out"), outIdx + 1 < args.count {
                outPath = args[outIdx + 1]
            } else {
                outPath = inputURL.deletingPathExtension().path + ".cape"
            }

            do {
                var theme = try InfAndPackImporter.importFrom(url: inputURL)
                theme.targetPointSize = pointSize
                let outURL = URL(fileURLWithPath: outPath)
                try CapeCoder.exportCape(theme: theme, to: outURL)
                print("✅ 已将「\(theme.name)」(\(theme.assignedRolesCount) 个光标) 导出为: \(outURL.path)")
                return 0
            } catch {
                fputs("❌ 转换失败: \(error.localizedDescription)\n", stderr)
                return 1
            }
        }

        if let applyIdx = args.firstIndex(of: "--apply"), applyIdx + 1 < args.count {
            let inputPath = args[applyIdx + 1]
            let inputURL = URL(fileURLWithPath: inputPath)
            do {
                var theme = try InfAndPackImporter.importFrom(url: inputURL)
                theme.targetPointSize = pointSize
                let res = SkyLightCursorBridge.shared.applyTheme(theme)
                print("✅ 已将「\(theme.name)」应用到 MacBook (成功注册 \(res.succeeded) 个标识符, 失败 \(res.failed) 个)")
                return res.succeeded > 0 ? 0 : 1
            } catch {
                fputs("❌ 应用失败: \(error.localizedDescription)\n", stderr)
                return 1
            }
        }

        return 0
    }

    private static func runSelfTest() -> Int32 {
        print("🔍 开始执行 MouseSwitch 端到端自检...")
        do {
            let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("MouseSwitchSelfTest_\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: tmpDir) }

            // 1. Generate sample Windows cursor pack (.cur + .ani + install.inf)
            let packDir = try DemoWinCursorPackGenerator.generateSampleWindowsPack(in: tmpDir)
            print("  [1/4] 生成测试 Windows 光标包 (.cur + .ani + install.inf) 成功: \(packDir.lastPathComponent)")

            // 2. Parse Windows cursor pack via InfAndPackImporter
            let theme = try InfAndPackImporter.importDirectory(packDir)
            guard theme.assignedRolesCount == 9, theme.animatedRolesCount == 2 else {
                print("  ❌ 角色解析数量不符: assigned=\(theme.assignedRolesCount), animated=\(theme.animatedRolesCount)")
                return 1
            }
            print("  [2/4] 解析 install.inf 与 .cur/.ani 二进制成功: 识别出 \(theme.assignedRolesCount) 种光标 (含 \(theme.animatedRolesCount) 个 RIFF ACON 动画光标)")

            // 3. Export to .cape and re-import from .cape
            let capeURL = tmpDir.appendingPathComponent("test_output.cape")
            try CapeCoder.exportCape(theme: theme, to: capeURL)
            let reimported = try CapeCoder.importCape(from: capeURL)
            guard reimported.assignedRolesCount == theme.assignedRolesCount else {
                print("  ❌ .cape 往返导入导出不一致")
                return 1
            }
            // 逐角色校验 .cape 往返结构保真度（帧数、时长、每帧非空）
            for role in CursorRole.allCases {
                guard let original = theme.cursor(for: role),
                      let reimportedCursor = reimported.cursor(for: role) else {
                    continue
                }
                guard original.frameCount == reimportedCursor.frameCount,
                      abs(original.frameDuration - reimportedCursor.frameDuration) < 0.05,
                      reimportedCursor.framePNGs.count == original.frameCount,
                      reimportedCursor.framePNGs.allSatisfy({ !$0.isEmpty }) else {
                    print("  ❌ .cape 往返保真度不一致: 角色 \(role.rawValue)")
                    return 1
                }
            }
            print("  [3/4] 导出与重新解析 macOS .cape (1x/2x Retina 垂直精灵图) 验证通过")

            // 4. Verify SkyLight bridge availability & system backup
            guard SkyLightCursorBridge.shared.isAvailable else {
                print("  ❌ SkyLight 私有框架符号不可用")
                return 1
            }
            SkyLightCursorBridge.shared.ensureSystemDefaultBackup()
            print("  [4/4] SkyLight.framework 核心符号绑定与系统默认光标备份检查通过")

            print("🎉 自检全部通过！")
            return 0
        } catch {
            print("❌ 自检异常: \(error.localizedDescription)")
            return 1
        }
    }
}

struct MouseSwitchGUIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var viewModel = AppViewModel()

    var body: some Scene {
        WindowGroup("MouseSwitch — Windows 光标转换与 MacBook 应用工具") {
            MainWindowView(viewModel: viewModel)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("导入 Windows 光标包 / 文件...") {
                    viewModel.promptImportDialog()
                }
                .keyboardShortcut("o", modifiers: [.command])

                Button("导出当前主题为 .cape...") {
                    viewModel.promptExportCape()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Divider()

                Button("立即应用当前光标主题") {
                    viewModel.applySelectedThemeToMac()
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("恢复 Mac 系统默认光标") {
                    viewModel.restoreSystemDefaultCursor()
                }
                .keyboardShortcut("0", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra("MouseSwitch", systemImage: "cursorarrow.rays") {
            VStack(alignment: .leading, spacing: 4) {
                if let activeID = viewModel.activeThemeID,
                   let active = viewModel.themes.first(where: { $0.id == activeID }) {
                    Text("当前生效: \(active.name)")
                        .font(.caption)
                } else {
                    Text("当前生效: macOS 系统默认光标")
                        .font(.caption)
                }

                Divider()

                Text("快速切换光标主题")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                ForEach(viewModel.themes) { theme in
                    Button {
                        viewModel.selectedThemeID = theme.id
                        viewModel.applyTheme(theme)
                    } label: {
                        HStack {
                            if viewModel.activeThemeID == theme.id {
                                Image(systemName: "checkmark")
                            }
                            Text(theme.name)
                        }
                    }
                }

                Divider()

                Toggle("休眠唤醒自动保持", isOn: $viewModel.keepAliveOnWake)

                Button("重新刷新当前光标") {
                    viewModel.applySelectedThemeToMac()
                }

                Button("恢复 Mac 系统默认光标") {
                    viewModel.restoreSystemDefaultCursor()
                }

                Divider()

                Button("显示主窗口") {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    for window in NSApplication.shared.windows {
                        window.makeKeyAndOrderFront(nil)
                    }
                }

                Button("退出 MouseSwitch") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
