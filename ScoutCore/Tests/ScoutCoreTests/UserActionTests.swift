import Foundation
import Testing
@testable import ScoutCore

@Suite struct UserActionTests {
    @Test func findsScriptsItCanRun() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "actions-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        func write(_ name: String, executable: Bool = false) throws {
            let url = folder.appending(path: name)
            try "echo hi".write(to: url, atomically: true, encoding: .utf8)
            if executable { try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.filePath) }
        }
        try write("resize-for-web.sh")
        try write("Make Thumbnails.py")
        try write("clean_up", executable: true)
        try write("notes.txt") // not a script
        try write(".hidden.sh")
        try FileManager.default.createDirectory(at: folder.appending(path: "sub.sh"), withIntermediateDirectories: true)

        let actions = UserAction.load(from: folder)
        #expect(actions.map(\.title) == ["Clean Up", "Make Thumbnails", "Resize for Web"])
        let resize = try #require(actions.first { $0.title == "Resize for Web" })
        #expect(resize.launchPath == "/bin/zsh")
        #expect(resize.arguments(for: ["/a b.png"]) == [resize.url.filePath, "/a b.png"])
        #expect(resize.url.lastPathComponent == "resize-for-web.sh")
        let python = try #require(actions.first { $0.title == "Make Thumbnails" })
        #expect(python.launchPath == "/usr/bin/env")
        #expect(python.arguments(for: []).first == "python3")
        let binary = try #require(actions.first { $0.title == "Clean Up" })
        #expect(binary.arguments(for: ["/x"]) == ["/x"])
    }

    @Test func missingFolderIsEmpty() {
        #expect(UserAction.load(from: URL(filePath: "/nonexistent-\(UUID().uuidString)")).isEmpty)
    }
}
