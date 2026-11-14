import Foundation

// MARK: - What happened

/// What Scout did to some files.
public enum FileAction: String, Codable, Sendable {
    case move, copy, rename, trash, tidy
    /// Put an earlier action back (⌘Z, or Undo on the History page). Undoing an undo is a redo.
    case undo
}

/// One file or folder going from one place to another. For a copy, `from` stays where it was.
public struct FileChange: Codable, Hashable, Sendable {
    public var from: String
    public var to: String

    public init(from: String, to: String) {
        self.from = from
        self.to = to
    }

    public init(_ pair: (URL, URL)) {
        self.init(from: pair.0.filePath, to: pair.1.filePath)
    }
}

/// One thing Scout did, as the History page shows it.
public struct FileHistoryEntry: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var date: Date
    public var action: FileAction
    public var changes: [FileChange]
    /// For `.undo`: the entry it put back.
    public var undoes: UUID?

    public init(id: UUID = UUID(), date: Date = .now, action: FileAction, changes: [FileChange], undoes: UUID? = nil) {
        self.id = id
        self.date = date
        self.action = action
        self.changes = changes
        self.undoes = undoes
    }
}

// MARK: - The log

/// Everything Scout moved, copied, renamed or trashed, oldest first. It outlives the
/// app (unlike ⌘Z), so it can answer "where did that file go?" days later.
public struct FileHistory: Sendable, Equatable {
    public private(set) var entries: [FileHistoryEntry]

    /// Kept: the last year, and at most this many entries.
    public static let entriesKept = 5000
    public static let daysKept = 365

    public init(entries: [FileHistoryEntry] = []) {
        self.entries = entries
    }

    public mutating func append(_ entry: FileHistoryEntry) {
        entries.append(entry)
    }

    /// Drops old entries. Returns true if anything was dropped (so the file needs rewriting).
    @discardableResult
    public mutating func prune(now: Date = .now) -> Bool {
        let cutoff = now.addingTimeInterval(-Double(Self.daysKept) * 86_400)
        var kept = entries.filter { $0.date >= cutoff }
        if kept.count > Self.entriesKept { kept.removeFirst(kept.count - Self.entriesKept) }
        guard kept.count != entries.count else { return false }
        entries = kept
        return true
    }

    public func entry(_ id: UUID) -> FileHistoryEntry? {
        entries.last { $0.id == id }
    }

    /// The later entry that undid this one, if any.
    public func undo(of id: UUID) -> FileHistoryEntry? {
        entries.last { $0.undoes == id }
    }

    /// The action an entry reads as: an undo of an undo is a redo of the original.
    public func describedAction(of entry: FileHistoryEntry) -> (action: FileAction, isRedo: Bool) {
        guard entry.action == .undo, let target = entry.undoes.flatMap(self.entry) else { return (entry.action, false) }
        if target.action == .undo, let original = target.undoes.flatMap(self.entry) {
            return (original.action, true)
        }
        return (.undo, false)
    }

    // MARK: Where is it now?

    /// Where a path ended up after the entry at `index`: follows later moves, renames,
    /// trashes and undos of it or of a folder it was in. Copies leave it where it is.
    public func currentPath(of path: String, after index: Int) -> String {
        var path = path
        for entry in entries.dropFirst(index + 1) where entry.action != .copy {
            for change in entry.changes {
                if path == change.from {
                    path = change.to
                    break
                }
                if path.hasPrefix(change.from + "/") {
                    path = change.to + path.dropFirst(change.from.count)
                    break
                }
            }
        }
        return path
    }

    /// One file in one entry, with where it is now.
    public struct Match: Hashable, Identifiable, Sendable {
        public var id: String { "\(entry.id)|\(change.from)|\(change.to)" }
        public let entry: FileHistoryEntry
        public let change: FileChange
        /// Where the file is now, as far as Scout knows (it may since have been changed by other apps).
        public let currentPath: String
    }

    /// Files whose old or new name contains every word of `query` (case and accents ignored),
    /// newest first. "where did Q3-model go?" → `matches("Q3-model")`.
    public func matches(_ query: String, limit: Int = 200) -> [Match] {
        let words = query.split(whereSeparator: \.isWhitespace).map { String($0) }
        guard !words.isEmpty else { return [] }
        func hit(_ path: String) -> Bool {
            let name = (path as NSString).lastPathComponent
            return words.allSatisfy { name.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
        var results: [Match] = []
        for index in entries.indices.reversed() {
            let entry = entries[index]
            for change in entry.changes where hit(change.from) || hit(change.to) {
                results.append(Match(entry: entry, change: change,
                                     currentPath: currentPath(of: change.to, after: index)))
                if results.count >= limit { return results }
            }
        }
        return results
    }

    // MARK: Undo

    /// Why an entry can't be undone, or nil if it can. `exists` checks the disk.
    public func undoBlocker(for entry: FileHistoryEntry, exists: (String) -> Bool) -> String? {
        if undo(of: entry.id) != nil { return "Already undone." }
        if entry.action == .copy {
            return entry.changes.contains { exists($0.to) } ? nil : "The copies are already gone."
        }
        for change in entry.changes {
            if !exists(change.to) {
                return "“\((change.to as NSString).lastPathComponent)” has moved since."
            }
            if exists(change.from), change.from.lowercased() != change.to.lowercased() {
                return "Something else is now at “\((change.from as NSString).lastPathComponent)”’s old place."
            }
        }
        return nil
    }
}

// MARK: - Saving

/// The log on disk: one JSON entry per line (`file-history.jsonl`), so recording an
/// action appends a line instead of rewriting the file.
public enum FileHistoryStore {
    public static var url: URL { ScoutStore.directory.appending(path: "file-history.jsonl") }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// Reads the log, skipping any line that doesn't parse (e.g. a half-written last line).
    public static func load(from url: URL = url) -> FileHistory {
        guard let data = try? Data(contentsOf: url) else { return FileHistory() }
        let entries = data.split(separator: UInt8(ascii: "\n")).compactMap {
            try? decoder.decode(FileHistoryEntry.self, from: Data($0))
        }
        return FileHistory(entries: entries)
    }

    /// Adds one entry to the end of the file.
    public static func append(_ entry: FileHistoryEntry, to url: URL = url) throws {
        var line = try encoder.encode(entry)
        line.append(UInt8(ascii: "\n"))
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.filePath) {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try line.write(to: url, options: .atomic)
            return
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
    }

    /// Replaces the whole file (after pruning).
    public static func save(_ history: FileHistory, to url: URL = url) throws {
        var data = Data()
        for entry in history.entries {
            data.append(try encoder.encode(entry))
            data.append(UInt8(ascii: "\n"))
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
