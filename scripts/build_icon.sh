#!/bin/bash
# 生成 AppIcon.icns（便签待办应用图标）
# 依赖：swift、sips、iconutil（macOS 自带）
set -e
cd "$(dirname "$0")/.."

WORK=".iconset.work"
OUT="Resources/AppIcon.icns"
PNG_1024=".build/AppIcon_1024.png"

mkdir -p Resources .build "$WORK"
rm -f "$WORK"/*.png

echo "==> 绘制 1024 主图 ..."
swift scripts/make_icon.swift "$PNG_1024"

echo "==> 生成多尺寸 PNG ..."
# iconutil 需要的标准 iconset 尺寸
sips -z 16 16     "$PNG_1024" --out "$WORK/icon_16x16.png"        >/dev/null
sips -z 32 32     "$PNG_1024" --out "$WORK/icon_16x16@2x.png"     >/dev/null
sips -z 32 32     "$PNG_1024" --out "$WORK/icon_32x32.png"        >/dev/null
sips -z 64 64     "$PNG_1024" --out "$WORK/icon_32x32@2x.png"     >/dev/null
sips -z 128 128   "$PNG_1024" --out "$WORK/icon_128x128.png"      >/dev/null
sips -z 256 256   "$PNG_1024" --out "$WORK/icon_128x128@2x.png"   >/dev/null
sips -z 256 256   "$PNG_1024" --out "$WORK/icon_256x256.png"      >/dev/null
sips -z 512 512   "$PNG_1024" --out "$WORK/icon_256x256@2x.png"   >/dev/null
sips -z 512 512   "$PNG_1024" --out "$WORK/icon_512x512.png"      >/dev/null
cp "$PNG_1024"      "$WORK/icon_512x512@2x.png"

echo "==> 打包 icns ..."
# iconutil 要求目录名以 .iconset 结尾
ICONSET_DIR=".AppIcon.iconset"
rm -rf "$ICONSET_DIR"
mv "$WORK" "$ICONSET_DIR"
iconutil -c icns "$ICONSET_DIR" -o "$OUT"
rm -rf "$ICONSET_DIR"

echo "==> 图标完成: $OUT"
