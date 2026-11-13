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

@Suite struct MoreCleanupTests {
    let home = FileManager.default.temporaryDirectory.appending(path: "Home-\(UUID().uuidString)")

    private func make(_ path: String, bytes: Int = 10, modified: Date? = nil) throws {
        let url = home.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: bytes).write(to: url)
        if let modified {
            try FileManager.default.setAttributes([.modificationDate: modified, .creationDate: modified], ofItemAtPath: url.filePath)
        }
    }

    @Test func findsOldNodeModulesOnly() throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let old = Date(timeIntervalSinceNow: -400 * 86_400)
        try make("code/old-app/package.json", modified: old)
        try make("code/old-app/node_modules/x/index.js", bytes: 2_000_000)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: home.appending(path: "code/old-app/node_modules").filePath)
        try make("code/new-app/package.json")
        try make("code/new-app/node_modules/x/index.js", bytes: 2_000_000)
        let items = CleanupScanner.scanOldNodeModules(home: home.filePath) { FileCopier.totalBytes($0) }
        #expect(items.map(\.name) == ["old-app/node_modules"])
    }

    @Test func findsOldScreenRecordings() throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let old = Date(timeIntervalSinceNow: -60 * 86_400)
        try make("Desktop/Screen Recording 2026-08-01 at 10.00.mov", bytes: 500, modified: old)
        try make("Desktop/Screen Recording today.mov", bytes: 500)
        try make("Movies/Holiday.mov", bytes: 500, modified: old)
        #expect(CleanupScanner.scanScreenRecordings(home: home.filePath).map(\.name) == ["Screen Recording 2026-08-01 at 10.00.mov"])
    }

    @Test func findsLeftoversOfUninstalledApps() throws {
        defer { try? FileManager.default.removeItem(at: home) }
        try make("Library/Containers/com.gone.App/Data/big.bin", bytes: 2_000_000)
        try make("Library/Containers/com.here.App/Data/big.bin", bytes: 2_000_000)
        try make("Library/Containers/com.apple.Notes/Data/big.bin", bytes: 2_000_000)
        try make("Library/Caches/com.gone.App/cache.bin", bytes: 3_000_000)
        try make("Library/Caches/SomeFolder/cache.bin", bytes: 3_000_000)
        let items = CleanupScanner.scanAppLeftovers(home: home.filePath, isInstalled: { $0 == "com.here.App" }) {
            FileCopier.totalBytes($0)
        }
        #expect(items.map(\.name) == ["com.gone.App", "com.gone.App"])
        #expect(items.first?.detail?.hasPrefix("Cache") == true)
    }
}
