import Testing
@testable import ScoutCore

@Suite struct BatchRenameTests {
    let names = ["IMG_0001.JPG", "IMG_0002.JPG", "notes.final.txt", ".env", "Folder"]

    @Test func findAndReplaceKeepsExtensions() {
        var rules = RenameRules()
        rules.find = "img_"
        rules.replace = "Trip "
        #expect(BatchRename.newNames(for: names, rules: rules)
            == ["Trip 0001.JPG", "Trip 0002.JPG", "notes.final.txt", ".env", "Folder"])
        rules.matchCase = true
        #expect(BatchRename.newNames(for: names, rules: rules)[0] == "IMG_0001.JPG")
    }

    @Test func caseNumberingPrefixSuffix() {
        var rules = RenameRules()
        rules.caseChange = .lower
        rules.prefix = "2026-"
        rules.suffix = "_v2"
        #expect(BatchRename.newNames(for: ["Report.PDF"], rules: rules) == ["2026-report_v2.PDF"])

        rules = RenameRules()
        rules.numbering = .replace
        rules.baseName = "Ski Trip"
        let twelve = (1...12).map { "photo\($0).heic" }
        let renamed = BatchRename.newNames(for: twelve, rules: rules)
        #expect(renamed.first == "Ski Trip 01.heic" && renamed.last == "Ski Trip 12.heic")

        rules.numbering = .append
        rules.startNumber = 5
        #expect(BatchRename.newNames(for: ["a.txt", "b.txt"], rules: rules) == ["a 5.txt", "b 6.txt"])
    }

    @Test func extensionsCanBeIncluded() {
        var rules = RenameRules()
        rules.keepExtension = false
        rules.caseChange = .lower
        #expect(BatchRename.newNames(for: ["A.JPG"], rules: rules) == ["a.jpg"])
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
