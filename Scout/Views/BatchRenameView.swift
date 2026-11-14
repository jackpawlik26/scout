import ScoutCore
import SwiftUI

/// Rename Items: a list of steps that run in order (replace, add, new name, remove, case,
/// trim), with {variables}, regular expressions, presets and a live preview. ⌘Z undoes it.
struct BatchRenameView: View {
    let browser: BrowserModel
    let items: [FileItem]
    @Environment(\.dismiss) private var dismiss
    @State private var pipeline = RenamePipeline()
    @State private var imageSizes: [URL: (Int, Int)] = [:]
    @State private var isSavingPreset = false
    @State private var presetName = ""
    @State private var showsVariables = false

    private var contexts: [RenameContext] {
        items.map { item in
            let size = imageSizes[item.url]
            return RenameContext(name: item.name, parent: item.url.deletingLastPathComponent().lastPathComponent,
                                 created: item.dateCreated, modified: item.dateModified, added: item.dateAdded,
                                 width: size?.0, height: size?.1)
        }
    }

    private var otherNames: Set<String> {
        let renaming = Set(items.map(\.id))
        return Set(browser.items.filter { !renaming.contains($0.id) }.map(\.name))
    }

    var body: some View {
        let others = otherNames
        let names = BatchRename.newNames(for: contexts, pipeline: pipeline, existing: others)
        let problems = BatchRename.problems(old: items.map(\.name), new: names, existing: others)
        let changed = zip(items, names).filter { $0.name != $1 }.count
        VStack(alignment: .leading, spacing: 16) {
            header
            steps
            options
            preview(names: names, problems: problems, changed: changed)
            footer(names: names, problems: problems, changed: changed)
        }
        .padding(22)
        .frame(width: 880)
        .onWindowKey(.escape) {
            dismiss()
            return true
        }
        .task(id: pipeline.needsImageSize) { await loadImageSizes() }
        .alert("Save Preset", isPresented: $isSavingPreset) {
            TextField("Name", text: $presetName)
            Button("Save") {
                let name = presetName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { browser.services.saveRenamePreset(name: name, pipeline: pipeline) }
                presetName = ""
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) { presetName = "" }
        } message: {
            Text("Save these steps to use again from the Presets menu. A preset with the same name is updated.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Text("Rename \(items.count) Items").font(.ui(18, .medium)).foregroundStyle(Color.textStrong)
            Spacer()
            Menu {
                Section("Built In") {
                    ForEach(RenamePreset.builtIn) { preset in
                        Button(preset.name) { load(preset) }
                    }
                }
                let saved = browser.services.renamePresets
                if !saved.isEmpty {
                    Section("Yours") {
                        ForEach(saved) { preset in
                            Button(preset.name) { load(preset) }
                        }
                    }
                }
                Divider()
                Button("Save as Preset…") { isSavingPreset = true }
                if !saved.isEmpty {
                    Menu("Delete Preset") {
                        ForEach(saved) { preset in
                            Button(preset.name, role: .destructive) { browser.services.deleteRenamePreset(preset.id) }
                        }
                    }
                }
            } label: {
                Label("Presets", systemImage: "square.stack")
            }
            .fixedSize()
            IconButton(symbol: "arrow.counterclockwise", help: "Start over") { pipeline = RenamePipeline() }
        }
    }

    private func load(_ preset: RenamePreset) {
        var loaded = preset.pipeline
        // Fresh ids, so the same preset can be loaded twice without SwiftUI mixing up rows.
        loaded.steps = loaded.steps.map { var step = $0; step.id = UUID(); return step }
        pipeline = loaded
    }

    // MARK: - Steps

    private var steps: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(spacing: 0) {
                ForEach(Array(pipeline.steps.enumerated()), id: \.element.id) { index, step in
                    if index > 0 { Divider().padding(.leading, 40) }
                    StepRow(step: binding(for: step.id), number: index + 1,
                            canMoveUp: index > 0, canMoveDown: index < pipeline.steps.count - 1,
                            move: { offset in moveStep(at: index, by: offset) },
                            duplicate: { duplicateStep(at: index) },
                            remove: pipeline.steps.count > 1 ? { pipeline.steps.remove(at: index) } : nil)
                }
            }
            .background(RaisedFill(shape: RoundedRectangle(cornerRadius: 10)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.hairline))

            Menu {
                ForEach(RenameStep.Kind.allCases) { kind in
                    Button { pipeline.steps.append(RenameStep(kind)) } label: { Label(kind.title, systemImage: kind.symbol) }
                }
            } label: {
                Label("Add Step", systemImage: "plus")
            }
            .fixedSize()
        }
    }

    private func binding(for id: UUID) -> Binding<RenameStep> {
        Binding(
            get: { pipeline.steps.first { $0.id == id } ?? RenameStep(.trimSpaces) },
            set: { new in
                if let index = pipeline.steps.firstIndex(where: { $0.id == id }) { pipeline.steps[index] = new }
            })
    }

    private func moveStep(at index: Int, by offset: Int) {
        let target = index + offset
        guard pipeline.steps.indices.contains(target) else { return }
        pipeline.steps.swapAt(index, target)
    }

    private func duplicateStep(at index: Int) {
        var copy = pipeline.steps[index]
        copy.id = UUID()
        pipeline.steps.insert(copy, at: index + 1)
    }

    // MARK: - Options

    private var options: some View {
        HStack(spacing: 16) {
            Toggle("Include extension", isOn: $pipeline.includeExtension).fixedSize()
                .help("Let the steps change “.JPG” too")
            Toggle("Number clashes", isOn: $pipeline.autoNumberConflicts).fixedSize()
                .help("When two new names are the same, or a name is taken, add 2, 3… instead of stopping")
            Spacer()
            HStack(spacing: 6) {
                Text("{n} starts at").foregroundStyle(Color.textSubtle).fixedSize()
                TextField("1", value: $pipeline.startNumber, format: .number).frame(width: 44)
                Text("by").foregroundStyle(Color.textSubtle).fixedSize()
                TextField("1", value: $pipeline.numberStep, format: .number).frame(width: 36)
                Picker("", selection: $pipeline.digits) {
                    Text("Auto digits").tag(0)
                    ForEach(1...5, id: \.self) { Text("\($0) digit\($0 == 1 ? "" : "s")").tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
            .textFieldStyle(.roundedBorder)
        }
        .toggleStyle(.checkbox)
        .font(.ui(13))
        .foregroundStyle(Color.textDefault)
    }

    // MARK: - Preview

    private func preview(names: [String], problems: [Int: String], changed: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Preview").font(.ui(12, .medium)).foregroundStyle(Color.textSubtle)
                Spacer()
                Text("\(changed) change\(changed == 1 ? "" : "s") · \(items.count - changed) unchanged")
                    .font(.ui(12)).foregroundStyle(Color.textSubtle)
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        let newName = names[index]
                        let same = newName == item.name
                        HStack(spacing: 8) {
                            FileIconView(item: item, size: 16)
                            Text(item.name).lineLimit(1).truncationMode(.middle)
                                .foregroundStyle(Color.textSubtle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "arrow.right").font(.system(size: 11, weight: .light))
                                .foregroundStyle(Color.textSubtle)
                            Group {
                                if let problem = problems[index] {
                                    Text("\(newName)  ·  \(problem)").foregroundStyle(.red)
                                } else {
                                    Text(newName)
                                        .foregroundStyle(same ? Color.textSubtle : Color.textStrong)
                                        .fontWeight(same ? .regular : .medium)
                                }
                            }
                            .lineLimit(1).truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.ui(13))
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(index.isMultiple(of: 2) ? Color.bgSelected : .clear)
                    }
                }
            }
            .frame(height: min(CGFloat(items.count) * 28, 224))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.hairline))
        }
    }

    // MARK: - Footer

    private func footer(names: [String], problems: [Int: String], changed: Int) -> some View {
        HStack(spacing: 10) {
            Button { showsVariables.toggle() } label: { Label("Variables", systemImage: "curlybraces") }
                .popover(isPresented: $showsVariables, arrowEdge: .bottom) { VariablesHelp() }
            if let problem = pipeline.problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.ui(13))
            } else if !problems.isEmpty {
                Label("\(problems.count) name\(problems.count == 1 ? "" : "s") can’t be used", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red).font(.ui(13))
            } else {
                Text(changed == 0 ? "Nothing changes yet." : "⌘Z undoes it.")
                    .foregroundStyle(Color.textSubtle).font(.ui(13))
            }
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Rename") {
                browser.applyBatchRename(Array(zip(items, names)).map { (item: $0, newName: $1) })
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(changed == 0 || !problems.isEmpty || pipeline.problem != nil)
        }
    }

    /// {width} and {height} need each image opened, so only when a step uses them.
    private func loadImageSizes() async {
        guard pipeline.needsImageSize, imageSizes.isEmpty else { return }
        let urls = items.map(\.url)
        let sizes = await Task.detached(priority: .userInitiated) { () -> [URL: (Int, Int)] in
            var found: [URL: (Int, Int)] = [:]
            for url in urls { if let size = RenameContext.imageSize(url) { found[url] = (size.width, size.height) } }
            return found
        }.value
        imageSizes = sizes
    }
}

