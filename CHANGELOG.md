# 变更日志

## [1.0.0] — 2026-10-27

### 新增
- 首次公开发布：Windows 光标 (`.cur` / `.ani` / `install.inf`) → macOS `.cape` 转换与系统注入工具
- 纯 Swift 二进制解析器 `WinCursorParser`：支持 `.cur`/`.ico` (PNG / DIB 32/24/16/8/4/1-bit) 与 `.ani` (RIFF ACON) 解包，提取热点与帧时长
- `InfAndPackImporter`：解析 `install.inf`（UTF-8 / UTF-16 / GB18030 / Windows-1252），智能文件名启发式角色匹配
- `CapeCoder`：合成 1x/2x Retina 垂直精灵图，支持 `.cape` 双向导入导出（兼容 Mousecape）
- `SkyLightCursorBridge`：通过私有框架 `CGSRegisterCursorWithImages` 全局注入系统光标；首次运行备份系统默认光标，一键无损恢复；休眠唤醒自动重新应用
- 图形界面 (SwiftUI) 与命令行 (CLI) 双模式：`--convert` / `--apply` / `--restore` / `--self-test`
- 端到端自测 `--self-test`，覆盖生成示例包、解析、`.cape` 往返、SkyLight 符号绑定

### 修复
- 修复 `CapeCoder.importCape` 中 `.cape` 导入时动画帧顺序被颠倒的问题（sprite sheet 帧 0 在顶部，cropping 需按 `frameCount-1-i` 取 Y）
- `--self-test` 新增 `.cape` 往返结构保真校验（帧数、时长、每帧非空）

### 构建 / 工程
- 构建脚本从直连 `swiftc`（硬编码 `arm64`）迁移至 `swift build -c release`，移除架构硬编码
- 添加 `Tests/MouseSwitchTests`（XCTest，4 个用例）与 GitHub Actions CI（macOS：build / test / self-test）
- 添加 `.gitignore`（构建产物、Xcode、macOS、AppSupport 运行时数据）
- README 补充私有 API 风险与已知限制章节

### 已知限制
- 依赖 `SkyLight.framework` 私有 API，符号可能随 macOS 版本变更；无法通过 App Store 审核，仅适合侧载/个人使用
- 当前未支持 Intel Mac（待构建流程进一步完善为通用架构）
