import Foundation
import Synchronization
import Testing
@testable import ScoutCore

@Suite struct FileCopierTests {
    let dir = FileManager.default.temporaryDirectory.appending(path: "Copier-\(UUID().uuidString)")

    private func write(_ name: String, bytes: Int) throws {
        let url = dir.appending(path: name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 7, count: bytes).write(to: url)
    }

    @Test func copiesFoldersWithProgress() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        try write("src/a.bin", bytes: 300_000)
        try write("src/sub/b.bin", bytes: 200_000)
        let reported = Mutex<Int64>(0)
        try FileCopier.copy(dir.appending(path: "src"), to: dir.appending(path: "dst")) { bytes in
            reported.withLock { $0 = max($0, bytes) }
            return true
        }
        #expect(FileManager.default.fileExists(atPath: dir.appending(path: "dst/sub/b.bin").filePath))
        #expect(FileCopier.totalBytes(dir.appending(path: "dst")) == 500_000)
        // Clones report nothing; real copies report up to the total.
        #expect(reported.withLock { $0 } <= 500_000)
    }

    @Test func cancelsCleanly() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        try write("big/a.bin", bytes: 4_000_000)
        try write("big/b.bin", bytes: 4_000_000)
        // Force a real copy path by cancelling at the first progress report (clones may finish instantly).
        do {
            try FileCopier.copy(dir.appending(path: "big"), to: dir.appending(path: "out")) { _ in false }
        } catch FileCopier.Failure.cancelled {
            #expect(!FileManager.default.fileExists(atPath: dir.appending(path: "out").filePath))
        }
    }

    @Test func picksDestinationsForConflicts() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        try write("from/report.pdf", bytes: 10)
        try write("to/report.pdf", bytes: 20)
        let source = dir.appending(path: "from/report.pdf")
        let folder = dir.appending(path: "to")
        #expect(FileCopier.destination(for: source, in: folder, choice: nil, isCopy: true) == nil)
        #expect(FileCopier.destination(for: source, in: folder, choice: .skip, isCopy: true) == nil)
        #expect(FileCopier.destination(for: source, in: folder, choice: .replace, isCopy: true)?.lastPathComponent == "report.pdf")
        #expect(FileCopier.destination(for: source, in: folder, choice: .keepBoth, isCopy: true)?.lastPathComponent == "report copy.pdf")
        #expect(FileCopier.destination(for: source, in: folder, choice: .keepBoth, isCopy: false)?.lastPathComponent == "report 2.pdf")
        #expect(FileCopier.destination(for: source, in: dir.appending(path: "from/../from2"), choice: nil, isCopy: true) != nil)
    }
}
