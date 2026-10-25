#!/usr/bin/env bash
# Builds a signed, notarized DMG and a Sparkle appcast for one version.
#
#   DYSONBAR_VERSION=0.1.0 DYSONBAR_NOTARY_PROFILE=<profile> ./script/release.sh
#
# The notary profile comes from `xcrun notarytool store-credentials <profile>`.
# Without it the DMG is built and signed but not notarized (for testing only).
# Uploading to GitHub stays a separate, manual step.
set -euo pipefail

APP_NAME="DysonBar"
VERSION="${DYSONBAR_VERSION:?Set DYSONBAR_VERSION, e.g. 0.1.0}"
TAG="v$VERSION"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/dist/release-$VERSION"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
DMG="$OUT_DIR/$APP_NAME-$VERSION.dmg"
SPARKLE_BIN="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin"
DOWNLOAD_PREFIX="https://github.com/jx-grxf/DysonBar/releases/download/$TAG/"

cd "$ROOT_DIR"
DYSONBAR_VERSION="$VERSION" ./script/build_and_run.sh release

codesign --verify --strict --deep "$APP_BUNDLE"
lipo -archs "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"
STAGING="$(mktemp -d)"
ditto "$APP_BUNDLE" "$STAGING/$APP_NAME.app"

create-dmg \
  --volname "$APP_NAME $VERSION" \
  --volicon "$APP_BUNDLE/Contents/Resources/AppIcon.icns" \
  --window-pos 200 120 \
  --window-size 560 360 \
  --icon-size 120 \
  --icon "$APP_NAME.app" 150 170 \
  --hide-extension "$APP_NAME.app" \
  --app-drop-link 410 170 \
  --no-internet-enable \
  "$DMG" "$STAGING" >/dev/null
rm -rf "$STAGING"
codesign --force --sign "Developer ID Application" --timestamp "$DMG"

if [[ -n "${DYSONBAR_NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$DYSONBAR_NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  spctl --assess --type open --context context:primary-signature -v "$DMG"
else
  echo "warning: DYSONBAR_NOTARY_PROFILE not set, DMG is NOT notarized" >&2
fi

# Release notes for this version become the update dialog's text.
awk -v version="$VERSION" '
  $0 ~ "^## " version "( |$)" { found = 1; next }
  found && /^## / { exit }
  found { print }
' "$ROOT_DIR/CHANGELOG.md" >"$OUT_DIR/$APP_NAME-$VERSION.md"

"$SPARKLE_BIN/generate_appcast" \
  --account dysonbar \
  --download-url-prefix "$DOWNLOAD_PREFIX" \
  --embed-release-notes \
  --link "https://github.com/jx-grxf/DysonBar" \
  "$OUT_DIR"

SHA="$(shasum -a 256 "$DMG" | cut -d' ' -f1)"
echo
echo "DMG:     $DMG"
echo "Appcast: $OUT_DIR/appcast.xml"
echo "SHA-256: $SHA"
echo
echo "Next: gh release create $TAG \"$DMG\" \"$OUT_DIR/appcast.xml\" --notes-file \"$OUT_DIR/$APP_NAME-$VERSION.md\""
echo "      then update Casks/dysonbar.rb in jx-grxf/homebrew-tap (version $VERSION, sha256 $SHA)"
