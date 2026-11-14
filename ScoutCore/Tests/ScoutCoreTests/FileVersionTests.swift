import Foundation
import Testing
@testable import ScoutCore

@Suite struct FileVersionTests {
    @Test func listsSavesAndRestores() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "versions-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "notes.txt")
        defer {
            try? NSFileVersion.removeOtherVersionsOfItem(at: url)
            try? FileManager.default.removeItem(at: folder)
        }
        try "first".write(to: url, atomically: false, encoding: .utf8)
        #expect(FileVersions.list(url).isEmpty)
        _ = try NSFileVersion.addOfItem(at: url, withContentsOf: url, options: [])
        try "second".write(to: url, atomically: false, encoding: .utf8)

        let versions = FileVersions.list(url)
        #expect(versions.count == 1)
        let old = try #require(versions.first)

        let copy = try FileVersions.saveCopy(old, of: url)
        #expect(try String(contentsOf: copy, encoding: .utf8) == "first")
        #expect(copy.lastPathComponent.hasPrefix("notes ("))

        try FileVersions.restore(old, of: url)
        #expect(try String(contentsOf: url, encoding: .utf8) == "first")
        // What was there before the restore is now a version too.
        let after = FileVersions.list(url)
        #expect(try after.contains { try String(contentsOf: $0.url, encoding: .utf8) == "second" })
    }
}
