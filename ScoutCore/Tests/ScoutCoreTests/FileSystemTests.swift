import Foundation
import Testing
@testable import ScoutCore

/// Tests that touch a real (temporary) folder.
@Suite struct FileSystemTests {
    let root: URL
    let fs = LocalFileSource()

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "ScoutTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func makeFile(_ name: String, in folder: URL? = nil) throws -> URL {
        let url = (folder ?? root).appending(path: name)
        try Data("hi".utf8).write(to: url)
        return url
    }

    @Test func listsFilesAndFolders() async throws {
        _ = try makeFile("a.txt")
        _ = try makeFile(".hidden")
        _ = try fs.createFolder(in: root, named: "Sub")

        let visible = try await fs.contents(of: root, includeHidden: false)
        #expect(Set(visible.map(\.name)) == ["a.txt", "Sub"])
        let sub = try #require(visible.first { $0.name == "Sub" })
        #expect(sub.isNavigable)
        #expect(sub.size == nil)
        #expect(visible.first { $0.name == "a.txt" }?.size == 2)

        let all = try await fs.contents(of: root, includeHidden: true)
        #expect(all.contains { $0.name == ".hidden" })
    }

    @Test func newFoldersGetNumberedNames() throws {
        let first = try fs.createFolder(in: root, named: "untitled folder")
        let second = try fs.createFolder(in: root, named: "untitled folder")
        #expect(first.lastPathComponent == "untitled folder")
        #expect(second.lastPathComponent == "untitled folder 2")
    }

    @Test func copiesGetCopyNames() throws {
        let file = try makeFile("report.pdf")
        let c1 = try fs.copy(file, into: root)
        let c2 = try fs.copy(file, into: root)
        #expect(c1.lastPathComponent == "report copy.pdf")
        #expect(c2.lastPathComponent == "report copy 2.pdf")
    }

    @Test func renameRefusesToOverwrite() throws {
        let a = try makeFile("a.txt")
        _ = try makeFile("b.txt")
        #expect(throws: ScoutError.alreadyExists("b.txt")) { try fs.rename(a, to: "b.txt") }
        #expect(throws: ScoutError.self) { try fs.rename(a, to: "bad/name") }
        let renamed = try fs.rename(a, to: "c.txt")
        #expect(renamed.lastPathComponent == "c.txt")
    }

    @Test func renameAllowsCaseChanges() throws {
        let a = try makeFile("notes.txt")
        let renamed = try fs.rename(a, to: "Notes.txt")
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.filePath).contains("Notes.txt"))
        #expect(renamed.lastPathComponent == "Notes.txt")
    }

    @Test func tabCompletion() throws {
        _ = try fs.createFolder(in: root, named: "Projects")
        _ = try fs.createFolder(in: root, named: "Photos")
        _ = try fs.createFolder(in: root, named: "Music")
        let base = root.filePath

        #expect(PathCompletion.complete(base + "/Mu", home: "/nowhere") == base + "/Music/")
        #expect(PathCompletion.complete(base + "/p", home: "/nowhere") == base + "/P")
        #expect(PathCompletion.complete(base + "/Pr", home: "/nowhere") == base + "/Projects/")
        #expect(PathCompletion.complete(base + "/zz", home: "/nowhere") == nil)
        // "~" stays "~" in what you see.
        #expect(PathCompletion.complete("~/Mu", home: base) == "~/Music/")
    }

    @Test func indexerSkipsJunk() throws {
        let proj = try fs.createFolder(in: root, named: "proj")
        _ = try fs.createFolder(in: proj, named: "src")
        let nm = try fs.createFolder(in: proj, named: "node_modules")
        _ = try fs.createFolder(in: nm, named: "left-pad")
        let lib = try fs.createFolder(in: root, named: "Library")
        _ = try fs.createFolder(in: lib, named: "Caches")

        let names = Set(FolderIndexer.scan(roots: [root], home: root.filePath).map(\.name))
        #expect(names.contains("src"))
        #expect(names.contains("Library"))       // listed…
        #expect(!names.contains("Caches"))       // …but not entered
        #expect(!names.contains("node_modules"))
        #expect(!names.contains("left-pad"))
    }
}
