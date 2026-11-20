**Scout 0.4**: your own fields, links on folders and saved layouts. Organize files like a database, keep a project's links with its folder, and bring back a whole window with one key.

### Install
1. Download **Scout.zip** below and open it.
2. Drag **Scout** into **Applications** (replace the old one if you have it).
3. Open it. The first time, macOS says it can't verify the app: click **Done**, go to **System Settings ▸ Privacy & Security**, and click **Open Anyway** next to Scout. You only do this once.
4. When macOS asks whether Scout can see your Downloads, Desktop and Documents folders, click **Allow**.

Needs macOS 26 or later. Works on Apple silicon and Intel Macs. Ask Scout and smart names need Apple Intelligence; everything else works on any Mac.

Prefer to build it yourself? With Xcode 26 and Homebrew, it's `git clone`, `brew install xcodegen` and `./scripts/install.sh`, with no "Open Anyway" step. See [Build Scout from source](https://github.com/jackpawlik26/scout/blob/main/docs/BUILDING.md).

### New
- **Your own fields**: give files and folders a Status, Client, Due date or Amount from the info panel. Each field gets a list column and is searchable in ⌘K, and each choice field adds a sidebar section that always lists what's set to each choice. Drop files on a choice to set it.
- **Links on folders**: attach the Notion brief, the Figma file or the repo to a folder. Links follow the folder when it moves, and ⌘K opens them.
- **Saved layouts**: Go ▸ Save Layout… remembers a window's tabs and split view. Reopen it with ⌥⌘1–9 or from the sidebar.
- **Downloads window**: a small window that stays on top with your 30 newest downloads, to drag into any app. Drop files on it to move them into Downloads.
- **Drop shelf** (Settings ▸ Keyboard & System, off by default): drag files to the top edge of the screen from any app to drop them on a favorite folder or the Shelf.
- **Open folders in your apps from ⌘L**: type `code .`, `cursor`, `zed`, `terminal` or `finder` in Go to Path.
- **Function keys**: F2 rename, F3 Quick Look, F4 open in your editor, F7 new folder, F8 move to Trash, alongside F5 and F6.
- **AI Agents** (Developer tools): your Claude Code, Codex, Cursor and Gemini projects with token use and MCP servers, plus the dev servers running from your folders. All read on your Mac.
- **Image tools**: flip images, and convert to AVIF, or to WebP when `cwebp` is installed (`brew install webp`).

See the [docs](https://scoutformac.com/docs/#new) and the [changelog](https://scoutformac.com/changelog/). Found a bug? [Open an issue](https://github.com/jackpawlik26/scout/issues/new/choose).
