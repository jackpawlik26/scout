import Foundation

/// What Clean Up looks for. Each kind says why its items are safe (or worth a look).
public enum CleanupKind: String, CaseIterable, Sendable, Identifiable {
    case devCaches, installers, oldDownloads, largeFiles, duplicates,
         oldNodeModules, screenRecordings, mailAttachments, appLeftovers, unusedApps

    public var id: Self { self }

    public var title: String {
        switch self {
        case .devCaches: "Developer caches"
        case .installers: "Installers in Downloads"
        case .oldDownloads: "Old downloads"
        case .largeFiles: "Large files"
        case .duplicates: "Duplicates"
        case .oldNodeModules: "Old node_modules"
        case .screenRecordings: "Screen recordings"
        case .mailAttachments: "Mail attachments"
        case .appLeftovers: "Leftovers from deleted apps"
        case .unusedApps: "Apps you don’t use"
        }
    }

    public var explanation: String {
        switch self {
        case .devCaches: "Build data and package downloads. Tools re-create them when needed."
        case .installers: "Disk images and installer packages. Once an app is installed, these aren't needed."
        case .oldDownloads: "Added to Downloads and not changed in over 90 days."
        case .largeFiles: "Files over 500 MB anywhere in your home folder. Worth a look, not necessarily junk."
        case .duplicates: "Extra copies of files over 1 MB with exactly the same contents. Scout keeps the original and lists the rest."
        case .oldNodeModules: "Dependencies in projects untouched for 6 months. “npm install” brings them back."
        case .screenRecordings: "Screen recordings over 30 days old on your Desktop and in Movies, Documents and Downloads."
        case .mailAttachments: "Attachments Mail saved when you opened them. The originals stay in your email."
        case .appLeftovers: "Data and caches from apps that aren’t installed anymore."
        case .unusedApps: "Apps not opened in 6 months (Apple’s own apps aren’t listed)."
        }
    }

