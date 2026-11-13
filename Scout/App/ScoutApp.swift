import SwiftUI

@main
struct ScoutApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var services = AppServices()

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
    }
}
