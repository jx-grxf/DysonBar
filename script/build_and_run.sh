#!/usr/bin/env bash
# Builds the app bundle in dist/. Modes: run (default), build, release.
# release = optimized, Developer ID signed with hardened runtime, ready for a DMG.
set -euo pipefail

MODE="${1:-run}"
APP_NAME="DysonBar"
BUNDLE_ID="at.johannesgrof.DysonBar"
VERSION="${DYSONBAR_VERSION:-0.1.0}"
MIN_SYSTEM_VERSION="15.0"
SPARKLE_FEED_URL="https://github.com/jx-grxf/DysonBar/releases/latest/download/appcast.xml"
# The private half lives in the login Keychain under the account "dysonbar"
# (Sparkle's generate_keys --account dysonbar).
SPARKLE_PUBLIC_KEY="gCPtLQhTrJE+2fAILj9s/khuYUBYV0ZFfz0tebRHbOs="

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_NUMBER="${DYSONBAR_BUILD:-$(git -C "$ROOT_DIR" rev-list --count HEAD 2>/dev/null || echo 1)}"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
RESOURCES="$CONTENTS/Resources"
FRAMEWORKS="$CONTENTS/Frameworks"

if [[ "$MODE" == "release" ]]; then
  CONFIGURATION="release"
  SIGN_IDENTITY="${DYSONBAR_SIGN_IDENTITY:-Developer ID Application}"
else
  CONFIGURATION="${DYSONBAR_CONFIGURATION:-debug}"
  # A stable identity keeps the Keychain "Always allow" across rebuilds; ad-hoc
  # signatures change with every build and would ask again each time.
  SIGN_IDENTITY="${DYSONBAR_SIGN_IDENTITY:-Apple Development}"
fi

cd "$ROOT_DIR"
if [[ "$CONFIGURATION" == "release" ]]; then
  swift build -c release --arch arm64 --arch x86_64
  BIN_PATH="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
else
  swift build -c "$CONFIGURATION"
  BIN_PATH="$(swift build -c "$CONFIGURATION" --show-bin-path)"
fi

[[ "$MODE" == "run" ]] && { pkill -x "$APP_NAME" >/dev/null 2>&1 || true; }
rm -rf "$APP_BUNDLE"
mkdir -p "$CONTENTS/MacOS" "$RESOURCES" "$FRAMEWORKS"
cp "$BIN_PATH/$APP_NAME" "$CONTENTS/MacOS/$APP_NAME"

SPARKLE_FRAMEWORK="$(find "$ROOT_DIR/.build/artifacts" -path '*macos*/Sparkle.framework' -type d -prune | head -n 1)"
[[ -z "$SPARKLE_FRAMEWORK" ]] && SPARKLE_FRAMEWORK="$(find "$ROOT_DIR/.build/artifacts" -name Sparkle.framework -type d -prune | head -n 1)"
ditto "$SPARKLE_FRAMEWORK" "$FRAMEWORKS/Sparkle.framework"

xcrun xcstringstool compile "$ROOT_DIR/Sources/DysonBar/Resources/Localizable.xcstrings" \
  --output-directory "$RESOURCES" >/dev/null

# Info.plist strings shown by macOS itself (local network prompt).
mkdir -p "$RESOURCES/en.lproj" "$RESOURCES/de.lproj"
cat >"$RESOURCES/en.lproj/InfoPlist.strings" <<'STRINGS'
"NSLocalNetworkUsageDescription" = "DysonBar talks to your Dyson purifier directly over your Wi-Fi, without the Dyson cloud.";
STRINGS
cat >"$RESOURCES/de.lproj/InfoPlist.strings" <<'STRINGS'
"NSLocalNetworkUsageDescription" = "DysonBar spricht direkt über dein WLAN mit deinem Dyson-Luftreiniger, ohne Dyson-Cloud.";
STRINGS

# Liquid Glass icon for macOS 26, plus the .icns fallback actool derives for older systems.
ICON_PARTIAL="$ROOT_DIR/.build/icon-partial.plist"
xcrun actool "$ROOT_DIR/Assets/AppIcon.icon" \
  --compile "$RESOURCES" \
  --platform macosx \
  --minimum-deployment-target "$MIN_SYSTEM_VERSION" \
  --app-icon AppIcon \
  --output-partial-info-plist "$ICON_PARTIAL" >/dev/null

cat >"$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>de</string></array>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIconName</key><string>AppIcon</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHumanReadableCopyright</key><string>MIT License. Not affiliated with Dyson.</string>
  <key>NSLocalNetworkUsageDescription</key>
  <string>DysonBar talks to your Dyson purifier directly over your Wi-Fi, without the Dyson cloud.</string>
  <key>NSBonjourServices</key><array><string>_dyson_mqtt._tcp</string></array>
  <key>SUFeedURL</key><string>$SPARKLE_FEED_URL</string>
  <key>SUPublicEDKey</key><string>$SPARKLE_PUBLIC_KEY</string>
  <key>SUEnableAutomaticChecks</key><true/>
  <key>SUScheduledCheckInterval</key><integer>86400</integer>
</dict>
</plist>
PLIST

# Inside out: Sparkle's helpers first, then the framework, then the app.
# --deep would re-sign the helpers without their own entitlements.
sign() { codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp "$@"; }
if [[ "$MODE" != "release" ]]; then
  sign() { codesign --force --sign "$SIGN_IDENTITY" --options runtime "$@" 2>/dev/null \
    || codesign --force --sign - "$@"; }
fi
SPARKLE_B="$FRAMEWORKS/Sparkle.framework/Versions/B"
sign "$SPARKLE_B/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$SPARKLE_B/XPCServices/Downloader.xpc"
sign "$SPARKLE_B/Autoupdate"
sign "$SPARKLE_B/Updater.app"
sign "$FRAMEWORKS/Sparkle.framework"
sign "$APP_BUNDLE"

case "$MODE" in
  run) open "$APP_BUNDLE" ;;
  build | release) ;;
  *) echo "usage: $0 [run|build|release]" >&2; exit 2 ;;
esac
echo "$APP_BUNDLE"
