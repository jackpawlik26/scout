import AppKit
import Observation
import SwiftUI

/// Commands whose keyboard shortcut you can change in Settings ▸ Keyboard Shortcuts.
enum ScoutShortcut: String, CaseIterable, Identifiable {
    case newTab, moveTo, copyTo, newFolder, newTextFile, tidy, open, quickLook, infoPanel, showInFinder, getInfo, makeAlias, airDrop, terminal, editor, trash, closeTab, copyPath, moveHere, filter, splitView, swapPanes, otherPane, sidebar, listView, iconView, columnView, biggerIcons, smallerIcons, shelf, hiddenFiles, nextTab, previousTab, shortcutsSheet, back, forward, enclosingFolder, jump, findFiles, goToPath, recents, home, desktop, documents, downloads, applications, iCloud, addFavorites, cleanUp, packages, gitChanges, newWorkspace

    var id: Self { self }

    var title: String {
        switch self {
        case .newTab: "New Tab"
        case .moveTo: "Move To…"
        case .copyTo: "Copy To…"
        case .newFolder: "New Folder"
        case .newTextFile: "New Text File"
        case .tidy: "Tidy Folder"
        case .open: "Open"
        case .quickLook: "Quick Look"
        case .infoPanel: "Info Panel"
        case .showInFinder: "Show in Finder"
        case .getInfo: "Get Info (Finder)"
        case .makeAlias: "Make Alias"
        case .airDrop: "AirDrop"
        case .terminal: "Open in Terminal"
        case .editor: "Open in Editor"
        case .trash: "Move to Trash"
        case .closeTab: "Close Tab"
        case .copyPath: "Copy Path"
        case .moveHere: "Move Copied Items Here"
        case .filter: "Filter This Folder"
        case .splitView: "Split View"
        case .swapPanes: "Swap Panes"
        case .otherPane: "Switch to Other Pane"
        case .sidebar: "Sidebar"
        case .listView: "View as List"
        case .iconView: "View as Icons"
        case .columnView: "View as Columns"
        case .biggerIcons: "Bigger Icons"
        case .smallerIcons: "Smaller Icons"
        case .shelf: "Shelf"
        case .hiddenFiles: "Hidden Files"
        case .nextTab: "Next Tab"
        case .previousTab: "Previous Tab"
        case .shortcutsSheet: "Keyboard Shortcuts"
        case .back: "Back"
        case .forward: "Forward"
        case .enclosingFolder: "Enclosing Folder"
        case .jump: "Jump to Folder or File"
        case .findFiles: "Find Files"
        case .goToPath: "Go to Path"
        case .recents: "Recents"
        case .home: "Home"
        case .desktop: "Desktop"
        case .documents: "Documents"
        case .downloads: "Downloads"
        case .applications: "Applications"
        case .iCloud: "iCloud Drive"
        case .addFavorites: "Add to Favorites"
        case .cleanUp: "Clean Up"
        case .packages: "Packages"
        case .gitChanges: "Git Changes"
        case .newWorkspace: "New Workspace"
        }
    }

