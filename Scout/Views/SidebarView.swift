import ScoutCore
import SwiftUI

/// Scout's own sidebar: logo, search, collapsible sections, storage at the bottom.
struct SidebarView: View {
    let window: BrowserWindowModel
    let browser: BrowserModel
    @Environment(AppServices.self) private var services
    @AppStorage("collapsedSections") private var collapsedRaw = ""
    @State private var isConfirmingEmptyTrash = false
    @State private var sidebarMessage: String?

    var body: some View {
        sidebar
            .alert("Empty the Trash?", isPresented: $isConfirmingEmptyTrash) {
                Button("Empty Trash", role: .destructive) {
                    let failed = services.emptyTrash()
                    if failed > 0 { sidebarMessage = "\(failed) item\(failed == 1 ? "" : "s") couldn’t be removed." }
                    Task { await browser.reload() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Everything in the Trash is deleted for good. This can’t be undone.")
            }
            .alert("Scout", isPresented: Binding(get: { sidebarMessage != nil }, set: { if !$0 { sidebarMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(sidebarMessage ?? "")
            }
    }

    private func eject(_ place: Place) {
        do {
            if browser.location.filePath.hasPrefix(place.url.filePath) { browser.go(to: services.home) }
            try services.eject(place)
        } catch {
            sidebarMessage = "Couldn’t eject “\(place.name)”: \(error.localizedDescription)"
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                // The real app icon, so the sidebar always matches the Dock.
                Image(nsImage: NSApp.applicationIconImage).resizable().interpolation(.high).frame(width: 24, height: 24)
                Text("Scout").font(.system(size: 15, weight: .semibold, design: .rounded))
                Spacer()
                IconButton(symbol: "gearshape", isOn: browser.mode == .settings, help: "Settings (⌘,)") {
                    browser.showSettings()
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .padding(.top, 4)
            .padding(.bottom, 12)

            SidebarSearchButton { window.isPaletteOpen = true }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    section("Favorites", addHelp: "Add “\(browser.title)” to Favorites (⌃⌘T)",
                            add: browser.isFolder ? { services.addFavorites([browser.location.filePath]) } : nil) {
                        SidebarRow(title: "Recents", symbol: "clock", isSelected: browser.mode == .recents) {
                            browser.showRecents()
                        }
                        .help("Files you opened or downloaded lately (⌥⌘R)")
                        FavoritesList(window: window, browser: browser) { place in
                            placeRow(place) {
                                let favorites = services.favoritePaths
                                Divider()
                                Button("Move Up") { services.moveFavorite(place.id, by: -1) }
                                    .disabled(favorites.first == place.id)
                                Button("Move Down") { services.moveFavorite(place.id, by: 1) }
                                    .disabled(favorites.last == place.id)
                                Button("Remove from Favorites") { services.removeFavorite(place.id) }
                            }
                        }
                    }
                    section("Workspaces", addHelp: "New Workspace (⌥⌘N)", add: { window.newWorkspacePaths = [] }) {
                        ForEach(Array(services.workspaces.enumerated()), id: \.element.id) { index, workspace in
                            SidebarRow(title: workspace.name, symbol: workspace.symbol,
                                       isSelected: browser.workspaceID == workspace.id) {
                                browser.showWorkspace(workspace.id)
                            }
                            .help(index < 9 ? "\(workspace.name) (⌃\(index + 1))" : workspace.name)
                            .contextMenu {
                                Button("Open in New Tab") {
                                    window.newTab()
                                    window.current.showWorkspace(workspace.id)
                                }
                                Divider()
                                Button("Delete Workspace", role: .destructive) { services.deleteWorkspace(workspace.id) }
                            }
                            .dropDestination(for: URL.self) { urls, _ in
                                services.updateWorkspace(workspace.id) { $0.add(urls.map(\.filePath)) }
                                return true
                            }
                        }
                        if services.workspaces.isEmpty {
                            Button { window.newWorkspacePaths = [] } label: {
                                Text("Gather folders from anywhere onto one page")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.tertiary)
                                    .multilineTextAlignment(.leading)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 2)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    let frequent = services.frequent()
                    if !frequent.isEmpty {
                        section("Frequent") {
                            ForEach(frequent) { place in
                                placeRow(place) {
                                    Button("Remove from Frequent") { services.forget(place.id) }
                                }
                            }
                        }
                    }
                    if !services.savedSearches.isEmpty {
                        section("Saved Searches") {
                            ForEach(services.savedSearches) { saved in
                                SidebarRow(title: saved.name, symbol: "magnifyingglass",
                                           isSelected: browser.search?.id == saved.id) {
                                    browser.showSearch(saved)
                                }
                                .help(saved.spec.summary)
                                .contextMenu {
                                    Button("Open in New Tab") {
                                        window.newTab()
                                        window.current.showSearch(saved)
                                    }
                                    Divider()
                                    Button("Remove Saved Search", role: .destructive) { services.removeSearch(saved.id) }
                                }
                            }
                        }
                    }
                    section("Tags") {
                        ForEach(services.allTags) { tag in
                            TagSidebarRow(tag: tag, isSelected: browser.tagName == tag.name) { browser.showTag(tag.name) }
                        }
                    }
                    section("Locations") {
                        ForEach(services.locations) { place in
                            placeRow(place) {
                                if place.isEjectable {
                                    Divider()
                                    Button("Eject “\(place.name)”") { eject(place) }
                                }
                                if place.symbol == "trash" {
                                    Divider()
                                    Button("Empty Trash…") { isConfirmingEmptyTrash = true }
                                }
                            }
                            .overlay(alignment: .trailing) {
                                if place.isEjectable {
                                    Button { eject(place) } label: {
                                        Image(systemName: "eject.fill").font(.system(size: 10)).foregroundStyle(.secondary)
                                            .frame(width: 22, height: 22).contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .help("Eject")
                                    .padding(.trailing, 4)
                                }
                            }
                        }
                    }
                    section("Tools") {
                        SidebarRow(title: "Clean Up", symbol: "sparkles", isSelected: browser.mode == .cleanup) {
                            browser.showCleanup()
                        }
                        .help("Find space you can free up (⇧⌘K)")
                        SidebarRow(title: "Packages", symbol: "shippingbox", isSelected: browser.mode == .packages) {
                            browser.showPackages()
                        }
                        .help("Homebrew and npm: what’s installed and what’s outdated (⌥⌘P)")
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.never)

            StorageMeter(browser: browser, isIndexing: services.isIndexing)
                .padding(10)
        }
    }

    // MARK: - Pieces

    private func placeRow(_ place: Place, @ViewBuilder extraMenu: () -> some View = { EmptyView() }) -> some View {
        SidebarRow(title: place.name, symbol: place.symbol,
                   isSelected: browser.isFolder && browser.location.filePath == place.id) {
            browser.go(to: place.url)
        }
        .contextMenu {
            Button("Open in New Tab") { window.newTab(at: place.url) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([place.url]) }
            Button("Open in \(DevApp.preferredTerminal?.name ?? "Terminal")") { browser.openInTerminal(place.url) }
            OpenInMenu(url: place.url)
            extraMenu()
        }
    }

    private var collapsed: Set<String> {
        Set(collapsedRaw.split(separator: "|").map(String.init))
    }

    @ViewBuilder
    private func section(_ title: String, addHelp: String? = nil, add: (() -> Void)? = nil,
                         @ViewBuilder rows: () -> some View) -> some View {
        let isCollapsed = collapsed.contains(title)
        SectionHeader(title: title, isCollapsed: isCollapsed, addHelp: addHelp, add: add) {
            var set = collapsed
            if isCollapsed { set.remove(title) } else { set.insert(title) }
            withAnimation(.snappy(duration: 0.2)) { collapsedRaw = set.sorted().joined(separator: "|") }
        }
        if !isCollapsed { rows() }
    }
}

struct SidebarRow: View {
    let title: String
    let symbol: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? Color.accentColor : .primary)
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentSoft : (isHovering ? Color.primary.opacity(0.06) : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

/// A tag in the sidebar: its color dot and name.
private struct TagSidebarRow: View {
    let tag: FileTag
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                TagDots(tags: [tag], size: 10).frame(width: 18)
                Text(tag.name).font(.system(size: 13, weight: isSelected ? .semibold : .regular)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? Color.accentColor : .primary)
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentSoft : (isHovering ? Color.primary.opacity(0.06) : .clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

/// Favorites: drop folders on the list to pin them (before the row you drop on, or at the
/// end), drag a favorite onto another to reorder.
private struct FavoritesList<Row: View>: View {
    let window: BrowserWindowModel
    let browser: BrowserModel
    @ViewBuilder let row: (Place) -> Row
    @Environment(AppServices.self) private var services
    @State private var isTargeted = false

    var body: some View {
        let favorites = services.favorites
        VStack(spacing: 1) {
            ForEach(Array(favorites.enumerated()), id: \.element.id) { index, place in
                FavoriteDropRow(index: index) { row(place).draggable(place.url) }
            }
            if favorites.isEmpty {
                Text("Drag folders here to pin them")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 9)
                    .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            }
        }
        .background(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor.opacity(isTargeted ? 0.5 : 0), lineWidth: 1.5))
        .dropDestination(for: URL.self) { urls, _ in
            services.addFavorites(urls.map(\.filePath))
            return true
        } isTargeted: { isTargeted = $0 }
    }
}

/// One favorite that shows an insertion line when something is dragged over it.
private struct FavoriteDropRow<Content: View>: View {
    let index: Int
    @ViewBuilder let content: Content
    @Environment(AppServices.self) private var services
    @State private var isTargeted = false

    var body: some View {
        content
            .overlay(alignment: .top) {
                Capsule().fill(Color.accentColor).frame(height: 2.5).padding(.horizontal, 6).offset(y: -1.5)
                    .opacity(isTargeted ? 1 : 0)
            }
            .dropDestination(for: URL.self) { urls, _ in
                services.addFavorites(urls.map(\.filePath), at: index)
                return true
            } isTargeted: { isTargeted = $0 }
    }
}

private struct SectionHeader: View {
    let title: String
    let isCollapsed: Bool
    var addHelp: String?
    var add: (() -> Void)?
    let toggle: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 4) {
                Text(title.uppercased())
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(0.6)
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    .opacity(isHovering || isCollapsed ? 1 : 0)
                Spacer()
                if let add {
                    Button(action: add) {
                        Image(systemName: "plus").font(.system(size: 10, weight: .bold))
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .opacity(isHovering ? 1 : 0)
                    .help(addHelp ?? "Add")
                }
            }
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 9)
            .padding(.top, 14)
            .padding(.bottom, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

/// The search box at the top of the sidebar. Opens ⌘K.
private struct SidebarSearchButton: View {
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .medium))
                Text("Search").font(.system(size: 13))
                Spacer()
                KeyCap(text: "⌘K")
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.canvas.opacity(isHovering ? 1 : 0.7)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.hairline))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Find any folder or file (⌘K)")
    }
}

/// Free space on the current disk, at the bottom of the sidebar.
private struct StorageMeter: View {
    let browser: BrowserModel
    let isIndexing: Bool
    @State private var capacity: (total: Int64, free: Int64)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "internaldrive").font(.system(size: 11, weight: .medium))
                Text(volumeName).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Spacer()
                if isIndexing {
                    ProgressView().controlSize(.mini).help("Indexing folders for ⌘K")
                }
            }
            if let capacity, capacity.total > 0 {
                GeometryReader { geo in
                    Capsule().fill(Color.primary.opacity(0.08))
                        .overlay(alignment: .leading) {
                            Capsule().fill(Color.accentColor)
                                .frame(width: geo.size.width * CGFloat(capacity.total - capacity.free) / CGFloat(capacity.total))
                        }
                }
                .frame(height: 4)
                Text("\(Format.bytes(capacity.free)) free of \(Format.bytes(capacity.total))")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(.secondary)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
        .task(id: browser.freeSpace) { capacity = Self.capacity(of: browser.location) }
    }

    private var volumeName: String {
        let volume = (try? browser.location.resourceValues(forKeys: [.volumeURLKey]))?.volume ?? URL.folder("/")
        return AppServices.volumeName(volume) ?? "Disk"
    }

    static func capacity(of url: URL) -> (total: Int64, free: Int64)? {
        guard let v = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]),
              let total = v.volumeTotalCapacity, let free = v.volumeAvailableCapacityForImportantUsage else { return nil }
        return (Int64(total), free)
    }
}
