import Foundation
import Testing
@testable import ScoutCore

@Suite struct SpotlightQueryTests {
    @Test func wordsMatchNameOrContents() {
        let q = SpotlightQueryBuilder.queryString(for: SearchSpec(query: "tax return", scope: .files))
        #expect(q == #"(kMDItemFSName == "*tax*"cd || kMDItemTextContent == "tax*"cdw) && "#
            + #"(kMDItemFSName == "*return*"cd || kMDItemTextContent == "return*"cdw) && "#
            + #"kMDItemContentType != "public.folder""#)
    }

    @Test func shortWordsOnlyMatchNames() {
        let q = SpotlightQueryBuilder.queryString(for: SearchSpec(query: "ib"))
        #expect(q == #"kMDItemFSName == "*ib*"cd"#)
    }

    @Test func filtersWithoutWords() {
        let q = SpotlightQueryBuilder.queryString(for: SearchSpec(kind: .images, date: .week))
        #expect(q == #"kMDItemContentTypeTree == "public.image" && kMDItemFSContentChangeDate >= $time.today(-6)"#)
    }

    @Test func escapesSpecialCharacters() {
        #expect(SpotlightQueryBuilder.escape(#"a"b*c\"#) == #"a\"b\*c\\"#)
    }

    @Test func whenSpotlightRuns() {
        #expect(SearchSpec(query: "a").includesSpotlight == false) // too short
        #expect(SearchSpec(query: "ab").includesSpotlight)
        #expect(SearchSpec(query: "abc", scope: .folders).includesSpotlight == false)
        #expect(SearchSpec(date: .today).includesSpotlight)
        #expect(SpotlightQueryBuilder.queryString(for: SearchSpec()) == nil)
        #expect(SpotlightQueryBuilder.queryString(for: SearchSpec(query: "abc", scope: .folders))
            == #"(kMDItemFSName == "*abc*"cd || kMDItemTextContent == "abc*"cdw) && kMDItemContentType == "public.folder""#)
    }

    @Test func indexedFoldersOnlyWithoutFileFilters() {
        #expect(SearchSpec(query: "ib").includesIndexedFolders)
        #expect(!SearchSpec(query: "ib", scope: .files).includesIndexedFolders)
        #expect(!SearchSpec(query: "ib", kind: .pdfs).includesIndexedFolders)
    }

    @Test func savedSearchRoundTrips() throws {
        let s = SavedSearch(name: "Recent PDFs", spec: SearchSpec(kind: .pdfs, date: .month))
        let data = try JSONEncoder().encode([s])
        #expect(try JSONDecoder().decode([SavedSearch].self, from: data) == [s])
        #expect(s.spec.summary == "PDFs · Past 30 Days")
    }
}

@Suite struct FileHitRankerTests {
    let home = "/Users/j"
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func filtersNoise() {
        #expect(FileHitRanker.isNoise("/Users/j/Library/Caches/x.txt", home: home))
        #expect(FileHitRanker.isNoise("/Users/j/proj/node_modules/a/readme.md", home: home))
        #expect(FileHitRanker.isNoise("/Users/j/.config/x", home: home))
        #expect(FileHitRanker.isNoise("/Applications/Foo.app/Contents/Info.plist", home: home))
        #expect(!FileHitRanker.isNoise("/Applications/Foo.app", home: home))
        #expect(!FileHitRanker.isNoise("/Users/j/Library/Mobile Documents/com~apple~CloudDocs/a.pdf", home: home))
        #expect(!FileHitRanker.isNoise("/Users/j/Documents/taxes.pdf", home: home))
    }

    @Test func nameMatchesBeatContentMatches() {
        let hits = [
            FileHit(path: "/Users/j/a/notes.txt", name: "notes.txt"),
            FileHit(path: "/Users/j/a/taxes 2026.pdf", name: "taxes 2026.pdf"),
        ]
        let ranked = FileHitRanker.rank(hits, query: "taxes", home: home, now: now)
        #expect(ranked.first?.hit.name == "taxes 2026.pdf")
        #expect(ranked.first?.nameIndices == [0, 1, 2, 3, 4])
    }

    @Test func recentFilesRise() {
        let hits = [
            FileHit(path: "/Users/j/old.pdf", name: "report.pdf", modified: now.addingTimeInterval(-400 * 86_400)),
            FileHit(path: "/Users/j/new.pdf", name: "report.pdf", lastUsed: now.addingTimeInterval(-3_600)),
        ]
        #expect(FileHitRanker.rank(hits, query: "report", home: home, now: now).first?.hit.path == "/Users/j/new.pdf")
    }
}
