import AppKit
import Observation
import ScoutCore

enum ViewMode: String, CaseIterable, Identifiable {
    case list, icons, columns
    var id: Self { self }
}

enum SortField: String, CaseIterable, Identifiable {
    case name, kind, modified, added, created, size
    var id: Self { self }

    var title: String {
        switch self {
        case .name: "Name"
        case .modified: "Date Modified"
        case .added: "Date Added"
        case .created: "Date Created"
        case .size: "Size"
        case .kind: "Kind"
        }
    }

    /// Which date the list's date column shows.
    var isDate: Bool { self == .modified || self == .added || self == .created }

    /// Dates and sizes start newest/biggest first.
    var defaultAscending: Bool { self == .name || self == .kind }
}

/// What a tab is showing.
enum BrowserMode: Equatable, Codable {
    /// A folder's contents (the usual case).
    case folder
    /// Live Spotlight results.
    case search(SavedSearch)
    /// A workspace: folders and files gathered from anywhere.
    case workspace(UUID)
    /// The Clean Up page.
    case cleanup
    /// Every changed file in a git repository (the repository's root path).
    case changes(String)
    /// Installed Homebrew and npm packages.
    case packages
    /// Scout's settings.
    case settings
    /// Files you opened or downloaded lately, from anywhere.
    case recents
    /// Everything with a Finder tag.
    case tag(String)
}

/// A stop in a tab's Back/Forward history.
struct HistoryEntry {
    var location: URL
    var mode: BrowserMode = .folder
}

private let defaultSortOrder = [KeyPathComparator(\FileItem.name, comparator: String.StandardComparator.localizedStandard)]

/// One tab: a folder (or search results, a workspace, Clean Up) you're looking at,
/// plus its history, selection and view settings.
@Observable
final class BrowserModel: Identifiable {
    let id = UUID()

    private(set) var location: URL
    private(set) var items: [FileItem] = [] { didSet { refreshDisplayed() } }
    /// `items` after filtering and sorting: what the views show.
    private(set) var displayedItems: [FileItem] = []

    /// Empty = keep the incoming order (search results arrive best-first).
    var sortOrder = defaultSortOrder {
        didSet {
            refreshDisplayed()
            rememberFolderView() // header clicks too
        }
    }
    var filterText = "" { didSet { refreshDisplayed() } }
    /// New tabs start from Settings' choices; the View menu changes one tab.
    var foldersFirst = UserDefaults.standard.object(forKey: "foldersFirst") as? Bool ?? true { didSet { refreshDisplayed() } }
    /// Finder-style groups (Kind, Date Added…). Remembered per folder, like the sort.
    var groupBy: GroupBy = .none {
        didSet {
            refreshDisplayed()
            rememberFolderView()
        }
    }
    /// `displayedItems` split into labeled groups (one untitled group when not grouping).
    private(set) var displayedGroups: [ItemGroup] = []
    /// Folders opened in place in the list (disclosure arrows), and what's inside them.
    private(set) var expanded: Set<URL> = []
    @ObservationIgnored private var childItems: [URL: [FileItem]] = [:]
    /// How deep each shown item is (0 = in this folder), for indenting.
    private(set) var depth: [URL: Int] = [:]
    var showHidden = UserDefaults.standard.bool(forKey: "showHidden") { didSet { Task { await load(recordVisit: false) } } }
    /// Remembered across tabs and launches, like Finder.
    var viewMode: ViewMode = ViewMode(rawValue: UserDefaults.standard.string(forKey: "viewMode") ?? "") ?? .list {
        didSet { UserDefaults.standard.set(viewMode.rawValue, forKey: "viewMode") }
    }

    var selection = Set<URL>() {
        didSet {
            if previewURL != nil { previewURL = selectedItems.first?.url }
            // Selecting something in a pane makes it the active pane.
            if !selection.isEmpty, let pane { pane.window?.focus(pane) }
        }
    }
    /// The file shown in Quick Look, if it's open.
    var previewURL: URL?
    /// An item the list or grid should scroll to (after type-select, reveal, arrow keys).
    var scrollTarget: URL?
    /// The item being renamed (drives the rename dialog).
    var renaming: FileItem?
    /// Items being renamed together (drives the Rename Items sheet).
    var batchRenaming: [FileItem]?
    /// Tidy Folder's plan, waiting for you to confirm (drives the Tidy sheet).
    var tidyPlan: [Tidy.Move]?
    /// Something slow in progress ("Compressing…"), shown in the footer.
    private(set) var activity: String?
    var alertMessage: String?

    private(set) var loadError: String?
    private(set) var needsPermission = false
    private(set) var isLoading = false
    private(set) var freeSpace: Int64?
    private(set) var backStack: [HistoryEntry] = []
    private(set) var forwardStack: [HistoryEntry] = []

    /// What this tab shows. For anything but `.folder`, `location` stays on the last
    /// folder (used for "this folder" searches and for going back up).
    private(set) var mode: BrowserMode = .folder
    private(set) var isSearching = false
    /// Git status when this folder is inside a repository.
    private(set) var git: GitRunner.Snapshot?
    /// A repository whose settings could run programs, so git waits until you trust it.
    private(set) var untrustedRepo: String?

    var search: SavedSearch? {
        if case .search(let saved) = mode { return saved }
        return nil
    }

    var workspaceID: UUID? {
        if case .workspace(let id) = mode { return id }
        return nil
    }

    var workspace: Workspace? { workspaceID.flatMap(services.workspace(_:)) }

    /// Showing a real folder's contents (so New Folder, Paste, drops etc. apply).
    var isFolder: Bool { mode == .folder }

    /// The git repository whose changes this tab lists.
    var changesRoot: String? {
        if case .changes(let root) = mode { return root }
        return nil
    }

    /// Clean Up and Packages: pages with their own layout instead of a file list.
    var isToolPage: Bool { mode == .cleanup || mode == .packages || mode == .settings }

    /// Items come from many folders, so views show where each one lives.
    var showsLocations: Bool {
        search != nil || workspaceID != nil || changesRoot != nil || mode == .recents || tagName != nil
    }

    var tagName: String? {
        if case .tag(let name) = mode { return name }
        return nil
    }

    @ObservationIgnored let services: AppServices
    /// The pane (column) this tab lives in.
    @ObservationIgnored weak var pane: PaneModel?
    @ObservationIgnored weak var undoManager: UndoManager?
    @ObservationIgnored private var watcher: DirectoryWatcher?
    @ObservationIgnored private var reloadTask: Task<Void, Never>?
    @ObservationIgnored private var loadGeneration = 0
    /// Select this once the folder loads (e.g. the folder you just came up from).
    @ObservationIgnored private var pendingSelection: String?
    @ObservationIgnored private var spotlight: SpotlightSearch?
    @ObservationIgnored private var spotlightAdded: SpotlightSearch?
    /// The folder sort order, kept while a search is showing.
    @ObservationIgnored private var folderSortOrder = defaultSortOrder
    @ObservationIgnored private var gitTask: Task<Void, Never>?

