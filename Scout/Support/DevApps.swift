import AppKit
import ScoutCore

/// Terminals and code editors Scout can open folders in. Only installed ones show up.
struct DevApp: Identifiable, Hashable {
    enum Kind { case terminal, editor }

    let id: String // bundle identifier
    let name: String
    let kind: Kind
    /// A Services menu item that opens folders (more reliable than `open -a` for some terminals).
    var service: String?

    static let known: [DevApp] = [
        DevApp(id: "so.stencil.tern", name: "Tern", kind: .terminal, service: "Open in Tern"),
        DevApp(id: "com.mitchellh.ghostty", name: "Ghostty", kind: .terminal),
        DevApp(id: "com.googlecode.iterm2", name: "iTerm", kind: .terminal, service: "New iTerm2 Tab Here"),
        DevApp(id: "dev.warp.Warp-Stable", name: "Warp", kind: .terminal),
        DevApp(id: "com.apple.Terminal", name: "Terminal", kind: .terminal),
        DevApp(id: "com.todesktop.230313mzl4w4u92", name: "Cursor", kind: .editor),
        DevApp(id: "com.microsoft.VSCode", name: "VS Code", kind: .editor),
        DevApp(id: "dev.zed.Zed", name: "Zed", kind: .editor),
        DevApp(id: "com.sublimetext.4", name: "Sublime Text", kind: .editor),
        DevApp(id: "com.panic.Nova", name: "Nova", kind: .editor),
        DevApp(id: "com.apple.dt.Xcode", name: "Xcode", kind: .editor),
    ]

    var appURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) }
    var icon: NSImage? { appURL.map { IconCache.icon(forPath: $0.filePath) } }

    static func installed(_ kind: Kind) -> [DevApp] {
        known.filter { $0.kind == kind && $0.appURL != nil }
    }

    /// The terminal ⌥⇧⌘T uses: your pick, else the first installed one (Tern before Terminal).
    static var preferredTerminal: DevApp? {
        preferred(.terminal, key: "terminalApp")
    }

    /// The editor ⇧⌘O uses: your pick, else the first installed one.
    static var preferredEditor: DevApp? {
        preferred(.editor, key: "editorApp")
    }

    static func setPreferred(_ app: DevApp) {
        UserDefaults.standard.set(app.id, forKey: app.kind == .terminal ? "terminalApp" : "editorApp")
    }

    /// Remembered for a few seconds: menus ask on every redraw, and each check asks
    /// Launch Services about ~10 apps.
    nonisolated(unsafe) private static var cache: [String: (app: DevApp?, at: Date)] = [:]

    private static func preferred(_ kind: Kind, key: String) -> DevApp? {
        let chosen = UserDefaults.standard.string(forKey: key)
        let cacheKey = key + ":" + (chosen ?? "")
        if let hit = cache[cacheKey], Date().timeIntervalSince(hit.at) < 10 { return hit.app }
        let apps = installed(kind)
        let app = apps.first { $0.id == chosen } ?? apps.first
        cache[cacheKey] = (app, .now)
        return app
    }

    /// Opens a folder (or file) in this app.
    func open(_ url: URL) {
        if let service {
            let pasteboard = NSPasteboard.withUniqueName()
            pasteboard.clearContents()
            pasteboard.writeObjects([url as NSURL])
            if NSPerformService(service, pasteboard) { return }
        }
        guard let appURL else { return }
        NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
    }
}

/// Settings ▸ Developer tools: git status and badges, the Packages page, and Open in
/// Terminal/Editor. Off for new installs (see `AppServices.applyFirstRunDefaults`).
enum DeveloperTools {
    static let key = "developerTools"
    static var isOn: Bool { UserDefaults.standard.bool(forKey: key) }
}
