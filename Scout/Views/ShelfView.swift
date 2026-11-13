import ScoutCore
import SwiftUI

/// The Shelf (⌥⌘S): a floating holding area. Drop files in from anywhere, then copy or
/// move them all into the folder you're looking at, or drag them out to another app.
struct ShelfView: View {
    @Environment(AppServices.self) private var services
    @State private var isTargeted = false

    private var target: BrowserModel? {
        guard let browser = services.frontWindow?.current, browser.isFolder else { return nil }
        return browser
    }

    var body: some View {
        let items = services.shelf.compactMap { LocalFileSource.item(for: $0) }
        VStack(spacing: 0) {
            if items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray.and.arrow.down").font(.system(size: 28)).foregroundStyle(.secondary)
                    Text("Drop files here").font(.headline)
                    Text("Collect files from different folders, then copy or move them together.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(items) { item in
                        HStack(spacing: 8) {
                            FileIconView(item: item, size: 20)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(item.name).lineLimit(1).truncationMode(.middle)
                                Text(PathDisplay.display(item.url.deletingLastPathComponent().filePath, home: services.homePath))
                                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                            }
                            Spacer()
                            Button { services.removeFromShelf(item.url) } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain).foregroundStyle(.tertiary)
                        }
                        .draggable(item.url)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            Divider()
            HStack(spacing: 8) {
                Button("Clear") { services.clearShelf() }.disabled(items.isEmpty)
                Spacer()
                Button("Copy Here") { send(move: false) }.disabled(items.isEmpty || target == nil)
                Button("Move Here") { send(move: true) }
                    .buttonStyle(.borderedProminent)
                    .disabled(items.isEmpty || target == nil)
            }
            .controlSize(.small)
            .padding(10)
            Text(target.map { "Into “\($0.title)”" } ?? "Open a folder in Scout to copy or move into it")
                .font(.caption2).foregroundStyle(.tertiary).padding(.bottom, 8)
        }
        .frame(width: 300, height: 360)
        .background(isTargeted ? Color.accentSoft : Color.clear)
        .dropDestination(for: URL.self) { urls, _ in
            services.addToShelf(urls)
            return true
        } isTargeted: { isTargeted = $0 }
    }

    private func send(move: Bool) {
        guard let target else { return }
        target.transfer(services.shelf, into: target.location, move: move)
        if move { services.clearShelf() }
    }
}
