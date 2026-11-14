import Foundation

/// Your own commands: scripts in `~/Library/Application Support/Scout/Actions/`. Each one
/// shows up in ⌘K and the right-click menu as "Run …", and runs with the selected files'
/// paths as arguments, in the folder you're looking at.
public struct UserAction: Hashable, Identifiable, Sendable {
    public var id: String { url.filePath }
    public let url: URL
    /// "Resize for Web" from "resize-for-web.sh" or "Resize for Web.py".
    public let title: String
    /// What runs it: the script itself when it's executable, otherwise an interpreter.
    public let launchPath: String
    public let leadingArguments: [String]

    public static var folder: URL { ScoutStore.directory.appending(path: "Actions", directoryHint: .isDirectory) }

    /// Interpreters for scripts that aren't marked executable.
    static let interpreters: [String: [String]] = [
        "sh": ["/bin/zsh"], "zsh": ["/bin/zsh"], "bash": ["/bin/bash"],
        "py": ["/usr/bin/env", "python3"], "rb": ["/usr/bin/env", "ruby"], "js": ["/usr/bin/env", "node"],
        "applescript": ["/usr/bin/osascript"], "scpt": ["/usr/bin/osascript"],
    ]

    /// The scripts in `folder`, by title. Skips hidden files, folders and files it can't run.
    public static func load(from folder: URL = folder) -> [UserAction] {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey],
                                                      options: [.skipsHiddenFiles]) else { return [] }
        return urls.compactMap { url -> UserAction? in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true else { return nil }
            let ext = url.pathExtension.lowercased()
            let title = title(for: url)
            if let interpreter = interpreters[ext] {
                return UserAction(url: url, title: title, launchPath: interpreter[0],
                                  leadingArguments: Array(interpreter.dropFirst()) + [url.filePath])
            }
            if fm.isExecutableFile(atPath: url.filePath) {
                return UserAction(url: url, title: title, launchPath: url.filePath, leadingArguments: [])
            }
            return nil
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// "resize-for-web.sh" → "Resize for Web"; names with capitals or spaces stay as written.
    static func title(for url: URL) -> String {
        let stem = url.deletingPathExtension().lastPathComponent
        guard stem == stem.lowercased(), stem.contains(where: { $0 == "-" || $0 == "_" }) else {
            return stem
        }
        let small: Set<String> = ["a", "an", "and", "for", "in", "of", "on", "or", "the", "to", "with"]
        return stem.split(whereSeparator: { $0 == "-" || $0 == "_" }).enumerated().map { index, word in
            index > 0 && small.contains(String(word)) ? String(word) : word.prefix(1).uppercased() + word.dropFirst()
        }.joined(separator: " ")
    }

    /// The full argument list: interpreter arguments, then the selected paths.
    public func arguments(for paths: [String]) -> [String] { leadingArguments + paths }

    /// A starter script, written the first time the Actions folder is opened.
    public static let example = """
        #!/bin/zsh
        # Scout runs scripts in this folder from ⌘K (type > and the name) and the right-click menu.
        # The selected files arrive as arguments; the folder you're looking at is the current directory
        # (also in $SCOUT_FOLDER). Anything printed is shown when the script finishes.
        #
        # This example counts the lines in each selected text file. Delete it or make your own.
        for file in "$@"; do
          echo "$(wc -l < "$file" | tr -d ' ') lines: ${file:t}"
        done
        """
}
