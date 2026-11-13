import AppKit
import Observation
import ScoutCore

/// A place in the sidebar.
struct Place: Identifiable, Hashable {
    let url: URL
    let name: String
    let symbol: String
    var id: String { url.filePath }
}

/// App-wide state shared by every window: the folder index for ⌘K, visit history,
/// and the drives shown in the sidebar.
@Observable
final class AppServices {
    let fileSource = LocalFileSource()
    let home = URL.folder(FileManager.default.homeDirectoryForCurrentUser.filePath)
    var homePath: String { home.filePath }

    private(set) var frecency: FrecencyLog
    private(set) var folders: [IndexedFolder] = []
    private(set) var isIndexing = false
    private(set) var volumes: [Place] = []
    private(set) var savedSearches: [SavedSearch] = []
    private(set) var workspaces: [Workspace] = []
    /// Copies and moves in progress (the progress card shows the slow ones).
    private(set) var transfers: [Transfer] = []

    /// Tags you've used besides Finder's seven colors (remembered as they're seen).
    private(set) var customTags: [FileTag] = (UserDefaults.standard.array(forKey: "customTags") as? [String] ?? [])
        .map { Tags.parse($0) }

    var allTags: [FileTag] { FileTag.standard + customTags }

    /// Remembers tags that aren't Finder's built-in colors so they show in menus and the sidebar.
    func noteTags(_ tags: some Sequence<FileTag>) {
        let known = Set(allTags.map(\.name))
        let new = tags.filter { !known.contains($0.name) }
        guard !new.isEmpty else { return }
        var seen = Set<String>()
        customTags = (customTags + new).filter { seen.insert($0.name).inserted }.sorted { $0.name < $1.name }
        UserDefaults.standard.set(customTags.map { "\($0.name)\n\($0.color)" }, forKey: "customTags")
    }

    func begin(_ transfer: Transfer) { transfers.append(transfer) }
    func end(_ transfer: Transfer) { transfers.removeAll { $0.id == transfer.id } }
    /// Pinned favorites, in your order (starts with Home, Desktop, Documents, Downloads, Applications).
    private(set) var favoritePaths: [String] = []

    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var sizeCache: [String: (size: FolderStats.Size, at: Date)] = [:]
    @ObservationIgnored private var mountObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var windowModels: [WeakWindow] = []
    /// The palette was opened by the global shortcut from another app (so Esc goes back there).
    @ObservationIgnored private var summonedByHotKey = false

    private struct WeakWindow { weak var model: BrowserWindowModel? }

