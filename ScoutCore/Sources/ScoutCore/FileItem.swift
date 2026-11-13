import Foundation

/// One file or folder as Scout shows it.
///
/// Plain data on purpose: today it comes from the local disk, later it could come
/// from a Scout server over the network.
public struct FileItem: Identifiable, Hashable, Sendable {
    public var id: URL { url }

    public let url: URL
    public let name: String
    /// True for folders, and for packages such as `.app` bundles.
    public let isDirectory: Bool
    public let isPackage: Bool
    public let isHidden: Bool
    public let isSymlink: Bool
    /// Byte size for files; nil for folders.
    public let size: Int64?
    public let dateModified: Date?
    public let dateCreated: Date?
    public let dateAdded: Date?
    /// Human-readable kind, e.g. "PDF document".
    public let kind: String
    /// Uniform type identifier, e.g. "com.adobe.pdf".
    public let typeIdentifier: String?
    /// For folders: everything inside, once measured (filled in after the listing loads).
    public var folderBytes: Int64?
    /// When you last opened it (or added it, for new downloads), when known (Recents).
    public var lastOpened: Date?
    /// Finder tags (colored labels).
    public var tags: [FileTag] = []
    /// For iCloud / OneDrive / other cloud files: whether it's on this Mac.
    public var cloud: CloudState?

    public init(
        url: URL,
        name: String,
        isDirectory: Bool,
        isPackage: Bool = false,
        isHidden: Bool = false,
        isSymlink: Bool = false,
        size: Int64? = nil,
        dateModified: Date? = nil,
        dateCreated: Date? = nil,
        dateAdded: Date? = nil,
        kind: String = "",
        typeIdentifier: String? = nil
    ) {
        self.url = url
        self.name = name
        self.isDirectory = isDirectory
        self.isPackage = isPackage
        self.isHidden = isHidden
        self.isSymlink = isSymlink
        self.size = size
        self.dateModified = dateModified
        self.dateCreated = dateCreated
        self.dateAdded = dateAdded
        self.kind = kind
        self.typeIdentifier = typeIdentifier
    }

    /// Folders you can step into. Apps and other packages open instead.
    public var isNavigable: Bool { isDirectory && !isPackage }

    public var path: String { url.filePath }

    // Non-optional keys so table columns can sort on them.
    public var sizeSortKey: Int64 { size ?? folderBytes ?? -1 }
    public var modifiedSortKey: Date { dateModified ?? .distantPast }
    public var createdSortKey: Date { dateCreated ?? .distantPast }
    public var addedSortKey: Date { dateAdded ?? .distantPast }
}

/// Where a cloud file's contents are.
public enum CloudState: Sendable, Hashable {
    /// Only in the cloud (downloads when opened).
    case online
    case downloading
    /// On this Mac.
    case downloaded
}

public extension URL {
    /// The file system path without a trailing slash (except for "/").
    var filePath: String {
        var p = path(percentEncoded: false)
        if p.count > 1, p.hasSuffix("/") { p.removeLast() }
        return p
    }

    /// A folder URL built from a path, so equal paths give equal URLs.
    static func folder(_ path: String) -> URL {
        URL(filePath: path, directoryHint: .isDirectory)
    }
}
