import AppKit
import ScoutCore
import SwiftUI

/// List view: sortable columns, multi-select, drag files out to other apps.
struct FileTableView: View {
    let window: BrowserWindowModel
    @Bindable var browser: BrowserModel

    var body: some View {
        Table(of: FileItem.self, selection: $browser.selection, sortOrder: $browser.sortOrder) {
            TableColumn("Name", value: \.name, comparator: .localizedStandard) { item in
                HStack(spacing: 8) {
                    FileIconView(item: item, size: browser.showsLocations ? 24 : 18)
                    if browser.showsLocations {
                        // Search results: show where each one lives.
                        VStack(alignment: .leading, spacing: 0) {
                            Text(item.name).lineLimit(1).truncationMode(.middle)
                            Text(PathDisplay.display(item.url.deletingLastPathComponent().filePath,
                                                     home: browser.services.homePath))
                                .font(.caption2).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.head)
                        }
                    } else {
                        Text(item.name).lineLimit(1).truncationMode(.middle)
                    }
                    if let state = browser.gitState(item) {
                        Spacer(minLength: 4)
                        GitBadge(state: state, isFolder: item.isNavigable)
                    }
                }
                .opacity(item.isHidden ? 0.55 : 1)
            }
            .width(min: 120, ideal: 150)

            TableColumn("Date Modified", value: \.modifiedSortKey) { item in
                FittingDate(date: item.dateModified).foregroundStyle(.secondary)
            }
            .width(min: 76, ideal: 120)

            TableColumn("Size", value: \.sizeSortKey) { item in
                Text(Format.size(item))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 52, ideal: 64)
        } rows: {
            ForEach(browser.displayedItems) { item in
                TableRow(item)
                    .itemProvider { NSItemProvider(contentsOf: item.url) }
            }
        }
        .contextMenu(forSelectionType: URL.self) { urls in
            FileContextMenu(window: window, browser: browser, urls: urls)
        } primaryAction: { urls in
            browser.open(urls)
        }
        // No stripes or column headers: Scout's header has a Sort menu instead.
        .tableStyle(.inset(alternatesRowBackgrounds: false))
        .tableColumnHeaders(.hidden)
        .scrollContentBackground(.hidden)
        .fileKeyboardShortcuts(browser)
        .onCopyCommand {
            browser.copySelectionToPasteboard()
            return []
        }
        .onPasteCommand(of: [.fileURL]) { _ in browser.paste(move: false) }
    }
}

/// Icon view with real thumbnails.
struct FileGridView: View {
    let window: BrowserWindowModel
    @Bindable var browser: BrowserModel
    @FocusState private var isFocused: Bool

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 112, maximum: 140), spacing: 6)], spacing: 16) {
                let items = browser.displayedItems
                let folders = items.filter(\.isNavigable)
                let files = items.filter { !$0.isNavigable }
                // Folders and files in their own sections (when folders are kept on top).
                if browser.foldersFirst, browser.isFolder, !folders.isEmpty, !files.isEmpty {
                    Section { cells(folders) } header: { sectionHeader("Folders", count: folders.count) }
                    Section { cells(files) } header: { sectionHeader("Files", count: files.count) }
                } else {
                    cells(items)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .contentShape(Rectangle())
        .onTapGesture { browser.selection = [] }
        .contextMenu { FileContextMenu(window: window, browser: browser, urls: []) }
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .fileKeyboardShortcuts(browser)
        .onCopyCommand {
            browser.copySelectionToPasteboard()
            return []
        }
        .onPasteCommand(of: [.fileURL]) { _ in browser.paste(move: false) }
        .onAppear { isFocused = true }
    }

    private func cells(_ items: [FileItem]) -> some View {
        ForEach(items) { item in
            GridCell(item: item, isSelected: browser.selection.contains(item.id), gitState: browser.gitState(item))
                .onTapGesture { click(item) }
                .contextMenu {
                    FileContextMenu(window: window, browser: browser,
                                    urls: browser.selection.contains(item.id) ? browser.selection : [item.id])
                }
                .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        }
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
            Text("\(count)").font(.subheadline).foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.top, 6)
    }

    private func click(_ item: FileItem) {
        isFocused = true
        if NSApp.currentEvent?.clickCount == 2 {
            browser.open([item.id])
            return
        }
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) || flags.contains(.shift) {
            if browser.selection.contains(item.id) { browser.selection.remove(item.id) }
            else { browser.selection.insert(item.id) }
        } else {
            browser.selection = [item.id]
        }
    }
}

private struct GridCell: View {
    let item: FileItem
    let isSelected: Bool
    var gitState: GitFileState?
    @State private var itemCount: Int?

    var body: some View {
        VStack(spacing: 4) {
            ThumbnailView(item: item, size: 64)
                .overlay(alignment: .bottomTrailing) {
                    if let gitState { GitBadge(state: gitState, isFolder: item.isNavigable).offset(x: 4, y: 2) }
                }
                .padding(6)
                .background(isSelected ? Color.secondary.opacity(0.2) : .clear,
                            in: RoundedRectangle(cornerRadius: 8))
            Text(item.name)
                .font(.callout)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .truncationMode(.middle)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .foregroundStyle(isSelected ? .white : .primary)
                .background(isSelected ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 5))
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(width: 112)
        .task(id: item.id) {
            guard item.isNavigable else { return }
            let url = item.url
            itemCount = await Task.detached(priority: .utility) { FolderStats.itemCount(of: url) }.value
        }
        .opacity(item.isHidden ? 0.55 : 1)
        .contentShape(Rectangle())
    }

