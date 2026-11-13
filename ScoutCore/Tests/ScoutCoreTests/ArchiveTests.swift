import Foundation
import Testing
@testable import ScoutCore

@Suite struct ArchiveTests {
    let dir = FileManager.default.temporaryDirectory.appending(path: "Archive-\(UUID().uuidString)")

    private func write(_ name: String, _ text: String) throws {
        let url = dir.appending(path: name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    @Test func zipsAndUnzipsAFolder() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        try write("Project/a.txt", "alpha")
        try write("Project/sub/b.txt", "beta")
        let zip = try Archiver.compress([dir.appending(path: "Project")])
        #expect(zip.lastPathComponent == "Project.zip")

        try FileManager.default.removeItem(at: dir.appending(path: "Project"))
        let out = try Archiver.extract(zip)
        #expect(out.lastPathComponent == "Project") // one item: lands as-is
        #expect(try String(contentsOf: out.appending(path: "sub/b.txt"), encoding: .utf8) == "beta")
        // Extracting again doesn't overwrite.
        #expect(try Archiver.extract(zip).lastPathComponent == "Project 2")
    }

    @Test func severalItemsGoInAFolder() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        try write("one.txt", "1")
        try write("two.txt", "2")
        let zip = try Archiver.compress([dir.appending(path: "one.txt"), dir.appending(path: "two.txt")])
        #expect(zip.lastPathComponent == "Archive.zip")
        let out = try Archiver.extract(zip)
        #expect(out.lastPathComponent == "Archive")
        let names = try FileManager.default.contentsOfDirectory(atPath: out.filePath).sorted()
        #expect(names == ["one.txt", "two.txt"])
    }

    @Test func readsTarballs() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        try write("src/x.txt", "x")
        try write("src/y.txt", "y")
        let tarball = dir.appending(path: "Photos.tar.gz")
        _ = CommandRunner.run("/usr/bin/tar", ["-czf", tarball.filePath, "-C", dir.appending(path: "src").filePath, "x.txt", "y.txt"])
        #expect(Archiver.canExtract(tarball) && !Archiver.canExtract(dir.appending(path: "notes.txt")))
        #expect(try Archiver.extract(tarball).lastPathComponent == "Photos")
    }
}
