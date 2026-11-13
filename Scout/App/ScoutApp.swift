import SwiftUI

@main
struct ScoutApp: App {
    @State private var services = AppServices()

    var body: some Scene {
        WindowGroup(id: "browser") {
            BrowserWindow()
                .environment(services)
        }
        .defaultSize(width: 1180, height: 740)
        // Scout draws its own header; no system title bar or toolbar.
        .windowStyle(.hiddenTitleBar)
        .commands { ScoutCommands() }
    }
}
