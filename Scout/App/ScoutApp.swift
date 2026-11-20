import SwiftUI

@main
struct ScoutApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var services = AppServices()
    @AppStorage("menuBarIcon") private var showsMenuBarIcon = true

    var body: some Scene {
        WindowGroup(id: "browser") {
            BrowserWindow()
                .environment(services)
                .onAppear { delegate.services = services }
        }
        .defaultSize(width: 1180, height: 740)
        // Scout draws its own header; no system title bar or toolbar.
        .windowStyle(.hiddenTitleBar)
        .commands { ScoutCommands() }

        MenuBarExtra("Scout", systemImage: "binoculars.fill", isInserted: $showsMenuBarIcon) {
            MenuBarMenu()
                .environment(services)
        }

        Window("Shelf", id: "shelf") {
            ShelfView()
                .environment(services)
        }
        .windowResizability(.contentSize)
        .windowLevel(.floating)
        .defaultPosition(.trailing)
        .restorationBehavior(.disabled)

        Window("Downloads", id: "downloads") {
            DownloadsWindowView()
                .environment(services)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 300, height: 420)
        .windowLevel(.floating)
        .defaultPosition(.topTrailing)
    }
}
