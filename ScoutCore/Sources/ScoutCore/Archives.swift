import Foundation

#if os(macOS)
/// Zip and unzip with the tools macOS ships (ditto keeps Mac metadata like Finder does;
/// bsdtar reads tar, tar.gz, 7z and more).
public enum Archiver {
    public enum Failure: LocalizedError {
        case failed(String)
        public var errorDescription: String? {
            if case .failed(let message) = self { return message }
            return nil
        }
    }

    static let tarSuffixes = [".tar", ".tgz", ".tbz", ".tbz2", ".txz", ".tar.gz", ".tar.bz2", ".tar.xz", ".7z"]

    /// Archives Scout can open.
    public static func canExtract(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return name.hasSuffix(".zip") || tarSuffixes.contains { name.hasSuffix($0) }
    }

    /// "Report.zip" for one item, "Archive.zip" for several, next to them. Returns the archive.
    @discardableResult
    public static func compress(_ urls: [URL]) throws -> URL {
        guard let first = urls.first else { throw Failure.failed("Nothing to compress.") }
        let folder = first.deletingLastPathComponent()
        let name = urls.count == 1 ? first.lastPathComponent + ".zip" : "Archive.zip"
        let destination = LocalFileSource.availableURL(in: folder, preferredName: name, isDirectory: false, style: .numbered)
        let ok: Bool
        if urls.count == 1 {
            ok = CommandRunner.run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", first.filePath,
                                                      destination.filePath], timeout: 3600) != nil
        } else {
            // Several items: zip them by name from their folder, skipping Finder clutter.
            ok = CommandRunner.run("/usr/bin/zip", ["-r", "-y", "-q", destination.filePath]
                                   + urls.map(\.lastPathComponent) + ["-x", "*.DS_Store"],
                                   timeout: 3600, directory: folder) != nil
        }
        guard ok, FileManager.default.fileExists(atPath: destination.filePath) else {
            try? FileManager.default.removeItem(at: destination)
            throw Failure.failed("Couldn’t compress \(urls.count == 1 ? "“\(first.lastPathComponent)”" : "those items").")
        }
        return destination
    }

    /// Extracts next to the archive: a single item lands as-is, several go in a folder
    /// named after the archive. Returns what was created.
    @discardableResult
    public static func extract(_ archive: URL) throws -> URL {
        let folder = archive.deletingLastPathComponent()
        let fm = FileManager.default
        let staging = folder.appending(path: ".scout-extract-\(UUID().uuidString)")
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: staging) }

        let isZip = archive.pathExtension.lowercased() == "zip"
        let ok = isZip
            ? CommandRunner.run("/usr/bin/ditto", ["-x", "-k", archive.filePath, staging.filePath], timeout: 3600) != nil
            : CommandRunner.run("/usr/bin/tar", ["-xf", archive.filePath, "-C", staging.filePath], timeout: 3600) != nil
        guard ok else { throw Failure.failed("Couldn’t open “\(archive.lastPathComponent)”. It may be damaged or a format Scout can’t read.") }

        try? fm.removeItem(at: staging.appending(path: "__MACOSX"))
        let contents = (try? fm.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil))?
            .filter { $0.lastPathComponent != ".DS_Store" } ?? []
        guard !contents.isEmpty else { throw Failure.failed("“\(archive.lastPathComponent)” is empty.") }

        if contents.count == 1 {
            let item = contents[0]
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let destination = LocalFileSource.availableURL(in: folder, preferredName: item.lastPathComponent,
                                                           isDirectory: isDir, style: .numbered)
            try fm.moveItem(at: item, to: destination)
            return destination
        }
        let destination = LocalFileSource.availableURL(in: folder, preferredName: stem(of: archive),
                                                       isDirectory: true, style: .numbered)
        try fm.moveItem(at: staging, to: destination)
        return destination
    }

    /// "Photos.tar.gz" → "Photos".
    static func stem(of archive: URL) -> String {
        var name = archive.lastPathComponent
        for suffix in [".tar.gz", ".tar.bz2", ".tar.xz"] + tarSuffixes + [".zip"]
        where name.lowercased().hasSuffix(suffix) {
            name.removeLast(suffix.count)
            break
        }
        return name
    }
}
#endif
