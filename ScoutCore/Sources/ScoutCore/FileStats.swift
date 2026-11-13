import Foundation
import UniformTypeIdentifiers

/// Broad buckets for "what takes the space" breakdowns.
public enum FileCategory: String, CaseIterable, Sendable, Hashable {
    case folders, documents, images, videos, audio, archives, apps, code, other

    public var title: String {
        switch self {
        case .folders: "Folders"
        case .documents: "Documents"
        case .images: "Images"
        case .videos: "Videos"
        case .audio: "Audio"
        case .archives: "Archives & Installers"
        case .apps: "Apps"
        case .code: "Code"
        case .other: "Other"
        }
    }

    public static func of(_ item: FileItem) -> FileCategory {
        if item.isNavigable { return .folders }
        return of(type: item.typeIdentifier.flatMap(UTType.init))
    }

    public static func of(type: UTType?) -> FileCategory {
        guard let type else { return .other }
        if type.conforms(to: .applicationBundle) { return .apps }
        if type.conforms(to: .image) { return .images }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .videos }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .archive) || type.conforms(to: .diskImage) || type.identifier == "com.apple.installer-package-archive" {
            return .archives
        }
        if type.conforms(to: .sourceCode) || type.conforms(to: .script) || type.conforms(to: .json) || type.conforms(to: .yaml) {
            return .code
        }
        if type.conforms(to: .pdf) || type.conforms(to: .text) || type.conforms(to: .presentation)
            || type.conforms(to: .spreadsheet) || type.conforms(to: .compositeContent) || type.conforms(to: .epub) {
            return .documents
        }
        return .other
    }
}

public enum FolderStats {
    public struct Size: Sendable, Equatable {
        public let bytes: Int64
        public let files: Int
        /// True when we stopped early (very large folder); `bytes` is then a lower bound.
        public let isPartial: Bool
        /// Bytes by kind of file, for "what takes the space".
        public var byCategory: [FileCategory: Int64] = [:]
    }

    /// Total size on disk of everything inside a folder, split by kind of file.
    /// Stops after `fileLimit` files so huge folders don't spin forever.
    /// Files inside packages (like .app bundles) count toward the package's kind.
    public static func size(of folder: URL, fileLimit: Int = 200_000) -> Size {
        let keys: [URLResourceKey] = [
            .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey, .isPackageKey, .contentTypeKey,
        ]
        guard let walker = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }
        ) else { return Size(bytes: 0, files: 0, isPartial: false) }

        var bytes: Int64 = 0
        var files = 0
        var byCategory: [FileCategory: Int64] = [:]
        var package: (prefix: String, category: FileCategory)?

        while let url = walker.nextObject() as? URL {
            if Task.isCancelled || files >= fileLimit {
                return Size(bytes: bytes, files: files, isPartial: true, byCategory: byCategory)
            }
            guard let v = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            let path = url.filePath
            if let current = package, !path.hasPrefix(current.prefix) { package = nil }
            if package == nil, v.isPackage == true {
                package = (path + "/", FileCategory.of(type: v.contentType))
                continue
            }
            guard v.isRegularFile == true else { continue }
            let size = Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
            bytes += size
            files += 1
            byCategory[package?.category ?? FileCategory.of(type: v.contentType), default: 0] += size
        }
        return Size(bytes: bytes, files: files, isPartial: false, byCategory: byCategory)
    }

    /// Number of visible items directly inside a folder.
    public static func itemCount(of folder: URL) -> Int? {
        try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ).count
    }

    /// Bytes per kind of file, biggest first. Subfolders contribute what's inside
    /// them (from `folderBreakdowns`) rather than counting as "Folders".
    public static func breakdown(_ items: [FileItem],
                                 folderBreakdowns: [URL: [FileCategory: Int64]] = [:]) -> [(FileCategory, Int64)] {
        var totals: [FileCategory: Int64] = [:]
        for item in items {
            if item.isNavigable {
                for (category, bytes) in folderBreakdowns[item.url] ?? [:] { totals[category, default: 0] += bytes }
            } else {
                totals[FileCategory.of(item), default: 0] += item.size ?? 0
            }
        }
        return totals.filter { $0.value > 0 }.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key.rawValue < $1.key.rawValue }
    }
}
