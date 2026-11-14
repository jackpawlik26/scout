**Scout 0.2.2**: select and drag several files like Finder. Dragging a selection onto a folder moves all of it (in list, icon and column views), Shift with the arrow keys or Shift-click selects a range, and the toolbar no longer jumbles after closing a split view. Plus everything in 0.2: rename presets, a new look, and a safety pass.

### Install
1. Download **Scout.zip** below and open it.
2. Drag **Scout** into **Applications** (replace the old one if you have it).
3. Open it. The first time, macOS says it can't verify the app: click **Done**, go to **System Settings ▸ Privacy & Security**, and click **Open Anyway** next to Scout. You only do this once.
4. When macOS asks whether Scout can see your Downloads, Desktop and Documents folders, click **Allow**.

Needs macOS 26 or later. Works on Apple silicon and Intel Macs.

### New
- **Rename Items 2.** Select files and press Return. Stack steps (replace with regular expressions and `$1` groups, add text, new name, remove characters, change case, trim spaces), use variables like `{n}`, `{created:yyyy-MM-dd}`, `{parent}` and `{width}`, and save presets. Four come built in.
- **A calmer design.** One type scale, neutral grays, thin icons.
- **Welcome card** on first launch, and a **Developer tools** switch in Settings (git, Packages, Open in Terminal), off for new installs.

### Safer
- A downloaded git repository can no longer run programs when you browse into it: git pauses there until you click **Trust This Repository**.
- Moving files to another disk verifies the copy before removing originals, and same-named files moved together no longer collide.
- Plus fixes for copying a folder into itself, Replace, undo of swapped renames, and Clean Up duplicates.

### Faster
- Empty Trash, Recents and folder sizes work in the background; big folders stay smooth.

Found a bug? [Open an issue](https://github.com/jackpawlik26/scout/issues/new/choose).
