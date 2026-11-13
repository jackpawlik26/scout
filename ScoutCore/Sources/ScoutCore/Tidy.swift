import Foundation

/// Tidy Folder: a plan to move loose files into folders by kind ("PDFs", "Images",
/// "Installers"…). Nothing moves until you confirm; folders and hidden files stay put.
public enum Tidy {
    public struct Move: Equatable, Sendable {
        public let item: FileItem
        /// The folder it goes into ("PDFs").
        public let folder: String
    }

    /// Unfinished downloads.
    static let downloading: Set<String> = ["crdownload", "download", "part", "partial", "opdownload"]

    public static func folderName(for item: FileItem) -> String {
        let lower = item.name.lowercased()
        if lower.hasPrefix("screenshot") || lower.hasPrefix("cleanshot") || lower.hasPrefix("screen shot")
            || lower.hasPrefix("screen recording") {
            return "Screenshots"
        }
        switch KindGroup.of(item) {
        case .pdfs: return "PDFs"
        case .images: return "Images"
        case .movies: return "Videos"
        case .music: return "Audio"
        case .documents, .text: return "Documents"
        case .spreadsheets: return "Spreadsheets"
        case .presentations: return "Presentations"
        case .archives: return "Archives"
        case .diskImages: return "Installers"
        case .code: return "Code"
        case .applications: return "Apps"
        case .folders, .other: return "Other"
        }
    }

    /// What would move. Skips folders, apps, hidden files, unfinished downloads, files added in the
    /// last 2 minutes, and files that already sit in a folder with their kind's name.
    public static func plan(for items: [FileItem], in folder: URL, now: Date = .now) -> [Move] {
        let here = folder.lastPathComponent
        return items.compactMap { item -> Move? in
            guard !item.isDirectory, !item.isHidden,
                  !downloading.contains(item.url.pathExtension.lowercased()) else { return nil }
            if let added = item.dateAdded, now.timeIntervalSince(added) < 120 { return nil }
            let target = folderName(for: item)
            guard target != here else { return nil }
            return Move(item: item, folder: target)
        }
    }

    /// Moves are grouped by folder for the confirmation sheet, biggest group first.
    public static func summary(_ moves: [Move]) -> [(folder: String, count: Int)] {
        Dictionary(grouping: moves, by: \.folder)
            .map { ($0.key, $0.value.count) }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
    }
}
