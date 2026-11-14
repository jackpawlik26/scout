import AppKit
import Observation
import ScoutCore
import SwiftUI

/// One column of a window: its own tabs. A window has one pane, or two side by side (⌘D).
@Observable
final class PaneModel: Identifiable {
    let id = UUID()
    let services: AppServices
    private(set) var tabs: [BrowserModel] = []
    var selectedTabID: UUID
    @ObservationIgnored weak var window: BrowserWindowModel?

    init(services: AppServices, start: URL, viewMode: ViewMode? = nil) {
        self.services = services
        let first = BrowserModel(location: start, services: services)
        if let viewMode { first.viewMode = viewMode }
        selectedTabID = first.id
        tabs = [first]
        first.pane = self
    }

    /// Reopens saved tabs (skipping folders that are gone); nil when none survive.
    init?(services: AppServices, saved: WindowSession.Pane) {
        self.services = services
        let fm = FileManager.default
        let restored: [BrowserModel] = saved.tabs.compactMap { tab in
            guard fm.fileExists(atPath: tab.path) else { return nil }
            let model = BrowserModel(location: .folder(tab.path), services: services)
            if let mode = ViewMode(rawValue: tab.viewMode) { model.viewMode = mode }
            model.restore(tab.mode)
            return model
        }
        guard !restored.isEmpty else { return nil }
        tabs = restored
        selectedTabID = restored[min(max(saved.selected, 0), restored.count - 1)].id
        for tab in restored { tab.pane = self }
    }

    var current: BrowserModel { tabs.first { $0.id == selectedTabID } ?? tabs[0] }

    var saved: WindowSession.Pane {
        WindowSession.Pane(
            tabs: tabs.map { WindowSession.Tab(path: $0.location.filePath, mode: $0.mode, viewMode: $0.viewMode.rawValue) },
            selected: tabs.firstIndex { $0.id == selectedTabID } ?? 0)
    }

    func newTab(at url: URL? = nil) {
        let tab = BrowserModel(location: url ?? current.location, services: services)
        tab.pane = self
        tab.viewMode = current.viewMode
        let index = tabs.firstIndex { $0.id == selectedTabID } ?? tabs.count - 1
        tabs.insert(tab, at: index + 1)
        selectedTabID = tab.id
    }

    func closeTab(_ id: UUID) {
        guard tabs.count > 1, let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: index)
        if selectedTabID == id { selectedTabID = tabs[min(index, tabs.count - 1)].id }
    }

    func selectTab(offset: Int) {
        guard let index = tabs.firstIndex(where: { $0.id == selectedTabID }) else { return }
        selectedTabID = tabs[(index + offset + tabs.count) % tabs.count].id
    }
}

/// One Scout window: its panes and the overlays (⌘K palette, Go to Path).
@Observable
final class BrowserWindowModel {
    let services: AppServices
    private(set) var panes: [PaneModel] = []
    /// The pane that menus and shortcuts act on.
    private(set) var focusedPaneID: UUID

    var isPaletteOpen = false
    /// Text to pre-fill when the palette opens (from a `scout://jump?query=` link).
    var paletteInitialQuery = ""
    /// Scope to start the palette in (e.g. Files for ⇧⌘F).
    var paletteInitialScope: SearchScope?
    var isGoToPathOpen = false
    /// Compare Folders: the left and right panes' folders.
    var comparing: CompareRequest?

    /// Compares the two panes' folders (both must be showing a folder).
    func compareFolders() {
        guard isSplit, panes.count == 2, panes[0].current.isFolder, panes[1].current.isFolder else {
            current.alertMessage = "Open two folders side by side (⌘D) to compare them."
            return
        }
        comparing = CompareRequest(left: panes[0].current.location, right: panes[1].current.location)
    }
    /// The keyboard shortcuts sheet (⌘/).
    var isShortcutsOpen = false
    /// The window this model is shown in (set once SwiftUI puts it on screen).
    @ObservationIgnored weak var nsWindow: NSWindow?
    /// Remembered across launches.
    var isSidebarShown = UserDefaults.standard.object(forKey: "sidebarShown") as? Bool ?? true {
        didSet { UserDefaults.standard.set(isSidebarShown, forKey: "sidebarShown") }
    }
    /// The info panel on the right (⌘I). Remembered across launches.
    var isInspectorShown = UserDefaults.standard.bool(forKey: "inspectorShown") {
        didSet { UserDefaults.standard.set(isInspectorShown, forKey: "inspectorShown") }
    }
    /// Bumped to ask the current tab to focus its filter field (⌘F).
    var filterFocusRequest = 0
    /// Paths for a workspace being created (drives the "New Workspace" dialog).
    var newWorkspacePaths: [String]?
    /// Items waiting for a destination: the palette is picking a folder to move or copy them to.
    var destinationRequest: DestinationRequest?

