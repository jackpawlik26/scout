import ScoutCore
import SwiftUI

/// The menu bar icon's menu: jump, latest downloads, favorites, workspaces, tools.
struct MenuBarMenu: View {
    @Environment(AppServices.self) private var services
    @Environment(\.openWindow) private var openWindow

    private var latestDownloads: [FileItem] {
        let downloads = services.home.appending(path: "Downloads")
        let urls = (try? FileManager.default.contentsOfDirectory(at: downloads, includingPropertiesForKeys: nil,
                                                                 options: [.skipsHiddenFiles])) ?? []
        return urls.compactMap(LocalFileSource.item(for:))
            .sorted { ($0.dateAdded ?? .distantPast) > ($1.dateAdded ?? .distantPast) }
            .prefix(8).map(\.self)
    }

    var body: some View {
        Button("Jump to Folder or File…") { services.route(.jump(query: nil)) }
        Divider()
        Section("Latest Downloads") {
            ForEach(latestDownloads) { item in
                Button {
                    services.route(.open(path: item.path, newTab: false))
                } label: {
                    Label {
                        Text(item.name)
                    } icon: {
                        Image(nsImage: IconCache.icon(forPath: item.path))
                    }
                }
            }
        }
        Section("Favorites") {
            ForEach(services.favorites) { place in
                Button(place.name) { services.route(.open(path: place.url.filePath, newTab: false)) }
            }
        }
        if !services.workspaces.isEmpty {
            Section("Workspaces") {
                ForEach(services.workspaces) { workspace in
                    Button(workspace.name) { services.route(.workspace(name: workspace.name)) }
                }
            }
        }
        Divider()
        Button("Recents") { services.route(.recents) }
        Button("Clean Up") { services.route(.cleanup) }
        Button("Shelf") {
            NSApp.activate()
            openWindow(id: "shelf")
        }
        Divider()
        Button("Settings…") { services.route(.settings) }
        Button("Quit Scout") { NSApp.terminate(nil) }
    }
}
