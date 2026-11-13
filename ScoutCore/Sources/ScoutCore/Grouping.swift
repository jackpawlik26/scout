import Foundation
import UniformTypeIdentifiers

/// Finder-style "Group By": the list splits into labeled blocks.
public enum GroupBy: String, CaseIterable, Sendable, Identifiable {
    case none, kind, dateModified, dateAdded, dateCreated, size, name, dateOpened, tags

    public var id: Self { self }

    /// Choices for a folder (Date Last Opened is only known in Recents).
    public static let folderChoices: [GroupBy] = [.none, .kind, .dateModified, .dateAdded, .dateCreated, .size, .name, .tags]

    /// Finder's ⌃⌘ shortcut digits.
    public var shortcutDigit: Character? {
        switch self {
        case .none: "0"
        case .name: "1"
        case .kind: "2"
        case .size: "3"
        case .dateAdded: "5"
        case .dateModified: "6"
        case .dateCreated: "7"
        case .tags: "8"
        case .dateOpened: nil
        }
    }

    public var title: String {
        switch self {
        case .none: "None"
        case .kind: "Kind"
        case .dateModified: "Date Modified"
        case .dateAdded: "Date Added"
        case .dateCreated: "Date Created"
        case .size: "Size"
        case .name: "Name"
        case .dateOpened: "Date Last Opened"
        case .tags: "Tags"
        }
    }
}

/// One labeled block of items.
public struct ItemGroup: Identifiable, Equatable, Sendable {
    public var id: String { title }
    public let title: String
    public var items: [FileItem]

    public init(title: String, items: [FileItem]) {
        self.title = title
        self.items = items
    }
}

/// Finer kinds than FileCategory, matching how Finder groups by Kind.
public enum KindGroup: Int, CaseIterable, Sendable {
    case folders, applications, documents, pdfs, spreadsheets, presentations, images, movies, music,
         text, code, archives, diskImages, other

    public var title: String {
        switch self {
        case .folders: "Folders"
        case .applications: "Applications"
        case .documents: "Documents"
        case .pdfs: "PDF Documents"
        case .spreadsheets: "Spreadsheets"
        case .presentations: "Presentations"
        case .images: "Images"
        case .movies: "Movies"
        case .music: "Music"
        case .text: "Text"
        case .code: "Code"
        case .archives: "Archives"
        case .diskImages: "Disk Images & Installers"
        case .other: "Other"
        }
    }

    public static func of(_ item: FileItem) -> KindGroup {
        if item.isNavigable { return .folders }
        let ext = item.url.pathExtension.lowercased()
        guard let type = item.typeIdentifier.flatMap(UTType.init) ?? UTType(filenameExtension: ext) else { return .other }
        if type.conforms(to: .applicationBundle) { return .applications }
        if type.conforms(to: .pdf) { return .pdfs }
        if type.conforms(to: .spreadsheet) || ["xlsx", "xls", "numbers", "csv"].contains(ext) { return .spreadsheets }
        if type.conforms(to: .presentation) || ["pptx", "ppt", "key"].contains(ext) { return .presentations }
        if type.conforms(to: .image) { return .images }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .movies }
        if type.conforms(to: .audio) { return .music }
        if type.conforms(to: .diskImage) || ["dmg", "iso", "pkg", "mpkg", "exe", "msi"].contains(ext) { return .diskImages }
        if type.conforms(to: .archive) || ["zip", "gz", "tgz", "7z", "rar", "tar", "bz2", "xz"].contains(ext) { return .archives }
        if type.conforms(to: .sourceCode) || type.conforms(to: .script) || type.conforms(to: .json)
            || type.conforms(to: .yaml) || type.conforms(to: .xml) { return .code }
        if ["doc", "docx", "pages", "rtf", "odt", "epub"].contains(ext) || type.conforms(to: .rtf)
            || type.conforms(to: .compositeContent) || type.conforms(to: .epub) { return .documents }
        if type.conforms(to: .plainText) || type.conforms(to: .text) { return .text }
        return .other
    }
}

public enum ItemGrouper {
    /// Splits `items` (already sorted) into groups, keeping their order inside each group.
    /// Group order: dates newest first, sizes biggest first, kinds Folders then A–Z, names A–Z.
    public static func groups(_ items: [FileItem], by groupBy: GroupBy, now: Date = .now,
                              calendar: Calendar = .current) -> [ItemGroup] {
        guard groupBy != .none else { return [ItemGroup(title: "", items: items)] }
        var buckets: [String: [FileItem]] = [:]
        var rank: [String: Double] = [:]
        for item in items {
            let (title, order) = key(for: item, by: groupBy, now: now, calendar: calendar)
            buckets[title, default: []].append(item)
            rank[title] = order
        }
        return buckets.keys
            .sorted { (rank[$0]!, $0) < (rank[$1]!, $1) }
            .map { ItemGroup(title: $0, items: buckets[$0]!) }
    }

    /// The group title for an item and a number to order groups by (lower first).
    static func key(for item: FileItem, by groupBy: GroupBy, now: Date, calendar: Calendar) -> (String, Double) {
        switch groupBy {
        case .none:
            return ("", 0)
        case .kind:
            let kind = KindGroup.of(item)
            return (kind.title, kind == .folders ? 0 : (kind == .other ? 2 : 1))
        case .name:
            guard let first = item.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).first,
                  first.isLetter else { return ("#", 0) }
            return (String(first).uppercased(), 1)
        case .size:
            let bytes = item.size ?? item.folderBytes
            guard let bytes else { return ("Folders", 9) }
            let bands: [(Int64, String)] = [
                (1_000_000_000, "Over 1 GB"), (100_000_000, "100 MB – 1 GB"), (10_000_000, "10 – 100 MB"),
                (1_000_000, "1 – 10 MB"), (100_000, "100 KB – 1 MB"), (1, "Under 100 KB"),
            ]
            for (index, band) in bands.enumerated() where bytes >= band.0 { return (band.1, Double(index)) }
            return ("Empty", 8)
        case .dateOpened:
            return dateKey(item.lastOpened, now: now, calendar: calendar)
        case .tags:
            guard let tag = item.tags.first else { return ("No Tags", 9) }
            return (tag.name, 1)
        case .dateModified, .dateAdded, .dateCreated:
            let date = groupBy == .dateModified ? item.dateModified : groupBy == .dateAdded ? item.dateAdded : item.dateCreated
            return dateKey(date, now: now, calendar: calendar)
        }
    }

    /// Today, Yesterday, Previous 7 Days, Previous 30 Days, then months this year, then years.
    static func dateKey(_ date: Date?, now: Date, calendar: Calendar) -> (String, Double) {
        guard let date else { return ("No Date", .greatestFiniteMagnitude) }
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: day, to: today).day ?? 0
        if days <= 0 { return ("Today", 0) }
        if days == 1 { return ("Yesterday", 1) }
        if days < 7 { return ("Previous 7 Days", 2) }
        if days < 30 { return ("Previous 30 Days", 3) }
        // Older: by month this year, by year before that. Newest first.
        let age = now.timeIntervalSince(date)
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            let month = calendar.monthSymbols[calendar.component(.month, from: date) - 1]
            return (month, 4 + age / 1e10)
        }
        return (String(calendar.component(.year, from: date)), 5 + age / 1e10)
    }
}
