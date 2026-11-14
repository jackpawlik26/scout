import Foundation
import Testing
@testable import ScoutCore

@Suite struct RelatedFilesTests {
    let t = Date(timeIntervalSince1970: 1_000_000)

    @Test func openedTogetherRanksFirst() {
        var opens = OpenLog()
        opens.record("/u/Work/model.xlsx", at: t)
        opens.record("/u/Work/memo.docx", at: t.addingTimeInterval(5 * 60))
        opens.record("/u/Work/deck.key", at: t.addingTimeInterval(50 * 60))
        opens.record("/u/Other/far.pdf", at: t.addingTimeInterval(5 * 3600))
        let related = RelatedFiles.rank(path: "/u/Work/model.xlsx", opens: opens, history: FileHistory(), home: "/u")
        #expect(related == ["/u/Work/memo.docx", "/u/Work/deck.key"])
    }

    @Test func movedTogetherFollowsLaterMoves() {
        var history = FileHistory()
        history.append(FileHistoryEntry(action: .move, changes: [
            FileChange(from: "/u/Downloads/a.pdf", to: "/u/Taxes/a.pdf"),
            FileChange(from: "/u/Downloads/b.pdf", to: "/u/Taxes/b.pdf"),
        ]))
        history.append(FileHistoryEntry(action: .rename, changes: [FileChange(from: "/u/Taxes/b.pdf", to: "/u/Taxes/W-2.pdf")]))
        #expect(RelatedFiles.rank(path: "/u/Taxes/a.pdf", opens: OpenLog(), history: history, home: "/u") == ["/u/Taxes/W-2.pdf"])
        #expect(RelatedFiles.rank(path: "/u/Taxes/W-2.pdf", opens: OpenLog(), history: history, home: "/u") == ["/u/Taxes/a.pdf"])
    }

    @Test func spotlightFillsInAndJunkIsSkipped() {
        let hits = [
            FileHit(path: "/u/Work/deck.key", name: "deck.key", lastUsed: t.addingTimeInterval(60)),
            FileHit(path: "/u/Work", name: "Work", isFolder: true, lastUsed: t),
            FileHit(path: "/Applications/Keynote.app", name: "Keynote.app", lastUsed: t, contentType: "com.apple.application-bundle"),
            FileHit(path: "/u/Library/Caches/x.db", name: "x.db", lastUsed: t),
            FileHit(path: "/u/Work/model.xlsx", name: "model.xlsx", lastUsed: t),
        ]
        let related = RelatedFiles.rank(path: "/u/Work/model.xlsx", opens: OpenLog(), history: FileHistory(),
                                        spotlightUsed: t, spotlightHits: hits, home: "/u")
        #expect(related == ["/u/Work/deck.key"])
    }

    @Test func openLogKeepsTheLatestAndSaves() throws {
        var log = OpenLog()
        for i in 0..<(OpenLog.kept + 5) { log.record("/f\(i)", at: t) }
        #expect(log.entries.count == OpenLog.kept)
        #expect(log.entries.first?.path == "/f5")
        let url = FileManager.default.temporaryDirectory.appending(path: "opens-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try log.save(to: url)
        #expect(OpenLog.load(from: url) == log)
    }

    @Test func queryCoversAnHourEitherSide() {
        let q = RelatedFiles.query(around: Date(timeIntervalSince1970: 0))
        #expect(q.contains("$time.iso(1969-12-31T23:00:00Z)"))
        #expect(q.contains("$time.iso(1970-01-01T01:00:00Z)"))
    }
}
