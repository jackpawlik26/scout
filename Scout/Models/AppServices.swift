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

    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var sizeCache: [String: (size: FolderStats.Size, at: Date)] = [:]
    @ObservationIgnored private var mountObservers: [NSObjectProtocol] = []

    init() {
        frecency = ScoutStore.loadHistory()
        savedSearches = ScoutStore.loadSavedSearches()
        workspaces = ScoutStore.loadWorkspaces()
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

    var favorites: [Place] {
        [
            Place(url: home, name: FileManager.default.displayName(atPath: homePath), symbol: "house"),
            Place(url: home.appending(path: "Desktop", directoryHint: .isDirectory), name: "Desktop", symbol: "menubar.dock.rectangle"),
            Place(url: home.appending(path: "Documents", directoryHint: .isDirectory), name: "Documents", symbol: "doc"),
            Place(url: home.appending(path: "Downloads", directoryHint: .isDirectory), name: "Downloads", symbol: "arrow.down.circle"),
            Place(url: .folder("/Applications"), name: "Applications", symbol: "square.grid.2x2"),
        ]
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
