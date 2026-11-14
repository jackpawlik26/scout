import CryptoKit
import Foundation

/// Compares two folders (split view's panes) file by file, including subfolders, and plans
/// a one-way sync. Used for backups, USB drives and copies of projects.
public enum FolderCompare {
    public enum Status: String, Sendable, CaseIterable {
        case onlyLeft, onlyRight, leftNewer, rightNewer, different, same

        public var title: String {
            switch self {
            case .onlyLeft: "Only on the left"
            case .onlyRight: "Only on the right"
            case .leftNewer: "Newer on the left"
            case .rightNewer: "Newer on the right"
            case .different: "Different"
            case .same: "Same"
            }
        }
    }

    public struct FileInfo: Sendable, Equatable {
        public let size: Int64
        public let modified: Date
    }

    public struct Entry: Sendable, Identifiable, Equatable {
        public var id: String { path }
        /// Relative to both folders: "Photos/2026/a.jpg".
        public let path: String
        public let status: Status
        public let left: FileInfo?
        public let right: FileInfo?
    }

    /// Files are "the same age" within this many seconds (FAT drives store 2-second times).
    static let timeSlack: TimeInterval = 2
    public static let maxFiles = 100_000

    /// Every file under each folder, by relative path. Skips hidden files, package insides,
    /// and folders like node_modules and .git.
    static func files(in root: URL, isCancelled: () -> Bool) -> [String: FileInfo] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        // Relative URLs: "Sub/a.txt" whatever path the root was reached by (/var vs /private/var).
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants, .producesRelativePathURLs])
        else { return [:] }
        var result: [String: FileInfo] = [:]
        for case let url as URL in enumerator {
            if isCancelled() || result.count >= maxFiles { break }
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if values.isDirectory == true {
                if DuplicateFinder.skippedFolderNames.contains(url.lastPathComponent) { enumerator.skipDescendants() }
                continue
            }
            guard values.isRegularFile == true else { continue }
            let path = url.relativePath
            result[path] = FileInfo(size: Int64(values.fileSize ?? 0), modified: values.contentModificationDate ?? .distantPast)
        }
        return result
    }

    /// Compares by size and date; with `checkContents`, files whose dates differ but sizes
    /// match are read to see if they really differ (slower, but no false "newer").
    public static func compare(_ left: URL, _ right: URL, checkContents: Bool = false,
                               isCancelled: () -> Bool = { false }) -> [Entry] {
        let l = files(in: left, isCancelled: isCancelled)
        let r = files(in: right, isCancelled: isCancelled)
        var entries: [Entry] = []
        for path in Set(l.keys).union(r.keys) {
            if isCancelled() { return [] }
            let a = l[path], b = r[path]
            let status: Status
            switch (a, b) {
            case (_?, nil): status = .onlyLeft
            case (nil, _?): status = .onlyRight
            case let (a?, b?):
                let gap = a.modified.timeIntervalSince(b.modified)
                if a.size == b.size, abs(gap) <= timeSlack {
                    status = .same
                } else if checkContents, a.size == b.size,
                          sameContents(left.appending(path: path), right.appending(path: path)) {
                    status = .same
                } else if abs(gap) <= timeSlack {
                    status = .different
                } else {
                    status = gap > 0 ? .leftNewer : .rightNewer
                }
            case (nil, nil): continue
            }
            entries.append(Entry(path: path, status: status, left: a, right: b))
        }
        return entries.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    static func sameContents(_ a: URL, _ b: URL) -> Bool {
        guard let x = digest(a), let y = digest(b) else { return false }
        return x == y
    }

    static func digest(_ url: URL) -> SHA256.Digest? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize()
    }

    // MARK: - Sync

    public struct SyncPlan: Equatable, Sendable {
        /// Relative paths to copy from the source side (new there, or newer, or different).
        public var copy: [String]
        /// Of those, the ones that replace a file on the other side (it goes to the Trash first).
        public var replace: [String]
        /// Files only on the other side, moved to the Trash when mirroring.
        public var trash: [String]

        public var isEmpty: Bool { copy.isEmpty && trash.isEmpty }
    }

    /// What a one-way sync would do. `leftToRight`: the left folder wins. Files that are newer on
    /// the receiving side are left alone (never overwrite newer work). `mirror` also trashes files
    /// that only exist on the receiving side.
    public static func plan(_ entries: [Entry], leftToRight: Bool, mirror: Bool) -> SyncPlan {
        let onlySource: Status = leftToRight ? .onlyLeft : .onlyRight
        let sourceNewer: Status = leftToRight ? .leftNewer : .rightNewer
        let onlyTarget: Status = leftToRight ? .onlyRight : .onlyLeft
        var plan = SyncPlan(copy: [], replace: [], trash: [])
        for entry in entries {
            switch entry.status {
            case onlySource: plan.copy.append(entry.path)
            case sourceNewer, .different:
                plan.copy.append(entry.path)
                plan.replace.append(entry.path)
            case onlyTarget where mirror: plan.trash.append(entry.path)
            default: break
            }
        }
        return plan
    }
}