    var defaultShortcut: KeyboardShortcut {
        switch self {
        case .newTab: KeyboardShortcut(KeyEquivalent("t"), modifiers: .command)
        case .moveTo: KeyboardShortcut(KeyEquivalent("m"), modifiers: [.command, .shift])
        case .copyTo: KeyboardShortcut(KeyEquivalent("m"), modifiers: [.command, .option, .shift])
        case .newFolder: KeyboardShortcut(KeyEquivalent("n"), modifiers: [.command, .shift])
        case .newTextFile: KeyboardShortcut(KeyEquivalent("n"), modifiers: [.command, .control])
        case .tidy: KeyboardShortcut(KeyEquivalent("t"), modifiers: [.command, .option])
        case .open: KeyboardShortcut(KeyEquivalent("o"), modifiers: .command)
        case .quickLook: KeyboardShortcut(KeyEquivalent("y"), modifiers: .command)
        case .infoPanel: KeyboardShortcut(KeyEquivalent("i"), modifiers: .command)
        case .showInFinder: KeyboardShortcut(KeyEquivalent("r"), modifiers: .command)
        case .getInfo: KeyboardShortcut(KeyEquivalent("i"), modifiers: [.command, .option])
        case .makeAlias: KeyboardShortcut(KeyEquivalent("a"), modifiers: [.command, .control])
        case .airDrop: KeyboardShortcut(KeyEquivalent("r"), modifiers: [.command, .shift])
        case .terminal: KeyboardShortcut(KeyEquivalent("t"), modifiers: [.command, .option, .shift])
        case .editor: KeyboardShortcut(KeyEquivalent("e"), modifiers: [.command, .option, .shift])
        case .trash: KeyboardShortcut(.delete, modifiers: .command)
        case .closeTab: KeyboardShortcut(KeyEquivalent("w"), modifiers: .command)
        case .copyPath: KeyboardShortcut(KeyEquivalent("c"), modifiers: [.command, .option])
        case .moveHere: KeyboardShortcut(KeyEquivalent("v"), modifiers: [.command, .option])
        case .filter: KeyboardShortcut(KeyEquivalent("f"), modifiers: .command)
        case .splitView: KeyboardShortcut(KeyEquivalent("d"), modifiers: .command)
        case .swapPanes: KeyboardShortcut(KeyEquivalent("u"), modifiers: .command)
        case .otherPane: KeyboardShortcut(.tab, modifiers: .option)
        case .sidebar: KeyboardShortcut(KeyEquivalent("s"), modifiers: [.command, .control])
        case .listView: KeyboardShortcut(KeyEquivalent("1"), modifiers: .command)
        case .iconView: KeyboardShortcut(KeyEquivalent("2"), modifiers: .command)
        case .columnView: KeyboardShortcut(KeyEquivalent("3"), modifiers: .command)
        case .biggerIcons: KeyboardShortcut(KeyEquivalent("="), modifiers: .command)
        case .smallerIcons: KeyboardShortcut(KeyEquivalent("-"), modifiers: .command)
        case .shelf: KeyboardShortcut(KeyEquivalent("s"), modifiers: [.command, .option])
        case .hiddenFiles: KeyboardShortcut(KeyEquivalent("."), modifiers: [.command, .shift])
        case .nextTab: KeyboardShortcut(KeyEquivalent("]"), modifiers: [.command, .shift])
        case .previousTab: KeyboardShortcut(KeyEquivalent("["), modifiers: [.command, .shift])
        case .shortcutsSheet: KeyboardShortcut(KeyEquivalent("/"), modifiers: .command)
        case .back: KeyboardShortcut(KeyEquivalent("["), modifiers: .command)
        case .forward: KeyboardShortcut(KeyEquivalent("]"), modifiers: .command)
        case .enclosingFolder: KeyboardShortcut(.upArrow, modifiers: .command)
        case .jump: KeyboardShortcut(KeyEquivalent("k"), modifiers: .command)
        case .findFiles: KeyboardShortcut(KeyEquivalent("f"), modifiers: [.command, .shift])
        case .goToPath: KeyboardShortcut(KeyEquivalent("l"), modifiers: .command)
        case .recents: KeyboardShortcut(KeyEquivalent("r"), modifiers: [.command, .option])
        case .home: KeyboardShortcut(KeyEquivalent("h"), modifiers: [.command, .shift])
        case .desktop: KeyboardShortcut(KeyEquivalent("d"), modifiers: [.command, .shift])
        case .documents: KeyboardShortcut(KeyEquivalent("o"), modifiers: [.command, .shift])
        case .downloads: KeyboardShortcut(KeyEquivalent("l"), modifiers: [.command, .option])
        case .applications: KeyboardShortcut(KeyEquivalent("a"), modifiers: [.command, .shift])
        case .iCloud: KeyboardShortcut(KeyEquivalent("i"), modifiers: [.command, .shift])
        case .addFavorites: KeyboardShortcut(KeyEquivalent("t"), modifiers: [.command, .control])
        case .cleanUp: KeyboardShortcut(KeyEquivalent("k"), modifiers: [.command, .shift])
        case .packages: KeyboardShortcut(KeyEquivalent("p"), modifiers: [.command, .option])
        case .gitChanges: KeyboardShortcut(KeyEquivalent("g"), modifiers: [.command, .option])
        case .newWorkspace: KeyboardShortcut(KeyEquivalent("n"), modifiers: [.command, .option])
        }
    }
}
