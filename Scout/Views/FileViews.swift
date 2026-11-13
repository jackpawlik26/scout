import AppKit
import ScoutCore
import SwiftUI

/// List view: sortable columns, multi-select, drag files out to other apps.
struct FileTableView: View {
    let window: BrowserWindowModel
    @Bindable var browser: BrowserModel

    @State private var anchor = TableAnchor()

    var body: some View {
        table
            .background(TableAnchorView(anchor: anchor))
            .onChange(of: browser.location) {
                Task {
                    try? await Task.sleep(for: .milliseconds(100))
                    anchor.focus()
                }
            }
            .onChange(of: browser.scrollTarget) { _, target in
                guard let target else { return }
                // SwiftUI's scrollTo doesn't reach Table rows, so ask the AppKit table directly,
                // now and again once a freshly loaded folder has laid out.
                let row = { browser.displayedItems.firstIndex { $0.id == target } }
                if let index = row() { anchor.scroll(to: index) }
                Task {
                    try? await Task.sleep(for: .milliseconds(150))
                    if let index = row() { anchor.scroll(to: index) }
                    browser.scrollTarget = nil
                }
            }
    }

    private var table: some View {
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
                FittingDate(date: browser.date(of: item)).foregroundStyle(.secondary)
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
            ForEach(browser.displayedGroups) { group in
                Section {
                    ForEach(group.items) { item in
                        TableRow(item)
                            .itemProvider { NSItemProvider(contentsOf: item.url) }
                    }
                } header: {
                    if !group.title.isEmpty {
                        GroupHeader(title: group.title, count: group.items.count)
                    }
                }
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

    @State private var width: CGFloat = 0

    static let cellWidth: CGFloat = 112
    static let spacing: CGFloat = 6
    static let padding: CGFloat = 16

    /// The Group By groups; or Folders and Files (when folders are kept on top); else one.
    private var sections: [[FileItem]] { groups.map(\.items) }

    private var groups: [ItemGroup] {
        if browser.groupBy != .none { return browser.displayedGroups }
        let items = browser.displayedItems
        let folders = items.filter(\.isNavigable)
        let files = items.filter { !$0.isNavigable }
        if browser.foldersFirst, browser.isFolder, !folders.isEmpty, !files.isEmpty {
            return [ItemGroup(title: "Folders", items: folders), ItemGroup(title: "Files", items: files)]
        }
        return [ItemGroup(title: "", items: items)]
    }

    private var columnCount: Int {
        max(1, Int((width - Self.padding * 2 + Self.spacing) / (Self.cellWidth + Self.spacing)))
    }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.cellWidth, maximum: 140), spacing: Self.spacing)], spacing: 16) {
                ForEach(groups) { group in
                    if group.title.isEmpty {
                        cells(group.items)
                    } else {
                        Section { cells(group.items) } header: { sectionHeader(group.title, count: group.items.count) }
                    }
                }
            }
            .padding(Self.padding)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .onChange(of: browser.scrollTarget) { _, target in scroll(proxy, to: target, browser) }
        }
        .contentShape(Rectangle())
        .onTapGesture { browser.selection = [] }
        .contextMenu { FileContextMenu(window: window, browser: browser, urls: []) }
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { move(.left) }
        .onKeyPress(.rightArrow) { move(.right) }
        .onKeyPress(.upArrow) { move(.up) }
        .onKeyPress(.downArrow) { move(.down) }
        .fileKeyboardShortcuts(browser)
        .onCopyCommand {
            browser.copySelectionToPasteboard()
            return []
        }
        .onPasteCommand(of: [.fileURL]) { _ in browser.paste(move: false) }
        .onAppear { isFocused = true }
        .onChange(of: browser.location) { if !isEditingText { isFocused = true } }
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

    private enum Direction { case left, right, up, down }

    /// Arrow keys move the selection through the grid, row by row within each section.
    private func move(_ direction: Direction) -> KeyPress.Result {
        let sections = sections
        let flat = sections.flatMap(\.self)
        guard !flat.isEmpty else { return .ignored }
        guard let current = flat.lastIndex(where: { browser.selection.contains($0.id) }) else {
            browser.select(flat[0])
            return .handled
        }
        var target = current
        switch direction {
        case .left: target = max(0, current - 1)
        case .right: target = min(flat.count - 1, current + 1)
        case .up, .down:
            // Position inside its section.
            var start = 0
            var sectionIndex = 0
            while current >= start + sections[sectionIndex].count {
                start += sections[sectionIndex].count
                sectionIndex += 1
            }
            let columns = columnCount
            let index = current - start
            let column = index % columns
            let count = sections[sectionIndex].count
            if direction == .down {
                if index + columns < count {
                    target = current + columns
                } else if (index / columns) < (count - 1) / columns {
                    target = start + count - 1 // a shorter last row
                } else if sectionIndex + 1 < sections.count {
                    target = start + count + min(column, sections[sectionIndex + 1].count - 1)
                }
            } else {
                if index - columns >= 0 {
                    target = current - columns
                } else if sectionIndex > 0 {
                    let previous = sections[sectionIndex - 1].count
                    let lastRowStart = (previous - 1) / columns * columns
                    target = start - previous + min(lastRowStart + column, previous - 1)
                }
            }
        }
        browser.select(flat[target])
        return .handled
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

/// A Finder-style group title ("Documents", "Yesterday") with its count.
struct GroupHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title).font(.system(size: 12, weight: .semibold))
            Text("\(count)").font(.system(size: 11)).foregroundStyle(.tertiary).monospacedDigit()
            Spacer()
        }
        .padding(.top, 6)
    }
}

