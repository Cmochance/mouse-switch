import Foundation
import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor
final class AppViewModel: ObservableObject {
    @Published var themes: [CursorTheme] = []
    @Published var selectedThemeID: UUID?
    @Published var activeThemeID: UUID?
    @Published var keepAliveOnWake: Bool = true {
        didSet {
            UserDefaults.standard.set(keepAliveOnWake, forKey: "keepAliveOnWake")
        }
    }
    @Published var statusMessage: String = "就绪：支持导入 Windows (.cur / .ani / .inf 文件夹) 或 .cape 光标包"
    @Published var isStatusError: Bool = false
    @Published var editingRole: CursorRole?

    private var wakeObserver: NSObjectProtocol?
    private var sessionObserver: NSObjectProtocol?

    private var themesDirURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("MouseSwitch/Themes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    init() {
        self.keepAliveOnWake = UserDefaults.standard.object(forKey: "keepAliveOnWake") as? Bool ?? true
        loadSavedThemes()

        if themes.isEmpty {
            createAndImportDemoPack(silent: true)
        }
        selectedThemeID = themes.first?.id

        if let savedActiveIDStr = UserDefaults.standard.string(forKey: "activeThemeID"),
           let uuid = UUID(uuidString: savedActiveIDStr),
           themes.contains(where: { $0.id == uuid }) {
            activeThemeID = uuid
        }

        setupWakeObservers()

        // 系统默认光标备份涉及文件 I/O 与 SkyLight 调用，放入后台线程，避免阻塞主线程
        Task.detached {
            SkyLightCursorBridge.shared.ensureSystemDefaultBackup()
        }
    }

    var selectedTheme: CursorTheme? {
        get {
            guard let id = selectedThemeID else { return themes.first }
            return themes.first(where: { $0.id == id })
        }
        set {
            guard let updated = newValue,
                  let idx = themes.firstIndex(where: { $0.id == updated.id }) else {
                return
            }
            themes[idx] = updated
            saveThemeToDisk(updated)
        }
    }

    // MARK: - Persistence

    func loadSavedThemes() {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: themesDirURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        var loaded: [CursorTheme] = []
        let decoder = JSONDecoder()
        for url in urls where url.pathExtension == "json" {
            if let data = try? Data(contentsOf: url),
               let theme = try? decoder.decode(CursorTheme.self, from: data) {
                loaded.append(theme)
            }
        }
        loaded.sort { $0.createdAt < $1.createdAt }
        self.themes = loaded
    }

    func saveThemeToDisk(_ theme: CursorTheme) {
        let fileURL = themesDirURL.appendingPathComponent("\(theme.id.uuidString).json")
        if let data = try? JSONEncoder().encode(theme) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func deleteTheme(_ theme: CursorTheme) {
        if activeThemeID == theme.id {
            restoreSystemDefaultCursor()
        }
        themes.removeAll { $0.id == theme.id }
        let fileURL = themesDirURL.appendingPathComponent("\(theme.id.uuidString).json")
        try? FileManager.default.removeItem(at: fileURL)
        if selectedThemeID == theme.id {
            selectedThemeID = themes.first?.id
        }
        setStatus("已删除主题「\(theme.name)」", isError: false)
    }

    func createBlankTheme() {
        let newTheme = CursorTheme(
            name: "新建自定义主题 \(themes.count + 1)",
            author: NSFullUserName()
        )
        themes.append(newTheme)
        saveThemeToDisk(newTheme)
        selectedThemeID = newTheme.id
        setStatus("已创建空白光标主题，可拖拽 .cur / .ani 到对应槽位", isError: false)
    }

    // MARK: - Import & Export Actions

    func promptImportDialog() {
        let panel = NSOpenPanel()
        panel.title = "选择 Windows 光标文件夹、install.inf、.cur、.ani 或 .cape 文件"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "导入并转换"

        if panel.runModal() == .OK {
            handleImportedURLs(panel.urls)
        }
    }

    func handleImportedURLs(_ urls: [URL]) {
        guard !urls.isEmpty else { return }

        // If user selected multiple individual .cur / .ani files, combine them into one theme
        if urls.count > 1 && urls.allSatisfy({ ["cur", "ani", "ico"].contains($0.pathExtension.lowercased()) }) {
            let folderName = urls.first?.deletingLastPathComponent().lastPathComponent ?? "Windows 导入光标组"
            var combined = CursorTheme(name: folderName, author: "Windows Batch Import")
            var failedFiles: [String] = []
            for url in urls {
                do {
                    let parsed = try WinCursorParser.parse(fileURL: url)
                    let stem = url.deletingPathExtension().lastPathComponent
                    let role = CursorRole.match(identifierOrFilename: stem) ?? .arrow
                    combined.setCursor(parsed, for: role)
                } catch {
                    failedFiles.append(url.lastPathComponent)
                }
            }
            if combined.assignedRolesCount > 0 {
                themes.append(combined)
                saveThemeToDisk(combined)
                selectedThemeID = combined.id
                let msg = failedFiles.isEmpty
                    ? "成功合并导入 \(combined.assignedRolesCount) 个 Windows 光标文件！"
                    : "合并导入 \(combined.assignedRolesCount) 个光标，失败 \(failedFiles.count) 个：\(failedFiles.joined(separator: ", "))"
                setStatus(msg, isError: !failedFiles.isEmpty)
                return
            }
        }

        // Otherwise import each URL (folder, .inf, .cape, or single file)
        var lastImported: CursorTheme?
        for url in urls {
            do {
                let theme = try InfAndPackImporter.importFrom(url: url)
                themes.append(theme)
                saveThemeToDisk(theme)
                lastImported = theme
            } catch {
                setStatus("导入失败 (\(url.lastPathComponent)): \(error.localizedDescription)", isError: true)
            }
        }

        if let imported = lastImported {
            selectedThemeID = imported.id
            setStatus(
                "已成功转换导入「\(imported.name)」（共 \(imported.assignedRolesCount) 种光标，含 \(imported.animatedRolesCount) 个动画光标）",
                isError: false
            )
        }
    }

    func assignSingleCursorFile(url: URL, to role: CursorRole) {
        guard var current = selectedTheme else { return }
        do {
            let parsed = try WinCursorParser.parse(fileURL: url)
            current.setCursor(parsed, for: role)
            selectedTheme = current
            setStatus("已将 \(url.lastPathComponent) 分配给「\(role.shortName)」", isError: false)
        } catch {
            setStatus("解析 \(url.lastPathComponent) 失败: \(error.localizedDescription)", isError: true)
        }
    }

    func promptSelectCursorForRole(_ role: CursorRole) {
        let panel = NSOpenPanel()
        panel.title = "为「\(role.displayName)」选择 .cur 或 .ani 文件"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            assignSingleCursorFile(url: url, to: role)
        }
    }

