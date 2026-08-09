#!/bin/bash
# 编译并打包 WeChatTodo.app
set -e
cd "$(dirname "$0")"

APP_NAME="便签待办"
BUNDLE_ID="com.zaza.WeChatTodo"

echo "==> swift build ..."
swift build -c release

echo "==> 生成应用图标 ..."
./scripts/build_icon.sh

BIN=".build/release/WeChatTodo"
DIST="dist/${APP_NAME}.app"

rm -rf "$DIST"
mkdir -p "$DIST/Contents/MacOS"
mkdir -p "$DIST/Contents/Resources"

cp "$BIN" "$DIST/Contents/MacOS/WeChatTodo"
cp "Resources/AppIcon.icns" "$DIST/Contents/Resources/AppIcon.icns"

cat > "$DIST/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>WeChatTodo</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# 刷新 Finder/Dock 缓存，避免旧图标残留（仅本地构建有用，失败不阻断）
touch "$DIST" 2>/dev/null || true

echo "==> 打包完成: $DIST"
