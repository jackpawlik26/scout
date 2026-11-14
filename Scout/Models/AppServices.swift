import AppKit
import Observation
import ScoutCore

/// A place in the sidebar.
struct Place: Identifiable, Hashable {
    let url: URL
    let name: String
    let symbol: String
    /// External drives, disk images and network shares show an eject button.
    var isEjectable = false
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

    /// Tags actually on your files (from Spotlight, plus any seen while browsing), for the
    /// sidebar. Empty for people who don't use tags, so the section stays hidden.
    private(set) var tagsInUse: [FileTag] = []

    func refreshTagsInUse() {
        let home = homePath
        Task {
            let found = await Self.findUsedTags(home: home)
            addTagsInUse(found)
        }
    }

    private func addTagsInUse(_ tags: some Sequence<FileTag>) {
        var byName = Dictionary(tagsInUse.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        for tag in tags where byName[tag.name] == nil { byName[tag.name] = tag }
        guard byName.count != tagsInUse.count else { return }
        let order = FileTag.standard.map(\.name)
        tagsInUse = byName.values.sorted {
            let a = order.firstIndex(of: $0.name) ?? order.count, b = order.firstIndex(of: $1.name) ?? order.count
            return a != b ? a < b : $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    @concurrent nonisolated private static func findUsedTags(home: String) async -> [FileTag] {
        guard let output = CommandRunner.run("/usr/bin/mdfind", ["-onlyin", home, "kMDItemUserTags == *"], timeout: 15)
        else { return [] }
        var found: [String: FileTag] = [:]
        for path in output.split(separator: "\n").prefix(3_000) {
            for tag in Tags.read(URL(filePath: String(path))) where found[tag.name] == nil { found[tag.name] = tag }
        }
        return Array(found.values)
    }

    /// Remembers tags that aren't Finder's built-in colors so they show in menus and the sidebar.
    func noteTags(_ tags: some Sequence<FileTag>) {
        addTagsInUse(tags)
        let known = Set(allTags.map(\.name))
        let new = tags.filter { !known.contains($0.name) }
        guard !new.isEmpty else { return }
        var seen = Set<String>()
        customTags = (customTags + new).filter { seen.insert($0.name).inserted }.sorted { $0.name < $1.name }
        UserDefaults.standard.set(customTags.map { "\($0.name)\n\($0.color)" }, forKey: "customTags")
    }

    /// Folder colors and symbols, nicknames and pinned items (customizations.json).
    private(set) var customizations = ScoutStore.loadCustomizations()

    func customize(_ path: String, _ change: (inout ItemStyle) -> Void) {
        customizations.update(path, change)
        try? ScoutStore.saveCustomizations(customizations)
    }

    func togglePin(_ path: String) {
        customizations.togglePin(path)
        try? ScoutStore.saveCustomizations(customizations)
    }

    /// The nickname if you gave one, else the real name.
    func displayName(_ item: FileItem) -> String {
        customizations.style(for: item.path)?.nickname.flatMap { $0.isEmpty ? nil : $0 } ?? item.name
    }

    /// Files collected on the Shelf (⌥⌘S).
    private(set) var shelf: [URL] = []

    func addToShelf(_ urls: [URL]) {
        for url in urls where !shelf.contains(url) { shelf.append(url) }
    }

    func removeFromShelf(_ url: URL) { shelf.removeAll { $0 == url } }
    func clearShelf() { shelf = [] }

    func begin(_ transfer: Transfer) { transfers.append(transfer) }
    func end(_ transfer: Transfer) { transfers.removeAll { $0.id == transfer.id } }
    /// Pinned favorites, in your order (starts with Home, Desktop, Documents, Downloads, Applications).
    private(set) var favoritePaths: [String] = []

    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var sizeCache: [String: (size: FolderStats.Size, at: Date)] = [:]
    @ObservationIgnored private var sizeWalks: [String: Task<FolderStats.Size, Never>] = [:]
    @ObservationIgnored private var mountObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var windowModels: [WeakWindow] = []
    /// The palette was opened by the global shortcut from another app (so Esc goes back there).
    @ObservationIgnored private var summonedByHotKey = false

    private struct WeakWindow { weak var model: BrowserWindowModel? }

    /// Settings that differ for new installs: developer tools off, a welcome card, and a
    /// shorter sidebar. People who used Scout before keep what they had.
    static func applyFirstRunDefaults() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: DeveloperTools.key) == nil else { return }
        let returning = FileManager.default.fileExists(atPath: ScoutStore.historyURL.filePath)
        defaults.set(returning, forKey: DeveloperTools.key)
        defaults.set(returning, forKey: "welcomeShown")
        if !returning, defaults.string(forKey: "collapsedSections") == nil {
            defaults.set("Locations", forKey: "collapsedSections")
        }
    }

    init() {
        Self.applyFirstRunDefaults()
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
        refreshLatestDownloads()
        refreshTagsInUse()
        Task {
            // A recent index (or a quick relaunch) doesn't need a fresh scan of the whole home folder.
            if let built = ScoutStore.indexDate(), !folders.isEmpty {
                let age = Date().timeIntervalSince(built)
                if age < 30 * 60 { try? await Task.sleep(for: .seconds(30 * 60 - age)) }
            }
            while !Task.isCancelled {
                // Only while you're using Scout, and not on Low Power Mode.
                if NSApp.isActive || !ProcessInfo.processInfo.isLowPowerModeEnabled { await rebuildIndex() }
                try? await Task.sleep(for: .seconds(30 * 60))
            }
        }
    }

    // MARK: - Rename presets

    /// Your saved renames (rename-presets.json); Scout's built-in ones come first in menus.
    private(set) var renamePresets: [RenamePreset] = ScoutStore.loadRenamePresets()

    func saveRenamePreset(name: String, pipeline: RenamePipeline) {
        if let index = renamePresets.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            renamePresets[index].pipeline = pipeline
        } else {
            renamePresets.append(RenamePreset(name: name, pipeline: pipeline))
        }
        try? ScoutStore.saveRenamePresets(renamePresets)
    }

