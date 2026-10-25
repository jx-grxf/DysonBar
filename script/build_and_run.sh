#!/usr/bin/env bash
set -euo pipefail

APP_NAME="DysonBar"
BUNDLE_ID="at.johannesgrof.DysonBar"
CONFIGURATION="${DYSONBAR_CONFIGURATION:-release}"
# A stable identity keeps the Keychain "Always allow" across rebuilds; ad-hoc
# signatures change with every build and would ask again each time.
SIGN_IDENTITY="${DYSONBAR_SIGN_IDENTITY:-Apple Development}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"

cd "$ROOT_DIR"
swift build -c "$CONFIGURATION"
BIN_PATH="$(swift build -c "$CONFIGURATION" --show-bin-path)"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BIN_PATH/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

cat >"$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleDevelopmentRegion</key><string>de</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSUIElement</key><true/>
  <key>NSLocalNetworkUsageDescription</key>
  <string>DysonBar spricht direkt mit deinem Dyson-Luftreiniger im WLAN, ohne Umweg über die Cloud.</string>
  <key>NSBonjourServices</key>
  <array><string>_dyson_mqtt._tcp</string></array>
</dict>
</plist>
PLIST

codesign --force --sign "$SIGN_IDENTITY" "$APP_BUNDLE" 2>/dev/null \
  || codesign --force --sign - "$APP_BUNDLE"

if [[ "${1:-run}" == "run" ]]; then
  open "$APP_BUNDLE"
fi
echo "$APP_BUNDLE"
