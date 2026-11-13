import Foundation

/// Turns raw paths into the friendly versions people recognize.
public enum PathDisplay {
    public static func display(_ path: String, home: String) -> String {
        let iCloud = home + "/Library/Mobile Documents/com~apple~CloudDocs"
        if path == iCloud || path.hasPrefix(iCloud + "/") {
            return "iCloud Drive" + path.dropFirst(iCloud.count)
        }
        let cloudStorage = home + "/Library/CloudStorage/"
        if path.hasPrefix(cloudStorage) {
            let rest = path.dropFirst(cloudStorage.count)
            let folder = rest.prefix { $0 != "/" }
            return cloudName(String(folder)) + rest.dropFirst(folder.count)
        }
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }
}

extension PathDisplay {
    /// Friendly names for ~/Library/CloudStorage folders:
    /// "OneDrive-Personal" → "OneDrive (Personal)", "GoogleDrive-me@gmail.com" → "Google Drive",
    /// "ProtonDrive-me@proton.me-folder" → "Proton Drive".
    public static func cloudName(_ folder: String) -> String {
        let provider: Substring
        var account: Substring
        if let dash = folder.firstIndex(of: "-") {
            provider = folder[..<dash]
            account = folder[folder.index(after: dash)...]
        } else {
            provider = Substring(folder)
            account = ""
        }
        if account.hasSuffix("-folder") { account = account.dropLast("-folder".count) }
        if account.contains("@") { account = "" } // email addresses add noise

        let names = ["OneDrive": "OneDrive", "GoogleDrive": "Google Drive", "ProtonDrive": "Proton Drive",
                     "Dropbox": "Dropbox", "Box": "Box", "iCloudDrive": "iCloud Drive"]
        let name = names[String(provider)] ?? String(provider)
        return account.isEmpty ? name : "\(name) (\(account))"
    }
}

/// Typing paths in "Go to Path" (⌘L): "~" expansion and Tab completion.
public enum PathCompletion {
    public static func expandTilde(_ input: String, home: String) -> String {
        if input == "~" { return home }
        if input.hasPrefix("~/") { return home + input.dropFirst(1) }
        return input
    }

    /// Completes the last folder name in `input`. Returns nil when there's nothing
    /// to add. One match → full name plus "/"; several → their shared beginning.
    public static func complete(_ input: String, home: String) -> String? {
        let expanded = expandTilde(input, home: home)
        guard expanded.hasPrefix("/") else { return nil }

        let parent: String
        let partial: String
        if expanded.hasSuffix("/") {
            parent = expanded
            partial = ""
        } else {
            parent = (expanded as NSString).deletingLastPathComponent
            partial = (expanded as NSString).lastPathComponent
        }

        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: parent) else { return nil }
        let showHidden = partial.hasPrefix(".")
        let matches = names.filter { name in
            guard showHidden || !name.hasPrefix(".") else { return false }
            guard name.lowercased().hasPrefix(partial.lowercased()) else { return false }
            var isDir: ObjCBool = false
            let full = (parent as NSString).appendingPathComponent(name)
            return fm.fileExists(atPath: full, isDirectory: &isDir) && isDir.boolValue
        }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }

        guard let first = matches.first else { return nil }
        let base = parent.hasSuffix("/") ? parent : parent + "/"

        let completed: String
        if matches.count == 1 {
            completed = base + first + "/"
        } else {
            let common = commonPrefix(matches)
            // Progress = more letters, or fixing the case ("p" → "P").
            guard common.count > partial.count || common != partial else { return nil }
            completed = base + common
        }

        if input.hasPrefix("~"), completed.hasPrefix(home) {
            return "~" + completed.dropFirst(home.count)
        }
        return completed
    }

    /// Case-insensitive shared beginning, keeping the first name's casing.
    static func commonPrefix(_ names: [String]) -> String {
        guard var prefix = names.first.map(Array.init) else { return "" }
        for name in names.dropFirst() {
            let other = Array(name)
            var n = 0
            while n < prefix.count, n < other.count,
                  prefix[n].lowercased() == other[n].lowercased() { n += 1 }
            prefix = Array(prefix.prefix(n))
        }
        return String(prefix)
    }
}
