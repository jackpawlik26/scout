import Foundation

// MARK: - "Ask Scout": a description → a search

/// What the on-device model made of a description like "the lease I signed last spring".
/// Plain strings, so the model's answer can be checked and cleaned here (and tested).
public struct SearchPlan: Equatable, Sendable {
    public var keywords: [String]
    /// A `KindFilter` raw value, or "any".
    public var kind: String
    /// yyyy-MM-dd, or empty.
    public var after: String
    /// yyyy-MM-dd (inclusive), or empty.
    public var before: String

    public init(keywords: [String], kind: String = "any", after: String = "", before: String = "") {
        self.keywords = keywords
        self.kind = kind
        self.after = after
        self.before = before
    }

    /// Words that describe the search rather than the file ("files", "spring", "last").
    static let notKeywords: Set<String> = [
        "file", "files", "document", "documents", "doc", "docs", "pdf", "pdfs", "image", "images", "photo", "photos",
        "picture", "pictures", "screenshot", "screenshots", "video", "videos", "spreadsheet", "spreadsheets",
        "the", "a", "an", "my", "i", "that", "from", "last", "this", "recent", "recently", "old", "new",
        "spring", "summer", "fall", "autumn", "winter", "week", "month", "year", "today", "yesterday",
    ]

    /// The search to run, or nil when the plan has nothing usable. Drops amounts and
    /// filler, keeps at most two keywords (Spotlight needs every word to match), and
    /// ignores impossible or reversed dates.
    public func spec(scope: SearchScope = .files, calendar: Calendar = .current) -> SearchSpec? {
        let words = keywords
            .flatMap { $0.split(whereSeparator: \.isWhitespace).map(String.init) }
            .map { $0.trimmingCharacters(in: .punctuationCharacters.union(.symbols)) }
            .filter { word in
                word.count >= 2 && !Self.notKeywords.contains(word.lowercased())
                    && word.rangeOfCharacter(from: .letters) != nil
            }
        var unique: [String] = []
        for word in words where !unique.contains(where: { $0.caseInsensitiveCompare(word) == .orderedSame }) {
            unique.append(word)
        }
        var spec = SearchSpec(query: unique.prefix(2).joined(separator: " "), scope: scope,
                              kind: KindFilter(rawValue: kind.lowercased()))
        spec.after = Self.day(after, calendar: calendar)
        // "before" is inclusive: up to the end of that day.
        spec.before = Self.day(before, calendar: calendar).flatMap { calendar.date(byAdding: .day, value: 1, to: $0) }
        if let a = spec.after, let b = spec.before, a >= b { spec.before = nil }
        return spec.isEmpty ? nil : spec
    }

    static func day(_ text: String, calendar: Calendar) -> Date? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// Whether a palette query reads like a description worth asking about.
    public static func looksLikeQuestion(_ query: String) -> Bool {
        let words = query.split(whereSeparator: \.isWhitespace)
        guard words.count >= 3, !query.hasPrefix("/"), !query.hasPrefix("~") else { return false }
        return !words.contains { $0.lowercased().hasPrefix("from:") }
    }
}

// MARK: - Text in images

/// Text Scout read from images and screenshots (Spotlight reads text in only a few of
/// them), so ⌘K can find "the screenshot with the error". Kept in `image-text.json`.
public struct ImageTextIndex: Codable, Sendable, Equatable {
    public struct Entry: Codable, Sendable, Equatable {
        public var modified: Date
        /// Lowercased, one line per line of text.
        public var text: String

        public init(modified: Date, text: String) {
            self.modified = modified
            self.text = text
        }
    }

    public var entries: [String: Entry] = [:]
    public static let maxImages = 4000

    public init() {}

    /// Whether `path` needs reading (new, or changed since it was read).
    public func needsReading(_ path: String, modified: Date) -> Bool {
        guard let entry = entries[path] else { return true }
        return abs(entry.modified.timeIntervalSince(modified)) > 1
    }

    public mutating func set(_ path: String, modified: Date, text: String) {
        entries[path] = Entry(modified: modified, text: text.lowercased())
    }

    /// Keeps only these paths (others were deleted or moved).
    public mutating func keep(only paths: Set<String>) {
        entries = entries.filter { paths.contains($0.key) }
    }

    /// Images whose text contains every word, newest first.
    public func matches(_ query: String, limit: Int = 40) -> [String] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init).filter { $0.count >= 3 }
        guard !words.isEmpty else { return [] }
        return entries
            .filter { _, entry in words.allSatisfy { entry.text.contains($0) } }
            .sorted { $0.value.modified > $1.value.modified }
            .prefix(limit)
            .map(\.key)
    }

    public static var url: URL { ScoutStore.directory.appending(path: "image-text.json") }

    public static func load(from url: URL = url) -> ImageTextIndex {
        guard let data = try? Data(contentsOf: url) else { return ImageTextIndex() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return (try? decoder.decode(ImageTextIndex.self, from: data)) ?? ImageTextIndex()
    }

    public func save(to url: URL = url) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
