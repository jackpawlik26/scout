import AppKit
import ScoutCore
import SwiftUI

/// Column view (⌘3): one column per folder from your home (or the disk) down to where
/// you are, plus a preview of the selected file. → opens, ← goes back, ↑↓ move.
struct ColumnBrowserView: View {
    let window: BrowserWindowModel
    @Bindable var browser: BrowserModel
    @State private var columns: [URL: [FileItem]] = [:]
    @FocusState private var isFocused: Bool

    static let width: CGFloat = 230

    /// Folders shown as columns, outermost first. The last is where you are.
    private var path: [URL] {
        let home = browser.services.homePath
        let here = browser.location.filePath
        let rootPath = here == home || here.hasPrefix(home + "/") ? home : "/"
        var result: [URL] = []
        var url = browser.location
        while true {
            result.insert(url, at: 0)
            if url.filePath == rootPath { break }
            let parent = url.deletingLastPathComponent()
            if parent.filePath == url.filePath { break }
            url = parent
        }
        return result
    }

    private var previewItem: FileItem? {
        let selected = browser.selectedItems
        guard selected.count == 1, !selected[0].isNavigable else { return nil }
        return selected[0]
    }

    var body: some View {
        let path = path
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(Array(path.enumerated()), id: \.element) { index, folder in
                        let isCurrent = index == path.count - 1
                        column(folder: folder, items: isCurrent ? browser.displayedItems : (columns[folder] ?? []),
                               highlighted: isCurrent ? nil : path[index + 1], isCurrent: isCurrent)
                            .id(folder)
                        Rectangle().fill(Color.hairline).frame(width: 1)
                    }
                    if let previewItem {
                        ColumnPreview(browser: browser, item: previewItem)
                            .frame(width: 280)
                            .id("preview")
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .onChange(of: browser.location, initial: true) {
                loadAncestors()
                Task {
                    try? await Task.sleep(for: .milliseconds(50))
                    withAnimation(.snappy(duration: 0.2)) { proxy.scrollTo(browser.location, anchor: .trailing) }
                }
            }
            .onChange(of: previewItem?.id) { _, id in
                if id != nil { withAnimation(.snappy(duration: 0.2)) { proxy.scrollTo("preview", anchor: .trailing) } }
            }
        }
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onAppear { isFocused = true }
        .onChange(of: browser.location) { if !isEditingText { isFocused = true } }
        .onKeyPress(.upArrow, phases: [.down, .repeat]) { move(-1, extend: $0.modifiers.contains(.shift)) }
        .onKeyPress(.downArrow, phases: [.down, .repeat]) { move(1, extend: $0.modifiers.contains(.shift)) }
        .onKeyPress(.rightArrow) {
            guard let item = browser.selectedItems.first, item.isNavigable else { return .ignored }
            browser.go(to: item.url)
            return .handled
        }
        .onKeyPress(.leftArrow) {
            guard path.count > 1 else { return .ignored }
            browser.goUp()
            return .handled
        }
        .onKeyPress(.space) {
            browser.toggleQuickLook()
            return .handled
        }
        .onKeyPress(.return) { browser.beginRename() ? .handled : .ignored }
        .onKeyPress(characters: .alphanumerics.union(.punctuationCharacters), phases: .down) { press in
            guard press.modifiers.isDisjoint(with: [.command, .control, .option]) else { return .ignored }
            browser.typeSelect(press.characters)
            return .handled
        }
        .onCopyCommand {
            browser.copySelectionToPasteboard()
            return []
        }
        .onPasteCommand(of: [.fileURL]) { _ in browser.paste(move: false) }
    }

    // MARK: - A column

