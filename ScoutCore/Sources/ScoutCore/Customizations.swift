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

    public init(color: String? = nil, symbol: String? = nil, nickname: String? = nil, note: String? = nil) {
        self.color = color
        self.symbol = symbol
        self.nickname = nickname
        self.note = note
    }

    public var isEmpty: Bool {
        color == nil && symbol == nil && (nickname ?? "").isEmpty && (note ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static let colors = ["red", "orange", "yellow", "green", "mint", "teal", "blue", "indigo", "purple", "pink", "gray"]
    public static let symbols = [
        "star.fill", "heart.fill", "briefcase.fill", "graduationcap.fill", "dollarsign.circle.fill", "chart.bar.fill",
        "doc.text.fill", "photo.fill", "music.note", "film.fill", "hammer.fill", "chevron.left.forwardslash.chevron.right",
        "gamecontroller.fill", "airplane", "house.fill", "person.2.fill", "lock.fill", "archivebox.fill",
    ]
}

/// Styles by path, and pinned items by folder.
public struct Customizations: Codable, Equatable, Sendable {
    public var styles: [String: ItemStyle] = [:]
    /// Folder path → paths pinned to the top of it, in order.
    public var pinned: [String: [String]] = [:]

    public init() {}

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
