import Foundation

/// Coding agents (Claude Code, Codex, Cursor…) and the projects you've used them in, read
/// from their own files on this Mac. Nothing is sent anywhere.
public enum CodingAgent: String, CaseIterable, Codable, Sendable, Comparable {
    case claudeCode, codex, cursor, gemini, windsurf

    public var title: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .cursor: "Cursor"
        case .gemini: "Gemini"
        case .windsurf: "Windsurf"
        }
    }

    public static func < (a: Self, b: Self) -> Bool {
        allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
    }
}

/// Tokens a project's sessions used.
public struct TokenUsage: Equatable, Sendable {
    public var input: Int = 0
    public var output: Int = 0
    /// Prompt tokens read back from the provider's cache (cheap, and usually most of the total).
    public var cacheRead: Int = 0
    public var cacheWrite: Int = 0

    public init(input: Int = 0, output: Int = 0, cacheRead: Int = 0, cacheWrite: Int = 0) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite
    }

    public var total: Int { input + output + cacheRead + cacheWrite }
    public var isZero: Bool { total == 0 }

    public static func + (a: Self, b: Self) -> Self {
        TokenUsage(input: a.input + b.input, output: a.output + b.output,
                   cacheRead: a.cacheRead + b.cacheRead, cacheWrite: a.cacheWrite + b.cacheWrite)
    }
}

public struct AgentProject: Identifiable, Equatable, Sendable {
    public var path: String
    /// Agents with sessions or set-up files here.
    public var agents: Set<CodingAgent> = []
    /// Agent files in the folder ("CLAUDE.md", "AGENTS.md", ".cursor"…).
    public var files: [String] = []
    public var sessions: [CodingAgent: Int] = [:]
    public var tokens: [CodingAgent: TokenUsage] = [:]
    public var lastUsed: Date?
    /// MCP servers set up for this project (from .mcp.json and Claude Code's settings).
    public var mcpServers: [String] = []

    public var id: String { path }
    public var name: String { (path as NSString).lastPathComponent }
    public var totalTokens: TokenUsage { tokens.values.reduce(TokenUsage(), +) }
    public var totalSessions: Int { sessions.values.reduce(0, +) }

    public init(path: String) { self.path = path }
}

public struct AgentOverview: Equatable, Sendable {
    public var projects: [AgentProject]
    /// MCP servers available in every project (Claude Code's user-level ones).
    public var globalMCPServers: [String]
}

public enum AgentProjects {
    /// Files that mean a folder is set up for an agent.
    static let markers: [(name: String, agent: CodingAgent)] = [
        ("CLAUDE.md", .claudeCode), (".claude", .claudeCode), ("AGENTS.md", .codex), (".codex", .codex),
        (".cursor", .cursor), (".cursorrules", .cursor), ("GEMINI.md", .gemini), (".gemini", .gemini),
        (".windsurfrules", .windsurf), (".windsurf", .windsurf),
    ]

    /// Reads everything under `home`. Slow-ish (it reads every session log), so call it off the main thread.
    public static func scan(home: String) -> AgentOverview {
        var projects: [String: AgentProject] = [:]
        func touch(_ path: String, _ change: (inout AgentProject) -> Void) {
            var project = projects[path] ?? AgentProject(path: path)
            change(&project)
            projects[path] = project
        }

        for session in claudeSessions(home: home) {
            touch(session.cwd) { p in
                p.agents.insert(.claudeCode)
                p.sessions[.claudeCode, default: 0] += 1
                p.tokens[.claudeCode] = (p.tokens[.claudeCode] ?? TokenUsage()) + session.tokens
                p.lastUsed = max(p.lastUsed ?? .distantPast, session.lastUsed)
            }
        }
        for session in codexSessions(home: home) {
            touch(session.cwd) { p in
                p.agents.insert(.codex)
                p.sessions[.codex, default: 0] += 1
                p.tokens[.codex] = (p.tokens[.codex] ?? TokenUsage()) + session.tokens
                p.lastUsed = max(p.lastUsed ?? .distantPast, session.lastUsed)
            }
        }

        let config = claudeConfig(home: home)
        for (path, servers) in config.projectServers {
            touch(path) { p in p.mcpServers += servers }
        }

        let fm = FileManager.default
        var result: [AgentProject] = []
        for var project in projects.values {
            // Temporary folders (agents run from scratch dirs) and folders that are gone.
            let isTemporary = ["/private/var/folders/", "/var/folders/", "/private/tmp/", "/tmp/"]
                .contains { project.path.hasPrefix($0) } && !project.path.hasPrefix(home + "/")
            // Agents also run inside their own hidden folders (~/.claude/...); those aren't projects.
            let isHidden = project.path.split(separator: "/").contains { $0.hasPrefix(".") }
            guard !isTemporary, !isHidden, project.path != "/", fm.fileExists(atPath: project.path) else { continue }
            for marker in markers where fm.fileExists(atPath: project.path + "/" + marker.name) {
                project.files.append(marker.name)
                project.agents.insert(marker.agent)
            }
            project.mcpServers += mcpJSONServers(at: project.path)
            project.mcpServers = Array(Set(project.mcpServers)).sorted()
            guard !project.agents.isEmpty else { continue }
            result.append(project)
        }
        result.sort { ($0.lastUsed ?? .distantPast) > ($1.lastUsed ?? .distantPast) }
        return AgentOverview(projects: result, globalMCPServers: config.globalServers)
    }

