import Foundation

#if os(macOS)
/// Earlier versions macOS keeps of a document (apps like Pages, TextEdit and Preview save
/// them as you work). The info panel lists them; you can save one as a copy or restore it.
public enum FileVersions {
    public struct Version: Identifiable, Sendable, Hashable {
        public var id: URL { url }
        /// Where macOS keeps this version's contents (readable, for Quick Look and copying).
        public let url: URL
        public let date: Date?
        /// The Mac that saved it, when it came from another one (iCloud).
        public let computer: String?
    }

    /// Versions other than the current one, newest first.
    public static func list(_ url: URL) -> [Version] {
        (NSFileVersion.otherVersionsOfItem(at: url) ?? [])
            .map { Version(url: $0.url, date: $0.modificationDate, computer: $0.localizedNameOfSavingComputer) }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    /// Saves a version next to the file as "name (Nov 3, 2026 at 4.05 PM).ext". Returns the copy.
    public static func saveCopy(_ version: Version, of url: URL) throws -> URL {
        let stem = url.deletingPathExtension().lastPathComponent
        let stamp = (version.date ?? .now).formatted(date: .abbreviated, time: .shortened)
            .replacingOccurrences(of: ":", with: ".")
        let name = url.pathExtension.isEmpty ? "\(stem) (\(stamp))" : "\(stem) (\(stamp)).\(url.pathExtension)"
        let target = LocalFileSource.availableURL(in: url.deletingLastPathComponent(), preferredName: name,
                                                  isDirectory: false, style: .numbered)
        try FileManager.default.copyItem(at: version.url, to: target)
        return target
    }

    /// Puts a version back in place. The current contents are kept as a version first, so
    /// restoring can itself be undone from the same list.
    public static func restore(_ version: Version, of url: URL) throws {
        _ = try NSFileVersion.addOfItem(at: url, withContentsOf: url, options: [])
        guard let match = (NSFileVersion.otherVersionsOfItem(at: url) ?? []).first(where: { $0.url == version.url }) else {
            throw CocoaError(.fileNoSuchFile)
        }
        _ = try match.replaceItem(at: url, options: [])
    }
}
#endif
