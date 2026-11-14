import Foundation

// MARK: - What to search for

public enum SearchScope: String, Codable, CaseIterable, Sendable {
    case all, folders, files

    public var title: String {
        switch self {
        case .all: "All"
        case .folders: "Folders"
        case .files: "Files"
        }
    }
}

public enum KindFilter: String, Codable, CaseIterable, Sendable {
    case documents, pdfs, images, videos, audio, spreadsheets, presentations, code, archives, apps

    public var title: String {
        switch self {
        case .documents: "Documents"
        case .pdfs: "PDFs"
        case .images: "Images"
        case .videos: "Videos"
        case .audio: "Audio"
        case .spreadsheets: "Spreadsheets"
        case .presentations: "Presentations"
        case .code: "Code"
        case .archives: "Archives"
        case .apps: "Apps"
        }
    }

    public var symbol: String {
        switch self {
        case .documents: "doc.text"
        case .pdfs: "doc.richtext"
        case .images: "photo"
        case .videos: "film"
        case .audio: "waveform"
        case .spreadsheets: "tablecells"
        case .presentations: "rectangle.on.rectangle"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .archives: "archivebox"
        case .apps: "app"
        }
    }

    /// Uniform type identifiers; subtypes match too (kMDItemContentTypeTree).
    public var contentTypes: [String] {
        switch self {
        case .documents:
            ["com.adobe.pdf", "public.rtf", "public.plain-text", "net.daringfireball.markdown",
             "org.openxmlformats.wordprocessingml.document", "com.microsoft.word.doc",
             "com.apple.iwork.pages.sffpages", "com.apple.iwork.pages.pages", "org.oasis-open.opendocument.text"]
        case .pdfs: ["com.adobe.pdf"]
        case .images: ["public.image"]
        case .videos: ["public.movie"]
        case .audio: ["public.audio"]
        case .spreadsheets:
            ["public.spreadsheet", "org.openxmlformats.spreadsheetml.sheet", "com.microsoft.excel.xls",
             "com.apple.iwork.numbers.sffnumbers", "com.apple.iwork.numbers.numbers", "public.comma-separated-values-text"]
        case .presentations:
            ["public.presentation", "org.openxmlformats.presentationml.presentation", "com.microsoft.powerpoint.ppt",
             "com.apple.iwork.keynote.sffkey", "com.apple.iwork.keynote.key"]
        case .code: ["public.source-code", "public.script", "public.json", "public.yaml", "public.xml"]
        case .archives: ["public.archive", "com.apple.disk-image"]
        case .apps: ["com.apple.application-bundle"]
        }
    }
}

public enum DateFilter: String, Codable, CaseIterable, Sendable {
    case today, week, month, year

    public var title: String {
        switch self {
        case .today: "Today"
        case .week: "Past 7 Days"
        case .month: "Past 30 Days"
        case .year: "Past Year"
        }
    }

    /// Days before today to include (0 = today only).
    var daysBack: Int {
        switch self {
        case .today: 0
        case .week: 6
        case .month: 29
        case .year: 364
        }
    }
}

/// A search: words plus optional filters.
public struct SearchSpec: Codable, Hashable, Sendable {
    public var query: String
    public var scope: SearchScope
    public var kind: KindFilter?
    public var date: DateFilter?
    /// Only search inside this folder (and its subfolders).
    public var withinPath: String?

    public init(query: String = "", scope: SearchScope = .all, kind: KindFilter? = nil,
                date: DateFilter? = nil, withinPath: String? = nil) {
        self.query = query
        self.scope = scope
        self.kind = kind
        self.date = date
        self.withinPath = withinPath
    }

    public var words: [String] {
        query.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Has a filter that only Spotlight can answer (kind or date).
    public var hasFileFilters: Bool { kind != nil || date != nil }

    /// Nothing to search for yet.
    public var isEmpty: Bool { words.isEmpty && !hasFileFilters }

    /// Should the folder index (⌘K's instant folder results) be included?
    public var includesIndexedFolders: Bool { scope != .files && !hasFileFilters && !words.isEmpty }

    /// Should Spotlight run? Needs 2+ letters or a filter, and not folders-only.
    public var includesSpotlight: Bool {
        guard scope != .folders else { return false }
        return hasFileFilters || query.trimmingCharacters(in: .whitespaces).count >= 2
    }

    /// A short label, e.g. "“taxes” · PDFs · Past 30 Days".
    public var summary: String {
        var parts: [String] = []
        if !words.isEmpty { parts.append("“\(words.joined(separator: " "))”") }
        if let kind { parts.append(kind.title) }
        if let date { parts.append(date.title) }
        if scope == .folders { parts.append("Folders") }
        if let withinPath { parts.append("in \((withinPath as NSString).lastPathComponent)") }
        return parts.isEmpty ? "Search" : parts.joined(separator: " · ")
    }
}

public struct SavedSearch: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var spec: SearchSpec

    public init(id: UUID = UUID(), name: String, spec: SearchSpec) {
        self.id = id
        self.name = name
        self.spec = spec
    }
}

// MARK: - Spotlight query strings

