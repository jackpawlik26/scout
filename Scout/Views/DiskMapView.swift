import AppKit
import ScoutCore
import SwiftUI

/// Disk Map: what fills a folder, as blocks sized by how much space each item takes.
/// Click a folder to go into it; right-click to show, open or trash.
struct DiskMapView: View {
    let browser: BrowserModel
    /// Where the map started (the path bar can't go above it).
    let root: String
    @Environment(AppServices.self) private var services

    @State private var current: String
    @State private var nodes: [Node] = []
    @State private var measuring = 0
    @State private var hovered: String?

    struct Node: Identifiable, Equatable {
        var id: String { path }
        let path: String
        let name: String
        var bytes: Int64
        let isFolder: Bool
        let category: FileCategory
        var isPartial = false
        /// "Smaller items": everything too small to draw on its own.
        var isOther = false
    }

    init(browser: BrowserModel, root: String) {
        self.browser = browser
        self.root = root
        _current = State(initialValue: root)
    }

    /// Items drawn on their own; the rest are summed into one block.
    static let maxBlocks = 120

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            pathBar
            GeometryReader { geo in
                let shown = nodes.filter { $0.bytes > 0 }
                let rects = Treemap.layout(shown.map { Double($0.bytes) }, in: CGRect(origin: .zero, size: geo.size))
                ZStack(alignment: .topLeading) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, node in
                        block(node, rect: rects[index])
                    }
                }
            }
            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                if nodes.isEmpty, measuring == 0 {
                    Text("Nothing here takes up space.").foregroundStyle(Color.textSubtle)
                }
            }
        }
        .padding(16)
        .task(id: current) { await load() }
    }

    // MARK: - Pieces

    private var pathBar: some View {
        let total = nodes.reduce(Int64(0)) { $0 + $1.bytes }
        return HStack(spacing: 6) {
            Button { goUp() } label: { Image(systemName: "chevron.left") }
                .disabled(current == root)
                .help("Back out")
            ForEach(crumbs, id: \.self) { path in
                if path != crumbs.first { Image(systemName: "chevron.compact.right").foregroundStyle(Color.textSubtle) }
                Button(FileManager.default.displayName(atPath: path)) { current = path }
                    .buttonStyle(.plain)
                    .fontWeight(path == current ? .medium : .regular)
            }
            Spacer()
            if measuring > 0 {
                ProgressView().controlSize(.small)
                Text("Measuring \(measuring) folder\(measuring == 1 ? "" : "s")…").foregroundStyle(Color.textSubtle)
            }
            Text(Format.bytes(total)).monospacedDigit()
            Button("Show in Scout") { browser.go(to: .folder(current)) }
        }
        .font(.ui(13))
    }

    private var crumbs: [String] {
        var paths = [current]
        var path = current
        while path != root, path.count > root.count {
            path = (path as NSString).deletingLastPathComponent
            paths.insert(path, at: 0)
        }
        return paths
    }

    private func block(_ node: Node, rect: CGRect) -> some View {
        let isHovered = hovered == node.path
        let color: Color = node.isOther ? .gray : node.isFolder ? .accentColor : node.category.color
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 5)
                .fill(color.opacity(isHovered ? 0.55 : 0.32))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(color.opacity(0.7), lineWidth: isHovered ? 2 : 0.5))
            if rect.width > 70, rect.height > 34 {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        if node.isFolder { Image(systemName: "folder.fill").font(.system(size: 10)) }
                        Text(node.name).lineLimit(1).truncationMode(.middle)
                    }
                    .font(.ui(12, .medium))
                    Text((node.isPartial ? "≥ " : "") + Format.bytes(node.bytes)).font(.ui(11)).monospacedDigit()
                        .foregroundStyle(Color.textSubtle)
                }
                .padding(6)
            }
        }
        .frame(width: max(0, rect.width - 2), height: max(0, rect.height - 2))
        .offset(x: rect.minX + 1, y: rect.minY + 1)
        .contentShape(Rectangle())
        .onHover { inside in hovered = inside ? node.path : (hovered == node.path ? nil : hovered) }
        .help("\(node.name) · \(Format.bytes(node.bytes))\(node.isFolder ? " · click to go in" : "")")
        .onTapGesture { if node.isFolder { current = node.path } }
        .contextMenu {
            if !node.isOther {
                Button("Show in Scout") { browser.reveal(URL(filePath: node.path)) }
                Button("Open") { NSWorkspace.shared.open(URL(filePath: node.path)) }
                Divider()
                Button("Move to Trash") {
                    if browser.trash([URL(filePath: node.path)]) > 0 { nodes.removeAll { $0.path == node.path } }
                }
            }
        }
    }

    // MARK: - Loading

    private func goUp() {
        guard current != root else { return }
        current = (current as NSString).deletingLastPathComponent
    }

    /// Files first (their sizes are known), then each folder as it's measured, biggest first.
    private func load() async {
        let folder = URL.folder(current)
        let items = (try? await LocalFileSource().contents(of: folder, includeHidden: true)) ?? []
        guard !Task.isCancelled else { return }
        var list = items.map { item in
            Node(path: item.path, name: item.name, bytes: item.isNavigable ? 0 : (item.size ?? 0),
                 isFolder: item.isNavigable, category: FileCategory.of(item))
        }
        nodes = Self.condensed(list)
        let folders = list.filter(\.isFolder)
        measuring = folders.count
        for node in folders {
            guard !Task.isCancelled else { return }
            let size = await services.folderSize(URL.folder(node.path))
            if let index = list.firstIndex(where: { $0.path == node.path }) {
                list[index].bytes = size.bytes
                list[index].isPartial = size.isPartial
            }
            measuring -= 1
            nodes = Self.condensed(list)
        }
    }

    /// Biggest first; past `maxBlocks`, the rest become one "Smaller items" block.
    static func condensed(_ list: [Node]) -> [Node] {
        let sorted = list.filter { $0.bytes > 0 }.sorted { $0.bytes > $1.bytes }
        guard sorted.count > maxBlocks else { return sorted }
        let rest = sorted.dropFirst(maxBlocks)
        let other = Node(path: "other:\(rest.count)", name: "\(rest.count) smaller items",
                         bytes: rest.reduce(0) { $0 + $1.bytes }, isFolder: false, category: .other, isOther: true)
        return Array(sorted.prefix(maxBlocks)) + [other]
    }
}
