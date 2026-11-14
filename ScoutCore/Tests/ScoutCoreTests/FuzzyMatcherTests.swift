import Foundation
import Testing
@testable import ScoutCore

@Suite struct FuzzyMatcherTests {
    @Test func matchesLettersInOrder() {
        #expect(FuzzyMatcher.match("dl", in: "Downloads") != nil)
        #expect(FuzzyMatcher.match("dsk", in: "Desktop") != nil)
        #expect(FuzzyMatcher.match("ld", in: "Downloads") != nil) // l…d appears in "loads"
        #expect(FuzzyMatcher.match("xyz", in: "Downloads") == nil)
    }

    @Test func isCaseInsensitive() {
        #expect(FuzzyMatcher.match("DOC", in: "Documents") != nil)
        #expect(FuzzyMatcher.match("doc", in: "DOCUMENTS") != nil)
    }

    @Test func prefersWordStarts() throws {
        let documents = try #require(FuzzyMatcher.match("doc", in: "Documents"))
        let docker = try #require(FuzzyMatcher.match("doc", in: "my docker files"))
        let buried = try #require(FuzzyMatcher.match("doc", in: "random_xdoxc"))
        #expect(documents.score > docker.score)
        #expect(docker.score > buried.score)
    }

    @Test func exactBeatsLonger() throws {
        let exact = try #require(FuzzyMatcher.match("scout", in: "Scout"))
        let longer = try #require(FuzzyMatcher.match("scout", in: "Scouting Reports"))
        #expect(exact.score > longer.score)
    }

    @Test func findsBestPlacementNotFirst() throws {
        // "ux" should land on "ux-notes", not inside "library".
        let m = try #require(FuzzyMatcher.match("ux", in: "library ux-notes"))
        #expect(m.indices == [8, 9])
    }

    @Test func spaceSeparatedWordsMustAllMatch() {
        #expect(FuzzyMatcher.match("ux notes", in: "ux-notes") != nil)
        #expect(FuzzyMatcher.match("notes ux", in: "ux-notes") != nil)
        #expect(FuzzyMatcher.match("ux zzz", in: "ux-notes") == nil)
    }

    @Test func prefilterNeverRejectsRealMatches() {
        let q = Array("dl".utf8)
        #expect(FuzzyMatcher.mightMatch(queryUTF8: q, candidateLower: "downloads"))
        #expect(!FuzzyMatcher.mightMatch(queryUTF8: q, candidateLower: "desktop"))
        #expect(FuzzyMatcher.mightMatch(queryUTF8: Array("é".utf8), candidateLower: "café"))
    }
}
