# Developing Scout

## What you need

- A Mac with macOS 26 or later
- [Xcode](https://apps.apple.com/app/xcode/id497799835) 26 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen), which turns `project.yml` into the Xcode project: `brew install xcodegen`

## Build and run

```sh
xcodegen                    # makes Scout.xcodeproj from project.yml (not committed)
open Scout.xcodeproj        # then press ⌘R in Xcode
```

Or entirely from Terminal:

```sh
xcodegen && xcodebuild -scheme Scout -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/Scout.app
```

Tests for the shared logic (no Xcode window needed): `cd ScoutCore && swift test`

Install your build to /Applications, with the `scout` command on your PATH: `./scripts/install.sh`. If a code-signing certificate named "Scout Local Signing" is in your keychain, the script signs with it so macOS remembers Scout's folder permissions between builds; otherwise every install asks again.

## What's where

| Folder | What's in it |
|---|---|
| [`Scout/`](../Scout) | The macOS app (SwiftUI). `App/` is startup, menus and system hooks; `Models/` holds the state (`AppServices` for the whole app, `BrowserWindowModel` per window, `PaneModel` per pane, `BrowserModel` per tab); `Views/` is the interface; `Support/` is glue (keyboard, theme, shortcuts, Finder). |
| [`ScoutCore/`](../ScoutCore) | Logic with no interface, shared by the app and the `scout` command: listing files, fuzzy matching and ranking, the folder index, git status, Clean Up scanners, duplicates, batch rename, tags. Kept UI-free so a future server or iPhone app can reuse it. Its tests live in `ScoutCore/Tests`. |
| [`ScoutCore/Sources/ScoutCLI`](../ScoutCore/Sources/ScoutCLI) | The `scout` command-line tool, bundled at `Scout.app/Contents/Helpers/scout`. |
| [`raycast/`](../raycast) | The Raycast extension (TypeScript/React). It calls the `scout` command. |
| [`site/`](../site) | The landing page and changelog: plain HTML and CSS, served by a Cloudflare Worker (`wrangler.jsonc`). |
| [`scripts/`](../scripts) | `install.sh` (build and install locally), `release.sh` (make `Scout.zip` and a GitHub Release), `deploy-site.sh` (publish `site/`). |
| [`docs/`](.) | These docs. |

## Making a release

1. Bump `MARKETING_VERSION` (and `CURRENT_PROJECT_VERSION`) in `project.yml`, and add the build to `site/changelog/`.
2. Run `./scripts/release.sh`. It builds a universal (Apple silicon + Intel) Release, signs it ad hoc, zips it to `dist/Scout.zip`, and checks that the zip opens.
3. Run `./scripts/release.sh --publish` to also tag `v<version>` and upload the zip as a GitHub Release, with notes from `scripts/release-notes.md`.

The website and README link to `releases/latest/download/Scout.zip`, so they always point at the newest release.

Scout isn't signed with an Apple Developer ID yet (that costs $99 a year), so on first open macOS says it can't verify the app and people need **Open Anyway** (see the README). Signing and notarizing would remove that step.

## Publishing the website

`./scripts/deploy-site.sh` (first time: `npx wrangler login`).

## Design system

All in `Scout/Support/Theme.swift`, so new views stay consistent:

- **Type:** SF Pro (the system font), regular and medium only, at 12, 13 (base), 14, 16, 18 and 24 points. Use `.font(.ui(13))` or `.font(.ui(16, .medium))`.
- **Text colors:** `Color.textStrong` (#292929, titles and names), `Color.textDefault` (#5D5D5D, body), `Color.textSubtle` (#7F7F7F, hints and captions), each with a dark-mode value.
- **Surfaces:** `Color.bgSelected` (#F5F5F5 on white) for hovered and selected rows, tabs and chips; `Color.hairline` (#F2F2F2) for borders; `chrome`, `canvas` and `raised` for the window frame, cards and panels.
- **Icons:** SF Symbols at `.light` weight (`.regular` below 11 points), for a thin 1-pixel look.
- The accent color is for focus, the list selection and primary buttons only. File lists keep the system's `.primary`/`.secondary` styles so selected rows turn white on the accent.

## Gotchas

- Clicks in the top 32 points of the window drag it (SwiftUI reports `mouseDownCanMoveWindow`). Anything clickable up there goes in an `NSTitlebarAccessoryViewController`; see `SidebarToggleAccessory.swift`.
- Esc never reaches SwiftUI's `onKeyPress` inside text fields, so window-wide keys use `.onWindowKey` (an `NSEvent` monitor, in `Keyboard.swift`).
- `ScrollViewReader.scrollTo` doesn't work on `Table`; `TableAnchor` finds the `NSTableView` and scrolls it directly.
- Custom-view toolbar items don't render on macOS 26, so Scout draws its own header.
- macOS only restores windows after quitting when "Close windows when quitting an app" is off, which isn't the default, so Scout saves its tabs and split itself (`WindowSession`).
- Changing `BrowserModel.items` re-sorts the list. Sorting thousands of names is slow, so big folders arrive pre-sorted from a background task, and folder sizes are applied in batches.
