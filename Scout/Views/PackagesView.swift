import AppKit
import ScoutCore
import SwiftUI

/// Packages: what Homebrew and npm have installed, how big each is, and what's outdated.
/// Scout never runs installs itself; it copies the command and opens your terminal.
struct PackagesView: View {
    let browser: BrowserModel

    @State private var packages: [PackageSource: [Package]] = [:]
    /// Tools that aren't installed (nil result from the scanner).
    @State private var missing: Set<PackageSource> = []
    @State private var loading: Set<PackageSource> = []
    @State private var sizes: [String: Int64] = [:]
    @State private var showOnlyUpdates = false
    @State private var showDependencies = false
    @State private var isUpdatingHomebrew = false
    @State private var banner: String?
    @State private var loadID = 0

    private var all: [Package] { PackageSource.allCases.flatMap { packages[$0] ?? [] } }
    private var outdated: [Package] { all.filter(\.isOutdated) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                overview
                if let banner {
                    Label(banner, systemImage: "doc.on.clipboard")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.textSubtle)
                        .padding(.horizontal, 4)
                }
                ForEach(PackageSource.allCases) { source in
                    if !missing.contains(source) { sourceCard(source) }
                }
                if missing.count == PackageSource.allCases.count {
                    ContentUnavailableView("No Package Managers", systemImage: "shippingbox",
                                           description: Text("Scout looks for Homebrew and npm. Neither is installed."))
                }
            }
            .padding(16)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .task(id: loadID) { await load() }
    }

    // MARK: - Pieces

    private var overview: some View {
        Card(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(all.count) installed")
                    .font(.system(size: 24, weight: .medium))
                if !outdated.isEmpty {
                    Text("\(outdated.count) update\(outdated.count == 1 ? "" : "s") available")
                        .foregroundStyle(.orange)
                }
                Spacer()
                if !loading.isEmpty || isUpdatingHomebrew {
                    ProgressView().controlSize(.small)
                    Text(isUpdatingHomebrew ? "Checking Homebrew…" : "Looking…").foregroundStyle(Color.textSubtle)
                }
            }
            Text("Sizes are what each package takes on disk. Updates are checked against Homebrew’s last refresh and the npm registry.")
                .font(.system(size: 13))
                .foregroundStyle(Color.textSubtle)
            HStack(spacing: 10) {
                Picker("", selection: $showOnlyUpdates) {
                    Text("All").tag(false)
                    Text("Updates (\(outdated.count))").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Toggle("Show dependencies", isOn: $showDependencies)
                    .toggleStyle(.checkbox)
                    .help("Homebrew packages installed only because something else needs them")
                Spacer()
                if !missing.contains(.homebrew) {
                    Button("Check Homebrew") { checkHomebrew() }
                        .disabled(isUpdatingHomebrew || !loading.isEmpty)
                        .help("Run “brew update” so outdated packages show up")
                }
                Button("Upgrade All…") { runInTerminal(upgradeAllCommand) }
                    .buttonStyle(.borderedProminent)
                    .disabled(outdated.isEmpty)
                    .help(upgradeAllCommand)
            }
        }
    }

    private func sourceCard(_ source: PackageSource) -> some View {
        let everything = packages[source] ?? []
        let dependencies = everything.filter(\.isDependency).count
        let shown = everything.filter { (showDependencies || !$0.isDependency) && (!showOnlyUpdates || $0.isOutdated) }
        let total = everything.compactMap { sizes[$0.id] }.reduce(0, +)
        let updates = everything.filter(\.isOutdated).count
        return Card(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: source.symbol)
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(source.title).font(.system(size: 13, weight: .medium))
                    Text(subtitle(count: everything.count, dependencies: dependencies, updates: updates))
                        .font(.system(size: 12)).foregroundStyle(Color.textSubtle)
                }
                Spacer()
                if loading.contains(source) {
                    ProgressView().controlSize(.small)
                } else if total > 0 {
                    Text(Format.bytes(total)).font(.system(size: 13, weight: .medium)).monospacedDigit()
                }
            }
            if !shown.isEmpty {
                Rectangle().fill(Color.hairline).frame(height: 1).padding(.vertical, 10)
                VStack(spacing: 2) {
                    ForEach(shown) { row($0) }
                }
            } else if !loading.contains(source), !everything.isEmpty {
                Text(showOnlyUpdates ? "Everything’s up to date." : "Only dependencies here.")
                    .font(.system(size: 12)).foregroundStyle(Color.textSubtle)
                    .padding(.top, 8).padding(.leading, 32)
            }
        }
    }

    private func subtitle(count: Int, dependencies: Int, updates: Int) -> String {
        var parts = ["\(count) installed"]
        if dependencies > 0 { parts.append("\(dependencies) as dependencies") }
        if updates > 0 { parts.append("\(updates) outdated") }
        return parts.joined(separator: " · ")
    }

    private func row(_ package: Package) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(package.name).font(.system(size: 13, weight: .medium))
                    Text(package.version)
                        .font(.system(size: 12, design: .monospaced)).foregroundStyle(Color.textSubtle)
                    if let latest = package.latest, package.isOutdated {
                        Text("→ \(latest)")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(.orange)
                    }
                    if package.isDependency {
                        Text("dependency").font(.system(size: 12)).foregroundStyle(Color.textSubtle)
                    }
                }
                if let summary = package.summary {
                    Text(summary).font(.system(size: 12)).foregroundStyle(Color.textSubtle).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let size = sizes[package.id] {
                Text(Format.bytes(size)).font(.system(size: 12)).foregroundStyle(Color.textSubtle).monospacedDigit()
            }
            if package.isOutdated {
                Button("Upgrade") { runInTerminal(package.upgradeCommand) }
                    .controlSize(.small)
                    .help(package.upgradeCommand)
            }
            Menu {
                if let path = package.path {
                    Button("Show in Scout") { browser.reveal(URL(filePath: path)) }
                }
                if let page = package.webPage {
                    Button("Open Website") { NSWorkspace.shared.open(page) }
                }
                Divider()
                Button("Copy Upgrade Command") { copy(package.upgradeCommand) }
                Button("Copy Uninstall Command") { copy(package.uninstallCommand) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .light))
                    .foregroundStyle(Color.textSubtle)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.leading, 32)
        .padding(.vertical, 3)
    }

    private var upgradeAllCommand: String {
        var commands: [String] = []
        let brew = outdated.filter { $0.source != .npm }
        if !brew.isEmpty { commands.append("brew upgrade") }
        let npm = outdated.filter { $0.source == .npm }
        if !npm.isEmpty { commands.append("npm install -g " + npm.map { "\($0.name)@latest" }.joined(separator: " ")) }
        return commands.joined(separator: " && ")
    }

    // MARK: - Actions

    /// Copies the command and opens your terminal, ready to paste. Scout doesn't run installs itself.
    private func runInTerminal(_ command: String) {
        copy(command)
        browser.openInTerminal(browser.services.home)
        banner = "Copied “\(command)”. Paste it in \(DevApp.preferredTerminal?.name ?? "Terminal") (⌘V) and press Return, then Look Again here."
    }

    private func copy(_ command: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        banner = "Copied “\(command)”."
    }

    private func checkHomebrew() {
        isUpdatingHomebrew = true
        Task {
            _ = await Self.updateHomebrew()
            isUpdatingHomebrew = false
            loadID += 1
        }
    }

    // MARK: - Loading

    private func load() async {
        loading = Set(PackageSource.allCases)
        await withTaskGroup(of: (PackageSource, [Package]?).self) { group in
            group.addTask { (.homebrew, await Self.scanHomebrew()) }
            group.addTask { (.npm, await Self.scanNpm()) }
            for await (source, result) in group {
                if source == .homebrew {
                    finish(.homebrew, result?.filter { $0.source == .homebrew })
                    finish(.cask, result?.filter { $0.source == .cask })
                } else {
                    finish(source, result)
                }
            }
        }
        // Sizes last: they're the slow part.
        for package in all where sizes[package.id] == nil {
            guard let path = package.path else { continue }
            sizes[package.id] = await Self.measure(path)
        }
    }

    private func finish(_ source: PackageSource, _ result: [Package]?) {
        loading.remove(source)
        if let result {
            missing.remove(source)
            packages[source] = result
        } else {
            missing.insert(source)
            packages[source] = nil
        }
    }

    @concurrent nonisolated private static func scanHomebrew() async -> [Package]? { PackageScanner.homebrew() }
    @concurrent nonisolated private static func scanNpm() async -> [Package]? { PackageScanner.npm() }
    @concurrent nonisolated private static func updateHomebrew() async -> Bool { PackageScanner.updateHomebrew() }
    @concurrent nonisolated private static func measure(_ path: String) async -> Int64 {
        FolderStats.size(of: URL(filePath: path), fileLimit: 200_000).bytes
    }
}
