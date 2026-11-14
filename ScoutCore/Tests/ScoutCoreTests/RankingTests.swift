import Foundation
import Testing
@testable import ScoutCore

@Suite struct FrecencyTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func recentAndFrequentRankFirst() {
        var log = FrecencyLog()
        log.record("/a", at: now.addingTimeInterval(-100 * 86_400))
        for i in 0..<5 { log.record("/b", at: now.addingTimeInterval(Double(-i) * 3_600)) }
        log.record("/c", at: now.addingTimeInterval(-60))
        #expect(log.top(3, now: now) == ["/b", "/c", "/a"])
    }

    @Test func rapidRevisitsCountOnce() {
        var log = FrecencyLog()
        log.record("/a", at: now)
        log.record("/a", at: now.addingTimeInterval(5))
        #expect(log.entries["/a"]?.count == 1)
    }

    @Test func keepsOnlyRecentVisits() {
        var log = FrecencyLog()
        for i in 0..<25 { log.record("/a", at: now.addingTimeInterval(Double(i) * 100)) }
        #expect(log.entries["/a"]?.count == FrecencyLog.visitsKept)
    }

    @Test func roundTripsThroughJSON() throws {
        var log = FrecencyLog()
        log.record("/a", at: now)
        let data = try JSONEncoder().encode(log)
        #expect(try JSONDecoder().decode(FrecencyLog.self, from: data) == log)
    }
}

@Suite struct FolderRankerTests {
    let home = "/Users/alex"
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func folders(_ paths: [String]) -> [IndexedFolder] {
        paths.map { IndexedFolder(path: $0, home: home) }
    }

    @Test func nameMatchesBeatPathMatches() {
        let list = folders(["/Users/alex/Downloads", "/Users/alex/dev/old-logs"])
        let ranked = FolderRanker.rank(query: "dl", folders: list, frecency: .init(), home: home, now: now)
        #expect(ranked.first?.folder.name == "Downloads")
    }

    @Test func frecencyBreaksTies() {
        let list = folders(["/Users/alex/a/Notes", "/Users/alex/b/Notes"])
        var log = FrecencyLog()
        log.record("/Users/alex/b/Notes", at: now)
        let ranked = FolderRanker.rank(query: "notes", folders: list, frecency: log, home: home, now: now)
        #expect(ranked.first?.folder.path == "/Users/alex/b/Notes")
    }

    @Test func scatteredPathMatchesAreDropped() {
        let list = folders([
            "/Users/alex/Library/CloudStorage/ProtonDrive-sam@proton.me-folder/Sam Pawlak/UI Resources/Illustrations",
            "/Users/alex/finance/valuation",
        ])
        let ranked = FolderRanker.rank(query: "valuation", folders: list, frecency: .init(), home: home, now: now)
        #expect(ranked.map(\.folder.name) == ["valuation"])
    }

    @Test func scatteredNameMatchesAreDropped() {
        let list = folders([
            "/Users/alex/mc/mr_dungeons_andtavernsoceanmonumentoverhaul",
            "/Users/alex/Professional/Resume",
            "/Users/alex/Professional/2029 Resume",
        ])
        let ranked = FolderRanker.rank(query: "resume", folders: list, frecency: .init(), home: home, now: now)
        #expect(ranked.map(\.folder.name) == ["Resume", "2029 Resume"])
        // Abbreviations and short fuzzy queries still work.
        #expect(FolderRanker.rank(query: "rsme", folders: list, frecency: .init(), home: home, now: now)
            .first?.folder.name == "Resume")
        #expect(FolderRanker.rank(query: "dl", folders: folders(["/Users/alex/Downloads"]),
                                  frecency: .init(), home: home, now: now).count == 1)
    }

    @Test func wholeWordPathMatchesStillWork() {
        // "study prep" isn’t in the name "guides", but both words are in its path.
        let list = folders(["/Users/alex/study-prep/guides"])
        let ranked = FolderRanker.rank(query: "study prep", folders: list, frecency: .init(), home: home, now: now)
        #expect(ranked.count == 1)
    }

    @Test func slashQueriesMatchThePath() {
        let list = folders(["/Users/alex/Scout/Scout", "/Users/alex/other/Scout"])
        let ranked = FolderRanker.rank(query: "other/sc", folders: list, frecency: .init(), home: home, now: now)
        #expect(ranked.first?.folder.path == "/Users/alex/other/Scout")
    }

    @Test func emptyQueryShowsMostUsed() {
        var log = FrecencyLog()
        log.record("/Users/alex/x", at: now)
        let ranked = FolderRanker.rank(query: "", folders: [], frecency: log, home: home, now: now)
        #expect(ranked.map(\.folder.path) == ["/Users/alex/x"])
    }

    @Test func visitedFoldersOutsideIndexStillShowUp() {
        var log = FrecencyLog()
        log.record("/Applications", at: now)
        let ranked = FolderRanker.rank(query: "apps", folders: [], frecency: log, home: home, now: now)
        #expect(ranked.first?.folder.path == "/Applications")
    }

    @Test func friendlyPaths() {
        #expect(PathDisplay.display("/Users/alex/Documents", home: home) == "~/Documents")
        #expect(PathDisplay.display("/Users/alex/Library/Mobile Documents/com~apple~CloudDocs/Taxes",
                                    home: home) == "iCloud Drive/Taxes")
        #expect(PathDisplay.display("/Users/alex/Library/CloudStorage/OneDrive-Contoso/Class",
                                    home: home) == "OneDrive (Contoso)/Class")
        #expect(PathDisplay.display("/Users/alex/Library/CloudStorage/ProtonDrive-me@proton.me-folder/UI",
                                    home: home) == "Proton Drive/UI")
        #expect(PathDisplay.cloudName("GoogleDrive-me@gmail.com") == "Google Drive")
        #expect(PathDisplay.cloudName("Dropbox") == "Dropbox")
    }
}
