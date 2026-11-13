import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// Files with exactly the same contents. `paths[0]` is the one to keep.
public struct DuplicateGroup: Equatable, Sendable {
    public let paths: [String]
    public let size: Int64

    /// Space you'd get back by keeping only the first.
    public var wasted: Int64 { size * Int64(paths.count - 1) }
}

public enum DuplicateFinder {
    /// Folders never worth scanning: build output, dependencies, version control.
    public static let skippedFolderNames: Set<String> = [
        "node_modules", ".git", "build", ".build", "DerivedData", "dist", "Pods", "venv", ".venv",
        "__pycache__", "target", ".next", ".cache",
    ]

    struct Candidate {
        let path: String
        let size: Int64
        let created: Date?
        /// APFS clones share one of these (and share their disk space, so aren't waste).
        let contentID: AnyHashable?
        /// Hard links share this.
        let fileID: AnyHashable?
    }

    /// Finds duplicates among files of at least `minimumSize` bytes under `roots`.
    /// Skips hidden files, app/package insides, cloud files that aren't downloaded, and `skippedFolderNames`.
    /// Biggest waste first.
    public static func find(in roots: [URL], minimumSize: Int64 = 1_000_000,
                            isCancelled: () -> Bool = { false }) -> [DuplicateGroup] {
        // 1. Group by size: files of different sizes can't match.
        var bySize: [Int64: [Candidate]] = [:]
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .creationDateKey, .fileContentIdentifierKey,
                                      .fileResourceIdentifierKey, .isDirectoryKey, .isUbiquitousItemKey,
                                      .ubiquitousItemDownloadingStatusKey]
        for root in roots where !shouldSkipFolder(root) {
            guard let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in enumerator {
                if isCancelled() { return [] }
                guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
                if values.isDirectory == true {
                    if shouldSkipFolder(url) { enumerator.skipDescendants() }
                    continue
                }
                guard values.isRegularFile == true, let size = values.fileSize.map(Int64.init), size >= minimumSize,
                      !isDataless(url, values) else { continue }
                bySize[size, default: []].append(Candidate(
                    path: url.filePath, size: size, created: values.creationDate,
                    contentID: values.allValues[.fileContentIdentifierKey] as? AnyHashable,
                    fileID: values.fileResourceIdentifier as? AnyHashable))
            }
        }

        var groups: [DuplicateGroup] = []
        for (_, sameSize) in bySize where sameSize.count > 1 {
            // Hard links and clones are the same data stored once: count each once.
            let distinct = unique(sameSize)
            guard distinct.count > 1 else { continue }
            // 2. Cheap check (start and end of each file), 3. then the full contents.
            // Unreadable files (nil hash) are left out rather than lumped together.
            let sampled = distinct.compactMap { file in sampleHash(file.path).map { (file, $0) } }
            for quick in Dictionary(grouping: sampled, by: \.1).values where quick.count > 1 {
                if isCancelled() { return [] }
                let hashed = quick.compactMap { file, _ in fullHash(file.path).map { (file, $0) } }
                for full in Dictionary(grouping: hashed, by: \.1).values where full.count > 1 {
                    let paths = keeperOrder(full.map { ($0.0.path, $0.0.created) })
                    groups.append(DuplicateGroup(paths: paths, size: full[0].0.size))
                }
            }
        }
        return groups.sorted { $0.wasted != $1.wasted ? $0.wasted > $1.wasted : $0.paths[0] < $1.paths[0] }
    }

    /// Folders whose copies are on purpose or belong to an app: code repositories (a
    /// logo in public/ and docs/), app libraries ("_Serato_", "Design.library") and backups.
    public static func shouldSkipFolder(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        let lower = name.lowercased()
        return skippedFolderNames.contains(name)
            || name.hasPrefix("_")
            || lower.hasSuffix(".library") || lower.hasSuffix(".lrdata")
            || lower.contains("backup")
            || FileManager.default.fileExists(atPath: url.appending(path: ".git").filePath)
    }

    /// Which copy to keep first: not named like a copy ("x copy.pdf", "x (1).pdf", "x 2.pdf"),
    /// then the oldest, then the shortest path.
    public static func keeperOrder(_ files: [(path: String, created: Date?)]) -> [String] {
        files.sorted { a, b in
            let (ca, cb) = (looksLikeCopy(a.path), looksLikeCopy(b.path))
            if ca != cb { return !ca }
            let (da, db) = (a.created ?? .distantFuture, b.created ?? .distantFuture)
            if da != db { return da < db }
            if a.path.count != b.path.count { return a.path.count < b.path.count }
            return a.path < b.path
        }
        .map(\.path)
    }

    /// "Report copy.pdf", "Report copy 2.pdf", "Report (1).pdf", "Report 2.pdf", "Report-1.pdf".
    public static func looksLikeCopy(_ path: String) -> Bool {
        let stem = ((path as NSString).lastPathComponent as NSString).deletingPathExtension.lowercased()
        let patterns = [#" copy( \d+)?$"#, #" \(\d+\)$"#, #" \d$"#, #"-\d$"#, #"_\d$"#]
        return patterns.contains { stem.range(of: $0, options: .regularExpression) != nil }
    }

    private static func unique(_ files: [Candidate]) -> [Candidate] {
        var seen = Set<AnyHashable>()
        return files.filter { file in
            if let id = file.fileID, !seen.insert(["f", id] as [AnyHashable]).inserted { return false }
            if let id = file.contentID, !seen.insert(["c", id] as [AnyHashable]).inserted { return false }
            return true
        }
    }

    /// Cloud placeholders (iCloud, OneDrive…) would download in full if read.
    private static func isDataless(_ url: URL, _ values: URLResourceValues) -> Bool {
        if values.isUbiquitousItem == true, values.ubiquitousItemDownloadingStatus != .current { return true }
        var info = stat()
        guard lstat(url.filePath, &info) == 0 else { return true }
        return info.st_flags & 0x4000_0000 != 0 // SF_DATALESS
    }

    static let sampleSize = 64 * 1024

    /// Hash of the first and last 64 KB.
    static func sampleHash(_ path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        var data = (try? handle.read(upToCount: sampleSize)) ?? Data()
        if let end = try? handle.seekToEnd(), end > UInt64(sampleSize * 2) {
            try? handle.seek(toOffset: end - UInt64(sampleSize))
            data.append((try? handle.read(upToCount: sampleSize)) ?? Data())
        }
        return digest(data)
    }

    static func fullHash(_ path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        #if canImport(CryptoKit)
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        #else
        return (try? handle.readToEnd()).map(digest) ?? nil
        #endif
    }

    private static func digest(_ data: Data) -> String {
        #if canImport(CryptoKit)
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #else
        String(data.hashValue)
        #endif
    }
}
