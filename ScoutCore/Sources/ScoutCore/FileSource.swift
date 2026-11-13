import Foundation

/// Where files come from. `LocalFileSource` is the Mac's own disk; a future
/// `RemoteFileSource` could talk to a Scout server on your home machine over Tailscale.
public protocol FileSource: Sendable {
    func contents(of folder: URL, includeHidden: Bool) async throws -> [FileItem]
    func createFolder(in parent: URL, named name: String) throws -> URL
    func rename(_ url: URL, to newName: String) throws -> URL
    /// Moves an item to the Trash and returns where it ended up, for Undo.
    func trash(_ url: URL) throws -> URL?
    /// Moves an item to an exact destination URL.
    func move(_ url: URL, to destination: URL) throws
    /// Copies an item into a folder, picking a free name ("name copy") if needed.
    func copy(_ url: URL, into folder: URL) throws -> URL
    /// Moves an item into a folder, picking a free name ("name 2") if needed.
    func move(_ url: URL, into folder: URL) throws -> URL
}

public enum ScoutError: LocalizedError, Equatable {
    case invalidName(String)
    case alreadyExists(String)

    public var errorDescription: String? {
        switch self {
        case .invalidName(let reason): reason
        case .alreadyExists(let name): "An item named “\(name)” already exists here."
        }
    }
}
