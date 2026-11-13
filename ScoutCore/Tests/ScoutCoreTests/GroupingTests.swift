import Foundation
import Testing
@testable import ScoutCore

@Suite struct GroupingTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }()

    private func date(_ string: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: string)!
    }

    private func file(_ name: String, size: Int64? = 10, added: String? = nil, folder: Bool = false) -> FileItem {
        FileItem(url: URL(filePath: "/d/" + name), name: name, isDirectory: folder, size: folder ? nil : size,
                 dateAdded: added.map(date))
    }

    @Test func groupsByKindLikeFinder() {
        let items = [file("a.docx"), file("b.png"), file("c.pdf"), file("Stuff", folder: true), file("d.docx"),
                     file("e.xlsx"), file("setup.dmg"), file("f.zip"), file("main.swift"), file("mystery.zzz")]
        let groups = ItemGrouper.groups(items, by: .kind)
        #expect(groups.map(\.title) == ["Folders", "Archives", "Code", "Disk Images & Installers", "Documents",
                                         "Images", "PDF Documents", "Spreadsheets", "Other"])
        #expect(groups.first { $0.title == "Documents" }?.items.map(\.name) == ["a.docx", "d.docx"]) // order kept
    }

    @Test func groupsByDateNewestFirst() {
        let now = date("2026-11-13 16:40")
        let items = [file("old", added: "2024-03-01 09:00"), file("today", added: "2026-11-13 08:00"),
                     file("yesterday", added: "2026-11-12 23:00"), file("week", added: "2026-11-09 10:00"),
                     file("month", added: "2026-10-20 10:00"), file("sept", added: "2026-09-02 10:00"),
                     file("march", added: "2026-03-02 10:00"), file("lastyear", added: "2025-06-01 10:00"),
                     file("none")]
        let groups = ItemGrouper.groups(items, by: .dateAdded, now: now, calendar: calendar)
        #expect(groups.map(\.title) == ["Today", "Yesterday", "Previous 7 Days", "Previous 30 Days",
                                         "September", "March", "2025", "2024", "No Date"])
    }

    @Test func groupsBySizeAndName() {
        var folder = file("Big", folder: true)
        folder.folderBytes = 2_000_000_000
        let items = [file("a", size: 50), file("b", size: 5_000_000), folder, file("c", size: 0), file("Ünder")]
        #expect(ItemGrouper.groups(items, by: .size).map(\.title) == ["Over 1 GB", "1 – 10 MB", "Under 100 KB", "Empty"])
        #expect(ItemGrouper.groups([file("beta"), file("Alpha"), file("über"), file("2026 plan")], by: .name).map(\.title)
            == ["#", "A", "B", "U"])
        #expect(ItemGrouper.groups(items, by: .none).count == 1)
    }
}