    init() {
        frecency = ScoutStore.loadHistory()
        savedSearches = ScoutStore.loadSavedSearches()
        workspaces = ScoutStore.loadWorkspaces()
        favoritePaths = ScoutStore.loadFavorites() ?? defaultFavorites
        // Start with the saved index so ⌘K works instantly, then refresh it.
        folders = ScoutStore.loadFolders(home: home.filePath) ?? []
        refreshVolumes()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            mountObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshVolumes() }
            })
        }
        Task {
            while !Task.isCancelled {
                await rebuildIndex()
                try? await Task.sleep(for: .seconds(30 * 60))
            }
        }
    }

    // MARK: - Windows, links from outside, the global shortcut

    func register(_ window: BrowserWindowModel) {
        windowModels.removeAll { $0.model == nil }
        windowModels.append(WeakWindow(model: window))
    }

    /// The frontmost Scout window that's on screen (or minimized).
    var frontWindow: BrowserWindowModel? {
        let models = windowModels.compactMap(\.model).filter { $0.nsWindow != nil }
        for window in NSApp.orderedWindows {
            if let model = models.first(where: { $0.nsWindow === window }) { return model }
        }
        return models.first
    }

    /// Brings Scout forward and handles the link in its front window, or opens a window for it.
    func route(_ link: ScoutLink) {
        if let model = frontWindow, let window = model.nsWindow {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            model.handle(link)
        } else {
            // No window open: SwiftUI opens one and passes it the link.
            NSWorkspace.shared.open(link.url)
        }
    }

    /// The global shortcut: opens the jump palette over whatever you're doing; pressing it
    /// again (or Esc) closes it and goes back to the app you were in.
    func toggleJumpPalette() {
        if NSApp.isActive, let model = frontWindow, model.nsWindow?.isKeyWindow == true, model.isPaletteOpen {
            model.isPaletteOpen = false
            paletteClosed(cancelled: true)
            return
        }
        summonedByHotKey = !NSApp.isActive
        route(.jump(query: nil))
    }

    func paletteClosed(cancelled: Bool) {
        if cancelled, summonedByHotKey { NSApp.hide(nil) }
        summonedByHotKey = false
    }

    // MARK: - Sidebar places

    var iCloudDrive: URL? {
        let url = home.appending(path: "Library/Mobile Documents/com~apple~CloudDocs", directoryHint: .isDirectory)
        return FileManager.default.fileExists(atPath: url.filePath) ? url : nil
    }

    /// OneDrive, Google Drive, Dropbox… (they live in ~/Library/CloudStorage).
    var cloudStorage: [Place] {
        let dir = home.appending(path: "Library/CloudStorage", directoryHint: .isDirectory)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.filePath)) ?? []
        return names.filter { !$0.hasPrefix(".") }.sorted().map {
            Place(url: dir.appending(path: $0, directoryHint: .isDirectory), name: PathDisplay.cloudName($0), symbol: "cloud")
        }
    }

    private var defaultFavorites: [String] {
        [homePath, homePath + "/Desktop", homePath + "/Documents", homePath + "/Downloads", "/Applications"]
    }

    /// Favorites that still exist, with their sidebar icons.
    var favorites: [Place] {
        favoritePaths.compactMap { path in
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { return nil }
            let symbols = [homePath: "house", homePath + "/Desktop": "menubar.dock.rectangle", homePath + "/Documents": "doc",
                           homePath + "/Downloads": "arrow.down.circle", "/Applications": "square.grid.2x2"]
            let symbol = symbols[path] ?? (isDir.boolValue ? "folder" : "doc.text")
            return Place(url: isDir.boolValue ? .folder(path) : URL(filePath: path),
                         name: FileManager.default.displayName(atPath: path), symbol: symbol)
        }
    }

    func isFavorite(_ path: String) -> Bool { favoritePaths.contains(path) }

    /// Pins paths to Favorites (before `index`, or at the end). Pinned ones move there instead.
    func addFavorites(_ paths: [String], at index: Int? = nil) {
        var list = favoritePaths
        var insertAt = min(index ?? list.count, list.count)
        for path in paths {
            if let existing = list.firstIndex(of: path) {
                list.remove(at: existing)
                if existing < insertAt { insertAt -= 1 }
            }
            list.insert(path, at: insertAt)
            insertAt += 1
        }
        setFavorites(list)
    }

    func removeFavorite(_ path: String) { setFavorites(favoritePaths.filter { $0 != path }) }

    func moveFavorite(_ path: String, by offset: Int) {
        guard let index = favoritePaths.firstIndex(of: path) else { return }
        let target = index + offset
        guard favoritePaths.indices.contains(target) else { return }
        var list = favoritePaths
        list.swapAt(index, target)
        setFavorites(list)
    }

    func resetFavorites() { setFavorites(defaultFavorites) }

    private func setFavorites(_ paths: [String]) {
        favoritePaths = paths
        try? ScoutStore.saveFavorites(paths)
    }

    var locations: [Place] {
        var result = [Place(url: .folder("/"), name: Self.volumeName(.folder("/")) ?? "Macintosh HD", symbol: "internaldrive")]
        if let iCloudDrive { result.append(Place(url: iCloudDrive, name: "iCloud Drive", symbol: "icloud")) }
        result += cloudStorage
        result += volumes
        return result
    }

    /// Most-used folders that aren't already favorites.
    func frequent(limit: Int = 6) -> [Place] {
        let taken = Set((favorites + locations).map(\.id))
        return frecency.top(limit * 3)
            .filter { !taken.contains($0) && FileManager.default.fileExists(atPath: $0) }
            .prefix(limit)
            .map { Place(url: .folder($0), name: ($0 as NSString).lastPathComponent, symbol: "folder") }
    }

    func refreshVolumes() {
        let keys: [URLResourceKey] = [.volumeIsBrowsableKey, .volumeIsRootFileSystemKey, .volumeIsInternalKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        volumes = urls.compactMap { url in
            guard let v = try? url.resourceValues(forKeys: Set(keys)),
                  v.volumeIsBrowsable == true, v.volumeIsRootFileSystem != true else { return nil }
            let symbol = v.volumeIsInternal == true ? "internaldrive" : "externaldrive"
            return Place(url: .folder(url.filePath), name: Self.volumeName(url) ?? url.lastPathComponent, symbol: symbol)
        }
    }

    static func volumeName(_ url: URL) -> String? {
        try? url.resourceValues(forKeys: [.volumeLocalizedNameKey]).volumeLocalizedName
    }


    // MARK: - Folder index (⌘K)

    func rebuildIndex() async {
        guard !isIndexing else { return }
        isIndexing = true
        let homePath = homePath
        let roots = ScoutStore.defaultIndexRoots(home: homePath)
        let result = await Task.detached(priority: .utility) {
            FolderIndexer.scan(roots: roots, home: homePath)
        }.value
        folders = result
        isIndexing = false
        // Shared with the `scout` CLI and the Raycast extension.
        try? ScoutStore.saveFolders(result)
    }

    // MARK: - Folder sizes

    /// Total size of a folder, cached for 10 minutes.
    func folderSize(_ url: URL) async -> FolderStats.Size {
        let key = url.filePath
        if let cached = sizeCache[key], Date().timeIntervalSince(cached.at) < 600 { return cached.size }
        let size = await Self.measure(url)
        if !Task.isCancelled { sizeCache[key] = (size, .now) }
        return size
    }

    @concurrent nonisolated private static func measure(_ url: URL) async -> FolderStats.Size {
        FolderStats.size(of: url, fileLimit: 100_000)
    }

    // MARK: - Workspaces

    func workspace(_ id: UUID) -> Workspace? { workspaces.first { $0.id == id } }

    @discardableResult
    func createWorkspace(name: String, symbol: String, paths: [String]) -> Workspace {
        let workspace = Workspace(name: name, symbol: symbol, paths: paths)
        workspaces.append(workspace)
        persistWorkspaces()
        return workspace
    }

    func updateWorkspace(_ id: UUID, _ change: (inout Workspace) -> Void) {
        guard let i = workspaces.firstIndex(where: { $0.id == id }) else { return }
        change(&workspaces[i])
        persistWorkspaces()
    }

    func deleteWorkspace(_ id: UUID) {
        workspaces.removeAll { $0.id == id }
        persistWorkspaces()
    }

    private func persistWorkspaces() {
        try? ScoutStore.saveWorkspaces(workspaces)
    }

    // MARK: - Saved searches

    func save(_ search: SavedSearch) {
        if let i = savedSearches.firstIndex(where: { $0.id == search.id }) {
            savedSearches[i] = search
        } else {
            savedSearches.append(search)
        }
        try? ScoutStore.saveSavedSearches(savedSearches)
    }

    func removeSearch(_ id: UUID) {
        savedSearches.removeAll { $0.id == id }
        try? ScoutStore.saveSavedSearches(savedSearches)
    }

    func isSaved(_ search: SavedSearch) -> Bool {
        savedSearches.contains { $0.id == search.id }
    }

    // MARK: - Visit history

    func recordVisit(_ url: URL) {
        frecency.record(url.filePath)
        scheduleSave()
    }

    /// Forgets every visit (⌘K ranking and the Frequent list start over).
    func clearHistory() {
        frecency = FrecencyLog()
        scheduleSave()
    }

    func forget(_ path: String) {
        frecency.forget(path)
        scheduleSave()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = frecency
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            try? ScoutStore.saveHistory(snapshot)
        }
    }
}
