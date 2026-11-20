**Scout 0.4.1**: file search works again. On recent versions of macOS, results that come from Spotlight came back empty: files in ⌘K, Recents, tags and Clean Up's large files. They're back. Plus everything in 0.4: your own fields, links on folders, saved layouts and more.

### Install
1. Download **Scout.zip** below and open it.
2. Drag **Scout** into **Applications** (replace the old one if you have it).
3. Open it. The first time, macOS says it can't verify the app: click **Done**, go to **System Settings ▸ Privacy & Security**, and click **Open Anyway** next to Scout. You only do this once.
4. When macOS asks whether Scout can see your Downloads, Desktop and Documents folders, click **Allow**.

Needs macOS 26 or later. Works on Apple silicon and Intel Macs. Ask Scout and smart names need Apple Intelligence; everything else works on any Mac.

Prefer to build it yourself? With Xcode 26 and Homebrew, it's `git clone`, `brew install xcodegen` and `./scripts/install.sh`, with no "Open Anyway" step. See [Build Scout from source](https://github.com/jackpawlik26/scout/blob/main/docs/BUILDING.md).

### Fixed
- **Files from Spotlight are back**: ⌘K file results, Recents, everything with a tag, saved searches and Clean Up's **Large files** were empty on recent versions of macOS, which stopped handing Scout the files' paths.
- **⌘K lists each folder once**: a folder could show up twice, once from Scout's folder index and again from Spotlight.

See the [docs](https://scoutformac.com/docs/) and the [changelog](https://scoutformac.com/changelog/). Found a bug? [Open an issue](https://github.com/jackpawlik26/scout/issues/new/choose).
