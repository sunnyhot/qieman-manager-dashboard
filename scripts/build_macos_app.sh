#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="${APP_NAME:-QiemanDashboard}"
APP_DISPLAY_NAME="${APP_DISPLAY_NAME:-且慢主理人}"
APP_VERSION="${APP_VERSION:-2.1.0}"
APP_BUILD="${APP_BUILD:-$(date +%Y%m%d%H%M)}"
BUNDLE_ID="${BUNDLE_ID:-com.sunnyhot.qieman.manager.dashboard}"
MIN_MACOS_VERSION="${MIN_MACOS_VERSION:-14.0}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
TARGET_ARCH="${TARGET_ARCH:-$(uname -m)}"
DIST_DIR="$ROOT_DIR/dist/macos-app"
APP_DIR="$DIST_DIR/${APP_NAME}.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
PAYLOAD_DIR="$RESOURCES_DIR/project"
ICONSET_DIR="$DIST_DIR/${APP_NAME}.iconset"
ICON_FILE="$RESOURCES_DIR/${APP_NAME}.icns"
ZIP_FILE="$DIST_DIR/${APP_NAME}-${APP_VERSION}.zip"
SWIFT_SOURCES=()

while IFS= read -r file; do
  SWIFT_SOURCES+=("$file")
done < <(find "$ROOT_DIR/macos-app" -name '*.swift' ! -name 'Package.swift' | sort)

echo "[1/8] 清理旧产物"
rm -rf "$APP_DIR"
rm -rf "$ICONSET_DIR"
rm -f "$ZIP_FILE"
mkdir -p "$MACOS_DIR" "$PAYLOAD_DIR" "$PAYLOAD_DIR/output" "$RESOURCES_DIR"

echo "[2/8] 生成 App 图标"
swift "$ROOT_DIR/scripts/render_macos_icon.swift" "$ICONSET_DIR"
iconutil -c icns "$ICONSET_DIR" -o "$ICON_FILE"

echo "[3/8] 编译原生 macOS 应用"
swiftc \
  "${SWIFT_SOURCES[@]}" \
  -O \
  -target "${TARGET_ARCH}-apple-macos${MIN_MACOS_VERSION}" \
  -framework SwiftUI \
  -framework WebKit \
  -framework AppKit \
  -framework Vision \
  -framework UniformTypeIdentifiers \
  -o "$MACOS_DIR/$APP_NAME"

echo "[4/8] 写入 Bundle 元数据"
cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>__APP_NAME__</string>
  <key>CFBundleDisplayName</key>
  <string>__APP_DISPLAY_NAME__</string>
  <key>CFBundleIconFile</key>
  <string>__APP_NAME__</string>
  <key>CFBundleIdentifier</key>
  <string>__BUNDLE_ID__</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>__APP_DISPLAY_NAME__</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>__APP_VERSION__</string>
  <key>CFBundleVersion</key>
  <string>__APP_BUILD__</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.finance</string>
  <key>LSMinimumSystemVersion</key>
  <string>__MIN_MACOS_VERSION__</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSHumanReadableCopyright</key>
  <string>Copyright © 2026 sunnyhot. All rights reserved.</string>
</dict>
</plist>
PLIST
perl -0pi -e 's#__APP_NAME__#'"$APP_NAME"'#g; s#__APP_DISPLAY_NAME__#'"$APP_DISPLAY_NAME"'#g; s#__APP_VERSION__#'"$APP_VERSION"'#g; s#__APP_BUILD__#'"$APP_BUILD"'#g; s#__BUNDLE_ID__#'"$BUNDLE_ID"'#g; s#__MIN_MACOS_VERSION__#'"$MIN_MACOS_VERSION"'#g' "$CONTENTS_DIR/Info.plist"
printf 'APPL????' > "$CONTENTS_DIR/PkgInfo"

echo "[5/8] 拷贝项目运行文件"
cp "$ROOT_DIR/dashboard_server.py" "$PAYLOAD_DIR/"
cp "$ROOT_DIR/qieman_community_scraper.py" "$PAYLOAD_DIR/"
cp "$ROOT_DIR/qieman_scraper.py" "$PAYLOAD_DIR/"
cp "$ROOT_DIR/README.md" "$PAYLOAD_DIR/"
cp -R "$ROOT_DIR/scripts" "$PAYLOAD_DIR/"
cp -R "$ROOT_DIR/skills" "$PAYLOAD_DIR/"
if [ -d "$ROOT_DIR/output" ]; then
  rsync -a \
    --exclude 'watch-state-*' \
    "$ROOT_DIR/output/" "$PAYLOAD_DIR/output/"
fi

cat > "$PAYLOAD_DIR/APP_BUNDLE_README.txt" <<'TXT'
This app bundle contains a copy of the Python project files.

Runtime data location:
~/Library/Application Support/QiemanDashboard

Put your login cookie here if needed:
~/Library/Application Support/QiemanDashboard/qieman.cookie

The bundled app also ships with snapshot backups from the legacy web dashboard.
TXT

echo "[6/8] 进行 Bundle 签名"
codesign --force --deep --sign "$SIGN_IDENTITY" --timestamp=none "$APP_DIR"

echo "[7/8] 验证签名与可执行性"
codesign --verify --deep --strict "$APP_DIR"
if spctl_output="$(spctl --assess --type execute "$APP_DIR" 2>&1)"; then
  echo "Gatekeeper 校验通过"
else
  echo "Gatekeeper 结果: ${spctl_output}"
  echo "提示: 当前产物是本地 ad-hoc 签名，适合自用与测试；若要对外分发并消除系统警告，还需要 Apple Developer 证书与 notarization。"
fi

echo "[8/8] 生成分发压缩包"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_FILE"

echo "完成"
echo "App 已生成: $APP_DIR"
echo "压缩包: $ZIP_FILE"
echo "运行方式: open \"$APP_DIR\""
