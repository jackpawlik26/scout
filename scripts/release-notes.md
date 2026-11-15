**Scout 0.3**: the biggest update yet. Scout now helps keep your files organized, remembers everything it did, and understands what's in your files, all on your Mac.

### Install
1. Download **Scout.zip** below and open it.
2. Drag **Scout** into **Applications** (replace the old one if you have it).
3. Open it. The first time, macOS says it can't verify the app: click **Done**, go to **System Settings ▸ Privacy & Security**, and click **Open Anyway** next to Scout. You only do this once.
4. When macOS asks whether Scout can see your Downloads, Desktop and Documents folders, click **Allow**.

Needs macOS 26 or later. Works on Apple silicon and Intel Macs. Ask Scout and smart names need Apple Intelligence; everything else works on any Mac.

Prefer to build it yourself? With Xcode 26 and Homebrew, it's `git clone`, `brew install xcodegen` and `./scripts/install.sh`, with no "Open Anyway" step. See [Build Scout from source](https://github.com/jackpawlik26/scout/blob/main/docs/BUILDING.md).

### New
- **Triage Downloads** (⌥⌘J): new downloads one at a time with a big preview. One key files, trashes, renames or skips each. Suggestions learn from where similar files went before, and **Always do this** turns one into a rule that files new downloads on its own.
- **History** (⌥⌘Y): everything Scout moved, copied, renamed or trashed, kept after you quit. Search it to find where a file went, and undo things from days ago.
- **Ask Scout**: describe a file in ⌘K ("the lease I signed last spring") and press ⌥↵. Apple's on-device model turns it into a search. Nothing leaves your Mac.
- **Text in images**: ⌘K finds screenshots and images by the text in them.
- **Smart names**: Rename Items can name files by what's in them (`{about}` and the Smart names preset).
- **Commands in ⌘K**: type `>` to run any menu command. Your own scripts in the Actions folder run on the selection from ⌘K and the right-click menu.
- **Where a file came from**: the info panel shows the site or Mail message a download came from; `from:site` in ⌘K finds everything from one place.
- **Compare Folders**: in split view, see what's different between two folders and copy changes one way.
- **Cloud buckets**: connect Cloudflare R2 or Amazon S3 in the sidebar to browse, upload and download.
- **Disk Map**: what fills a folder, as blocks you can click into.
- **Notes** on files and folders, **earlier versions** of documents with Restore, and **Used around the same time** in the info panel.
- A dot marks files that arrived since your last visit, and **Settings ▸ Browsing ▸ Group folders by** groups every folder the same way.

### Better
- Notes, nicknames, colors and pins now follow files when Scout moves or renames them.
- File searches finish about 3× sooner.

### Fixed
- Searching in ⌘K could freeze Scout for several seconds (the spinning beach ball), especially for common words.

Everything new is in the [docs](https://scoutformac.com/docs/#new). Found a bug? [Open an issue](https://github.com/jackpawlik26/scout/issues/new/choose).
