#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/Arklike.xcodeproj"
SCHEME="Arklike"
CONFIGURATION="Release"
APP_NAME="Arklike"
BUNDLE_ID="com.arklike.app"
ENTITLEMENTS="$ROOT/Arklike/Arklike.entitlements"
INFO_PLIST="$ROOT/Arklike/Info.plist"
BUILD_ROOT="$ROOT/.build/release"
DERIVED_DATA="$BUILD_ROOT/DerivedData"
DIST_DIR="$ROOT/dist"
VERSION="${VERSION:-}"
BUILD_NUMBER="${BUILD_NUMBER:-${GITHUB_RUN_NUMBER:-1}}"
SIGNING_IDENTITY="${MACOS_SIGNING_IDENTITY:-}"

usage() {
  cat <<'EOF'
Usage: VERSION=0.1.0 BUILD_NUMBER=123 Scripts/package-release.sh

Required environment:
  VERSION                         Release version without leading v
  APPLE_ID                        Apple ID used for notarization
  APPLE_TEAM_ID                   Apple Developer Team ID
  APPLE_APP_SPECIFIC_PASSWORD     App-specific password for notarytool

Optional environment:
  MACOS_SIGNING_IDENTITY          Developer ID Application identity. If omitted, the first matching identity is used.
EOF
}

if [[ "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ -z "$VERSION" ]]; then
  echo "VERSION is required, e.g. VERSION=0.1.0 Scripts/package-release.sh" >&2
  exit 1
fi
VERSION="${VERSION#v}"

for required in APPLE_ID APPLE_TEAM_ID APPLE_APP_SPECIFIC_PASSWORD; do
  if [[ -z "${!required:-}" ]]; then
    echo "$required is required for notarization" >&2
    exit 1
  fi
done

if [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' | head -n 1)"
fi

if [[ -z "$SIGNING_IDENTITY" ]]; then
  echo "Could not find a Developer ID Application signing identity" >&2
  security find-identity -v -p codesigning || true
  exit 1
fi

echo "Packaging $APP_NAME $VERSION ($BUILD_NUMBER)"
echo "Signing identity: $SIGNING_IDENTITY"

rm -rf "$BUILD_ROOT" "$DIST_DIR"
mkdir -p "$BUILD_ROOT" "$DIST_DIR"

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

APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_NAME.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Expected app was not built at $APP_PATH" >&2
  exit 1
fi

codesign \
  --force \
  --timestamp \
  --options runtime \
  --entitlements "$ENTITLEMENTS" \
  --sign "$SIGNING_IDENTITY" \
  "$APP_PATH"

codesign --verify --strict --verbose=2 "$APP_PATH"

NOTARY_ZIP="$BUILD_ROOT/$APP_NAME-notary.zip"
ditto -c -k --keepParent "$APP_PATH" "$NOTARY_ZIP"

xcrun notarytool submit "$NOTARY_ZIP" \
  --apple-id "$APPLE_ID" \
  --team-id "$APPLE_TEAM_ID" \
  --password "$APPLE_APP_SPECIFIC_PASSWORD" \
  --wait

xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"
spctl --assess --type execute --verbose=4 "$APP_PATH"

FINAL_ZIP="$DIST_DIR/$APP_NAME-$VERSION.zip"
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