    func deleteRenamePreset(_ id: UUID) {
        renamePresets.removeAll { $0.id == id }
        try? ScoutStore.saveRenamePresets(renamePresets)
    }

    // MARK: - Trusted git repositories

    private static let trustedReposKey = "trustedRepositories"

    func isTrustedRepository(_ root: String) -> Bool {
        (UserDefaults.standard.stringArray(forKey: Self.trustedReposKey) ?? []).contains(root)
    }

    func trustRepository(_ root: String) {
        var list = UserDefaults.standard.stringArray(forKey: Self.trustedReposKey) ?? []
        if !list.contains(root) { list.append(root) }
        UserDefaults.standard.set(list, forKey: Self.trustedReposKey)
    }

    // MARK: - Latest downloads (menu bar)

    /// The newest files in Downloads, for the menu bar icon's menu.
    private(set) var latestDownloads: [FileItem] = []
    @ObservationIgnored private var downloadsWatcher: DirectoryWatcher?

    /// Read off the main thread: on a first launch, macOS holds the read until you answer
    /// its "access your Downloads folder?" prompt, and the app must stay usable meanwhile.
    func refreshLatestDownloads() {
        let folder = home.appending(path: "Downloads", directoryHint: .isDirectory)
        Task {
            let latest = await Task.detached(priority: .utility) { () -> [FileItem]? in
                guard let urls = try? FileManager.default.contentsOfDirectory(
                    at: folder, includingPropertiesForKeys: [.addedToDirectoryDateKey], options: [.skipsHiddenFiles])
                else { return nil }
                func added(_ url: URL) -> Date {
                    (try? url.resourceValues(forKeys: [.addedToDirectoryDateKey]).addedToDirectoryDate) ?? .distantPast
                }
                let newest = urls.map { ($0, added($0)) }.sorted { $0.1 > $1.1 }.prefix(8)
                return newest.compactMap { LocalFileSource.item(for: $0.0) }
            }.value
            guard let latest else { return } // no access (yet)
            latestDownloads = latest
            if downloadsWatcher == nil {
                downloadsWatcher = DirectoryWatcher(url: folder) { [weak self] in self?.refreshLatestDownloads() }
            }
        }
    }

