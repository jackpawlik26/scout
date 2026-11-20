# Screenshots

The app screenshots on the site, in the docs and in the README (`site/assets/shots/*.webp`) all come
from one made-up Mac user, so they show the same folders, fields, links and downloads everywhere and
nothing of yours.

- **The demo home**: `setup-home.py` builds `/Users/Shared/marta`. It has the Northwind Studio demo
  folder ([`../demo-folder`](../demo-folder)) with fields, folder links and a workspace, downloads to
  triage with a File History that taught Scout where they go, Clean Up and Disk Map material, and
  coding-agent projects with Claude Code and Codex logs. Big files are APFS clones of one file, so
  the home takes under 1 GB of real disk.
- **The demo app**: a Release build with its own bundle id (`com.jackpawlik.scout.demo`), so its
  settings don't touch yours. Running it with `SCOUT_DEMO_HOME=/Users/Shared/marta` makes Scout treat
  that folder as your home: it keeps its files there and Spotlight searches stay inside it.
- **Capturing**: `screencapture -o -l <window>` grabs just the window, with its own rounded corners
  and no shadow. The page adds a shadow that follows the corners.

## Retake them

```sh
# once: the demo app, the helpers and the home
xcodebuild -scheme Scout -configuration Release -derivedDataPath build/demo \
  PRODUCT_BUNDLE_IDENTIFIER=com.jackpawlik.scout.demo build
marketing/screenshots/build-tools.sh
python3 -I marketing/screenshots/setup-home.py      # an existing demo home goes to the Trash

# a dev server for the AI Agents page
(cd "/Users/Shared/marta/Northwind Studio/Projects/northwind-site" && \
  node -e "require('http').createServer((q,r)=>r.end('ok')).listen(5173)" &)

cd marketing/screenshots
./launch.sh          # starts the demo Scout: 1440×900, dark, Scout's own indigo accent
./prep-hero.sh       # the hero state; then ./cap.sh <out>/list.png
```

Terminal (or whichever app runs these) needs **Accessibility** and **Screen Recording** permission:
the scripts press keys, click and drag in the demo window.

| Shot | How |
|---|---|
| `list` | `./prep-hero.sh` |
| `palette` | after the hero: `./link.sh jump "" "query=acme"` |
| `split` | `⌥⌘1` (the Client work layout), info panel off, expand Acme Coffee and Harbor & Pine, select the proposal |
| `cleanup` | `./link.sh cleanup`, wait about 15 s |
| `triage` | `./link.sh triage` |
| `agents` | Go ▸ AI Agents |
| `diskmap` | `./link.sh diskmap "/Users/Shared/marta/Northwind Studio"` |
| `packages` | `./link.sh packages` (lists the Homebrew and npm packages on the Mac you run it on) |
| `shortcuts` | open Northwind Studio, then `./link.sh shortcuts` |
| `icons` | `⌘2` in Northwind Studio (used by the launch video) |

Save each with `./cap.sh <folder>/<name>.png`, then `python3 -I export.py <folder>` writes the WebPs
into `site/assets/shots`.

SwiftUI brings list columns back at different widths (and sometimes in a different order) after a
relaunch. `fit-columns.sh` finds the column dividers in a capture and drags each one to a target
position, so check the capture and adjust the targets if the order changed.
