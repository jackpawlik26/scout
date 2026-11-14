# Scout for power users

Everything here is optional. Scout works fine without any of it.

## Make Scout your main file browser

Both switches are in **Settings ▸ Keyboard & System**:

- **Use Scout for "Show in Finder"**: when another app reveals a file ("Show in Finder", "Reveal in Finder"), it opens in Scout. Apps notice the change after they restart.
- **Open folders in Scout**: folders opened from Spotlight, a browser's downloads, other apps or Terminal's `open` command open in Scout, each as a new tab.

Finder still runs the Desktop and the Open/Save dialogs inside other apps; no app can replace those. Scout's own **Show in Finder** (⌘R) always goes to Finder.

## Where files came from

When a browser downloads a file or Mail saves an attachment, macOS records where it came from. Scout shows it in the info panel (**Downloaded from canvas.depaul.edu**), with **Open Page**, **Copy Link** and **More from** that site. You can also add a **Source** column to the list: right-click the column headers.

To search by it, type `from:` and part of a site or sender in ⌘K. It works on its own or with other words:

| Search | Finds |
|---|---|
| `from:github` | Everything you downloaded from GitHub |
| `syllabus from:canvas.depaul.edu` | Files named or mentioning "syllabus" that came from Canvas |
| `from:jane@example.com` | Attachments saved from Jane's emails |

Press ⇧↵ to open the results in a tab and save the search to the sidebar.

## Developer tools

Turn on **Settings ▸ Developer tools** (it's off for new installs) for:

- Git branch and status in the header, badges on changed files, and a Git card in the info panel. In a repository whose own settings could run programs, git waits until you click **Trust This Repository**.
- **Packages** (⌥⌘P): everything Homebrew and npm installed, and what's outdated.
- **Changes** (⌥⌘G): every changed file in the repository.
- **Open in Terminal** (⌥⇧⌘T) and **Open in Editor** (⌥⇧⌘E), using the apps you pick in Settings.

## Links

Any app, script or shortcut can control Scout with `scout://` links:

| Link | What it does |
|---|---|
| `scout://open?path=~/Downloads` | Open a folder (a file path reveals the file) |
| `scout://open?path=~/Downloads&newTab=1` | …in a new tab |
| `scout://open?path=~/Downloads&split=1` | …in the other pane |
| `scout://jump?query=taxes` | Open the ⌘K palette, already filled in |
| `scout://workspace?name=Taxes` | Open a workspace |
| `scout://recents` | Files you opened or downloaded in the last 30 days |
| `scout://history` | Everything Scout moved, copied, renamed or trashed |
| `scout://tidy?path=~/Downloads` | Show Tidy Folder's plan (nothing moves until you confirm) |
| `scout://cleanup` | Open Clean Up |
| `scout://packages` | Open Packages (Homebrew, npm; needs Developer tools) |
| `scout://changes?path=~/Code/my-app` | Every changed file in a git repository |
| `scout://settings` | Open Settings |
| `scout://shortcuts` | Show the keyboard shortcuts |

Try one from Terminal: `open "scout://open?path=~/Downloads"`.

## Shortcuts app and Siri

Scout adds actions to the Shortcuts app: Open in Scout, Open Workspace, Jump, Recents, Clean Up and Tidy Downloads.

## The `scout` command

Scout ships a command-line tool inside the app (`Scout.app/Contents/Helpers/scout`). To use it from Terminal, link it onto your PATH once:

```sh
mkdir -p ~/.local/bin
ln -sf /Applications/Scout.app/Contents/Helpers/scout ~/.local/bin/scout
```

Then:

```sh
cd "$(scout jump proj)"      # cd to the best-matching folder, like zoxide
scout rank proj --json       # ranked matches (same ranking as ⌘K)
scout open . --new-tab       # open the current folder in Scout
scout index                  # rebuild the folder index
scout duplicates ~/Desktop   # list duplicate files (no folder = your whole home)
```

## Raycast

The [`raycast/`](../raycast) folder is a Raycast extension with **Jump to Folder** and **Open Finder Selection in Scout**. It needs the `scout` command above. To load it, install [Node.js](https://nodejs.org), then:

```sh
cd raycast && npm install && npm run dev
```

Stop it with Ctrl-C; it stays installed in Raycast.

## Where Scout keeps its data

`~/Library/Application Support/Scout/`:

- `folders.txt`: the folder index behind ⌘K, one path per line
- `history.json`: folder visits (for "Most Used" ranking), ISO 8601 dates
- `file-history.jsonl`: what Scout moved, copied, renamed and trashed (the History page), one JSON entry per line, kept for a year
- `favorites.json`, `workspaces.json`, `saved-searches.json`: what their names say
- `customizations.json`: folder colors, symbols, nicknames and pins

Scout has no accounts, analytics or tracking. The only page that goes online is Packages, which asks Homebrew and npm whether updates exist.
