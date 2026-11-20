import Foundation
import Testing
@testable import ScoutCore

@Suite struct AgentProjectsTests {
    @Test func readsSessionsTokensAndServers() throws {
        let home = FileManager.default.temporaryDirectory.appending(path: "agents-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let fm = FileManager.default
        let project = home.appending(path: "Sites/app")
        try fm.createDirectory(at: project, withIntermediateDirectories: true)
        try "# rules".write(to: project.appending(path: "CLAUDE.md"), atomically: true, encoding: .utf8)
        try #"{"mcpServers":{"linear":{},"sentry":{}}}"#.write(to: project.appending(path: ".mcp.json"), atomically: true, encoding: .utf8)
        try fm.createDirectory(at: project.appending(path: ".cursor"), withIntermediateDirectories: true)

        let claude = home.appending(path: ".claude/projects/-Sites-app")
        try fm.createDirectory(at: claude, withIntermediateDirectories: true)
        let lines = [
            #"{"type":"mode"}"#,
            #"{"type":"user","cwd":"\#(project.path)","message":{"role":"user"}}"#,
            #"{"type":"assistant","message":{"id":"m1","usage":{"input_tokens":10,"output_tokens":5,"cache_read_input_tokens":100,"cache_creation_input_tokens":20,"output_tokens_details":{"thinking_tokens":1}}}}"#,
            #"{"type":"assistant","message":{"id":"m1","usage":{"input_tokens":10,"output_tokens":5,"cache_read_input_tokens":100,"cache_creation_input_tokens":20}}}"#,
            #"{"type":"assistant","message":{"id":"m2","usage":{"input_tokens":1,"output_tokens":2}}}"#,
        ]
        try lines.joined(separator: "\n").write(to: claude.appending(path: "s1.jsonl"), atomically: true, encoding: .utf8)

        let codex = home.appending(path: ".codex/sessions/2026/11/18")
        try fm.createDirectory(at: codex, withIntermediateDirectories: true)
        let codexLines = [
            #"{"type":"session_meta","payload":{"cwd":"\#(project.path)"}}"#,
            #"{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":50,"cached_input_tokens":30,"output_tokens":7}}}}"#,
            #"{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":80,"cached_input_tokens":40,"output_tokens":9}}}}"#,
        ]
        try codexLines.joined(separator: "\n").write(to: codex.appending(path: "r.jsonl"), atomically: true, encoding: .utf8)
        try #"{"mcpServers":{"github":{}},"projects":{"\#(project.path)":{"mcpServers":{"supabase":{}}}}}"#
            .write(to: home.appending(path: ".claude.json"), atomically: true, encoding: .utf8)

        let overview = AgentProjects.scan(home: home.path)
        #expect(overview.globalMCPServers == ["github"])
        let found = try #require(overview.projects.first)
        #expect(overview.projects.count == 1)
        #expect(found.agents == [.claudeCode, .codex, .cursor])
        #expect(found.files == ["CLAUDE.md", ".cursor"])
        #expect(found.mcpServers == ["linear", "sentry", "supabase"])
        #expect(found.tokens[.claudeCode] == TokenUsage(input: 11, output: 7, cacheRead: 100, cacheWrite: 20)) // m1 counted once
        #expect(found.tokens[.codex] == TokenUsage(input: 40, output: 9, cacheRead: 40)) // last running total
        #expect(found.totalSessions == 2)
    }
}

@Suite struct DevServerTests {
    @Test func parsesLsof() {
        let listeners = DevServers.parseListeners("p10\ncnode\nf20\nn*:5173\nf21\nn[::1]:5173\nf22\nn127.0.0.1:24678\np11\ncrapportd\np12\ncpython3\nf3\nn*:8000\n")
        #expect(listeners.map(\.pid) == [10, 12])
        #expect(listeners[0].ports == [5173, 24678])
        #expect(listeners[1].command == "python3")
        #expect(DevServers.parseFolders("p10\nfcwd\nn/Users/j/Sites/app\np12\nfcwd\nn/\n") == [10: "/Users/j/Sites/app", 12: "/"])
    }
}
