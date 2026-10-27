# MouseSwitch — Windows 光标转 macOS (`.cape`) 及一键应用工具

原生 macOS (Swift + SwiftUI) 应用，支持将 Windows 鼠标光标文件（`.cur` 静态光标、`.ani` 动态光标、`install.inf` 主题安装包）直接转换为 macOS 标准 `.cape` 格式，并通过 `SkyLight.framework` / `CoreGraphics` 私有接口**免关闭 SIP、免 Root 权限一键在 MacBook 上全局生效**。

---

## 核心特性

1. **纯 Swift 原生二进制解析器 (`WinCursorParser`)**
   - **`.cur` / `.ico` 解析**：完整支持内嵌 PNG 以及 Windows 传统 `BITMAPINFOHEADER` DIB 位图（32-bit BGRA、24-bit BGR、16/8/4/1-bit 调色板 + 1-bit AND 透明掩码），精准提取像素级 Hotspot `(X, Y)`。
   - **`.ani` 动画光标解析**：完整解包 `RIFF ACON` 容器（`anih`、`seq ` 帧序列、`rate` 可变帧时长、`LIST(fram -> icon)`），自动将帧展开并合成为 macOS 硬件光标所需的**垂直精灵图（Vertical Sprite Sheet）**，并对超过 24 帧的动画自动等距重采样以适配 macOS `WindowServer` 限制。
   - **`install.inf` 与智能角色识别 (`InfAndPackImporter`)**：自动识别 UTF-8 / UTF-16 / GB18030 (GBK) / Windows-1252 编码的 `.inf` 安装脚本；对于无 `.inf` 的文件夹，内置中英文文件名启发式匹配规则。
2. **Retina HiDPI 多倍图合成与 `.cape` 双向兼容 (`CapeCoder`)**
   - 自动生成 `1x` 与 `2x` (Retina) 垂直拼接精灵图，按所选逻辑点尺寸（如 `24pt Retina 推荐` 或 `32pt`）自动换算热点坐标。
   - 支持导出与导入兼容 **Mousecape** 的 `.cape` (Property List) 文件。
3. **macOS 系统直接注入与安全还原 (`SkyLightCursorBridge`)**
   - 动态调用 `SkyLight.framework` 的 `CGSRegisterCursorWithImages` 接口，同时注册传统标识符与新版 macOS (`ArrowS`、`IBeamS` 等) 兼容标识符。
   - 首次运行自动通过 `CGSCopyRegisteredCursorImages` 备份当前系统原生多倍图光标至 `~/Library/Application Support/MouseSwitch/SystemDefaultBackup.plist`，随时支持**一键无损恢复 Mac 系统默认光标**。
   - 内置状态栏常驻菜单（`MenuBarExtra`）与系统休眠唤醒监听（`NSWorkspace.didWakeNotification`），睡眠唤醒后自动保持自定义光标。

---

## 快速构建与运行

### 1. 构建 `.app` 应用包

```bash
./scripts/build_app.sh
```

构建完成后，原生应用位于：
`build/MouseSwitch.app`

### 2. 启动图形界面 (GUI)

```bash
open build/MouseSwitch.app
```

### 3. 命令行模式 (CLI)

`MouseSwitch` 同时内置了命令行工具模式：

```bash
# 查看帮助
./build/MouseSwitch.app/Contents/MacOS/MouseSwitch --help

# 运行端到端二进制自检
./build/MouseSwitch.app/Contents/MacOS/MouseSwitch --self-test

# 将 Windows 光标文件夹或 .inf/.cur/.ani 转换为 .cape 文件
./build/MouseSwitch.app/Contents/MacOS/MouseSwitch --convert ./samples/CyberNeon_Windows_Pack --out ./samples/CyberNeon.cape --size 24

# 直接将 Windows 光标包或 .cape 应用到当前 MacBook
./build/MouseSwitch.app/Contents/MacOS/MouseSwitch --apply ./samples/CyberNeon_Windows_Pack --size 24

# 一键恢复 macOS 系统默认鼠标光标
./build/MouseSwitch.app/Contents/MacOS/MouseSwitch --restore
```

---

## 已知限制与私有 API 风险

- **`SkyLight.framework` 私有 API**：系统光标注入依赖通过 `dlopen` 动态绑定 `/System/Library/PrivateFrameworks/SkyLight.framework` 的 `CGSRegisterCursorWithImages` 等私有符号。该符号可能随 macOS 版本（Sonoma / Sequoia / Tahoe / macOS 27 等）变更而失效；使用私有 API 无法通过 App Store 审核，仅适合侧载或个人使用。若目标系统符号不可用，CLI 会返回错误并提示。
- **免 SIP / 免 Root**：注入本身不要求关闭 SIP 或 Root 权限，但私有 API 调用仍可能受系统完整性保护与 Gatekeeper 审查，具体表现因 macOS 版本而异。
- **架构支持**：当前构建脚本硬编码 `arm64-apple-macosx13.0`，暂不支持 Intel Mac；后续将迁移至 `swift build` 并支持通用架构。
