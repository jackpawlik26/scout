import Foundation

/// How git sees one file (or, for folders, the most important change inside).
public enum GitFileState: Int, Comparable, Sendable {
    case untracked = 1
    case renamed
    case added
    case deleted
    case modified
    case conflicted

    /// The one-letter badge shown next to a file.
    public var letter: String {
        switch self {
        case .untracked: "U"
        case .renamed: "R"
        case .added: "A"
        case .deleted: "D"
        case .modified: "M"
        case .conflicted: "!"
        }
    }

    public var title: String {
        switch self {
        case .untracked: "Untracked"
        case .renamed: "Renamed"
        case .added: "Added"
        case .deleted: "Deleted"
        case .modified: "Modified"
        case .conflicted: "Conflict"
        }
    }

    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

/// A snapshot of `git status` for one repository.
public struct GitStatus: Equatable, Sendable {
    /// The repository's top folder.
    public var root: String
    /// Branch name, or nil when detached.
    public var branch: String?
    /// Short commit hash (for detached HEAD); nil before the first commit.
    public var commit: String?
    public var upstream: String?
    public var ahead = 0
    public var behind = 0
    /// Changed files, keyed by path relative to `root`. Untracked folders end in "/".
    public var changes: [String: GitFileState] = [:]

    public init(root: String, branch: String? = nil, commit: String? = nil) {
        self.root = root
        self.branch = branch
        self.commit = commit
    }

    /// Branch name, or the short commit when detached.
    public var headName: String { branch ?? commit.map { String($0.prefix(7)) } ?? "No commits" }

    public var changeCount: Int { changes.count }

    /// Path of `absolutePath` inside the repository ("" for the root), or nil if it's outside.
    public func relativePath(_ absolutePath: String) -> String? {
        if absolutePath == root { return "" }
        let prefix = root.hasSuffix("/") ? root : root + "/"
        guard absolutePath.hasPrefix(prefix) else { return nil }
        return String(absolutePath.dropFirst(prefix.count))
    }

    /// The state to badge `absolutePath` with. Folders show the strongest change inside them.
    public func state(for absolutePath: String, isFolder: Bool) -> GitFileState? {
        guard let relative = relativePath(absolutePath), !relative.isEmpty else { return nil }
        if let state = changes[relative] ?? changes[relative + "/"] { return state }
        // Inside an untracked folder: untracked too.
        var parent = relative
        while let slash = parent.lastIndex(of: "/") {
            parent = String(parent[..<slash])
            if changes[parent + "/"] == .untracked { return .untracked }
        }
        guard isFolder else { return nil }
        let prefix = relative + "/"
        return changes.lazy.filter { $0.key.hasPrefix(prefix) }.map(\.value).max()
    }
}

/// Parses `git status --porcelain=v2 --branch -z`.
public enum GitStatusParser {
    public static func parse(_ output: String, root: String) -> GitStatus {
        var status = GitStatus(root: root)
        var records = output.split(separator: "\0", omittingEmptySubsequences: true)[...]
        while let record = records.popFirst() {
            let line = String(record)
            if line.hasPrefix("# ") {
                parseHeader(line.dropFirst(2), into: &status)
                continue
            }
            guard let kind = line.first else { continue }
            switch kind {
            case "1":
                // 1 XY sub mH mI mW hH hI path
                if let (xy, path) = fields(line, before: 8) { status.changes[path] = state(xy) }
            case "2":
                // 2 XY sub mH mI mW hH hI Xscore path, then the original path as its own record
                if let (_, path) = fields(line, before: 9) { status.changes[path] = .renamed }
                _ = records.popFirst()
            case "u":
                if let (_, path) = fields(line, before: 10) { status.changes[path] = .conflicted }
            case "?":
                status.changes[String(line.dropFirst(2))] = .untracked
            default:
                break // "!" = ignored
            }
        }
        return status
    }

    private static func parseHeader(_ header: Substring, into status: inout GitStatus) {
        let parts = header.split(separator: " ", maxSplits: 1)
        guard parts.count == 2 else { return }
        let value = String(parts[1])
        switch parts[0] {
        case "branch.oid": status.commit = value == "(initial)" ? nil : value
        case "branch.head": status.branch = value == "(detached)" ? nil : value
        case "branch.upstream": status.upstream = value
        case "branch.ab":
            for part in value.split(separator: " ") {
                if part.hasPrefix("+") { status.ahead = Int(part.dropFirst()) ?? 0 }
                if part.hasPrefix("-") { status.behind = Int(part.dropFirst()) ?? 0 }
            }
        default: break
        }
    }

    /// Splits off `count` space-separated fields (after the record type); the rest is the path.
    private static func fields(_ line: String, before count: Int) -> (xy: Substring, path: String)? {
        let parts = line.split(separator: " ", maxSplits: count, omittingEmptySubsequences: false)
        guard parts.count == count + 1 else { return nil }
        return (parts[1], String(parts[count]))
    }

