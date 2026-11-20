import Foundation

/// How you've personalized a file or folder in Scout (Finder doesn't see these).
public struct ItemStyle: Codable, Equatable, Sendable {
    /// A color name from `ItemStyle.colors` (folders).
    public var color: String?
    /// An SF Symbol drawn on the folder.
    public var symbol: String?
    /// Shown instead of the real name in Scout; the name on disk is unchanged.
    public var nickname: String?
    /// Your note ("final version sent to client"), shown in the info panel and searchable in ⌘K.
    public var note: String?
    /// Web pages that belong with it (the Notion brief, the Figma file, the repo).
    public var links: [ItemLink]?
    /// Your fields' values, by field id ("Status" → "In progress"). Dates are "yyyy-MM-dd".
    public var fields: [String: String]?

    public init(color: String? = nil, symbol: String? = nil, nickname: String? = nil, note: String? = nil,
                links: [ItemLink]? = nil, fields: [String: String]? = nil) {
        self.color = color
        self.symbol = symbol
        self.nickname = nickname
        self.note = note
        self.links = links
        self.fields = fields
    }

    public var isEmpty: Bool {
        color == nil && symbol == nil && (nickname ?? "").isEmpty && (note ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (links ?? []).isEmpty && (fields ?? [:]).isEmpty
    }

    public static let colors = ["red", "orange", "yellow", "green", "mint", "teal", "blue", "indigo", "purple", "pink", "gray"]
    public static let symbols = [
        "star.fill", "heart.fill", "briefcase.fill", "graduationcap.fill", "dollarsign.circle.fill", "chart.bar.fill",
        "doc.text.fill", "photo.fill", "music.note", "film.fill", "hammer.fill", "chevron.left.forwardslash.chevron.right",
        "gamecontroller.fill", "airplane", "house.fill", "person.2.fill", "lock.fill", "archivebox.fill",
    ]
}

/// A web link on a file or folder.
public struct ItemLink: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var title: String
    public var url: String
    public var id: String { url }

    public init(title: String, url: String) {
        self.title = title
        self.url = url
    }

    /// A link from what you typed or pasted ("notion.so/acme" → https://notion.so/acme), or nil
    /// when it isn't a web address. Titled after the site unless `title` is given.
    public init?(_ text: String, title: String? = nil) {
        var raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, !raw.contains(" ") else { return nil }
        if !raw.contains("://") { raw = "https://" + raw }
        guard let components = URLComponents(string: raw),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = components.host, host.contains(".") || host == "localhost"
        else { return nil }
        let given = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.init(title: given.isEmpty ? Self.siteName(host: host) : given, url: raw)
    }

    /// "Notion", "Figma", "GitHub"… for well-known sites, otherwise the bare host ("acme.com").
    public static func siteName(host: String) -> String {
        let bare = host.lowercased().hasPrefix("www.") ? String(host.dropFirst(4)) : host.lowercased()
        let known: [(String, String)] = [
            ("notion.so", "Notion"), ("notion.site", "Notion"), ("figma.com", "Figma"), ("github.com", "GitHub"),
            ("gitlab.com", "GitLab"), ("linear.app", "Linear"), ("docs.google.com", "Google Docs"),
            ("drive.google.com", "Google Drive"), ("dropbox.com", "Dropbox"), ("trello.com", "Trello"),
            ("airtable.com", "Airtable"), ("canva.com", "Canva"), ("miro.com", "Miro"), ("slack.com", "Slack"),
            ("youtube.com", "YouTube"), ("vercel.com", "Vercel"), ("dash.cloudflare.com", "Cloudflare"),
        ]
        return known.first { bare == $0.0 || bare.hasSuffix("." + $0.0) }?.1 ?? bare
    }
}

