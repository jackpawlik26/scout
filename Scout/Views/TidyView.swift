import ScoutCore
import SwiftUI

/// Tidy Folder's plan: which loose files go into which folder. Untick a group to leave it.
struct TidyView: View {
    let browser: BrowserModel
    let moves: [Tidy.Move]
    @Environment(\.dismiss) private var dismiss
    @State private var skipped: Set<String> = []

    private var chosen: [Tidy.Move] { moves.filter { !skipped.contains($0.folder) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Tidy “\(browser.title)”").font(.headline)
                Text("Loose files move into folders by kind. Folders, hidden files and anything still downloading stay put. ⌘Z puts everything back.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Tidy.summary(moves), id: \.folder) { group in
                        row(group.folder, count: group.count)
                    }
                }
            }
            .frame(maxHeight: 320)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.03)))
            HStack {
                Text("\(chosen.count) of \(moves.count) files").foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Tidy \(chosen.count) Files") {
                    browser.applyTidy(chosen)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(chosen.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 500)
        .onWindowKey(.escape) {
            dismiss()
            return true
        }
    }

    private func row(_ folder: String, count: Int) -> some View {
        let names = moves.filter { $0.folder == folder }.map(\.item.name)
        return HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { !skipped.contains(folder) },
                                     set: { if $0 { skipped.remove(folder) } else { skipped.insert(folder) } }))
                .toggleStyle(.checkbox).labelsHidden()
            Image(systemName: "folder.fill").foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text(folder).font(.system(size: 13, weight: .medium))
                Text(names.prefix(3).joined(separator: ", ") + (names.count > 3 ? ", …" : ""))
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
            }
            Spacer()
            Text("\(count)").monospacedDigit().foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
    }
}
