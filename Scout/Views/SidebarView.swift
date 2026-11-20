import ScoutCore
import SwiftUI

/// Scout's own sidebar: logo, search, collapsible sections, storage at the bottom.
struct SidebarView: View {
    let window: BrowserWindowModel
    let browser: BrowserModel
    @Environment(AppServices.self) private var services
    @AppStorage("collapsedSections") private var collapsedRaw = ""
    @AppStorage(DeveloperTools.key) private var developerTools = false
    @State private var isConfirmingEmptyTrash = false
    @State private var isAddingBucket = false
    @State private var removingBucket: BucketConfig?
    @State private var sidebarMessage: String?

    var body: some View {
        sidebar
            .sheet(isPresented: $isAddingBucket) {
                AddBucketView { id in browser.showBucket(id) }
            }
            .alert("Remove this bucket from Scout?", isPresented: Binding(get: { removingBucket != nil },
                                                                     set: { if !$0 { removingBucket = nil } })) {
                Button("Remove", role: .destructive) {
                    if let bucket = removingBucket { services.removeBucket(bucket.id) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Scout forgets the connection and its key. Nothing in the bucket is deleted.")
            }
            .alert("Empty the Trash?", isPresented: $isConfirmingEmptyTrash) {
                Button("Empty Trash", role: .destructive) {
                    Task {
                        let failed = await services.emptyTrash()
                        if failed > 0 { sidebarMessage = "\(failed) item\(failed == 1 ? "" : "s") couldn’t be removed." }
                        await browser.reload()
                    }
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
                Text("Scout").font(.system(size: 14, weight: .medium))
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
                            placeRow(place, dropsInto: false) {
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
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.textSubtle)
                                    .multilineTextAlignment(.leading)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 2)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    let choiceFields = services.customizations.fields.filter { $0.kind == .choice }
                    ForEach(choiceFields) { field in
                        let counts = services.customizations.counts(for: field.id)
                        section(field.name, addHelp: "Edit “\(field.name)”", add: { window.fieldEditor = FieldEditorRequest(field: field) }) {
                            ForEach(field.choices, id: \.self) { choice in
                                SidebarRow(title: choice, symbol: "circle.fill",
                                           isSelected: browser.fieldGroup.map { $0.field == field.id && $0.value == choice } ?? false) {
                                    browser.showFieldGroup(field.id, choice)
                                }
                                .overlay(alignment: .trailing) {
                                    if let count = counts[choice] {
                                        Text("\(count)").font(.ui(11)).foregroundStyle(Color.textSubtle).monospacedDigit().padding(.trailing, 9)
                                    }
                                }
                                .help("Everything with \(field.name) set to \(choice). Updates as you change it.")
                                .dropDestination(for: URL.self) { urls, _ in
                                    services.setFieldValue(choice, of: field.id, for: urls.filter(\.isFileURL).map(\.filePath))
                                    return true
                                }
                            }
                        }
                    }
                    if !services.savedLayouts.isEmpty {
                        section("Layouts", addHelp: "Save Layout", add: { window.isSavingLayout = true }) {
                            ForEach(Array(services.savedLayouts.enumerated()), id: \.element.id) { index, layout in
                                SidebarRow(title: layout.name, symbol: layout.session.panes.count > 1 ? "rectangle.split.2x1" : "rectangle",
                                           isSelected: false) {
                                    window.open(layout)
                                }
                                .help("\(layout.summary)\(index < 9 ? " (⌥⌘\(index + 1))" : "")")
                                .contextMenu {
                                    Button("Update to This Window") { services.updateLayout(layout.id, session: window.session) }
                                    Divider()
                                    Button("Delete Layout", role: .destructive) { services.deleteLayout(layout.id) }
                                }
                            }
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
                    if !services.tagsInUse.isEmpty {
                    section("Tags") {
                        ForEach(services.tagsInUse) { tag in
                            TagSidebarRow(tag: tag, isSelected: browser.tagName == tag.name) { browser.showTag(tag.name) }
                        }
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
                                        Image(systemName: "eject.fill").font(.system(size: 10, weight: .medium)).foregroundStyle(Color.textSubtle)
                                            .frame(width: 22, height: 22).contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .help("Eject")
                                    .padding(.trailing, 4)
                                }
                            }
                        }
                    }
                    section("Buckets") {
                        ForEach(services.buckets) { bucket in
                            SidebarRow(title: bucket.name, symbol: "cloud", isSelected: browser.bucketID == bucket.id) {
                                browser.showBucket(bucket.id)
                            }
                            .contextMenu {
                                Button("Remove “\(bucket.name)”…") { removingBucket = bucket }
                            }
                            .help("\(bucket.bucket) at \(bucket.endpoint)")
                        }
                        SidebarRow(title: "Add Bucket…", symbol: "plus", isSelected: false) { isAddingBucket = true }
                            .help("Connect Cloudflare R2, Amazon S3 or other S3-compatible storage")
                    }
                    section("Tools") {
                        SidebarRow(title: "Clean Up", symbol: "sparkles", isSelected: browser.mode == .cleanup) {
                            browser.showCleanup()
                        }
                        .help("Find space you can free up (⇧⌘K)")
                        SidebarRow(title: "Triage Downloads", symbol: "tray.and.arrow.down", isSelected: browser.triageFolder != nil) {
                            browser.showTriage()
                        }
                        .help("Go through new downloads one at a time and file them (⌥⌘J)")
                        SidebarRow(title: "History", symbol: "clock.arrow.circlepath", isSelected: browser.mode == .history) {
                            browser.showHistory()
                        }
                        .help("Everything Scout moved, renamed or trashed, with Undo (⌥⌘Y)")
                        if developerTools {
                            SidebarRow(title: "Packages", symbol: "shippingbox", isSelected: browser.mode == .packages) {
                                browser.showPackages()
                            }
                            .help("Homebrew and npm: what’s installed and what’s outdated (⌥⌘P)")
                            SidebarRow(title: "AI Agents", symbol: "sparkle", isSelected: browser.mode == .agents) {
                                browser.showAgents()
                            }
                            .help("Projects set up for Claude Code, Codex and Cursor, with tokens used and running dev servers")
                        }
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

    /// `dropsInto`: files dropped on the row move into the folder (Favorites does its own).
    private func placeRow(_ place: Place, dropsInto: Bool = true,
                          @ViewBuilder extraMenu: () -> some View = { EmptyView() }) -> some View {
        SidebarRow(title: place.name, symbol: place.symbol,
                   isSelected: browser.isFolder && browser.location.filePath == place.id) {
            browser.go(to: place.url)
        }
        .modifier(SidebarFolderDrop(place: place, browser: browser, isEnabled: dropsInto))
        .contextMenu {
            Button("Open in New Tab") { window.newTab(at: place.url) }
            Button("Show in Finder") { FinderBridge.reveal([place.url]) }
            if developerTools {
                Button("Open in \(DevApp.preferredTerminal?.name ?? "Terminal")") { browser.openInTerminal(place.url) }
            }
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
                    .font(.system(size: 13, weight: .regular))
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? Color.textStrong : Color.textSubtle)
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? Color.textStrong : Color.textDefault)
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.bgSelected : (isHovering ? Color.bgSelected.opacity(0.6) : .clear))
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
                Text(tag.name).font(.system(size: 13, weight: isSelected ? .medium : .regular)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? Color.textStrong : Color.textDefault)
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.bgSelected : (isHovering ? Color.bgSelected.opacity(0.6) : .clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

/// Favorites: drop files onto a favorite folder to move them in, or between favorites (or
/// on the list) to pin them there. Dragging a favorite onto another reorders.
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
                FavoriteDropRow(index: index, place: place, isLast: index == favorites.count - 1, browser: browser) {
                    row(place).draggable(place.url)
                }
            }
            if favorites.isEmpty {
                Text("Drag folders here to pin them")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textSubtle)
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

/// Where a drag over a favorite lands: pinned above or below it, or moved into it.
private enum FavoriteDropZone { case before, after, into }

/// One favorite: an insertion line near its edges (pin or reorder), a ring over the middle
/// of a folder (move into it, and it opens after a moment's hover so you can go deeper).
private struct FavoriteDropRow<Content: View>: View {
    let index: Int
    let place: Place
    let isLast: Bool
    let browser: BrowserModel
    @ViewBuilder let content: Content
    @Environment(AppServices.self) private var services
    @State private var zone: FavoriteDropZone?
    @State private var height: CGFloat = 28
    @State private var spring: Task<Void, Never>?

    var body: some View {
        content
            .overlay(alignment: .top) { insertionLine(zone == .before).offset(y: -1.5) }
            .overlay(alignment: .bottom) { insertionLine(zone == .after).offset(y: 1.5) }
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: 2)
                .opacity(zone == .into ? 1 : 0).allowsHitTesting(false))
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
            .onDrop(of: [.fileURL], delegate: FavoriteDropDelegate(
                index: index, place: place, isLast: isLast, height: height, browser: browser, services: services,
                zone: $zone, spring: $spring))
    }

    private func insertionLine(_ isOn: Bool) -> some View {
        Capsule().fill(Color.accentColor).frame(height: 2.5).padding(.horizontal, 6).opacity(isOn ? 1 : 0)
    }
}

private struct FavoriteDropDelegate: DropDelegate {
    let index: Int
    let place: Place
    let isLast: Bool
    let height: CGFloat
    let browser: BrowserModel
    let services: AppServices
    @Binding var zone: FavoriteDropZone?
    @Binding var spring: Task<Void, Never>?

    /// The files being dragged, readable while the drag is still in the air.
    private var dragged: [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        return NSPasteboard(name: .drag).readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []
    }

    private func zone(at y: CGFloat) -> FavoriteDropZone {
        let urls = dragged
        let reordering = !urls.isEmpty && urls.allSatisfy { services.isFavorite($0.filePath) }
        if reordering || !place.url.hasDirectoryPath { return y < height / 2 ? .before : .after }
        if y < height * 0.25 { return .before }
        if isLast && y > height * 0.75 { return .after }
        return .into
    }

    func dropEntered(info: DropInfo) { update(zone(at: info.location.y)) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let next = zone(at: info.location.y)
        update(next)
        let copies = next != .into || NSEvent.modifierFlags.contains(.option)
        return DropProposal(operation: copies ? .copy : .move)
    }

    func dropExited(info: DropInfo) { update(nil) }

    func performDrop(info: DropInfo) -> Bool {
        let target = zone(at: info.location.y)
        update(nil)
        let urls = dragged
        if !urls.isEmpty { return apply(target, urls) }
        // Not on the drag pasteboard: load the URLs from the drop itself.
        let providers = info.itemProviders(for: [.fileURL])
        guard !providers.isEmpty else { return false }
        Task { @MainActor in
            var loaded: [URL] = []
            for provider in providers {
                let url: URL? = await withCheckedContinuation { done in
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in done.resume(returning: url) }
                }
                if let url { loaded.append(url) }
            }
            if !loaded.isEmpty { _ = apply(target, loaded) }
        }
        return true
    }

    private func apply(_ target: FavoriteDropZone, _ urls: [URL]) -> Bool {
        switch target {
        case .into: return browser.receiveDrop(urls.filter { !services.isSidebarPlace($0.filePath) }, into: place.url)
        case .before: services.addFavorites(urls.map(\.filePath), at: index)
        case .after: services.addFavorites(urls.map(\.filePath), at: index + 1)
        }
        return true
    }

    private func update(_ next: FavoriteDropZone?) {
        guard next != zone else { return }
        zone = next
        spring?.cancel()
        spring = nil
        guard next == .into else { return }
        let url = place.url
        spring = Task { [browser] in
            try? await Task.sleep(for: .seconds(1))
            if !Task.isCancelled { browser.go(to: url) }
        }
    }
}

/// A sidebar folder (Locations, Frequent) that takes drops: files move into it (copy across
/// disks, ⌥ copies), the Trash trashes them, and it opens after a moment's hover.
private struct SidebarFolderDrop: ViewModifier {
    let place: Place
    let browser: BrowserModel
    let isEnabled: Bool
    @Environment(AppServices.self) private var services
    @State private var isTargeted = false
    @State private var spring: Task<Void, Never>?

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: 2)
                    .opacity(isTargeted ? 1 : 0).allowsHitTesting(false))
                .dropDestination(for: URL.self) { urls, _ in
                    spring?.cancel()
                    // A sidebar place dragged here was being rearranged, not filed away.
                    let urls = urls.filter { $0.isFileURL && !services.isSidebarPlace($0.filePath) }
                    guard !urls.isEmpty else { return false }
                    if place.symbol == "trash" { return browser.trash(urls) > 0 }
                    return browser.receiveDrop(urls, into: place.url)
                } isTargeted: { targeted in
                    isTargeted = targeted
                    spring?.cancel()
                    guard targeted else { return }
                    spring = Task {
                        try? await Task.sleep(for: .seconds(1))
                        if !Task.isCancelled { browser.go(to: place.url) }
                    }
                }
        } else {
            content
        }
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
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .medium))
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    .opacity(isHovering || isCollapsed ? 1 : 0)
                Spacer()
                if let add {
                    Button(action: add) {
                        Image(systemName: "plus").font(.system(size: 10, weight: .medium))
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .opacity(isHovering ? 1 : 0)
                    .help(addHelp ?? "Add")
                }
            }
            .foregroundStyle(Color.textSubtle)
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
                Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .regular))
                Text("Search").font(.system(size: 13))
                Spacer()
                KeyCap(text: "⌘K")
            }
            .foregroundStyle(Color.textSubtle)
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
                Image(systemName: "internaldrive").font(.system(size: 11, weight: .regular))
                Text(volumeName).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Spacer()
                if isIndexing {
                    ProgressView().controlSize(.mini).help("Indexing folders for ⌘K")
                }
            }
            if let capacity, capacity.total > 0 {
                GeometryReader { geo in
                    Capsule().fill(Color.bgSelected)
                        .overlay(alignment: .leading) {
                            Capsule().fill(Color.accentColor)
                                .frame(width: geo.size.width * CGFloat(capacity.total - capacity.free) / CGFloat(capacity.total))
                        }
                }
                .frame(height: 4)
                Text("\(Format.bytes(capacity.free)) free of \(Format.bytes(capacity.total))")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textSubtle)
            }
        }
        .foregroundStyle(Color.textSubtle)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.bgSelected))
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
