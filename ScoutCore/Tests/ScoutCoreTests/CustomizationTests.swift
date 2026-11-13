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
