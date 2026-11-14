import Foundation

/// "Related": files that belong with this one. Three signals, strongest first:
/// - opened through Scout around the same time (Scout's own open log),
/// - moved, tidied or renamed together (File History),
/// - used around the same time in any app (Spotlight's last-used date, when macOS kept one).
public enum RelatedFiles {
    /// How far either side of a use counts as "around the same time".
    public static let window: TimeInterval = 60 * 60

    /// The Spotlight query for files used near `date`.
    public static func query(around date: Date) -> String {
        let from = date.addingTimeInterval(-window).formatted(.iso8601)
        let to = date.addingTimeInterval(window).formatted(.iso8601)
        return #"kMDItemLastUsedDate >= $time.iso(\#(from)) && kMDItemLastUsedDate <= $time.iso(\#(to)) && kMDItemContentType != "public.folder""#
    }

    /// Paths related to `path`, best first. `spotlightUsed` is Spotlight's last-used date for the
    /// file and `spotlightHits` the files used near it.
    public static func rank(path: String, opens: OpenLog, history: FileHistory,
                            spotlightUsed: Date? = nil, spotlightHits: [FileHit] = [],
                            home: String, limit: Int = 5) -> [String] {
        var score: [String: Double] = [:]
        func closeness(_ a: Date, _ b: Date) -> Double { max(0, 1 - abs(a.timeIntervalSince(b)) / window) }

        // 1. Opened through Scout near any time this file was opened.
        let mine = opens.entries.filter { $0.path == path }.map(\.date)
        if !mine.isEmpty {
            for entry in opens.entries where entry.path != path {
                let best = mine.map { closeness($0, entry.date) }.max() ?? 0
                if best > 0 { score[entry.path, default: 0] += 1 + best }
            }
        }
        // 2. Moved together: other files in the same History entry, where they are now.
        for (index, entry) in history.entries.enumerated() where entry.action != .undo && entry.changes.count > 1 {
            guard entry.changes.contains(where: { history.currentPath(of: $0.to, after: index) == path }) else { continue }
            for change in entry.changes {
                let now = history.currentPath(of: change.to, after: index)
                if now != path { score[now, default: 0] += 1.2 }
            }
        }
        // 3. Used around the same time in any app.
        if let used = spotlightUsed {
            for hit in spotlightHits where !hit.isFolder && hit.contentType != "com.apple.application-bundle" {
                if let last = hit.lastUsed { score[hit.path, default: 0] += 0.5 + closeness(used, last) * 0.5 }
            }
        }
        score[path] = nil
        return score
            .filter { !FileHitRanker.isNoise($0.key, home: home) }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(limit)
            .map(\.key)
    }
}

/// Files you opened through Scout and when (the last 2,000), for "Related".
public struct OpenLog: Codable, Sendable, Equatable {
    public struct Entry: Codable, Sendable, Equatable {
        public var path: String
        public var date: Date
    }

    public private(set) var entries: [Entry] = []
    public static let kept = 2000

    public init(entries: [Entry] = []) { self.entries = entries }

    public mutating func record(_ path: String, at date: Date = .now) {
        entries.append(Entry(path: path, date: date))
        if entries.count > Self.kept { entries.removeFirst(entries.count - Self.kept) }
    }

    public static var url: URL { ScoutStore.directory.appending(path: "opens.json") }

    public static func load(from url: URL = url) -> OpenLog {
        guard let data = try? Data(contentsOf: url) else { return OpenLog() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(OpenLog.self, from: data)) ?? OpenLog()
    }

    public func save(to url: URL = url) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.withoutEscapingSlashes]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