/// Builds Spotlight query strings (the `mdfind` syntax) from a `SearchSpec`.
public enum SpotlightQueryBuilder {
    /// Nil when there's nothing to search for. (⌘K also checks `includesSpotlight`
    /// so it doesn't search on one letter; a results tab searches any spec.)
    public static func queryString(for spec: SearchSpec) -> String? {
        guard !spec.isEmpty else { return nil }
        var clauses: [String] = []

        for word in spec.words {
            let w = escape(word)
            // Name contains the word anywhere; or (3+ letters) a word inside the document starts with it.
            var options = ["kMDItemFSName == \"*\(w)*\"cd"]
            if word.count >= 3 { options.append("kMDItemTextContent == \"\(w)*\"cdw") }
            clauses.append(options.count == 1 ? options[0] : "(" + options.joined(separator: " || ") + ")")
        }

        if let kind = spec.kind {
            let types = kind.contentTypes.map { "kMDItemContentTypeTree == \"\($0)\"" }
            clauses.append(types.count == 1 ? types[0] : "(" + types.joined(separator: " || ") + ")")
        }

        if let date = spec.date {
            let time = date.daysBack == 0 ? "$time.today" : "$time.today(-\(date.daysBack))"
            clauses.append("kMDItemFSContentChangeDate >= \(time)")
        }

        switch spec.scope {
        case .folders: clauses.append("kMDItemContentType == \"public.folder\"")
        case .files: clauses.append("kMDItemContentType != \"public.folder\"")
        case .all: break
        }

        return clauses.joined(separator: " && ")
    }

    public static func escape(_ s: String) -> String {
        var out = ""
        for c in s {
            if c == "\\" || c == "\"" || c == "*" || c == "?" { out.append("\\") }
            out.append(c)
        }
        return out
    }
}

// MARK: - Spotlight results

/// One file Spotlight found.
public struct FileHit: Sendable, Hashable, Identifiable {
    public var id: String { path }
    public let path: String
    public let name: String
    public let isFolder: Bool
    public let modified: Date?
    public let lastUsed: Date?
    public let contentType: String?

    public init(path: String, name: String, isFolder: Bool = false, modified: Date? = nil,
                lastUsed: Date? = nil, contentType: String? = nil) {
        self.path = path
        self.name = name
        self.isFolder = isFolder
        self.modified = modified
        self.lastUsed = lastUsed
        self.contentType = contentType
    }
}

public struct RankedHit: Sendable, Hashable, Identifiable {
    public var id: String { hit.path }
    public let hit: FileHit
    public let score: Double
    /// Letters of the name to bold (empty when only the contents matched).
    public let nameIndices: [Int]
}

public enum FileHitRanker {
    /// Drops junk (caches, node_modules, hidden folders…), then ranks:
    /// name matches beat content-only matches, and recently used files rise.
    public static func rank(_ hits: [FileHit], query: String, home: String, now: Date = .now,
                            limit: Int = 50) -> [RankedHit] {
        let q = query.trimmingCharacters(in: .whitespaces)
        var ranked: [RankedHit] = []
        ranked.reserveCapacity(min(hits.count, 4000))

        for hit in hits where !isNoise(hit.path, home: home) {
            var score: Double
            var indices: [Int] = []
            if q.isEmpty {
                score = 0
            } else if let m = FuzzyMatcher.match(q, in: hit.name) {
                score = Double(m.score)
                indices = m.indices
            } else {
                score = 10 // only the contents matched
            }
            if let recent = [hit.lastUsed, hit.modified].compactMap({ $0 }).max() {
                let days = now.timeIntervalSince(recent) / 86_400
                score += days < 1 ? 30 : days < 7 ? 20 : days < 30 ? 10 : days < 365 ? 3 : 0
                if q.isEmpty { score += max(0, 100 - days) / 10 } // filters only: newest first
            }
            ranked.append(RankedHit(hit: hit, score: score, nameIndices: indices))
        }

        ranked.sort { $0.score != $1.score ? $0.score > $1.score : $0.hit.name < $1.hit.name }
        return Array(ranked.prefix(limit))
    }

    /// Files nobody means to find: app caches, dependency folders, hidden files,
    /// the insides of app bundles.
    public static func isNoise(_ path: String, home: String) -> Bool {
        if path.hasPrefix(home + "/Library/") {
            let allowed = ["/Library/Mobile Documents/", "/Library/CloudStorage/"]
            if !allowed.contains(where: { path.hasPrefix(home + $0) }) { return true }
        }
        // Xcode and other build output ("…/build/Build/Products/Debug/Scout.app").
        if path.contains("/Build/Products/") || path.contains("/Build/Intermediates") { return true }
        let components = path.split(separator: "/")
        for (i, part) in components.enumerated() {
            if part.hasPrefix(".") { return true }
            if FolderIndexer.skipEntirely.contains(String(part)) { return true }
            if ["DerivedData", "Caches", ".build", "Pods"].contains(part) { return true }
            // Inside an app or other bundle (but not the bundle itself).
            if i < components.count - 1, part.hasSuffix(".app") || part.hasSuffix(".bundle") || part.hasSuffix(".framework") {
                return true
            }
        }
        return false
    }
}
