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

**Show in Finder:** with Settings ▸ Keyboard & System ▸ “Use Scout for Show in Finder” on, other apps’ Show in Finder / Reveal open in Scout (it sets the `NSFileViewer` default; apps pick it up when they restart). Scout’s own Show in Finder (⌘R) always goes to Finder.

**Open folders in Scout:** the switch below it makes Scout the default app for folders, so folders opened from Spotlight, `open ~/Downloads`, a browser’s downloads or other apps open in Scout, as a new tab. Finder still owns the Desktop and the system Open/Save dialogs.

**Tabs come back:** Scout reopens with the tabs and split view you had when you quit, even with macOS’s “Close windows when quitting an app” on.

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
- `scout://recents`: files you opened or downloaded in the last 30 days
- `scout://tidy?path=~/Downloads`: show Tidy Folder's plan (nothing moves until you confirm)
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
| ⌘O, ⌘↩, ⌃↩, ⌘↓ or double-click | Open |
| Type a name | Select the first match (like Finder) |
| Arrow keys | Move the selection (list and icons) |
| ⌘/ | All keyboard shortcuts |
| Space or ⌘Y | Quick Look |
| Return | Rename |
| ⇧⌘N / ⌃⌘N | New folder / new text file (File ▸ New Markdown File too) |
| Return with several selected | Rename Items: find & replace, prefix/suffix, numbering, letter case, live preview |
| ⌘⌫ | Move to Trash (⌘Z undoes) |
| ⌘C / ⌘V / ⌥⌘V | Copy / paste / move here |
| ⇧⌘M / ⌥⇧⌘M | Move to… / Copy to…: type a few letters of the destination in the palette, ↵ (⌘↵ also goes there, ⇥ switches move/copy) |
| Right-click ▸ Compress / Extract Here | Zip items; unzip .zip, .tar(.gz/.bz2/.xz), .7z |
| ⌥⌘C | Copy path |
| ⌘1 / ⌘2 / ⌘3 | List / icons / columns (→ ← move through columns; in the list, → ← open and close folders in place, ⌥ for everything inside) |
| ⌃⌘0–8 | Group by none / name / kind / size / date added / modified / created / tags |
| ⌘+ / ⌘− | Bigger / smaller icons (slider in the footer); right-click list headers to add Kind or Tags columns |
| ⌥⌘S | Shelf: collect files from anywhere, then Copy Here / Move Here |
| ⌃⌘A / ⇧⌘R / ⌥⌘I | Make Alias / AirDrop / Finder's Get Info (plus Duplicate and Share in the right-click menu) |
| Right-click ▸ Quick Actions | Convert or resize images, combine PDFs (originals kept) |
| Drag onto a folder | Moves into it; hover a second to open it and drop deeper |
| Menu bar 🔭 | Jump, latest downloads, favorites, workspaces, Recents, Clean Up, Shelf (turn off in Settings) |
| Shortcuts app / Siri | Open in Scout, Open Workspace, Jump, Recents, Clean Up, Tidy Downloads |
| Right-click ▸ Customize | Folder color and symbol, nickname, Pin to Top (Scout-only) |
| Settings ▸ Keyboard Shortcuts | Change any of 50 shortcuts; clashes are resolved for you |
| ⌥⌘R | Recents: files opened or downloaded in the last 30 days, grouped by day |
| ⌥⌘T | Tidy Folder: plan, then move loose files into folders by kind (⌘Z undoes) |
| Right-click ▸ Tags | Finder-compatible colored tags; sidebar Tags lists everything with a tag |
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
