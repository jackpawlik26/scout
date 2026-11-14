import AppKit
import ScoutCore
import SwiftUI

extension FileCategory {
    var color: Color {
        switch self {
        case .folders: .accentColor
        case .documents: .blue
        case .images: .pink
        case .videos: .orange
        case .audio: .teal
        case .archives: .brown
        case .apps: .indigo
        case .code: .green
        case .other: .gray
        }
    }
}

/// The info panel on the right (⌥⌘I): details for the selection, or a summary
/// of the folder with what takes the space.
struct InspectorView: View {
    let browser: BrowserModel

    var body: some View {
        let selected = browser.selectedItems
        ScrollView {
            Group {
                if selected.count == 1 {
                    ItemInspector(browser: browser, item: selected[0])
                } else if selected.count > 1 {
                    FolderSummary(browser: browser, title: "\(selected.count) items selected",
                                  icon: nil, items: selected)
                } else if browser.isFolder {
                    VStack(alignment: .leading, spacing: 14) {
                        FolderSummary(browser: browser, title: browser.title,
                                      icon: IconCache.icon(forPath: browser.location.filePath), items: browser.items)
                        if let git = browser.git {
                            GitCard(browser: browser, git: git)
                        } else if browser.untrustedRepo != nil {
                            UntrustedRepoCard(browser: browser)
                        }
                    }
                } else if browser.workspaceID != nil {
                    FolderSummary(browser: browser, title: browser.title, icon: nil, items: browser.items)
                } else {
                    Text(browser.mode == .settings ? "Settings apply to every Scout window."
                         : browser.isToolPage ? "\(browser.title) shows what each item is right in the list."
                         : "Select an item to see its details.")
                        .foregroundStyle(Color.textSubtle)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - One item

private struct ItemInspector: View {
    let browser: BrowserModel
    let item: FileItem
    @State private var folderSize: FolderStats.Size?
    @State private var itemCount: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PreviewPane(item: item)
                .id(item.id)

            VStack(alignment: .leading, spacing: 3) {
                Text(browser.services.displayName(item))
                    .font(.ui(16).weight(.medium))
                    .textSelection(.enabled)
                if browser.services.displayName(item) != item.name {
                    Text("On disk: \(item.name)").font(.ui(12)).foregroundStyle(Color.textSubtle).textSelection(.enabled)
                }
                Text(item.isNavigable ? "Folder" : item.kind)
                    .foregroundStyle(Color.textSubtle)
            }

            Card {
                InfoRow("Size", value: sizeText)
                if item.isNavigable { InfoRow("Contains", value: itemCount.map { "\($0) item\($0 == 1 ? "" : "s")" } ?? "…") }
                InfoRow("Created", value: Format.date(item.dateCreated))
                InfoRow("Modified", value: Format.date(item.dateModified))
                if item.dateAdded != nil { InfoRow("Added", value: Format.date(item.dateAdded)) }
                InfoRow("Where", value: PathDisplay.display(item.url.deletingLastPathComponent().filePath,
                                                            home: browser.services.homePath))
                HStack(alignment: .firstTextBaseline) {
                    Text("Tags").foregroundStyle(Color.textSubtle)
                    Spacer(minLength: 12)
                    if item.tags.isEmpty {
                        Text("None").foregroundStyle(Color.textSubtle)
                    } else {
                        TagDots(tags: item.tags, size: 10)
                        Text(item.tags.map(\.name).joined(separator: ", ")).lineLimit(1)
                    }
                    Menu {
                        TagsMenu(browser: browser, items: [item])
                    } label: {
                        Image(systemName: "tag")
                    }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                    .help("Change tags")
                }
            }

            if let source = item.source {
                SourceCard(browser: browser, source: source)
            }

            HStack {
                Button("Open") { browser.open([item.id]) }
                Button("Quick Look") { browser.toggleQuickLook() }
                    .disabled(item.isNavigable)
                Spacer()
            }
            .controlSize(.regular)


            if let git = browser.git {
                GitCard(browser: browser, git: git, item: item)
            }
        }
        .task(id: item.id) {
            folderSize = nil
            itemCount = nil
            guard item.isNavigable else { return }
            let url = item.url
            itemCount = await Task.detached { FolderStats.itemCount(of: url) }.value
            folderSize = await browser.services.folderSize(url)
        }
    }

    private var sizeText: String {
        if let size = item.size { return Format.bytes(size) }
        guard let folderSize else { return "Calculating…" }
        return (folderSize.isPartial ? "≥ " : "") + Format.bytes(folderSize.bytes)
    }
}

// MARK: - Where it came from

/// Where a download or Mail attachment came from, with a way back to it.
private struct SourceCard: View {
    let browser: BrowserModel
    let source: DownloadSource

    var body: some View {
        Card {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: source.isMail ? "envelope" : "globe")
                    .foregroundStyle(Color.textSubtle)
                Text(source.isMail ? "From Mail" : "Downloaded from")
                    .foregroundStyle(Color.textSubtle)
                Spacer(minLength: 8)
                Text(source.summary ?? "")
                    .fontWeight(.medium)
                    .lineLimit(1).truncationMode(.middle)
                    .textSelection(.enabled)
            }
            .font(.ui(13))
            if let subject = source.subject {
                Text(subject).font(.ui(12)).foregroundStyle(Color.textSubtle).lineLimit(2)
            }
            if let fileHost = source.fileSite, fileHost != source.site {
                Text("File served by \(fileHost)").font(.ui(12)).foregroundStyle(Color.textSubtle).lineLimit(1)
            }
            HStack(spacing: 8) {
                if let url = source.openURL {
                    Button(source.pageURL == nil && source.fileURL == nil ? "Show in Mail" : "Open Page") {
                        NSWorkspace.shared.open(url)
                    }
                    .help(url.absoluteString)
                }
                if let link = source.pageURL ?? source.fileURL {
                    Button("Copy Link") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(link.absoluteString, forType: .string)
                    }
                }
                Spacer(minLength: 0)
                if let site = source.site {
                    Button("More from \(site)") { showMore(from: site) }
                        .buttonStyle(.link)
                        .lineLimit(1)
                        .help("Every file you downloaded from \(site)")
                }
            }
            .controlSize(.small)
        }
    }

