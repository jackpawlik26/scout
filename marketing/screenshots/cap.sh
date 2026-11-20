#!/bin/zsh
# cap.sh out.png — captures the demo Scout's main window (no shadow)
S=${0:A:h}; T=${TMPDIR:-/tmp}/scout-shots; mkdir -p $T; PID=$(cat $T/demo.pid)
WID=$($S/bin/windows $PID | awk '$6==0 && $4>1300 {print $1; exit}')
screencapture -x -o -l$WID "$1"