    // MARK: - Windows, links from outside, the global shortcut

    /// macOS only restores windows after a quit when "Close windows when quitting an app" is off
    /// (it's on by default), so Scout keeps the last window's tabs and split itself, like Finder.
    private static let sessionKey = "lastSession"
    @ObservationIgnored private var launchSessionTaken = false

    /// The saved session, handed to the first window of this launch only.
    func takeLaunchSession() -> WindowSession? {
        guard !launchSessionTaken else { return nil }
        launchSessionTaken = true
        return WindowSession(encoded: UserDefaults.standard.string(forKey: Self.sessionKey) ?? "")
    }

    func saveSession(_ session: WindowSession) {
        UserDefaults.standard.set(session.encoded, forKey: Self.sessionKey)
    }

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
        result.append(Place(url: home.appending(path: ".Trash", directoryHint: .isDirectory), name: "Trash", symbol: "trash"))
        return result
    }

    /// Unmounts a drive or share (it disappears from the sidebar when macOS confirms).
    func eject(_ place: Place) throws {
        try NSWorkspace.shared.unmountAndEjectDevice(at: place.url)
    }

    /// Permanently deletes what's in the Trash. Returns how many items couldn't be removed.
    @discardableResult
    /// Deletes everything in the Trash, off the main thread (it can hold huge folders).
    /// Returns how many items couldn't be removed.
    func emptyTrash() async -> Int {
        isEmptyingTrash = true
        defer { isEmptyingTrash = false }
        return await Self.removeTrashContents(home.appending(path: ".Trash"))
    }

    /// Shown while the Trash empties.
    private(set) var isEmptyingTrash = false

    @concurrent nonisolated private static func removeTrashContents(_ trash: URL) async -> Int {
        let items = (try? FileManager.default.contentsOfDirectory(at: trash, includingPropertiesForKeys: nil)) ?? []
        var failed = 0
        for item in items {
            do { try FileManager.default.removeItem(at: item) } catch { failed += 1 }
        }
        return failed
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
        let keys: [URLResourceKey] = [.volumeIsBrowsableKey, .volumeIsRootFileSystemKey, .volumeIsInternalKey,
                                      .volumeIsEjectableKey, .volumeIsRemovableKey, .volumeIsLocalKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        volumes = urls.compactMap { url in
            guard let v = try? url.resourceValues(forKeys: Set(keys)),
                  v.volumeIsBrowsable == true, v.volumeIsRootFileSystem != true else { return nil }
            let symbol = v.volumeIsLocal == false ? "server.rack" : v.volumeIsInternal == true ? "internaldrive" : "externaldrive"
            let ejectable = v.volumeIsEjectable == true || v.volumeIsRemovable == true || v.volumeIsInternal != true
            return Place(url: .folder(url.filePath), name: Self.volumeName(url) ?? url.lastPathComponent, symbol: symbol,
                         isEjectable: ejectable)
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
        // The list and the info panel often ask for the same folder at once: walk it once.
        if let running = sizeWalks[key] { return await running.value }
        let walk = Task { await Self.measure(url) }
        sizeWalks[key] = walk
        let size = await walk.value
        sizeWalks[key] = nil
        if sizeCache.count > 5_000 { sizeCache = sizeCache.filter { Date().timeIntervalSince($0.value.at) < 600 } }
        sizeCache[key] = (size, .now)
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
