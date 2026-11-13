import AppKit
import ScoutCore
import SwiftUI

/// List view: sortable columns, multi-select, drag files out to other apps.
struct FileTableView: View {
    let window: BrowserWindowModel
    @Bindable var browser: BrowserModel

    @State private var anchor = TableAnchor()
    /// Which columns show (right-click a header to change), remembered per window.
    @SceneStorage("scout.listColumns") private var columns = TableColumnCustomization<FileItem>()
    @AppStorage("columnHeaders") private var showHeaders = true

    /// The date column sorts by the date it shows.
    private var dateComparator: KeyPathComparator<FileItem> {
        switch browser.shownDate {
        case .added: KeyPathComparator(\FileItem.addedSortKey)
        case .created: KeyPathComparator(\FileItem.createdSortKey)
        default: KeyPathComparator(\FileItem.modifiedSortKey)
        }
    }

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
        Table(of: FileItem.self, selection: $browser.selection, sortOrder: $browser.sortOrder, columnCustomization: $columns) {
            TableColumn("Name", value: \.name, comparator: .localizedStandard) { item in
                HStack(spacing: 8) {
                    if browser.isFolder {
                        DisclosureButton(item: item, browser: browser)
                            .padding(.leading, CGFloat(browser.depth[item.id] ?? 0) * 16)
                    }
                    FileIconView(item: item, size: browser.showsLocations ? 24 : 18)
                    if browser.showsLocations {
                        // Search results: show where each one lives.
                        VStack(alignment: .leading, spacing: 0) {
                            Text(browser.services.displayName(item)).lineLimit(1).truncationMode(.middle)
                            Text(PathDisplay.display(item.url.deletingLastPathComponent().filePath,
                                                     home: browser.services.homePath))
                                .font(.caption2).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.head)
                        }
                    } else {
                        Text(browser.services.displayName(item)).lineLimit(1).truncationMode(.middle)
                        if browser.isFolder, browser.services.customizations.isPinned(item.path) {
                            Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(.secondary)
                                .help("Pinned to the top")
                        }
                    }
                    TagDots(tags: item.tags)
                    CloudBadge(state: item.cloud)
                    if let state = browser.gitState(item) {
                        Spacer(minLength: 4)
                        GitBadge(state: state, isFolder: item.isNavigable)
                    }
                }
                .opacity(item.isHidden ? 0.55 : 1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .folderDropTarget(item, browser: browser)
            }
            .width(min: 120, ideal: 150)
            .customizationID("name")
            .disabledCustomizationBehavior(.visibility)

            TableColumn(Text(browser.groupBy == .dateOpened ? "Date Last Opened" : browser.shownDate.title),
                        sortUsing: dateComparator) { item in
                FittingDate(date: browser.date(of: item)).foregroundStyle(.secondary)
            }
            .width(min: 76, ideal: 120)
            .customizationID("date")

            TableColumn("Kind", value: \.kind, comparator: .localizedStandard) { item in
                Text(item.isNavigable ? "Folder" : item.kind).foregroundStyle(.secondary).lineLimit(1)
            }
            .width(min: 60, ideal: 110)
            .customizationID("kind")
            .defaultVisibility(.hidden)

            TableColumn("Tags") { item in
                HStack(spacing: 4) {
                    TagDots(tags: item.tags)
                    Text(item.tags.map(\.name).joined(separator: ", ")).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .width(min: 50, ideal: 90)
            .customizationID("tags")
            .defaultVisibility(.hidden)

            TableColumn("Size", value: \.sizeSortKey) { item in
                Text(Format.size(item))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 52, ideal: 64)
            .customizationID("size")
        } rows: {
            if browser.groupBy == .none {
                ForEach(browser.displayedItems) { item in
                    TableRow(item)
                        .itemProvider { NSItemProvider(contentsOf: item.url) }
                }
            } else {
                ForEach(browser.displayedGroups) { group in
                    Section {
                        ForEach(group.items) { item in
                            TableRow(item)
                                .itemProvider { NSItemProvider(contentsOf: item.url) }
                        }
                    } header: {
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
        .onKeyPress(.rightArrow) {
            let folders = browser.selectedItems.filter { $0.isNavigable && !browser.expanded.contains($0.id) }
            guard browser.isFolder, !folders.isEmpty else { return .ignored }
            for folder in folders { browser.toggleExpanded(folder, recursive: NSEvent.modifierFlags.contains(.option)) }
            return .handled
        }
        .onKeyPress(.leftArrow) {
            let open = browser.selectedItems.filter { browser.expanded.contains($0.id) }
            guard browser.isFolder, !open.isEmpty else { return .ignored }
            for folder in open { browser.toggleExpanded(folder) }
            return .handled
        }
        .tableStyle(.inset(alternatesRowBackgrounds: false))
        .tableColumnHeaders(showHeaders ? .visible : .hidden)
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

    @AppStorage("iconSize") private var iconSize = 64.0
    private var cellWidth: CGFloat { max(96, iconSize + 48) }
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
        max(1, Int((width - Self.padding * 2 + Self.spacing) / (cellWidth + Self.spacing)))
    }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: cellWidth, maximum: cellWidth + 28), spacing: Self.spacing)], spacing: 16) {
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
            GridCell(item: item, isSelected: browser.selection.contains(item.id), gitState: browser.gitState(item),
                     iconSize: iconSize, width: cellWidth)
                .onTapGesture { click(item) }
                .contextMenu {
                    FileContextMenu(window: window, browser: browser,
                                    urls: browser.selection.contains(item.id) ? browser.selection : [item.id])
                }
                .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
                .folderDropTarget(item, browser: browser)
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
    var iconSize: CGFloat = 64
    var width: CGFloat = 112
    @State private var itemCount: Int?
    @Environment(AppServices.self) private var services: AppServices?

    var body: some View {
        VStack(spacing: 4) {
            ThumbnailView(item: item, size: iconSize)
                .overlay(alignment: .bottomTrailing) {
                    if let gitState { GitBadge(state: gitState, isFolder: item.isNavigable).offset(x: 4, y: 2) }
                }
                .padding(6)
                .background(isSelected ? Color.secondary.opacity(0.2) : .clear,
                            in: RoundedRectangle(cornerRadius: 8))
            HStack(spacing: 4) {
                TagDots(tags: item.tags, size: 8)
                CloudBadge(state: item.cloud)
                Text(services?.displayName(item) ?? item.name)
            }
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
        .frame(width: width)
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

extension View {
    /// Folders accept drops (files move into them) and open after a moment's hover while
    /// dragging ("spring-loaded"), so you can drop deeper. Files are left as they are.
    func folderDropTarget(_ item: FileItem, browser: BrowserModel) -> some View {
        modifier(FolderDropTarget(item: item, browser: browser))
    }
}

private struct FolderDropTarget: ViewModifier {
    let item: FileItem
    let browser: BrowserModel
    @State private var isTargeted = false
    @State private var spring: Task<Void, Never>?

    func body(content: Content) -> some View {
        if item.isNavigable {
            content
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor, lineWidth: 2)
                    .opacity(isTargeted ? 1 : 0).allowsHitTesting(false))
                .dropDestination(for: URL.self) { urls, _ in
                    spring?.cancel()
                    return browser.receiveDrop(urls, into: item.url)
                } isTargeted: { targeted in
                    isTargeted = targeted
                    spring?.cancel()
                    guard targeted else { return }
                    spring = Task {
                        try? await Task.sleep(for: .seconds(1))
                        if !Task.isCancelled { browser.go(to: item.url) }
                    }
                }
        } else {
            content
        }
    }
}

/// Online-only (cloud) or downloading, like Finder's cloud icons. Nothing when it's on this Mac.
struct CloudBadge: View {
    let state: CloudState?

    var body: some View {
        switch state {
        case .online:
            Image(systemName: "icloud.and.arrow.down").font(.system(size: 10)).foregroundStyle(.secondary)
                .help("In the cloud only. Opens after downloading.")
        case .downloading:
            Image(systemName: "arrow.down.circle.dotted").font(.system(size: 10)).foregroundStyle(Color.accentColor)
                .help("Downloading")
        default:
            EmptyView()
        }
    }
}

/// The little arrow that opens a folder in place (⌥-click opens everything inside).
private struct DisclosureButton: View {
    let item: FileItem
    let browser: BrowserModel

    var body: some View {
        if item.isNavigable {
            Button {
                withAnimation(.snappy(duration: 0.15)) {
                    browser.toggleExpanded(item, recursive: NSEvent.modifierFlags.contains(.option))
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(browser.expanded.contains(item.id) ? 90 : 0))
                    .frame(width: 12, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Show contents (⌥-click: everything inside)")
        } else {
            Color.clear.frame(width: 12, height: 16)
        }
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
    @Environment(\.openWindow) private var openWindow

    private var items: [FileItem] { browser.displayedItems.filter { urls.contains($0.id) } }

    var body: some View {
        if urls.isEmpty {
            if browser.isFolder {
                Button("New Folder") { browser.newFolder() }
                Button("Tidy Folder…") { browser.beginTidy() }
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
            Button("Show in Finder") { FinderBridge.reveal([browser.location]) }
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
            QuickActionsMenu(browser: browser, urls: urls)
            if items.contains(where: { $0.cloud == .online }) {
                Button("Download Now") { browser.downloadCloudItems(items) }
            }
            if items.contains(where: { $0.cloud == .downloaded }) {
                Button("Remove Download") { browser.removeCloudDownloads(items) }
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
            TagsMenu(browser: browser, items: items)
            CustomizeMenu(browser: browser, items: items)
            Button("Add to Shelf") {
                browser.services.addToShelf(items.map(\.url))
                openWindow(id: "shelf")
            }
            let unpinned = items.filter { $0.isNavigable && !browser.services.isFavorite($0.path) }
            if !unpinned.isEmpty {
                Button("Add to Favorites") { browser.services.addFavorites(unpinned.map(\.path)) }
            }
            WorkspaceMenu(window: window, browser: browser, paths: items.map(\.path))
            Button("Move To…") {
                browser.selection = urls
                window.beginMoveTo(copy: false)
            }
            Button("Copy To…") {
                browser.selection = urls
                window.beginMoveTo(copy: true)
            }
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
            Button("Show in Finder") { FinderBridge.reveal(items.map(\.url)) }
            Divider()
            Button("Duplicate") {
                browser.selection = urls
                browser.duplicateSelection()
            }
            Button("Make Alias") {
                browser.selection = urls
                browser.makeAliases()
            }
            ShareLink(items: items.map(\.url)) { Label("Share…", systemImage: "square.and.arrow.up") }
            Button("AirDrop…") {
                browser.selection = urls
                browser.airDropSelection()
            }
            Button("Get Info (Finder)") {
                browser.selection = urls
                browser.showFinderInfo()
            }
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


/// Right-click ▸ Customize: folder color and symbol, nickname, pin to top. Scout-only.
private struct CustomizeMenu: View {
    let browser: BrowserModel
    let items: [FileItem]

    var body: some View {
        let services = browser.services
        let folders = items.filter(\.isNavigable)
        Menu("Customize") {
            if !folders.isEmpty {
                Menu("Folder Color") {
                    ForEach(ItemStyle.colors, id: \.self) { color in
                        Button(color.capitalized) { for folder in folders { services.customize(folder.path) { $0.color = color } } }
                    }
                    Divider()
                    Button("Default") { for folder in folders { services.customize(folder.path) { $0.color = nil } } }
                }
                Menu("Folder Symbol") {
                    ForEach(ItemStyle.symbols, id: \.self) { symbol in
                        Button { for folder in folders { services.customize(folder.path) { $0.symbol = symbol } } } label: {
                            Label(symbol, systemImage: symbol)
                        }
                    }
                    Divider()
                    Button("None") { for folder in folders { services.customize(folder.path) { $0.symbol = nil } } }
                }
            }
            if items.count == 1, let item = items.first {
                Button("Nickname…") { browser.nicknaming = item }
                if services.customizations.style(for: item.path)?.nickname != nil {
                    Button("Remove Nickname") {
                        services.customize(item.path) { $0.nickname = nil }
                        browser.refresh()
                    }
                }
            }
            if browser.isFolder {
                let pinned = items.allSatisfy { services.customizations.isPinned($0.path) }
                Button(pinned ? "Unpin" : "Pin to Top") {
                    for item in items where services.customizations.isPinned(item.path) == pinned { services.togglePin(item.path) }
                    browser.refresh()
                }
            }
        }
    }
}

/// Image and PDF actions that fit the selection. Results land next to the originals.
private struct QuickActionsMenu: View {
    let browser: BrowserModel
    let urls: Set<URL>

    var body: some View {
        let images = urls.filter(QuickActions.isImage)
        let pdfs = urls.filter(QuickActions.isPDF)
        if !images.isEmpty || pdfs.count > 1 {
            Menu("Quick Actions") {
                if !images.isEmpty {
                    Menu("Convert Image") {
                        ForEach(QuickActions.ImageFormat.allCases) { format in
                            Button("to \(format.title)") {
                                browser.selection = urls
                                browser.convertImages(to: format)
                            }
                        }
                    }
                    Menu("Resize Image") {
                        ForEach([3840, 2560, 1920, 1280, 800, 400], id: \.self) { size in
                            Button("Longest side \(size) px") {
                                browser.selection = urls
                                browser.resizeImages(maxPixels: size)
                            }
                        }
                    }
                }
                if pdfs.count > 1 {
                    Button("Combine \(pdfs.count) PDFs") {
                        browser.selection = urls
                        browser.combinePDFs()
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
