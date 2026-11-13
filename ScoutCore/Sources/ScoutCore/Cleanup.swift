import Foundation

/// What Clean Up looks for. Each kind says why its items are safe (or worth a look).
public enum CleanupKind: String, CaseIterable, Sendable, Identifiable {
    case devCaches, installers, oldDownloads, largeFiles, duplicates

    public var id: Self { self }

    public var title: String {
        switch self {
        case .devCaches: "Developer caches"
        case .installers: "Installers in Downloads"
        case .oldDownloads: "Old downloads"
        case .largeFiles: "Large files"
        case .duplicates: "Duplicates"
        }
    }

    public var explanation: String {
        switch self {
        case .devCaches: "Build data and package downloads. Tools re-create them when needed."
        case .installers: "Disk images and installer packages. Once an app is installed, these aren't needed."
        case .oldDownloads: "Added to Downloads and not changed in over 90 days."
        case .largeFiles: "Files over 500 MB anywhere in your home folder. Worth a look, not necessarily junk."
        case .duplicates: "Extra copies of files over 1 MB with exactly the same contents. Scout keeps the original and lists the rest."
        }
    }

    public var symbol: String {
        switch self {
        case .devCaches: "hammer"
        case .installers: "shippingbox"
        case .oldDownloads: "clock.arrow.circlepath"
        case .largeFiles: "externaldrive.badge.exclamationmark"
        case .duplicates: "square.on.square"
        }
    }

    /// Safe kinds start ticked; the rest start unticked so nothing surprising goes.
    public var selectedByDefault: Bool { self == .devCaches || self == .installers }
}

public struct CleanupItem: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let path: String
    public let name: String
    public let bytes: Int64
    /// Extra context, e.g. "npm download cache" or "Added Mar 3, 2025".
    public let detail: String?

    public init(path: String, name: String, bytes: Int64, detail: String? = nil) {
        self.path = path
        self.name = name
        self.bytes = bytes
        self.detail = detail
    }
}

public enum CleanupScanner {
    /// Known developer caches, relative to home.
    public static let devCaches: [(path: String, name: String)] = [
        ("Library/Developer/Xcode/DerivedData", "Xcode build data (DerivedData)"),
        ("Library/Developer/Xcode/iOS DeviceSupport", "Xcode device support files"),
        ("Library/Developer/CoreSimulator/Caches", "Simulator caches"),
        ("Library/Caches/Homebrew", "Homebrew downloads"),
        (".npm/_cacache", "npm download cache"),
        ("Library/Caches/pip", "pip download cache"),
        ("Library/Caches/Yarn", "Yarn cache"),
        ("Library/pnpm/store", "pnpm store"),
        ("Library/Caches/CocoaPods", "CocoaPods cache"),
        (".gradle/caches", "Gradle caches"),
        (".cargo/registry/cache", "Cargo download cache"),
        ("Library/Caches/go-build", "Go build cache"),
    ]

    public static let installerExtensions: Set<String> = ["dmg", "pkg", "mpkg", "iso"]

    /// Developer caches that exist, with their sizes. Slow-ish: measures each folder.
    public static func scanDevCaches(home: String, sizeOf: (URL) -> Int64) -> [CleanupItem] {
        devCaches.compactMap { entry in
            let path = home + "/" + entry.path
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            let bytes = sizeOf(URL.folder(path))
            guard bytes > 1_000_000 else { return nil } // skip near-empty ones
            return CleanupItem(path: path, name: entry.name, bytes: bytes, detail: "~/" + entry.path)
        }
        .sorted { $0.bytes > $1.bytes }
    }

    /// Disk images and installer packages sitting at the top of a folder (Downloads).
    public static func scanInstallers(in folder: URL) -> [CleanupItem] {
        topLevel(of: folder).compactMap { item in
            guard installerExtensions.contains(item.url.pathExtension.lowercased()) else { return nil }
            return CleanupItem(path: item.path, name: item.name, bytes: item.size ?? 0,
                               detail: item.dateAdded.map { "Downloaded \($0.formatted(date: .abbreviated, time: .omitted))" })
        }
        .sorted { $0.bytes > $1.bytes }
    }

    /// Top-level items added and last changed more than `days` ago (installers excluded,
    /// they have their own group). Folders count with their full size.
    public static func scanOldDownloads(in folder: URL, now: Date = .now, days: Int = 90,
                                        sizeOf: (URL) -> Int64) -> [CleanupItem] {
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        return topLevel(of: folder).compactMap { item in
            guard !installerExtensions.contains(item.url.pathExtension.lowercased()) else { return nil }
            let touched = [item.dateAdded, item.dateModified].compactMap { $0 }.max() ?? .distantPast
            guard touched < cutoff else { return nil }
            let bytes = item.isNavigable ? sizeOf(item.url) : (item.size ?? 0)
            return CleanupItem(path: item.path, name: item.name, bytes: bytes,
                               detail: "Last changed \(touched.formatted(date: .abbreviated, time: .omitted))")
        }
        .sorted { $0.bytes > $1.bytes }
    }

    /// Folders in your home worth checking for duplicates: everything except Library,
    /// Applications and hidden folders (cloud drives live in Library, so they're skipped).
    public static func duplicateRoots(home: String) -> [URL] {
        let skip: Set<String> = ["Library", "Applications", "Public"]
        let names = (try? FileManager.default.contentsOfDirectory(atPath: home)) ?? []
        return names.filter { !$0.hasPrefix(".") && !skip.contains($0) }
            .map { URL(filePath: home).appending(path: $0) }
            .filter { url in
                var isDir: ObjCBool = false
                return FileManager.default.fileExists(atPath: url.filePath, isDirectory: &isDir) && isDir.boolValue
            }
    }

    /// Every copy except the one to keep, each pointing at the kept original.
    public static func duplicateItems(_ groups: [DuplicateGroup], home: String) -> [CleanupItem] {
        groups.flatMap { group in
            group.paths.dropFirst().map { path in
                CleanupItem(path: path, name: (path as NSString).lastPathComponent, bytes: group.size,
                            detail: "Same as " + PathDisplay.display(group.paths[0], home: home))
            }
        }
        .sorted { $0.bytes != $1.bytes ? $0.bytes > $1.bytes : $0.path < $1.path }
    }

    private static func topLevel(of folder: URL) -> [FileItem] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return urls.compactMap(LocalFileSource.item(for:))
    }
}
