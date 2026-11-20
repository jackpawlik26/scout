#!/bin/zsh
# keys.sh 'applescript lines'  — runs System Events commands with the demo Scout frontmost
S=${0:A:h}; T=${TMPDIR:-/tmp}/scout-shots; mkdir -p $T; PID=$(cat $T/demo.pid)
osascript -e "tell application \"System Events\"
set frontmost of (first process whose unix id is $PID) to true
delay 0.3
$1
end tell"
