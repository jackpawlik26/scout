import Foundation
import Testing
@testable import ScoutCore

@Suite struct TagTests {
    @Test func roundTripsLikeFinder() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "tags-\(UUID().uuidString).txt")
        try "x".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(Tags.read(url).isEmpty)
        try Tags.write([FileTag(name: "Red", color: 6), FileTag(name: "Client A", color: 0)], to: url)
        #expect(Tags.read(url) == [FileTag(name: "Red", color: 6), FileTag(name: "Client A", color: 0)])
        // macOS sees them too.
        let names = try url.resourceValues(forKeys: [.tagNamesKey]).tagNames
        #expect(names == ["Red", "Client A"])

        try Tags.toggle(FileTag(name: "Red", color: 6), on: [url])
        #expect(Tags.read(url).map(\.name) == ["Client A"])
        try Tags.write([], to: url)
        #expect(Tags.read(url).isEmpty)
    }

    @Test func parsesEntries() {
        #expect(Tags.parse("Work\n4") == FileTag(name: "Work", color: 4))
        #expect(Tags.parse("Green") == FileTag(name: "Green", color: 2))
        #expect(Tags.parse("Misc") == FileTag(name: "Misc", color: 0))
    }
}
