#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
BUILD_DIR="$ROOT_DIR/build"
APP_BUNDLE="$BUILD_DIR/MouseSwitch.app"
MACOS_DIR="$APP_BUNDLE/Contents/MacOS"
RESOURCES_DIR="$APP_BUNDLE/Contents/Resources"

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" /tmp/swift-module-cache

echo "🔨 正在编译 MouseSwitch 原生 macOS 应用..."
swiftc \
    -disable-sandbox \
    -module-cache-path /tmp/swift-module-cache \
    -parse-as-library \
    -target arm64-apple-macosx13.0 \
    -O \
    "$ROOT_DIR/Sources/MouseSwitch/Models/CursorModels.swift" \
    "$ROOT_DIR/Sources/MouseSwitch/Parsers/WinCursorParser.swift" \
    "$ROOT_DIR/Sources/MouseSwitch/Parsers/InfAndPackImporter.swift" \
    "$ROOT_DIR/Sources/MouseSwitch/Engine/CapeCoder.swift" \
    "$ROOT_DIR/Sources/MouseSwitch/Engine/SkyLightCursorBridge.swift" \
    "$ROOT_DIR/Sources/MouseSwitch/Generator/DemoWinCursorPackGenerator.swift" \
    "$ROOT_DIR/Sources/MouseSwitch/ViewModels/AppViewModel.swift" \
    "$ROOT_DIR/Sources/MouseSwitch/Views/AnimatedCursorPreviewView.swift" \
    "$ROOT_DIR/Sources/MouseSwitch/Views/CursorRoleEditorSheet.swift" \
    "$ROOT_DIR/Sources/MouseSwitch/Views/CursorTestSandboxView.swift" \
    "$ROOT_DIR/Sources/MouseSwitch/Views/MainWindowView.swift" \
    "$ROOT_DIR/Sources/MouseSwitch/MouseSwitchApp.swift" \
    -o "$MACOS_DIR/MouseSwitch"

cat > "$APP_BUNDLE/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleExecutable</key>
    <string>MouseSwitch</string>
    <key>CFBundleIdentifier</key>
    <string>com.mouseswitch.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>MouseSwitch</string>
    <key>CFBundleDisplayName</key>
    <string>MouseSwitch 光标转换器</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null || true

echo "✅ 已构建完成: $APP_BUNDLE"