    init(location: URL, services: AppServices) {
        self.location = .folder(location.filePath)
        self.services = services
        applyFolderView()
        Task { await load(recordVisit: true) }
    }

    var title: String {
        switch mode {
        case .search(let saved): return saved.name
        case .workspace: return workspace?.name ?? "Workspace"
        case .cleanup: return "Clean Up"
        case .packages: return "Packages"
        case .settings: return "Settings"
        case .recents: return "Recents"
        case .tag(let name): return name
        case .changes(let root): return "Changes in " + FileManager.default.displayName(atPath: root)
        case .folder: break
        }
        return location.filePath == "/" ? (AppServices.volumeName(location) ?? "/")
            : FileManager.default.displayName(atPath: location.filePath)
    }

    private var here: HistoryEntry { HistoryEntry(location: location, mode: mode) }

    var selectedItems: [FileItem] { displayedItems.filter { selection.contains($0.id) } }

    // MARK: - Sorting

    var sortField: SortField? {
        guard let keyPath = sortOrder.first?.keyPath else { return nil }
        switch keyPath {
        case \FileItem.name: return .name
        case \FileItem.modifiedSortKey: return .modified
        case \FileItem.sizeSortKey: return .size
        case \FileItem.kind: return .kind
        case \FileItem.addedSortKey: return .added
        case \FileItem.createdSortKey: return .created
        default: return nil
        }
    }

    var sortAscending: Bool { sortOrder.first?.order != .reverse }

    func sort(by field: SortField, ascending: Bool) {
        var comparator: KeyPathComparator<FileItem>
        switch field {
        case .name: comparator = KeyPathComparator(\FileItem.name, comparator: String.StandardComparator.localizedStandard)
        case .modified: comparator = KeyPathComparator(\FileItem.modifiedSortKey)
        case .size: comparator = KeyPathComparator(\FileItem.sizeSortKey)
        case .kind: comparator = KeyPathComparator(\FileItem.kind, comparator: String.StandardComparator.localizedStandard)
        case .added: comparator = KeyPathComparator(\FileItem.addedSortKey)
        case .created: comparator = KeyPathComparator(\FileItem.createdSortKey)
        }
        comparator.order = ascending ? .forward : .reverse
        sortOrder = [comparator]
        rememberFolderView()
    }

    /// The date the list shows: the one you're grouping or sorting by, else Date Modified.
    var shownDate: SortField {
        switch groupBy {
        case .dateAdded: return .added
        case .dateCreated: return .created
        case .dateModified: return .modified
        default: return sortField?.isDate == true ? sortField! : .modified
        }
    }

    func date(of item: FileItem) -> Date? {
        if groupBy == .dateOpened { return item.lastOpened }
        switch shownDate {
        case .added: return item.dateAdded
        case .created: return item.dateCreated
        default: return item.dateModified
        }
    }

    // MARK: - Per-folder view settings (like Finder)

    @ObservationIgnored private var isApplyingFolderView = false

    /// Saved as "field|ascending|groupBy" per folder path.
    private static let folderViewsKey = "folderViews"

    /// Restores this folder's sort and grouping (Downloads starts newest-added first, grouped by day).
    private func applyFolderView() {
        guard mode == .folder else { return }
        let saved = (UserDefaults.standard.dictionary(forKey: Self.folderViewsKey) as? [String: String])?[location.filePath]
        var field = SortField.name, ascending = true, group = GroupBy.none
        if let saved {
            let parts = saved.split(separator: "|").map(String.init)
            if parts.count == 3 {
                field = SortField(rawValue: parts[0]) ?? .name
                ascending = parts[1] == "1"
                group = GroupBy(rawValue: parts[2]) ?? .none
            }
        } else if location.filePath == services.homePath + "/Downloads" {
            field = .added
            ascending = false
            group = .dateAdded
        }
        isApplyingFolderView = true
        sort(by: field, ascending: ascending)
        groupBy = group
        isApplyingFolderView = false
    }

    private func rememberFolderView() {
        guard !isApplyingFolderView, mode == .folder else { return }
        var views = UserDefaults.standard.dictionary(forKey: Self.folderViewsKey) as? [String: String] ?? [:]
        views[location.filePath] = "\(sortField?.rawValue ?? "name")|\(sortAscending ? 1 : 0)|\(groupBy.rawValue)"
        UserDefaults.standard.set(views, forKey: Self.folderViewsKey)
    }

    // MARK: - Navigation

    func go(to url: URL, select child: URL? = nil) {
        let target = URL.folder(url.filePath)
        guard !isFolder || target.filePath != location.filePath else {
            // Already here: select now, or once the folder finishes loading.
            if let child, !selectPath(child.filePath) { pendingSelection = child.filePath }
            return
        }
        pushHistory()
        show(HistoryEntry(location: target), select: child)
    }

    /// Puts a reopened tab back on what it was showing (search, workspace, Clean Up…).
    func restore(_ mode: BrowserMode) {
        switch mode {
        case .folder: break
        case .search(let saved): showSearch(saved)
        case .workspace(let id): if services.workspace(id) != nil { showWorkspace(id) }
        case .cleanup: showCleanup()
        case .changes(let root): if FileManager.default.fileExists(atPath: root) { showChanges(in: root) }
        case .packages: showPackages()
        case .settings: showSettings()
        case .recents: showRecents()
        case .tag(let name): showTag(name)
        }
    }

    /// Shows live Spotlight results in this tab.
    func showSearch(_ saved: SavedSearch) {
        pushHistory()
        show(HistoryEntry(location: location, mode: .search(saved)))
    }

    func showWorkspace(_ id: UUID) {
        guard workspaceID != id else { return }
        pushHistory()
        show(HistoryEntry(location: location, mode: .workspace(id)))
    }

    func showCleanup() {
        guard mode != .cleanup else { return }
        pushHistory()
        show(HistoryEntry(location: location, mode: .cleanup))
    }

    func showTag(_ name: String) {
        guard tagName != name else { return }
        pushHistory()
        show(HistoryEntry(location: location, mode: .tag(name)))
    }

    func showRecents() {
        guard mode != .recents else { return }
        pushHistory()
        show(HistoryEntry(location: location, mode: .recents))
    }

    func showSettings() {
        guard mode != .settings else { return }
        pushHistory()
        show(HistoryEntry(location: location, mode: .settings))
    }

    func showPackages() {
        guard mode != .packages else { return }
        pushHistory()
        show(HistoryEntry(location: location, mode: .packages))
    }

