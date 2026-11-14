import AppKit
import ScoutCore
import SwiftUI

/// ⌘K: find any folder or file.
///
/// Folders come from Scout's own index (instant, ranked by how often you use them);
/// files come from Spotlight, matching names and what's inside documents.
struct CommandPalette: View {
    @Bindable var window: BrowserWindowModel
    @Environment(AppServices.self) private var services

    @State private var query = ""
    @State private var scope: SearchScope = .all
    @State private var kind: KindFilter?
    @State private var date: DateFilter?
    @State private var inThisFolder = false
    /// "Ask Scout": the date range the model found, and what you typed before it rewrote the query.
    @State private var after: Date?
    @State private var before: Date?
    @State private var askedFrom: String?
    @State private var isAsking = false
    @State private var askError: String?

    @State private var folders: [RankedFolder] = []
    /// Menu commands and your scripts, read when the palette opens (so "can it run now?" is current).
    @State private var commands: [PaletteCommand] = []
    @State private var files: [RankedHit] = []
    @State private var isSearchingFiles = false
    @State private var spotlight: SpotlightSearch?
    @State private var selectedIndex = 0
    /// Move to… / Copy to…: the palette picks a folder for these items instead of opening things.
    @State private var destination: DestinationRequest?
    @State private var destinationError: String?
    @FocusState private var isFieldFocused: Bool

    private var spec: SearchSpec {
        SearchSpec(query: query, scope: scope, kind: kind, date: date,
                   withinPath: inThisFolder ? window.current.location.filePath : nil, after: after, before: before)
    }

    /// Offer "Ask Scout" for descriptions ("the lease I signed last spring").
    private var canAsk: Bool {
        destination == nil && askedFrom == nil && SearchPlan.looksLikeQuestion(query) && OnDeviceAI.isAvailable
    }

    /// Typing ">" first lists only commands, like other command palettes.
    private var isCommandMode: Bool { destination == nil && query.hasPrefix(">") }

    private var rows: [PaletteItem] {
        if isCommandMode { return matchingCommands(String(query.dropFirst()), limit: 60) }
        let folderLimit = scope == .folders ? 50 : (files.isEmpty ? 30 : 6)
        let commandRows = scope == .all && destination == nil ? matchingCommands(query, limit: 4, strict: true) : []
        return folders.prefix(folderLimit).map(PaletteItem.folder) + commandRows + files.map(PaletteItem.file)
    }