/// A field you add to files and folders: Status, Client, Due, Amount…
public struct FieldDefinition: Codable, Equatable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, CaseIterable, Sendable, Identifiable {
        case text, number, date, choice
        public var id: Self { self }
        public var title: String {
            switch self {
            case .text: "Text"
            case .number: "Number"
            case .date: "Date"
            case .choice: "Choice"
            }
        }
    }

    public var id: String
    public var name: String
    public var kind: Kind
    /// For a choice field, in order ("To do", "In progress", "Done").
    public var choices: [String]

    public init(id: String = UUID().uuidString, name: String, kind: Kind, choices: [String] = []) {
        self.id = id
        self.name = name
        self.kind = kind
        self.choices = choices
    }

    /// The value cleaned up for this kind, or nil to clear it ("1,200" → "1200", a bad date → nil).
    public func normalized(_ raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        switch kind {
        case .text: return text
        case .choice: return choices.first { $0.caseInsensitiveCompare(text) == .orderedSame } ?? text
        case .number:
            let digits = text.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")
            guard let value = Double(digits) else { return nil }
            return value == value.rounded() && abs(value) < 1e15 ? String(Int(value)) : String(value)
        case .date:
            return Self.dayFormat.date(from: text) == nil ? nil : text
        }
    }

    /// Dates are stored as "yyyy-MM-dd" so they sort as text and read the same in every time zone.
    public static let dayFormat: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Orders two stored values the way this kind should sort (numbers by value, choices in order).
    public func less(_ a: String?, _ b: String?) -> Bool {
        guard let a else { return false }
        guard let b else { return true }
        switch kind {
        case .number: return (Double(a) ?? 0) < (Double(b) ?? 0)
        case .choice:
            let ia = choices.firstIndex(of: a) ?? .max, ib = choices.firstIndex(of: b) ?? .max
            return ia == ib ? a.localizedStandardCompare(b) == .orderedAscending : ia < ib
        case .text, .date: return a.localizedStandardCompare(b) == .orderedAscending
        }
    }
}

/// Styles by path, and pinned items by folder.
public struct Customizations: Codable, Equatable, Sendable {
    public var styles: [String: ItemStyle] = [:]
    /// Folder path → paths pinned to the top of it, in order.
    public var pinned: [String: [String]] = [:]
    /// The fields you've added, in the order they show.
    public var fieldDefinitions: [FieldDefinition]?

    public init() {}

    enum CodingKeys: String, CodingKey { case styles, pinned, fieldDefinitions }

