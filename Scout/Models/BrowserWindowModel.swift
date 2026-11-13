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

    var current: BrowserModel { tabs.first { $0.id == selectedTabID } ?? tabs[0] }

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

    init(services: AppServices, start: URL) {
        self.services = services
        let first = PaneModel(services: services, start: start)
        focusedPaneID = first.id
        panes = [first]
        first.window = self
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
            if inNewTab { newTab(at: folder) }
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
        case .changes(let path):
            current.showChanges(in: PathCompletion.expandTilde(path, home: services.homePath))
        case .jump(let query):
            paletteInitialQuery = query ?? ""
            isPaletteOpen = true
        }
    }
}

extension FocusedValues {
    @Entry var browserWindow: BrowserWindowModel?
}