    func removeCursorForRole(_ role: CursorRole) {
        guard var current = selectedTheme else { return }
        current.setCursor(nil, for: role)
        selectedTheme = current
        setStatus("已移除「\(role.shortName)」的自定义光标", isError: false)
    }

    func createAndImportDemoPack(silent: Bool = false) {
        do {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let sampleDir = appSupport.appendingPathComponent("MouseSwitch/SampleWindowsPack_CyberNeon", isDirectory: true)
            _ = try DemoWinCursorPackGenerator.generateSampleWindowsPack(in: sampleDir)
            let theme = try InfAndPackImporter.importDirectory(sampleDir)
            themes.append(theme)
            saveThemeToDisk(theme)
            selectedThemeID = theme.id
            if !silent {
                setStatus("已生成并导入示例 Windows 光标包（含真实 .cur、.ani 与 install.inf）", isError: false)
            }
        } catch {
            if !silent {
                setStatus("生成示例光标包失败: \(error.localizedDescription)", isError: true)
            }
        }
    }

    func revealSampleWindowsPackInFinder() {
        do {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let sampleDir = appSupport.appendingPathComponent("MouseSwitch/SampleWindowsPack_CyberNeon", isDirectory: true)
            _ = try DemoWinCursorPackGenerator.generateSampleWindowsPack(in: sampleDir)
            NSWorkspace.shared.selectFile(sampleDir.appendingPathComponent("install.inf").path, inFileViewerRootedAtPath: sampleDir.path)
            setStatus("已在 Finder 中打开示例 Windows 光标包目录", isError: false)
        } catch {
            setStatus("无法打开示例文件夹: \(error.localizedDescription)", isError: true)
        }
    }

    func promptExportCape() {
        guard let theme = selectedTheme else { return }
        let panel = NSSavePanel()
        panel.title = "导出为 macOS (.cape) 光标主题包"
        panel.nameFieldStringValue = "\(theme.name).cape"
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try CapeCoder.exportCape(theme: theme, to: url)
                setStatus("已成功导出 .cape 文件至: \(url.path)", isError: false)
            } catch {
                setStatus("导出 .cape 失败: \(error.localizedDescription)", isError: true)
            }
        }
    }

    // MARK: - Apply & Restore on macOS

    func applyTheme(_ theme: CursorTheme) {
        guard theme.assignedRolesCount > 0 else {
            setStatus("当前主题尚未配置任何光标，请先导入 .cur / .ani 文件", isError: true)
            return
        }

        let res = SkyLightCursorBridge.shared.applyTheme(theme)
        if res.succeeded > 0 {
            activeThemeID = theme.id
            UserDefaults.standard.set(theme.id.uuidString, forKey: "activeThemeID")
            setStatus(
                "已应用「\(theme.name)」到 MacBook（成功注册 \(res.succeeded) 个系统光标标识符，尺寸 \(Int(theme.targetPointSize))pt）",
                isError: false
            )
        } else {
            setStatus("应用光标失败：未能调用 SkyLight 接口 (failed=\(res.failed))", isError: true)
        }
    }

    func applySelectedThemeToMac() {
        guard let theme = selectedTheme else { return }
        applyTheme(theme)
    }

    func restoreSystemDefaultCursor() {
        let ok = SkyLightCursorBridge.shared.restoreSystemDefaults(silent: false)
        activeThemeID = nil
        UserDefaults.standard.removeObject(forKey: "activeThemeID")
        if ok {
            setStatus("已恢复 macOS 系统默认鼠标光标", isError: false)
        } else {
            setStatus("恢复默认光标失败", isError: true)
        }
    }

    // MARK: - Wake / Session Persistence

    private func setupWakeObservers() {
        let wsCenter = NSWorkspace.shared.notificationCenter
        wakeObserver = wsCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reapplyActiveThemeIfNeeded(reason: "系统休眠唤醒")
            }
        }

        sessionObserver = wsCenter.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reapplyActiveThemeIfNeeded(reason: "会话激活")
            }
        }
    }

    private func reapplyActiveThemeIfNeeded(reason: String) {
        guard keepAliveOnWake,
              let activeID = activeThemeID,
              let theme = themes.first(where: { $0.id == activeID }) else {
            return
        }
        let res = SkyLightCursorBridge.shared.applyTheme(theme)
        if res.succeeded > 0 {
            setStatus("\(reason)：已自动重新同步「\(theme.name)」光标", isError: false)
        }
    }

    private func setStatus(_ msg: String, isError: Bool) {
        self.statusMessage = msg
        self.isStatusError = isError
    }
}
