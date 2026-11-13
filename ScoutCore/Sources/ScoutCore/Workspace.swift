import Foundation

/// A named collection of folders and files from anywhere (local, iCloud, cloud
/// drives, external disks) shown together on one page. Nothing is moved or copied:
/// a workspace only remembers paths.
public struct Workspace: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var symbol: String
    public private(set) var paths: [String]

    public init(id: UUID = UUID(), name: String, symbol: String = "square.stack.3d.up", paths: [String] = []) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.paths = []
        add(paths)
    }

    /// Adds paths at the end, skipping ones already here.
    public mutating func add(_ newPaths: [String]) {
        for path in newPaths where !paths.contains(path) { paths.append(path) }
    }

    public mutating func remove(_ removed: Set<String>) {
        paths.removeAll { removed.contains($0) }
    }

    /// Symbols offered when creating a workspace.
    public static let symbols = [
        "square.stack.3d.up", "briefcase", "graduationcap", "chart.line.uptrend.xyaxis", "doc.text",
        "hammer", "paintbrush", "airplane", "house", "star", "heart", "gamecontroller",
    ]
}
