import QuickLook
import ScoutCore
import SwiftUI

/// The main card: header (title, path, controls), tabs, files, footer.
struct BrowserPane: View {
    let window: BrowserWindowModel
    let pane: PaneModel
    @Bindable var browser: BrowserModel
    @Environment(\.undoManager) private var undoManager
    @Environment(AppServices.self) private var services
    @State private var renameText = ""
    @State private var isFilterShown = false
    @FocusState private var isFilterFocused: Bool
    @State private var isNamingSearch = false
    @State private var searchName = ""
    @State private var isRenamingWorkspace = false
    @State private var workspaceName = ""
    @State private var newTagName = ""
    @State private var nickname = ""

    /// Only built while Quick Look is open (it's every item in the folder).
    private var quickLookItems: [URL] {
        browser.previewURL == nil ? [] : browser.displayedItems.map(\.url)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if pane.tabs.count > 1 {
                TabStrip(pane: pane)
            }
            if let search = browser.search {
                searchHeader(search)
            }
            if let workspace = browser.workspace {
                workspaceHeader(workspace)
            }
            if browser.changesRoot != nil {
                changesHeader
            }
            if isFilterShown || !browser.filterText.isEmpty {
                filterBar
            }
            Rectangle().fill(Color.hairline).frame(height: 1)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if !browser.isToolPage { footer }
        }
        .navigationTitle(browser.title)
        .quickLookPreview($browser.previewURL, in: quickLookItems)
        .onAppear { browser.undoManager = undoManager }
        .onChange(of: undoManager) { _, manager in browser.undoManager = manager }
        .onChange(of: window.filterFocusRequest) { showFilter() }
        // Commits, checkouts and edits made elsewhere show up when you come back.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            browser.refreshGit()
        }
        .onChange(of: browser.renaming) { _, item in
            if let item { renameText = item.name }
        }
        .alert("Rename", isPresented: renameBinding, presenting: browser.renaming) { item in
            TextField("Name", text: $renameText)
            Button("Rename") { browser.rename(item, to: renameText) }
                .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {}
        } message: { item in
            Text("Enter a new name for “\(item.name)”.")
        }
        .alert("Save Search", isPresented: $isNamingSearch) {
            TextField("Name", text: $searchName)
            Button("Save") {
                if let search = browser.search {
                    var saved = search
                    saved.name = searchName.trimmingCharacters(in: .whitespaces).isEmpty ? search.name : searchName
                    services.save(saved)
                    browser.showSearch(saved)
                }
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It will appear in the sidebar and stay up to date.")
        }
        .alert("Rename Workspace", isPresented: $isRenamingWorkspace) {
            TextField("Name", text: $workspaceName)
            Button("Rename") {
                guard let id = browser.workspaceID else { return }
                let name = workspaceName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { services.updateWorkspace(id) { $0.name = name } }
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $browser.conflict) { prompt in
            ConflictView(prompt: prompt)
                .interactiveDismissDisabled()
        }
        .alert("Nickname", isPresented: Binding(get: { browser.nicknaming != nil }, set: { if !$0 { browser.nicknaming = nil } }),
               presenting: browser.nicknaming) { item in
            TextField(item.name, text: $nickname)
            Button("Save") {
                let name = nickname.trimmingCharacters(in: .whitespaces)
                services.customize(item.path) { $0.nickname = name.isEmpty ? nil : name }
                browser.refresh()
                nickname = ""
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) { nickname = "" }
        } message: { item in
            Text("Shown in Scout instead of “\(item.name)”. The name on disk doesn’t change.")
        }
        .alert("New Tag", isPresented: newTagBinding) {
            TextField("Name", text: $newTagName)
            Button("Add") {
                let name = newTagName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty, let items = browser.newTagItems {
                    browser.toggleTag(FileTag(name: name, color: 0), on: items)
                }
                newTagName = ""
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) { newTagName = "" }
        }
        .sheet(item: tidyBinding) { plan in
            TidyView(browser: browser, moves: plan.moves)
        }
        .sheet(item: batchRenameBinding) { batch in
            BatchRenameView(browser: browser, items: batch.items)
        }
        .alert("Scout", isPresented: alertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(browser.alertMessage ?? "")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 0) {
                IconButton(symbol: "chevron.left", help: "Back (⌘[)") { browser.goBack() }
                    .disabled(browser.backStack.isEmpty)
                    .opacity(browser.backStack.isEmpty ? 0.35 : 1)
                IconButton(symbol: "chevron.right", help: "Forward (⌘])") { browser.goForward() }
                    .disabled(browser.forwardStack.isEmpty)
                    .opacity(browser.forwardStack.isEmpty ? 0.35 : 1)
            }

            titleBlock
                .layoutPriority(1)

            WindowDragArea().frame(minWidth: 12, maxHeight: 40)

            ViewThatFits(in: .horizontal) {
                fullControls
                compactControls
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .padding(.top, 10)
        .padding(.bottom, 10)
    }

    /// Header controls when there's room.
    private var fullControls: some View {
        HStack(spacing: 10) {
            if let git = browser.git {
                GitChip(browser: browser, git: git)
            }
            if !browser.isToolPage {
                HStack(spacing: 0) {
                    IconButton(symbol: "list.bullet", isOn: browser.viewMode == .list, help: "List (⌘1)") {
                        browser.viewMode = .list
                    }
                    IconButton(symbol: "square.grid.2x2", isOn: browser.viewMode == .icons, help: "Icons (⌘2)") {
                        browser.viewMode = .icons
                    }
                    IconButton(symbol: "rectangle.split.3x1", isOn: browser.viewMode == .columns, help: "Columns (⌘3)") {
                        browser.viewMode = .columns
                    }
                }
                .padding(2)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.045)))

                SortMenu(browser: browser)
                IconButton(symbol: "line.3.horizontal.decrease", isOn: isFilterShown || !browser.filterText.isEmpty,
                           help: "Filter This Folder (⌘F)") {
                    if isFilterShown { hideFilter() } else { showFilter() }
                }
            }
            if window.isSplit {
                IconButton(symbol: "xmark", help: "Close Pane") { window.closePane(pane) }
            }
            IconButton(symbol: "sidebar.right", isOn: window.isInspectorShown, help: "Info Panel (⌘I)") {
                withAnimation(.snappy(duration: 0.25)) { window.isInspectorShown.toggle() }
            }
        }
        .fixedSize()
    }

    /// Header controls in a narrow pane: everything folds into one menu.
    private var compactControls: some View {
        HStack(spacing: 4) {
            Menu {
                if !browser.isToolPage {
                    Picker("View", selection: $browser.viewMode) {
                        Label("as List", systemImage: "list.bullet").tag(ViewMode.list)
                        Label("as Icons", systemImage: "square.grid.2x2").tag(ViewMode.icons)
                        Label("as Columns", systemImage: "rectangle.split.3x1").tag(ViewMode.columns)
                    }
                    .pickerStyle(.inline)
                    Menu("Sort By") { SortMenuItems(browser: browser) }
                    Button("Filter…") { showFilter() }
                    Divider()
                }
                if let git = browser.git {
                    Menu("Git: \(git.status.headName)") { GitMenuItems(browser: browser, git: git) }
                    Divider()
                }
                Toggle("Info Panel", isOn: Binding(
                    get: { window.isInspectorShown },
                    set: { on in withAnimation(.snappy(duration: 0.25)) { window.isInspectorShown = on } }
                ))
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.textSubtle)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("View Options")
            if window.isSplit {
                IconButton(symbol: "xmark", help: "Close Pane") { window.closePane(pane) }
            }
        }
        .fixedSize()
    }

    /// Big rounded title with the path above it (each part clickable).
    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 3) {
                switch browser.mode {
                case .search: Text("Search")
                case .workspace: Text("Workspace")
                case .cleanup, .packages: Text("Tools")
                case .settings: Text("Scout")
                case .recents: Text("Last 30 days")
                case .tag: Text("Tag")
                case .changes: Text("Git")
                case .folder:
                    ForEach(Array(parentCrumbs.enumerated()), id: \.offset) { index, url in
                        if index > 0 {
                            Image(systemName: "chevron.compact.right").font(.system(size: 9, weight: .medium))
                        }
                        CrumbButton(title: Self.displayName(url)) { browser.go(to: url) }
                    }
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(Color.textSubtle)
            .lineLimit(1)
            .frame(height: 14)

            HStack(spacing: 7) {
                if let symbol = modeSymbol {
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 20)
                } else {
                    Image(nsImage: IconCache.icon(forPath: browser.location.filePath))
                        .resizable().frame(width: 20, height: 20)
                }
                Text(browser.title)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.textStrong)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    /// The title icon for non-folder pages.
    private var modeSymbol: String? {
        switch browser.mode {
        case .folder: nil
        case .search: "magnifyingglass"
        case .workspace: browser.workspace?.symbol ?? "square.stack.3d.up"
        case .cleanup: "sparkles"
        case .packages: "shippingbox"
        case .settings: "gearshape"
        case .recents: "clock"
        case .tag: "tag"
        case .changes: "arrow.triangle.branch"
        }
    }

    /// The folders above this one, nearest last (at most four).
    private var parentCrumbs: [URL] {
        var result: [URL] = []
        var url = browser.location
        while true {
            let parent = url.deletingLastPathComponent()
            if parent.filePath == url.filePath { break }
            result.insert(parent, at: 0)
            url = parent
        }
        return Array(result.suffix(4))
    }

    static func displayName(_ url: URL) -> String {
        url.filePath == "/" ? (AppServices.volumeName(url) ?? "/") : FileManager.default.displayName(atPath: url.filePath)
    }

    // MARK: - Bars under the header

    /// ⌘F: narrows the current folder as you type. Esc closes it.
    private var filterBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease").foregroundStyle(Color.accentColor)
            TextField("Filter \(browser.title)", text: $browser.filterText)
                .textFieldStyle(.plain)
                .focused($isFilterFocused)
                .onKeyPress(.escape) { hideFilter(); return .handled }
                .onKeyPress(.downArrow) { isFilterFocused = false; return .handled }
            if !browser.filterText.isEmpty {
                Text("\(browser.displayedItems.count) of \(browser.items.count)")
                    .foregroundStyle(Color.textSubtle)
                    .monospacedDigit()
            }
            Button(action: hideFilter) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(Color.textSubtle)
            }
            .buttonStyle(.plain)
            .help("Close Filter (Esc)")
        }
        .font(.system(size: 13))
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(RaisedFill(shape: RoundedRectangle(cornerRadius: 9)))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.accentColor.opacity(0.35)))
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private func showFilter() {
        isFilterShown = true
        isFilterFocused = true
    }

    private func hideFilter() {
        browser.filterText = ""
        isFilterShown = false
        isFilterFocused = false
    }

    private func searchHeader(_ search: SavedSearch) -> some View {
        HStack(spacing: 8) {
            Text(search.spec.summary).fontWeight(.medium).lineLimit(1)
            if browser.isSearching {
                ProgressView().controlSize(.small)
            } else {
                Text("\(browser.displayedItems.count) result\(browser.displayedItems.count == 1 ? "" : "s")")
                    .foregroundStyle(Color.textSubtle)
            }
            Spacer()
            if services.isSaved(search) {
                Label("Saved", systemImage: "checkmark").foregroundStyle(Color.textSubtle)
            } else {
                Button("Save Search…") {
                    searchName = search.name
                    isNamingSearch = true
                }
            }
            Button("Edit") {
                window.paletteInitialQuery = search.spec.query
                window.isPaletteOpen = true
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(RaisedFill(shape: RoundedRectangle(cornerRadius: 9)))
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    /// Above the Changes list: what's there, and the repository's actions.
    private var changesHeader: some View {
        HStack(spacing: 8) {
            if let status = browser.git?.status {
                let deleted = status.changes.values.filter { $0 == .deleted }.count
                Text(status.changeCount == 0 ? "Nothing changed on \(status.headName)"
                     : "\(status.changeCount) change\(status.changeCount == 1 ? "" : "s") on \(status.headName)")
                    .fontWeight(.medium)
                if deleted > 0 {
                    Text("· \(deleted) deleted (not shown)").foregroundStyle(Color.textSubtle)
                }
            } else {
                ProgressView().controlSize(.small)
            }
            Spacer()
            Button("Refresh") { browser.refreshGit() }
            if let root = browser.changesRoot {
                Button("Open Repository") { browser.go(to: .folder(root)) }
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(RaisedFill(shape: RoundedRectangle(cornerRadius: 9)))
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private func workspaceHeader(_ workspace: Workspace) -> some View {
        HStack(spacing: 8) {
            Text("\(workspace.paths.count) item\(workspace.paths.count == 1 ? "" : "s") from anywhere")
                .foregroundStyle(Color.textSubtle)
            Spacer()
            Button("Open All in Tabs") {
                for item in browser.items where item.isNavigable { pane.newTab(at: item.url) }
            }
            .disabled(!browser.items.contains(where: \.isNavigable))
            Menu {
                Button("Rename…") {
                    workspaceName = workspace.name
                    isRenamingWorkspace = true
                }
                Menu("Icon") {
                    ForEach(Workspace.symbols, id: \.self) { symbol in
                        Button { services.updateWorkspace(workspace.id) { $0.symbol = symbol } } label: {
                            Label(symbol, systemImage: symbol)
                        }
                    }
                }
                Divider()
                Button("Delete Workspace", role: .destructive) {
                    services.deleteWorkspace(workspace.id)
                    browser.goBack()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .font(.system(size: 13))
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(RaisedFill(shape: RoundedRectangle(cornerRadius: 9)))
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    // MARK: - Content and footer

    @ViewBuilder private var content: some View {
        if browser.mode == .cleanup {
            CleanupView(browser: browser)
        } else if browser.mode == .packages {
            PackagesView(browser: browser)
        } else if browser.mode == .settings {
            SettingsView(window: window, browser: browser)
        } else if let error = browser.loadError {
            ContentUnavailableView {
                Label("Can’t Open This Folder", systemImage: "lock.fill")
            } description: {
                Text(error)
            } actions: {
                if browser.needsPermission {
                    Button("Open Full Disk Access Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                    }
                }
            }
        } else {
            Group {
                switch browser.viewMode {
                case .list: FileTableView(window: window, browser: browser)
                case .icons: FileGridView(window: window, browser: browser)
                case .columns:
                    // Searches and workspaces aren't one folder, so they show as a list.
                    if browser.isFolder { ColumnBrowserView(window: window, browser: browser) }
                    else { FileTableView(window: window, browser: browser) }
                }
            }
            .overlay {
                if browser.displayedItems.isEmpty, !browser.isLoading, !browser.isSearching {
                    emptyState.allowsHitTesting(false)
                }
            }
            // Drop files here (from another pane, Finder, anywhere) to move or copy them in.
            .dropDestination(for: URL.self) { urls, _ in browser.receiveDrop(urls) }
        }
    }

    private var emptyState: some View {
        let title: String
        let symbol: String
        var message = ""
        if !browser.filterText.isEmpty {
            title = "No Matches"
            symbol = "line.3.horizontal.decrease"
            message = "Nothing here matches “\(browser.filterText)”."
        } else {
            switch browser.mode {
            case .search:
                title = "No Results"
                symbol = "magnifyingglass"
            case .workspace:
                title = "Empty Workspace"
                symbol = browser.workspace?.symbol ?? "square.stack.3d.up"
                message = "Right-click any file or folder and choose Add to Workspace."
            default:
                title = "Empty Folder"
                symbol = "folder"
            }
        }
        return ContentUnavailableView(title, systemImage: symbol, description: Text(message))
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Text(summary)
            Spacer()
            if let activity = browser.activity {
                ProgressView().controlSize(.mini)
                Text(activity)
            } else if browser.isLoading {
                ProgressView().controlSize(.mini)
            }
            if browser.viewMode == .icons, !browser.isToolPage {
                IconSizeSlider()
            }
            if let free = browser.freeSpace, browser.isFolder {
                Text("\(Format.bytes(free)) free")
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(Color.textSubtle)
        .monospacedDigit()
        .padding(.horizontal, 14)
        .frame(height: 26)
        .overlay(alignment: .top) { Rectangle().fill(Color.hairline).frame(height: 1) }
    }

    private var summary: String {
        let count = browser.displayedItems.count
        let noun = browser.search == nil ? "item" : "result"
        if !browser.selection.isEmpty { return "\(browser.selection.count) of \(count) selected" }
        return "\(count) \(noun)\(count == 1 ? "" : "s")"
    }

    private var renameBinding: Binding<Bool> {
        Binding(get: { browser.renaming != nil }, set: { if !$0 { browser.renaming = nil } })
    }

    private struct Batch: Identifiable {
        let items: [FileItem]
        var id: [URL] { items.map(\.id) }
    }

    private var newTagBinding: Binding<Bool> {
        Binding(get: { browser.newTagItems != nil }, set: { if !$0 { browser.newTagItems = nil } })
    }

    private struct TidyPlan: Identifiable {
        let moves: [Tidy.Move]
        var id: Int { moves.count }
    }

    private var tidyBinding: Binding<TidyPlan?> {
        Binding(get: { browser.tidyPlan.map(TidyPlan.init) }, set: { if $0 == nil { browser.tidyPlan = nil } })
    }

    private var batchRenameBinding: Binding<Batch?> {
        Binding(get: { browser.batchRenaming.map(Batch.init) }, set: { if $0 == nil { browser.batchRenaming = nil } })
    }

    private var alertBinding: Binding<Bool> {
        Binding(get: { browser.alertMessage != nil }, set: { if !$0 { browser.alertMessage = nil } })
    }
}

private struct CrumbButton: View {
    let title: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .foregroundStyle(isHovering ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
                .underline(isHovering)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

/// Sort options (replaces column headers).
/// Footer slider for icon size (⌘+ / ⌘− too).
private struct IconSizeSlider: View {
    @AppStorage("iconSize") private var iconSize = 64.0

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "square.grid.3x3").font(.system(size: 9, weight: .medium))
            Slider(value: $iconSize, in: 32...160, step: 8).frame(width: 90).controlSize(.mini)
            Image(systemName: "square.grid.2x2").font(.system(size: 11, weight: .regular))
        }
        .padding(.trailing, 8)
        .help("Icon size (⌘+ / ⌘−)")
    }
}

private struct SortMenu: View {
    @Bindable var browser: BrowserModel

    var body: some View {
        Menu {
            SortMenuItems(browser: browser)
        } label: {
            Image(systemName: browser.groupBy == .none ? "arrow.up.arrow.down" : "square.split.1x2")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(browser.groupBy == .none ? Color.secondary : Color.accentColor)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(browser.groupBy == .none ? "Sort" : "Sort and Group (grouped by \(browser.groupBy.title))")
    }
}

private struct SortMenuItems: View {
    @Bindable var browser: BrowserModel

    var body: some View {
            Picker("Sort By", selection: Binding(
                get: { browser.sortField ?? .name },
                set: { browser.sort(by: $0, ascending: $0.defaultAscending) }
            )) {
                ForEach(SortField.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
            Divider()
            Toggle("Ascending", isOn: Binding(
                get: { browser.sortAscending },
                set: { browser.sort(by: browser.sortField ?? .name, ascending: $0) }
            ))
            Toggle("Folders on Top", isOn: $browser.foldersFirst)
                .disabled(browser.groupBy != .none)
            if !browser.showsLocations {
                Divider()
                Picker("Group By", selection: $browser.groupBy) {
                    ForEach(GroupBy.folderChoices) { Text($0.title).tag($0) }
                }
            }
    }
}
