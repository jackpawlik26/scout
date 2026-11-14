import Foundation

/// Scout's files in ~/Library/Application Support/Scout, shared by the app, the
/// `scout` command-line tool and the Raycast extension.
///
/// - `folders.txt`: the ⌘K folder index, one path per line.
/// - `history.json`: folder visits (`{"entries": {"/path": ["2026-11-13T17:00:00Z", …]}}`).
public enum ScoutStore {
    public static var directory: URL {
        URL.applicationSupportDirectory.appending(path: "Scout", directoryHint: .isDirectory)
    }
    public static var historyURL: URL { directory.appending(path: "history.json") }
    public static var foldersURL: URL { directory.appending(path: "folders.txt") }
    public static var savedSearchesURL: URL { directory.appending(path: "saved-searches.json") }
    public static var workspacesURL: URL { directory.appending(path: "workspaces.json") }
    public static var favoritesURL: URL { directory.appending(path: "favorites.json") }
    public static var customizationsURL: URL { directory.appending(path: "customizations.json") }
    public static var renamePresetsURL: URL { directory.appending(path: "rename-presets.json") }

    public static func loadCustomizations(from url: URL = customizationsURL) -> Customizations {
        guard let data = try? Data(contentsOf: url) else { return Customizations() }
        return (try? JSONDecoder().decode(Customizations.self, from: data)) ?? Customizations()
    }

    public static func saveCustomizations(_ value: Customizations, to url: URL = customizationsURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    /// Pinned sidebar favorites (paths, in order). Nil until you change them.
    public static func loadFavorites(from url: URL = favoritesURL) -> [String]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([String].self, from: data)
    }

    public static func saveFavorites(_ paths: [String], to url: URL = favoritesURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        try encoder.encode(paths).write(to: url, options: .atomic)
    }

    // MARK: Workspaces

    public static func loadWorkspaces(from url: URL = workspacesURL) -> [Workspace] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Workspace].self, from: data)) ?? []
    }

    public static func saveWorkspaces(_ workspaces: [Workspace], to url: URL = workspacesURL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try write(encoder.encode(workspaces), to: url)
    }

    // MARK: Rename presets

    public static func loadRenamePresets(from url: URL = renamePresetsURL) -> [RenamePreset] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([RenamePreset].self, from: data)) ?? []
    }

    public static func saveRenamePresets(_ presets: [RenamePreset], to url: URL = renamePresetsURL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try write(encoder.encode(presets), to: url)
    }

    // MARK: Saved searches

    public static func loadSavedSearches(from url: URL = savedSearchesURL) -> [SavedSearch] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([SavedSearch].self, from: data)) ?? []
    }

    public static func saveSavedSearches(_ searches: [SavedSearch], to url: URL = savedSearchesURL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try write(encoder.encode(searches), to: url)
    }

    // MARK: History

    public static func loadHistory(from url: URL = historyURL) -> FrecencyLog {
        guard let data = try? Data(contentsOf: url) else { return FrecencyLog() }
        let iso = JSONDecoder()
        iso.dateDecodingStrategy = .iso8601
        if let log = try? iso.decode(FrecencyLog.self, from: data) { return log }
        // Files from Scout 0.1 used Apple's default date format.
        return (try? JSONDecoder().decode(FrecencyLog.self, from: data)) ?? FrecencyLog()
    }

    public static func saveHistory(_ log: FrecencyLog, to url: URL = historyURL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try write(encoder.encode(log), to: url)
    }

    // MARK: Folder index

    /// Nil when Scout hasn't built an index yet.
    public static func loadFolders(home: String, from url: URL = foldersURL) -> [IndexedFolder]? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return text.split(separator: "\n").map { IndexedFolder(path: String($0), home: home) }
    }

    public static func saveFolders(_ folders: [IndexedFolder], to url: URL = foldersURL) throws {
        try write(Data(folders.map(\.path).joined(separator: "\n").utf8), to: url)
    }

    public static func indexDate(of url: URL = foldersURL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    /// Folders worth indexing: home, iCloud Drive, and cloud drives (OneDrive, Google Drive…).
    public static func defaultIndexRoots(home: String) -> [URL] {
        let fm = FileManager.default
        var roots = [URL.folder(home)]
        let iCloud = home + "/Library/Mobile Documents/com~apple~CloudDocs"
        if fm.fileExists(atPath: iCloud) { roots.append(.folder(iCloud)) }
        let cloudStorage = home + "/Library/CloudStorage"
        for name in ((try? fm.contentsOfDirectory(atPath: cloudStorage)) ?? []).sorted() where !name.hasPrefix(".") {
            roots.append(.folder(cloudStorage + "/" + name))
        }
        return roots
    }

    private static func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
