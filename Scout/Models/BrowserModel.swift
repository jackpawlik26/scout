import AppKit
import Observation
import ScoutCore

enum ViewMode: String, CaseIterable, Identifiable {
    case list, icons
    var id: Self { self }
}

enum SortField: String, CaseIterable, Identifiable {
    case name, modified, size, kind
    var id: Self { self }

    var title: String {
        switch self {
        case .name: "Name"
        case .modified: "Date Modified"
        case .size: "Size"
        case .kind: "Kind"
        }
    }

    /// Dates and sizes start newest/biggest first.
    var defaultAscending: Bool { self == .name || self == .kind }
}

/// What a tab is showing.
enum BrowserMode: Equatable {
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
        didSet { refreshDisplayed() }
    }
    var filterText = "" { didSet { refreshDisplayed() } }
    /// New tabs start from Settings' choices; the View menu changes one tab.
    var foldersFirst = UserDefaults.standard.object(forKey: "foldersFirst") as? Bool ?? true { didSet { refreshDisplayed() } }
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
    /// The item being renamed (drives the rename dialog).
    var renaming: FileItem?
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
    var showsLocations: Bool { search != nil || workspaceID != nil || changesRoot != nil }

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
    /// The folder sort order, kept while a search is showing.
    @ObservationIgnored private var folderSortOrder = defaultSortOrder
    @ObservationIgnored private var gitTask: Task<Void, Never>?

    init(location: URL, services: AppServices) {
        self.location = .folder(location.filePath)
        self.services = services
        Task { await load(recordVisit: true) }
    }

    var title: String {
        switch mode {
        case .search(let saved): return saved.name
        case .workspace: return workspace?.name ?? "Workspace"
        case .cleanup: return "Clean Up"
        case .packages: return "Packages"
        case .settings: return "Settings"
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
        }
        comparator.order = ascending ? .forward : .reverse
        sortOrder = [comparator]
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
        pendingSelection = child?.filePath
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
            watcher = nil
            items = []
            return
        case .changes:
            spotlight = nil
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
        isSearching = false
        let target = location
        isLoading = true
        defer { if generation == loadGeneration { isLoading = false } }

        do {
            let result = try await services.fileSource.contents(of: target, includeHidden: showHidden)
            guard generation == loadGeneration else { return }
            items = result
            loadError = nil
            needsPermission = false
            freeSpace = try? target.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
                .volumeAvailableCapacityForImportantUsage
            if recordVisit { services.recordVisit(target) }
            refreshGit()
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

    /// A workspace's items, in the order you added them. Missing ones are skipped.
    private func loadWorkspace() {
        spotlight = nil
        watcher = nil
        isSearching = false
        loadError = nil
        needsPermission = false
        items = (workspace?.paths ?? []).compactMap { LocalFileSource.item(for: URL(filePath: $0)) }
    }

    private func startSearch(_ saved: SavedSearch, generation: Int) {
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
        return true
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
        if foldersFirst, isFolder { list = list.filter(\.isNavigable) + list.filter { !$0.isNavigable } }
        displayedItems = list
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

    func beginRename() -> Bool {
        guard selectedItems.count == 1 else { return false }
        renaming = selectedItems[0]
        return true
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
    func receiveDrop(_ urls: [URL]) -> Bool {
        guard isFolder, !urls.isEmpty else { return false }
        let forceCopy = NSEvent.modifierFlags.contains(.option)
        let destinationVolume = try? location.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier as? NSObject
        let sameVolume = urls.allSatisfy { url in
            let volume = try? url.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier as? NSObject
            return volume != nil && volume == destinationVolume
        }
        transfer(urls, into: location, move: sameVolume && !forceCopy)
        return true
    }

    /// Copies or moves items into a folder (paste, drops, F5/F6 between panes).
    /// Name clashes keep both ("report copy.pdf"); ⌘Z undoes.
    func transfer(_ urls: [URL], into destination: URL, move: Bool) {
        let source = services.fileSource

        Task {
            // Copy off the main thread so big files don't freeze the window.
            let (results, errors) = await Task.detached(priority: .userInitiated) {
                var done: [(URL, URL)] = []
                var failed: [String] = []
                for url in urls {
                    if move && url.deletingLastPathComponent().filePath == destination.filePath { continue }
                    do {
                        let new = move ? try source.move(url, into: destination) : try source.copy(url, into: destination)
                        done.append((url, new))
                    } catch {
                        failed.append(error.localizedDescription)
                    }
                }
                return (done, failed)
            }.value

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
            if !errors.isEmpty { alertMessage = errors.joined(separator: "\n") }
            await reload()
            if destination.filePath == location.filePath {
                let newPaths = Set(results.map(\.1.filePath))
                selection = Set(items.filter { newPaths.contains($0.path) }.map(\.id))
            }
        }
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
        NSWorkspace.shared.activateFileViewerSelecting(urls)
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
            return
        }
        gitTask = Task {
            let snapshot = await Self.readGit(root: root)
            guard !Task.isCancelled else { return }
            git = snapshot
            if changesRoot != nil { items = changedItems() }
        }
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

    @concurrent nonisolated private static func readGit(root: String) async -> GitRunner.Snapshot? {
        GitRunner.snapshot(root: root)
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
