import AppKit
import ScoutCore
import SwiftUI

/// Triage (⌥⌘J): a folder's loose files one at a time, with a big preview and one key
/// to file, trash, rename or skip each. Suggestions come from where similar files went
/// before (File History); "Always do this" turns one into a rule for new downloads.
struct TriageView: View {
    let window: BrowserWindowModel
    let browser: BrowserModel
    let folder: String
    @Environment(AppServices.self) private var services

    @State private var items: [FileItem] = []
    @State private var currentPath: String?
    @State private var loaded = false
    @State private var watcher: DirectoryWatcher?
    @State private var alwaysDo = false
    @State private var renameText: String?
    @State private var note: String?
    @FocusState private var isFocused: Bool
    @FocusState private var isRenameFocused: Bool

    private var index: Int? {
        guard let currentPath else { return items.isEmpty ? nil : 0 }
        return items.firstIndex { $0.path == currentPath } ?? (items.isEmpty ? nil : 0)
    }
    private var current: FileItem? { index.map { items[$0] } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !loaded {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                } else if let current {
                    fileCard(current)
                } else {
                    doneCard
                }
                rulesCard
            }
            .padding(16)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onKeyPress(phases: .down) { press in handleKey(press) }
        .task { await load() }
        .onAppear {
            isFocused = true
            watcher = DirectoryWatcher(url: URL.folder(folder)) { Task { await load() } }
        }
        .onDisappear { watcher = nil }
    }

    // MARK: - The file

    private func fileCard(_ item: FileItem) -> some View {
        let suggestions = suggestions(for: item)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("\((index ?? 0) + 1) of \(items.count) in \(FileManager.default.displayName(atPath: folder))")
                    .foregroundStyle(Color.textSubtle)
                Spacer()
                if let note {
                    Label(note, systemImage: "checkmark.circle.fill").foregroundStyle(.green).lineLimit(1)
                }
            }
            .font(.ui(12))

            HStack(alignment: .top, spacing: 16) {
                PreviewPane(item: item)
                    .id(item.id)
                    .frame(width: 340)
                    .frame(maxHeight: 420)

                VStack(alignment: .leading, spacing: 12) {
                    if let renameText {
                        TextField("Name", text: Binding(get: { renameText }, set: { self.renameText = $0 }))
                            .textFieldStyle(.roundedBorder)
                            .focused($isRenameFocused)
                            .onSubmit { finishRename(item) }
                            .onExitCommand { self.renameText = nil; isFocused = true }
                            .onAppear { isRenameFocused = true }
                    } else {
                        Text(item.name).font(.ui(17, .medium)).lineLimit(3).textSelection(.enabled)
                    }
                    Text(details(item)).font(.ui(12)).foregroundStyle(Color.textSubtle)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("File it in").font(.ui(12).weight(.medium)).foregroundStyle(Color.textSubtle)
                        if suggestions.isEmpty {
                            Text("No suggestions yet. Scout learns from where you put things.")
                                .font(.ui(12)).foregroundStyle(Color.textSubtle)
                        }
                        ForEach(Array(suggestions.enumerated()), id: \.element.id) { position, suggestion in
                            suggestionRow(suggestion, key: position + 1, item: item)
                        }
                        Button { chooseFolder(item) } label: {
                            KeyLabel(key: "O", title: "Other folder…", detail: nil)
                        }
                        .buttonStyle(.plain)
                        Toggle("Always do this for files like it", isOn: $alwaysDo)
                            .font(.ui(12))
                            .help(alwaysDoHelp(item))
                            .disabled(TriageRule.suggested(name: item.name, site: item.source?.site, destination: "/") == nil)
                    }

                    Divider()
                    HStack(spacing: 8) {
                        Button("Rename (R)") { startRename(item) }
                        Button("Trash (⌫)") { trash(item) }
                        Button("Skip (→)") { step(1) }
                        Button("←") { step(-1) }.help("Back")
                            .disabled((index ?? 0) == 0)
                    }
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .background(RaisedFill(shape: RoundedRectangle(cornerRadius: 12)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.hairline))
    }

    private func suggestionRow(_ suggestion: DestinationSuggestion, key: Int, item: FileItem) -> some View {
        Button { file(item, into: suggestion.folder) } label: {
            KeyLabel(key: key == 1 ? "\(key) ↵" : "\(key)",
                     title: PathDisplay.display(suggestion.folder, home: services.homePath),
                     detail: suggestion.reason)
        }
        .buttonStyle(.plain)
    }

    private var doneCard: some View {
        Card(spacing: 8) {
            Label("Nothing left to triage", systemImage: "checkmark.seal").font(.ui(16, .medium))
            Text("\(FileManager.default.displayName(atPath: folder)) has no loose files. New downloads show up here as they arrive.")
                .foregroundStyle(Color.textSubtle)
            Button("Open \(FileManager.default.displayName(atPath: folder))") { browser.go(to: .folder(folder)) }
                .padding(.top, 4)
        }
    }

    // MARK: - Rules

    private var rulesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Rules").font(.ui(12).weight(.medium)).foregroundStyle(Color.textSubtle).padding(.horizontal, 4)
            Card(spacing: 8) {
                if services.triageRules.isEmpty {
                    Text("Turn on “Always do this” when you file something, and Scout files new downloads like it on its own while it’s open. You can undo each one in History.")
                        .font(.ui(12)).foregroundStyle(Color.textSubtle)
                }
                ForEach(services.triageRules) { rule in
                    HStack(spacing: 10) {
                        Toggle("", isOn: Binding(get: { rule.isEnabled }, set: { on in
                            var changed = rule
                            changed.isEnabled = on
                            services.updateTriageRule(changed)
                        }))
                        .toggleStyle(.switch).controlSize(.mini).labelsHidden()
                        VStack(alignment: .leading, spacing: 1) {
                            Text(rule.summary).lineLimit(1)
                            Text("→ " + PathDisplay.display(rule.destination, home: services.homePath))
                                .font(.ui(12)).foregroundStyle(Color.textSubtle).lineLimit(1).truncationMode(.head)
                        }
                        Spacer()
                        Button { services.removeTriageRule(rule.id) } label: { Image(systemName: "trash") }
                            .buttonStyle(.plain).foregroundStyle(Color.textSubtle)
                            .help("Delete this rule")
                    }
                    .font(.ui(13))
                }
            }
        }
    }

    // MARK: - Keys

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        guard renameText == nil, let item = current else { return .ignored }
        let suggestions = suggestions(for: item)
        if press.modifiers.contains(.command) {
            if press.key == .delete { trash(item); return .handled }
            return .ignored
        }
        switch press.key {
        case .return:
            if let first = suggestions.first { file(item, into: first.folder) }
            return .handled
        case .delete: trash(item); return .handled
        case .rightArrow: step(1); return .handled
        case .leftArrow: step(-1); return .handled
        default: break
        }
        switch press.characters.lowercased() {
        case "1", "2", "3":
            let n = Int(press.characters)! - 1
            if suggestions.indices.contains(n) { file(item, into: suggestions[n].folder) }
            return .handled
        case "s": step(1); return .handled
        case "r": startRename(item); return .handled
        case "o": chooseFolder(item); return .handled
        case "a": alwaysDo.toggle(); return .handled
        default: return .ignored
        }
    }

    // MARK: - Actions

    private func load() async {
        let url = URL.folder(folder)
        let listed = (try? await LocalFileSource().contents(of: url, includeHidden: false)) ?? []
        let inbox = Triage.inbox(listed)
        // Stay on the same file; if it left (filed, trashed), move on to the one that took its place.
        if let currentPath, !inbox.contains(where: { $0.path == currentPath }) {
            let oldIndex = items.firstIndex { $0.path == currentPath } ?? 0
            let next = inbox.indices.contains(oldIndex) ? inbox[oldIndex] : inbox.last
            self.currentPath = next?.path
            alwaysDo = false
        } else if currentPath == nil {
            currentPath = inbox.first?.path
        }
        items = inbox
        loaded = true
    }

    private func step(_ delta: Int) {
        guard let index, !items.isEmpty else { return }
        let next = min(max(index + delta, 0), items.count - 1)
        currentPath = items[next].path
        alwaysDo = false
        renameText = nil
    }

    private func file(_ item: FileItem, into destination: String) {
        let folderURL = URL.folder(destination)
        if !FileManager.default.fileExists(atPath: destination) {
            do {
                try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            } catch {
                browser.alertMessage = error.localizedDescription
                return
            }
        }
        if alwaysDo, let rule = TriageRule.suggested(name: item.name, site: item.source?.site, destination: destination) {
            services.addTriageRule(rule)
            note = "New rule: \(rule.summary)"
        } else {
            note = "Filed in \(FileManager.default.displayName(atPath: destination))"
        }
        browser.transfer([item.url], into: folderURL, move: true)
        isFocused = true
    }

    private func trash(_ item: FileItem) {
        if browser.trash([item.url]) > 0 { note = "Moved “\(item.name)” to the Trash" }
        isFocused = true
    }

    private func chooseFolder(_ item: FileItem) {
        window.destinationRequest = DestinationRequest(urls: [item.url], copy: false)
        window.isPaletteOpen = true
    }

    private func startRename(_ item: FileItem) {
        renameText = item.name
    }

    private func finishRename(_ item: FileItem) {
        guard let name = renameText?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty, name != item.name else {
            renameText = nil
            isFocused = true
            return
        }
        currentPath = item.url.deletingLastPathComponent().appending(path: name).filePath
        browser.rename(item, to: name)
        renameText = nil
        isFocused = true
    }

    // MARK: - Suggestions and details

    /// Learned folders first; then Tidy's folder for this kind, so there's always somewhere to go.
    private func suggestions(for item: FileItem) -> [DestinationSuggestion] {
        let fm = FileManager.default
        var list = DestinationLearner.suggestions(name: item.name, site: item.source?.site,
                                                  history: services.fileHistory, excluding: folder, limit: 5)
            .filter { fm.fileExists(atPath: $0.folder) }
        let tidy = folder + "/" + Tidy.folderName(for: item)
        if list.count < 3, !list.contains(where: { $0.folder == tidy }) {
            list.append(DestinationSuggestion(folder: tidy, score: 0,
                                              reason: fm.fileExists(atPath: tidy) ? "Tidy’s folder for this kind"
                                                  : "Tidy’s folder for this kind (Scout makes it)"))
        }
        return Array(list.prefix(3))
    }

    private func details(_ item: FileItem) -> String {
        var parts = [item.kind, Format.size(item)]
        if let added = item.dateAdded { parts.append("added " + added.formatted(.relative(presentation: .named))) }
        if let source = item.source?.summary { parts.append("from " + source) }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func alwaysDoHelp(_ item: FileItem) -> String {
        guard let rule = TriageRule.suggested(name: item.name, site: item.source?.site, destination: "/") else {
            return "This file has no type or download source to make a rule from."
        }
        return "New \(rule.summary) will go to the folder you pick, on their own (A)"
    }
}

/// "1  ~/School/FIN320  ·  6 PDF files from canvas.depaul.edu went here"
private struct KeyLabel: View {
    let key: String
    let title: String
    let detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(key)
                .font(.ui(11, .medium)).monospacedDigit()
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).lineLimit(1).truncationMode(.head)
                if let detail { Text(detail).font(.ui(11)).foregroundStyle(Color.textSubtle).lineLimit(1) }
            }
            Spacer(minLength: 0)
        }
        .font(.ui(13))
        .padding(.vertical, 4).padding(.horizontal, 6)
        .contentShape(Rectangle())
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.04)))
    }
}
