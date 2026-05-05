#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${CONFIG:-Debug}"
BUILD_DIR="$ROOT/.build/$CONFIG"
APP="$BUILD_DIR/Arklike.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"

rm -rf "$APP"
mkdir -p "$MACOS"

SOURCES=()
while IFS= read -r -d '' file; do
  SOURCES+=("$file")
done < <(find "$ROOT/Arklike" -maxdepth 1 -name '*.swift' -print0 | sort -z)

swiftc \
  -target arm64-apple-macosx14.0 \
  -parse-as-library \
  -Ounchecked \
  "${SOURCES[@]}" \
  -framework AppKit \
  -framework SwiftUI \
  -framework Carbon \
  -framework ApplicationServices \
  -framework CoreServices \
  -framework UserNotifications \
  -framework OSLog \
  -o "$MACOS/Arklike"

python3 - "$ROOT/Arklike/Info.plist" "$CONTENTS/Info.plist" <<'PY'
import sys
from pathlib import Path
src = Path(sys.argv[1]).read_text()
replacements = {
    '$(DEVELOPMENT_LANGUAGE)': 'en',
    '$(EXECUTABLE_NAME)': 'Arklike',
    '$(PRODUCT_BUNDLE_IDENTIFIER)': 'com.arklike.app',
    '$(PRODUCT_NAME)': 'Arklike',
    '$(PRODUCT_BUNDLE_PACKAGE_TYPE)': 'APPL',
    '$(MACOSX_DEPLOYMENT_TARGET)': '14.0',
}
for k, v in replacements.items():
    src = src.replace(k, v)
Path(sys.argv[2]).write_text(src)
PY

plutil -lint "$CONTENTS/Info.plist" >/dev/null

# Ad-hoc sign for local execution. Permissions are tied to the built app path,
# so keep using the same .build/Debug/Arklike.app path while testing.
codesign --force --deep --sign - --entitlements "$ROOT/Arklike/Arklike.entitlements" "$APP" >/dev/null

echo "Built: $APP"

if [[ "${1:-}" == "--run" ]]; then
  open "$APP"
fi
