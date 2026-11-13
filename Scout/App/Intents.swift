import AppIntents
import AppKit
import ScoutCore

// Actions for the Shortcuts app and Siri. Each opens Scout and does one thing, through the
// same scout:// links Raycast uses.

nonisolated private func openLink(_ link: ScoutLink) {
    NSWorkspace.shared.open(link.url)
}

struct OpenInScoutIntent: AppIntent {
    static let title: LocalizedStringResource = "Open in Scout"
    static let description = IntentDescription("Opens a folder in Scout, or shows a file in its folder.")
    static let openAppWhenRun = true

    @Parameter(title: "File or Folder", supportedContentTypes: [.item, .folder])
    var item: IntentFile

    func perform() async throws -> some IntentResult {
        guard let url = item.fileURL else { throw $item.needsValueError("Which file or folder?") }
        openLink(.open(path: url.filePath, newTab: false))
        return .result()
    }
}

struct WorkspaceEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Workspace"
    static let defaultQuery = WorkspaceQuery()
    let id: UUID
    let name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct WorkspaceQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [WorkspaceEntity] {
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [WorkspaceEntity] {
        ScoutStore.loadWorkspaces().map { WorkspaceEntity(id: $0.id, name: $0.name) }
    }
}

struct OpenWorkspaceIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Workspace"
    static let description = IntentDescription("Opens one of your Scout workspaces.")
    static let openAppWhenRun = true

    @Parameter(title: "Workspace")
    var workspace: WorkspaceEntity

    func perform() async throws -> some IntentResult {
        openLink(.workspace(name: workspace.name))
        return .result()
    }
}

struct JumpIntent: AppIntent {
    static let title: LocalizedStringResource = "Jump in Scout"
    static let description = IntentDescription("Opens Scout's ⌘K palette, optionally already searching.")
    static let openAppWhenRun = true

    @Parameter(title: "Search For", default: "")
    var query: String

    func perform() async throws -> some IntentResult {
        openLink(.jump(query: query.isEmpty ? nil : query))
        return .result()
    }
}

struct RecentsIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Recents in Scout"
    static let openAppWhenRun = true
    func perform() async throws -> some IntentResult {
        openLink(.recents)
        return .result()
    }
}

struct CleanUpIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Clean Up"
    static let description = IntentDescription("Shows what Scout can free up. Nothing is removed until you choose.")
    static let openAppWhenRun = true
    func perform() async throws -> some IntentResult {
        openLink(.cleanup)
        return .result()
    }
}

struct TidyDownloadsIntent: AppIntent {
    static let title: LocalizedStringResource = "Tidy Downloads"
    static let description = IntentDescription("Shows Scout's plan for sorting Downloads into folders. Nothing moves until you confirm.")
    static let openAppWhenRun = true
    func perform() async throws -> some IntentResult {
        openLink(.tidy(path: "~/Downloads"))
        return .result()
    }
}

struct ScoutShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: JumpIntent(), phrases: ["Jump in \(.applicationName)", "Find a file in \(.applicationName)"],
                    shortTitle: "Jump", systemImageName: "magnifyingglass")
        AppShortcut(intent: OpenWorkspaceIntent(), phrases: ["Open \(\.$workspace) in \(.applicationName)",
                                                             "Open a workspace in \(.applicationName)"],
                    shortTitle: "Open Workspace", systemImageName: "square.stack.3d.up")
        AppShortcut(intent: RecentsIntent(), phrases: ["Show recent files in \(.applicationName)"],
                    shortTitle: "Recents", systemImageName: "clock")
        AppShortcut(intent: TidyDownloadsIntent(), phrases: ["Tidy Downloads with \(.applicationName)"],
                    shortTitle: "Tidy Downloads", systemImageName: "tray.full")
        AppShortcut(intent: CleanUpIntent(), phrases: ["Clean up my Mac with \(.applicationName)"],
                    shortTitle: "Clean Up", systemImageName: "sparkles")
    }
}
