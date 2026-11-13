// `scout`: command-line companion to Scout.app. Ships inside Scout.app/Contents/Helpers.
import Foundation
import ScoutCore

let usage = """
    scout: command-line companion to Scout

      scout jump <query>                   Print the best-matching folder (cd "$(scout jump proj)")
      scout rank [query] [--limit N] [--json]
                                           List matching folders, best first (no query = most used)
      scout open <path> [--new-tab]        Open a folder, or reveal a file, in Scout
      scout index                          Rebuild the folder index now
      scout duplicates [folder…]           List duplicate files (over 1 MB), biggest waste first
    """

struct RankedOutput: Encodable {
    let path: String
    let name: String
    let displayPath: String
    let score: Double
    let visits: Int
}

let home = FileManager.default.homeDirectoryForCurrentUser.filePath
var args = Array(CommandLine.arguments.dropFirst())

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

/// Removes `--name` (and its value, if `takesValue`) from args.
@MainActor
func takeFlag(_ name: String, takesValue: Bool = false) -> String? {
    guard let i = args.firstIndex(of: name) else { return nil }
    args.remove(at: i)
    guard takesValue else { return "" }
    guard i < args.count else { fail("\(name) needs a value") }
    return args.remove(at: i)
}

@MainActor func loadIndex() -> [IndexedFolder] {
    guard let folders = ScoutStore.loadFolders(home: home) else {
        fail("Scout hasn't built its folder index yet. Open Scout once, or run `scout index`.")
    }
    return folders
}

@MainActor func rank(_ query: String, limit: Int) -> [RankedFolder] {
    FolderRanker.rank(query: query, folders: loadIndex(), frecency: ScoutStore.loadHistory(),
                      home: home, limit: limit)
}

let command = args.isEmpty ? "help" : args.removeFirst()

switch command {
case "rank":
    let json = takeFlag("--json") != nil
    let limit = takeFlag("--limit", takesValue: true).flatMap(Int.init) ?? 30
    let history = ScoutStore.loadHistory()
    let results = rank(args.joined(separator: " "), limit: limit)
    if json {
        let output = results.map {
            RankedOutput(path: $0.folder.path, name: $0.folder.name, displayPath: $0.folder.displayPath,
                         score: $0.score, visits: history.entries[$0.folder.path]?.count ?? 0)
        }
        FileHandle.standardOutput.write(try JSONEncoder().encode(output))
    } else {
        for r in results { print(r.folder.path) }
    }

case "jump":
    guard !args.isEmpty else { fail("usage: scout jump <query>") }
    guard let best = rank(args.joined(separator: " "), limit: 1).first else {
        fail("No folder matches “\(args.joined(separator: " "))”.")
    }
    print(best.folder.path)

case "open":
    let newTab = takeFlag("--new-tab") != nil
    guard let raw = args.first else { fail("usage: scout open <path> [--new-tab]") }
    let expanded = PathCompletion.expandTilde(raw, home: home)
    let absolute = expanded.hasPrefix("/")
        ? expanded : FileManager.default.currentDirectoryPath + "/" + expanded
    let path = URL(filePath: absolute).standardizedFileURL.filePath
    guard FileManager.default.fileExists(atPath: path) else { fail("Nothing exists at \(path)") }
    let opener = Process()
    opener.executableURL = URL(filePath: "/usr/bin/open")
    opener.arguments = [ScoutLink.open(path: path, newTab: newTab).url.absoluteString]
    try opener.run()
    opener.waitUntilExit()

case "index":
    let start = Date()
    let folders = FolderIndexer.scan(roots: ScoutStore.defaultIndexRoots(home: home), home: home)
    try ScoutStore.saveFolders(folders)
    print("Indexed \(folders.count.formatted()) folders in \(String(format: "%.1f", Date().timeIntervalSince(start)))s")

case "duplicates", "dupes":
    let start = Date()
    let roots = args.isEmpty ? CleanupScanner.duplicateRoots(home: home)
        : args.map { URL.folder(PathCompletion.expandTilde($0, home: home)) }
    let groups = DuplicateFinder.find(in: roots)
    for group in groups {
        print("\(ByteCountFormatter.string(fromByteCount: group.wasted, countStyle: .file)) wasted")
        for (index, path) in group.paths.enumerated() {
            print("  \(index == 0 ? "keep" : "    ") \(PathDisplay.display(path, home: home))")
        }
    }
    let total = groups.reduce(Int64(0)) { $0 + $1.wasted }
    print("\(groups.count) groups, \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file)) wasted, "
        + "\(String(format: "%.1f", Date().timeIntervalSince(start)))s")

case "help", "-h", "--help":
    print(usage)

default:
    fail("Unknown command “\(command)”.\n\n" + usage)
}
