import AppKit
import ScoutCore
import SwiftUI

/// Compare Folders (split view ▸ View ▸ Compare Folders…): what's different between the two
/// panes, including subfolders, and a one-way sync. Nothing is deleted: replaced files and
/// mirrored extras go to the Trash, and History can undo the copies.
struct CompareView: View {
    let window: BrowserWindowModel
    let request: CompareRequest
    @Environment(\.dismiss) private var dismiss

    @State private var entries: [FolderCompare.Entry] = []
    @State private var isComparing = true
    @State private var checkContents = false
    @State private var showSame = false
    @State private var mirror = false
    @State private var confirming: Bool?   // leftToRight
    @State private var isSyncing = false
    @State private var result: String?

    private var shown: [FolderCompare.Entry] { showSame ? entries : entries.filter { $0.status != .same } }
    private var differences: Int { entries.filter { $0.status != .same }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            list
            footer
        }
        .padding(22)
        .frame(width: 860, height: 600)
        .task(id: checkContents) { await compare() }
        .alert(confirmTitle, isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } })) {
            Button("Sync") { if let direction = confirming { sync(leftToRight: direction) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(confirmMessage)
        }
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Compare Folders").font(.ui(18, .medium)).foregroundStyle(Color.textStrong)
                Spacer()
                if isComparing || isSyncing { ProgressView().controlSize(.small) }
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            HStack(spacing: 8) {
                folderLabel(request.left, side: "Left")
                Image(systemName: "arrow.left.arrow.right").foregroundStyle(Color.textSubtle)
                folderLabel(request.right, side: "Right")
            }
            HStack(spacing: 16) {
                Text(isComparing ? "Comparing…" : differences == 0 ? "These folders match." : "\(differences) difference\(differences == 1 ? "" : "s")")
                    .foregroundStyle(Color.textSubtle)
                Spacer()
                Toggle("Show matching files", isOn: $showSame)
                Toggle("Check contents", isOn: $checkContents)
                    .help("Read files whose dates differ but sizes match, to see if they really differ (slower)")
            }
            .font(.ui(12))
            if let result {
                Label(result, systemImage: "checkmark.circle.fill").font(.ui(12)).foregroundStyle(.green)
            }
        }
    }

    private func folderLabel(_ url: URL, side: String) -> some View {
        HStack(spacing: 6) {
            Image(nsImage: IconCache.icon(forPath: url.filePath)).resizable().frame(width: 16, height: 16)
            Text("\(side):").foregroundStyle(Color.textSubtle)
            Text(url.lastPathComponent)
        }
        .font(.ui(13))
        .help(url.filePath)
    }

    private var list: some View {
        Table(shown) {
            TableColumn("") { entry in
                Image(systemName: Self.symbol(entry.status)).foregroundStyle(Self.color(entry.status))
                    .help(entry.status.title)
            }
            .width(22)
            TableColumn("File") { entry in
                Text(entry.path).lineLimit(1).truncationMode(.middle).help(entry.path)
            }
            TableColumn("Left") { entry in info(entry.left, newer: entry.status == .leftNewer) }
                .width(min: 120, ideal: 150)
            TableColumn("Right") { entry in info(entry.right, newer: entry.status == .rightNewer) }
                .width(min: 120, ideal: 150)
        }
        .overlay {
            if !isComparing, shown.isEmpty {
                Text(entries.isEmpty ? "Both folders are empty." : "No differences.").foregroundStyle(Color.textSubtle)
            }
        }
    }

    private func info(_ file: FolderCompare.FileInfo?, newer: Bool) -> some View {
        Group {
            if let file {
                Text("\(file.modified.formatted(date: .abbreviated, time: .shortened)) · \(Format.bytes(file.size))")
                    .fontWeight(newer ? .medium : .regular)
            } else {
                Text("—").foregroundStyle(Color.textSubtle)
            }
        }
        .font(.ui(12))
        .lineLimit(1)
    }

    private var footer: some View {
        let toRight = FolderCompare.plan(entries, leftToRight: true, mirror: mirror)
        let toLeft = FolderCompare.plan(entries, leftToRight: false, mirror: mirror)
        return HStack(spacing: 10) {
            Toggle("Also move extra files on the receiving side to the Trash", isOn: $mirror)
                .font(.ui(12))
                .help("Make the receiving folder match exactly. Files only it has go to the Trash, not away for good.")
            Spacer()
            Button("← Copy to Left (\(toLeft.copy.count + toLeft.trash.count))") { confirming = false }
                .disabled(toLeft.isEmpty || isComparing || isSyncing)
            Button("Copy to Right → (\(toRight.copy.count + toRight.trash.count))") { confirming = true }
                .disabled(toRight.isEmpty || isComparing || isSyncing)
                .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - Confirm

    private var pendingPlan: FolderCompare.SyncPlan? {
        confirming.map { FolderCompare.plan(entries, leftToRight: $0, mirror: mirror) }
    }

    private var confirmTitle: String {
        guard let confirming else { return "" }
        let target = confirming ? request.right : request.left
        return "Sync into “\(target.lastPathComponent)”?"
    }

    private var confirmMessage: String {
        guard let plan = pendingPlan else { return "" }
        var lines: [String] = []
        let added = plan.copy.count - plan.replace.count
        if added > 0 { lines.append("Copy \(added) new file\(added == 1 ? "" : "s").") }
        if !plan.replace.isEmpty {
            lines.append("Replace \(plan.replace.count) older or different file\(plan.replace.count == 1 ? "" : "s") (the old ones go to the Trash).")
        }
        if !plan.trash.isEmpty {
            lines.append("Move \(plan.trash.count) extra file\(plan.trash.count == 1 ? "" : "s") to the Trash.")
        }
        lines.append("Files that are newer on the receiving side are left alone.")
        return lines.joined(separator: "\n")
    }

    // MARK: - Work

    private func compare() async {
        isComparing = true
        let (left, right, check) = (request.left, request.right, checkContents)
        entries = await Task.detached(priority: .userInitiated) {
            FolderCompare.compare(left, right, checkContents: check)
        }.value
        isComparing = false
    }

    private func sync(leftToRight: Bool) {
        let plan = FolderCompare.plan(entries, leftToRight: leftToRight, mirror: mirror)
        let source = leftToRight ? request.left : request.right
        let target = leftToRight ? request.right : request.left
        let services = window.services
        let transfer = Transfer(title: "Syncing into “\(target.lastPathComponent)”",
                                totalBytes: plan.copy.reduce(0) { total, path in
                                    total + ((leftToRight ? entryInfo(path)?.left : entryInfo(path)?.right)?.size ?? 0)
                                })
        isSyncing = true
        services.begin(transfer)
        Task {
            let outcome = await Self.run(plan, from: source, to: target, transfer: transfer)
            services.end(transfer)
            services.recordFiles(.copy, outcome.copied)
            services.recordFiles(.trash, outcome.trashed)
            for pane in window.panes { Task { await pane.current.reload() } }
            isSyncing = false
            result = "Copied \(outcome.copied.count), moved \(outcome.trashed.count) to the Trash"
                + (outcome.errors.isEmpty ? "." : ". \(outcome.errors.count) couldn’t be done: \(outcome.errors.first!)")
            await compare()
        }
    }

    private func entryInfo(_ path: String) -> FolderCompare.Entry? { entries.first { $0.path == path } }

    struct Outcome: Sendable {
        var copied: [(URL, URL)] = []
        var trashed: [(URL, URL)] = []
        var errors: [String] = []
    }

    @concurrent nonisolated private static func run(_ plan: FolderCompare.SyncPlan, from source: URL, to target: URL,
                                                    transfer: Transfer) async -> Outcome {
        let fm = FileManager.default
        var outcome = Outcome()
        let replacing = Set(plan.replace)
        var done: Int64 = 0
        for path in plan.copy {
            if transfer.isCancelled { break }
            transfer.set(current: (path as NSString).lastPathComponent)
            let from = source.appending(path: path)
            let to = target.appending(path: path)
            do {
                try fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
                if replacing.contains(path), fm.fileExists(atPath: to.filePath) {
                    var trashed: NSURL?
                    try fm.trashItem(at: to, resultingItemURL: &trashed)
                    if let trashed { outcome.trashed.append((to, trashed as URL)) }
                }
                let base = done
                try FileCopier.copy(from, to: to) { bytes in
                    transfer.set(done: base + bytes)
                    return !transfer.isCancelled
                }
                done += FileCopier.totalBytes(to)
                outcome.copied.append((from, to))
            } catch FileCopier.Failure.cancelled {
                break
            } catch {
                outcome.errors.append("\(path): \(error.localizedDescription)")
            }
        }
        for path in plan.trash where !transfer.isCancelled {
            let url = target.appending(path: path)
            var trashed: NSURL?
            do {
                try fm.trashItem(at: url, resultingItemURL: &trashed)
                if let trashed { outcome.trashed.append((url, trashed as URL)) }
            } catch {
                outcome.errors.append("\(path): \(error.localizedDescription)")
            }
        }
        return outcome
    }

    // MARK: - Look

    static func symbol(_ status: FolderCompare.Status) -> String {
        switch status {
        case .onlyLeft: "arrow.left.circle"
        case .onlyRight: "arrow.right.circle"
        case .leftNewer: "chevron.left.circle.fill"
        case .rightNewer: "chevron.right.circle.fill"
        case .different: "exclamationmark.circle"
        case .same: "checkmark.circle"
        }
    }

    static func color(_ status: FolderCompare.Status) -> Color {
        switch status {
        case .onlyLeft, .onlyRight: .accentColor
        case .leftNewer, .rightNewer: .orange
        case .different: .red
        case .same: .secondary
        }
    }
}
