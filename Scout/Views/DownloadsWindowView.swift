import AppKit
import ScoutCore
import SwiftUI

/// A small window that stays on top with your newest downloads. Drag a file out into any
/// app, or drop files on it to move them into Downloads (hold ⌥ to copy).
struct DownloadsWindowView: View {
    @Environment(AppServices.self) private var services
    @State private var isTargeted = false
    @State private var filter = ""

    private var downloads: URL { services.home.appending(path: "Downloads", directoryHint: .isDirectory) }

    var body: some View {
        let items = services.latestDownloads.filter { item in
            filter.isEmpty || item.name.range(of: filter, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
        VStack(spacing: 0) {
            TextField("Filter", text: $filter)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .padding(8)
            Divider()
            if items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle").font(.system(size: 28)).foregroundStyle(Color.textSubtle)
                    Text(filter.isEmpty ? "Nothing in Downloads" : "No matches").font(.ui(13, .medium))
                    Text("Drop files here to move them into Downloads. Hold ⌥ to copy.")
                        .font(.ui(12)).foregroundStyle(Color.textSubtle).multilineTextAlignment(.center)
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(items) { item in
                    HStack(spacing: 8) {
                        FileIconView(item: item, size: 24)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(item.name).lineLimit(1).truncationMode(.middle)
                            Text(detail(item)).font(.ui(11)).foregroundStyle(Color.textSubtle).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                    .draggable(item.url)
                    .onTapGesture(count: 2) {
                        NSWorkspace.shared.open(item.url)
                        services.recordOpen(item.url)
                    }
                    .contextMenu {
                        Button("Open") { NSWorkspace.shared.open(item.url) }
                        Button("Show in Scout") { reveal(item.url) }
                        Button("Add to Shelf") { services.addToShelf([item.url]) }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            Divider()
            HStack {
                Text("Double-click opens. Drag a file out to use it anywhere.")
                    .font(.ui(11)).foregroundStyle(Color.textSubtle)
                Spacer()
                Button { reveal(downloads) } label: { Image(systemName: "folder") }
                    .buttonStyle(.plain).foregroundStyle(Color.textSubtle)
                    .help("Open Downloads in Scout")
            }
            .padding(8)
        }
        .frame(minWidth: 260, minHeight: 280)
        .background(isTargeted ? Color.accentSoft : Color.clear)
        .dropDestination(for: URL.self) { urls, _ in
            let incoming = urls.filter { $0.isFileURL && $0.deletingLastPathComponent().filePath != downloads.filePath }
            guard !incoming.isEmpty else { return false }
            if let browser = services.frontWindow?.current {
                // Moves within a disk, copies across disks or with ⌥; undoable, asks about clashes.
                browser.receiveDrop(incoming, into: downloads)
            } else {
                NSApp.activate()
                services.route(.open(path: downloads.filePath, newTab: false))
            }
            return true
        } isTargeted: { isTargeted = $0 }
        .onAppear { services.refreshLatestDownloads() }
    }

    private func detail(_ item: FileItem) -> String {
        let when = item.dateAdded.map { $0.formatted(.relative(presentation: .named)) } ?? ""
        return [when, item.isDirectory ? "Folder" : Format.size(item)].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Shows the file selected in its folder, in the frontmost Scout window (or a new one).
    private func reveal(_ url: URL) {
        services.route(.open(path: url.filePath, newTab: false))
    }
}
