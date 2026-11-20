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
    /// Words that open a folder in this app from Go to Path ("code .").
    var commands: [String] = []

    static let known: [DevApp] = [
        DevApp(id: "so.stencil.tern", name: "Tern", kind: .terminal, service: "Open in Tern", commands: ["tern"]),
        DevApp(id: "com.mitchellh.ghostty", name: "Ghostty", kind: .terminal, commands: ["ghostty"]),
        DevApp(id: "com.googlecode.iterm2", name: "iTerm", kind: .terminal, service: "New iTerm2 Tab Here", commands: ["iterm", "iterm2"]),
        DevApp(id: "dev.warp.Warp-Stable", name: "Warp", kind: .terminal, commands: ["warp"]),
        DevApp(id: "com.apple.Terminal", name: "Terminal", kind: .terminal),
        DevApp(id: "com.todesktop.230313mzl4w4u92", name: "Cursor", kind: .editor, commands: ["cursor"]),
        DevApp(id: "com.microsoft.VSCode", name: "VS Code", kind: .editor, commands: ["code", "vscode"]),
        DevApp(id: "com.microsoft.VSCodeInsiders", name: "VS Code Insiders", kind: .editor, commands: ["code-insiders"]),
        DevApp(id: "com.exafunction.windsurf", name: "Windsurf", kind: .editor, commands: ["windsurf"]),
        DevApp(id: "dev.zed.Zed", name: "Zed", kind: .editor, commands: ["zed"]),
        DevApp(id: "com.sublimetext.4", name: "Sublime Text", kind: .editor, commands: ["subl", "sublime"]),
        DevApp(id: "com.panic.Nova", name: "Nova", kind: .editor, commands: ["nova"]),
        DevApp(id: "com.barebones.bbedit", name: "BBEdit", kind: .editor, commands: ["bbedit"]),
        DevApp(id: "com.apple.dt.Xcode", name: "Xcode", kind: .editor, commands: ["xed", "xcode"]),
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

    /// Command words for Go to Path: each installed app's own words, plus "terminal" and
    /// "edit" for your preferred terminal and editor, and "finder" to show it in Finder.
    static var pathBarCommands: Set<String> {
        Set(known.filter { $0.appURL != nil }.flatMap(\.commands)).union(["terminal", "term", "edit", "editor", "finder"])
    }

    /// The app a Go to Path command word opens (nil for "finder", handled by the caller).
    static func app(forCommand word: String) -> DevApp? {
        switch word {
        case "terminal", "term": preferredTerminal
        case "edit", "editor": preferredEditor
        default: known.first { $0.commands.contains(word) && $0.appURL != nil }
        }
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