    // MARK: - Claude Code (~/.claude/projects/<folder>/<session>.jsonl)

    struct Session: Sendable {
        var cwd: String
        var tokens: TokenUsage
        var lastUsed: Date
    }

    static func claudeSessions(home: String) -> [Session] {
        let root = URL(filePath: home).appending(path: ".claude/projects")
        return parallelMap(jsonlFiles(under: root), readClaudeSession)
    }

    /// One session: its folder and the usage of each reply (a reply is logged once per content
    /// block with the same usage, so replies are counted by message id).
    static func readClaudeSession(_ url: URL) -> Session? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        var cwd: String?
        var seen = Set<String>()
        var tokens = TokenUsage()
        let usageMarker = Data("\"usage\"".utf8), cwdMarker = Data("\"cwd\"".utf8)
        for line in data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true) {
            let needsCwd = cwd == nil && line.range(of: cwdMarker) != nil
            let hasUsage = line.range(of: usageMarker) != nil
            guard needsCwd || hasUsage,
                  let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            if needsCwd, let value = object["cwd"] as? String { cwd = value }
            guard hasUsage, let message = object["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any] else { continue }
            if let id = message["id"] as? String, !seen.insert(id).inserted { continue }
            tokens.input += usage["input_tokens"] as? Int ?? 0
            tokens.output += usage["output_tokens"] as? Int ?? 0
            tokens.cacheRead += usage["cache_read_input_tokens"] as? Int ?? 0
            tokens.cacheWrite += usage["cache_creation_input_tokens"] as? Int ?? 0
        }
        guard let cwd else { return nil }
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        return Session(cwd: cwd, tokens: tokens, lastUsed: modified)
    }

    // MARK: - Codex (~/.codex/sessions/YYYY/MM/DD/*.jsonl)

    static func codexSessions(home: String) -> [Session] {
        let root = URL(filePath: home).appending(path: ".codex/sessions")
        return parallelMap(jsonlFiles(under: root), readCodexSession)
    }

    /// Reads files on every core (session logs add up to hundreds of MB).
    static func parallelMap(_ urls: [URL], _ read: @Sendable (URL) -> Session?) -> [Session] {
        let results = UnsafeMutableBufferPointer<Session?>.allocate(capacity: urls.count)
        results.initialize(repeating: nil)
        defer { results.deallocate() }
        nonisolated(unsafe) let slots = results
        DispatchQueue.concurrentPerform(iterations: urls.count) { i in slots[i] = read(urls[i]) }
        return results.compactMap { $0 }
    }

    /// The folder from `session_meta`, and the last running total from `token_count` events.
    static func readCodexSession(_ url: URL) -> Session? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        var cwd: String?
        var tokens = TokenUsage()
        let metaMarker = Data("\"session_meta\"".utf8), countMarker = Data("\"total_token_usage\"".utf8)
        for line in data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true) {
            let isMeta = cwd == nil && line.range(of: metaMarker) != nil
            let isCount = line.range(of: countMarker) != nil
            guard isMeta || isCount,
                  let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let payload = object["payload"] as? [String: Any] else { continue }
            if isMeta, let value = payload["cwd"] as? String { cwd = value }
            if isCount, let info = payload["info"] as? [String: Any], let total = info["total_token_usage"] as? [String: Any] {
                let cached = total["cached_input_tokens"] as? Int ?? 0
                tokens = TokenUsage(input: max(0, (total["input_tokens"] as? Int ?? 0) - cached),
                                    output: total["output_tokens"] as? Int ?? 0,
                                    cacheRead: cached,
                                    cacheWrite: total["cache_write_input_tokens"] as? Int ?? 0)
            }
        }
        guard let cwd else { return nil }
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        return Session(cwd: cwd, tokens: tokens, lastUsed: modified)
    }

    // MARK: - MCP servers

    struct ClaudeConfig {
        var projectServers: [String: [String]] = [:]
        var globalServers: [String] = []
    }

    /// ~/.claude.json: user-level MCP servers and each project's own.
    static func claudeConfig(home: String) -> ClaudeConfig {
        let url = URL(filePath: home).appending(path: ".claude.json")
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return ClaudeConfig() }
        var config = ClaudeConfig()
        config.globalServers = ((root["mcpServers"] as? [String: Any])?.keys).map { $0.sorted() } ?? []
        for (path, value) in (root["projects"] as? [String: Any]) ?? [:] {
            let servers = ((value as? [String: Any])?["mcpServers"] as? [String: Any])?.keys.sorted() ?? []
            config.projectServers[path] = servers
        }
        return config
    }

    /// Servers in a project's .mcp.json (shared with the team through git).
    static func mcpJSONServers(at path: String) -> [String] {
        guard let data = try? Data(contentsOf: URL(filePath: path + "/.mcp.json")),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let servers = root["mcpServers"] as? [String: Any] else { return [] }
        return servers.keys.sorted()
    }

    static func jsonlFiles(under root: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil,
                                                              options: [.skipsHiddenFiles]) else { return [] }
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "jsonl" }
    }
}

