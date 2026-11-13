import Foundation
import Testing
@testable import ScoutCore

@Suite struct ScoutLinkTests {
    @Test func parsesOpenLinks() {
        #expect(ScoutLink(url: URL(string: "scout://open?path=%7E/Downloads")!) == .open(path: "~/Downloads", newTab: false))
        #expect(ScoutLink(url: URL(string: "scout://open?path=/tmp&newTab=1")!) == .open(path: "/tmp", newTab: true))
        #expect(ScoutLink(url: URL(string: "SCOUT://Reveal?path=/a%20b")!) == .open(path: "/a b", newTab: false))
    }

    @Test func parsesJumpLinks() {
        #expect(ScoutLink(url: URL(string: "scout://jump")!) == .jump(query: nil))
        #expect(ScoutLink(url: URL(string: "scout://jump?query=taxes")!) == .jump(query: "taxes"))
    }

    @Test func rejectsBadLinks() {
        #expect(ScoutLink(url: URL(string: "scout://open")!) == nil)
        #expect(ScoutLink(url: URL(string: "scout://explode?path=/")!) == nil)
        #expect(ScoutLink(url: URL(string: "https://open?path=/")!) == nil)
    }

    @Test func roundTrips() {
        #expect(ScoutLink(url: URL(string: "scout://open?path=/tmp&split=1")!) == .open(path: "/tmp", newTab: false, split: true))
        #expect(ScoutLink(url: URL(string: "scout://cleanup")!) == .cleanup)
        #expect(ScoutLink(url: URL(string: "scout://workspace")!) == nil)
        for link in [ScoutLink.open(path: "/Users/jack/My Files & Stuff", newTab: true), .jump(query: "ib prep"), .jump(query: nil),
                     .workspace(name: "IB Recruiting"), .cleanup, .open(path: "/x", newTab: false, split: true)] {
            #expect(ScoutLink(url: link.url) == link)
        }
    }
}

@Suite struct ScoutStoreTests {
    let dir = FileManager.default.temporaryDirectory.appending(path: "ScoutStore-\(UUID().uuidString)")

    @Test func historyRoundTripsAsISO8601() throws {
        var log = FrecencyLog()
        log.record("/a", at: Date(timeIntervalSince1970: 1_800_000_000))
        let url = dir.appending(path: "history.json")
        try ScoutStore.saveHistory(log, to: url)
        #expect(try String(contentsOf: url, encoding: .utf8).contains("2027-01-15T08:00:00Z"))
        #expect(ScoutStore.loadHistory(from: url) == log)
    }

    @Test func readsOldHistoryFormat() throws {
        var log = FrecencyLog()
        log.record("/a", at: Date(timeIntervalSince1970: 1_800_000_000))
        let url = dir.appending(path: "old.json")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try JSONEncoder().encode(log).write(to: url)
        #expect(ScoutStore.loadHistory(from: url) == log)
    }

    @Test func foldersRoundTrip() throws {
        let folders = ["/Users/j/a", "/Users/j/b c"].map { IndexedFolder(path: $0, home: "/Users/j") }
        let url = dir.appending(path: "folders.txt")
        try ScoutStore.saveFolders(folders, to: url)
        #expect(ScoutStore.loadFolders(home: "/Users/j", from: url) == folders)
        #expect(ScoutStore.loadFolders(home: "/Users/j", from: dir.appending(path: "missing.txt")) == nil)
    }
}