    /// Commands whose name matches. `strict` (mixed in with folders and files): the typed text
    /// must appear in the name, so commands don't crowd out what you're looking for.
    private func matchingCommands(_ text: String, limit: Int, strict: Bool = false) -> [PaletteItem] {
        let q = text.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return strict ? [] : commands.filter(\.isEnabled).prefix(limit).map { .command($0, []) } }
        if strict, q.count < 3 { return [] }
        return commands
            .compactMap { command -> (PaletteCommand, FuzzyMatch)? in
                if strict, command.title.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) == nil { return nil }
                return FuzzyMatcher.match(q, in: command.title).map { (command, $0) }
            }
            .sorted { a, b in
                a.0.isEnabled != b.0.isEnabled ? a.0.isEnabled : a.1.score > b.1.score
            }
            .prefix(limit)
            .map { .command($0.0, $0.1.indices) }
    }

    private var selected: PaletteItem? {
        rows.indices.contains(selectedIndex) ? rows[selectedIndex] : nil
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.12)
                .ignoresSafeArea()
                .onTapGesture { close(cancelled: true) }

            VStack(spacing: 0) {
                if let destination {
                    DestinationHeader(request: destination, error: destinationError) { copy in
                        self.destination?.copy = copy
                    }
                }
                searchField
                if canAsk || isAsking || askedFrom != nil || askError != nil { askBar }
                if destination == nil {
                    FilterBar(scope: $scope, kind: $kind, date: $date, inThisFolder: $inThisFolder,
                              folderName: window.current.location.lastPathComponent)
                }
                Divider()
                resultsList
                Divider()
                footer
            }
            .frame(width: 680)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
            .shadow(color: .black.opacity(0.25), radius: 30, y: 12)
            .padding(.top, 64)
        }
        .onAppear {
            commands = MenuCommands.all() + UserAction.load().map { action in
                PaletteCommand(id: "action:\(action.id)", title: "Run “\(action.title)”", detail: "Your action",
                               shortcut: "", symbol: "terminal", isEnabled: true) { [window] in
                    window.current.run(action)
                }
            } + [PaletteCommand(id: "action:folder", title: "Open Actions Folder", detail: "Your actions",
                                shortcut: "", symbol: "folder.badge.gearshape", isEnabled: true) { [window] in
                    window.current.openActionsFolder()
                }]
            if !window.paletteInitialQuery.isEmpty { query = window.paletteInitialQuery }
            if let initialScope = window.paletteInitialScope { scope = initialScope }
            window.paletteInitialQuery = ""
            window.paletteInitialScope = nil
            if let request = window.destinationRequest {
                destination = request
                scope = .folders
            }
            isFieldFocused = true
        }
        .onExitCommand { close(cancelled: true) }
        // Esc, even while typing (the text field would otherwise swallow it).
        .onWindowKey(.escape) {
            close(cancelled: true)
            return true
        }
        .onChange(of: window.paletteInitialQuery) { _, newQuery in
            guard !newQuery.isEmpty else { return }
            query = newQuery
            window.paletteInitialQuery = ""
        }
        .task(id: spec) { await search(spec) }
        .onChange(of: query) {
            destinationError = nil
            askError = nil
        }
        .onChange(of: services.isIndexing) { Task { await searchFolders(spec) } }
    }

    // MARK: - Pieces

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Color.textSubtle)
            TextField(placeholder, text: $query)
                .textFieldStyle(.plain)
                .font(.ui(16))
                .focused($isFieldFocused)
                .onKeyPress(.downArrow) { move(1); return .handled }
                .onKeyPress(.upArrow) { move(-1); return .handled }
                .onKeyPress(.tab) {
                    if destination != nil {
                        destination?.copy.toggle()
                        return .handled
                    }
                    let all = SearchScope.allCases
                    scope = all[(all.firstIndex(of: scope)! + 1) % all.count]
                    return .handled
                }
                .onKeyPress(.return, phases: .down) { press in
                    if press.modifiers.contains(.option), canAsk {
                        ask()
                        return .handled
                    }
                    activate(modifiers: press.modifiers)
                    return .handled
                }
            if isSearchingFiles || services.isIndexing {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    /// "✨ Ask Scout" while you type a description; then what it understood, with a way back.
    private var askBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles").foregroundStyle(Color.accentColor)
            if isAsking {
                Text("Working out what you mean…").foregroundStyle(Color.textSubtle)
                ProgressView().controlSize(.small)
            } else if let askError {
                Text(askError).foregroundStyle(Color.textSubtle)
            } else if let askedFrom {
                Text("Searching for \(spec.summary)").lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 8)
                Button("Use “\(askedFrom)” instead") { undoAsk() }
                    .buttonStyle(.link)
                    .lineLimit(1)
            } else {
                Button { ask() } label: {
                    Text("Ask Scout what you mean").fontWeight(.medium)
                }
                .buttonStyle(.link)
                Text("⌥↵ · on this Mac").foregroundStyle(Color.textSubtle)
            }
            Spacer(minLength: 0)
        }
        .font(.ui(12))
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    /// Asks the on-device model what the description means, then searches for that.
    private func ask() {
        let original = query
        isAsking = true
        askError = nil
        Task {
            defer { isAsking = false }
            guard let plan = try? await OnDeviceAI.searchPlan(for: original), let planned = plan.spec() else {
                askError = "Couldn’t work that out. Try fewer, more specific words."
                return
            }
            guard query == original else { return } // you kept typing
            askedFrom = original
            scope = planned.scope
            kind = planned.kind
            after = planned.after
            before = planned.before
            query = planned.query
        }
    }

    private func undoAsk() {
        guard let original = askedFrom else { return }
        askedFrom = nil
        after = nil
        before = nil
        kind = nil
        scope = .all
        query = original
    }

    private var placeholder: String {
        if destination != nil { return "Type a folder name or path…" }
        return switch scope {
        case .all: "Find a folder or file…"
        case .folders: "Jump to a folder…"
        case .files: "Find a file by name or contents…"
        }
    }

    @ViewBuilder private var resultsList: some View {
        let rows = rows
        if rows.isEmpty {
            Text(emptyMessage)
                .font(.ui(13))
                .foregroundStyle(Color.textSubtle)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            if let header = sectionHeader(at: index, in: rows) {
                                Text(header)
                                    .font(.ui(12).weight(.medium))
                                    .foregroundStyle(Color.textSubtle)
                                    .padding(.horizontal, 10)
                                    .padding(.top, index == 0 ? 2 : 10)
                                    .padding(.bottom, 2)
                            }
                            PaletteRow(item: row, home: services.homePath, isSelected: index == selectedIndex)
                                .id(row.id)
                                .onTapGesture {
                                    selectedIndex = index
                                    activate(modifiers: NSEvent.modifierFlags.contains(.command) ? .command : [])
                                }
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 400)
                .onChange(of: selectedIndex) { _, index in
                    if rows.indices.contains(index) { proxy.scrollTo(rows[index].id) }
                }
            }
        }
    }

    private var emptyMessage: String {
        if destination != nil, spec.isEmpty { return "Type to find a folder." }
        if spec.isEmpty {
            return scope == .files ? "Type to search files, or pick a kind or date above." : "Folders you open will show up here."
        }
        if isSearchingFiles || services.isIndexing { return "Searching…" }
        if scope != .folders && !spec.includesSpotlight { return "Keep typing to search files…" }
        return "No matches."
    }

    private func sectionHeader(at index: Int, in rows: [PaletteItem]) -> String? {
        let current = rows[index]
        if destination != nil, spec.isEmpty {
            let suggested = destinationSuggestions.count
            if index == 0 { return suggested > 0 ? "Suggested" : "Most Used" }
            return index == suggested ? "Most Used" : nil
        }
        if index > 0, rows[index - 1].section == current.section { return nil }
        switch current.section {
        case 2: return "Files"
        case 1: return "Commands"
        default: return spec.isEmpty ? "Most Used" : "Folders"
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            if let destination {
                let verb = destination.copy ? "copy" : "move"
                hint("↵", "\(verb) here")
                hint("⌘↵", "\(verb) and go there")
                hint("⇥", destination.copy ? "move instead" : "copy instead")
            } else if let selected, case .command = selected {
                hint("↵", "run")
            } else if let selected {
                if selected.isFile {
                    hint("↵", "open")
                    hint("⌘↵", "show in Scout")
                } else {
                    hint("↵", "go")
                    hint("⌘↵", "new tab")
                }
            }
            if destination == nil {
                if !spec.isEmpty { hint("⇧↵", "all results") }
                hint("⇥", "scope")
            }
            Spacer()
            Text(services.isIndexing ? "Indexing folders…" : "\(services.folders.count.formatted()) folders indexed")
        }
        .font(.ui(12))
        .foregroundStyle(Color.textSubtle)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key).fontWeight(.medium)
            Text(label)
        }
    }

    // MARK: - Searching

    private func search(_ spec: SearchSpec) async {
        selectedIndex = 0
        if isCommandMode {
            spotlight = nil
            folders = []
            files = []
            isSearchingFiles = false
            return
        }
        // Stop the last search now, so it can't deliver stale results (or keep Spotlight busy).
        spotlight = nil
        await searchFolders(spec)

        // Wait for a pause in typing before asking Spotlight.
        try? await Task.sleep(for: .milliseconds(140))
        guard !Task.isCancelled else { return }

        guard spec.includesSpotlight else {
            spotlight = nil
            files = []
            isSearchingFiles = false
            return
        }
        let home = services.homePath
        isSearchingFiles = true
        // Screenshots and images whose text matches (Spotlight reads text in only a few).
        let imageHits = spec.kind == nil || spec.kind == .images
            ? (spec.date == nil && spec.after == nil && spec.before == nil && spec.source == nil
                ? services.imageTextMatches(spec.nameQuery).filter { hit in
                    spec.withinPath.map { hit.path.hasPrefix($0 + "/") } ?? true
                } : [])
            : []
        spotlight = SpotlightSearch(spec: spec, home: home, live: false) { hits in
            // Ranked in the background. In "All", folders come from Scout's index instead.
            var fileHits = spec.scope == .all ? hits.filter { !$0.isFolder } : hits
            let found = Set(fileHits.map(\.path))
            fileHits += imageHits.filter { !found.contains($0.path) }
            return FileHitRanker.rank(fileHits, query: spec.nameQuery, home: home, limit: 40)
        } onResults: { ranked, finished in
            files = ranked
            if finished { isSearchingFiles = false }
        }
        if spotlight == nil { isSearchingFiles = false }
    }

    private func searchFolders(_ spec: SearchSpec) async {
        let home = services.homePath
        guard spec.scope != .files, !spec.hasFileFilters else {
            folders = []
            return
        }
        if spec.isEmpty {
            let ranked = FolderRanker.rank(query: "", folders: [], frecency: services.frecency, home: home)
            if destination != nil {
                let suggested = destinationSuggestions
                let taken = Set(suggested.map(\.folder.path))
                folders = suggested + ranked.filter { !taken.contains($0.folder.path) }
            } else {
                folders = ranked
            }
            return
        }
        let index = services.folders
        let frecency = services.frecency
        var ranked = await Task.detached(priority: .userInitiated) {
            FolderRanker.rank(query: spec.query, folders: index, frecency: frecency, home: home, limit: 60)
        }.value
        guard !Task.isCancelled else { return }

        if let within = spec.withinPath {
            ranked.removeAll { !$0.folder.path.hasPrefix(within + "/") }
        }
        // Typed a path like "~/Desktop" or "/usr/local"? Offer it first.
        if spec.query.hasPrefix("/") || spec.query.hasPrefix("~") {
            let path = PathCompletion.expandTilde(spec.query, home: home)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                let clean = URL.folder(path).filePath
                ranked.removeAll { $0.folder.path == clean }
                ranked.insert(RankedFolder(folder: IndexedFolder(path: clean, home: home), score: 1_000_000, nameIndices: []), at: 0)
            }
        }
        folders = ranked
    }

    // MARK: - Actions

    private func move(_ delta: Int) {
        let count = rows.count
        guard count > 0 else { return }
        selectedIndex = (selectedIndex + delta + count) % count
    }

    /// For Move to…: the other pane's folder, then recent destinations.
    private var destinationSuggestions: [RankedFolder] {
        guard let destination else { return [] }
        let home = services.homePath
        var paths: [String] = []
        if let other = window.otherPane?.current, other.isFolder { paths.append(other.location.filePath) }
        paths += RecentDestinations.paths
        let sources = Set(destination.urls.map { $0.deletingLastPathComponent().filePath })
        var seen = Set<String>()
        return paths.filter { path in
            // Moving into the folder they're already in does nothing.
            guard seen.insert(path).inserted, destination.copy || !(sources.count == 1 && sources.contains(path)) else { return false }
            return true
        }
        .prefix(5)
        .map { RankedFolder(folder: IndexedFolder(path: $0, home: home), score: 0, nameIndices: []) }
    }

    private func activate(modifiers: EventModifiers) {
        if let destination {
            guard let selected, !selected.isFile else { return }
            let folder = URL.folder(selected.path)
            guard FileManager.default.fileExists(atPath: selected.path) else {
                services.forget(selected.path)
                destinationError = "“\(selected.path)” no longer exists."
                return
            }
            if let error = window.finishMoveTo(folder, copy: destination.copy, follow: modifiers.contains(.command)) {
                destinationError = error
            } else {
                close()
            }
            return
        }
        if modifiers.contains(.shift) {
            showAllResults()
            return
        }
        guard let selected else { return }
        if case .command(let command, _) = selected {
            guard command.isEnabled else { return }
            close()
            command.run()
            return
        }
        let url = URL(filePath: selected.path)
        guard FileManager.default.fileExists(atPath: selected.path) else {
            services.forget(selected.path)
            window.current.alertMessage = "“\(selected.path)” no longer exists."
            close()
            return
        }
        let commandHeld = modifiers.contains(.command)
        if selected.isFile {
            if commandHeld { window.current.reveal(url) } else { NSWorkspace.shared.open(url) }
        } else {
            if commandHeld { window.newTab(at: url) } else { window.current.go(to: url) }
        }
        close()
    }

    private func showAllResults() {
        let spec = spec
        guard !spec.isEmpty else { return }
        window.current.showSearch(SavedSearch(name: spec.summary, spec: spec))
        close()
    }

    /// `cancelled`: dismissed without picking anything (Esc, clicking outside).
    private func close(cancelled: Bool = false) {
        spotlight = nil
        window.destinationRequest = nil
        window.isPaletteOpen = false
        services.paletteClosed(cancelled: cancelled)
    }
}

