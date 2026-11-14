import Foundation
import Testing
@testable import ScoutCore

@Suite struct FolderCompareTests {
    func makeFolders() throws -> (URL, URL, URL) {
        let base = FileManager.default.temporaryDirectory.appending(path: "compare-\(UUID().uuidString)", directoryHint: .isDirectory)
        let left = base.appending(path: "Left", directoryHint: .isDirectory)
        let right = base.appending(path: "Right", directoryHint: .isDirectory)
        for folder in [left, right] {
            try FileManager.default.createDirectory(at: folder.appending(path: "Sub"), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: folder.appending(path: "node_modules"), withIntermediateDirectories: true)
        }
        return (base, left, right)
    }

    func write(_ text: String, _ url: URL, age: TimeInterval) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -age)], ofItemAtPath: url.filePath)
    }

    @Test func comparesAndPlans() throws {
        let (base, left, right) = try makeFolders()
        defer { try? FileManager.default.removeItem(at: base) }
        try write("same", left.appending(path: "same.txt"), age: 100)
        try write("same", right.appending(path: "same.txt"), age: 100)
        try write("new", left.appending(path: "Sub/only-left.txt"), age: 10)
        try write("extra", right.appending(path: "only-right.txt"), age: 10)
        try write("v2 edited", left.appending(path: "report.txt"), age: 10)
        try write("v1", right.appending(path: "report.txt"), age: 1000)
        try write("mine", left.appending(path: "notes.txt"), age: 1000)
        try write("newer there", right.appending(path: "notes.txt"), age: 10)
        try write("ignored", left.appending(path: "node_modules/x.js"), age: 10)
        try write("hidden", left.appending(path: ".DS_Store"), age: 10)
        // Same size, different dates, same contents: only the content check calls them the same.
        try write("abcd", left.appending(path: "touched.txt"), age: 10)
        try write("abcd", right.appending(path: "touched.txt"), age: 500)

        let entries = FolderCompare.compare(left, right)
        let status = Dictionary(uniqueKeysWithValues: entries.map { ($0.path, $0.status) })
        #expect(status == [
            "same.txt": .same, "Sub/only-left.txt": .onlyLeft, "only-right.txt": .onlyRight,
            "report.txt": .leftNewer, "notes.txt": .rightNewer, "touched.txt": .leftNewer,
        ])
        let checked = FolderCompare.compare(left, right, checkContents: true)
        #expect(checked.first { $0.path == "touched.txt" }?.status == .same)

        // Left wins: copy new and newer; never overwrite newer work on the right.
        let plan = FolderCompare.plan(checked, leftToRight: true, mirror: false)
        #expect(Set(plan.copy) == ["Sub/only-left.txt", "report.txt"])
        #expect(plan.replace == ["report.txt"])
        #expect(plan.trash.isEmpty)
        #expect(FolderCompare.plan(checked, leftToRight: true, mirror: true).trash == ["only-right.txt"])
        let back = FolderCompare.plan(checked, leftToRight: false, mirror: false)
        #expect(Set(back.copy) == ["only-right.txt", "notes.txt"])
    }

    @Test func differentWhenSameTimeButNotSameSize() {
        let t = Date()
        let entries = [FolderCompare.Entry(path: "a", status: .different,
                                           left: .init(size: 1, modified: t), right: .init(size: 2, modified: t))]
        // "Different" (can't tell which is newer) copies in either direction you choose.
        #expect(FolderCompare.plan(entries, leftToRight: true, mirror: false).replace == ["a"])
        #expect(FolderCompare.plan(entries, leftToRight: false, mirror: false).replace == ["a"])
    }
}
