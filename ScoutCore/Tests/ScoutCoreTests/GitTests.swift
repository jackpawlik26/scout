import Foundation
import Testing
@testable import ScoutCore

@Suite struct GitTests {
    let sample = [
        "# branch.oid 1234567890abcdef1234567890abcdef12345678",
        "# branch.head main",
        "# branch.upstream origin/main",
        "# branch.ab +2 -1",
        "1 .M N... 100644 100644 100644 aaa bbb Sources/App/main.swift",
        "1 A. N... 000000 100644 100644 000 ccc README with spaces.md",
        "1 D. N... 100644 000000 000000 ddd 000 old.txt",
        "2 R. N... 100644 100644 100644 eee eee R100 Docs/new name.md", "Docs/old name.md",
        "u UU N... 100644 100644 100644 100644 f1 f2 f3 conflict.txt",
        "? scratch/",
        "? notes.txt",
    ].joined(separator: "\0") + "\0"

    @Test func parsesBranchAndChanges() {
        let status = GitStatusParser.parse(sample, root: "/r")
        #expect(status.branch == "main")
        #expect(status.upstream == "origin/main")
        #expect(status.ahead == 2 && status.behind == 1)
        #expect(status.changes == [
            "Sources/App/main.swift": .modified,
            "README with spaces.md": .added,
            "old.txt": .deleted,
            "Docs/new name.md": .renamed,
            "conflict.txt": .conflicted,
            "scratch/": .untracked,
            "notes.txt": .untracked,
        ])
    }

    @Test func parsesDetachedAndEmptyRepos() {
        let detached = GitStatusParser.parse("# branch.oid abcdef1234\0# branch.head (detached)\0", root: "/r")
        #expect(detached.branch == nil && detached.headName == "abcdef1")
        let empty = GitStatusParser.parse("# branch.oid (initial)\0# branch.head main\0", root: "/r")
        #expect(empty.commit == nil && empty.headName == "main" && empty.changeCount == 0)
    }

    @Test func badgesFilesAndFolders() {
        let status = GitStatusParser.parse(sample, root: "/r")
        #expect(status.state(for: "/r/Sources/App/main.swift", isFolder: false) == .modified)
        #expect(status.state(for: "/r/Sources", isFolder: true) == .modified)
        #expect(status.state(for: "/r/Docs", isFolder: true) == .renamed)
        #expect(status.state(for: "/r/scratch", isFolder: true) == .untracked)
        #expect(status.state(for: "/r/scratch/deep/file.txt", isFolder: false) == .untracked)
        #expect(status.state(for: "/r/Package.swift", isFolder: false) == nil)
        #expect(status.state(for: "/r", isFolder: true) == nil)
        #expect(status.state(for: "/other/main.swift", isFolder: false) == nil)
        // A conflict outranks everything else.
        #expect([GitFileState.untracked, .conflicted, .modified].max() == .conflicted)
    }

    @Test func findsRepositoryRoot() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "GitRoot-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appending(path: ".git"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dir.appending(path: "a/b"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(Git.repositoryRoot(containing: dir.appending(path: "a/b").filePath) == dir.filePath)
        #expect(Git.repositoryRoot(containing: FileManager.default.temporaryDirectory.filePath) == nil)
    }

    @Test func makesGitHubLinks() {
        let repo = URL(string: "https://github.com/me/scout")!
        for remote in ["git@github.com:me/scout.git", "https://github.com/me/scout.git", "https://github.com/me/scout",
                       "ssh://git@github.com/me/scout.git", "https://token@github.com/me/scout.git\n"] {
            #expect(Git.gitHubURL(fromRemote: remote) == repo, "\(remote)")
        }
        #expect(Git.gitHubURL(fromRemote: "git@gitlab.com:me/scout.git") == nil)
        #expect(Git.gitHubURL(repo: repo, ref: "main", relativePath: "Docs/a b.md", isFolder: false).absoluteString
            == "https://github.com/me/scout/blob/main/Docs/a%20b.md")
        #expect(Git.gitHubURL(repo: repo, ref: "main", relativePath: "Sources", isFolder: true).absoluteString
            == "https://github.com/me/scout/tree/main/Sources")
        #expect(Git.gitHubURL(repo: repo, ref: "main", relativePath: "", isFolder: true).absoluteString
            == "https://github.com/me/scout/tree/main")
    }

    @Test func readsARealRepository() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "GitReal-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = dir.resolvingSymlinksInPath().filePath
        guard GitRunner.run(["init", "-q", "-b", "trunk"], in: root) != nil else { return } // no git installed
        try "hi".write(to: dir.appending(path: "a.txt"), atomically: true, encoding: .utf8)
        let snapshot = try #require(GitRunner.snapshot(root: root))
        #expect(snapshot.status.branch == "trunk")
        #expect(snapshot.status.changes == ["a.txt": .untracked])
        #expect(snapshot.lastCommitSubject == nil)
    }
}