// MARK: - Rows

enum PaletteItem: Identifiable {
    case folder(RankedFolder)
    case file(RankedHit)
    /// A menu command or one of your scripts, with the letters of its name that matched.
    case command(PaletteCommand, [Int])

    var id: String {
        switch self {
        case .folder(let f): "d:" + f.folder.path
        case .file(let h): "f:" + h.hit.path
        case .command(let c, _): "c:" + c.id
        }
    }

    var path: String {
        switch self {
        case .folder(let f): f.folder.path
        case .file(let h): h.hit.path
        case .command: ""
        }
    }

    /// Folders, commands, files: for section headers.
    var section: Int {
        switch self {
        case .folder: 0
        case .command: 1
        case .file(let h): h.hit.isFolder ? 0 : 2
        }
    }

    /// Opens in an app rather than navigating (packages like .app count as files).
    var isFile: Bool {
        if case .file(let h) = self { return !h.hit.isFolder }
        return false
    }
}

private struct PaletteRow: View {
    let item: PaletteItem
    let home: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            if case .command(let command, _) = item {
                Image(systemName: command.symbol)
                    .font(.system(size: 14))
                    .frame(width: 22, height: 22)
            } else {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 22, height: 22)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(highlighted).lineLimit(1)
                Text(subtitle)
                    .font(.ui(12))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer()
            if case .command(let command, _) = item, !command.shortcut.isEmpty {
                Text(command.shortcut)
                    .font(.ui(12))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary))
            }
        }
        .opacity(isDisabledCommand ? 0.45 : 1)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .foregroundStyle(isSelected ? .white : .primary)
        .background(isSelected ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 9))
        .contentShape(Rectangle())
    }

    private var name: String {
        if case .command(let command, _) = item { return command.title }
        return (item.path as NSString).lastPathComponent
    }

    private var isDisabledCommand: Bool {
        if case .command(let command, _) = item { return !command.isEnabled }
        return false
    }

    private var icon: NSImage {
        switch item {
        case .folder(let f): IconCache.icon(forPath: f.folder.path)
        case .file(let h): IconCache.icon(forPath: h.hit.path, contentType: h.hit.contentType, isFolder: h.hit.isFolder)
        case .command: NSImage()
        }
    }

    private var subtitle: String {
        switch item {
        case .command(let command, _):
            return command.isEnabled ? command.detail : command.detail + " · not available here"
        case .folder(let f):
            return f.folder.displayPath
        case .file(let h):
            let parent = PathDisplay.display((h.hit.path as NSString).deletingLastPathComponent, home: home)
            if let date = h.hit.lastUsed ?? h.hit.modified {
                return "\(parent) · \(date.formatted(.relative(presentation: .named)))"
            }
            return parent
        }
    }

    /// The name with matched letters in bold.
    private var highlighted: AttributedString {
        let indices: [Int]
        switch item {
        case .folder(let f): indices = f.nameIndices
        case .file(let h): indices = h.nameIndices
        case .command(_, let matched): indices = matched
        }
        let matched = Set(indices)
        var output = AttributedString()
        for (index, character) in name.enumerated() {
            var piece = AttributedString(String(character))
            if matched.contains(index) {
                piece.font = .ui(13, .medium)
                if !isSelected { piece.foregroundColor = .accentColor }
            }
            output += piece
        }
        return output
    }
}