    // Files saved before a property existed still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        styles = try c.decodeIfPresent([String: ItemStyle].self, forKey: .styles) ?? [:]
        pinned = try c.decodeIfPresent([String: [String]].self, forKey: .pinned) ?? [:]
        fieldDefinitions = try c.decodeIfPresent([FieldDefinition].self, forKey: .fieldDefinitions)
    }

    // MARK: Fields

    public var fields: [FieldDefinition] { fieldDefinitions ?? [] }

    public func field(_ id: String) -> FieldDefinition? { fields.first { $0.id == id } }

    public func value(of fieldID: String, for path: String) -> String? { styles[path]?.fields?[fieldID] }

    public mutating func addField(_ field: FieldDefinition) {
        fieldDefinitions = fields + [field]
    }

    public mutating func updateField(_ field: FieldDefinition) {
        guard let i = fields.firstIndex(where: { $0.id == field.id }) else { return }
        var all = fields
        // A renamed choice keeps its items; a removed one leaves them with the old text.
        all[i] = field
        fieldDefinitions = all
    }

    /// Removes the field and every value set for it.
    public mutating func deleteField(_ id: String) {
        fieldDefinitions = fields.filter { $0.id != id }
        for path in Array(styles.keys) {
            update(path) { style in
                style.fields?[id] = nil
                if style.fields?.isEmpty == true { style.fields = nil }
            }
        }
    }

    /// Sets (or clears, for nil or empty) a field on a path. Values are normalized for the field's kind.
    public mutating func setValue(_ raw: String?, of fieldID: String, for path: String) {
        guard let field = field(fieldID) else { return }
        let value = raw.flatMap(field.normalized)
        update(path) { style in
            var fields = style.fields ?? [:]
            fields[fieldID] = value
            style.fields = fields.isEmpty ? nil : fields
        }
    }

    /// Paths with `value` in a field, sorted. Self-updating sidebar groups use this.
    public func paths(withValue value: String, in fieldID: String) -> [String] {
        styles.compactMap { path, style in style.fields?[fieldID] == value ? path : nil }.sorted()
    }

    /// How many paths have each value of a field.
    public func counts(for fieldID: String) -> [String: Int] {
        var counts: [String: Int] = [:]
        for style in styles.values { if let value = style.fields?[fieldID] { counts[value, default: 0] += 1 } }
        return counts
    }

    /// Paths whose field values contain every word of `query` ("acme invoice").
    public func fieldValuesMatching(_ query: String) -> [String] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init).filter { $0.count >= 2 }
        guard !words.isEmpty, !fields.isEmpty else { return [] }
        return styles.compactMap { path, style in
            guard let values = style.fields, !values.isEmpty else { return nil }
            let text = values.values.joined(separator: " ")
            return words.allSatisfy { text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil } ? path : nil
        }
        .sorted()
    }

    public func style(for path: String) -> ItemStyle? { styles[path] }

    public mutating func update(_ path: String, _ change: (inout ItemStyle) -> Void) {
        var style = styles[path] ?? ItemStyle()
        change(&style)
        styles[path] = style.isEmpty ? nil : style
    }

    /// Something moved or was renamed: its style and pin (and those of anything inside it,
    /// for a folder) follow it.
    public mutating func moved(from old: String, to new: String) {
        guard old != new else { return }
        func rekey(_ path: String) -> String? {
            if path == old { return new }
            if path.hasPrefix(old + "/") { return new + path.dropFirst(old.count) }
            return nil
        }
        for (path, style) in styles {
            guard let moved = rekey(path) else { continue }
            styles[path] = nil
            styles[moved] = style
        }
        var newPins: [String: [String]] = [:]
        for (folder, list) in pinned {
            let folderNow = rekey(folder) ?? folder
            var kept: [String] = []
            for path in list {
                let now = rekey(path) ?? path
                // A pin only makes sense inside its folder.
                if (now as NSString).deletingLastPathComponent == folderNow { kept.append(now) }
            }
            if !kept.isEmpty { newPins[folderNow, default: []] += kept }
        }
        pinned = newPins
    }

    /// Paths whose note contains every word of `query`.
    public func notesMatching(_ query: String) -> [String] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init).filter { $0.count >= 2 }
        guard !words.isEmpty else { return [] }
        return styles.compactMap { path, style in
            guard let note = style.note, words.allSatisfy({ note.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil })
            else { return nil }
            return path
        }
        .sorted()
    }

    /// Every link, with the path it's on, whose title or address contains every word of `query`.
    public func linksMatching(_ query: String) -> [(path: String, link: ItemLink)] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init).filter { $0.count >= 2 }
        guard !words.isEmpty else { return [] }
        var found: [(path: String, link: ItemLink)] = []
        for (path, style) in styles {
            let folderName = (path as NSString).lastPathComponent
            for link in style.links ?? [] {
                let haystack = [link.title, link.url, folderName].joined(separator: " ")
                if words.allSatisfy({ haystack.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }) {
                    found.append((path, link))
                }
            }
        }
        return found.sorted { $0.path == $1.path ? $0.link.title < $1.link.title : $0.path < $1.path }
    }

    public func isPinned(_ path: String) -> Bool {
        let parent = (path as NSString).deletingLastPathComponent
        return pinned[parent]?.contains(path) ?? false
    }

    public mutating func togglePin(_ path: String) {
        let parent = (path as NSString).deletingLastPathComponent
        var list = pinned[parent] ?? []
        if let index = list.firstIndex(of: path) { list.remove(at: index) } else { list.append(path) }
        pinned[parent] = list.isEmpty ? nil : list
    }

    /// `items` with this folder's pinned ones first (in pin order).
    public func pinnedFirst(_ items: [FileItem], in folder: String) -> [FileItem] {
        guard let order = pinned[folder], !order.isEmpty else { return items }
        let rank = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        let top = items.filter { rank[$0.path] != nil }.sorted { rank[$0.path]! < rank[$1.path]! }
        return top + items.filter { rank[$0.path] == nil }
    }
}
