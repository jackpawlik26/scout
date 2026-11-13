#!/bin/zsh
# Builds Scout (Release) and installs it to /Applications, then opens it.
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen --quiet
xcodebuild -scheme Scout -configuration Release -derivedDataPath build build -quiet

# Sign with the stable local certificate so macOS remembers Scout's folder
# permissions (and Full Disk Access) across rebuilds. Ad-hoc signatures change
# every build, which makes macOS ask again each time.
APP=build/Build/Products/Release/Scout.app
IDENTITY="Scout Local Signing"
if security find-identity -p codesigning | grep -q "$IDENTITY"; then
  codesign --force --options runtime --timestamp=none -s "$IDENTITY" "$APP/Contents/Helpers/scout"
  codesign --force --options runtime --timestamp=none -s "$IDENTITY" "$APP"
else
  echo "warning: '$IDENTITY' certificate not found; permissions will reset on every install" >&2
fi

osascript -e 'tell application "Scout" to quit' 2>/dev/null || true
# Wait (up to 5s) for it to finish quitting, or reopening it fails.
for _ in {1..50}; do pgrep -xq Scout || break; sleep 0.1; done
# A sheet or dialog can block quitting; Scout keeps nothing unsaved, so stop it.
pgrep -xq Scout && pkill -x Scout && sleep 0.5
rm -rf /Applications/Scout.app
cp -R "$APP" /Applications/Scout.app
open /Applications/Scout.app || { sleep 1; open /Applications/Scout.app; } || true

# Put the `scout` command on your PATH.
mkdir -p ~/.local/bin
ln -sf /Applications/Scout.app/Contents/Helpers/scout ~/.local/bin/scout

echo "Installed /Applications/Scout.app and ~/.local/bin/scout"
