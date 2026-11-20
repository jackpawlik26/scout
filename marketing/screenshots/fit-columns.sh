#!/bin/zsh
# fit-columns.sh target… — drags the list's column dividers (window points, left to right) to targets.
S=${0:A:h}; TMP=${TMPDIR:-/tmp}/scout-shots; mkdir -p $TMP; T=("$@")
for pass in 1 2 3; do
  for i in {1..${#T}}; do
    $S/cap.sh $TMP/_fit.png
    cur=${${(s: :)$(python3 -I $S/dividers.py $TMP/_fit.png)}[$i]}
    [[ -z $cur ]] && continue
    (( cur > 1418 )) && continue
    delta=$(( T[i] - cur )); (( delta < 0 )) && delta=$(( -delta ))
    if (( delta > 1 )); then
      $S/keys.sh 'delay 0.05' >/dev/null
      $S/bin/mouse drag $(( cur + 15 )) 147 $(( T[i] + 15 )) 147; sleep 0.35
    fi
  done
done
$S/bin/mouse move 1400 950; sleep 0.3
$S/cap.sh $TMP/_fit.png; python3 -I $S/dividers.py $TMP/_fit.png
