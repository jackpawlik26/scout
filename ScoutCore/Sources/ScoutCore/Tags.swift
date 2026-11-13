import Foundation

/// A Finder tag: a name and one of Finder's colors. Stored the way Finder stores them
/// (the `_kMDItemUserTags` extended attribute), so both apps see the same tags.
public struct FileTag: Hashable, Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    /// Finder's color number: 0 none, 1 gray, 2 green, 3 purple, 4 blue, 5 yellow, 6 red, 7 orange.
    public let color: Int

    public init(name: String, color: Int) {
        self.name = name
        self.color = color
    }

    /// Finder's built-in color tags, in Finder's menu order.
    public static let standard: [FileTag] = [
        FileTag(name: "Red", color: 6), FileTag(name: "Orange", color: 7), FileTag(name: "Yellow", color: 5),
        FileTag(name: "Green", color: 2), FileTag(name: "Blue", color: 4), FileTag(name: "Purple", color: 3),
        FileTag(name: "Gray", color: 1),
    ]
}

#if canImport(Darwin)
public enum Tags {
    static let attribute = "com.apple.metadata:_kMDItemUserTags"

    /// The tags on a file or folder (empty when it has none).
    public static func read(_ url: URL) -> [FileTag] {
        let size = getxattr(url.filePath, attribute, nil, 0, 0, XATTR_NOFOLLOW)
        guard size > 0 else { return [] }
        var data = Data(count: size)
        let read = data.withUnsafeMutableBytes { getxattr(url.filePath, attribute, $0.baseAddress, size, 0, XATTR_NOFOLLOW) }
        guard read == size,
              let list = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String] else { return [] }
        return list.map(parse)
    }

    /// Replaces the tags on a file or folder (an empty list removes them).
    public static func write(_ tags: [FileTag], to url: URL) throws {
        if tags.isEmpty {
            if removexattr(url.filePath, attribute, XATTR_NOFOLLOW) != 0, errno != ENOATTR { throw posixError() }
            return
        }
        let list = tags.map { $0.color == 0 ? $0.name : "\($0.name)\n\($0.color)" }
        let data = try PropertyListSerialization.data(fromPropertyList: list, format: .binary, options: 0)
        let result = data.withUnsafeBytes { setxattr(url.filePath, attribute, $0.baseAddress, data.count, 0, XATTR_NOFOLLOW) }
        if result != 0 { throw posixError() }
    }

    /// Adds or removes one tag on several items. Adds it if any of them lacks it.
    public static func toggle(_ tag: FileTag, on urls: [URL]) throws {
        let current = urls.map(read)
        let add = current.contains { !$0.contains { $0.name == tag.name } }
        for (url, tags) in zip(urls, current) {
            var updated = tags.filter { $0.name != tag.name }
            if add { updated.append(tag) }
            try write(updated, to: url)
        }
    }

    /// "Work\n6" → Work, red. Untagged colors come in as plain names.
    public static func parse(_ entry: String) -> FileTag {
        let parts = entry.split(separator: "\n", maxSplits: 1)
        let name = String(parts.first ?? "")
        let color = parts.count > 1 ? Int(parts[1]) ?? 0 : (FileTag.standard.first { $0.name == name }?.color ?? 0)
        return FileTag(name: name, color: color)
    }

    private static func posixError() -> Error { NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
}
#endif
