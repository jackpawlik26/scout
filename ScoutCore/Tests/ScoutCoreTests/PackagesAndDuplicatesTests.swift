import Foundation
import Testing
@testable import ScoutCore

@Suite struct PackageParserTests {
    @Test func readsHomebrew() throws {
        let info = """
        {"formulae":[
          {"name":"gh","desc":"GitHub CLI","homepage":"https://cli.github.com/",
           "installed":[{"version":"2.103.3","installed_on_request":true}]},
          {"name":"xz","desc":"Compression","homepage":"https://tukaani.org/xz/",
           "installed":[{"version":"5.8","installed_on_request":false}]},
          {"name":"broken"}
        ],
        "casks":[{"token":"vorssaint","name":["Vorssaint"],"desc":null,"version":"3.4.4","installed":"3.1.4","outdated":false,
          "artifacts":[{"uninstall":[]},{"app":["Vorssaint.app"]}]}]}
        """
        let outdated = """
        {"formulae":[{"name":"gh","installed_versions":["2.103.3"],"current_version":"2.104.0"}],
         "casks":[{"name":"vorssaint","installed_versions":["3.1.4"],"current_version":"3.4.4"}]}
        """
        let packages = PackageParser.homebrew(info: Data(info.utf8), outdated: Data(outdated.utf8), prefix: "/opt/homebrew")
        #expect(packages.map(\.name) == ["gh", "xz", "vorssaint"])
        let gh = packages[0]
        #expect(gh.isOutdated && gh.latest == "2.104.0" && !gh.isDependency)
        #expect(gh.path == "/opt/homebrew/Cellar/gh" && gh.upgradeCommand == "brew upgrade gh")
        #expect(packages[1].isDependency && !packages[1].isOutdated)
        let cask = packages[2]
        #expect(cask.source == .cask && cask.path == "/Applications/Vorssaint.app")
        #expect(cask.summary == "Vorssaint" && cask.latest == "3.4.4")
        #expect(cask.upgradeCommand == "brew upgrade --cask vorssaint")
    }

    @Test func readsNpm() {
        let list = #"{"name":"lib","dependencies":{"vercel":{"version":"65.9.0"},"corepack":{"version":"0.31.0"}}}"#
        let outdated = #"{"vercel":{"current":"65.9.0","wanted":"65.15.0","latest":"65.15.0"}}"#
        let packages = PackageParser.npm(list: Data(list.utf8), outdated: Data(outdated.utf8), root: "/usr/local/lib/node_modules")
        #expect(packages.map(\.name) == ["corepack", "vercel"])
        #expect(packages[1].isOutdated && packages[1].latest == "65.15.0")
        #expect(packages[1].webPage?.absoluteString == "https://www.npmjs.com/package/vercel")
        #expect(packages[0].path == "/usr/local/lib/node_modules/corepack" && !packages[0].isOutdated)
        // Offline: no outdated info, nothing breaks.
        #expect(PackageParser.npm(list: Data(list.utf8), outdated: nil, root: "/r").count == 2)
        #expect(PackageParser.npm(list: Data("garbage".utf8), outdated: nil, root: "/r").isEmpty)
    }
}

@Suite struct DuplicateFinderTests {
    let dir = FileManager.default.temporaryDirectory.appending(path: "Dupes-\(UUID().uuidString)")

    private func write(_ name: String, _ data: Data) throws {
        let url = dir.appending(path: name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    @Test func findsRealDuplicatesOnly() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let big = Data((0..<300_000).map { UInt8($0 % 251) })
        var almost = big
        almost[150_000] ^= 1 // same size, same start and end, different middle
        try write("Report.pdf", big)
        try write("Downloads/Report copy.pdf", big)
        try write("Downloads/Report (1).pdf", big)
        try write("Other.pdf", almost)
        try write("node_modules/pkg/Report.pdf", big) // skipped folder
        try write(".hidden/Report.pdf", big) // hidden
        try write("_Serato_/Report.pdf", big) // app data
        try write("Music Backup/Report.pdf", big) // a backup
        try write("Photos.library/Report.pdf", big)
        try write("project/.git/HEAD", Data("ref".utf8))
        try write("project/public/Report.pdf", big) // inside a repo
        try write("small.txt", Data(repeating: 7, count: 10))
        try write("small copy.txt", Data(repeating: 7, count: 10)) // under the minimum

        let groups = DuplicateFinder.find(in: [dir, dir.appending(path: "project")], minimumSize: 100_000)
        #expect(groups.count == 1)
        let group = try #require(groups.first)
        #expect(group.paths.count == 3)
        #expect(group.paths[0].hasSuffix("/Report.pdf"))
        #expect(group.wasted == 600_000)

        // (Temp folders may come back as /private/var/…, so take the folder from the result.)
        let home = (group.paths[0] as NSString).deletingLastPathComponent
        let items = CleanupScanner.duplicateItems(groups, home: home)
        #expect(items.count == 2)
        #expect(items.allSatisfy { $0.detail == "Same as ~/Report.pdf" })
    }

    @Test func hardLinksAreNotWaste() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        try write("a.bin", Data(repeating: 1, count: 200_000))
        try FileManager.default.linkItem(at: dir.appending(path: "a.bin"), to: dir.appending(path: "b.bin"))
        #expect(DuplicateFinder.find(in: [dir], minimumSize: 100_000).isEmpty)
    }

    @Test func clonesAreNotWaste() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        try write("a.bin", Data(repeating: 2, count: 200_000))
        // On APFS, copyItem makes a clone that shares the data.
        try FileManager.default.copyItem(at: dir.appending(path: "a.bin"), to: dir.appending(path: "b.bin"))
        let id = { (name: String) in
            try? self.dir.appending(path: name).resourceValues(forKeys: [.fileContentIdentifierKey])
                .allValues[.fileContentIdentifierKey] as? Int64
        }
        guard let a = id("a.bin"), a == id("b.bin") else { return } // not APFS: nothing to check
        #expect(DuplicateFinder.find(in: [dir], minimumSize: 100_000).isEmpty)
    }

    @Test func keepsTheOriginal() {
        let old = Date(timeIntervalSince1970: 0), new = Date()
        #expect(DuplicateFinder.keeperOrder([("/d/Report copy.pdf", old), ("/d/Report.pdf", new)]).first == "/d/Report.pdf")
        #expect(DuplicateFinder.keeperOrder([("/d/b.pdf", new), ("/d/a.pdf", old)]).first == "/d/a.pdf")
        #expect(DuplicateFinder.keeperOrder([("/d/deep/x.pdf", nil), ("/d/x.pdf", nil)]).first == "/d/x.pdf")
        for name in ["Report copy.pdf", "Report copy 2.pdf", "Report (1).pdf", "Report 2.pdf", "Report-1.pdf"] {
            #expect(DuplicateFinder.looksLikeCopy("/d/" + name), "\(name)")
        }
        for name in ["Report.pdf", "IMG_1234.jpg", "2025 Taxes.pdf", "Copywriting.pdf"] {
            #expect(!DuplicateFinder.looksLikeCopy("/d/" + name), "\(name)")
        }
    }
}
