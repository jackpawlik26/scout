import AppKit
import ScoutCore
import SwiftUI

/// Settings, as a page inside Scout (⌘, or the gear in the sidebar).
struct SettingsView: View {
    let window: BrowserWindowModel
    let browser: BrowserModel

    @Environment(AppServices.self) private var services
    @AppStorage("appearance") private var appearance = AppAppearance.system.rawValue
    @AppStorage("viewMode") private var viewMode = ViewMode.list.rawValue
    @AppStorage("foldersFirst") private var foldersFirst = true
    @AppStorage("showHidden") private var showHidden = false
    @AppStorage("terminalApp") private var terminalApp = ""
    @AppStorage("editorApp") private var editorApp = ""
    @State private var isConfirmingClearHistory = false
    @State private var hasFullDiskAccess = Self.checkFullDiskAccess()
    @State private var copied: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                appearanceCard
                browsingCard
                developerCard
                searchCard
                integrationsCard
                aboutCard
            }
            .padding(16)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasFullDiskAccess = Self.checkFullDiskAccess()
        }
        .alert("Clear visit history?", isPresented: $isConfirmingClearHistory) {
            Button("Clear History", role: .destructive) { services.clearHistory() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("⌘K and the Frequent list forget which folders you use most. Your files aren’t touched.")
        }
    }

    // MARK: - Sections

    private var appearanceCard: some View {
        SettingsCard("Appearance", symbol: "circle.lefthalf.filled") {
            HStack(spacing: 14) {
                ForEach(AppAppearance.allCases) { option in
                    AppearanceTile(option: option, isSelected: appearance == option.rawValue) {
                        appearance = option.rawValue
                        option.apply()
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var browsingCard: some View {
        SettingsCard("Browsing", symbol: "folder") {
            SettingRow("View new tabs as") {
                Picker("", selection: Binding(get: { viewMode }, set: { value in
                    viewMode = value
                    if let mode = ViewMode(rawValue: value) { browser.viewMode = mode }
                })) {
                    Text("List").tag(ViewMode.list.rawValue)
                    Text("Icons").tag(ViewMode.icons.rawValue)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            Divider()
            SettingRow("Keep folders on top", detail: "Folders first, then files. The View menu changes it for one tab.") {
                Toggle("", isOn: Binding(get: { foldersFirst }, set: { on in
                    foldersFirst = on
                    for tab in allTabs { tab.foldersFirst = on }
                }))
                .toggleStyle(.switch).labelsHidden()
            }
            Divider()
            SettingRow("Show hidden files", detail: "Files whose names start with a dot. ⇧⌘. changes it for one tab.") {
                Toggle("", isOn: Binding(get: { showHidden }, set: { on in
                    showHidden = on
                    for tab in allTabs where tab.showHidden != on { tab.showHidden = on }
                }))
                .toggleStyle(.switch).labelsHidden()
            }
            Divider()
            SettingRow("Sidebar", detail: "⌃⌘S") {
                Toggle("", isOn: Binding(get: { window.isSidebarShown }, set: { on in
                    withAnimation(.snappy(duration: 0.25)) { window.isSidebarShown = on }
                }))
                .toggleStyle(.switch).labelsHidden()
            }
            Divider()
            SettingRow("Info panel", detail: "⌘I") {
                Toggle("", isOn: Binding(get: { window.isInspectorShown }, set: { on in
                    withAnimation(.snappy(duration: 0.25)) { window.isInspectorShown = on }
                }))
                .toggleStyle(.switch).labelsHidden()
            }
        }
    }

    private var developerCard: some View {
        SettingsCard("Developer", symbol: "chevron.left.forwardslash.chevron.right") {
            appPicker("Terminal", detail: "Open in Terminal (⌥⇧⌘T) and package upgrades", kind: .terminal,
                      current: DevApp.preferredTerminal, selection: $terminalApp)
            Divider()
            appPicker("Code editor", detail: "Open in Editor (⌥⇧⌘E)", kind: .editor,
                      current: DevApp.preferredEditor, selection: $editorApp)
        }
    }

    private var searchCard: some View {
        SettingsCard("Search & History", symbol: "magnifyingglass") {
            SettingRow("Jump index", detail: services.isIndexing ? "Indexing…"
                       : "\(services.folders.count.formatted()) folders. Refreshes every 30 minutes.") {
                Button("Rebuild Now") { Task { await services.rebuildIndex() } }
                    .disabled(services.isIndexing)
            }
            Divider()
            SettingRow("Visit history", detail: "Ranks ⌘K results and the Frequent list. Stays on this Mac.") {
                Button("Clear…") { isConfirmingClearHistory = true }
            }
            Divider()
            SettingRow("Full Disk Access", detail: hasFullDiskAccess
                       ? "On. Scout can open every folder and see inside the Trash."
                       : "Off. Some folders (Mail, Safari, the Trash) stay locked.") {
                if hasFullDiskAccess {
                    Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Button("Open Settings…") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                    }
                }
            }
        }
    }

    private var integrationsCard: some View {
        let cli = services.homePath + "/.local/bin/scout"
        let hasCLI = FileManager.default.fileExists(atPath: cli)
        return SettingsCard("Integrations", symbol: "link") {
            SettingRow("Command line", detail: hasCLI ? "`scout` is installed in ~/.local/bin. Try: cd \"$(scout jump proj)\""
                       : "Run scripts/install.sh to install the `scout` command.") {
                if hasCLI { Label("Installed", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            }
            Divider()
            SettingRow("Links", detail: "Raycast, Shortcuts or any app can open scout:// links.") {
                Menu(copied.map { "Copied \($0)" } ?? "Copy a Link") {
                    linkButton("Open this folder", ScoutLink.open(path: PathDisplay.display(browser.location.filePath,
                                                                                           home: services.homePath), newTab: false))
                    linkButton("Jump palette", .jump(query: nil))
                    linkButton("Clean Up", .cleanup)
                    linkButton("Packages", .packages)
                }
                .fixedSize()
            }
        }
    }

    private var aboutCard: some View {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return Card(spacing: 0) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().interpolation(.high).frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Scout").font(.system(size: 17, weight: .semibold, design: .rounded))
                    Text("Version \(version) (\(build))").foregroundStyle(.secondary)
                    Text("Your files, found fast.").font(.caption).foregroundStyle(.tertiary)
                }
                Spacer()
            }
        }
    }

    // MARK: - Helpers

    private var allTabs: [BrowserModel] { window.panes.flatMap(\.tabs) }

    @ViewBuilder
    private func appPicker(_ title: String, detail: String, kind: DevApp.Kind, current: DevApp?,
                           selection: Binding<String>) -> some View {
        let apps = DevApp.installed(kind)
        SettingRow(title, detail: detail) {
            if apps.isEmpty {
                Text("None installed").foregroundStyle(.secondary)
            } else {
                Picker("", selection: Binding(get: { current?.id ?? "" }, set: { selection.wrappedValue = $0 })) {
                    ForEach(apps) { app in
                        Label {
                            Text(app.name)
                        } icon: {
                            if let icon = app.icon { Image(nsImage: icon) }
                        }
                        .tag(app.id)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
        }
    }

    private func linkButton(_ title: String, _ link: ScoutLink) -> some View {
        Button(title) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(link.url.absoluteString, forType: .string)
            copied = title
        }
    }

    /// Reading the Trash needs Full Disk Access, so it's a cheap check.
    static func checkFullDiskAccess() -> Bool {
        let trash = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".Trash").filePath
        return (try? FileManager.default.contentsOfDirectory(atPath: trash)) != nil
    }
}

/// A titled card of settings rows.
private struct SettingsCard<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    init(_ title: String, symbol: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            Card(spacing: 10) { content }
        }
    }
}

/// Title (and optional explanation) on the left, control on the right.
private struct SettingRow<Control: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder let control: Control

    init(_ title: String, detail: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.detail = detail
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13))
                if let detail {
                    Text(LocalizedStringKey(detail)).font(.system(size: 11.5)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            control
        }
    }
}

/// A little picture of Scout in light, dark, or both (Match System).
private struct AppearanceTile: View {
    let option: AppAppearance
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                preview
                    .frame(width: 128, height: 82)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .strokeBorder(isSelected ? Color.accentColor : Color.hairline, lineWidth: isSelected ? 2.5 : 1)
                    )
                Text(option.title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var preview: some View {
        switch option {
        case .light: MiniWindow(dark: false)
        case .dark: MiniWindow(dark: true)
        case .system:
            ZStack {
                MiniWindow(dark: false)
                MiniWindow(dark: true)
                    .mask(GeometryReader { geo in
                        Path { path in
                            path.move(to: CGPoint(x: geo.size.width * 0.62, y: 0))
                            path.addLine(to: CGPoint(x: geo.size.width, y: 0))
                            path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                            path.addLine(to: CGPoint(x: geo.size.width * 0.38, y: geo.size.height))
                        }
                    })
            }
        }
    }
}

/// A tiny Scout window: sidebar, card, a few file rows.
private struct MiniWindow: View {
    let dark: Bool

    var body: some View {
        let chrome = dark ? Color(white: 0.13) : Color(red: 0.94, green: 0.94, blue: 0.97)
        let card = dark ? Color(white: 0.19) : .white
        let line = dark ? Color.white.opacity(0.16) : Color.black.opacity(0.1)
        HStack(spacing: 5) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 2.5) {
                    ForEach([Color.red, .yellow, .green], id: \.self) { Circle().fill($0.opacity(0.85)).frame(width: 4, height: 4) }
                }
                .padding(.bottom, 3)
                RoundedRectangle(cornerRadius: 2).fill(Color.accentColor.opacity(0.85)).frame(width: 24, height: 5)
                ForEach(0..<4, id: \.self) { _ in RoundedRectangle(cornerRadius: 2).fill(line).frame(width: 22, height: 4) }
                Spacer()
            }
            .padding(.leading, 6).padding(.top, 6)
            VStack(alignment: .leading, spacing: 5) {
                RoundedRectangle(cornerRadius: 2).fill(line.opacity(2)).frame(width: 34, height: 6)
                ForEach(0..<4, id: \.self) { index in
                    HStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 1).fill(Color.blue.opacity(0.6)).frame(width: 5, height: 5)
                        RoundedRectangle(cornerRadius: 2).fill(line).frame(width: CGFloat(44 - index * 6), height: 4)
                    }
                }
                Spacer()
            }
            .padding(7)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(card, in: RoundedRectangle(cornerRadius: 5))
            .padding([.top, .trailing, .bottom], 5)
        }
        .background(chrome)
    }
}
