import AppKit
import ScoutCore

/// A command ⌘K can run: any item in Scout's menus, or one of your scripts.
struct PaletteCommand: Identifiable {
    let id: String
    let title: String
    /// Where it lives ("File", "View ▸ Group By") or "Your action".
    let detail: String
    /// "⇧⌘N", shown on the right.
    let shortcut: String
    let symbol: String
    let isEnabled: Bool
    let run: @MainActor () -> Void
}

/// Every command in the menu bar, read from the menus themselves so new commands show
/// up in ⌘K without being listed anywhere else.
enum MenuCommands {
    /// Menus that hold lists rather than commands.
    private static let skippedMenus: Set<String> = ["Services", "Open Recent", "Window"]

    @MainActor
    static func all() -> [PaletteCommand] {
        guard let main = NSApp.mainMenu else { return [] }
        var commands: [PaletteCommand] = []
        for top in main.items {
            guard let menu = top.submenu, !skippedMenus.contains(top.title) else { continue }
            collect(menu, path: top.title == "Scout" ? "Scout" : top.title, into: &commands)
        }
        return commands
    }

    @MainActor
    private static func collect(_ menu: NSMenu, path: String, into commands: inout [PaletteCommand]) {
        menu.update() // ask each item whether it applies right now
        for (index, item) in menu.items.enumerated() {
            guard !item.isSeparatorItem, !item.isHidden, !item.isAlternate, !item.title.isEmpty else { continue }
            if let submenu = item.submenu {
                guard !skippedMenus.contains(item.title) else { continue }
                collect(submenu, path: path + " ▸ " + item.title, into: &commands)
                continue
            }
            // "Quit Scout", "Hide Others"… are better left to their keys.
            if ["Quit Scout", "Hide Scout", "Hide Others", "Show All"].contains(item.title) { continue }
            commands.append(PaletteCommand(
                id: "menu:\(path)/\(item.title)",
                title: item.title.replacingOccurrences(of: "…", with: ""),
                detail: path,
                shortcut: shortcut(item),
                symbol: item.state == .on ? "checkmark" : "command",
                isEnabled: item.isEnabled,
                run: { [weak menu] in
                    // On the next turn of the run loop, after the palette has closed.
                    DispatchQueue.main.async {
                        guard let menu, menu.items.indices.contains(index) else { return }
                        menu.performActionForItem(at: index)
                    }
                }
            ))
        }
    }

    static func shortcut(_ item: NSMenuItem) -> String {
        guard !item.keyEquivalent.isEmpty else { return "" }
        let m = item.keyEquivalentModifierMask
        var text = ""
        if m.contains(.control) { text += "⌃" }
        if m.contains(.option) { text += "⌥" }
        if m.contains(.shift) { text += "⇧" }
        if m.contains(.command) { text += "⌘" }
        let key: String = switch item.keyEquivalent {
        case "\u{8}", "\u{7f}": "⌫"
        case "\r": "↵"
        case "\t": "⇥"
        case " ": "Space"
        case "\u{1b}": "Esc"
        case String(UnicodeScalar(NSUpArrowFunctionKey)!): "↑"
        case String(UnicodeScalar(NSDownArrowFunctionKey)!): "↓"
        case String(UnicodeScalar(NSLeftArrowFunctionKey)!): "←"
        case String(UnicodeScalar(NSRightArrowFunctionKey)!): "→"
        default: item.keyEquivalent.uppercased()
        }
        return text + key
    }
}