    private func showMore(from site: String) {
        let spec = SearchSpec(query: "from:\(site)", scope: .files)
        browser.showSearch(SavedSearch(name: "From \(site)", spec: spec))
    }
}

// MARK: - Folder (or multi-selection) summary

private struct FolderSummary: View {
    let browser: BrowserModel
    let title: String
    let icon: NSImage?
    let items: [FileItem]

    @State private var folderSizes: [URL: Int64] = [:]
    @State private var folderBreakdowns: [URL: [FileCategory: Int64]] = [:]
    @State private var measured = 0
    @State private var isMeasuring = false

    private var folders: [FileItem] { items.filter(\.isNavigable) }
    private var breakdown: [(FileCategory, Int64)] { FolderStats.breakdown(items, folderBreakdowns: folderBreakdowns) }

    var body: some View {
        // Worked out once per redraw (it walks every item).
        let parts = breakdown
        let sum = parts.reduce(0) { $0 + $1.1 }
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                if let icon {
                    Image(nsImage: icon).resizable().frame(width: 40, height: 40)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.ui(16).weight(.medium)).lineLimit(2)
                    Text(countText).foregroundStyle(Color.textSubtle)
                }
            }

            Card {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Format.bytes(sum)).font(.ui(18, .medium)).monospacedDigit()
                    Text("in all").foregroundStyle(Color.textSubtle)
                    Spacer()
                    if isMeasuring {
                        ProgressView().controlSize(.small)
                            .help("Measuring folders: \(measured) of \(folders.count)")
                    }
                }
                StackedBar(parts: parts, total: sum)
                    .padding(.vertical, 2)

                Text("What takes the space")
                    .font(.ui(12).weight(.medium))
                    .foregroundStyle(Color.textSubtle)
                    .padding(.top, 4)
                ForEach(parts, id: \.0) { category, bytes in
                    HStack(spacing: 8) {
                        Circle().fill(category.color).frame(width: 8, height: 8)
                        Text(category.title)
                        Spacer()
                        Text(Format.bytes(bytes)).foregroundStyle(Color.textSubtle).monospacedDigit()
                    }
                    .font(.ui(13))
                }
                if parts.isEmpty, !isMeasuring {
                    Text("Nothing here takes up space.").font(.ui(13)).foregroundStyle(Color.textSubtle)
                }
            }

            let largest = largestItems
            if !largest.isEmpty {
                Text("Largest")
                    .font(.ui(12).weight(.medium))
                    .foregroundStyle(Color.textSubtle)
                Card(spacing: 6) {
                    ForEach(largest, id: \.0.id) { item, bytes in
                        Button {
                            browser.selection = [item.id]
                        } label: {
                            HStack(spacing: 8) {
                                FileIconView(item: item, size: 18)
                                Text(item.name).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Text(Format.bytes(bytes)).foregroundStyle(Color.textSubtle).monospacedDigit()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .font(.ui(13))
                    }
                }
            }
        }
        // Keyed cheaply: building and comparing every item's id on each redraw adds up in big folders.
        .task(id: ItemsKey(items)) { await measureFolders() }
    }

    private var countText: String {
        let files = items.count - folders.count
        var parts: [String] = []
        if !folders.isEmpty { parts.append("\(folders.count) folder\(folders.count == 1 ? "" : "s")") }
        if files > 0 { parts.append("\(files) file\(files == 1 ? "" : "s")") }
        return parts.isEmpty ? "Empty" : parts.joined(separator: ", ")
    }

    private var largestItems: [(FileItem, Int64)] {
        items.compactMap { item -> (FileItem, Int64)? in
            let bytes = item.isNavigable ? folderSizes[item.url] : item.size
            return bytes.map { (item, $0) }
        }
        .sorted { $0.1 > $1.1 }
        .prefix(5)
        .map { $0 }
    }

    private func measureFolders() async {
        folderSizes = [:]
        folderBreakdowns = [:]
        measured = 0
        isMeasuring = !folders.isEmpty
        for folder in folders {
            guard !Task.isCancelled else { return }
            let size = await browser.services.folderSize(folder.url)
            folderSizes[folder.url] = size.bytes
            folderBreakdowns[folder.url] = size.byCategory
            measured += 1
        }
        isMeasuring = false
    }
}

// MARK: - Building blocks

private struct StackedBar: View {
    let parts: [(FileCategory, Int64)]
    let total: Int64

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(parts, id: \.0) { category, bytes in
                    category.color
                        .frame(width: max(3, geo.size.width * CGFloat(bytes) / CGFloat(max(total, 1)) - 2))
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: 8)
        .background(.quaternary)
        .clipShape(Capsule())
    }
}

/// A rounded panel used throughout the inspector.
struct Card<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) { content }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RaisedFill(shape: RoundedRectangle(cornerRadius: 12)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.hairline))
    }
}

private struct InfoRow: View {
    let label: String
    let value: String

    init(_ label: String, value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(Color.textSubtle).fixedSize()
            Spacer(minLength: 12)
            Text(value)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .font(.ui(13))
    }
}

/// A cheap stand-in for "the same list of items": count plus the first and last.
private struct ItemsKey: Equatable {
    let count: Int
    let first: URL?
    let last: URL?
    init(_ items: [FileItem]) {
        count = items.count
        first = items.first?.id
        last = items.last?.id
    }
}