    private func column(folder: URL, items: [FileItem], highlighted: URL?, isCurrent: Bool) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(items) { item in
                        ColumnRow(item: item,
                                  isSelected: isCurrent ? browser.selection.contains(item.id) : item.url.filePath == highlighted?.filePath,
                                  isActive: isCurrent && isFocused,
                                  gitState: isCurrent ? browser.gitState(item) : nil)
                            .id(item.id)
                            .onTapGesture { click(item, inColumn: folder, isCurrent: isCurrent) }
                            .contextMenu {
                                if isCurrent {
                                    FileContextMenu(window: window, browser: browser,
                                                    urls: browser.selection.contains(item.id) ? browser.selection : [item.id])
                                }
                            }
                            .draggable(containerItemID: item.id)
                            .folderDropTarget(item, browser: browser)
                    }
                }
                .padding(6)
            }
            .fileDragContainer(browser)
            .onAppear { if let highlighted { proxy.scrollTo(highlighted, anchor: .center) } }
            .onChange(of: browser.scrollTarget) { _, target in
                if isCurrent, let target { proxy.scrollTo(target) }
            }
        }
        .frame(width: Self.width)
        .contentShape(Rectangle())
        .contextMenu { if isCurrent { FileContextMenu(window: window, browser: browser, urls: []) } }
        .dropDestination(for: URL.self) { urls, _ in
            // Same rules as any drop: ⌥ copies, other disks copy, never into itself.
            return isCurrent ? browser.receiveDrop(urls) : browser.receiveDrop(urls, into: folder)
        }
    }

    private func click(_ item: FileItem, inColumn folder: URL, isCurrent: Bool) {
        isFocused = true
        if NSApp.currentEvent?.clickCount == 2 {
            if isCurrent { browser.open([item.id]) } else { browser.go(to: folder, select: item.url) }
            return
        }
        if item.isNavigable {
            browser.go(to: item.url)
        } else if !isCurrent {
            browser.go(to: folder, select: item.url)
        } else {
            browser.click(item, in: browser.displayedItems, modifiers: NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags)
        }
    }

    private func move(_ offset: Int, extend: Bool) -> KeyPress.Result {
        let items = browser.displayedItems
        guard !items.isEmpty else { return .ignored }
        guard let current = browser.cursorIndex(in: items) else {
            browser.select(items[0])
            return .handled
        }
        let next = max(0, min(items.count - 1, current + offset))
        browser.moveSelection(to: items[next], in: items, extend: extend)
        return .handled
    }

    /// Loads the folders above the current one (the current one is the browser's own listing).
    private func loadAncestors() {
        let folders = Array(path.dropLast())
        let includeHidden = browser.showHidden
        let source = browser.services.fileSource
        Task {
            for folder in folders where columns[folder] == nil {
                let items = (try? await source.contents(of: folder, includeHidden: includeHidden)) ?? []
                columns[folder] = items.sorted {
                    if $0.isNavigable != $1.isNavigable { return $0.isNavigable }
                    return $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
            }
            // Keep the cache small: only folders on the current path.
            columns = columns.filter { folders.contains($0.key) }
        }
    }
}

private struct ColumnRow: View {
    let item: FileItem
    @Environment(AppServices.self) private var services: AppServices?
    let isSelected: Bool
    let isActive: Bool
    let gitState: GitFileState?

    var body: some View {
        HStack(spacing: 7) {
            FileIconView(item: item, size: 16)
            Text(services?.displayName(item) ?? item.name).font(.system(size: 13)).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 4)
            if let gitState { GitBadge(state: gitState, isFolder: item.isNavigable) }
            if item.isNavigable {
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .medium))
                    .foregroundStyle(isSelected && isActive ? Color.white.opacity(0.85) : Color.secondary.opacity(0.6))
            }
        }
        .foregroundStyle(isSelected && isActive ? Color.white : Color.primary)
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(
            RoundedRectangle(cornerRadius: 6).fill(isSelected ? (isActive ? Color.accentColor : Color.primary.opacity(0.1)) : .clear)
        )
        .opacity(item.isHidden ? 0.55 : 1)
        .contentShape(Rectangle())
    }
}

/// The last column: a preview and the basics of the selected file.
private struct ColumnPreview: View {
    let browser: BrowserModel
    let item: FileItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                PreviewPane(item: item)
                Text(item.name).font(.ui(13, .medium)).textSelection(.enabled)
                Text(item.kind).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(Format.size(item))
                    Text("Modified \(Format.date(item.dateModified))")
                }
                .font(.ui(13)).foregroundStyle(.secondary)
                Button("Open") { browser.open([item.id]) }
            }
            .padding(14)
        }
    }
}