    init(services: AppServices, start: URL) {
        self.services = services
        let first = PaneModel(services: services, start: start)
        focusedPaneID = first.id
        panes = [first]
        first.window = self
        services.register(self)
    }

    /// Reopens a window's tabs and split from last time; nil if none of its folders still exist.
    init?(services: AppServices, session: WindowSession) {
        self.services = services
        let restored = session.panes.prefix(2).compactMap { PaneModel(services: services, saved: $0) }
        guard !restored.isEmpty else { return nil }
        panes = restored
        focusedPaneID = restored[min(max(session.focused, 0), restored.count - 1)].id
        for pane in restored { pane.window = self }
        services.register(self)
    }

    /// Everything needed to reopen this window as it is: each pane's tabs and the split.
    var session: WindowSession {
        WindowSession(panes: panes.map(\.saved), focused: panes.firstIndex { $0.id == focusedPaneID } ?? 0)
    }

    var focusedPane: PaneModel { panes.first { $0.id == focusedPaneID } ?? panes[0] }
    var current: BrowserModel { focusedPane.current }
    var isSplit: Bool { panes.count > 1 }
    /// The pane that isn't focused, when split.
    var otherPane: PaneModel? { panes.first { $0.id != focusedPaneID } }

    func focus(_ pane: PaneModel) {
        if focusedPaneID != pane.id { focusedPaneID = pane.id }
    }

    // MARK: - Tabs (in the focused pane)

    func newTab(at url: URL? = nil) { focusedPane.newTab(at: url) }
    func selectTab(offset: Int) { focusedPane.selectTab(offset: offset) }

    /// ⌘W: closes the tab; then the pane (when split); then the window.
    func closeCurrentTab() {
        let pane = focusedPane
        if pane.tabs.count > 1 {
            pane.closeTab(pane.selectedTabID)
        } else if isSplit {
            closePane(pane)
        } else {
            NSApp.keyWindow?.performClose(nil)
        }
    }

    /// For folders opened from other apps: reuse a tab already showing it, or a fresh untouched
    /// home tab; otherwise open a new tab (the caller then navigates it).
    private func showInTab(_ folder: URL) {
        let pane = focusedPane
        if let existing = pane.tabs.first(where: { $0.isFolder && $0.location.filePath == folder.filePath }) {
            pane.selectedTabID = existing.id
            return
        }
        let tab = pane.current
        let untouched = tab.isFolder && tab.backStack.isEmpty && tab.location.filePath == services.home.filePath
        if !untouched { newTab(at: folder) }
    }

    // MARK: - Split view

    /// ⌘D: split into two panes (the new one starts where you are), or go back to one.
    func toggleSplit() {
        if let other = otherPane {
            closePane(other)
        } else {
            let pane = PaneModel(services: services, start: current.location, viewMode: current.viewMode)
            pane.window = self
            panes.append(pane)
            focusedPaneID = pane.id
        }
    }

    func closePane(_ pane: PaneModel) {
        guard isSplit else { return }
        panes.removeAll { $0.id == pane.id }
        focusedPaneID = panes[0].id
    }

    /// ⌘U: swap the two panes.
    func swapPanes() {
        guard isSplit else { return }
        panes.reverse()
    }

    /// ⌥⇥: move focus to the other pane.
    func focusOtherPane() {
        if let other = otherPane { focusedPaneID = other.id }
    }

    /// F5 / F6: copy or move the selection into the other pane's folder.
    func transferToOtherPane(move: Bool) {
        guard let target = otherPane?.current, target.isFolder else { return }
        let urls = current.selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        current.transfer(urls, into: target.location, move: move)
    }

    // MARK: - Move to… / Copy to…

    /// ⇧⌘M / ⌥⇧⌘M: pick a destination in the palette for the selected items.
    func beginMoveTo(copy: Bool) {
        let urls = current.selectedItems.map(\.url)
        guard !urls.isEmpty else {
            current.alertMessage = "Select the files or folders to \(copy ? "copy" : "move") first."
            return
        }
        destinationRequest = DestinationRequest(urls: urls, copy: copy)
        isPaletteOpen = true
    }