    /// XY is index then worktree status, "." for unchanged.
    private static func state(_ xy: Substring) -> GitFileState {
        let codes = Set(xy)
        if codes.contains("D") { return .deleted }
        if codes.contains("M") || codes.contains("T") { return .modified }
        if codes.contains("A") { return .added }
        if codes.contains("R") || codes.contains("C") { return .renamed }
        return .modified
    }
}

public enum Git {
    /// The repository containing `path` (the folder holding `.git`), found without running git.
    public static func repositoryRoot(containing path: String, fileManager: FileManager = .default) -> String? {
        var url = URL(filePath: path)
        while true {
            if fileManager.fileExists(atPath: url.appending(path: ".git").filePath) {
                return url.filePath
            }
            let parent = url.deletingLastPathComponent()
            if parent.filePath == url.filePath { return nil }
            url = parent
        }
    }

    /// `https://github.com/owner/repo` for a GitHub remote URL (SSH or HTTPS), else nil.
    public static func gitHubURL(fromRemote remote: String) -> URL? {
        var path: Substring
        let remote = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        if remote.hasPrefix("git@github.com:") {
            path = remote.dropFirst("git@github.com:".count)
        } else if let url = URL(string: remote), let host = url.host(), host == "github.com" || host.hasSuffix("@github.com") {
            path = Substring(url.path())
        } else if remote.hasPrefix("ssh://git@github.com/") {
            path = remote.dropFirst("ssh://git@github.com/".count)
        } else {
            return nil
        }
        path = path.drop { $0 == "/" }
        if path.hasSuffix(".git") { path = path.dropLast(4) }
        guard path.split(separator: "/").count == 2 else { return nil }
        return URL(string: "https://github.com/\(path)")
    }

    /// The GitHub page for a file or folder inside a repository.
    public static func gitHubURL(repo: URL, ref: String, relativePath: String, isFolder: Bool) -> URL {
        guard !relativePath.isEmpty else { return isFolder ? repo.appending(path: "tree/\(ref)") : repo }
        return repo.appending(path: "\(isFolder ? "tree" : "blob")/\(ref)/\(relativePath)")
    }
}

#if os(macOS)
/// Runs git for Scout (macOS only; a future server would do the same).
public enum GitRunner {
    public static let executable = "/usr/bin/git"

    /// Everything Scout shows about a repository, from one or two quick git calls.
    public struct Snapshot: Sendable {
        public var status: GitStatus
        public var remote: String?
        public var lastCommitSubject: String?
        public var lastCommitDate: Date?
    }

    public static func snapshot(root: String) -> Snapshot? {
        guard let output = run(["status", "--porcelain=v2", "--branch", "-z", "--untracked-files=normal"], in: root)
        else { return nil }
        var snapshot = Snapshot(status: GitStatusParser.parse(output, root: root))
        snapshot.remote = run(["config", "--get", "remote.origin.url"], in: root)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if snapshot.status.commit != nil,
           let log = run(["log", "-1", "--format=%s%x00%ct"], in: root)?.trimmingCharacters(in: .newlines) {
            let parts = log.split(separator: "\0", omittingEmptySubsequences: false)
            snapshot.lastCommitSubject = parts.first.map(String.init)
            if parts.count > 1, let seconds = TimeInterval(parts[1]) {
                snapshot.lastCommitDate = Date(timeIntervalSince1970: seconds)
            }
        }
        return snapshot
    }

    /// Runs git and returns stdout, or nil if it failed or took longer than `timeout`.
    public static func run(_ arguments: [String], in directory: String, timeout: TimeInterval = 5) -> String? {
        // Read-only: don't take index.lock (which would also wake folder watchers).
        CommandRunner.run(executable, ["-C", directory] + arguments, timeout: timeout,
                          environment: ["GIT_OPTIONAL_LOCKS": "0", "GIT_TERMINAL_PROMPT": "0"])
    }
}

/// Runs command-line tools (git, brew, npm) for Scout.
public enum CommandRunner {
    /// Returns stdout, or nil if the tool is missing, failed, or took longer than `timeout`.
    /// `allowFailure` keeps the output of tools that exit non-zero to report something
    /// (`npm outdated` exits 1 when anything is outdated).
    public static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 10,
                           environment extra: [String: String] = [:], allowFailure: Bool = false) -> String? {
        guard FileManager.default.isExecutableFile(atPath: executable) else { return nil }
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        // Apps launched from the Dock get a bare PATH; tools like npm need to find node.
        let toolDir = (executable as NSString).deletingLastPathComponent
        environment["PATH"] = [toolDir, "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", environment["PATH"]]
            .compactMap(\.self).joined(separator: ":")
        environment.merge(extra) { _, new in new }
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }

        let timer = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timer.cancel()
        guard process.terminationReason == .exit, allowFailure || process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
#endif
