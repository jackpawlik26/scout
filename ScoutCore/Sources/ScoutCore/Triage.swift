import Foundation

// MARK: - What's waiting

public enum Triage {
    /// Loose files waiting in an inbox, newest first. Skips folders, hidden files and
    /// downloads that haven't finished.
    public static func inbox(_ items: [FileItem]) -> [FileItem] {
        items
            .filter { !$0.isDirectory && !$0.isHidden && !Tidy.downloading.contains($0.url.pathExtension.lowercased()) }
            .sorted { $0.addedSortKey > $1.addedSortKey }
    }

    /// Words in a file name that say what it is ("Invoice_Acme_2026-03.pdf" → invoice, acme).
    static func words(in name: String) -> Set<String> {
        let stem = (name as NSString).deletingPathExtension.lowercased()
        let parts = stem.split { !$0.isLetter }.map(String.init)
        return Set(parts.filter { $0.count >= 3 && !stopWords.contains($0) })
    }

    static let stopWords: Set<String> = [
        "the", "and", "for", "with", "copy", "final", "untitled", "download", "downloads", "file",
        "new", "img", "image", "document", "doc", "from", "version", "draft", "pdf",
    ]

    static func ext(_ name: String) -> String { (name as NSString).pathExtension.lowercased() }
}

// MARK: - Where should it go?

/// A folder triage suggests for a file, and why.
public struct DestinationSuggestion: Hashable, Sendable, Identifiable {
    public var id: String { folder }
    public let folder: String
    public let score: Double
    /// "6 PDFs from canvas.depaul.edu went here"
    public let reason: String

    public init(folder: String, score: Double, reason: String) {
        self.folder = folder
        self.score = score
        self.reason = reason
    }
}

/// Learns where files go from what you moved before (File History).
public enum DestinationLearner {
    /// Up to `limit` folders for a file, best first. Each past move counts when it was a file
    /// like this one: the same site (strongest), words in common, or the same type; recent
    /// moves count more.
    /// Moves you later undid don't count (they were mistakes).
    public static func suggestions(name: String, site: String?, history: FileHistory, excluding here: String,
                                   now: Date = .now, limit: Int = 3) -> [DestinationSuggestion] {
        let ext = Triage.ext(name)
        let words = Triage.words(in: name)
        let undone = Set(history.entries.compactMap(\.undoes))

        struct Tally { var score = 0.0, count = 0, sameSite = 0, sameType = 0, last = Date.distantPast }
        var tallies: [String: Tally] = [:]
        for entry in history.entries where [.move, .tidy, .rule].contains(entry.action) && !undone.contains(entry.id) {
            let age = now.timeIntervalSince(entry.date) / 86_400
            let recency = age < 30 ? 1.0 : age < 180 ? 0.7 : 0.4
            for change in entry.changes {
                let pastName = (change.to as NSString).lastPathComponent
                let sameSite = site != nil && change.site == site
                let sameType = !ext.isEmpty && Triage.ext(pastName) == ext
                let shared = words.intersection(Triage.words(in: pastName)).count
                // A shared site or shared words say much more than a shared file type
                // (lots of unrelated things are PDFs).
                var score = (sameSite ? 3 : 0) + (sameType ? 1 : 0) + Double(min(shared, 2)) * 1.5
                guard score > 0 else { continue }
                score *= recency
                let folder = (change.to as NSString).deletingLastPathComponent
                guard folder != here else { continue }
                var tally = tallies[folder, default: Tally()]
                tally.score += score
                tally.count += 1
                if sameSite { tally.sameSite += 1 }
                if sameType { tally.sameType += 1 }
                tally.last = max(tally.last, entry.date)
                tallies[folder] = tally
            }
        }
        return tallies
            .sorted { $0.value.score != $1.value.score ? $0.value.score > $1.value.score : $0.key < $1.key }
            .prefix(limit)
            .map { folder, tally in
                DestinationSuggestion(folder: folder, score: tally.score,
                                      reason: reason(tally.count, sameSite: tally.sameSite, sameType: tally.sameType,
                                                     ext: ext, site: site))
            }
    }