    public var symbol: String {
        switch self {
        case .devCaches: "hammer"
        case .installers: "shippingbox"
        case .oldDownloads: "clock.arrow.circlepath"
        case .largeFiles: "externaldrive.badge.exclamationmark"
        case .duplicates: "square.on.square"
        case .oldNodeModules: "shippingbox"
        case .screenRecordings: "record.circle"
        case .mailAttachments: "paperclip"
        case .appLeftovers: "puzzlepiece.extension"
        case .unusedApps: "app.dashed"
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
    /// For a duplicate: the copy Scout keeps. It must never go to the Trash with this one.
    public let original: String?

    public init(path: String, name: String, bytes: Int64, detail: String? = nil, original: String? = nil) {
        self.path = path
        self.name = name
        self.bytes = bytes
        self.detail = detail
        self.original = original
    }

    /// The items safe to trash together: drops any duplicate whose kept copy is also being
    /// trashed (picked in another group, or inside a picked folder), so one copy always survives.
    public static func safeToTrash(_ items: [CleanupItem]) -> [CleanupItem] {
        let paths = items.map(\.path)
        func trashed(_ path: String) -> Bool { paths.contains { path == $0 || path.hasPrefix($0 + "/") } }
        return items.filter { item in item.original.map { !trashed($0) } ?? true }
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
                            detail: "Same as " + PathDisplay.display(group.paths[0], home: home),
                            original: group.paths[0])
            }
        }
        .sorted { $0.bytes != $1.bytes ? $0.bytes > $1.bytes : $0.path < $1.path }
    }

    /// node_modules folders (up to 5 levels into your folders) whose project hasn't changed in `days`.
    public static func scanOldNodeModules(home: String, now: Date = .now, days: Int = 180,
                                          sizeOf: (URL) -> Int64) -> [CleanupItem] {
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        var found: [CleanupItem] = []
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey, .isPackageKey]
        for root in duplicateRoots(home: home) {
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                                  options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in enumerator {
                guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
                if enumerator.level > 5 { enumerator.skipDescendants(); continue }
                guard url.lastPathComponent == "node_modules" else { continue }
                enumerator.skipDescendants()
                let project = url.deletingLastPathComponent()
                let touched = [project.appending(path: "package.json"), project.appending(path: "package-lock.json"), url]
                    .compactMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
                    .max() ?? .distantPast
                guard touched < cutoff else { continue }
                found.append(CleanupItem(path: url.filePath, name: project.lastPathComponent + "/node_modules",
                                         bytes: sizeOf(url),
                                         detail: "Project last changed \(touched.formatted(date: .abbreviated, time: .omitted))"))
            }
        }
        return found.filter { $0.bytes > 1_000_000 }.sorted { $0.bytes > $1.bytes }
    }

    /// "Screen Recording …" videos older than `days` in the usual places.
    public static func scanScreenRecordings(home: String, now: Date = .now, days: Int = 30) -> [CleanupItem] {
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        let videoExtensions: Set<String> = ["mov", "mp4", "m4v"]
        return ["Desktop", "Movies", "Documents", "Downloads"].flatMap { folder in
            topLevel(of: URL.folder(home + "/" + folder)).compactMap { item -> CleanupItem? in
                let lower = item.name.lowercased()
                guard !item.isDirectory, videoExtensions.contains(item.url.pathExtension.lowercased()),
                      lower.hasPrefix("screen recording") || lower.hasPrefix("cleanshot") || lower.hasPrefix("screen shot"),
                      let date = item.dateCreated ?? item.dateModified, date < cutoff else { return nil }
                return CleanupItem(path: item.path, name: item.name, bytes: item.size ?? 0,
                                   detail: "Recorded \(date.formatted(date: .abbreviated, time: .omitted)) · ~/\(folder)")
            }
        }
        .sorted { $0.bytes > $1.bytes }
    }

    /// Files Mail saved from attachments you opened.
    public static func scanMailAttachments(home: String) -> [CleanupItem] {
        let folders = [home + "/Library/Containers/com.apple.mail/Data/Library/Mail Downloads", home + "/Library/Mail Downloads"]
        return folders.flatMap { folder in
            ((try? FileManager.default.contentsOfDirectory(at: URL.folder(folder), includingPropertiesForKeys: nil,
                                                           options: [.skipsHiddenFiles])) ?? []).compactMap { url -> CleanupItem? in
                let bytes = FolderStats.size(of: url, fileLimit: 50_000).bytes
                guard bytes > 0 else { return nil }
                let name = (try? FileManager.default.contentsOfDirectory(atPath: url.filePath).first) ?? url.lastPathComponent
                return CleanupItem(path: url.filePath, name: name, bytes: bytes, detail: "Mail Downloads")
            }
        }
        .sorted { $0.bytes > $1.bytes }
    }

    /// Sandboxed app data and caches named after apps that aren't installed. Apple's are skipped.
    public static func scanAppLeftovers(home: String, isInstalled: (String) -> Bool, sizeOf: (URL) -> Int64) -> [CleanupItem] {
        let places = [("Library/Containers", "App data"), ("Library/Caches", "Cache")]
        var items: [CleanupItem] = []
        for (relative, label) in places {
            let folder = URL.folder(home + "/" + relative)
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.filePath)) ?? []
            for name in names {
                // Only reverse-DNS names (com.vendor.App) can be matched to an app reliably.
                let parts = name.split(separator: ".")
                guard parts.count >= 3, !name.hasPrefix("com.apple."), !name.hasPrefix("."),
                      !isInstalled(name) else { continue }
                let url = folder.appending(path: name)
                let bytes = sizeOf(url)
                guard bytes > 1_000_000 else { continue }
                items.append(CleanupItem(path: url.filePath, name: name, bytes: bytes, detail: "\(label) · ~/\(relative)"))
            }
        }
        return items.sorted { $0.bytes > $1.bytes }
    }

    /// Apps in /Applications not opened in `days` (never-opened ones count too). Apple's are skipped.
    public static func scanUnusedApps(now: Date = .now, days: Int = 180, lastUsed: (URL) -> Date?,
                                      sizeOf: (URL) -> Int64) -> [CleanupItem] {
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        let apps = (try? FileManager.default.contentsOfDirectory(at: URL.folder("/Applications"), includingPropertiesForKeys: nil)) ?? []
        return apps.compactMap { app -> CleanupItem? in
            guard app.pathExtension == "app",
                  let bundleID = Bundle(url: app)?.bundleIdentifier, !bundleID.hasPrefix("com.apple.") else { return nil }
            let used = lastUsed(app)
            guard (used ?? .distantPast) < cutoff else { return nil }
            let detail = used.map { "Last opened \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "Never opened"
            return CleanupItem(path: app.filePath, name: app.deletingPathExtension().lastPathComponent, bytes: sizeOf(app),
                               detail: detail)
        }
        .sorted { $0.bytes > $1.bytes }
    }

    private static func topLevel(of folder: URL) -> [FileItem] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return urls.compactMap(LocalFileSource.item(for:))
    }
}
