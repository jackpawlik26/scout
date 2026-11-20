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

@Suite struct LinkTests {
    @Test func parsesAndNamesLinks() {
        #expect(ItemLink("notion.so/acme/brief")?.url == "https://notion.so/acme/brief")
        #expect(ItemLink("notion.so/acme/brief")?.title == "Notion")
        #expect(ItemLink("https://www.figma.com/file/x")?.title == "Figma")
        #expect(ItemLink("https://portal.acme.com", title: " Client portal ")?.title == "Client portal")
        #expect(ItemLink("https://acme.com")?.title == "acme.com")
        #expect(ItemLink("not a link") == nil)
        #expect(ItemLink("javascript:alert(1)") == nil)
        #expect(ItemLink("file:///etc/passwd") == nil)
        #expect(ItemLink("hello") == nil)
    }

    @Test func linksFollowMovesAndSearch() {
        var c = Customizations()
        c.update("/d/Acme") { $0.links = [ItemLink(title: "Brief", url: "https://notion.so/acme")] }
        #expect(!(c.style(for: "/d/Acme")?.isEmpty ?? true))
        c.moved(from: "/d/Acme", to: "/d/Clients/Acme")
        #expect(c.style(for: "/d/Clients/Acme")?.links?.first?.title == "Brief")
        #expect(c.linksMatching("brief").map(\.path) == ["/d/Clients/Acme"])
        #expect(c.linksMatching("acme notion").count == 1)
        #expect(c.linksMatching("figma").isEmpty)
        c.update("/d/Clients/Acme") { $0.links = [] }
        #expect(c.styles["/d/Clients/Acme"] == nil)
    }
}

@Suite struct FieldTests {
    @Test func valuesNormalizeFollowMovesAndGroup() throws {
        var c = Customizations()
        let status = FieldDefinition(name: "Status", kind: .choice, choices: ["To do", "In progress", "Done"])
        let amount = FieldDefinition(name: "Amount", kind: .number)
        let due = FieldDefinition(name: "Due", kind: .date)
        c.addField(status)
        c.addField(amount)
        c.addField(due)

        c.setValue("in progress", of: status.id, for: "/d/Acme")
        c.setValue("$1,200", of: amount.id, for: "/d/Acme")
        c.setValue("2026-12-01", of: due.id, for: "/d/Acme")
        c.setValue("Done", of: status.id, for: "/d/Globex")
        c.setValue("next week", of: due.id, for: "/d/Globex") // not a date: ignored
        #expect(c.value(of: status.id, for: "/d/Acme") == "In progress") // matched to the choice's casing
        #expect(c.value(of: amount.id, for: "/d/Acme") == "1200")
        #expect(c.value(of: due.id, for: "/d/Globex") == nil)

        c.moved(from: "/d/Acme", to: "/d/Clients/Acme")
        #expect(c.paths(withValue: "In progress", in: status.id) == ["/d/Clients/Acme"])
        #expect(c.counts(for: status.id) == ["In progress": 1, "Done": 1])
        #expect(c.fieldValuesMatching("progress") == ["/d/Clients/Acme"])

        #expect(status.less("To do", "Done"))
        #expect(amount.less("9", "1200"))
        #expect(!amount.less(nil, "1"))

        c.setValue("", of: status.id, for: "/d/Globex")
        #expect(c.styles["/d/Globex"] == nil) // cleared values drop the style

        c.deleteField(status.id)
        #expect(c.fields.map(\.name) == ["Amount", "Due"])
        #expect(c.value(of: status.id, for: "/d/Clients/Acme") == nil)
        #expect(c.value(of: amount.id, for: "/d/Clients/Acme") == "1200")

        // Saved files from before fields existed still load.
        let old = #"{"styles":{"/d/x":{"note":"hi"}},"pinned":{}}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Customizations.self, from: old)
        #expect(decoded.style(for: "/d/x")?.note == "hi")
        #expect(decoded.fields.isEmpty)
    }
}
