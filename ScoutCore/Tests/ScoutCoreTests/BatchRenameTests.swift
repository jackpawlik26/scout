import Foundation
import Testing
@testable import ScoutCore

@Suite struct BatchRenameTests {
    let names = ["IMG_0001.JPG", "IMG_0002.JPG", "notes.final.txt", ".env", "Folder"]
    func items(_ names: [String]) -> [RenameContext] { names.map { RenameContext(name: $0, parent: "Trip") } }
    func rename(_ names: [String], _ steps: [RenameStep], configure: (inout RenamePipeline) -> Void = { _ in }) -> [String] {
        var pipeline = RenamePipeline(steps: steps)
        configure(&pipeline)
        return BatchRename.newNames(for: items(names), pipeline: pipeline)
    }

    @Test func replaceKeepsExtensionsAndHonorsCase() {
        #expect(rename(names, [RenameStep(.replace, text: "img_", replacement: "Trip ")])
            == ["Trip 0001.JPG", "Trip 0002.JPG", "notes.final.txt", ".env", "Folder"])
        #expect(rename(names, [RenameStep(.replace, text: "img_", replacement: "x", matchCase: true)])[0] == "IMG_0001.JPG")
    }

    @Test func stepsRunInOrder() {
        let steps = [RenameStep(.changeCase, caseStyle: .lower), RenameStep(.add, text: "2026-", position: .start),
                     RenameStep(.add, text: "_v2")]
        #expect(rename(["Report.PDF"], steps) == ["2026-report_v2.PDF"])
        // Reversed order gives a different result: case runs last.
        #expect(rename(["Report.PDF"], steps.reversed()) == ["2026-report_v2.PDF".lowercased().replacingOccurrences(of: ".pdf", with: ".PDF")])
    }

    @Test func regexWithGroups() {
        let step = RenameStep(.replace, text: #"IMG_(\d+)"#, replacement: "Photo $1 in {parent}", regex: true)
        #expect(rename(["IMG_0042.JPG"], [step]) == ["Photo 0042 in Trip.JPG"])
        // Variable values are never read as $ groups.
        let money = RenameStep(.replace, text: "x", replacement: "{parent}", regex: true)
        #expect(BatchRename.newNames(for: [RenameContext(name: "x.txt", parent: "$1 bill")],
                                     pipeline: RenamePipeline(steps: [money])) == ["$1 bill.txt"])
        // An invalid pattern changes nothing and is reported.
        let bad = RenameStep(.replace, text: "(", regex: true)
        #expect(bad.problem != nil)
        #expect(rename(["a.txt"], [bad]) == ["a.txt"])
    }

    @Test func numbersAndTemplates() {
        let twelve = (1...12).map { "photo\($0).heic" }
        let renamed = rename(twelve, [RenameStep(.newName, text: "Ski Trip {n}")])
        #expect(renamed.first == "Ski Trip 01.heic" && renamed.last == "Ski Trip 12.heic")
        #expect(rename(["a.txt", "b.txt"], [RenameStep(.add, text: " {n}")]) { $0.startNumber = 5; $0.numberStep = 5; $0.digits = 3 }
            == ["a 005.txt", "b 010.txt"])
    }

    @Test func dateAndOtherVariables() {
        let created = ISO8601DateFormatter().date(from: "2026-03-09T15:04:00Z")!
        var item = RenameContext(name: "scan.pdf", parent: "Taxes", created: created, width: 800, height: 600)
        item.modified = created
        let pipeline = RenamePipeline(steps: [RenameStep(.newName, text: "{parent} {created:yyyy} {width}x{height} {{n}}")])
        #expect(BatchRename.newNames(for: [item], pipeline: pipeline) == ["Taxes 2026 800x600 {n}.pdf"])
        // Unknown words stay as typed; formats with "/" or ":" can't break the name.
        let odd = RenamePipeline(steps: [RenameStep(.newName, text: "{nope} {modified:yyyy/MM HH:mm}")])
        #expect(BatchRename.newNames(for: [item], pipeline: odd)[0].hasPrefix("{nope} 2026-03 "))
        #expect(!BatchRename.newNames(for: [item], pipeline: odd)[0].contains(":"))
    }

    @Test func caseStylesAndCleanup() {
        #expect(BatchRename.changeCase("My Summer  Photos!", to: .kebab) == "my-summer-photos")
        #expect(BatchRename.changeCase("My Summer Photos", to: .snake) == "my_summer_photos")
        #expect(BatchRename.changeCase("hello WORLD", to: .sentence) == "Hello world")
        #expect(rename(["  a   b .txt"], [RenameStep(.trimSpaces)]) == ["a b.txt"])
        #expect(rename(["abcdef.txt"], [RenameStep(.removeCharacters, position: .start, count: 2),
                                        RenameStep(.removeCharacters, position: .end, count: 10)]) == [".txt"])
    }

    @Test func builtInPresets() {
        let preset = { (name: String) in RenamePreset.builtIn.first { $0.name.hasPrefix(name) }!.pipeline }
        #expect(BatchRename.newNames(for: items(["Report copy 2.pdf", "Notes (1).txt", "Plan.key"]),
                                     pipeline: preset("Remove")) == ["Report.pdf", "Notes.txt", "Plan.key"])
        #expect(BatchRename.newNames(for: items(["My Summer Photo.JPG"]), pipeline: preset("Web")) == ["my-summer-photo.JPG"])
        #expect(BatchRename.newNames(for: items(["A.JPG", "b.Png"]), pipeline: preset("Lowercase")) == ["A.jpg", "b.png"])
        // Presets survive a save and load.
        let data = try! JSONEncoder().encode(RenamePreset.builtIn)
        #expect(try! JSONDecoder().decode([RenamePreset].self, from: data) == RenamePreset.builtIn)
    }

    @Test func autoNumbersConflicts() {
        let step = RenameStep(.newName, text: "Trip")
        let renamed = rename(["a.jpg", "b.jpg", "c.png"], [step]) { $0.autoNumberConflicts = true }
        #expect(renamed == ["Trip.jpg", "Trip 2.jpg", "Trip.png"])
        let taken = BatchRename.newNames(for: items(["a.jpg"]), pipeline: {
            var p = RenamePipeline(steps: [step]); p.autoNumberConflicts = true; return p
        }(), existing: ["Trip.jpg"])
        #expect(taken == ["Trip 2.jpg"])
    }

    @Test func extensionsCanBeIncluded() {
        #expect(rename(["A.JPG"], [RenameStep(.changeCase, caseStyle: .lower)]) { $0.includeExtension = true } == ["a.jpg"])
        #expect(BatchRename.split("Archive 2026.tar", keepExtension: true) == ("Archive 2026", "tar"))
        #expect(BatchRename.split("Notes v2. final draft", keepExtension: true) == ("Notes v2. final draft", ""))
    }

    @Test func flagsProblems() {
        let old = ["a.txt", "b.txt", "c.txt"]
        // Swapping names inside the batch is fine; clashing with others isn't.
        #expect(BatchRename.problems(old: ["a.txt", "b.txt"], new: ["b.txt", "a.txt"], existing: ["z.txt"]).isEmpty)
        let problems = BatchRename.problems(old: old, new: ["x.txt", "X.txt", "z.txt"], existing: ["z.txt"])
        #expect(problems[0] == "Same as another" && problems[1] == "Same as another")
        #expect(problems[2] == "Already in this folder")
        #expect(BatchRename.problems(old: ["a"], new: [" "], existing: [])[0] == "Empty name")
        #expect(BatchRename.problems(old: ["a"], new: ["a/b"], existing: [])[0] == "Can’t contain / or :")
        #expect(BatchRename.problems(old: ["a"], new: [".a"], existing: [])[0] == "Would be hidden")
    }
}
