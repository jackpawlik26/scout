import AppKit
import ScoutCore

/// App-level hooks SwiftUI doesn't cover: "Show in Finder" requests from other apps
/// (when Scout is the default file browser) and the global jump shortcut.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set by ScoutApp once its services exist.
    var services: AppServices? {
        didSet { DropShelf.shared.services = services }
    }
    /// Reveal requests that arrived before a window was ready.
    private var pending: [URL] = []

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Apps call NSWorkspace "activateFileViewerSelecting", which sends the default file
        // browser a "reveal" Apple Event (misc/mvis). Finder handles it normally; Scout does
        // once it's the default (Settings ▸ Browsing).
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleReveal(_:replyEvent:)),
            forEventClass: AEEventClass(kAEMiscStandards), andEventID: AEEventID(kAEMakeObjectsVisible))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        GlobalHotKey.shared.onPress = { [weak self] in self?.services?.toggleJumpPalette() }
        GlobalHotKey.shared.apply()
        DropShelf.shared.apply()
        for url in pending { reveal(url) }
        pending = []
    }

    @objc private func handleReveal(_ event: NSAppleEventDescriptor, replyEvent: NSAppleEventDescriptor) {
        for url in Self.fileURLs(in: event.paramDescriptor(forKeyword: keyDirectObject)) {
            reveal(url)
        }
    }

    private func reveal(_ url: URL) {
        guard let services else {
            pending.append(url)
            return
        }
        services.route(.open(path: url.filePath, newTab: true))
    }

    /// File URLs in an Apple Event's direct object (one item or a list).
    static func fileURLs(in descriptor: NSAppleEventDescriptor?) -> [URL] {
        guard let descriptor else { return [] }
        if descriptor.descriptorType == typeAEList {
            guard descriptor.numberOfItems > 0 else { return [] }
            return (1...descriptor.numberOfItems).flatMap { fileURLs(in: descriptor.atIndex($0)) }
        }
        if let coerced = descriptor.coerce(toDescriptorType: typeFileURL),
           let url = URL(dataRepresentation: coerced.data, relativeTo: nil), url.isFileURL {
            return [url]
        }
        if let path = descriptor.stringValue, path.hasPrefix("/") { return [URL(filePath: path)] }
        return []
    }
}

/// Makes Scout the app that "Show in Finder" opens in other apps (the NSFileViewer default).
enum DefaultFileBrowser {
    static let key = "NSFileViewer" as CFString

    static var isScout: Bool {
        (CFPreferencesCopyValue(key, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            as? String) == Bundle.main.bundleIdentifier
    }

    /// Writes only this one key of the global preferences (apps pick it up when they next launch).
    static func set(_ useScout: Bool) {
        let value = useScout ? Bundle.main.bundleIdentifier as CFString? : nil
        CFPreferencesSetValue(key, value, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }
}
