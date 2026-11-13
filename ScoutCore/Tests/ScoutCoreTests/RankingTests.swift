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
    let home = "/Users/jack"
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func folders(_ paths: [String]) -> [IndexedFolder] {
        paths.map { IndexedFolder(path: $0, home: home) }
    }

    @Test func nameMatchesBeatPathMatches() {
        let list = folders(["/Users/jack/Downloads", "/Users/jack/dev/old-logs"])
        let ranked = FolderRanker.rank(query: "dl", folders: list, frecency: .init(), home: home, now: now)
        #expect(ranked.first?.folder.name == "Downloads")
    }

    @Test func frecencyBreaksTies() {
        let list = folders(["/Users/jack/a/Notes", "/Users/jack/b/Notes"])
        var log = FrecencyLog()
        log.record("/Users/jack/b/Notes", at: now)
        let ranked = FolderRanker.rank(query: "notes", folders: list, frecency: log, home: home, now: now)
        #expect(ranked.first?.folder.path == "/Users/jack/b/Notes")
    }

    @Test func scatteredPathMatchesAreDropped() {
        let list = folders([
            "/Users/jack/Library/CloudStorage/ProtonDrive-jack@proton.me-folder/Jack Pawlik/UI Resources/Illustrations",
            "/Users/jack/ib-prep/valuation",
        ])
        let ranked = FolderRanker.rank(query: "valuation", folders: list, frecency: .init(), home: home, now: now)
        #expect(ranked.map(\.folder.name) == ["valuation"])
    }

    @Test func scatteredNameMatchesAreDropped() {
        let list = folders([
            "/Users/jack/mc/mr_dungeons_andtavernsoceanmonumentoverhaul",
            "/Users/jack/Professional/Resume",
            "/Users/jack/Professional/2029 Resume",
        ])
        let ranked = FolderRanker.rank(query: "resume", folders: list, frecency: .init(), home: home, now: now)
        #expect(ranked.map(\.folder.name) == ["Resume", "2029 Resume"])
        // Abbreviations and short fuzzy queries still work.
        #expect(FolderRanker.rank(query: "rsme", folders: list, frecency: .init(), home: home, now: now)
            .first?.folder.name == "Resume")
        #expect(FolderRanker.rank(query: "dl", folders: folders(["/Users/jack/Downloads"]),
                                  frecency: .init(), home: home, now: now).count == 1)
    }

    @Test func wholeWordPathMatchesStillWork() {
        // "ib prep" isn't in the name "guides", but both words are in its path.
        let list = folders(["/Users/jack/ib-prep/guides"])
        let ranked = FolderRanker.rank(query: "ib prep", folders: list, frecency: .init(), home: home, now: now)
        #expect(ranked.count == 1)
    }

    @Test func slashQueriesMatchThePath() {
        let list = folders(["/Users/jack/Scout/Scout", "/Users/jack/other/Scout"])
        let ranked = FolderRanker.rank(query: "other/sc", folders: list, frecency: .init(), home: home, now: now)
        #expect(ranked.first?.folder.path == "/Users/jack/other/Scout")
    }

    @Test func emptyQueryShowsMostUsed() {
        var log = FrecencyLog()
        log.record("/Users/jack/x", at: now)
        let ranked = FolderRanker.rank(query: "", folders: [], frecency: log, home: home, now: now)
        #expect(ranked.map(\.folder.path) == ["/Users/jack/x"])
    }

    @Test func visitedFoldersOutsideIndexStillShowUp() {
        var log = FrecencyLog()
        log.record("/Applications", at: now)
        let ranked = FolderRanker.rank(query: "apps", folders: [], frecency: log, home: home, now: now)
        #expect(ranked.first?.folder.path == "/Applications")
    }

    @Test func friendlyPaths() {
        #expect(PathDisplay.display("/Users/jack/Documents", home: home) == "~/Documents")
        #expect(PathDisplay.display("/Users/jack/Library/Mobile Documents/com~apple~CloudDocs/Taxes",
                                    home: home) == "iCloud Drive/Taxes")
        #expect(PathDisplay.display("/Users/jack/Library/CloudStorage/OneDrive-DePaul/Class",
                                    home: home) == "OneDrive (DePaul)/Class")
        #expect(PathDisplay.display("/Users/jack/Library/CloudStorage/ProtonDrive-me@proton.me-folder/UI",
                                    home: home) == "Proton Drive/UI")
        #expect(PathDisplay.cloudName("GoogleDrive-me@gmail.com") == "Google Drive")
        #expect(PathDisplay.cloudName("Dropbox") == "Dropbox")
    }
}
