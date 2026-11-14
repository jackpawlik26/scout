import AppKit
import ScoutCore
import SwiftUI

/// History (⌥⌘Y): everything Scout moved, copied, renamed or trashed, kept across
/// launches. Search it to answer "where did that file go?", and undo things from days ago.
struct HistoryView: View {
    let browser: BrowserModel
    @Environment(AppServices.self) private var services

    @State private var query = ""
    @State private var expanded: Set<UUID> = []
    @State private var shown = 150
    @State private var isConfirmingClear = false
    @FocusState private var isSearchFocused: Bool

    private var history: FileHistory { services.fileHistory }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if history.entries.isEmpty {
                    emptyState
                } else if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    timeline
                } else {
                    searchResults
                }
            }
            .padding(16)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .onAppear { isSearchFocused = true }
        .alert("Clear History?", isPresented: $isConfirmingClear) {
            Button("Clear History", role: .destructive) { services.clearFileHistory() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Scout forgets what it moved, renamed and trashed. Your files stay where they are.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Color.textSubtle)
                TextField("Where did that file go? Type part of its name…", text: $query)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(Color.textSubtle)
                        .help("Clear the search")
                }
            }
            .font(.ui(14))
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(RaisedFill(shape: RoundedRectangle(cornerRadius: 9)))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.hairline))

            Menu {
                Button("Clear History…") { isConfirmingClear = true }
                    .disabled(history.entries.isEmpty)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            .help("More")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath").font(.system(size: 28, weight: .light))
            Text("Nothing yet").font(.ui(15, .medium))
            Text("When you move, copy, rename or trash files in Scout, they show up here, so you can find them again or undo it later, even after quitting.")
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .foregroundStyle(Color.textSubtle)
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Everything, by day

    private var timeline: some View {
        let undone = Set(history.entries.compactMap(\.undoes))
        let indexed = Array(history.entries.enumerated().reversed().prefix(shown))
        let days = Dictionary(grouping: indexed) { Calendar.current.startOfDay(for: $0.element.date) }
        return VStack(alignment: .leading, spacing: 14) {
            ForEach(days.keys.sorted(by: >), id: \.self) { day in
                Text(Self.dayTitle(day))
                    .font(.ui(12).weight(.medium))
                    .foregroundStyle(Color.textSubtle)
                    .padding(.horizontal, 4)
                Card(spacing: 0) {
                    let rows = days[day] ?? []
                    ForEach(Array(rows.enumerated()), id: \.element.element.id) { position, row in
                        if position > 0 { Divider().padding(.vertical, 6) }
                        entryRow(row.element, index: row.offset, isUndone: undone.contains(row.element.id))
                    }
                }
            }
            if history.entries.count > shown {
                Button("Show Earlier") { shown += 300 }
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func entryRow(_ entry: FileHistoryEntry, index: Int, isUndone: Bool) -> some View {
        let isOpen = expanded.contains(entry.id)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: Self.symbol(for: history.describedAction(of: entry)))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(of: entry)).lineLimit(2)
                    Text(subtitle(of: entry))
                        .font(.ui(12)).foregroundStyle(Color.textSubtle).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 8)
                if isUndone {
                    Text("Undone").font(.ui(12)).foregroundStyle(Color.textSubtle)
                } else {
                    Button("Undo") { browser.undoFromHistory(entry) }
                        .controlSize(.small)
                        .help(entry.action == .copy ? "Move the copies to the Trash" : "Put \(entry.changes.count == 1 ? "it" : "them") back")
                }
                if entry.changes.count > 1 {
                    Button {
                        if isOpen { expanded.remove(entry.id) } else { expanded.insert(entry.id) }
                    } label: {
                        Image(systemName: "chevron.right")
                            .rotationEffect(.degrees(isOpen ? 90 : 0))
                            .frame(width: 16, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.textSubtle)
                    .help(isOpen ? "Hide the files" : "Show the files")
                } else if let change = entry.changes.first {
                    showButton(history.currentPath(of: change.to, after: index))
                }
            }
            .font(.ui(13))
            if isOpen {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(entry.changes, id: \.self) { change in
                        fileRow(change, now: history.currentPath(of: change.to, after: index))
                    }
                }
                .padding(.leading, 28)
            }
        }
    }

    private func fileRow(_ change: FileChange, now: String) -> some View {
        HStack(spacing: 8) {
            Image(nsImage: IconCache.icon(forPath: FileManager.default.fileExists(atPath: now) ? now : change.from))
                .resizable().frame(width: 16, height: 16)
            Text(Self.name(change.to)).lineLimit(1).truncationMode(.middle)
            Text(Self.name(change.from) == Self.name(change.to) ? "" : "was “\(Self.name(change.from))”")
                .foregroundStyle(Color.textSubtle).lineLimit(1)
            Spacer(minLength: 8)
            showButton(now)
        }
        .font(.ui(12))
    }

    // MARK: - Search: where did it go?

    private var searchResults: some View {
        let matches = history.matches(query)
        return VStack(alignment: .leading, spacing: 10) {
            if matches.isEmpty {
                Text("Scout hasn’t moved, renamed or trashed anything called “\(query)”.")
                    .foregroundStyle(Color.textSubtle)
                    .padding(.top, 20)
                    .frame(maxWidth: .infinity)
            } else {
                Card(spacing: 0) {
                    ForEach(Array(matches.enumerated()), id: \.element.id) { position, match in
                        if position > 0 { Divider().padding(.vertical, 6) }
                        matchRow(match)
                    }
                }
            }
        }
    }

    private func matchRow(_ match: FileHistory.Match) -> some View {
        let exists = FileManager.default.fileExists(atPath: match.currentPath)
        return HStack(alignment: .top, spacing: 10) {
            Image(nsImage: IconCache.icon(forPath: exists ? match.currentPath : match.change.from))
                .resizable().frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.name(match.change.to)).lineLimit(1).truncationMode(.middle)
                Text("\(changeSentence(match)) · \(Self.when(match.entry.date))")
                    .font(.ui(12)).foregroundStyle(Color.textSubtle).lineLimit(2)
                Text(exists ? "Now in \(display(parent(match.currentPath)))"
                     : "No longer at \(display(parent(match.currentPath))), it may have been moved by another app or deleted.")
                    .font(.ui(12)).foregroundStyle(exists ? Color.textStrong : Color.textSubtle).lineLimit(2)
            }
            Spacer(minLength: 8)
            showButton(match.currentPath)
        }
        .font(.ui(13))
    }

    /// "Moved from Downloads to Work", "Renamed from “a.pdf”", "Moved to the Trash from Desktop"…
    private func changeSentence(_ match: FileHistory.Match) -> String {
        let change = match.change
        let fromFolder = display(parent(change.from))
        let toFolder = display(parent(change.to))
        let (action, isRedo) = history.describedAction(of: match.entry)
        let prefix = isRedo ? "Redone: " : ""
        switch action {
        case .rename: return prefix + "Renamed from “\(Self.name(change.from))”"
        case .trash: return prefix + "Moved to the Trash from \(fromFolder)"
        case .copy: return prefix + "Copied from \(fromFolder) to \(toFolder)"
        case .tidy: return prefix + "Tidied into \(toFolder)"
        case .rule: return prefix + "Filed into \(toFolder) by “\(match.entry.note ?? "a rule")”"
        case .move: return prefix + "Moved from \(fromFolder) to \(toFolder)"
        case .undo: return "Put back in \(toFolder)"
        }
    }

    // MARK: - Pieces

    @ViewBuilder private func showButton(_ path: String) -> some View {
        if FileManager.default.fileExists(atPath: path) {
            Button("Show") { browser.reveal(URL(filePath: path)) }
                .controlSize(.small)
                .help(display(path))
        } else {
            Text("Gone").font(.ui(12)).foregroundStyle(Color.textSubtle)
                .help("Not at \(display(path)) any more")
        }
    }

    private func title(of entry: FileHistoryEntry) -> String {
        let (action, isRedo) = history.describedAction(of: entry)
        if action == .undo {
            if let target = entry.undoes.flatMap(history.entry) { return "Undid: " + plainTitle(target, action: target.action) }
            return "Put back \(Self.count(entry.changes.count))"
        }
        return (isRedo ? "Redid: " : "") + plainTitle(entry, action: action)
    }

    private func plainTitle(_ entry: FileHistoryEntry, action: FileAction) -> String {
        let changes = entry.changes
        let one = changes.count == 1 ? "“\(Self.name(changes[0].from))”" : Self.count(changes.count)
        let folders = Set(changes.map { parent($0.to) })
        let into = folders.count == 1 ? " to \(Self.name(folders.first!))" : ""
        switch action {
        case .move: return "Moved \(one)\(into)"
        case .copy: return "Copied \(one)\(into)"
        case .trash: return "Moved \(one) to the Trash"
        case .tidy: return "Tidied \(Self.count(changes.count)) in \(Self.name(parent(changes[0].from)))"
        case .rule: return "Filed \(one)\(into) by a rule"
        case .rename:
            return changes.count == 1 ? "Renamed \(one) to “\(Self.name(changes[0].to))”" : "Renamed \(one)"
        case .undo: return "Put back \(Self.count(changes.count))"
        }
    }

    private func subtitle(of entry: FileHistoryEntry) -> String {
        var time = entry.date.formatted(date: .omitted, time: .shortened)
        if entry.action == .rule, let rule = entry.note { time += " · “\(rule)”" }
        let from = Set(entry.changes.map { parent($0.from) })
        guard from.count == 1, let folder = from.first else { return time }
        return "\(time) · from \(display(folder))"
    }

    private func parent(_ path: String) -> String { (path as NSString).deletingLastPathComponent }
    private func display(_ path: String) -> String { PathDisplay.display(path, home: services.homePath) }

    static func name(_ path: String) -> String { (path as NSString).lastPathComponent }
    static func count(_ n: Int) -> String { n == 1 ? "1 item" : "\(n) items" }

    static func symbol(for described: (action: FileAction, isRedo: Bool)) -> String {
        if described.isRedo { return "arrow.uturn.forward" }
        switch described.action {
        case .move: return "arrow.right.doc.on.clipboard"
        case .copy: return "doc.on.doc"
        case .rename: return "character.cursor.ibeam"
        case .trash: return "trash"
        case .tidy: return "wand.and.sparkles"
        case .rule: return "tray.and.arrow.down"
        case .undo: return "arrow.uturn.backward"
        }
    }

    static func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        let sameYear = calendar.isDate(day, equalTo: .now, toGranularity: .year)
        return day.formatted(sameYear ? .dateTime.weekday(.wide).month(.wide).day()
                                      : .dateTime.month(.wide).day().year())
    }

    static func when(_ date: Date) -> String {
        Calendar.current.isDateInToday(date)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(date: .abbreviated, time: .shortened)
    }
}