    static func reason(_ count: Int, sameSite: Int, sameType: Int, ext: String, site: String?) -> String {
        let kind = sameType == count && !ext.isEmpty ? "\(ext.uppercased()) file" : "similar file"
        let noun = count == 1 ? kind : kind + "s"
        let from = sameSite == count && site != nil ? " from \(site!)" : ""
        return "\(count) \(noun)\(from) went here"
    }
}

// MARK: - Rules

/// "Always do this": files that match go to a folder on their own as they arrive.
/// Every condition that's set must hold, and a rule needs at least one.
public struct TriageRule: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    /// Downloaded from a site containing this ("canvas.depaul.edu").
    public var site: String?
    /// File types, lowercase, without dots ("pdf"). Empty means any.
    public var extensions: [String]
    /// The name contains this (case ignored).
    public var nameContains: String?
    /// The folder files go into.
    public var destination: String
    public var isEnabled: Bool
    public var created: Date

    public init(id: UUID = UUID(), name: String, site: String? = nil, extensions: [String] = [],
                nameContains: String? = nil, destination: String, isEnabled: Bool = true, created: Date = .now) {
        self.id = id
        self.name = name
        self.site = site
        self.extensions = extensions.map { $0.lowercased() }
        self.nameContains = nameContains
        self.destination = destination
        self.isEnabled = isEnabled
        self.created = created
    }

    public var hasConditions: Bool {
        site?.isEmpty == false || !extensions.isEmpty || nameContains?.isEmpty == false
    }

    public func matches(name: String, site fileSite: String?) -> Bool {
        guard isEnabled, hasConditions else { return false }
        if let site, !site.isEmpty {
            guard let fileSite, fileSite.range(of: site, options: .caseInsensitive) != nil else { return false }
        }
        if !extensions.isEmpty, !extensions.contains(Triage.ext(name)) { return false }
        if let nameContains, !nameContains.isEmpty,
           name.range(of: nameContains, options: [.caseInsensitive, .diacriticInsensitive]) == nil { return false }
        return true
    }

    /// The rule "Always do this" makes from one decision: same site (when known) and
    /// same file type. Without either, nothing safe to generalize from.
    public static func suggested(name: String, site: String?, destination: String) -> TriageRule? {
        let ext = Triage.ext(name)
        guard site != nil || !ext.isEmpty else { return nil }
        let folder = (destination as NSString).lastPathComponent
        var title = ext.isEmpty ? "Files" : "\(ext.uppercased()) files"
        if let site { title += " from \(site)" }
        return TriageRule(name: "\(title) → \(folder)", site: site,
                          extensions: ext.isEmpty ? [] : [ext], destination: destination)
    }

    /// Plain-English summary: "PDF files from canvas.depaul.edu".
    public var summary: String {
        var parts: [String] = []
        parts.append(extensions.isEmpty ? "Files" : extensions.map { $0.uppercased() }.joined(separator: ", ") + " files")
        if let site, !site.isEmpty { parts.append("from \(site)") }
        if let nameContains, !nameContains.isEmpty { parts.append("named like “\(nameContains)”") }
        return parts.joined(separator: " ")
    }

    /// The first enabled rule that matches.
    public static func first(_ rules: [TriageRule], matching name: String, site: String?) -> TriageRule? {
        rules.first { $0.matches(name: name, site: site) }
    }

    /// Whether a file has finished arriving and is new enough for rules to act on: added
    /// between `settle` seconds and `window` seconds ago, and not an unfinished download.
    public static func isReady(_ item: FileItem, now: Date = .now, settle: TimeInterval = 5,
                               window: TimeInterval = 15 * 60) -> Bool {
        guard !item.isDirectory, !item.isHidden,
              !Tidy.downloading.contains(item.url.pathExtension.lowercased()),
              let added = item.dateAdded else { return false }
        let age = now.timeIntervalSince(added)
        guard age >= settle, age <= window else { return false }
        if let modified = item.dateModified, now.timeIntervalSince(modified) < settle { return false }
        return true
    }
}

extension ScoutStore {
    public static var triageRulesURL: URL { directory.appending(path: "triage-rules.json") }

    public static func loadTriageRules(from url: URL = triageRulesURL) -> [TriageRule] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([TriageRule].self, from: data)) ?? []
    }

    public static func saveTriageRules(_ rules: [TriageRule], to url: URL = triageRulesURL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(rules).write(to: url, options: .atomic)
    }
}
