import Foundation
import UniformTypeIdentifiers

/// Reads and changes files on this Mac.
public struct LocalFileSource: FileSource {
    public init() {}

    static let resourceKeys: [URLResourceKey] = [
        .nameKey, .isDirectoryKey, .isPackageKey, .isHiddenKey, .isSymbolicLinkKey,
        .fileSizeKey, .contentModificationDateKey, .creationDateKey, .addedToDirectoryDateKey,
        .localizedTypeDescriptionKey, .contentTypeKey, .tagNamesKey,
    ]

    public func contents(of folder: URL, includeHidden: Bool) async throws -> [FileItem] {
        let options: FileManager.DirectoryEnumerationOptions = includeHidden ? [] : [.skipsHiddenFiles]
        let urls = try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: Self.resourceKeys, options: options)
        return urls.compactMap(Self.item(for:))
    }

    /// Builds a `FileItem` for one URL, or nil if it vanished.
    public static func item(for url: URL) -> FileItem? {
        guard let v = try? url.resourceValues(forKeys: Set(resourceKeys)) else { return nil }
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
            kind: v.localizedTypeDescription ?? "",
            typeIdentifier: v.contentType?.identifier
        )
        #if canImport(Darwin)
        if v.tagNames?.isEmpty == false { item.tags = Tags.read(url) }
        #endif
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
