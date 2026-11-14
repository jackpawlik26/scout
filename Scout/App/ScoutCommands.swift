import AppKit
import ScoutCore
import SwiftUI

/// The menu bar. Every shortcut lives here so it shows up in the menus.
struct ScoutCommands: Commands {
    @FocusedValue(\.browserWindow) private var window
    @Environment(\.openWindow) private var openWindow
    @AppStorage("appearance") private var appearance = AppAppearance.system.rawValue
    @AppStorage("iconSize") private var iconSize = 64.0
    @AppStorage("columnHeaders") private var columnHeaders = true
    @AppStorage(DeveloperTools.key) private var developerTools = false

    private var browser: BrowserModel? { window?.current }

    var body: some Commands {
        // Settings is a page inside the window, not a separate window.
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { browser?.showSettings() }
                .keyboardShortcut(",")
        }

        CommandGroup(after: .newItem) {
            Button("New Tab") { window?.newTab() }
                .customizableShortcut(.newTab)
            Button("New Folder") { browser?.newFolder() }
                .customizableShortcut(.newFolder)
            Button("New Text File") { browser?.newFile(.text) }
                .customizableShortcut(.newTextFile)
            Button("New Markdown File") { browser?.newFile(.markdown) }
            Button("Tidy Folder…") { browser?.beginTidy() }
                .customizableShortcut(.tidy)
                .disabled(browser?.isFolder != true)
            Divider()
            Button("Open") { browser?.openSelection() }
                .customizableShortcut(.open)
            Button("Quick Look") { browser?.toggleQuickLook() }
                .customizableShortcut(.quickLook)
            Button(window?.isInspectorShown == true ? "Hide Info Panel" : "Show Info Panel") {
                window?.isInspectorShown.toggle()
            }
            .customizableShortcut(.infoPanel)
            Button("Show in Finder") { browser?.showInFinder() }
                .customizableShortcut(.showInFinder)
            Button("Get Info (Finder)") { browser?.showFinderInfo() }
                .customizableShortcut(.getInfo)
            Button("Move To…") { window?.beginMoveTo(copy: false) }
                .customizableShortcut(.moveTo)
                .disabled(browser?.selection.isEmpty ?? true)
            Button("Copy To…") { window?.beginMoveTo(copy: true) }
                .customizableShortcut(.copyTo)
                .disabled(browser?.selection.isEmpty ?? true)
            Button("Duplicate") { browser?.duplicateSelection() }
                .disabled(browser?.selection.isEmpty ?? true)
            Button("Make Alias") { browser?.makeAliases() }
                .customizableShortcut(.makeAlias)
                .disabled(browser?.selection.isEmpty ?? true)
            Button("AirDrop…") { browser?.airDropSelection() }
                .customizableShortcut(.airDrop)
                .disabled(browser?.selection.isEmpty ?? true)
            Divider()
            Button("Rename…") { _ = browser?.beginRename() }
            Button("Compress") { browser?.compressSelection() }
                .disabled(browser?.selection.isEmpty ?? true)
            Button("Extract Here") { browser?.extractSelection() }
                .disabled(!(browser?.canExtractSelection ?? false))
            if developerTools {
                Button("Open in \(DevApp.preferredTerminal?.name ?? "Terminal")") { browser?.openInTerminal() }
                    .customizableShortcut(.terminal)
                Button("Open in \(DevApp.preferredEditor?.name ?? "Editor")") { browser?.openInEditor() }
                    .customizableShortcut(.editor)
            }
            Divider()
            Button("Move to Trash") { trashOrDeleteText() }
                .customizableShortcut(.trash)
            Divider()
            Button("Close Tab") { window?.closeCurrentTab() }
                .customizableShortcut(.closeTab)
        }

        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Copy Path") { browser?.copyPaths() }
                .customizableShortcut(.copyPath)
            Button("Move Copied Items Here") { browser?.paste(move: true) }
                .customizableShortcut(.moveHere)
            Divider()
            Button("Filter This Folder") { window?.filterFocusRequest += 1 }
                .customizableShortcut(.filter)
        }

        CommandGroup(before: .toolbar) {
            Menu("Appearance") {
                ForEach(AppAppearance.allCases) { option in
                    Toggle(option.title, isOn: Binding(
                        get: { appearance == option.rawValue },
                        set: { _ in
                            appearance = option.rawValue
                            option.apply()
                        }
                    ))
                }
            }
            Divider()
            Button(window?.isSplit == true ? "Close Split View" : "Split View") { window?.toggleSplit() }
                .customizableShortcut(.splitView)
            Button("Swap Panes") { window?.swapPanes() }
                .customizableShortcut(.swapPanes)
                .disabled(window?.isSplit != true)
            Button("Switch to Other Pane") { window?.focusOtherPane() }
                .customizableShortcut(.otherPane)
                .disabled(window?.isSplit != true)
            Button("Compare Folders…") { window?.compareFolders() }
                .disabled(window?.isSplit != true)
            Button("Copy to Other Pane") { window?.transferToOtherPane(move: false) }
                .keyboardShortcut(KeyEquivalent(Character(UnicodeScalar(NSF5FunctionKey)!)), modifiers: [])
                .disabled(window?.isSplit != true)
            Button("Move to Other Pane") { window?.transferToOtherPane(move: true) }
                .keyboardShortcut(KeyEquivalent(Character(UnicodeScalar(NSF6FunctionKey)!)), modifiers: [])
                .disabled(window?.isSplit != true)
            Divider()
            Button(window?.isSidebarShown == false ? "Show Sidebar" : "Hide Sidebar") {
                withAnimation(.snappy(duration: 0.25)) { window?.isSidebarShown.toggle() }
            }
            .customizableShortcut(.sidebar)
            Divider()
            Button("as List") { browser?.viewMode = .list }
                .customizableShortcut(.listView)
            Button("as Icons") { browser?.viewMode = .icons }
                .customizableShortcut(.iconView)
            Button("as Columns") { browser?.viewMode = .columns }
                .customizableShortcut(.columnView)
            Button("Bigger Icons") { iconSize = min(160, iconSize + 16) }
                .customizableShortcut(.biggerIcons)
            Button("Smaller Icons") { iconSize = max(32, iconSize - 16) }
                .customizableShortcut(.smallerIcons)
            Toggle("Column Headers", isOn: $columnHeaders)
            Button("Show Shelf") { openWindow(id: "shelf") }
                .customizableShortcut(.shelf)
            Divider()
            Menu("Group By") {
                ForEach(GroupBy.folderChoices) { group in
                    Toggle(group.title, isOn: Binding(
                        get: { browser?.groupBy == group },
                        set: { _ in browser?.groupBy = group }
                    ))
                    .keyboardShortcut(KeyEquivalent(group.shortcutDigit ?? "0"), modifiers: [.command, .control])
                }
            }
            .disabled(browser?.showsLocations ?? true)
            Menu("Sort By") {
                ForEach(SortField.allCases) { field in
                    Toggle(field.title, isOn: Binding(
                        get: { browser?.sortField == field },
                        set: { _ in browser?.sort(by: field, ascending: field.defaultAscending) }
                    ))
                }
            }
            Divider()
            Button(browser?.showHidden == true ? "Hide Hidden Files" : "Show Hidden Files") {
                browser?.showHidden.toggle()
            }
            .customizableShortcut(.hiddenFiles)
            Button(browser?.foldersFirst == true ? "Mix Folders with Files" : "Keep Folders on Top") {
                browser?.foldersFirst.toggle()
            }
            Divider()
            Button("Show Next Tab") { window?.selectTab(offset: 1) }
                .customizableShortcut(.nextTab)
            Button("Show Previous Tab") { window?.selectTab(offset: -1) }
                .customizableShortcut(.previousTab)
            Divider()
        }

        CommandGroup(replacing: .help) {
            Button("Keyboard Shortcuts") {
                window?.isPaletteOpen = false
                window?.isShortcutsOpen.toggle()
            }
            .customizableShortcut(.shortcutsSheet)
        }

        CommandMenu("Go") {
            Button("Back") { browser?.goBack() }
                .customizableShortcut(.back)
            Button("Forward") { browser?.goForward() }
                .customizableShortcut(.forward)
            Button("Enclosing Folder") { browser?.goUp() }
                .customizableShortcut(.enclosingFolder)
            Divider()
            Button("Jump to Folder…") { window?.isPaletteOpen = true }
                .customizableShortcut(.jump)
            Button("Find Files…") {
                window?.paletteInitialScope = .files
                window?.isPaletteOpen = true
            }
            .customizableShortcut(.findFiles)
            Button("Go to Path…") { window?.isGoToPathOpen = true }
                .customizableShortcut(.goToPath)
            Divider()
            if let window {
                let services = window.services
                Button("Recents") { browser?.showRecents() }
                    .customizableShortcut(.recents)
                Button("History") { browser?.showHistory() }
                    .customizableShortcut(.history)
                Button("Triage Downloads") { browser?.showTriage() }
                    .customizableShortcut(.triage)
                Button("Triage This Folder") {
                    if let browser, browser.isFolder { browser.showTriage(browser.location.filePath) }
                }
                .disabled(browser?.isFolder != true)
                Button("Home") { browser?.go(to: services.home) }
                    .customizableShortcut(.home)
                Button("Desktop") { browser?.go(to: services.home.appending(path: "Desktop")) }
                    .customizableShortcut(.desktop)
                Button("Documents") { browser?.go(to: services.home.appending(path: "Documents")) }
                    .customizableShortcut(.documents)
                Button("Downloads") { browser?.go(to: services.home.appending(path: "Downloads")) }
                    .customizableShortcut(.downloads)
                Button("Applications") { browser?.go(to: .folder("/Applications")) }
                    .customizableShortcut(.applications)
                if let iCloud = services.iCloudDrive {
                    Button("iCloud Drive") { browser?.go(to: iCloud) }
                        .customizableShortcut(.iCloud)
                }
                Button("Add to Favorites") {
                    guard let browser else { return }
                    let folders = browser.selectedItems.filter(\.isNavigable).map(\.path)
                    services.addFavorites(folders.isEmpty && browser.isFolder ? [browser.location.filePath] : folders)
                }
                .customizableShortcut(.addFavorites)
                Divider()
                Button("Clean Up") { browser?.showCleanup() }
                    .customizableShortcut(.cleanUp)
                Button("Disk Map") { browser?.showDiskMap() }
                if developerTools {
                    Button("Packages") { browser?.showPackages() }
                        .customizableShortcut(.packages)
                    Button("Git Changes") { browser?.showChanges() }
                        .customizableShortcut(.gitChanges)
                        .disabled(browser?.git == nil)
                }
                Divider()
                Button("New Workspace…") { window.newWorkspacePaths = browser?.selectedItems.map(\.path) ?? [] }
                    .customizableShortcut(.newWorkspace)
                ForEach(Array(services.workspaces.prefix(9).enumerated()), id: \.element.id) { index, workspace in
                    Button(workspace.name) { browser?.showWorkspace(workspace.id) }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .control)
                }
                Divider()
                Button("Rebuild Jump Index") { Task { await services.rebuildIndex() } }
                    .disabled(services.isIndexing)
            }
        }
    }

    /// ⌘⌫ trashes files, unless you're typing, where it should delete text instead.
    private func trashOrDeleteText() {
        if NSApp.keyWindow?.firstResponder is NSText {
            NSApp.sendAction(#selector(NSResponder.deleteToBeginningOfLine(_:)), to: nil, from: nil)
        } else {
            browser?.trashSelection()
        }
    }
}
