#!/usr/bin/env bash
set -euo pipefail

VERSION="${VERSION:-}"
SHA256="${SHA256:-}"
TAP_REPOSITORY="${TAP_REPOSITORY:-}"
TAP_REPO_PAT="${TAP_REPO_PAT:-}"
TAP_CASK_PATH="${TAP_CASK_PATH:-Casks/arklike.rb}"
TAP_CASK_TOKEN="${TAP_CASK_TOKEN:-arklike}"
SOURCE_REPOSITORY="${SOURCE_REPOSITORY:-${GITHUB_REPOSITORY:-CarterMcAlister/arklike}}"
APP_NAME="Arklike"
BUNDLE_ID="com.arklike.app"

usage() {
  cat <<'EOF'
Usage: VERSION=0.1.0 SHA256=... TAP_REPOSITORY=owner/homebrew-tools TAP_REPO_PAT=... Scripts/update-homebrew-cask.sh

Optional environment:
  TAP_CASK_PATH     Path in tap repo, default Casks/arklike.rb
  TAP_CASK_TOKEN    Cask token, default arklike
  SOURCE_REPOSITORY Source GitHub repo, default GITHUB_REPOSITORY
EOF
}

if [[ "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

for required in VERSION SHA256 TAP_REPOSITORY TAP_REPO_PAT; do
  if [[ -z "${!required:-}" ]]; then
    echo "$required is required" >&2
    exit 1
  fi
done
VERSION="${VERSION#v}"

WORKDIR="$(mktemp -d)"
cleanup() {
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

TAP_DIR="$WORKDIR/tap"
git clone "https://x-access-token:${TAP_REPO_PAT}@github.com/${TAP_REPOSITORY}.git" "$TAP_DIR" >/dev/null 2>&1
cd "$TAP_DIR"

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

mkdir -p "$(dirname "$TAP_CASK_PATH")"
cat > "$TAP_CASK_PATH" <<EOF
cask "$TAP_CASK_TOKEN" do
  version "$VERSION"
  sha256 "$SHA256"

  url "https://github.com/$SOURCE_REPOSITORY/releases/download/v#{version}/$APP_NAME-#{version}.zip"
  name "$APP_NAME"
  desc "Arc-style Safari workflows for macOS"
  homepage "https://github.com/$SOURCE_REPOSITORY"

  depends_on macos: ">= :sonoma"

  app "$APP_NAME.app"

  uninstall quit: "$BUNDLE_ID"

  zap trash: [
    "~/Library/Preferences/$BUNDLE_ID.plist",
  ]
end
EOF

if git diff --quiet -- "$TAP_CASK_PATH"; then
  echo "Homebrew cask is already up to date"
  exit 0
fi

git add "$TAP_CASK_PATH"
git commit -m "Update $TAP_CASK_TOKEN to $VERSION"
git push

echo "Updated $TAP_REPOSITORY:$TAP_CASK_PATH to $VERSION"
