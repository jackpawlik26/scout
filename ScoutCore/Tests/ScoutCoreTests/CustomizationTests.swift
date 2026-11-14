import Foundation
import Testing
@testable import ScoutCore

@Suite struct CustomizationTests {
    @Test func stylesAndPins() throws {
        var c = Customizations()
        c.update("/d/Taxes") { $0.color = "green"; $0.symbol = "dollarsign.circle.fill" }
        c.update("/d/x.pdf") { $0.nickname = "Final resume" }
        #expect(c.style(for: "/d/Taxes")?.color == "green")
        c.update("/d/x.pdf") { $0.nickname = nil }
        #expect(c.styles["/d/x.pdf"] == nil) // empty styles are dropped

        let items = ["a", "b", "c", "d"].map { FileItem(url: URL(filePath: "/d/" + $0), name: $0, isDirectory: false) }
        c.togglePin("/d/c")
        c.togglePin("/d/a")
        #expect(c.pinnedFirst(items, in: "/d").map(\.name) == ["c", "a", "b", "d"])
        #expect(c.isPinned("/d/c"))
        c.togglePin("/d/c")
        #expect(c.pinnedFirst(items, in: "/d").map(\.name) == ["a", "b", "c", "d"])

        let url = FileManager.default.temporaryDirectory.appending(path: "cust-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try ScoutStore.saveCustomizations(c, to: url)
        #expect(ScoutStore.loadCustomizations(from: url) == c)
    }
}

@Suite struct NoteTests {
    @Test func notesFollowMovesAndRenames() {
        var c = Customizations()
        c.update("/u/Work/contract.pdf") { $0.note = "Signed copy sent to Acme" }
        c.update("/u/Work") { $0.color = "blue" }
        c.update("/u/Work/Sub/x.txt") { $0.nickname = "X" }
        c.togglePin("/u/Work/contract.pdf")

        // The folder moves: everything inside goes with it.
        c.moved(from: "/u/Work", to: "/u/Archive/Work")
        #expect(c.style(for: "/u/Archive/Work/contract.pdf")?.note == "Signed copy sent to Acme")
        #expect(c.style(for: "/u/Archive/Work")?.color == "blue")
        #expect(c.style(for: "/u/Archive/Work/Sub/x.txt")?.nickname == "X")
        #expect(c.style(for: "/u/Work/contract.pdf") == nil)
        #expect(c.isPinned("/u/Archive/Work/contract.pdf"))

        // Renamed: still pinned in the same folder. Moved elsewhere: the pin drops (it was for that folder).
        c.moved(from: "/u/Archive/Work/contract.pdf", to: "/u/Archive/Work/Acme contract.pdf")
        #expect(c.isPinned("/u/Archive/Work/Acme contract.pdf"))
        c.moved(from: "/u/Archive/Work/Acme contract.pdf", to: "/u/Desktop/Acme contract.pdf")
        #expect(!c.isPinned("/u/Desktop/Acme contract.pdf"))
        #expect(c.style(for: "/u/Desktop/Acme contract.pdf")?.note == "Signed copy sent to Acme")
        // A similarly named sibling isn't caught up in it.
        c.update("/u/Workshop/a") { $0.note = "keep" }
        c.moved(from: "/u/Work", to: "/u/Elsewhere")
        #expect(c.style(for: "/u/Workshop/a")?.note == "keep")
    }

    @Test func searchAndEmptyNotes() {
        var c = Customizations()
        c.update("/u/a.pdf") { $0.note = "Needs signature by Friday" }
        c.update("/u/b.pdf") { $0.note = "Final, sent" }
        #expect(c.notesMatching("SIGNATURE friday") == ["/u/a.pdf"])
        #expect(c.notesMatching("x").isEmpty)
        // Clearing a note removes the style when nothing else is set.
        c.update("/u/b.pdf") { $0.note = "  " }
        #expect(c.style(for: "/u/b.pdf") == nil)
    }
}
