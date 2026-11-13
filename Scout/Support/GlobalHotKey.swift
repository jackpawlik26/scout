import AppKit
import Carbon.HIToolbox

/// A system-wide shortcut that works while you're in any app. Uses Carbon's
/// RegisterEventHotKey, which needs no Accessibility permission.
@MainActor
final class GlobalHotKey {
    static let shared = GlobalHotKey()

    /// The choices offered in Settings.
    enum Preset: String, CaseIterable, Identifiable {
        case optionSpace, controlOptionSpace, shiftOptionSpace, optionCommandK, off

        var id: Self { self }

        var title: String {
            switch self {
            case .optionSpace: "⌥ Space"
            case .controlOptionSpace: "⌃⌥ Space"
            case .shiftOptionSpace: "⇧⌥ Space"
            case .optionCommandK: "⌥⌘ K"
            case .off: "Off"
            }
        }

        var keyCode: UInt32? {
            switch self {
            case .optionSpace, .controlOptionSpace, .shiftOptionSpace: UInt32(kVK_Space)
            case .optionCommandK: UInt32(kVK_ANSI_K)
            case .off: nil
            }
        }

        var carbonModifiers: UInt32 {
            switch self {
            case .optionSpace: UInt32(optionKey)
            case .controlOptionSpace: UInt32(controlKey | optionKey)
            case .shiftOptionSpace: UInt32(shiftKey | optionKey)
            case .optionCommandK: UInt32(optionKey | cmdKey)
            case .off: 0
            }
        }

        static var saved: Preset {
            Preset(rawValue: UserDefaults.standard.string(forKey: "jumpHotKey") ?? "") ?? .optionSpace
        }
    }

    /// Called when the shortcut is pressed.
    var onPress: (() -> Void)?
    /// False when another app already owns the chosen shortcut.
    private(set) var isRegistered = false

    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    /// Registers the saved preset (or nothing, for Off). Returns false if it's taken.
    @discardableResult
    func apply(_ preset: Preset = .saved) -> Bool {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        isRegistered = false
        guard let keyCode = preset.keyCode else { return true }
        installHandler()
        let id = EventHotKeyID(signature: OSType(0x5343_4F54), id: 1) // "SCOT"
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, preset.carbonModifiers, id, GetApplicationEventTarget(), 0, &ref)
        hotKey = ref
        isRegistered = status == noErr
        return isRegistered
    }

    private func installHandler() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), globalHotKeyPressed, 1, &spec, nil, &handler)
    }
}

/// Carbon calls this on the main thread.
nonisolated private func globalHotKeyPressed(_: EventHandlerCallRef?, _: EventRef?, _: UnsafeMutableRawPointer?) -> OSStatus {
    MainActor.assumeIsolated { GlobalHotKey.shared.onPress?() }
    return noErr
}
