import Foundation

/// One folder in the jump index.
public struct IndexedFolder: Sendable, Hashable, Identifiable {
    public var id: String { path }
    public let path: String
    public let name: String
    /// Friendly path, e.g. "~/Projects/Scout" or "iCloud Drive/Taxes".
    public let displayPath: String

    let nameLower: String
    let displayLower: String

    public init(path: String, home: String) {
        self.path = path
        self.name = path == "/" ? "/" : (path as NSString).lastPathComponent
        self.displayPath = PathDisplay.display(path, home: home)
        self.nameLower = name.lowercased()
        self.displayLower = displayPath.lowercased()
    }
}

/// Walks your folders to build the list ⌘K searches. Folders only (files come
/// from Spotlight later), skipping junk like node_modules and .git.
public enum FolderIndexer {
    /// Never listed, never entered.
    public static let skipEntirely: Set<String> = [
        ".git", "node_modules", ".Trash", "__pycache__", ".svn", ".hg",
    ]

    /// Listed (so you can jump to them) but not entered.
    public static let skipContents: Set<String> = [
        "Library", "DerivedData", ".build", "build", "dist", "Pods", ".venv", "venv",
        ".next", ".nuxt", "target", ".cache", ".npm", ".cargo", ".rustup", ".gradle",
        "Caches", ".swiftpm", ".pnpm-store", ".yarn", ".wrangler", ".vercel", ".turbo",
    ]

    public static func scan(
        roots: [URL], home: String, maxDepth: Int = 12, limit: Int = 300_000
    ) -> [IndexedFolder] {
        var result: [IndexedFolder] = []
        var seen = Set<String>()
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]

        for root in roots {
            let rootPath = root.filePath
            if seen.insert(rootPath).inserted {
                result.append(IndexedFolder(path: rootPath, home: home))
            }
            guard let walker = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: keys,
                options: [.skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else { continue }

            while let url = walker.nextObject() as? URL {
                if Task.isCancelled || result.count >= limit { return result }
                guard let v = try? url.resourceValues(forKeys: Set(keys)),
                      v.isDirectory == true, v.isPackage != true else { continue }

                let name = url.lastPathComponent
                if skipEntirely.contains(name) {
                    walker.skipDescendants()
                    continue
                }
                let path = url.filePath
                if seen.insert(path).inserted {
                    result.append(IndexedFolder(path: path, home: home))
                }
                if skipContents.contains(name) || name.hasPrefix(".") || walker.level >= maxDepth {
                    walker.skipDescendants()
                }
            }
        }
        return result
    }
}

/// A folder ranked for the ⌘K palette.
public struct RankedFolder: Sendable, Identifiable, Equatable {
    public var id: String { folder.path }
    public let folder: IndexedFolder
    public let score: Double
    /// Letters of `folder.name` to bold. Empty when the match was on the path.
    public let nameIndices: [Int]

    public init(folder: IndexedFolder, score: Double, nameIndices: [Int]) {
        self.folder = folder
        self.score = score
        self.nameIndices = nameIndices
    }
}

public enum FolderRanker {
    /// Ranks folders for a ⌘K query. Empty query → your most-used folders.
    public static func rank(
        query: String,
        folders: [IndexedFolder],
        frecency: FrecencyLog,
        home: String,
        now: Date = .now,
        limit: Int = 50
    ) -> [RankedFolder] {
        let q = query.trimmingCharacters(in: .whitespaces)

        if q.isEmpty {
            return frecency.top(limit, now: now).map {
                RankedFolder(folder: IndexedFolder(path: $0, home: home),
                             score: frecency.score(for: $0, now: now), nameIndices: [])
            }
        }

        // Folders you've visited count even if the index skipped them.
        var candidates = folders
        let indexed = Set(folders.map(\.path))
        for path in frecency.entries.keys where !indexed.contains(path) {
            candidates.append(IndexedFolder(path: path, home: home))
        }

        // Each space-separated word must appear (in any order relative to the others).
        let tokenBytes = q.lowercased().split(separator: " ").map { Array($0.utf8) }
        func mightMatch(_ lower: String) -> Bool {
            tokenBytes.allSatisfy { FuzzyMatcher.mightMatch(queryUTF8: $0, candidateLower: lower) }
        }
        let matchPath = q.contains("/")
        // Path matches must be tight (mostly whole words), or letters scattered
        // across a long path ("v…a…l…u…" in "ProtonDrive/…/Illustrations") sneak in.
        let letters = q.filter { !$0.isWhitespace && $0 != "/" }.count
        let minimumPathScore = letters * 18
        // Longer queries shouldn't match letters strewn across a long name either
        // ("resume" in "mr_dungeons_andtavernsoceanmonumentoverhaul").
        let minimumNameScore = letters >= 4 ? letters * 16 : Int.min
        var ranked: [RankedFolder] = []

        for folder in candidates {
            if Task.isCancelled { return [] }
            var base: Double
            var indices: [Int] = []

            if !matchPath,
               mightMatch(folder.nameLower),
               let m = FuzzyMatcher.match(q, in: folder.name),
               m.score >= minimumNameScore {
                base = Double(m.score)
                indices = m.indices
            } else if mightMatch(folder.displayLower),
                      let m = FuzzyMatcher.match(q, in: folder.displayPath),
                      m.score >= minimumPathScore {
                base = Double(m.score) * (matchPath ? 1 : 0.5)
            } else {
                continue
            }

            let f = frecency.score(for: folder.path, now: now)
            let boost = f > 0 ? min(40, 12 * log2(1 + f / 10)) : 0
            let depth = Double(folder.displayPath.split(separator: "/").count)
            ranked.append(RankedFolder(folder: folder, score: base + boost - depth * 0.5,
                                       nameIndices: indices))
        }

        ranked.sort { $0.score != $1.score ? $0.score > $1.score : $0.folder.path < $1.folder.path }
        return Array(ranked.prefix(limit))
    }
}