    /// Every changed file in the repository containing `path` (default: this folder).
    func showChanges(in path: String? = nil) {
        guard let root = Git.repositoryRoot(containing: path ?? location.filePath) else {
            alertMessage = "“\(PathDisplay.display(path ?? location.filePath, home: services.homePath))” isn’t in a git repository."
            return
        }
        guard changesRoot != root else { return }
        pushHistory()
        show(HistoryEntry(location: isFolder ? location : .folder(root), mode: .changes(root)))
    }

    func goBack() {
        guard let previous = backStack.popLast() else { return }
        let current = here
        forwardStack.append(current)
        show(previous, select: current.mode == .folder ? current.location : nil, record: false)
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(here)
        show(next, record: false)
    }

    func goUp() {
        if !isFolder {
            go(to: location)
            return
        }
        let parent = location.deletingLastPathComponent()
        guard parent.filePath != location.filePath else { return }
        go(to: parent, select: location)
    }

    /// Shows a folder, or a file selected inside its folder ("Reveal").
    func reveal(_ url: URL) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.filePath, isDirectory: &isDir) else {
            alertMessage = "“\(url.filePath)” doesn’t exist."
            return
        }
        if isDir.boolValue, !NSWorkspace.shared.isFilePackage(atPath: url.filePath) {
            go(to: url)
        } else {
            go(to: url.deletingLastPathComponent(), select: url)
        }
    }

    private func pushHistory() {
        backStack.append(here)
        forwardStack.removeAll()
    }

    private func show(_ entry: HistoryEntry, select child: URL? = nil, record: Bool = true) {
        let wasOrdered = showsLocations
        location = .folder(entry.location.filePath)
        mode = entry.mode
        // Searches keep relevance order and workspaces keep your order; folders get their sort back.
        if wasOrdered != showsLocations {
            if showsLocations {
                folderSortOrder = sortOrder
                sortOrder = []
            } else {
                sortOrder = folderSortOrder.isEmpty ? defaultSortOrder : folderSortOrder
            }
        }
        selection = []
        filterText = ""
        previewURL = nil
        expanded = []
        childItems = [:]
        pendingSelection = child?.filePath
        // Folders get their own remembered view; searches and workspaces keep their own order.
        if mode == .folder { applyFolderView() } else { groupBy = mode == .recents ? .dateOpened : .none }
        Task { await load(recordVisit: record) }
    }

    // MARK: - Loading

    func load(recordVisit: Bool) async {
        loadGeneration += 1
        let generation = loadGeneration
        if !isFolder { refreshGit() } // clears it
        switch mode {
        case .search(let saved):
            startSearch(saved, generation: generation)
            return
        case .workspace:
            loadWorkspace()
            return
        case .cleanup, .packages, .settings:
            spotlight = nil
            spotlightAdded = nil
            watcher = nil
            items = []
            return
        case .recents:
            startRecents(generation: generation)
            return
        case .tag(let name):
            startTagSearch(name, generation: generation)
            return
        case .changes:
            spotlight = nil
            spotlightAdded = nil
            watcher = nil
            isSearching = false
            loadError = nil
            needsPermission = false
            if git?.status.root == changesRoot { items = changedItems() }
            return // refreshGit (above) fills in the rest
        case .folder:
            break
        }
        spotlight = nil
        spotlightAdded = nil
        isSearching = false
        let target = location
        isLoading = true
        defer { if generation == loadGeneration { isLoading = false } }

        do {
            var result = try await services.fileSource.contents(of: target, includeHidden: showHidden)
            guard generation == loadGeneration else { return }
            // Sort big folders off the main thread. The list then arrives in order, and
            // re-sorting a list that's already in order is nearly free.
            if result.count > 500, !sortOrder.isEmpty {
                let order = sortOrder
                let unsorted = result
                result = await Task.detached(priority: .userInitiated) { unsorted.sorted(using: order) }.value
                guard generation == loadGeneration else { return }
            }
            // Keep sizes already measured (auto-reloads happen on every change in the folder).
            let measured = Dictionary(items.compactMap { item in item.folderBytes.map { (item.url, $0) } },
                                      uniquingKeysWith: { a, _ in a })
            items = measured.isEmpty ? result : result.map { item in
                var item = item
                item.folderBytes = measured[item.url]
                return item
            }
            loadError = nil
            needsPermission = false
            freeSpace = try? target.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
                .volumeAvailableCapacityForImportantUsage
            if recordVisit { services.recordVisit(target) }
            refreshGit()
            measureFolderSizes(generation: generation)
            refreshExpanded()
            // Drop selections that no longer exist.
            let present = Set(result.map(\.id))
            if !selection.isSubset(of: present) { selection = selection.intersection(present) }
            if let pending = pendingSelection {
                pendingSelection = nil
                selectPath(pending)
            }
            watch(target)
        } catch {
            guard generation == loadGeneration else { return }
            items = []
            let ns = error as NSError
            needsPermission = ns.domain == NSCocoaErrorDomain && ns.code == NSFileReadNoPermissionError
            loadError = needsPermission
                ? "Scout doesn’t have permission to see this folder. Give it Full Disk Access to open everything."
                : error.localizedDescription
        }
    }

    func reload() async { await load(recordVisit: false) }

    /// Fills in folder sizes one at a time (shared cache with the info panel), so the
    /// Size column shows them and sorting by size works. Settings can turn this off.
    private func measureFolderSizes(generation: Int) {
        guard UserDefaults.standard.object(forKey: "folderSizes") as? Bool ?? true else { return }
        let folders = items.filter { $0.isNavigable && !$0.isSymlink && $0.folderBytes == nil }.map(\.url)
        guard !folders.isEmpty else { return }
        Task {
            // Apply sizes in batches: each change to `items` re-sorts the whole list, which
            // adds up in folders with thousands of subfolders.
            var measured: [URL: Int64] = [:]
            var lastFlush = ContinuousClock.now
            for url in folders {
                guard generation == loadGeneration else { return }
                measured[url] = await services.folderSize(url).bytes
                if ContinuousClock.now - lastFlush > .milliseconds(folders.count > 200 ? 600 : 150) {
                    applyFolderSizes(measured, generation: generation)
                    measured.removeAll()
                    lastFlush = .now
                }
            }
            applyFolderSizes(measured, generation: generation)
        }
    }

    private func applyFolderSizes(_ measured: [URL: Int64], generation: Int) {
        guard !measured.isEmpty, generation == loadGeneration else { return }
        var updated = items
        for index in updated.indices {
            if let bytes = measured[updated[index].url] { updated[index].folderBytes = bytes }
        }
        items = updated
    }

    /// A workspace's items, in the order you added them. Missing ones are skipped.
    private func loadWorkspace() {
        spotlight = nil
        spotlightAdded = nil
        watcher = nil
        isSearching = false
        loadError = nil
        needsPermission = false
        items = (workspace?.paths ?? []).compactMap { LocalFileSource.item(for: URL(filePath: $0)) }
    }

    /// Recents: opened in the last 30 days anywhere in your home, plus new arrivals in
    /// Downloads, Desktop and Documents. Newest first, grouped by day.
    private func startRecents(generation: Int) {
        watcher = nil
        loadError = nil
        needsPermission = false
        isSearching = true
        let home = services.homePath
        var opened: [FileHit] = []
        var added: [FileHit] = []
        var openedDone = false
        var addedDone = false
        let update: () -> Void = { [weak self] in
            guard let self, generation == self.loadGeneration else { return }
            var latest: [String: (FileHit, Date)] = [:]
            for hit in opened where !FileHitRanker.isNoise(hit.path, home: home) {
                if let used = hit.lastUsed { latest[hit.path] = (hit, used) }
            }
            var items: [FileItem] = []
            var seen = Set<String>()
            for hit in added where !FileHitRanker.isNoise(hit.path, home: home) {
                guard latest[hit.path] == nil, let item = LocalFileSource.item(for: URL(filePath: hit.path)),
                      let date = item.dateAdded else { continue }
                var dated = item
                dated.lastOpened = date
                items.append(dated)
                seen.insert(hit.path)
            }
            for (path, entry) in latest where !seen.contains(path) {
                guard var item = LocalFileSource.item(for: URL(filePath: path)) else { continue }
                item.lastOpened = max(entry.1, item.dateAdded ?? .distantPast)
                items.append(item)
            }
            self.items = Array(items.sorted { ($0.lastOpened ?? .distantPast) > ($1.lastOpened ?? .distantPast) }.prefix(400))
            if openedDone && addedDone { self.isSearching = false }
        }
        let notFolders = "kMDItemContentType != \"public.folder\""
        spotlight = SpotlightSearch(queryString: "kMDItemLastUsedDate >= $time.today(-30) && \(notFolders)",
                                    scopes: [NSMetadataQueryUserHomeScope], live: true) { hits, done in
            opened = hits
            if done { openedDone = true }
            update()
        }
        let arrivals = ["Downloads", "Desktop", "Documents"].map { URL.folder(home + "/" + $0) }
        spotlightAdded = SpotlightSearch(queryString: "kMDItemDateAdded >= $time.today(-30) && \(notFolders)",
                                         scopes: arrivals, live: true) { hits, done in
            added = hits
            if done { addedDone = true }
            update()
        }
    }

    /// Everything in your home with a Finder tag, from Spotlight.
    private func startTagSearch(_ name: String, generation: Int) {
        spotlightAdded = nil
        watcher = nil
        loadError = nil
        needsPermission = false
        isSearching = true
        let home = services.homePath
        let escaped = SpotlightQueryBuilder.escape(name)
        spotlight = SpotlightSearch(queryString: "kMDItemUserTags == \"\(escaped)\"",
                                    scopes: [NSMetadataQueryUserHomeScope], live: true) { [weak self] hits, finished in
            guard let self, generation == self.loadGeneration else { return }
            self.items = hits.filter { !FileHitRanker.isNoise($0.path, home: home) }
                .compactMap { LocalFileSource.item(for: URL(filePath: $0.path)) }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            if finished { self.isSearching = false }
        }
        if spotlight == nil {
            items = []
            isSearching = false
        }
    }

    // MARK: - Tags

    /// The item getting a nickname (drives the Nickname dialog).
    var nicknaming: FileItem?

    /// Items waiting for a name in the New Tag dialog.
    var newTagItems: [FileItem]?

    func toggleTag(_ tag: FileTag, on items: [FileItem]) {
        do {
            try Tags.toggle(tag, on: items.map(\.url))
        } catch {
            alertMessage = "Couldn’t change tags: \(error.localizedDescription)"
        }
        services.noteTags([tag])
        Task { await reload() }
    }

    func removeTags(from items: [FileItem]) {
        for item in items { try? Tags.write([], to: item.url) }
        Task { await reload() }
    }

    private func startSearch(_ saved: SavedSearch, generation: Int) {
        spotlightAdded = nil
        watcher = nil
        loadError = nil
        needsPermission = false
        isSearching = true
        let home = services.homePath
        let query = saved.spec.query
        spotlight = SpotlightSearch(spec: saved.spec, home: home, live: true) { [weak self] hits, finished in
            guard let self, generation == self.loadGeneration else { return }
            let ranked = FileHitRanker.rank(hits, query: query, home: home, limit: 500)
            self.items = ranked.compactMap { LocalFileSource.item(for: URL(filePath: $0.hit.path)) }
            if finished { self.isSearching = false }
        }
        if spotlight == nil {
            items = []
            isSearching = false
        }
    }

    @discardableResult
    private func selectPath(_ path: String) -> Bool {
        guard let item = items.first(where: { $0.path == path }) else { return false }
        selection = [item.id]
        scrollTarget = item.id
        return true
    }

    // MARK: - Keyboard selection

    @ObservationIgnored private var typedPrefix = ""
    @ObservationIgnored private var lastTyped = Date.distantPast

    /// Typing in the middle of a type-select (so Space adds a space instead of Quick Look).
    var isTypeSelecting: Bool { Date.now.timeIntervalSince(lastTyped) < 1 }

    /// Finder-style type-select: typing "rep" quickly selects the first item starting with "rep".
    func typeSelect(_ characters: String) {
        typedPrefix = isTypeSelecting ? typedPrefix + characters : characters
        lastTyped = .now
        let typed = typedPrefix
        let match = displayedItems.first {
            $0.name.range(of: typed, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil
        } ?? displayedItems.first { $0.name.localizedStandardContains(typed) }
        guard let match else { return }
        select(match)
    }

    /// Selects one item and scrolls to it.
    func select(_ item: FileItem) {
        selection = [item.id]
        scrollTarget = item.id
    }

    private func watch(_ folder: URL) {
        guard watcher?.url.filePath != folder.filePath else { return }
        watcher = DirectoryWatcher(url: folder) { [weak self] in self?.scheduleReload() }
    }

    /// Changes made outside Scout show up within a moment.
    private func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            await reload()
        }
    }

    private func refreshDisplayed() {
        var list = items
        let query = filterText.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty { list = list.filter { $0.name.localizedCaseInsensitiveContains(query) } }
        if !sortOrder.isEmpty { list.sort(using: sortOrder) }
        let tagsSeen = list.flatMap(\.tags)
        if !tagsSeen.isEmpty { services.noteTags(tagsSeen) }
        var depths: [URL: Int] = [:]
        if groupBy != .none {
            displayedGroups = ItemGrouper.groups(list, by: groupBy).map {
                ItemGroup(title: $0.title, items: withChildren($0.items, depth: 0, into: &depths))
            }
            displayedItems = displayedGroups.flatMap(\.items)
            depth = depths
            return
        }
        list = arrange(list)
        if isFolder { list = services.customizations.pinnedFirst(list, in: location.filePath) }
        list = withChildren(list, depth: 0, into: &depths)
        displayedItems = list
        displayedGroups = [ItemGroup(title: "", items: list)]
        depth = depths
    }

    /// Re-sorts after pins or nicknames change.
    func refresh() { refreshDisplayed() }

    /// Folders first (when on), as in the folder itself.
    private func arrange(_ list: [FileItem]) -> [FileItem] {
        guard foldersFirst, isFolder else { return list }
        return list.filter(\.isNavigable) + list.filter { !$0.isNavigable }
    }

    /// Inserts the contents of expanded folders after them, sorted the same way.
    private func withChildren(_ list: [FileItem], depth level: Int, into depths: inout [URL: Int]) -> [FileItem] {
        guard !expanded.isEmpty else { return list }
        var result: [FileItem] = []
        for item in list {
            result.append(item)
            if level > 0 { depths[item.id] = level }
            if expanded.contains(item.id), var children = childItems[item.id] {
                if !sortOrder.isEmpty { children.sort(using: sortOrder) }
                result += withChildren(arrange(children), depth: level + 1, into: &depths)
            }
        }
        return result
    }

    // MARK: - Expanding folders in place

    /// Opens or closes a folder in place. `recursive` (⌥-click) does every folder inside too.
    func toggleExpanded(_ item: FileItem, recursive: Bool = false) {
        guard item.isNavigable else { return }
        if expanded.contains(item.id) {
            expanded = expanded.filter { !($0 == item.id || $0.filePath.hasPrefix(item.path + "/")) }
            refreshDisplayed()
        } else {
            expand([item.url], recursive: recursive)
        }
    }

    private func expand(_ folders: [URL], recursive: Bool, level: Int = 0) {
        let includeHidden = showHidden
        let source = services.fileSource
        Task {
            var next: [URL] = []
            for folder in folders {
                let children = (try? await source.contents(of: folder, includeHidden: includeHidden)) ?? []
                childItems[folder] = children
                expanded.insert(folder)
                if recursive { next += children.filter(\.isNavigable).map(\.url) }
            }
            refreshDisplayed()
            // ⌥-click: a few levels deep at most, so huge trees don't run away.
            if recursive, !next.isEmpty, level < 3 { expand(next, recursive: true, level: level + 1) }
        }
    }

    /// Re-reads expanded folders after a reload, and closes them when you leave.
    private func refreshExpanded() {
        guard !expanded.isEmpty else { return }
        let folders = Array(expanded)
        let includeHidden = showHidden
        let source = services.fileSource
        Task {
            for folder in folders {
                if let children = try? await source.contents(of: folder, includeHidden: includeHidden) {
                    childItems[folder] = children
                } else {
                    expanded.remove(folder)
                }
            }
            refreshDisplayed()
        }
    }

    // MARK: - Opening

    func open(_ urls: Set<URL>) {
        let chosen = displayedItems.filter { urls.contains($0.id) }
        let folders = chosen.filter(\.isNavigable)
        let files = chosen.filter { !$0.isNavigable }
        if folders.count == 1, files.isEmpty {
            go(to: folders[0].url)
            return
        }
        for folder in folders { pane?.newTab(at: folder.url) }
        for file in files { NSWorkspace.shared.open(file.url) }
    }

    func openSelection() { open(selection) }

    func toggleQuickLook() {
        previewURL = previewURL == nil ? selectedItems.first?.url : nil
    }

    // MARK: - Changing files

    /// Return / Rename…: one item gets the quick dialog, several get Rename Items.
    func beginRename() -> Bool {
        let items = selectedItems
        if items.count == 1 {
            renaming = items[0]
        } else if items.count > 1 {
            batchRenaming = items
        } else {
            return false
        }
        return true
    }

    /// Renames many items at once (⌘Z undoes all of them). Goes through temporary names
    /// first so swaps like a→b, b→a work.
    func applyBatchRename(_ changes: [(item: FileItem, newName: String)]) {
        let changes = changes.filter { $0.item.name != $0.newName }
        guard !changes.isEmpty else { return }
        let fm = FileManager.default
        var staged: [(original: URL, temp: URL, final: URL)] = []
        var errors: [String] = []
        for change in changes {
            let temp = change.item.url.deletingLastPathComponent().appending(path: ".scout-rename-\(UUID().uuidString)")
            do {
                try fm.moveItem(at: change.item.url, to: temp)
                staged.append((change.item.url, temp, change.item.url.deletingLastPathComponent().appending(path: change.newName)))
            } catch {
                errors.append(error.localizedDescription)
            }
        }
        var moves: [(URL, URL)] = []
        for entry in staged {
            do {
                try fm.moveItem(at: entry.temp, to: entry.final)
                moves.append((entry.original, entry.final))
            } catch {
                try? fm.moveItem(at: entry.temp, to: entry.original) // put it back
                errors.append(error.localizedDescription)
            }
        }
        registerUndoMoves(moves, name: "Rename \(moves.count) Items")
        if !errors.isEmpty { alertMessage = errors.joined(separator: "\n") }
        let renamed = Set(moves.map(\.1.filePath))
        Task {
            await reload()
            selection = Set(items.filter { renamed.contains($0.path) }.map(\.id))
        }
    }

    // MARK: - Cloud files

    /// Downloads online-only cloud files now (iCloud, OneDrive…).
    func downloadCloudItems(_ items: [FileItem]) {
        for item in items where item.cloud == .online {
            do { try FileManager.default.startDownloadingUbiquitousItem(at: item.url) } catch {
                alertMessage = "Couldn’t download “\(item.name)”: \(error.localizedDescription)"
            }
        }
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            await reload()
        }
    }

    /// Frees the space a cloud file takes on this Mac; it stays in the cloud.
    func removeCloudDownloads(_ items: [FileItem]) {
        for item in items where item.cloud == .downloaded {
            do { try FileManager.default.evictUbiquitousItem(at: item.url) } catch {
                alertMessage = "Couldn’t remove the download of “\(item.name)”: \(error.localizedDescription)"
            }
        }
        Task { await reload() }
    }

    // MARK: - Finder basics

    /// "report copy.pdf" next to each selected item.
    func duplicateSelection() {
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        transfer(urls, into: urls[0].deletingLastPathComponent(), move: false)
    }

    /// Finder aliases ("report alias") next to each selected item.
    func makeAliases() {
        var made: [URL] = []
        for item in selectedItems {
            do {
                let data = try item.url.bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil,
                                                     relativeTo: nil)
                let alias = LocalFileSource.availableURL(in: item.url.deletingLastPathComponent(),
                                                         preferredName: item.name + " alias", isDirectory: false, style: .numbered)
                try URL.writeBookmarkData(data, to: alias)
                made.append(alias)
            } catch {
                alertMessage = "Couldn’t make an alias of “\(item.name)”: \(error.localizedDescription)"
            }
        }
        if let undoManager, !made.isEmpty {
            undoManager.registerUndo(withTarget: self) { model in
                MainActor.assumeIsolated { for url in made { _ = try? model.services.fileSource.trash(url) } }
            }
            undoManager.setActionName("Make Alias")
        }
        Task {
            await reload()
            if let first = made.first { selectPath(first.filePath) }
        }
    }

    func airDropSelection() {
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else { return }
        service.perform(withItems: urls)
    }

    /// Opens Finder's own Get Info window (sharing, permissions, "Open with" for all…).
    func showFinderInfo() {
        let urls = selectedItems.isEmpty ? [location] : selectedItems.map(\.url)
        for url in urls {
            let path = url.filePath.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let script = "tell application \"Finder\"\nactivate\nopen information window of (POSIX file \"\(path)\" as alias)\nend tell"
            var error: NSDictionary?
            NSAppleScript(source: script)?.executeAndReturnError(&error)
            if let error {
                alertMessage = "Finder didn’t open Get Info: \(error[NSAppleScript.errorMessage] as? String ?? "permission needed"). Allow Scout to control Finder in System Settings ▸ Privacy & Security ▸ Automation."
                return
            }
        }
    }

    // MARK: - Tidy Folder

    /// Plans moving this folder's loose files into folders by kind; shows the plan first.
    func beginTidy() {
        guard isFolder else { return }
        let plan = Tidy.plan(for: items, in: location)
        if plan.isEmpty {
            alertMessage = "Nothing to tidy: there are no loose files here (new and unfinished downloads are left alone)."
        } else {
            tidyPlan = plan
        }
    }

    /// Moves files into their kind folders. ⌘Z moves them back and removes folders it made.
    func applyTidy(_ moves: [Tidy.Move]) {
        let fm = FileManager.default
        var made: [URL] = []
        var done: [(URL, URL)] = []
        var errors: [String] = []
        for move in moves {
            let folder = location.appending(path: move.folder, directoryHint: .isDirectory)
            do {
                if !fm.fileExists(atPath: folder.filePath) {
                    try fm.createDirectory(at: folder, withIntermediateDirectories: false)
                    made.append(folder)
                }
                let target = LocalFileSource.availableURL(in: folder, preferredName: move.item.name,
                                                          isDirectory: false, style: .numbered)
                try fm.moveItem(at: move.item.url, to: target)
                done.append((move.item.url, target))
            } catch {
                errors.append(error.localizedDescription)
            }
        }
        if let undoManager, !done.isEmpty {
            undoManager.registerUndo(withTarget: self) { model in
                MainActor.assumeIsolated {
                    for (from, to) in done { try? fm.moveItem(at: to, to: from) }
                    for folder in made where (try? fm.contentsOfDirectory(atPath: folder.filePath))?.isEmpty == true {
                        try? fm.removeItem(at: folder)
                    }
                    Task { await model.reload() }
                }
            }
            undoManager.setActionName("Tidy Folder")
        }
        if !errors.isEmpty { alertMessage = errors.joined(separator: "\n") }
        Task { await reload() }
    }

    // MARK: - Archives and new files

    /// Zips the selection next to it ("Report.zip", or "Archive.zip" for several).
    func compressSelection() {
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        runActivity(urls.count == 1 ? "Compressing “\(urls[0].lastPathComponent)”…" : "Compressing \(urls.count) items…") {
            try await Self.compress(urls)
        }
    }

    /// Extracts the selected archives next to themselves.
    func extractSelection() {
        let archives = selectedItems.map(\.url).filter(Archiver.canExtract)
        guard !archives.isEmpty else { return }
        runActivity(archives.count == 1 ? "Extracting “\(archives[0].lastPathComponent)”…" : "Extracting \(archives.count) archives…") {
            var last: URL?
            for archive in archives { last = try await Self.extract(archive) }
            return last
        }
    }

    var canExtractSelection: Bool { selectedItems.contains { Archiver.canExtract($0.url) } }

    // MARK: - Quick actions (images, PDFs)

    var selectedImages: [URL] { selectedItems.map(\.url).filter(QuickActions.isImage) }
    var selectedPDFs: [URL] { selectedItems.map(\.url).filter(QuickActions.isPDF) }

    func convertImages(to format: QuickActions.ImageFormat) {
        let images = selectedImages
        guard !images.isEmpty else { return }
        runActivity("Converting \(images.count == 1 ? "“\(images[0].lastPathComponent)”" : "\(images.count) images") to \(format.title)…") {
            try await Self.inBackground { try images.map { try QuickActions.convert($0, to: format) }.last }
        }
    }

    func resizeImages(maxPixels: Int) {
        let images = selectedImages
        guard !images.isEmpty else { return }
        runActivity("Resizing \(images.count == 1 ? "“\(images[0].lastPathComponent)”" : "\(images.count) images")…") {
            try await Self.inBackground { try images.map { try QuickActions.resize($0, maxPixels: maxPixels) }.last }
        }
    }

    /// Joins the selected PDFs (in list order) into "Combined.pdf".
    func combinePDFs() {
        let pdfs = selectedPDFs
        guard pdfs.count > 1 else { return }
        runActivity("Combining \(pdfs.count) PDFs…") {
            try await Self.inBackground { try QuickActions.combinePDFs(pdfs) }
        }
    }

    @concurrent nonisolated private static func inBackground(_ work: @Sendable () throws -> URL?) async throws -> URL? {
        try work()
    }

    /// Runs slow work off the main thread, then selects what it made. ⌘Z moves it to the Trash.
    private func runActivity(_ title: String, _ work: @escaping () async throws -> URL?) {
        activity = title
        Task {
            do {
                if let made = try await work() {
                    if let undoManager {
                        undoManager.registerUndo(withTarget: self) { model in
                            MainActor.assumeIsolated { _ = try? model.services.fileSource.trash(made) }
                        }
                        undoManager.setActionName(title.hasPrefix("Compress") ? "Compress" : "Extract")
                    }
                    pendingSelection = made.filePath
                }
            } catch {
                alertMessage = error.localizedDescription
            }
            activity = nil
            await reload()
        }
    }

    @concurrent nonisolated private static func compress(_ urls: [URL]) async throws -> URL? {
        try Archiver.compress(urls)
    }

    @concurrent nonisolated private static func extract(_ url: URL) async throws -> URL? {
        try Archiver.extract(url)
    }

    enum NewFileKind: String, CaseIterable {
        case text, markdown
        var name: String { self == .text ? "untitled.txt" : "untitled.md" }
        var title: String { self == .text ? "Text File" : "Markdown File" }
    }

    /// An empty text or markdown file, ready to rename.
    func newFile(_ kind: NewFileKind) {
        guard isFolder else { return }
        let url = LocalFileSource.availableURL(in: location, preferredName: kind.name, isDirectory: false, style: .numbered)
        guard FileManager.default.createFile(atPath: url.filePath, contents: Data()) else {
            alertMessage = "Couldn’t create a file here."
            return
        }
        if let undoManager {
            undoManager.registerUndo(withTarget: self) { model in
                MainActor.assumeIsolated { _ = try? model.services.fileSource.trash(url) }
            }
            undoManager.setActionName("New \(kind.title)")
        }
        Task {
            await reload()
            if let item = items.first(where: { $0.path == url.filePath }) {
                select(item)
                renaming = item
            }
        }
    }

    func rename(_ item: FileItem, to newName: String) {
        do {
            let renamed = try services.fileSource.rename(item.url, to: newName)
            registerUndoMoves([(item.url, renamed)], name: "Rename")
            pendingSelection = renamed.filePath
            Task { await reload() }
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func newFolder() {
        guard isFolder else { return }
        do {
            let url = try services.fileSource.createFolder(in: location, named: "untitled folder")
            if let undoManager {
                undoManager.registerUndo(withTarget: self) { model in
                    MainActor.assumeIsolated { _ = try? model.services.fileSource.trash(url) }
                }
                undoManager.setActionName("New Folder")
            }
            Task {
                await reload()
                if let item = items.first(where: { $0.path == url.filePath }) {
                    selection = [item.id]
                    renaming = item
                }
            }
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func trashSelection() {
        guard !selectedItems.isEmpty else { return }
        trash(selectedItems.map(\.url))
        selection = []
    }

    /// Moves items to the Trash (⌘Z puts them back). Returns how many went.
    @discardableResult
    func trash(_ urls: [URL], actionName: String = "Move to Trash") -> Int {
        var moves: [(URL, URL)] = []
        var errors: [String] = []
        for url in urls {
            do {
                if let trashed = try services.fileSource.trash(url) { moves.append((url, trashed)) }
            } catch {
                errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        registerUndoMoves(moves, name: actionName)
        if !errors.isEmpty { alertMessage = errors.joined(separator: "\n") }
        Task { await reload() }
        return moves.count
    }

    func copySelectionToPasteboard() {
        let urls = selectedItems.map { $0.url as NSURL }
        guard !urls.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(urls)
    }

    func copyPaths() {
        let paths = selectedItems.isEmpty ? [location.filePath] : selectedItems.map(\.path)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(paths.joined(separator: "\n"), forType: .string)
    }

    /// Pastes files copied in Scout, Finder or anywhere else. `move` = ⌥⌘V.
    func paste(move: Bool) {
        guard isFolder else { return }
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: options) as? [URL],
              !urls.isEmpty else { return }
        transfer(urls, into: location, move: move)
    }

    /// Files dropped onto this tab: move within a disk, copy across disks (like
    /// Finder); holding ⌥ always copies.
    @discardableResult
    func receiveDrop(_ urls: [URL], into folder: URL? = nil) -> Bool {
        let target = folder ?? location
        guard folder != nil || isFolder else { return false }
        // Not into itself or something inside itself.
        let urls = urls.filter { $0.filePath != target.filePath && !target.filePath.hasPrefix($0.filePath + "/") }
        guard !urls.isEmpty else { return false }
        let forceCopy = NSEvent.modifierFlags.contains(.option)
        let destinationVolume = try? target.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier as? NSObject
        let sameVolume = urls.allSatisfy { url in
            let volume = try? url.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier as? NSObject
            return volume != nil && volume == destinationVolume
        }
        transfer(urls, into: target, move: sameVolume && !forceCopy)
        return true
    }

    /// The "already exists" question waiting for an answer (drives the conflict sheet).
    var conflict: ConflictPrompt?

    /// Copies or moves items into a folder (paste, drops, F5/F6 between panes).
    /// Asks Replace / Keep Both / Skip when a name is taken, shows progress for slow ones,
    /// and ⌘Z undoes it.
    func transfer(_ urls: [URL], into destination: URL, move: Bool) {
        // Never copy or move a folder into itself (copying would nest it until the path is too long).
        let urls = urls.filter { $0.filePath != destination.filePath && !destination.filePath.hasPrefix($0.filePath + "/") }
        guard !urls.isEmpty else {
            alertMessage = "Can’t put a folder inside itself."
            return
        }
        Task {
            // 1. Decide where each item goes, asking about clashes.
            var plan: [(source: URL, target: URL, replace: Bool)] = []
            var applyToAll: ConflictChoice?
            let fm = FileManager.default
            let clashing = urls.filter { url in
                url.deletingLastPathComponent().filePath != destination.filePath
                    && fm.fileExists(atPath: destination.appending(path: url.lastPathComponent).filePath)
            }
            var remaining = clashing.count
            for url in urls {
                let sameFolder = url.deletingLastPathComponent().filePath == destination.filePath
                if move && sameFolder { continue }
                var choice: ConflictChoice?
                if fm.fileExists(atPath: destination.appending(path: url.lastPathComponent).filePath) {
                    if sameFolder {
                        choice = .keepBoth // copying into its own folder makes "x copy"
                    } else if let all = applyToAll {
                        choice = all
                    } else {
                        guard let answer = await askConflict(url, in: destination, move: move, remaining: remaining)
                        else { return } // Stop
                        choice = answer.choice
                        if answer.applyToAll { applyToAll = answer.choice }
                    }
                    if !sameFolder { remaining -= 1 }
                }
                guard let target = FileCopier.destination(for: url, in: destination, choice: choice, isCopy: !move) else { continue }
                // Replacing a folder that contains the item would trash the item itself.
                if choice == .replace, url.filePath.hasPrefix(target.filePath + "/") {
                    alertMessage = "Can’t replace “\(target.lastPathComponent)”: it contains “\(url.lastPathComponent)”."
                    continue
                }
                plan.append((url, target, choice == .replace))
            }
            guard !plan.isEmpty else { return }

            // 2. Do it off the main thread, with progress.
            let verb = move ? "Moving" : "Copying"
            let title = plan.count == 1 ? "\(verb) “\(plan[0].source.lastPathComponent)”"
                : "\(verb) \(plan.count) items to “\(destination.lastPathComponent)”"
            let needsBytes = !move || !FileCopier.sameVolume(plan[0].source, destination)
            let total = needsBytes ? await Self.measure(plan.map(\.source)) : 0
            let transfer = Transfer(title: title, totalBytes: total)
            services.begin(transfer)
            let (results, errors) = await Self.run(plan, move: move, transfer: transfer)
            services.end(transfer)

            // 3. Undo, errors, refresh, select what arrived.
            if move {
                registerUndoMoves(results, name: "Move")
            } else if let undoManager, !results.isEmpty {
                let copies = results.map(\.1)
                undoManager.registerUndo(withTarget: self) { model in
                    MainActor.assumeIsolated {
                        for url in copies { _ = try? model.services.fileSource.trash(url) }
                    }
                }
                undoManager.setActionName("Copy")
            }
            if !errors.isEmpty, !transfer.isCancelled { alertMessage = errors.joined(separator: "\n") }
            await reload()
            if destination.filePath == location.filePath {
                let newPaths = Set(results.map(\.1.filePath))
                selection = Set(items.filter { newPaths.contains($0.path) }.map(\.id))
            }
        }
    }

    private func askConflict(_ url: URL, in folder: URL, move: Bool, remaining: Int) async -> ConflictAnswer? {
        guard let incoming = LocalFileSource.item(for: url),
              let existing = LocalFileSource.item(for: folder.appending(path: url.lastPathComponent)) else {
            return ConflictAnswer(choice: .keepBoth, applyToAll: false)
        }
        return await withCheckedContinuation { continuation in
            conflict = ConflictPrompt(incoming: incoming, existing: existing, folderName: folder.lastPathComponent,
                                      isMove: move, remaining: remaining) { [weak self] answer in
                self?.conflict = nil
                continuation.resume(returning: answer)
            }
        }
    }

    @concurrent nonisolated private static func measure(_ urls: [URL]) async -> Int64 {
        urls.reduce(0) { $0 + FileCopier.totalBytes($1) }
    }

    @concurrent nonisolated private static func run(_ plan: [(source: URL, target: URL, replace: Bool)], move: Bool,
                                                    transfer: Transfer) async -> ([(URL, URL)], [String]) {
        var done: [(URL, URL)] = []
        var failed: [String] = []
        var finishedBytes: Int64 = 0
        for step in plan {
            if transfer.isCancelled { break }
            transfer.set(current: step.source.lastPathComponent)
            do {
                if step.replace {
                    // The one being replaced goes to the Trash, not away for good.
                    try FileManager.default.trashItem(at: step.target, resultingItemURL: nil)
                }
                let base = finishedBytes
                let progress: FileCopier.Progress = { bytes in
                    transfer.set(done: base + bytes)
                    return !transfer.isCancelled
                }
                if move {
                    try FileCopier.move(step.source, to: step.target, progress: progress)
                } else {
                    try FileCopier.copy(step.source, to: step.target, progress: progress)
                }
                finishedBytes += transfer.totalBytes > 0 ? FileCopier.totalBytes(step.target) : 0
                transfer.set(done: finishedBytes)
                done.append((step.source, step.target))
            } catch FileCopier.Failure.cancelled {
                break
            } catch {
                failed.append(error.localizedDescription)
            }
        }
        return (done, failed)
    }

    /// Records that items moved from → to. Undo moves them back (and Redo forward again).
    private func registerUndoMoves(_ moves: [(URL, URL)], name: String) {
        guard let undoManager, !moves.isEmpty else { return }
        undoManager.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                var reversed: [(URL, URL)] = []
                for (from, to) in moves {
                    do {
                        try FileManager.default.moveItem(at: to, to: from)
                        reversed.append((to, from))
                    } catch {
                        model.alertMessage = error.localizedDescription
                    }
                }
                model.registerUndoMoves(reversed, name: name)
                Task { await model.reload() }
            }
        }
        undoManager.setActionName(name)
    }

    // MARK: - Other apps

    func showInFinder() {
        let urls = selectedItems.isEmpty ? [location] : selectedItems.map(\.url)
        FinderBridge.reveal(urls)
    }

    /// Opens a folder in your terminal (Tern, Ghostty, iTerm… or Terminal).
    func openInTerminal(_ folder: URL? = nil) {
        let target = folder ?? location
        if let terminal = DevApp.preferredTerminal {
            terminal.open(target)
        } else {
            let terminal = URL(filePath: "/System/Applications/Utilities/Terminal.app")
            NSWorkspace.shared.open([target], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    /// Opens the selection (or this folder) in your code editor.
    func openInEditor(_ url: URL? = nil) {
        guard let editor = DevApp.preferredEditor else {
            alertMessage = "Scout didn’t find a code editor (Cursor, VS Code, Zed, Xcode…)."
            return
        }
        editor.open(url ?? (selectedItems.count == 1 ? selectedItems[0].url : location))
    }

    // MARK: - Git

    /// Re-reads git status (after loading a folder, or when you come back to Scout).
    func refreshGit() {
        gitTask?.cancel()
        let path = changesRoot ?? (isFolder ? location.filePath : nil)
        guard let path, let root = Git.repositoryRoot(containing: path) else {
            if git != nil { git = nil }
            if untrustedRepo != nil { untrustedRepo = nil }
            return
        }
        let trusted = services.isTrustedRepository(root)
        gitTask = Task {
            let (snapshot, blocked) = await Self.readGit(root: root, trusted: trusted)
            guard !Task.isCancelled else { return }
            git = snapshot
            let untrusted = blocked ? root : nil
            if untrustedRepo != untrusted { untrustedRepo = untrusted }
            if changesRoot != nil { items = changedItems() }
        }
    }

    /// "Trust This Repository": run git here from now on.
    func trustRepository() {
        guard let root = untrustedRepo else { return }
        services.trustRepository(root)
        refreshGit()
    }

    /// The Changes page: changed files that still exist (deleted ones are counted in the header),
    /// conflicts first, then modified, added, untracked.
    private func changedItems() -> [FileItem] {
        guard let status = git?.status else { return [] }
        return status.changes
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key.localizedStandardCompare($1.key) == .orderedAscending }
            .compactMap { relative, _ in
                let path = status.root + "/" + (relative.hasSuffix("/") ? String(relative.dropLast()) : relative)
                return LocalFileSource.item(for: URL(filePath: path))
            }
    }

    /// The repository's status, or `blocked` when its settings could run programs and you
    /// haven't trusted it (git isn't run at all then).
    @concurrent nonisolated private static func readGit(root: String, trusted: Bool) async
        -> (snapshot: GitRunner.Snapshot?, blocked: Bool) {
        guard trusted || GitTrust.isSafe(root: root) else { return (nil, true) }
        return (GitRunner.snapshot(root: root), false)
    }

    func gitState(_ item: FileItem) -> GitFileState? {
        git?.status.state(for: item.path, isFolder: item.isNavigable)
    }

    /// The repository's GitHub page, if its remote is on GitHub.
    var gitHubRepo: URL? { git?.remote.flatMap(Git.gitHubURL(fromRemote:)) }

    /// The GitHub page for a file or folder in this repository.
    func gitHubURL(for url: URL, isFolder: Bool) -> URL? {
        guard let git, let repo = gitHubRepo, let relative = git.status.relativePath(url.filePath) else { return nil }
        return Git.gitHubURL(repo: repo, ref: git.status.branch ?? git.status.commit ?? "HEAD",
                             relativePath: relative, isFolder: isFolder)
    }

    /// Path relative to the repository root ("Sources/App/main.swift").
    func repoRelativePath(_ url: URL) -> String? {
        git?.status.relativePath(url.filePath).map { $0.isEmpty ? "." : $0 }
    }
}
