#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/Arklike.xcodeproj"
SCHEME="Arklike"
CONFIGURATION="Release"
APP_NAME="Arklike"
INFO_PLIST="$ROOT/Arklike/Info.plist"
BUILD_ROOT="$ROOT/.build/release"
DERIVED_DATA="$BUILD_ROOT/DerivedData"
DIST_DIR="$ROOT/dist"
VERSION="${VERSION:-}"
BUILD_NUMBER="${BUILD_NUMBER:-${GITHUB_RUN_NUMBER:-1}}"
APP_PATH="${APP_PATH:-$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_NAME.app}"

usage() {
  cat <<'EOF'
Usage:
  VERSION=0.1.0 BUILD_NUMBER=123 Scripts/package-release.sh --build
  VERSION=0.1.0 APP_PATH=/path/to/Arklike.app Scripts/package-release.sh --package

Commands:
  --build      Set bundle metadata and build an unsigned Release app.
  --package    Zip an already signed/notarized app and emit SHA256 metadata.

Required environment:
  VERSION      Release version, with or without leading v.

Optional environment:
  BUILD_NUMBER Build number for CFBundleVersion. Defaults to GITHUB_RUN_NUMBER or 1.
  APP_PATH     App path for --package. Defaults to the xcodebuild output path.
EOF
}

if [[ "${1:-}" == "--help" || -z "${1:-}" ]]; then
  usage
  exit 0
fi

if [[ -z "$VERSION" ]]; then
  echo "VERSION is required, e.g. VERSION=0.1.0 Scripts/package-release.sh --build" >&2
  exit 1
fi
VERSION="${VERSION#v}"

build_app() {
  echo "Building $APP_NAME $VERSION ($BUILD_NUMBER)"

  rm -rf "$BUILD_ROOT"
  mkdir -p "$BUILD_ROOT"

  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$INFO_PLIST"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$INFO_PLIST"

  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO \
    clean build

  if [[ ! -d "$APP_PATH" ]]; then
    echo "Expected app was not built at $APP_PATH" >&2
    exit 1
  fi

  echo "Built app: $APP_PATH"

  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "app_path=$APP_PATH" >> "$GITHUB_OUTPUT"
  fi
}

package_app() {
  if [[ ! -d "$APP_PATH" ]]; then
    echo "Expected app does not exist at $APP_PATH" >&2
    exit 1
  fi

  mkdir -p "$DIST_DIR"

  FINAL_ZIP="$DIST_DIR/$APP_NAME-$VERSION.zip"
  rm -f "$FINAL_ZIP" "$FINAL_ZIP.sha256"
  ditto -c -k --keepParent "$APP_PATH" "$FINAL_ZIP"

  SHA256="$(shasum -a 256 "$FINAL_ZIP" | awk '{print $1}')"
  printf '%s  %s\n' "$SHA256" "$(basename "$FINAL_ZIP")" > "$FINAL_ZIP.sha256"

  echo "Built artifact: $FINAL_ZIP"
  echo "SHA256: $SHA256"

  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    {
      echo "zip_path=$FINAL_ZIP"
      echo "sha256_path=$FINAL_ZIP.sha256"
      echo "sha256=$SHA256"
      echo "asset_name=$(basename "$FINAL_ZIP")"
    } >> "$GITHUB_OUTPUT"
  fi
}

case "${1:-}" in
  --build)
    build_app
    ;;
  --package)
    package_app
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
