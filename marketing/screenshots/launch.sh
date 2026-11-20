#!/bin/zsh
# launch.sh — (re)starts the demo Scout (build/demo) with the demo home, a 1440×900 window at (15, 40),
# and the Multicolor accent (Scout's own indigo, whatever your Mac's accent is). Prints the pid.
S=${0:A:h}; T=${TMPDIR:-/tmp}/scout-shots; mkdir -p $T
APP=${S:h:h}/build/demo/Build/Products/Release/Scout.app
pkill -f "build/demo/Build/Products/Release/Scout.app/Contents/MacOS/Scout"; sleep 1; rm -rf ~/Library/"Saved Application State"/com.jackpawlik.scout.demo.savedState
SCOUT_DEMO_HOME=/Users/Shared/marta nohup "$APP/Contents/MacOS/Scout" -AppleAccentColor 99 "$@" > $T/demo-app.log 2>&1 &
for i in {1..40}; do PID=$(pgrep -f "build/demo/Build/Products/Release/Scout.app/Contents/MacOS/Scout"); [[ -n $PID ]] && $S/bin/windows $PID | grep -q . && break; sleep 0.25; done
sleep 1
osascript -e "tell application \"System Events\" to tell (first process whose unix id is $PID)
set frontmost to true
set position of window 1 to {15, 40}
set size of window 1 to {1440, 900}
end tell" >/dev/null
echo $PID > $T/demo.pid; echo $PID
