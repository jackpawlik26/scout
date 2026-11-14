import SwiftUI

/// ⌘/: every keyboard shortcut on one sheet. Esc or ⌘/ closes it.
struct ShortcutsView: View {
    let window: BrowserWindowModel

    private struct ShortcutGroup: Identifiable {
        let title: String
        let rows: [(keys: String, action: String)]
        var id: String { title }
    }

    private var hotKey: String {
        let preset = GlobalHotKey.Preset.saved
        return preset == .off ? "Off (Settings)" : preset.title
    }

    private var groups: [ShortcutGroup] {
        [
            ShortcutGroup(title: "Find", rows: [
                ("⌘K", "Jump to any folder or file"),
                (hotKey, "Jump from any app"),
                ("⇧⌘F", "Find files"),
                ("⌘L", "Go to a path (Tab completes)"),
                ("⌘F", "Filter this folder"),
                ("⌥⌘R", "Recents"),
                ("a–z", "Type a name to select it"),
            ]),
            ShortcutGroup(title: "Move around", rows: [
                ("↑ ↓ ← →", "Move the selection"),
                ("⌘O  ⌘↩  ⌘↓", "Open (⌃↩ too)"),
                ("⌘↑", "Enclosing folder"),
                ("⌘[  ⌘]", "Back, forward"),
                ("⇧⌘H ⇧⌘D ⇧⌘O", "Home, Desktop, Docs"),
                ("⌥⌘L ⇧⌘A", "Downloads, Applications"),
            ]),
            ShortcutGroup(title: "Files", rows: [
                ("Space", "Quick Look"),
                ("Return", "Rename"),
                ("⇧⌘N", "New folder"),
                ("⌘C  ⌘V  ⌥⌘V", "Copy, paste, move here"),
                ("⇧⌘M  ⌥⇧⌘M", "Move to…, copy to…"),
                ("⌃⌘A  ⇧⌘R", "Make alias, AirDrop"),
                ("⌥⌘C", "Copy path"),
                ("⌘⌫", "Move to Trash (⌘Z undoes)"),
            ]),
            ShortcutGroup(title: "Tabs & panes", rows: [
                ("⌘T  ⌘W", "New tab, close tab"),
                ("⇧⌘]  ⇧⌘[", "Next, previous tab"),
                ("⌘D", "Split view"),
                ("⌥⇥  ⌘U", "Switch pane, swap panes"),
                ("F5  F6", "Copy, move to the other pane"),
                ("⌃1–9", "Workspaces"),
            ]),
            ShortcutGroup(title: "View", rows: [
                ("⌘1  ⌘2  ⌘3", "List, icons, columns"),
                ("⌘I", "Info panel"),
                ("⌃⌘S", "Sidebar"),
                ("⌃⌘0–8", "Group by kind, date, size…"),
                ("⇧⌘.", "Hidden files"),
                ("⌘,", "Settings"),
                ("⌘/", "This list"),
            ]),
            ShortcutGroup(title: "Tools", rows: [
                ("⇧⌘K", "Clean Up"),
                ("⌥⌘P", "Packages"),
                ("⌥⌘G", "Git changes"),
                ("⌥⌘T", "Tidy folder"),
                ("⌥⌘S", "Shelf"),
                ("⌥⇧⌘T", "Open in Terminal"),
                ("⌥⇧⌘E", "Open in Editor"),
                ("⌘R", "Show in Finder"),
            ]),
        ]
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.12)
                .ignoresSafeArea()
                .onTapGesture { close() }

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Keyboard Shortcuts").font(.system(size: 16, weight: .medium))
                    Spacer()
                    Text("Esc to close").font(.ui(12)).foregroundStyle(Color.textSubtle)
                }
                Grid(alignment: .topLeading, horizontalSpacing: 28, verticalSpacing: 18) {
                    ForEach(0..<2) { row in
                        GridRow {
                            ForEach(groups[(row * 3)..<(row * 3 + 3)]) { group in
                                groupView(group)
                            }
                        }
                    }
                }
            }
            .padding(22)
            .frame(width: 820)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
            .shadow(color: .black.opacity(0.25), radius: 30, y: 12)
        }
        .onWindowKey(.escape) {
            close()
            return true
        }
    }

    private func groupView(_ group: ShortcutGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(group.title.uppercased())
                .font(.system(size: 12, weight: .medium))
                .tracking(0.6)
                .foregroundStyle(Color.textSubtle)
                .padding(.bottom, 2)
            ForEach(group.rows, id: \.action) { row in
                HStack(spacing: 8) {
                    Text(row.keys)
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.bgSelected))
                        .fixedSize()
                    Text(row.action)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textSubtle)
                        .lineLimit(1)
                }
            }
        }
        .frame(width: 236, alignment: .leading)
    }

    private func close() { window.isShortcutsOpen = false }
}
