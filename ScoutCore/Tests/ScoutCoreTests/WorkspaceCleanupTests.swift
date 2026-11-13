import Foundation
import Testing
@testable import ScoutCore

@Suite struct WorkspaceTests {
    @Test func addsWithoutDuplicates() {
        var ws = Workspace(name: "Taxes", paths: ["/a", "/b", "/a"])
        #expect(ws.paths == ["/a", "/b"])
        ws.add(["/b", "/c"])
        #expect(ws.paths == ["/a", "/b", "/c"])
        ws.remove(["/a"])
        #expect(ws.paths == ["/b", "/c"])
    }

    @Test func roundTripsThroughStore() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "ws-\(UUID().uuidString).json")
        let list = [Workspace(name: "IB Recruiting", symbol: "briefcase", paths: ["/x/ib-prep"])]
        try ScoutStore.saveWorkspaces(list, to: url)
        #expect(ScoutStore.loadWorkspaces(from: url) == list)
    }
}

@Suite struct CleanupTests {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "Cleanup-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func make(_ name: String, bytes: Int = 10, age days: Double = 0) throws -> URL {
        let url = root.appending(path: name)
        try Data(count: bytes).write(to: url)
        let date = Date().addingTimeInterval(-days * 86_400)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.filePath)
        return url
    }

    @Test func findsInstallers() throws {
        _ = try make("Comet.dmg", bytes: 5_000)
        _ = try make("Tool.pkg", bytes: 3_000)
        _ = try make("notes.pdf")
        let found = CleanupScanner.scanInstallers(in: root)
        #expect(found.map(\.name) == ["Comet.dmg", "Tool.pkg"])
    }

    @Test func oldDownloadsUseAddedAndModified() throws {
        // A fresh file is never "old", whatever its modification date, because it was
        // just added to this folder. So only check that new files are excluded.
        _ = try make("old-looking.pdf", age: 400)
        _ = try make("Comet.dmg", age: 400)
        let found = CleanupScanner.scanOldDownloads(in: root, sizeOf: { _ in 0 })
        #expect(found.isEmpty)
        // Pretend it's a year from now: both age out, but installers are excluded.
        let later = CleanupScanner.scanOldDownloads(in: root, now: Date().addingTimeInterval(365 * 86_400), sizeOf: { _ in 0 })
        #expect(later.map(\.name) == ["old-looking.pdf"])
    }

    @Test func devCachesNeedToExistAndBeBig() throws {
        let fakeHome = root.filePath
        let derived = root.appending(path: "Library/Developer/Xcode/DerivedData")
        try FileManager.default.createDirectory(at: derived, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appending(path: ".npm/_cacache"), withIntermediateDirectories: true)
        let found = CleanupScanner.scanDevCaches(home: fakeHome) { url in
            url.filePath.hasSuffix("DerivedData") ? 2_000_000_000 : 100 // npm cache is near-empty
        }
        #expect(found.map(\.name) == ["Xcode build data (DerivedData)"])
        #expect(found.first?.detail == "~/Library/Developer/Xcode/DerivedData")
    }
}