/// A program listening on a local port that was started from a folder in your home
/// (a dev server: `npm run dev`, `rails s`, `python -m http.server`).
public struct DevServer: Identifiable, Equatable, Sendable {
    public var pid: Int32
    public var command: String
    public var ports: [Int]
    public var folder: String
    public var id: Int32 { pid }

    public init(pid: Int32, command: String, ports: [Int], folder: String) {
        self.pid = pid
        self.command = command
        self.ports = ports
        self.folder = folder
    }

    public var url: URL? { ports.first.flatMap { URL(string: "http://localhost:\($0)") } }
}

#if os(macOS)
public enum DevServers {
    /// Listening processes whose working folder is inside `home` (system services run from "/").
    public static func listening(home: String) -> [DevServer] {
        let listeners = parseListeners(run(["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpcn"]))
        guard !listeners.isEmpty else { return [] }
        let pids = listeners.map { String($0.pid) }.joined(separator: ",")
        let folders = parseFolders(run(["-a", "-p", pids, "-d", "cwd", "-Fpn"]))
        let hidden = home + "/Library/"
        return listeners.compactMap { listener in
            guard let folder = folders[listener.pid], folder.hasPrefix(home + "/"), !folder.hasPrefix(hidden) else { return nil }
            var server = listener
            server.folder = folder
            return server
        }
        .sorted { ($0.ports.first ?? 0) < ($1.ports.first ?? 0) }
    }

    /// `lsof -F pcn` output: "p<pid>", "c<command>", then "n<address:port>" lines.
    static func parseListeners(_ output: String) -> [DevServer] {
        var servers: [DevServer] = []
        var current: DevServer?
        for line in output.split(separator: "\n") {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            switch tag {
            case "p":
                if let current, !current.ports.isEmpty { servers.append(current) }
                current = Int32(value).map { DevServer(pid: $0, command: "", ports: [], folder: "") }
            case "c":
                current?.command = value
            case "n":
                if let port = value.split(separator: ":").last.flatMap({ Int($0) }), current?.ports.contains(port) == false {
                    current?.ports.append(port)
                }
            default:
                break
            }
        }
        if let current, !current.ports.isEmpty { servers.append(current) }
        return servers
    }

    /// `lsof -d cwd -F pn` output: pid → working folder.
    static func parseFolders(_ output: String) -> [Int32: String] {
        var folders: [Int32: String] = [:]
        var pid: Int32?
        for line in output.split(separator: "\n") {
            if line.hasPrefix("p") { pid = Int32(line.dropFirst()) }
            if line.hasPrefix("n"), let pid { folders[pid] = String(line.dropFirst()) }
        }
        return folders
    }

    private static func run(_ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/sbin/lsof")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
#endif
