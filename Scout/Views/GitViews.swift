import AppKit
import ScoutCore
import SwiftUI

extension GitFileState {
    var color: Color {
        switch self {
        case .modified: .orange
        case .added, .untracked: .green
        case .renamed: .blue
        case .deleted, .conflicted: .red
        }
    }
}

/// The little "M" / "U" next to a changed file. Folders get a dot (something inside changed).
struct GitBadge: View {
    let state: GitFileState
    var isFolder = false

    var body: some View {
        Group {
            if isFolder {
                Circle().fill(state.color).frame(width: 6, height: 6)
                    .frame(width: 16)
            } else {
                Text(state.letter)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(state.color)
                    .frame(width: 16, height: 16)
                    .background(state.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .help(isFolder ? "\(state.title) files inside" : state.title)
    }
}

/// Branch chip in the header when you're inside a git repository.
struct GitChip: View {
    let browser: BrowserModel
    let git: GitRunner.Snapshot

    var body: some View {
        let status = git.status
        Menu {
            GitMenuItems(browser: browser, git: git)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 11, weight: .regular))
                Text(status.headName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 140)
                    .fixedSize()
                if status.ahead > 0 || status.behind > 0 {
                    Text(syncText(status))
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(Color.textSubtle)
                }
                if status.changeCount > 0 {
                    Text("\(status.changeCount)")
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 16, minHeight: 16)
                        .background(Capsule().fill(Color.orange))
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(Capsule().fill(Color.primary.opacity(0.055)))
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(helpText(status))
    }

    private func syncText(_ status: GitStatus) -> String {
        [status.ahead > 0 ? "↑\(status.ahead)" : nil, status.behind > 0 ? "↓\(status.behind)" : nil]
            .compactMap(\.self).joined(separator: " ")
    }

    private func helpText(_ status: GitStatus) -> String {
        let changes = status.changeCount == 0 ? "no changes" : "\(status.changeCount) changed file\(status.changeCount == 1 ? "" : "s")"
        return "Git: \(status.headName), \(changes)"
    }
}

/// What the branch chip offers (also in the compact header menu).
struct GitMenuItems: View {
    let browser: BrowserModel
    let git: GitRunner.Snapshot

    var body: some View {
        let status = git.status
        let root = URL.folder(status.root)
        Section(FileManager.default.displayName(atPath: status.root) + " · " + status.headName) {
            Button("Show Changed Files (\(status.changeCount))") { browser.showChanges(in: status.root) }
                .disabled(status.changeCount == 0 || browser.changesRoot == status.root)
            Button("Copy Branch Name") { copy(status.headName) }
            if let page = browser.gitHubURL(for: browser.location, isFolder: true) {
                Button("Open on GitHub") { NSWorkspace.shared.open(page) }
            }
            if browser.location.filePath != status.root || !browser.isFolder {
                Button("Go to Repository Root") { browser.go(to: root) }
            }
        }
        Section {
            if let terminal = DevApp.preferredTerminal {
                Button("Open Repository in \(terminal.name)") { terminal.open(root) }
            }
            if let editor = DevApp.preferredEditor {
                Button("Open Repository in \(editor.name)") { editor.open(root) }
            }
            Button("Refresh Git Status") { browser.refreshGit() }
        }
    }
}

/// "Open In" submenu: every installed terminal and editor.
struct OpenInMenu: View {
    let url: URL

    var body: some View {
        let terminals = DevApp.installed(.terminal)
        let editors = DevApp.installed(.editor)
        Menu("Open In") {
            ForEach(editors) { app in appButton(app) }
            if !editors.isEmpty { Divider() }
            ForEach(terminals) { app in appButton(app) }
        }
    }

    private func appButton(_ app: DevApp) -> some View {
        Button {
            app.open(url)
        } label: {
            Label {
                Text(app.name)
            } icon: {
                if let icon = app.icon { Image(nsImage: icon) }
            }
        }
    }
}

/// Info-panel card for a repository (and the selected file's state in it).
struct GitCard: View {
    let browser: BrowserModel
    let git: GitRunner.Snapshot
    var item: FileItem?

    var body: some View {
        let status = git.status
        Card(spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch").foregroundStyle(Color.accentColor)
                Text(status.headName).font(.ui(13, .medium)).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                if let item, let state = browser.gitState(item) {
                    Text(item.isNavigable ? "Changes inside" : state.title)
                        .font(.ui(12).weight(.medium))
                        .foregroundStyle(state.color)
                }
            }
            Text(syncText(status)).font(.ui(13)).foregroundStyle(Color.textSubtle)
            if status.changeCount > 0 {
                Text(changesText(status)).font(.ui(13)).foregroundStyle(Color.textSubtle)
            }
            if let subject = git.lastCommitSubject {
                Divider()
                VStack(alignment: .leading, spacing: 2) {
                    Text(subject).lineLimit(2)
                    if let date = git.lastCommitDate {
                        Text("Last commit " + date.formatted(.relative(presentation: .named)))
                            .font(.ui(12)).foregroundStyle(Color.textSubtle)
                    }
                }
            }
            if let page = browser.gitHubURL(for: item?.url ?? browser.location, isFolder: item?.isNavigable ?? true) {
                Button("Open on GitHub") { NSWorkspace.shared.open(page) }
                    .controlSize(.small)
            }
        }
    }

    private func syncText(_ status: GitStatus) -> String {
        guard let upstream = status.upstream else {
            return status.commit == nil ? "No commits yet" : "Not pushed anywhere yet"
        }
        switch (status.ahead, status.behind) {
        case (0, 0): return "Up to date with \(upstream)"
        case (let a, 0): return "\(a) commit\(a == 1 ? "" : "s") to push"
        case (0, let b): return "\(b) commit\(b == 1 ? "" : "s") to pull"
        case (let a, let b): return "\(a) to push, \(b) to pull"
        }
    }

    private func changesText(_ status: GitStatus) -> String {
        let counts = Dictionary(grouping: status.changes.values, by: \.self).mapValues(\.count)
        return counts.sorted { $0.key > $1.key }
            .map { "\($0.value) \($0.key.title.lowercased())" }
            .joined(separator: ", ")
    }
}

private func copy(_ string: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(string, forType: .string)
}

/// Shown instead of the Git card when a repository's settings could run programs.
struct UntrustedRepoCard: View {
    let browser: BrowserModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Git is paused here", systemImage: "lock.shield")
                .font(.ui(13, .medium))
                .foregroundStyle(Color.textStrong)
            Text("This repository's settings can run programs when git reads it, so Scout didn't run git. Only trust repositories you know.")
                .font(.ui(12))
                .foregroundStyle(Color.textSubtle)
                .fixedSize(horizontal: false, vertical: true)
            Button("Trust This Repository") { browser.trustRepository() }
                .controlSize(.small)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RaisedFill(shape: RoundedRectangle(cornerRadius: 10)))
    }
}
