import ScoutCore
import SwiftUI

/// Rename many items at once, with a live before → after preview. ⌘Z undoes it.
struct BatchRenameView: View {
    let browser: BrowserModel
    let items: [FileItem]
    @Environment(\.dismiss) private var dismiss
    @State private var rules = RenameRules()

    private var newNames: [String] { BatchRename.newNames(for: items.map(\.name), rules: rules) }

    private var problems: [Int: String] {
        let renaming = Set(items.map(\.id))
        let others = Set(browser.items.filter { !renaming.contains($0.id) }.map(\.name))
        return BatchRename.problems(old: items.map(\.name), new: newNames, existing: others)
    }

    var body: some View {
        let names = newNames
        let problems = problems
        let changed = zip(items, names).filter { $0.name != $1 }.count
        VStack(alignment: .leading, spacing: 14) {
            Text("Rename \(items.count) Items").font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    label("Find")
                    TextField("Text to find", text: $rules.find).textFieldStyle(.roundedBorder)
                    label("Replace with")
                    TextField("Nothing", text: $rules.replace).textFieldStyle(.roundedBorder)
                }
                GridRow {
                    label("Add before")
                    TextField("Prefix", text: $rules.prefix).textFieldStyle(.roundedBorder)
                    label("Add after")
                    TextField("Suffix", text: $rules.suffix).textFieldStyle(.roundedBorder)
                }
                GridRow {
                    label("Numbers")
                    Picker("", selection: $rules.numbering) {
                        ForEach(RenameRules.Numbering.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    if rules.numbering == .replace {
                        label("New name")
                        TextField("e.g. Ski Trip", text: $rules.baseName).textFieldStyle(.roundedBorder)
                    } else if rules.numbering == .append {
                        label("Start at")
                        TextField("1", value: $rules.startNumber, format: .number).textFieldStyle(.roundedBorder).frame(width: 70)
                    }
                }
                GridRow {
                    label("Letters")
                    Picker("", selection: $rules.caseChange) {
                        ForEach(RenameRules.CaseChange.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    Toggle("Match case", isOn: $rules.matchCase).toggleStyle(.checkbox)
                    Toggle("Keep extensions", isOn: $rules.keepExtension).toggleStyle(.checkbox)
                }
            }

            preview(names: names, problems: problems)

            HStack {
                if !problems.isEmpty {
                    Label("\(problems.count) name\(problems.count == 1 ? "" : "s") can’t be used", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red).font(.callout)
                } else {
                    Text(changed == 0 ? "Nothing changes yet." : "\(changed) of \(items.count) will change. ⌘Z undoes it.")
                        .foregroundStyle(.secondary).font(.callout)
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Rename") {
                    browser.applyBatchRename(Array(zip(items, names)).map { (item: $0, newName: $1) })
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(changed == 0 || !problems.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 640)
        .onWindowKey(.escape) {
            dismiss()
            return true
        }
    }

    private func label(_ text: String) -> some View {
        Text(text).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
    }

    private func preview(names: [String], problems: [Int: String]) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    let newName = names[index]
                    HStack(spacing: 8) {
                        FileIconView(item: item, size: 16)
                        Text(item.name).lineLimit(1).truncationMode(.middle)
                            .foregroundStyle(newName == item.name ? .primary : .secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "arrow.right").font(.caption).foregroundStyle(.tertiary)
                        Group {
                            if let problem = problems[index] {
                                Text("\(newName)  ·  \(problem)").foregroundStyle(.red)
                            } else {
                                Text(newName).foregroundStyle(newName == item.name ? .secondary : .primary)
                                    .fontWeight(newName == item.name ? .regular : .medium)
                            }
                        }
                        .lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.system(size: 12))
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(index.isMultiple(of: 2) ? Color.primary.opacity(0.03) : .clear)
                }
            }
        }
        .frame(height: min(CGFloat(items.count) * 26, 260))
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.hairline))
    }
}
