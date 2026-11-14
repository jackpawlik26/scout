import Foundation
import Testing
@testable import ScoutCore

@Suite struct FileHistoryTests {
    func entry(_ action: FileAction, _ pairs: [(String, String)], undoes: UUID? = nil,
               daysAgo: Double = 0) -> FileHistoryEntry {
        FileHistoryEntry(date: Date(timeIntervalSinceNow: -daysAgo * 86_400), action: action,
                         changes: pairs.map { FileChange(from: $0.0, to: $0.1) }, undoes: undoes)
    }

    @Test func followsAFileThroughLaterMoves() {
        var history = FileHistory()
        history.append(entry(.move, [("/u/Downloads/Q3-model.xlsx", "/u/Work/Q3-model.xlsx")]))
        history.append(entry(.rename, [("/u/Work/Q3-model.xlsx", "/u/Work/Q3 model final.xlsx")]))
        // The folder it's in moves: the file goes with it.
        history.append(entry(.move, [("/u/Work", "/u/Archive/2026/Work")]))
        // Unrelated, and a copy of it (copies leave the original where it is).
        history.append(entry(.move, [("/u/Other.pdf", "/u/Docs/Other.pdf")]))
        history.append(entry(.copy, [("/u/Archive/2026/Work/Q3 model final.xlsx", "/u/Desktop/Q3 model final.xlsx")]))

        #expect(history.currentPath(of: "/u/Work/Q3-model.xlsx", after: 0) == "/u/Archive/2026/Work/Q3 model final.xlsx")

        let found = history.matches("q3 MODEL")
        // Newest first: the copy, the rename, then the first move.
        #expect(found.map(\.entry.action) == [.copy, .rename, .move])
        #expect(found.last?.change.to == "/u/Work/Q3-model.xlsx")
        #expect(found.last?.currentPath == "/u/Archive/2026/Work/Q3 model final.xlsx")
        #expect(history.matches("").isEmpty)
        #expect(history.matches("nothing-like-it").isEmpty)
    }

    @Test func folderNamesMatchOnlyTheLastPart() {
        var history = FileHistory()
        history.append(entry(.move, [("/u/Taxes/a.pdf", "/u/Done/a.pdf")]))
        #expect(history.matches("taxes").isEmpty)
        #expect(history.matches("a.pdf").count == 1)
    }

    @Test func undoRules() {
        var history = FileHistory()
        let move = entry(.move, [("/u/a.txt", "/u/Docs/a.txt")])
        history.append(move)
        var disk: Set<String> = ["/u/Docs/a.txt"]
        #expect(history.undoBlocker(for: move, exists: disk.contains) == nil)

        // Something new took its old place.
        disk.insert("/u/a.txt")
        #expect(history.undoBlocker(for: move, exists: disk.contains) != nil)
        // It moved away since.
        disk = []
        #expect(history.undoBlocker(for: move, exists: disk.contains) != nil)

        // Once undone, it can't be undone again; undoing the undo reads as a redo.
        disk = ["/u/Docs/a.txt"]
        let undo = entry(.undo, [("/u/Docs/a.txt", "/u/a.txt")], undoes: move.id)
        history.append(undo)
        #expect(history.undoBlocker(for: move, exists: disk.contains) == "Already undone.")
        #expect(history.describedAction(of: undo).action == .undo)
        #expect(!history.describedAction(of: undo).isRedo)
        let redo = entry(.undo, [("/u/a.txt", "/u/Docs/a.txt")], undoes: undo.id)
        history.append(redo)
        #expect(history.describedAction(of: redo).action == .move)
        #expect(history.describedAction(of: redo).isRedo)
        // After the redo the file is back in Docs.
        #expect(history.currentPath(of: "/u/Docs/a.txt", after: 0) == "/u/Docs/a.txt")
    }

    @Test func caseOnlyRenameCanBeUndone() {
        let rename = entry(.rename, [("/u/notes.txt", "/u/Notes.txt")])
        let history = FileHistory(entries: [rename])
        // On a case-insensitive disk both names "exist".
        #expect(history.undoBlocker(for: rename, exists: { _ in true }) == nil)
    }

    @Test func copiesUndoWhileAnyCopyRemains() {
        let copy = entry(.copy, [("/u/a", "/v/a"), ("/u/b", "/v/b")])
        let history = FileHistory(entries: [copy])
        #expect(history.undoBlocker(for: copy, exists: { $0 == "/v/b" }) == nil)
        #expect(history.undoBlocker(for: copy, exists: { _ in false }) != nil)
    }

    @Test func pruning() {
        var history = FileHistory()
        history.append(entry(.trash, [("/u/old", "/u/.Trash/old")], daysAgo: 400))
        history.append(entry(.trash, [("/u/new", "/u/.Trash/new")], daysAgo: 1))
        let dropped = history.prune()
        #expect(dropped)
        #expect(history.entries.count == 1)
        let droppedAgain = history.prune()
        #expect(!droppedAgain)
    }

    @Test func savesOneLinePerEntry() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "history-\(UUID().uuidString)/file-history.jsonl")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        #expect(FileHistoryStore.load(from: url).entries.isEmpty)

        let first = entry(.move, [("/u/a b.txt", "/u/Docs/a b.txt")])
        let second = entry(.trash, [("/u/c", "/u/.Trash/c")])
        try FileHistoryStore.append(first, to: url)
        try FileHistoryStore.append(second, to: url)
        // A half-written last line (the app quit mid-write) is skipped, not fatal.
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"id\":".utf8))
        try handle.close()

        let loaded = FileHistoryStore.load(from: url)
        #expect(loaded.entries.map(\.id) == [first.id, second.id])
        #expect(loaded.entries[0].changes == first.changes)
        #expect(abs(loaded.entries[0].date.timeIntervalSince(first.date)) < 1)

        try FileHistoryStore.save(FileHistory(entries: [second]), to: url)
        #expect(FileHistoryStore.load(from: url).entries.map(\.id) == [second.id])
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("\"/u/.Trash/c\""))
    }
}
