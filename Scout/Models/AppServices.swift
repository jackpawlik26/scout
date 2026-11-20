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
    /// Named window layouts (tabs and split), reopened from the sidebar or ⌥⌘1–9.
    private(set) var savedLayouts: [SavedLayout] = SavedLayout.load()
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

    // MARK: - Your fields

    func addField(_ field: FieldDefinition) {
        customizations.addField(field)
        try? ScoutStore.saveCustomizations(customizations)
    }

    func updateField(_ field: FieldDefinition) {
        customizations.updateField(field)
        try? ScoutStore.saveCustomizations(customizations)
        reloadFieldGroups()
    }

    func deleteField(_ id: String) {
        customizations.deleteField(id)
        try? ScoutStore.saveCustomizations(customizations)
        reloadFieldGroups()
    }

    /// Sets a field on files or folders (several at once from the info panel).
    func setFieldValue(_ value: String?, of fieldID: String, for paths: [String]) {
        for path in paths { customizations.setValue(value, of: fieldID, for: path) }
        try? ScoutStore.saveCustomizations(customizations)
        reloadFieldGroups()
    }

    /// Field groups list whatever has the value right now, so they reload when values change.
    private func reloadFieldGroups() {
        for window in windowModels.compactMap(\.model) {
            for pane in window.panes {
                for tab in pane.tabs where tab.fieldGroup != nil { Task { await tab.reload() } }
            }
        }
    }

    func togglePin(_ path: String) {
        customizations.togglePin(path)
        try? ScoutStore.saveCustomizations(customizations)
    }

    /// Your note on a file or folder, if any.
    func note(_ path: String) -> String? {
        customizations.style(for: path)?.note.flatMap { $0.isEmpty ? nil : $0 }
    }

    func setNote(_ path: String, _ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard note(path) ?? "" != trimmed else { return }
        customize(path) { $0.note = trimmed.isEmpty ? nil : trimmed }
    }

    /// Web links on a file or folder.
    func links(_ path: String) -> [ItemLink] { customizations.style(for: path)?.links ?? [] }

    /// Adds a link (skipping one that's already there). False when `text` isn't a web address.
    @discardableResult
    func addLink(_ text: String, title: String? = nil, to path: String) -> Bool {
        guard let link = ItemLink(text, title: title) else { return false }
        guard !links(path).contains(where: { $0.url == link.url }) else { return true }
        customize(path) { $0.links = ($0.links ?? []) + [link] }
        return true
    }

    func removeLink(_ link: ItemLink, from path: String) {
        customize(path) { style in
            style.links?.removeAll { $0.url == link.url }
            if style.links?.isEmpty == true { style.links = nil }
        }
    }

    func renameLink(_ link: ItemLink, to title: String, on path: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        customize(path) { style in
            guard let i = style.links?.firstIndex(where: { $0.url == link.url }) else { return }
            style.links?[i].title = trimmed
        }
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
        loadFileHistory()
        startImageTextIndex()
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

    /// The newest files in Downloads (up to 30), for the menu bar icon's menu (first 8) and
    /// the floating Downloads window.
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
                let newest = urls.map { ($0, added($0)) }.sorted { $0.1 > $1.1 }.prefix(30)
                return newest.compactMap { LocalFileSource.item(for: $0.0) }
            }.value
            guard let latest else { return } // no access (yet)
            latestDownloads = latest
            runTriageRules(on: Array(latest.prefix(8)))
            if downloadsWatcher == nil {
                downloadsWatcher = DirectoryWatcher(url: folder) { [weak self] in self?.refreshLatestDownloads() }
            }
        }
    }

    // MARK: - Triage rules

    /// "Always do this" rules from Triage: new downloads that match go to a folder on their own.
    private(set) var triageRules: [TriageRule] = ScoutStore.loadTriageRules()
    /// New downloads the rules already looked at (so a file you moved back isn't filed again).
    @ObservationIgnored private var triageSeen: Set<String> = []
    @ObservationIgnored private var triageRecheck: Task<Void, Never>?

    func addTriageRule(_ rule: TriageRule) {
        triageRules.removeAll { $0.id == rule.id }
        triageRules.append(rule)
        saveTriageRules()
    }

    func updateTriageRule(_ rule: TriageRule) {
        guard let index = triageRules.firstIndex(where: { $0.id == rule.id }) else { return }
        triageRules[index] = rule
        saveTriageRules()
    }

    func removeTriageRule(_ id: UUID) {
        triageRules.removeAll { $0.id == id }
        saveTriageRules()
    }

    private func saveTriageRules() { try? ScoutStore.saveTriageRules(triageRules) }

    /// Files new downloads that match a rule. Only files that just arrived and have finished
    /// downloading; each file is looked at once. Logged in History (as "Filed by a rule"), so
    /// it can be undone there.
    private func runTriageRules(on latest: [FileItem]) {
        guard triageRules.contains(where: \.isEnabled) else { return }
        let now = Date()
        var waiting = false
        var filed: [(rule: TriageRule, move: (URL, URL))] = []
        for item in latest where !triageSeen.contains(item.path) {
            guard TriageRule.isReady(item, now: now) else {
                // Just arrived or still being written: look again shortly.
                if let added = item.dateAdded, now.timeIntervalSince(added) < 60 { waiting = true }
                continue
            }
            triageSeen.insert(item.path)
            guard let rule = TriageRule.first(triageRules, matching: item.name, site: item.source?.site) else { continue }
            let folder = URL.folder(rule.destination)
            guard FileManager.default.fileExists(atPath: folder.filePath),
                  let moved = try? fileSource.move(item.url, into: folder) else { continue }
            filed.append((rule, (item.url, moved)))
        }
        for (rule, move) in filed { recordFiles(.rule, [move], note: rule.name) }
        if !filed.isEmpty {
            for model in windowModels.compactMap(\.model) {
                for tab in model.panes.flatMap(\.tabs) { Task { await tab.reload() } }
            }
        }
        if waiting {
            triageRecheck?.cancel()
            triageRecheck = Task { [weak self] in
                try? await Task.sleep(for: .seconds(6))
                guard !Task.isCancelled else { return }
                self?.refreshLatestDownloads()
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

    /// A favorite or a location (a disk, iCloud Drive, the Trash): never moved by a sidebar drop.
    func isSidebarPlace(_ path: String) -> Bool { isFavorite(path) || locations.contains { $0.id == path } }

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

    // MARK: - Saved layouts

    @discardableResult
    func saveLayout(name: String, session: WindowSession) -> SavedLayout {
        let layout = SavedLayout(name: name, session: session)
        savedLayouts.append(layout)
        SavedLayout.save(savedLayouts)
        return layout
    }

    /// Replaces a layout's tabs and split with the window's current ones.
    func updateLayout(_ id: UUID, session: WindowSession) {
        guard let i = savedLayouts.firstIndex(where: { $0.id == id }) else { return }
        savedLayouts[i].session = session
        SavedLayout.save(savedLayouts)
    }

    func deleteLayout(_ id: UUID) {
        savedLayouts.removeAll { $0.id == id }
        SavedLayout.save(savedLayouts)
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

    // MARK: - Text in images (⌘K finds screenshots by what they say)

    /// What Vision read from images in Desktop, Documents, Downloads and Pictures.
    @ObservationIgnored private(set) var imageText = ImageTextIndex()
    @ObservationIgnored private var imageTextSearch: SpotlightSearch?

    /// Images whose text contains every word of `query`, newest first.
    func imageTextMatches(_ query: String) -> [FileHit] {
        imageText.matches(query).map { path in
            FileHit(path: path, name: (path as NSString).lastPathComponent,
                    modified: imageText.entries[path]?.modified, contentType: "public.image")
        }
    }

    /// Loads what was read before, then reads new and changed images in the background, a
    /// few minutes after launch and at low priority. Images only in iCloud or OneDrive are
    /// skipped (reading them would download them).
    private func startImageTextIndex() {
        Task { [weak self] in
            guard let self else { return }
            imageText = await Task.detached(priority: .utility) { ImageTextIndex.load() }.value
            try? await Task.sleep(for: .seconds(120))
            let roots = ["Desktop", "Documents", "Downloads", "Pictures"].map { URL.folder(homePath + "/" + $0) }
            let home = homePath
            imageTextSearch = SpotlightSearch(
                queryString: #"kMDItemContentTypeTree == "public.image" && kMDItemFSSize < 26214400"#,
                scopes: roots, live: false, newestFirst: true
            ) { hits in
                hits.filter { !FileHitRanker.isNoise($0.path, home: home) }.prefix(ImageTextIndex.maxImages).map { $0 }
            } onResults: { [weak self] hits, finished in
                guard finished, let self else { return }
                self.imageTextSearch = nil
                Task { await self.readImages(hits) }
            }
        }
    }

    private func readImages(_ hits: [FileHit]) async {
        var index = imageText
        index.keep(only: Set(hits.map(\.path)))
        let pending = hits.filter { hit in index.needsReading(hit.path, modified: hit.modified ?? .distantPast) }
        let total = await Task.detached(priority: .background) { () -> ImageTextIndex in
            var index = index
            for (count, hit) in pending.enumerated() {
                let url = URL(filePath: hit.path)
                guard Self.isOnDisk(url) else { continue }
                let text = await OnDeviceAI.imageText(url, fast: true) ?? ""
                index.set(hit.path, modified: hit.modified ?? .distantPast, text: text)
                if count % 200 == 199 { try? index.save() }
            }
            try? index.save()
            return index
        }.value
        imageText = total
    }

    /// False for iCloud / OneDrive files that are only in the cloud.
    nonisolated static func isOnDisk(_ url: URL) -> Bool {
        let path = url.filePath
        guard path.contains("/Library/Mobile Documents/") || path.contains("/Library/CloudStorage/") else { return true }
        let status = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]).ubiquitousItemDownloadingStatus
        return status == nil || status == .current || status == .downloaded
    }

    // MARK: - Buckets (S3, Cloudflare R2…)

    private(set) var buckets: [BucketConfig] = ScoutStore.loadBuckets()
    /// Bumped after uploads and deletes, so bucket pages reload.
    private(set) var bucketRevision = 0

    func client(for id: UUID) -> S3Client? {
        guard let config = buckets.first(where: { $0.id == id }), let secret = Keychain.get(id.uuidString) else { return nil }
        return S3Client(config: config, secretKey: secret)
    }

    func saveBucket(_ config: BucketConfig, secret: String) {
        Keychain.set(secret, for: config.id.uuidString)
        buckets.removeAll { $0.id == config.id }
        buckets.append(config)
        try? ScoutStore.saveBuckets(buckets)
    }

    func removeBucket(_ id: UUID) {
        Keychain.delete(id.uuidString)
        buckets.removeAll { $0.id == id }
        try? ScoutStore.saveBuckets(buckets)
    }

    func bucketChanged() { bucketRevision += 1 }

    /// Uploads files (folders: everything inside, keeping their structure) under `prefix`,
    /// with progress on the transfer card.
    func upload(_ urls: [URL], to id: UUID, prefix: String) {
        guard let client = client(for: id) else { return }
        let files = urls.flatMap { url -> [(URL, String)] in
            let base = url.deletingLastPathComponent().filePath.count + 1
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.filePath, isDirectory: &isDir) else { return [] }
            if !isDir.boolValue { return [(url, prefix + url.lastPathComponent)] }
            let inside = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey],
                                                        options: [.skipsHiddenFiles])?.compactMap { $0 as? URL } ?? []
            return inside.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
                .map { ($0, prefix + String($0.filePath.dropFirst(base))) }
        }
        guard !files.isEmpty else { return }
        let total = files.reduce(Int64(0)) { $0 + FileCopier.totalBytes($1.0) }
        let transfer = Transfer(title: "Uploading \(files.count == 1 ? "“\(files[0].0.lastPathComponent)”" : "\(files.count) files") to \(client.config.name)",
                                totalBytes: total)
        begin(transfer)
        Task {
            var done: Int64 = 0
            var errors: [String] = []
            for (file, key) in files where !transfer.isCancelled {
                transfer.set(current: file.lastPathComponent)
                do {
                    try await client.upload(file, as: key)
                    done += FileCopier.totalBytes(file)
                    transfer.set(done: done)
                } catch {
                    errors.append("\(file.lastPathComponent): \(error.localizedDescription)")
                }
            }
            end(transfer)
            bucketChanged()
            if !errors.isEmpty { frontWindow?.current.alertMessage = errors.prefix(5).joined(separator: "\n") }
        }
    }

    // MARK: - Files opened through Scout (for "Related")

    @ObservationIgnored private(set) lazy var openLog = OpenLog.load()
    @ObservationIgnored private var openLogSave: Task<Void, Never>?

    func recordOpen(_ url: URL) {
        openLog.record(url.filePath)
        openLogSave?.cancel()
        let snapshot = openLog
        openLogSave = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await Task.detached(priority: .utility) { try? snapshot.save() }.value
        }
    }

    // MARK: - File history

    /// Everything Scout moved, copied, renamed or trashed (the History page). Loaded in
    /// the background at launch.
    private(set) var fileHistory = FileHistory()
    /// Reads and writes `file-history.jsonl` in order, off the main thread.
    @ObservationIgnored private let fileHistoryQueue = DispatchQueue(label: "Scout file history", qos: .utility)

    private func loadFileHistory() {
        fileHistoryQueue.async { [weak self] in
            var loaded = FileHistoryStore.load()
            if loaded.prune() { try? FileHistoryStore.save(loaded) }
            let entries = loaded.entries
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    // Anything recorded while loading goes after what was on disk.
                    self.fileHistory = FileHistory(entries: entries + self.fileHistory.entries)
                }
            }
        }
    }

    /// Records what Scout just did to some files and returns the entry's id (for undo).
    @discardableResult
    func recordFiles(_ action: FileAction, _ moves: [(URL, URL)], undoes: UUID? = nil, note: String? = nil) -> UUID? {
        guard !moves.isEmpty else { return nil }
        // Where each file was downloaded from, so triage can learn "files from this site go here".
        let changes = moves.map { move in
            FileChange(move, site: action == .undo ? nil : DownloadSource.read(move.1)?.site)
        }
        let entry = FileHistoryEntry(action: action, changes: changes, undoes: undoes, note: note)
        fileHistory.append(entry)
        // Notes, nicknames, colors and pins follow what moved (a copy leaves the original's in place).
        if action != .copy {
            let before = customizations
            for change in changes { customizations.moved(from: change.from, to: change.to) }
            if customizations != before { try? ScoutStore.saveCustomizations(customizations) }
        }
        fileHistoryQueue.async { try? FileHistoryStore.append(entry) }
        return entry.id
    }

    /// Forgets everything on the History page.
    func clearFileHistory() {
        fileHistory = FileHistory()
        fileHistoryQueue.async { try? FileHistoryStore.save(FileHistory()) }
    }

    /// When you last opened a folder before now, if Scout remembers (for "new since your last visit").
    func lastVisit(_ path: String) -> Date? {
        frecency.entries[path]?.last
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
