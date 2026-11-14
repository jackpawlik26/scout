import AppKit
import CoreServices
import ScoutCore
import SwiftUI

/// Clean Up: finds space you can get back, says why each item is there, and
/// moves only what you tick to the Trash (⌘Z puts it back).
struct CleanupView: View {
    let browser: BrowserModel

    @State private var groups: [CleanupKind: [CleanupItem]] = [:]
    @State private var scanning: Set<CleanupKind> = Set(CleanupKind.allCases)
    @State private var selected: Set<String> = []
    @State private var expanded: Set<CleanupKind> = []
    @State private var trash: TrashInfo?
    @State private var isConfirmingEmptyTrash = false
    @State private var lastResult: String?
    @State private var scanID = 0

    struct TrashInfo {
        let items: Int
        let bytes: Int64
        /// False when macOS won't let Scout look inside the Trash (needs Full Disk Access).
        let isReadable: Bool
    }

    private var allItems: [CleanupItem] { CleanupKind.allCases.flatMap { groups[$0] ?? [] } }
    private var selectedItems: [CleanupItem] {
        // An item can show up in two groups (e.g. a large old download); count it once.
        var seen = Set<String>()
        return allItems.filter { selected.contains($0.path) && seen.insert($0.path).inserted }
    }
    private var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.bytes } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                overview
                if let lastResult {
                    Label(lastResult, systemImage: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 4)
                }
                ForEach(CleanupKind.allCases) { kind in
                    groupCard(kind)
                }
                trashCard
            }
            .padding(16)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) { actionBar }
        .task(id: scanID) { await scan() }
        .alert("Empty the Trash?", isPresented: $isConfirmingEmptyTrash) {
            Button("Empty Trash", role: .destructive) { emptyTrash() }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let trash {
                Text("This permanently deletes \(trash.items) item\(trash.items == 1 ? "" : "s") (\(Format.bytes(trash.bytes))). This can’t be undone.")
            }
        }
    }

    // MARK: - Pieces

    private var overview: some View {
        let capacity = Self.diskCapacity()
        let found = allItems.reduce(Int64(0)) { $0 + $1.bytes } + (trash?.bytes ?? 0)
        return Card(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(capacity.map { "\(Format.bytes($0.free)) free" } ?? "Your Mac")
                    .font(.system(size: 24, weight: .medium))
                if let capacity { Text("of \(Format.bytes(capacity.total))").foregroundStyle(Color.textSubtle) }
                Spacer()
                if !scanning.isEmpty {
                    ProgressView().controlSize(.small)
                    Text("Looking…").foregroundStyle(Color.textSubtle)
                }
            }
            if let capacity, capacity.total > 0 {
                GeometryReader { geo in
                    let used = CGFloat(capacity.total - capacity.free) / CGFloat(capacity.total)
                    let reclaim = min(CGFloat(found) / CGFloat(capacity.total), used)
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.bgSelected)
                        Capsule().fill(Color.accentColor).frame(width: geo.size.width * used)
                        Capsule().fill(Color.green.opacity(0.85))
                            .frame(width: geo.size.width * reclaim)
                            .offset(x: geo.size.width * (used - reclaim))
                    }
                }
                .frame(height: 8)
            }
            Text(found > 0
                 ? "Scout found about \(Format.bytes(found)) you could free up. Nothing is removed until you choose."
                 : "Nothing is removed until you choose.")
                .font(.system(size: 13))
                .foregroundStyle(Color.textSubtle)
        }
    }

    private func groupCard(_ kind: CleanupKind) -> some View {
        let items = groups[kind] ?? []
        let total = items.reduce(Int64(0)) { $0 + $1.bytes }
        let isScanning = scanning.contains(kind)
        let isExpanded = expanded.contains(kind)
        return Card(spacing: 0) {
            HStack(spacing: 10) {
                Toggle("", isOn: groupBinding(items))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .disabled(items.isEmpty)
                Image(systemName: kind.symbol)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(kind.title).font(.system(size: 13, weight: .medium))
                        if !kind.selectedByDefault {
                            Text("YOUR CALL")
                                .font(.system(size: 12, weight: .medium))
                                .tracking(0.5)
                                .padding(.horizontal, 5).padding(.vertical, 1.5)
                                .background(Capsule().fill(Color.orange.opacity(0.18)))
                                .foregroundStyle(.orange)
                        }
                    }
                    Text(kind.explanation).font(.system(size: 12)).foregroundStyle(Color.textSubtle)
                }
                Spacer(minLength: 8)
                if isScanning {
                    ProgressView().controlSize(.small)
                } else {
                    Text(items.isEmpty ? "Nothing found" : Format.bytes(total))
                        .font(.system(size: 13, weight: items.isEmpty ? .regular : .medium))
                        .foregroundStyle(items.isEmpty ? .tertiary : .primary)
                        .monospacedDigit()
                }
                IconButton(symbol: isExpanded ? "chevron.up" : "chevron.down", help: isExpanded ? "Hide items" : "Show items") {
                    withAnimation(.snappy(duration: 0.2)) {
                        if isExpanded { expanded.remove(kind) } else { expanded.insert(kind) }
                    }
                }
                .disabled(items.isEmpty)
                .opacity(items.isEmpty ? 0.3 : 1)
            }
            if isExpanded, !items.isEmpty {
                Rectangle().fill(Color.hairline).frame(height: 1).padding(.vertical, 10)
                VStack(spacing: 2) {
                    ForEach(items) { item in itemRow(item) }
                }
            }
        }
    }

    private func itemRow(_ item: CleanupItem) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { selected.contains(item.path) },
                set: { if $0 { selected.insert(item.path) } else { selected.remove(item.path) } }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            Image(nsImage: IconCache.icon(forPath: item.path)).resizable().frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).font(.system(size: 13)).lineLimit(1).truncationMode(.middle)
                if let detail = item.detail {
                    Text(detail).font(.system(size: 12)).foregroundStyle(Color.textSubtle).lineLimit(1).truncationMode(.head)
                }
            }
            Spacer(minLength: 8)
            Text(Format.bytes(item.bytes)).font(.system(size: 12)).foregroundStyle(Color.textSubtle).monospacedDigit()
            IconButton(symbol: "arrow.forward.circle", help: "Show in Scout") {
                browser.reveal(URL(filePath: item.path))
            }
        }
        .padding(.leading, 32)
    }

    private var trashCard: some View {
        Card(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "trash")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 22)
                    .padding(.leading, 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Trash").font(.system(size: 13, weight: .medium))
                    Text(trashMessage).font(.system(size: 12)).foregroundStyle(Color.textSubtle)
                }
                Spacer()
                if let trash, trash.isReadable {
                    Text(Format.bytes(trash.bytes)).font(.system(size: 13, weight: .medium)).monospacedDigit()
                    Button("Empty Trash…", role: .destructive) { isConfirmingEmptyTrash = true }
                        .disabled(trash.items == 0)
                } else if trash != nil {
                    Button("Allow Access…") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                    }
                }
            }
        }
    }

    private var trashMessage: String {
        guard let trash else { return "Measuring…" }
        guard trash.isReadable else { return "Give Scout Full Disk Access to see what’s in the Trash." }
        if trash.items == 0 { return "Already empty." }
        return "\(trash.items) item\(trash.items == 1 ? "" : "s"). Space comes back once it’s emptied. Empty Trash always asks first."
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Text(selectedItems.isEmpty
                 ? "Tick items to move them to the Trash"
                 : "\(selectedItems.count) selected · \(Format.bytes(selectedBytes))")
                .font(.system(size: 13))
                .foregroundStyle(Color.textSubtle)
                .monospacedDigit()
            Spacer()
            Button("Look Again") { scanID += 1 }
                .disabled(!scanning.isEmpty)
            Button("Move to Trash") { moveSelectedToTrash() }
                .buttonStyle(.borderedProminent)
                .disabled(selectedItems.isEmpty)
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(CanvasFill())
        .overlay(alignment: .top) { Rectangle().fill(Color.hairline).frame(height: 1) }
    }

    private func groupBinding(_ items: [CleanupItem]) -> Binding<Bool> {
        Binding(
            get: { !items.isEmpty && items.allSatisfy { selected.contains($0.path) } },
            set: { on in
                for item in items {
                    if on { selected.insert(item.path) } else { selected.remove(item.path) }
                }
            }
        )
    }

    // MARK: - Actions

    private func moveSelectedToTrash() {
        let items = CleanupItem.safeToTrash(selectedItems)
        let bytes = items.reduce(0) { $0 + $1.bytes }
        let moved = browser.trash(items.map { URL(filePath: $0.path) }, actionName: "Clean Up")
        lastResult = moved > 0
            ? "Moved \(moved) item\(moved == 1 ? "" : "s") (\(Format.bytes(bytes))) to the Trash. ⌘Z puts \(moved == 1 ? "it" : "them") back."
            : nil
        scanID += 1
    }

    private func emptyTrash() {
        lastResult = "Emptying the Trash…"
        Task {
            let failed = await browser.services.emptyTrash()
            lastResult = failed == 0 ? "Emptied the Trash." : "Emptied the Trash, but \(failed) item\(failed == 1 ? "" : "s") couldn’t be removed."
            scanID += 1
        }
    }

    // MARK: - Scanning

    private func scan() async {
        groups = [:]
        selected = []
        trash = nil
        scanning = Set(CleanupKind.allCases)
        let home = browser.services.homePath

        // Large files come from Spotlight (main thread); the rest scan in the background.
        Task {
            let items = await largeFiles(home: home)
            finish(.largeFiles, with: items)
        }
        await withTaskGroup(of: (CleanupKind, [CleanupItem]).self) { group in
            group.addTask { (.devCaches, Self.scanDevCaches(home: home)) }
            group.addTask { (.installers, Self.scanInstallers(home: home)) }
            group.addTask { (.oldDownloads, Self.scanOldDownloads(home: home)) }
            group.addTask { (.duplicates, Self.scanDuplicates(home: home)) }
            group.addTask { (.oldNodeModules, CleanupScanner.scanOldNodeModules(home: home, sizeOf: Self.size)) }
            group.addTask { (.screenRecordings, CleanupScanner.scanScreenRecordings(home: home)) }
            group.addTask { (.mailAttachments, CleanupScanner.scanMailAttachments(home: home)) }
            group.addTask { (.appLeftovers, CleanupScanner.scanAppLeftovers(home: home, isInstalled: Self.isInstalled, sizeOf: Self.size)) }
            group.addTask { (.unusedApps, CleanupScanner.scanUnusedApps(lastUsed: Self.lastUsed, sizeOf: Self.size)) }
            for await (kind, items) in group {
                finish(kind, with: items)
            }
        }
        trash = await Self.measureTrash(home: home)
    }

    private func finish(_ kind: CleanupKind, with items: [CleanupItem]) {
        groups[kind] = items
        scanning.remove(kind)
        if kind.selectedByDefault { selected.formUnion(items.map(\.path)) }
    }

    nonisolated private static func size(_ url: URL) -> Int64 {
        FolderStats.size(of: url, fileLimit: 500_000).bytes
    }

    nonisolated private static func scanDevCaches(home: String) -> [CleanupItem] {
        CleanupScanner.scanDevCaches(home: home, sizeOf: size)
    }

    nonisolated private static func scanInstallers(home: String) -> [CleanupItem] {
        CleanupScanner.scanInstallers(in: URL.folder(home + "/Downloads"))
    }

    nonisolated private static func scanOldDownloads(home: String) -> [CleanupItem] {
        CleanupScanner.scanOldDownloads(in: URL.folder(home + "/Downloads"), sizeOf: size)
    }

    nonisolated private static func isInstalled(_ bundleID: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    /// When an app was last opened, from Spotlight.
    nonisolated private static func lastUsed(_ app: URL) -> Date? {
        guard let item = MDItemCreateWithURL(nil, app as CFURL) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }

    nonisolated private static func scanDuplicates(home: String) -> [CleanupItem] {
        let groups = DuplicateFinder.find(in: CleanupScanner.duplicateRoots(home: home))
        return CleanupScanner.duplicateItems(groups, home: home)
    }

    @concurrent nonisolated private static func measureTrash(home: String) async -> TrashInfo {
        let url = URL.folder(home + "/.Trash")
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: url.filePath) else {
            return TrashInfo(items: 0, bytes: 0, isReadable: false)
        }
        let count = items.filter { $0 != ".DS_Store" }.count
        return TrashInfo(items: count, bytes: FolderStats.size(of: url).bytes, isReadable: true)
    }

    /// Files over 500 MB in your home folder, from Spotlight (skipping caches and app insides).
    private func largeFiles(home: String) async -> [CleanupItem] {
        await withCheckedContinuation { continuation in
            var search: SpotlightSearch?
            var done = false
            search = SpotlightSearch(
                queryString: "kMDItemFSSize > 524288000 && kMDItemContentType != \"public.folder\"",
                scopes: [NSMetadataQueryUserHomeScope], live: false
            ) { hits, finished in
                guard finished, !done else { return }
                done = true
                let items = hits
                    .filter { !FileHitRanker.isNoise($0.path, home: home) && !$0.path.hasPrefix(home + "/.Trash/") }
                    .compactMap { hit -> CleanupItem? in
                        let size = (try? URL(filePath: hit.path).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                        guard size > 0 else { return nil }
                        let parent = PathDisplay.display((hit.path as NSString).deletingLastPathComponent, home: home)
                        return CleanupItem(path: hit.path, name: hit.name, bytes: Int64(size), detail: parent)
                    }
                    .sorted { $0.bytes > $1.bytes }
                continuation.resume(returning: Array(items.prefix(30)))
                search = nil
            }
            if search == nil {
                done = true
                continuation.resume(returning: [])
            }
        }
    }

    static func diskCapacity() -> (total: Int64, free: Int64)? {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let v = try? URL.folder("/").resourceValues(forKeys: keys),
              let total = v.volumeTotalCapacity, let free = v.volumeAvailableCapacityForImportantUsage else { return nil }
        return (Int64(total), free)
    }
}
