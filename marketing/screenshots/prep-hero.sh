#!/bin/zsh
# Puts the demo window in the hero state: Northwind Studio, Clients + Harbor & Pine expanded,
# info panel open, columns sized so nothing truncates.
S=${0:A:h}; T=${TMPDIR:-/tmp}/scout-shots; mkdir -p $T
PID=$(cat $T/demo.pid)
osascript -e "tell application \"System Events\" to tell (first process whose unix id is $PID) to click menu item \"Rebuild Jump Index\" of menu \"Go\" of menu bar 1" >/dev/null
$S/link.sh open "/Users/Shared/marta/Northwind Studio"; sleep 1.5
$S/keys.sh 'keystroke "clients"
delay 0.5
key code 124
delay 0.4
key code 125
key code 125
delay 0.3
key code 124
delay 1'
sleep 1
# Column widths: SwiftUI restores them unpredictably, so size them with the info panel closed,
# reopen it, then fit the final positions. The column order can also come back different; check the
# capture and adjust the targets (they are the divider positions, left to right, in window points).
$S/keys.sh 'keystroke "i" using command down
delay 1' >/dev/null
$S/fit-columns.sh 610 846 1014 1174 1308 >/dev/null
$S/keys.sh 'keystroke "i" using command down
delay 1.2' >/dev/null
$S/fit-columns.sh 517 693 818 937 1037 >/dev/null
$S/bin/mouse click 615 283; sleep 0.4
$S/bin/mouse move 1400 950; sleep 0.5