    /// "12 items" under folders, "5.6 MB" under files.
    private var caption: String {
        if item.isNavigable {
            guard let itemCount else { return " " }
            return "\(itemCount) item\(itemCount == 1 ? "" : "s")"
        }
        return Format.size(item)
    }
}

private extension View {
    /// Space = Quick Look, Return = rename (like Finder).
    func fileKeyboardShortcuts(_ browser: BrowserModel) -> some View {
        self
            .onKeyPress(.space) {
                browser.toggleQuickLook()
                return .handled
            }
            .onKeyPress(.return) {
                browser.beginRename() ? .handled : .ignored
            }
    }
}

/// Right-click menu. `urls` empty = clicked on empty space.
struct FileContextMenu: View {
    let window: BrowserWindowModel
    let browser: BrowserModel
    let urls: Set<URL>

    private var items: [FileItem] { browser.displayedItems.filter { urls.contains($0.id) } }

    var body: some View {
        if urls.isEmpty {
            if browser.isFolder {
                Button("New Folder") { browser.newFolder() }
                Button("Paste") { browser.paste(move: false) }
                Divider()
            }
            Button("Open in \(DevApp.preferredTerminal?.name ?? "Terminal")") { browser.openInTerminal() }
            OpenInMenu(url: browser.location)
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([browser.location]) }
            Button("Copy Path") { copy(browser.location.filePath) }
            if let page = browser.gitHubURL(for: browser.location, isFolder: true) {
                Button("Open on GitHub") { NSWorkspace.shared.open(page) }
            }
        } else {
            let items = items
            Button("Open") { browser.open(urls) }
            if browser.showsLocations, items.count == 1, let item = items.first {
                Button("Show in Enclosing Folder") { browser.reveal(item.url) }
            }
            if items.allSatisfy(\.isNavigable) {
                Button(items.count == 1 ? "Open in New Tab" : "Open in New Tabs") {
                    for item in items { browser.pane?.newTab(at: item.url) }
                }
            }
            if items.count == 1, let item = items.first, !item.isNavigable {
                OpenWithMenu(url: item.url)
            }
            Button("Quick Look") {
                browser.selection = urls
                browser.toggleQuickLook()
            }
            Divider()
            Button("Rename…") {
                browser.selection = urls
                _ = browser.beginRename()
            }
            .disabled(items.count != 1)
            Button("Move to Trash") {
                browser.selection = urls
                browser.trashSelection()
            }
            Divider()
            Button("Copy") {
                browser.selection = urls
                browser.copySelectionToPasteboard()
            }
            Button("Copy Path") { copy(items.map(\.path).joined(separator: "\n")) }
            if browser.git != nil {
                let relative = items.compactMap { browser.repoRelativePath($0.url) }
                if !relative.isEmpty {
                    Button("Copy Path in Repository") { copy(relative.joined(separator: "\n")) }
                }
            }
            Divider()
            WorkspaceMenu(window: window, browser: browser, paths: items.map(\.path))
            if window.isSplit, let other = window.otherPane?.current, other.isFolder {
                Button("Copy to Other Pane") {
                    browser.selection = urls
                    browser.transfer(items.map(\.url), into: other.location, move: false)
                }
                Button("Move to Other Pane") {
                    browser.selection = urls
                    browser.transfer(items.map(\.url), into: other.location, move: true)
                }
            }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(items.map(\.url)) }
            if items.count == 1, let item = items.first {
                if item.isNavigable {
                    Button("Open in \(DevApp.preferredTerminal?.name ?? "Terminal")") { browser.openInTerminal(item.url) }
                }
                OpenInMenu(url: item.url)
                if let page = browser.gitHubURL(for: item.url, isFolder: item.isNavigable) {
                    Button("Open on GitHub") { NSWorkspace.shared.open(page) }
                }
            }
        }
    }

    private func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}

private struct OpenWithMenu: View {
    let url: URL

    var body: some View {
        let apps = Array(NSWorkspace.shared.urlsForApplications(toOpen: url).prefix(15))
        if !apps.isEmpty {
            Menu("Open With") {
                ForEach(apps, id: \.self) { app in
                    Button {
                        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
                    } label: {
                        Label {
                            Text(FileManager.default.displayName(atPath: app.filePath))
                        } icon: {
                            Image(nsImage: IconCache.icon(forPath: app.filePath))
                        }
                    }
                }
            }
        }
    }
}


/// "Add to Workspace" submenu (and "Remove from Workspace" when inside one).
private struct WorkspaceMenu: View {
    let window: BrowserWindowModel
    let browser: BrowserModel
    let paths: [String]
    @Environment(AppServices.self) private var services

    var body: some View {
        Menu("Add to Workspace") {
            ForEach(services.workspaces) { workspace in
                Button {
                    services.updateWorkspace(workspace.id) { $0.add(paths) }
                } label: {
                    Label(workspace.name, systemImage: workspace.symbol)
                }
                .disabled(workspace.id == browser.workspaceID)
            }
            if !services.workspaces.isEmpty { Divider() }
            Button("New Workspace…") { window.newWorkspacePaths = paths }
        }
        if let id = browser.workspaceID {
            Button("Remove from Workspace") {
                services.updateWorkspace(id) { $0.remove(Set(paths)) }
                Task { await browser.reload() }
            }
        }
    }
}
