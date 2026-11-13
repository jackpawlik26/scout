import ScoutCore
import SwiftUI

/// Root of each window. Restores the last folder the window was showing.
struct BrowserWindow: View {
    @Environment(AppServices.self) private var services
    @SceneStorage("scout.location") private var savedLocation = ""
    @State private var window: BrowserWindowModel?
    /// A link that arrived before this window finished setting up.
    @State private var pendingLink: ScoutLink?

    var body: some View {
        Group {
            if let window {
                BrowserContent(window: window)
            } else {
                Color.clear
            }
        }
        .onAppear {
            AppAppearance.saved.apply()
            guard window == nil else { return }
            var start = services.home
            if !savedLocation.isEmpty, FileManager.default.fileExists(atPath: savedLocation) {
                start = .folder(savedLocation)
            }
            let model = BrowserWindowModel(services: services, start: start)
            window = model
            if let pendingLink {
                model.handle(pendingLink)
                self.pendingLink = nil
            }
        }
        // scout:// links go to an existing window instead of opening a new one.
        .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        .onOpenURL { url in
            guard let link = ScoutLink(url: url) else { return }
            if let window { window.handle(link) } else { pendingLink = link }
        }
        .onChange(of: window?.current.location) { _, location in
            if let location { savedLocation = location.filePath }
        }
    }
}

/// The window layout: sidebar on the tinted chrome, one or two panes as rounded
/// cards (⌘D splits), and the info panel as a card on the right.
struct BrowserContent: View {
    @Bindable var window: BrowserWindowModel
    @Environment(AppServices.self) private var services
    @State private var newWorkspaceName = ""

    var body: some View {
        let browser = window.current
        HStack(spacing: 0) {
            if window.isSidebarShown {
                SidebarView(window: window, browser: browser)
                    .frame(width: 236)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            VStack(spacing: 0) {
                if !window.isSidebarShown {
                    // No sidebar: the traffic lights and the "show sidebar" button get
                    // their own strip of chrome instead of sitting on top of the card.
                    HStack(spacing: 4) {
                        Color.clear.frame(width: Layout.trafficLightsWidth)
                        IconButton(symbol: "sidebar.left", help: "Show Sidebar (⌃⌘S)") {
                            withAnimation(.snappy(duration: 0.25)) { window.isSidebarShown = true }
                        }
                        WindowDragArea()
                    }
                    .frame(height: Layout.titleRowHeight)
                }
                HStack(spacing: Layout.gutter) {
                    ForEach(window.panes) { pane in
                        PaneCard(window: window, pane: pane)
                    }
                    if window.isInspectorShown {
                        InspectorView(browser: browser)
                            .frame(width: 300)
                            .canvasCard()
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .padding(.top, window.isSidebarShown ? Layout.gutter : 0)
                .padding(.bottom, Layout.gutter)
                .padding(.trailing, Layout.gutter)
                .padding(.leading, window.isSidebarShown ? 0 : Layout.gutter)
            }
        }
        .background(Color.chrome)
        .ignoresSafeArea()
        .frame(minWidth: 780, minHeight: 480)
        .animation(.snappy(duration: 0.25), value: window.panes.count)
        .overlay {
            if window.isPaletteOpen {
                CommandPalette(window: window)
            }
        }
        .sheet(isPresented: $window.isGoToPathOpen) {
            GoToPathView(window: window)
        }
        .alert("New Workspace", isPresented: newWorkspaceBinding) {
            TextField("Name", text: $newWorkspaceName)
            Button("Create") {
                let name = newWorkspaceName.trimmingCharacters(in: .whitespaces)
                let workspace = services.createWorkspace(
                    name: name.isEmpty ? "Untitled Workspace" : name,
                    symbol: Workspace.symbols[services.workspaces.count % Workspace.symbols.count],
                    paths: window.newWorkspacePaths ?? [])
                window.current.showWorkspace(workspace.id)
                newWorkspaceName = ""
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) { newWorkspaceName = "" }
        } message: {
            Text("Gather folders and files from anywhere onto one page. Nothing gets moved.")
        }
        .focusedSceneValue(\.browserWindow, window)
    }

    private var newWorkspaceBinding: Binding<Bool> {
        Binding(get: { window.newWorkspacePaths != nil }, set: { if !$0 { window.newWorkspacePaths = nil } })
    }
}

/// One pane as a card. When split, the active pane gets an accent outline.
private struct PaneCard: View {
    let window: BrowserWindowModel
    let pane: PaneModel

    var body: some View {
        let isFocused = window.isSplit && window.focusedPaneID == pane.id
        BrowserPane(window: window, pane: pane, browser: pane.current)
            .id(pane.current.id)
            .canvasCard()
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor.opacity(isFocused ? 0.55 : 0), lineWidth: 1.5)
            )
            .simultaneousGesture(TapGesture().onEnded { window.focus(pane) })
            .transition(.move(edge: .trailing).combined(with: .opacity))
    }
}

/// Tabs as pills under the header, shown once a pane has more than one (⌘T).
struct TabStrip: View {
    @Bindable var pane: PaneModel

    var body: some View {
        HStack(spacing: 4) {
            ForEach(pane.tabs) { tab in
                TabButton(
                    title: tab.title,
                    iconPath: tab.isFolder ? tab.location.filePath : nil,
                    isSelected: tab.id == pane.selectedTabID,
                    select: { pane.selectedTabID = tab.id },
                    close: { pane.closeTab(tab.id) }
                )
            }
            IconButton(symbol: "plus", help: "New Tab (⌘T)") { pane.newTab() }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }
}

private struct TabButton: View {
    let title: String
    /// Folder whose icon to show; nil for search tabs.
    let iconPath: String?
    let isSelected: Bool
    let select: () -> Void
    let close: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            if let iconPath {
                Image(nsImage: IconCache.icon(forPath: iconPath)).resizable().frame(width: 15, height: 15)
            } else {
                Image(systemName: "square.stack.3d.up").font(.system(size: 11, weight: .medium))
            }
            Text(title).font(.system(size: 12.5, weight: isSelected ? .semibold : .regular)).lineLimit(1)
            Spacer(minLength: 0)
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 8.5, weight: .bold))
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(Color.primary.opacity(isHovering ? 0.08 : 0)))
            }
            .buttonStyle(.plain)
            .opacity(isHovering || isSelected ? 1 : 0)
        }
        .foregroundStyle(isSelected ? .primary : .secondary)
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(height: 28)
        .frame(maxWidth: 220)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.raised : (isHovering ? Color.primary.opacity(0.04) : .clear))
        )
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isSelected ? Color.hairline : .clear))
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .onHover { isHovering = $0 }
    }
}
