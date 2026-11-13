# Scout

A native macOS file manager, built for finding things fast.

## Build

```sh
xcodegen            # makes Scout.xcodeproj from project.yml
open Scout.xcodeproj
```

Or from the terminal:

```sh
xcodegen && xcodebuild -scheme Scout -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/Scout.app
```

Core logic tests (no Xcode UI needed): `cd ScoutCore && swift test`

Install to /Applications (also puts the `scout` CLI in ~/.local/bin): `./scripts/install.sh`

## Talking to Scout from elsewhere

**Show in Finder:** with Settings ▸ Keyboard & System ▸ “Use Scout for Show in Finder” on, other apps’ Show in Finder / Reveal open in Scout (it sets the `NSFileViewer` default; apps pick it up when they restart).

**Links:** any app can open `scout://` links:

- `scout://open?path=~/Downloads`: open a folder (a file path reveals it)
- `scout://open?path=/some/folder&newTab=1`: in a new tab
- `scout://jump?query=taxes`: open the ⌘K palette, pre-filled
- `scout://open?path=~/Downloads&split=1`: open in the other pane
- `scout://workspace?name=Taxes`: open a workspace
- `scout://cleanup`: open Clean Up
- `scout://packages`: open Packages (Homebrew, npm)
- `scout://settings`: open Settings
- `scout://shortcuts`: show the keyboard shortcuts
- `scout://changes?path=~/Scout`: every changed file in a git repository

**CLI:** `scout` ships inside Scout.app (`Contents/Helpers/scout`):

```sh
cd "$(scout jump ib)"        # cd to the best match, like zoxide
scout rank proj --json       # ranked matches (same ranking as ⌘K)
scout open . --new-tab       # open the current folder in Scout
scout index                  # rebuild the folder index
scout duplicates ~/Desktop   # list duplicate files (no folder = whole home)
```

**Shared files** in `~/Library/Application Support/Scout/`: `folders.txt` (the index, one path per line) and `history.json` (visits, ISO 8601 dates).

**Raycast** (`raycast/`): "Jump to Folder" and "Open Finder Selection in Scout". Load or update it with `cd raycast && npm install && npm run dev` (stop with Ctrl-C; it stays installed).

## Layout

- `ScoutCore/`: UI-free logic shared by any future Scout app or server: file listing (`FileSource`), fuzzy matching, visit history (frecency), the folder index for ⌘K, path helpers.
- `ScoutCore/Sources/ScoutCLI`: the `scout` command-line tool.
- `raycast/`: the Raycast extension (TypeScript/React). It calls the `scout` CLI for ranking.
- `Scout/`: the macOS app (SwiftUI).
  - `Models/`: `AppServices` (app-wide), `BrowserWindowModel` (a window and its tabs), `BrowserModel` (one tab).
  - `Views/`: sidebar, list and icon views, ⌘K palette, Go to Path.

## Shortcuts

| Keys | Action |
|---|---|
| ⌥Space (anywhere) | Open the ⌘K palette from any app; again or Esc goes back (change it in Settings) |
| ⌘K | Find any folder or file (folders ranked by use; files via Spotlight, names and contents) |
| ⇧⌘F | Find files (⌘K starting on Files) |
| In ⌘K: ⇥ / ⌘↵ / ⇧↵ | Cycle All/Folders/Files / new tab or show in Scout / all results in a tab |
| ⌘L | Go to path (Tab completes) |
| ⌘F | Filter this folder |
| ⌘T / ⌘W | New tab / close tab |
| ⇧⌘] / ⇧⌘[ | Next / previous tab |
| ⌘[ / ⌘] / ⌘↑ | Back / forward / enclosing folder |
| ⌘O, ⌘↓ or double-click | Open |
| Type a name | Select the first match (like Finder) |
| Arrow keys | Move the selection (list and icons) |
| ⌘/ | All keyboard shortcuts |
| Space or ⌘Y | Quick Look |
| Return | Rename |
| ⇧⌘N | New folder |
| ⌘⌫ | Move to Trash (⌘Z undoes) |
| ⌘C / ⌘V / ⌥⌘V | Copy / paste / move here |
| ⌥⌘C | Copy path |
| ⌘1 / ⌘2 | List / icons |
| ⌘D / ⌘U / ⌥⇥ | Split view / swap panes / switch pane |
| F5 / F6 | Copy / move selection to the other pane |
| ⌥⌘N / ⌃1–9 | New workspace / open workspace 1–9 |
| ⇧⌘K / ⌥⌘P / ⌥⌘G | Clean Up / Packages / Git changes |
| ⌘I / ⌃⌘S / ⌘, | Info panel / sidebar / Settings (appearance, accent color, transparency, folder sizes, terminal and editor) |
| ⇧⌘. | Show hidden files |
| ⌘R | Show in Finder |
| ⌥⇧⌘T / ⌥⇧⌘E | Open in your terminal (Tern, Ghostty, iTerm, Terminal…) / code editor; pick them in Settings (⌘,) |
| ⌃⌘T | Add the folder (or selected folders) to Favorites; drag folders onto Favorites to pin, drag to reorder |
| ⇧⌘H ⇧⌘D ⇧⌘O ⌥⌘L ⇧⌘A ⇧⌘I | Home, Desktop, Documents, Downloads, Applications, iCloud Drive |

## Roadmap

1. ✅ Browser basics: sidebar, tabs, list/icon views, Quick Look, file operations with undo, live updates
2. ✅ Finding: ⌘K for files too (Spotlight), kind/date/folder filters, live results tabs, saved searches
3. ✅ Split panes (⌘D, F5/F6, drag between panes) and workspaces (folders from anywhere on one page)
4. ✅ Clean Up: dev caches, installers, old downloads, large files, duplicates, Trash (all to Trash with Undo)
5. ✅ Dev tools: Git branch chip and per-file badges, Git card in the info panel, Open on GitHub, Open In terminals/editors, repo-wide Changes view, Packages page (Homebrew, casks, npm: sizes, updates, upgrade commands)
6. Later: Scout server on a home machine over Tailscale, iPhone app
