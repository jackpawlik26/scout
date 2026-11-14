# Build Scout from source

Most people should [download Scout.zip](https://github.com/jackpawlik26/scout/releases/latest/download/Scout.zip). Building it yourself takes about 10 minutes plus Xcode's download, and has two upsides:

- **No "Open Anyway" step.** macOS trusts apps built on the same Mac, so Scout opens without the "can't verify" message.
- **You can read and change the code** before you run it.

## What you need

| | |
|---|---|
| **Mac** | macOS 26 (Tahoe) or later, Apple silicon or Intel |
| **Xcode** | 26 or later, free from the [Mac App Store](https://apps.apple.com/app/xcode/id497799835). It's a large download (several GB). |
| **Homebrew** | The Mac package manager, from [brew.sh](https://brew.sh) |
| **XcodeGen** | Turns `project.yml` into the Xcode project. Installed with Homebrew below. |
| **Disk space** | About 1 GB for the build, on top of Xcode |

You don't need an Apple developer account. Scout builds with an "ad-hoc" signature that only your Mac uses.

## Steps

**1. Set up Xcode (once).** After installing Xcode, open it once so it can finish installing its components, then quit it. Then, in Terminal:

```sh
sudo xcode-select -s /Applications/Xcode.app
sudo xcodebuild -license accept
```

**2. Install XcodeGen.**

```sh
brew install xcodegen
```

**3. Get the code.** This makes a `scout` folder wherever you are (your home folder, if you just opened Terminal):

```sh
git clone https://github.com/jackpawlik26/scout.git
cd scout
```

`main` has the newest changes, which may be ahead of the latest release. To build exactly the latest release instead:

```sh
git checkout "$(git describe --tags --abbrev=0)"
```

**4. Build and install.**

```sh
./scripts/install.sh
```

This takes a few minutes the first time. When it's done, Scout opens. The script:

- builds Scout in the `build` folder,
- quits Scout if it's running and replaces `/Applications/Scout.app` (including a copy you downloaded),
- opens the new copy,
- links the `scout` command into `~/.local/bin`. If `scout` isn't found in Terminal afterwards, add `export PATH="$HOME/.local/bin:$PATH"` to your `~/.zshrc`.

The first time Scout opens, macOS asks whether it can see your Downloads, Desktop and Documents folders. Click **Allow**.

## Updating

From the `scout` folder:

```sh
git pull
./scripts/install.sh
```

If you checked out a release tag, run `git checkout main` before `git pull`, then check out the new tag.

## Building without installing

To try a build without touching `/Applications`:

```sh
xcodegen
xcodebuild -scheme Scout -configuration Release -derivedDataPath build build
open build/Build/Products/Release/Scout.app
```

Or run `xcodegen`, open `Scout.xcodeproj` in Xcode and press ⌘R.

## Troubleshooting

**"xcodebuild requires Xcode, but active developer directory … is a command line tools instance"**
Run `sudo xcode-select -s /Applications/Xcode.app` (step 1).

**"You have not agreed to the Xcode license agreements"**
Run `sudo xcodebuild -license accept`.

**`xcodegen: command not found` or `brew: command not found`**
Install [Homebrew](https://brew.sh), then `brew install xcodegen`. Homebrew prints two lines at the end of its install that add it to your PATH; run them, or open a new Terminal window.

**Errors about the SDK, `macOS 26` or unknown APIs**
Your Xcode is too old. Scout needs Xcode 26 or later. Check with `xcodebuild -version`.

**macOS asks for folder access again after every rebuild**
Each ad-hoc build has a new signature, so macOS treats it as a new app. A one-time fix is to sign builds with your own local certificate, which `install.sh` uses automatically if it finds it:

1. Open **Keychain Access**, then choose **Keychain Access ▸ Certificate Assistant ▸ Create a Certificate…**
2. Name it exactly `Scout Local Signing`, set **Certificate Type** to **Code Signing**, and click **Create**.
3. Run `./scripts/install.sh` again. From then on, permissions stick between builds.

**Something else**
[Open an issue](https://github.com/jackpawlik26/scout/issues/new/choose) and paste what Terminal printed.

## Running the tests

The logic shared by the app and the `scout` command has its own tests, no Xcode window needed:

```sh
cd ScoutCore && swift test
```

## Uninstalling

```sh
rm -rf /Applications/Scout.app ~/.local/bin/scout
rm -rf ~/Library/Application\ Support/Scout   # history, favorites, workspaces, the folder index
defaults delete com.jackpawlik.scout          # settings
```

If you turned on **Open folders in Scout** or **Use Scout for "Show in Finder"**, turn them off in Scout's Settings first, so folders open in Finder again. Then delete the `scout` folder you cloned.

## Working on Scout

How the code is laid out, how releases are made and the design system are in [Developing Scout](DEVELOPING.md).
