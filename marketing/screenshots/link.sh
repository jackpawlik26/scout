#!/bin/zsh
# link.sh action [path] [extra query]  — sends scout://action?path=… to the demo app
APP=${0:A:h:h:h}/build/demo/Build/Products/Release/Scout.app
q=""
[[ -n $2 ]] && q="?path=$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1]))' "$2")"
[[ -n $3 ]] && q="${q:-?}&$3"
open -a "$APP" "scout://$1$q"
