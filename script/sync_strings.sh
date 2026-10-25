#!/usr/bin/env bash
# Collects every localizable string the compiler sees and merges it into the
# String Catalog. New keys show up untranslated; translate them in Xcode or by hand.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CATALOG="$ROOT_DIR/Sources/DysonBar/Resources/Localizable.xcstrings"
BUILD_PATH="$ROOT_DIR/.build/strings"

cd "$ROOT_DIR"
swift build --build-path "$BUILD_PATH" -Xswiftc -emit-localized-strings >/dev/null
if [[ ! -f "$CATALOG" ]]; then
  printf '{\n  "sourceLanguage" : "en",\n  "strings" : {},\n  "version" : "1.0"\n}\n' >"$CATALOG"
fi
args=()
while IFS= read -r file; do args+=(--stringsdata "$file"); done \
  < <(find "$BUILD_PATH" -name '*.stringsdata' -path '*Dyson*')
xcrun xcstringstool sync "$CATALOG" "${args[@]}"
echo "$CATALOG"