// MARK: - Move to… header

/// "Move 3 items to…" with a Move / Copy switch (⇥ flips it).
private struct DestinationHeader: View {
    let request: DestinationRequest
    let error: String?
    let setCopy: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: request.copy ? "doc.on.doc" : "arrow.right.doc.on.clipboard")
                    .foregroundStyle(Color.accentColor)
                Text("\(request.copy ? "Copy" : "Move") \(request.summary) to…")
                    .font(.ui(13).weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Chip(title: "Move", isOn: !request.copy) { setCopy(false) }
                Chip(title: "Copy", isOn: request.copy) { setCopy(true) }
            }
            if let error {
                Text(error).font(.ui(12)).foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
    }
}

// MARK: - Filters

private struct FilterBar: View {
    @Binding var scope: SearchScope
    @Binding var kind: KindFilter?
    @Binding var date: DateFilter?
    @Binding var inThisFolder: Bool
    let folderName: String

    var body: some View {
        HStack(spacing: 6) {
            ForEach(SearchScope.allCases, id: \.self) { option in
                Chip(title: option.title, isOn: scope == option) { scope = option }
            }
            Divider().frame(height: 16).padding(.horizontal, 2)

            Menu {
                Button("Any Kind") { kind = nil }
                Divider()
                ForEach(KindFilter.allCases, id: \.self) { option in
                    Button { kind = option; if scope == .folders { scope = .files } } label: {
                        Label(option.title, systemImage: option.symbol)
                    }
                }
            } label: {
                ChipLabel(title: kind?.title ?? "Any Kind", symbol: kind?.symbol ?? "square.grid.2x2", isOn: kind != nil)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .fixedSize()

            Menu {
                Button("Any Time") { date = nil }
                Divider()
                ForEach(DateFilter.allCases, id: \.self) { option in
                    Button(option.title) { date = option; if scope == .folders { scope = .files } }
                }
            } label: {
                ChipLabel(title: date?.title ?? "Any Time", symbol: "calendar", isOn: date != nil)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .fixedSize()

            Chip(title: "In \(folderName)", symbol: "folder", isOn: inThisFolder) { inThisFolder.toggle() }
                .help("Only search inside the folder this tab is showing")
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }
}

private struct Chip: View {
    let title: String
    var symbol: String?
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ChipLabel(title: title, symbol: symbol, isOn: isOn)
        }
        .buttonStyle(.plain)
    }
}

private struct ChipLabel: View {
    let title: String
    var symbol: String?
    let isOn: Bool

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).font(.ui(12)) }
            Text(title).lineLimit(1)
        }
        .font(.ui(12).weight(.medium))
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .foregroundStyle(isOn ? .white : .primary)
        .background(isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary), in: Capsule())
        .contentShape(Capsule())
    }
}
