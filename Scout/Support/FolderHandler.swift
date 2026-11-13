import AppKit
import CoreServices
import UniformTypeIdentifiers

/// Makes Scout the app macOS opens folders with (Spotlight, `open ~/Downloads`, a browser's
/// "show download", double-clicking a folder in other apps). Finder keeps the Desktop and
/// the system Open/Save dialogs, which no app can take over.
enum FolderHandler {
    static let finderURL = URL(filePath: "/System/Library/CoreServices/Finder.app")

    static var isScout: Bool {
        NSWorkspace.shared.urlForApplication(toOpen: .folder)?.standardizedFileURL.filePath
            == Bundle.main.bundleURL.standardizedFileURL.filePath
    }

    /// Switches between Scout and Finder. Throws if macOS refuses (or the user cancels its prompt).
    static func set(_ useScout: Bool) async throws {
        do {
            try await NSWorkspace.shared.setDefaultApplication(
                at: useScout ? Bundle.main.bundleURL : finderURL, toOpen: .folder)
        } catch {
            // NSWorkspace can refuse folders (paramErr); Launch Services' older call is what
            // other file managers use for this.
            let bundleID = (useScout ? Bundle.main.bundleIdentifier : "com.apple.finder") ?? "com.apple.finder"
            let status = LSSetDefaultRoleHandlerForContentType(UTType.folder.identifier as CFString, .all, bundleID as CFString)
            if status != noErr { throw error }
        }
        if isScout != useScout {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(paramErr),
                          userInfo: [NSLocalizedDescriptionKey: "macOS kept \(useScout ? "Finder" : "Scout") as the app for folders."])
        }
    }
}

/// Talks to Finder itself. "Show in Finder" can't use `activateFileViewerSelecting`, because
/// once Scout is the default file browser that request comes straight back to Scout.
enum FinderBridge {
    static func reveal(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let list = urls.map { "POSIX file \"\(escape($0.filePath))\"" }.joined(separator: ", ")
        let script = "tell application \"Finder\"\nreveal {\(list)}\nactivate\nend tell"
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        if error != nil {
            // No permission to control Finder: open the enclosing folder in Finder instead.
            let folders = Array(Set(urls.map { $0.deletingLastPathComponent() }))
            NSWorkspace.shared.open(folders, withApplicationAt: FolderHandler.finderURL,
                                    configuration: NSWorkspace.OpenConfiguration())
        }
    }

    private static func escape(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
