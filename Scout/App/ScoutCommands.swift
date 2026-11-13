import AppKit
import ScoutCore
import SwiftUI

/// The menu bar. Every shortcut lives here so it shows up in the menus.
struct ScoutCommands: Commands {
    @FocusedValue(\.browserWindow) private var window
    @AppStorage("appearance") private var appearance = AppAppearance.system.rawValue

    private var browser: BrowserModel? { window?.current }

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Tab") { window?.newTab() }
                .keyboardShortcut("t")
            Button("New Folder") { browser?.newFolder() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Divider()
            Button("Open") { browser?.openSelection() }
                .keyboardShortcut(.downArrow, modifiers: .command)
            Button("Quick Look") { browser?.toggleQuickLook() }
                .keyboardShortcut("y")
            Button(window?.isInspectorShown == true ? "Hide Info Panel" : "Show Info Panel") {
                window?.isInspectorShown.toggle()
            }
            .keyboardShortcut("i")
            Button("Show in Finder") { browser?.showInFinder() }
                .keyboardShortcut("r")
            Button("Open in Terminal") { browser?.openInTerminal() }
                .keyboardShortcut("t", modifiers: [.command, .option, .shift])
            Divider()
            Button("Move to Trash") { trashOrDeleteText() }
                .keyboardShortcut(.delete, modifiers: .command)
            Divider()
            Button("Close Tab") { window?.closeCurrentTab() }
                .keyboardShortcut("w")
        }

        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Copy Path") { browser?.copyPaths() }
                .keyboardShortcut("c", modifiers: [.command, .option])
            Button("Move Copied Items Here") { browser?.paste(move: true) }
                .keyboardShortcut("v", modifiers: [.command, .option])
            Divider()
            Button("Filter This Folder") { window?.filterFocusRequest += 1 }
                .keyboardShortcut("f")
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
                .keyboardShortcut("d")
            Button("Swap Panes") { window?.swapPanes() }
                .keyboardShortcut("u")
                .disabled(window?.isSplit != true)
            Button("Switch to Other Pane") { window?.focusOtherPane() }
                .keyboardShortcut(.tab, modifiers: .option)
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
            .keyboardShortcut("s", modifiers: [.command, .control])
            Divider()
            Button("as List") { browser?.viewMode = .list }
                .keyboardShortcut("1")
            Button("as Icons") { browser?.viewMode = .icons }
                .keyboardShortcut("2")
            Divider()
            Button(browser?.showHidden == true ? "Hide Hidden Files" : "Show Hidden Files") {
                browser?.showHidden.toggle()
            }
            .keyboardShortcut(".", modifiers: [.command, .shift])
            Button(browser?.foldersFirst == true ? "Mix Folders with Files" : "Keep Folders on Top") {
                browser?.foldersFirst.toggle()
            }
            Divider()
            Button("Show Next Tab") { window?.selectTab(offset: 1) }
                .keyboardShortcut("]", modifiers: [.command, .shift])
            Button("Show Previous Tab") { window?.selectTab(offset: -1) }
                .keyboardShortcut("[", modifiers: [.command, .shift])
            Divider()
        }

        CommandMenu("Go") {
            Button("Back") { browser?.goBack() }
                .keyboardShortcut("[")
            Button("Forward") { browser?.goForward() }
                .keyboardShortcut("]")
            Button("Enclosing Folder") { browser?.goUp() }
                .keyboardShortcut(.upArrow, modifiers: .command)
            Divider()
            Button("Jump to Folder…") { window?.isPaletteOpen = true }
                .keyboardShortcut("k")
            Button("Find Files…") {
                window?.paletteInitialScope = .files
                window?.isPaletteOpen = true
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            Button("Go to Path…") { window?.isGoToPathOpen = true }
                .keyboardShortcut("l")
            Divider()
            if let window {
                let services = window.services
                Button("Home") { browser?.go(to: services.home) }
                    .keyboardShortcut("h", modifiers: [.command, .shift])
                Button("Desktop") { browser?.go(to: services.home.appending(path: "Desktop")) }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                Button("Documents") { browser?.go(to: services.home.appending(path: "Documents")) }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                Button("Downloads") { browser?.go(to: services.home.appending(path: "Downloads")) }
                    .keyboardShortcut("l", modifiers: [.command, .option])
                Button("Applications") { browser?.go(to: .folder("/Applications")) }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                if let iCloud = services.iCloudDrive {
                    Button("iCloud Drive") { browser?.go(to: iCloud) }
                        .keyboardShortcut("i", modifiers: [.command, .shift])
                }
                Divider()
                Button("Clean Up") { browser?.showCleanup() }
                    .keyboardShortcut("k", modifiers: [.command, .shift])
                Divider()
                Button("New Workspace…") { window.newWorkspacePaths = browser?.selectedItems.map(\.path) ?? [] }
                    .keyboardShortcut("n", modifiers: [.command, .option])
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
