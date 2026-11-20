import AppKit
import ScoutCore
import SwiftUI

/// AI Agents: the projects you've set up for or used with coding agents (Claude Code, Codex,
/// Cursor…), the tokens their sessions used, their MCP servers, and the dev servers running
/// from your folders. Everything is read from files and processes on this Mac.
struct AgentsView: View {
    let browser: BrowserModel

    @State private var overview: AgentOverview?
    @State private var servers: [DevServer] = []
    @State private var isLoading = false
    @State private var loadID = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                summary
                serversCard
                if let overview {
                    if overview.projects.isEmpty {
                        ContentUnavailableView("No Agent Projects", systemImage: "sparkle",
                                               description: Text("Scout looks for Claude Code and Codex sessions, and for CLAUDE.md, AGENTS.md and .cursor in those folders."))
                    } else {
                        projectsCard(overview.projects)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .task(id: loadID) { await load() }
    }

    // MARK: - Pieces

    private var summary: some View {
        let projects = overview?.projects ?? []
        let tokens = projects.reduce(TokenUsage()) { $0 + $1.totalTokens }
        return Card(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(overview == nil ? "Looking…" : "\(projects.count) project\(projects.count == 1 ? "" : "s")")
                    .font(.system(size: 24, weight: .medium))
                if !tokens.isZero {
                    Text("\(Self.compact(tokens.total)) tokens").foregroundStyle(Color.textSubtle)
                        .help(Self.breakdown(tokens))
                }
                Spacer()
                if isLoading { ProgressView().controlSize(.small) }
                Button("Refresh") { loadID += 1 }.disabled(isLoading)
            }
            Text("Read from Claude Code’s and Codex’s session files and each project’s agent files. Nothing leaves your Mac.")
                .font(.system(size: 13)).foregroundStyle(Color.textSubtle)
            if let global = overview?.globalMCPServers, !global.isEmpty {
                HStack(spacing: 6) {
                    Text("MCP servers everywhere:").font(.system(size: 12)).foregroundStyle(Color.textSubtle)
                    chips(global)
                }
            }
        }
    }

    @ViewBuilder private var serversCard: some View {
        if !servers.isEmpty {
            Card(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "server.rack").foregroundStyle(Color.accentColor).frame(width: 22)
                    Text("Running dev servers").font(.system(size: 13, weight: .medium))
                    Spacer()
                }
                Rectangle().fill(Color.hairline).frame(height: 1).padding(.vertical, 10)
                VStack(spacing: 2) {
                    ForEach(servers) { server in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 6) {
                                    Text(server.ports.map { ":\($0)" }.joined(separator: " ")).font(.system(size: 13, weight: .medium, design: .monospaced))
                                    Text(server.command).font(.system(size: 12)).foregroundStyle(Color.textSubtle)
                                }
                                Text(PathDisplay.display(server.folder, home: browser.services.homePath))
                                    .font(.system(size: 12)).foregroundStyle(Color.textSubtle).lineLimit(1).truncationMode(.head)
                            }
                            Spacer(minLength: 8)
                            if let url = server.url {
                                Button("Open") { NSWorkspace.shared.open(url) }.controlSize(.small).help(url.absoluteString)
                            }
                            Button("Show Folder") { browser.go(to: .folder(server.folder)) }.controlSize(.small)
                        }
                        .padding(.leading, 32)
                        .padding(.vertical, 3)
                    }
                }
            }
        }
    }

    private func projectsCard(_ projects: [AgentProject]) -> some View {
        Card(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "sparkle").foregroundStyle(Color.accentColor).frame(width: 22)
                Text("Projects").font(.system(size: 13, weight: .medium))
                Spacer()
            }
            Rectangle().fill(Color.hairline).frame(height: 1).padding(.vertical, 10)
            VStack(spacing: 6) {
                ForEach(projects) { row($0) }
            }
        }
    }

    private func row(_ project: AgentProject) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(project.name).font(.system(size: 13, weight: .medium))
                    ForEach(project.agents.sorted(), id: \.self) { agent in
                        Text(agent.title)
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                    }
                }
                Text(details(project)).font(.system(size: 12)).foregroundStyle(Color.textSubtle).lineLimit(1)
                if !project.files.isEmpty || !project.mcpServers.isEmpty {
                    HStack(spacing: 6) {
                        if !project.files.isEmpty {
                            Text(project.files.joined(separator: "  "))
                                .font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.textSubtle)
                        }
                        if !project.mcpServers.isEmpty {
                            Text("MCP").font(.system(size: 11)).foregroundStyle(Color.textSubtle)
                            chips(project.mcpServers)
                        }
                    }
                }
            }
            Spacer(minLength: 8)
            if !project.totalTokens.isZero {
                Text(Self.compact(project.totalTokens.total))
                    .font(.system(size: 12, weight: .medium)).monospacedDigit()
                    .help(Self.breakdown(project.totalTokens))
            }
            Menu {
                Button("Open in Scout") { browser.go(to: .folder(project.path)) }
                Button("Open in \(DevApp.preferredTerminal?.name ?? "Terminal")") { browser.openInTerminal(.folder(project.path)) }
                Button("Open in \(DevApp.preferredEditor?.name ?? "Editor")") { browser.openInEditor(.folder(project.path)) }
                ForEach(["CLAUDE.md", "AGENTS.md"].filter { project.files.contains($0) }, id: \.self) { file in
                    Button("Open \(file)") { NSWorkspace.shared.open(URL(filePath: project.path + "/" + file)) }
                }
                Divider()
                Button("Copy Path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(project.path, forType: .string)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12)).foregroundStyle(Color.textSubtle)
                    .frame(width: 24, height: 24).contentShape(Rectangle())
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        }
        .padding(.leading, 32)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { browser.go(to: .folder(project.path)) }
    }

    private func chips(_ names: [String]) -> some View {
        HStack(spacing: 4) {
            ForEach(names, id: \.self) { name in
                Text(name)
                    .font(.system(size: 11))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .overlay(Capsule().strokeBorder(Color.hairline))
            }
        }
    }

    private func details(_ project: AgentProject) -> String {
        var parts = [PathDisplay.display(project.path, home: browser.services.homePath)]
        let sessions = project.totalSessions
        if sessions > 0 { parts.append("\(sessions) session\(sessions == 1 ? "" : "s")") }
        if let last = project.lastUsed, last > .distantPast {
            parts.append("last used " + last.formatted(.relative(presentation: .named)))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Loading

    private func load() async {
        isLoading = true
        let home = browser.services.homePath
        async let scanned = Task.detached(priority: .userInitiated) { AgentProjects.scan(home: home) }.value
        async let running = Task.detached(priority: .userInitiated) { DevServers.listening(home: home) }.value
        let (result, live) = await (scanned, running)
        overview = result
        servers = live
        isLoading = false
    }

    // MARK: - Formatting

    /// 1234 → "1.2K", 1_129_949_796 → "1.1B".
    static func compact(_ n: Int) -> String {
        n.formatted(.number.notation(.compactName).precision(.significantDigits(2)))
    }

    static func breakdown(_ t: TokenUsage) -> String {
        "Input \(compact(t.input)) · Output \(compact(t.output)) · Cache reads \(compact(t.cacheRead)) · Cache writes \(compact(t.cacheWrite))"
    }
}
