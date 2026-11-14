#!/bin/zsh
# Builds dist/Scout.zip, the download people get from GitHub Releases and the website.
#
#   ./scripts/release.sh            build and check the zip
#   ./scripts/release.sh --publish  also tag v<version> and publish a GitHub Release
#                                   (notes from scripts/release-notes.md)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(sed -nE 's/^ *MARKETING_VERSION: *"?([^"]+)"?.*/\1/p' project.yml)
TAG="v$VERSION"
APP=build/Build/Products/Release/Scout.app
ZIP=dist/Scout.zip

echo "Building Scout $VERSION (Apple silicon + Intel)…"
xcodegen --quiet
xcodebuild -scheme Scout -configuration Release -derivedDataPath build \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO build -quiet

# Ad-hoc signature: runs on any Mac after "Open Anyway". (A Developer ID + notarization
# would skip that step; see docs/DEVELOPING.md.)
codesign --force --options runtime --timestamp=none -s - "$APP/Contents/Helpers/scout"
codesign --force --options runtime --timestamp=none --entitlements Scout/Scout.entitlements -s - "$APP"
codesign --verify --deep --strict "$APP"

rm -rf dist && mkdir -p dist
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

# Check the zip: it unpacks to a valid, universal Scout.app.
CHECK=$(mktemp -d)
ditto -x -k "$ZIP" "$CHECK"
codesign --verify --deep --strict "$CHECK/Scout.app"
lipo -archs "$CHECK/Scout.app/Contents/MacOS/Scout" | grep -q arm64
lipo -archs "$CHECK/Scout.app/Contents/MacOS/Scout" | grep -q x86_64
rm -rf "$CHECK"

echo "Built $ZIP ($(du -h "$ZIP" | cut -f1 | xargs)), sha256 $(shasum -a 256 "$ZIP" | cut -c1-16)…"

if [[ "${1:-}" == "--publish" ]]; then
  if gh release view "$TAG" >/dev/null 2>&1; then
    echo "Release $TAG exists; replacing its Scout.zip."
    gh release upload "$TAG" "$ZIP" --clobber
  else
    gh release create "$TAG" "$ZIP" --title "Scout $VERSION" --notes-file scripts/release-notes.md
  fi
  echo "Published: https://github.com/jackpawlik26/scout/releases/tag/$TAG"
fi
