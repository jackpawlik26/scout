import Foundation
import Testing
@testable import ScoutCore

@Suite struct TriageTests {
    func move(_ from: String, _ to: String, site: String? = nil, daysAgo: Double = 1,
              action: FileAction = .move) -> FileHistoryEntry {
        FileHistoryEntry(date: Date(timeIntervalSinceNow: -daysAgo * 86_400), action: action,
                         changes: [FileChange(from: from, to: to, site: site)])
    }

    @Test func learnsFromSiteTypeAndWords() {
        var history = FileHistory()
        for i in 1...6 {
            history.append(move("/u/Downloads/hw\(i).pdf", "/u/School/FIN320/hw\(i).pdf", site: "canvas.depaul.edu"))
        }
        history.append(move("/u/Downloads/Invoice_Acme_03.pdf", "/u/Work/Acme/Invoices/Invoice_Acme_03.pdf"))
        history.append(move("/u/Downloads/Invoice_Acme_04.pdf", "/u/Work/Acme/Invoices/Invoice_Acme_04.pdf"))
        history.append(move("/u/Downloads/photo.jpg", "/u/Pictures/photo.jpg"))

        let canvas = DestinationLearner.suggestions(name: "hw7.pdf", site: "canvas.depaul.edu",
                                                    history: history, excluding: "/u/Downloads")
        #expect(canvas.first?.folder == "/u/School/FIN320")
        #expect(canvas.first?.reason == "6 PDF files from canvas.depaul.edu went here")
        #expect(!canvas.contains { $0.folder == "/u/Pictures" })

        // Same words and type, no site: Acme invoices win.
        let invoice = DestinationLearner.suggestions(name: "Invoice_Acme_05.pdf", site: nil,
                                                     history: history, excluding: "/u/Downloads")
        #expect(invoice.first?.folder == "/u/Work/Acme/Invoices")
    }

    @Test func undoneMovesDontTeach() {
        var history = FileHistory()
        let mistake = move("/u/Downloads/a.pdf", "/u/Wrong/a.pdf", site: "x.com")
        history.append(mistake)
        history.append(FileHistoryEntry(action: .undo, changes: [FileChange(from: "/u/Wrong/a.pdf", to: "/u/Downloads/a.pdf")],
                                        undoes: mistake.id))
        #expect(DestinationLearner.suggestions(name: "b.pdf", site: "x.com", history: history, excluding: "/u/Downloads").isEmpty)
    }

    @Test func rules() throws {
        let rule = try #require(TriageRule.suggested(name: "syllabus.PDF", site: "canvas.depaul.edu",
                                                     destination: "/u/School/FIN320"))
        #expect(rule.name == "PDF files from canvas.depaul.edu → FIN320")
        #expect(rule.summary == "PDF files from canvas.depaul.edu")
        #expect(rule.matches(name: "hw8.pdf", site: "canvas.depaul.edu"))
        #expect(!rule.matches(name: "hw8.docx", site: "canvas.depaul.edu"))
        #expect(!rule.matches(name: "hw8.pdf", site: nil))

        var off = rule
        off.isEnabled = false
        #expect(!off.matches(name: "hw8.pdf", site: "canvas.depaul.edu"))
        // A rule with no conditions never matches (it would file everything).
        #expect(!TriageRule(name: "All", destination: "/u/X").matches(name: "a.pdf", site: nil))
        #expect(TriageRule.suggested(name: "README", site: nil, destination: "/u/X") == nil)

        let named = TriageRule(name: "Statements", nameContains: "statement", destination: "/u/Bank")
        #expect(TriageRule.first([off, named], matching: "Chase Statement Oct.pdf", site: nil) == named)
    }

    @Test func readyMeansFinishedAndNew() {
        let now = Date()
        func file(_ name: String, addedAgo: TimeInterval, modifiedAgo: TimeInterval? = nil) -> FileItem {
            FileItem(url: URL(filePath: "/u/Downloads/\(name)"), name: name, isDirectory: false,
                     dateModified: now.addingTimeInterval(-(modifiedAgo ?? addedAgo)),
                     dateAdded: now.addingTimeInterval(-addedAgo))
        }
        #expect(TriageRule.isReady(file("a.pdf", addedAgo: 30), now: now))
        #expect(!TriageRule.isReady(file("a.pdf", addedAgo: 2), now: now)) // still settling
        #expect(!TriageRule.isReady(file("a.pdf", addedAgo: 30, modifiedAgo: 1), now: now)) // still being written
        #expect(!TriageRule.isReady(file("a.pdf.crdownload", addedAgo: 30), now: now))
        #expect(!TriageRule.isReady(file("old.pdf", addedAgo: 3600), now: now)) // not new: rules don't sweep old files
    }

    @Test func inboxSkipsFoldersHiddenAndPartial() {
        let items = [
            FileItem(url: URL(filePath: "/d/a.pdf"), name: "a.pdf", isDirectory: false, dateAdded: Date(timeIntervalSince1970: 1)),
            FileItem(url: URL(filePath: "/d/b.zip"), name: "b.zip", isDirectory: false, dateAdded: Date(timeIntervalSince1970: 2)),
            FileItem(url: URL(filePath: "/d/Folder"), name: "Folder", isDirectory: true),
            FileItem(url: URL(filePath: "/d/.hidden"), name: ".hidden", isDirectory: false, isHidden: true),
            FileItem(url: URL(filePath: "/d/c.crdownload"), name: "c.crdownload", isDirectory: false),
        ]
        #expect(Triage.inbox(items).map(\.name) == ["b.zip", "a.pdf"])
    }

    @Test func rulesSaveAndLoad() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "rules-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let rules = [TriageRule(name: "R", extensions: ["PDF"], destination: "/u/X")]
        try ScoutStore.saveTriageRules(rules, to: url)
        let loaded = ScoutStore.loadTriageRules(from: url)
        #expect(loaded.map(\.id) == rules.map(\.id))
        #expect(loaded.first?.extensions == ["pdf"])
    }

    @Test func olderHistoryWithoutSitesStillLoads() throws {
        let line = #"{"action":"move","changes":[{"from":"/a","to":"/b"}],"date":"2026-11-14T20:00:00Z","id":"5F2C6B9E-1D2A-4C3B-9E8F-0A1B2C3D4E5F"}"#
        let url = FileManager.default.temporaryDirectory.appending(path: "old-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data((line + "\n").utf8).write(to: url)
        let history = FileHistoryStore.load(from: url)
        #expect(history.entries.first?.changes.first?.site == nil)
        #expect(history.entries.first?.note == nil)
    }
}