    /// Moves or copies the waiting items into `folder`. Returns an error message instead when it can't.
    func finishMoveTo(_ folder: URL, copy: Bool, follow: Bool) -> String? {
        guard let request = destinationRequest else { return nil }
        let target = folder.filePath
        if let inside = request.urls.first(where: { target == $0.filePath || target.hasPrefix($0.filePath + "/") }) {
            return "Can’t put “\(inside.lastPathComponent)” inside itself."
        }
        if !copy, request.urls.allSatisfy({ $0.deletingLastPathComponent().filePath == target }) {
            return "They’re already in “\(folder.lastPathComponent)”."
        }
        destinationRequest = nil
        RecentDestinations.add(target)
        current.transfer(request.urls, into: .folder(target), move: !copy)
        if follow {
            current.go(to: .folder(target), select: request.urls.count == 1 ? URL.folder(target).appending(path: request.urls[0].lastPathComponent) : nil)
        }
        return nil
    }

    // MARK: - Links

    /// Handles a `scout://` link from Raycast, Terminal or another app.
    func handle(_ link: ScoutLink) {
        switch link {
        case .open(let rawPath, let inNewTab, let inOtherPane):
            let path = PathCompletion.expandTilde(rawPath, home: services.homePath)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else {
                current.alertMessage = "“\(path)” doesn’t exist."
                return
            }
            let url = URL(filePath: path)
            let isFolder = isDir.boolValue && !NSWorkspace.shared.isFilePackage(atPath: path)
            let folder = isFolder ? url : url.deletingLastPathComponent()
            if inOtherPane {
                if !isSplit { toggleSplit() } else { focusOtherPane() }
            }
            if inNewTab { showInTab(folder) }
            current.go(to: folder, select: isFolder ? nil : url)
        case .workspace(let name):
            if let workspace = services.workspaces.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
                current.showWorkspace(workspace.id)
            } else {
                current.alertMessage = "There’s no workspace named “\(name)”."
            }
        case .cleanup:
            current.showCleanup()
        case .packages:
            current.showPackages()
        case .settings:
            current.showSettings()
        case .recents:
            current.showRecents()
        case .history:
            current.showHistory()
        case .diskMap(let path):
            current.showDiskMap(path.map { URL.folder(PathCompletion.expandTilde($0, home: services.homePath)).filePath }
                                ?? services.homePath)
        case .triage(let path):
            current.showTriage(path.map { URL.folder(PathCompletion.expandTilde($0, home: services.homePath)).filePath })
        case .tidy(let rawPath):
            let folder = URL.folder(PathCompletion.expandTilde(rawPath, home: services.homePath))
            current.go(to: folder)
            Task {
                // Plan once the folder has loaded.
                for _ in 0..<40 where current.location.filePath != folder.filePath || current.isLoading {
                    try? await Task.sleep(for: .milliseconds(50))
                }
                try? await Task.sleep(for: .milliseconds(100))
                current.beginTidy()
            }
        case .shortcuts:
            isPaletteOpen = false
            isShortcutsOpen = true
        case .changes(let path):
            current.showChanges(in: PathCompletion.expandTilde(path, home: services.homePath))
        case .jump(let query):
            paletteInitialQuery = query ?? ""
            isPaletteOpen = true
        }
    }
}

/// Files waiting for Move to… / Copy to… to pick a folder.
struct DestinationRequest {
    var urls: [URL]
    var copy: Bool

    var summary: String {
        urls.count == 1 ? "“\(urls[0].lastPathComponent)”" : "\(urls.count) items"
    }
}

/// Folders you recently moved or copied things to, offered first next time.
enum RecentDestinations {
    private static let key = "recentDestinations"

    static var paths: [String] {
        (UserDefaults.standard.stringArray(forKey: key) ?? []).filter { FileManager.default.fileExists(atPath: $0) }
    }

    static func add(_ path: String) {
        var list = UserDefaults.standard.stringArray(forKey: key) ?? []
        list.removeAll { $0 == path }
        list.insert(path, at: 0)
        UserDefaults.standard.set(Array(list.prefix(8)), forKey: key)
    }
}

/// A window's tabs and split view, saved so they come back after quitting (like Finder).
struct WindowSession: Codable, Equatable {
    struct Tab: Codable, Equatable {
        var path: String
        var mode: BrowserMode
        var viewMode: String
    }

    struct Pane: Codable, Equatable {
        var tabs: [Tab]
        var selected: Int
    }

    var panes: [Pane]
    var focused: Int

    var encoded: String {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    init(panes: [Pane], focused: Int) {
        self.panes = panes
        self.focused = focused
    }

    init?(encoded: String) {
        guard !encoded.isEmpty, let data = encoded.data(using: .utf8),
              let session = try? JSONDecoder().decode(WindowSession.self, from: data) else { return nil }
        self = session
    }
}

extension FocusedValues {
    @Entry var browserWindow: BrowserWindowModel?
}

/// The two folders Compare Folders is looking at.
struct CompareRequest: Identifiable {
    let id = UUID()
    let left: URL
    let right: URL
}