/// One step: what it does, its settings, and move / duplicate / delete.
private struct StepRow: View {
    @Binding var step: RenameStep
    let number: Int
    let canMoveUp: Bool
    let canMoveDown: Bool
    let move: (Int) -> Void
    let duplicate: () -> Void
    let remove: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)").font(.ui(12)).foregroundStyle(Color.textSubtle).frame(width: 18)
            Picker("", selection: $step.kind) {
                ForEach(RenameStep.Kind.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .frame(width: 160)
            settings
            Menu {
                Button("Move Up") { move(-1) }.disabled(!canMoveUp)
                Button("Move Down") { move(1) }.disabled(!canMoveDown)
                Button("Duplicate") { duplicate() }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            Button { remove?() } label: { Image(systemName: "trash").font(.system(size: 12, weight: .light)) }
                .buttonStyle(.borderless)
                .disabled(remove == nil)
                .help("Remove this step")
        }
        .textFieldStyle(.roundedBorder)
        .font(.ui(13))
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder private var settings: some View {
        switch step.kind {
        case .replace:
            HStack(spacing: 8) {
                TextField(step.regex ? "Pattern, e.g. IMG_(\\d+)" : "Find", text: $step.text)
                Image(systemName: "arrow.right").font(.system(size: 11, weight: .light)).foregroundStyle(Color.textSubtle)
                VariableField(placeholder: step.regex ? "Replace, e.g. Photo $1" : "Replace with (empty removes it)",
                              text: $step.replacement)
                Toggle("Regex", isOn: $step.regex).toggleStyle(.checkbox).fixedSize()
                Toggle("Aa", isOn: $step.matchCase).toggleStyle(.checkbox).fixedSize().help("Match case")
            }
        case .add:
            HStack(spacing: 8) {
                VariableField(placeholder: "Text to add, e.g. -{n}", text: $step.text)
                Picker("", selection: $step.position) {
                    Text("At start").tag(RenameStep.Position.start)
                    Text("At end").tag(RenameStep.Position.end)
                }
                .labelsHidden().fixedSize()
            }
        case .newName:
            VariableField(placeholder: "e.g. Trip {n} or {created:yyyy-MM-dd} {name}", text: $step.text)
        case .removeCharacters:
            HStack(spacing: 8) {
                TextField("1", value: $step.count, format: .number).frame(width: 50)
                Text("characters from the").foregroundStyle(Color.textSubtle)
                Picker("", selection: $step.position) {
                    Text("start").tag(RenameStep.Position.start)
                    Text("end").tag(RenameStep.Position.end)
                }
                .labelsHidden().fixedSize()
                Spacer(minLength: 0)
            }
        case .changeCase:
            HStack {
                Picker("", selection: $step.caseStyle) {
                    ForEach(RenameStep.CaseStyle.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden().fixedSize()
                Spacer(minLength: 0)
            }
        case .trimSpaces:
            Text("Trims the ends and squeezes repeated spaces.").foregroundStyle(Color.textSubtle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A text field with a {} menu that inserts a variable.
private struct VariableField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 4) {
            TextField(placeholder, text: $text)
            Menu {
                ForEach(RenameVariable.allCases, id: \.self) { variable in
                    Button("\(variable.title)   \(variable.token)") { text += variable.token }
                }
            } label: {
                Image(systemName: "curlybraces")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Insert a variable")
        }
    }
}

/// The Variables popover: every variable and how to format dates.
private struct VariablesHelp: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Variables").font(.ui(14, .medium)).foregroundStyle(Color.textStrong)
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                ForEach(RenameVariable.allCases, id: \.self) { variable in
                    GridRow {
                        Text(variable.title).foregroundStyle(Color.textDefault)
                        Text(variable.token).font(.system(size: 12, design: .monospaced)).foregroundStyle(Color.textStrong)
                            .textSelection(.enabled)
                    }
                }
            }
            .font(.ui(13))
            Divider()
            Text("Dates take a format: {created:yyyy-MM-dd}, {now:HHmm}. Names and extensions take :lower or :upper, like {ext:lower}. With Regex on, $1, $2… insert matched groups. Type {{ or }} for a brace.")
                .font(.ui(12)).foregroundStyle(Color.textSubtle)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 340)
    }
}
