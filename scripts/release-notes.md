**Scout 0.3.1**: drop files on the sidebar. Drag files onto a folder in the sidebar to file them away without leaving the folder you're in. Plus everything in 0.3: Triage Downloads, History, Ask Scout and more.

### Install
1. Download **Scout.zip** below and open it.
2. Drag **Scout** into **Applications** (replace the old one if you have it).
3. Open it. The first time, macOS says it can't verify the app: click **Done**, go to **System Settings ▸ Privacy & Security**, and click **Open Anyway** next to Scout. You only do this once.
4. When macOS asks whether Scout can see your Downloads, Desktop and Documents folders, click **Allow**.

Needs macOS 26 or later. Works on Apple silicon and Intel Macs. Ask Scout and smart names need Apple Intelligence; everything else works on any Mac.

Prefer to build it yourself? With Xcode 26 and Homebrew, it's `git clone`, `brew install xcodegen` and `./scripts/install.sh`, with no "Open Anyway" step. See [Build Scout from source](https://github.com/jackpawlik26/scout/blob/main/docs/BUILDING.md).

### New
- **Drop files on the sidebar**: drag files onto a favorite, a frequent folder, iCloud Drive, Dropbox and other cloud drives, or a disk to move them into it. Another disk copies, and ⌥ always copies. Hover for a second to open the folder and drop deeper.
- **Drop on Trash** in the sidebar to move files to the Trash.

### Changed
- On **Favorites**, drop in the middle of a folder to move files into it, or between two favorites to pin them there. Dragging a favorite onto another still reorders.

See the [docs](https://scoutformac.com/docs/#move) and the [changelog](https://scoutformac.com/changelog/). Found a bug? [Open an issue](https://github.com/jackpawlik26/scout/issues/new/choose).
