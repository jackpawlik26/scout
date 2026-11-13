import Foundation
import Observation
import ScoutCore
import Synchronization

/// One running copy or move. Progress is written from a background thread and
/// read by the progress card a few times a second.
nonisolated final class Transfer: Identifiable, @unchecked Sendable {
    let id = UUID()
    let title: String
    let totalBytes: Int64
    let started = Date()
    private let state = Mutex((done: Int64(0), current: "", cancelled: false))

    init(title: String, totalBytes: Int64) {
        self.title = title
        self.totalBytes = totalBytes
    }

    var done: Int64 { state.withLock { $0.done } }
    var current: String { state.withLock { $0.current } }
    var isCancelled: Bool { state.withLock { $0.cancelled } }
    var fraction: Double? { totalBytes > 0 ? min(1, Double(done) / Double(totalBytes)) : nil }

    func cancel() { state.withLock { $0.cancelled = true } }
    func set(done: Int64) { state.withLock { $0.done = done } }
    func set(current: String) { state.withLock { $0.current = current } }
}

/// The conflict dialog's question, answered through `answer`.
struct ConflictPrompt: Identifiable {
    let id = UUID()
    let incoming: FileItem
    let existing: FileItem
    let folderName: String
    let isMove: Bool
    /// Conflicts left including this one (shows "Apply to all").
    let remaining: Int
    let answer: (ConflictAnswer?) -> Void
}

struct ConflictAnswer {
    var choice: ConflictChoice
    var applyToAll: Bool
}