/// Finds the NSTableView behind a SwiftUI Table (the one this anchor sits on).
@MainActor final class TableAnchor {
    weak var view: NSView?

    func scroll(to row: Int) {
        guard let table = findTable(), row < table.numberOfRows else { return }
        table.scrollRowToVisible(row)
        focus()
    }

    /// Gives the list keyboard focus (so arrows and type-select work right after a jump),
    /// unless you're typing in a field.
    func focus() {
        guard let table = findTable(), let window = table.window, !(window.firstResponder is NSText) else { return }
        window.makeFirstResponder(table)
    }

    private func findTable() -> NSTableView? {
        guard let view, view.window != nil else { return nil }
        let center = view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
        var ancestor = view.superview
        while let current = ancestor {
            if let table = Self.tables(in: current).first(where: { table in
                guard let scroll = table.enclosingScrollView else { return false }
                return scroll.convert(scroll.bounds, to: nil).contains(center)
            }) {
                return table
            }
            ancestor = current.superview
        }
        return nil
    }

    private static func tables(in view: NSView) -> [NSTableView] {
        if let table = view as? NSTableView { return [table] }
        return view.subviews.flatMap(tables(in:))
    }
}

private struct TableAnchorView: NSViewRepresentable {
    let anchor: TableAnchor

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) { anchor.view = view }
}

/// Scrolls the list or grid to a newly selected item, once a freshly loaded folder has laid out.
@MainActor private func scroll(_ proxy: ScrollViewProxy, to target: URL?, _ browser: BrowserModel) {
    guard target != nil else { return }
    proxy.scrollTo(target)
    Task {
        // Again once a freshly loaded folder has its real row heights.
        try? await Task.sleep(for: .milliseconds(150))
        proxy.scrollTo(target)
        browser.scrollTarget = nil // so selecting the same item again scrolls again
    }
}

private extension View {
    /// Space = Quick Look, Return = rename (like Finder).
    func fileKeyboardShortcuts(_ browser: BrowserModel) -> some View {
        self
            .onKeyPress(.space) {
                // Mid type-select, Space is part of the name ("my f…").
                if browser.isTypeSelecting { browser.typeSelect(" ") } else { browser.toggleQuickLook() }
                return .handled
            }
            .onKeyPress(characters: .alphanumerics.union(.punctuationCharacters).union(.symbols), phases: .down) { press in
                guard press.modifiers.isDisjoint(with: [.command, .control, .option]) else { return .ignored }
                browser.typeSelect(press.characters)
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
                Menu("New File") {
                    ForEach(BrowserModel.NewFileKind.allCases, id: \.self) { kind in
                        Button(kind.title) { browser.newFile(kind) }
                    }
                }
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
            Button(items.count == 1 ? "Rename…" : "Rename \(items.count) Items…") {
                browser.selection = urls
                _ = browser.beginRename()
            }
            Button(items.count == 1 ? "Compress “\(items[0].name)”" : "Compress \(items.count) Items") {
                browser.selection = urls
                browser.compressSelection()
            }
            if items.contains(where: { Archiver.canExtract($0.url) }) {
                Button("Extract Here") {
                    browser.selection = urls
                    browser.extractSelection()
                }
            }
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
            let unpinned = items.filter { $0.isNavigable && !browser.services.isFavorite($0.path) }
            if !unpinned.isEmpty {
                Button("Add to Favorites") { browser.services.addFavorites(unpinned.map(\.path)) }
            }
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
