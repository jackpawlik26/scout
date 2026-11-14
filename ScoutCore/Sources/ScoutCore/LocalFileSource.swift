import Foundation
import UniformTypeIdentifiers

/// Reads and changes files on this Mac.
public struct LocalFileSource: FileSource {
    public init() {}

    /// Cheap to read for every file.
    static let basicKeys: [URLResourceKey] = [
        .nameKey, .isDirectoryKey, .isPackageKey, .isHiddenKey, .isSymbolicLinkKey,
        .fileSizeKey, .contentModificationDateKey, .creationDateKey, .addedToDirectoryDateKey,
        .contentTypeKey,
    ]
    /// iCloud / OneDrive status: slow (about 50µs a file), so only read where files can sync.
    static let cloudKeys: [URLResourceKey] = [
        .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey, .ubiquitousItemIsDownloadingKey,
    ]
    static let resourceKeys = basicKeys + cloudKeys

    /// Lists a folder. Built to stay quick in folders with tens of thousands of items:
    /// slow attributes are skipped or shared, and files are read on several cores at once.
    public func contents(of folder: URL, includeHidden: Bool) async throws -> [FileItem] {
        let options: FileManager.DirectoryEnumerationOptions = includeHidden ? [] : [.skipsHiddenFiles]
        let cloud = Self.maySync(folder)
        let keys = cloud ? Self.resourceKeys : Self.basicKeys
        let urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: options)
        return Self.items(for: urls, cloud: cloud)
    }

    /// `FileItem`s for many URLs, read in parallel chunks (order kept, vanished files dropped).
    static func items(for urls: [URL], cloud: Bool) -> [FileItem] {
        guard urls.count > 256 else {
            let kinds = KindCache()
            return urls.compactMap { item(for: $0, cloud: cloud, kinds: kinds) }
        }
        let chunkCount = min(ProcessInfo.processInfo.activeProcessorCount * 2, 32)
        let chunkSize = (urls.count + chunkCount - 1) / chunkCount
        let results = ChunkResults(count: chunkCount)
        DispatchQueue.concurrentPerform(iterations: chunkCount) { chunk in
            let start = chunk * chunkSize
            guard start < urls.count else { return }
            let kinds = KindCache()
            let part = urls[start..<min(start + chunkSize, urls.count)].compactMap { item(for: $0, cloud: cloud, kinds: kinds) }
            results.set(chunk, part)
        }
        return results.joined
    }

    /// Whether files in this folder can be iCloud or cloud-storage (OneDrive, Dropbox…) files.
    static func maySync(_ folder: URL) -> Bool {
        let path = folder.filePath
        if path.contains("/Library/Mobile Documents/") || path.contains("/Library/CloudStorage/") { return true }
        return (try? folder.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem) == true
    }

    /// Builds a `FileItem` for one URL, or nil if it vanished.
    public static func item(for url: URL) -> FileItem? {
        item(for: url, cloud: true, kinds: KindCache())
    }

    static func item(for url: URL, cloud: Bool, kinds: KindCache) -> FileItem? {
        guard let v = try? url.resourceValues(forKeys: Set(cloud ? resourceKeys : basicKeys)) else { return nil }
        var isDirectory = v.isDirectory ?? false
        let isSymlink = v.isSymbolicLink ?? false
        // Finder treats a link to a folder like the folder itself.
        if isSymlink,
           let target = try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey]) {
            isDirectory = target.isDirectory ?? false
        }
        var item = FileItem(
            url: url,
            name: v.name ?? url.lastPathComponent,
            isDirectory: isDirectory,
            isPackage: v.isPackage ?? false,
            isHidden: v.isHidden ?? false,
            isSymlink: isSymlink,
            size: isDirectory ? nil : v.fileSize.map(Int64.init),
            dateModified: v.contentModificationDate,
            dateCreated: v.creationDate,
            dateAdded: v.addedToDirectoryDate,
            kind: kinds.kind(for: url, type: v.contentType),
            typeIdentifier: v.contentType?.identifier
        )
        #if canImport(Darwin)
        // Reading the tag attribute directly is several times faster than `.tagNamesKey`.
        item.tags = Tags.read(url)
        #endif
        if cloud, v.isUbiquitousItem == true {
            if v.ubiquitousItemIsDownloading == true {
                item.cloud = .downloading
            } else if let status = v.ubiquitousItemDownloadingStatus {
                item.cloud = status == .notDownloaded ? .online : .downloaded
            }
        }
        return item
    }

    // MARK: - Changing files

    public func createFolder(in parent: URL, named name: String) throws -> URL {
        try Self.validate(name)
        let url = Self.availableURL(in: parent, preferredName: name, isDirectory: true, style: .numbered)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    public func rename(_ url: URL, to newName: String) throws -> URL {
        try Self.validate(newName)
        let destination = url.deletingLastPathComponent().appending(path: newName)
        if destination.filePath == url.filePath { return url }
        // Allow case-only renames ("notes" → "Notes") on case-insensitive disks.
        let caseOnly = destination.filePath.lowercased() == url.filePath.lowercased()
        if !caseOnly, FileManager.default.fileExists(atPath: destination.filePath) {
            throw ScoutError.alreadyExists(newName)
        }
        try FileManager.default.moveItem(at: url, to: destination)
        return destination
    }

    public func trash(_ url: URL) throws -> URL? {
        var resulting: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
        return resulting as URL?
    }

    public func move(_ url: URL, to destination: URL) throws {
        try FileManager.default.moveItem(at: url, to: destination)
    }

    public func copy(_ url: URL, into folder: URL) throws -> URL {
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        let destination = Self.availableURL(
            in: folder, preferredName: url.lastPathComponent, isDirectory: isDir, style: .copy)
        try FileManager.default.copyItem(at: url, to: destination)
        return destination
    }

    public func move(_ url: URL, into folder: URL) throws -> URL {
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        let destination = Self.availableURL(
            in: folder, preferredName: url.lastPathComponent, isDirectory: isDir, style: .numbered)
        try FileManager.default.moveItem(at: url, to: destination)
        return destination
    }

    // MARK: - Naming

    public enum ConflictStyle: Sendable {
        /// "report.pdf" → "report copy.pdf" → "report copy 2.pdf"
        case copy
        /// "untitled folder" → "untitled folder 2"
        case numbered
    }

    /// The preferred name if it's free, otherwise the first free variation.
    public static func availableURL(
        in folder: URL, preferredName: String, isDirectory: Bool, style: ConflictStyle
    ) -> URL {
        let fm = FileManager.default
        let first = folder.appending(path: preferredName)
        if !fm.fileExists(atPath: first.filePath) { return first }

        let ext = isDirectory ? "" : (preferredName as NSString).pathExtension
        let stem = ext.isEmpty ? preferredName : (preferredName as NSString).deletingPathExtension
        func named(_ base: String) -> URL {
            folder.appending(path: ext.isEmpty ? base : "\(base).\(ext)")
        }

        var n = style == .copy ? 1 : 2
        while true {
            let base: String
            switch style {
            case .copy: base = n == 1 ? "\(stem) copy" : "\(stem) copy \(n)"
            case .numbered: base = "\(stem) \(n)"
            }
            let candidate = named(base)
            if !fm.fileExists(atPath: candidate.filePath) { return candidate }
            n += 1
        }
    }

    static func validate(_ name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { throw ScoutError.invalidName("A name can’t be empty.") }
        if name.contains("/") || name.contains(":") {
            throw ScoutError.invalidName("A name can’t contain “/” or “:”.")
        }
        if name == "." || name == ".." { throw ScoutError.invalidName("That name is reserved.") }
    }
}

/// "PDF document", "Folder"…: asked once per file type instead of once per file
/// (Finder's kind text is slow to look up). Not shared between threads.
final class KindCache {
    private var byType: [String: String] = [:]

    func kind(for url: URL, type: UTType?) -> String {
        guard let id = type?.identifier else {
            return (try? url.resourceValues(forKeys: [.localizedTypeDescriptionKey]).localizedTypeDescription) ?? ""
        }
        if let known = byType[id] { return known }
        let kind = (try? url.resourceValues(forKeys: [.localizedTypeDescriptionKey]).localizedTypeDescription) ?? ""
        byType[id] = kind
        return kind
    }
}

/// Collects each parallel chunk's items, then joins them in order.
private final class ChunkResults: @unchecked Sendable {
    private var parts: [[FileItem]]
    private let lock = NSLock()

    init(count: Int) { parts = Array(repeating: [], count: count) }

    func set(_ index: Int, _ items: [FileItem]) {
        lock.lock()
        parts[index] = items
        lock.unlock()
    }

    var joined: [FileItem] { parts.flatMap { $0 } }
}
