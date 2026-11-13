import ScoutCore
import SwiftUI

/// "“report.pdf” already exists": Replace, Keep Both, Skip or Stop, comparing the two.
struct ConflictView: View {
    let prompt: ConflictPrompt
    @State private var applyToAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                FileIconView(item: prompt.incoming, size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text("“\(prompt.incoming.name)” already exists in “\(prompt.folderName)”.")
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Replace it with the one you’re \(prompt.isMove ? "moving" : "copying"), keep both, or skip it? A replaced item goes to the Trash.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(spacing: 6) {
                compareRow("Already there", prompt.existing, newer: isNewer(prompt.existing, than: prompt.incoming))
                compareRow(prompt.isMove ? "Moving" : "Copying", prompt.incoming, newer: isNewer(prompt.incoming, than: prompt.existing))
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
            if prompt.remaining > 1 {
                Toggle("Do this for all \(prompt.remaining) clashes", isOn: $applyToAll).toggleStyle(.checkbox)
            }
            HStack {
                Button("Stop") { prompt.answer(nil) }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Skip") { answer(.skip) }
                Button("Replace") { answer(.replace) }
                Button("Keep Both") { answer(.keepBoth) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private func answer(_ choice: ConflictChoice) {
        prompt.answer(ConflictAnswer(choice: choice, applyToAll: applyToAll))
    }

    private func isNewer(_ a: FileItem, than b: FileItem) -> Bool {
        guard let da = a.dateModified, let db = b.dateModified else { return false }
        return da > db.addingTimeInterval(1)
    }

    private func compareRow(_ label: String, _ item: FileItem, newer: Bool) -> some View {
        HStack(spacing: 8) {
            Text(label).foregroundStyle(.secondary).frame(width: 92, alignment: .leading)
            Text(item.isNavigable ? "Folder" : Format.size(item)).monospacedDigit()
            Text("·").foregroundStyle(.tertiary)
            Text(Format.date(item.dateModified))
            if newer {
                Text("NEWER").font(.system(size: 9, weight: .bold)).tracking(0.5)
                    .padding(.horizontal, 5).padding(.vertical, 1.5)
                    .background(Capsule().fill(Color.accentColor.opacity(0.18)))
                    .foregroundStyle(Color.accentColor)
            }
            Spacer()
        }
        .font(.system(size: 12))
    }
}

/// Floating progress for copies and moves that take more than a moment.
struct TransferOverlay: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let slow = services.transfers.filter { context.date.timeIntervalSince($0.started) > 0.4 }
            VStack(spacing: 8) {
                ForEach(slow) { TransferCard(transfer: $0) }
            }
        }
        .padding(.bottom, 40)
        .animation(.snappy(duration: 0.2), value: services.transfers.map(\.id))
    }
}

private struct TransferCard: View {
    let transfer: Transfer

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.on.doc").font(.system(size: 16)).foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 5) {
                Text(transfer.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                if let fraction = transfer.fraction {
                    ProgressView(value: fraction).progressViewStyle(.linear)
                } else {
                    ProgressView().progressViewStyle(.linear)
                }
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    .monospacedDigit()
            }
            IconButton(symbol: "xmark", help: "Cancel") { transfer.cancel() }
        }
        .padding(12)
        .frame(width: 380)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.2), radius: 16, y: 6)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var detail: String {
        let current = transfer.current
        guard transfer.totalBytes > 0 else { return current }
        let bytes = "\(Format.bytes(transfer.done)) of \(Format.bytes(transfer.totalBytes))"
        return current.isEmpty ? bytes : "\(bytes) · \(current)"
    }
}
