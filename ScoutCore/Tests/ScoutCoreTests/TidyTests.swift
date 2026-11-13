import Foundation
import Testing
@testable import ScoutCore

@Suite struct TidyTests {
    private func file(_ name: String, added: Date? = Date(timeIntervalSince1970: 0), folder: Bool = false) -> FileItem {
        FileItem(url: URL(filePath: "/Users/j/Downloads/" + name), name: name, isDirectory: folder,
                 isHidden: name.hasPrefix("."), dateAdded: added)
    }

    @Test func plansMovesByKind() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let items = [file("Report.pdf"), file("photo.HEIC"), file("Screenshot 2026-11-10 at 1.png"),
                     file("CleanShot 2026-11-13.png"), file("setup.dmg"), file("Firefox Installer.exe"),
                     file("essay.docx"), file("data.xlsx"), file("deck.pptx"), file("song.mp3"), file("clip.mov"),
                     file("archive.zip"), file("script.py"), file("notes.txt"), file("weird.zzz"),
                     file("Projects", folder: true), file(".DS_Store"), file("big.iso.crdownload"),
                     file("just-now.pdf", added: now.addingTimeInterval(-30))]
        let plan = Tidy.plan(for: items, in: URL(filePath: "/Users/j/Downloads"), now: now)
        let byName = Dictionary(uniqueKeysWithValues: plan.map { ($0.item.name, $0.folder) })
        #expect(byName == [
            "Report.pdf": "PDFs", "photo.HEIC": "Images", "Screenshot 2026-11-10 at 1.png": "Screenshots",
            "CleanShot 2026-11-13.png": "Screenshots", "setup.dmg": "Installers", "Firefox Installer.exe": "Installers",
            "essay.docx": "Documents", "data.xlsx": "Spreadsheets", "deck.pptx": "Presentations", "song.mp3": "Audio",
            "clip.mov": "Videos", "archive.zip": "Archives", "script.py": "Code", "notes.txt": "Documents",
            "weird.zzz": "Other",
        ])
        #expect(Tidy.summary(plan).first?.folder == "Documents")
    }

    @Test func leavesFilesAlreadyInTheirFolder() {
        let pdf = FileItem(url: URL(filePath: "/d/PDFs/a.pdf"), name: "a.pdf", isDirectory: false)
        #expect(Tidy.plan(for: [pdf], in: URL(filePath: "/d/PDFs")).isEmpty)
    }
}
