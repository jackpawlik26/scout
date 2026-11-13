import AppKit
import Observation
import SwiftUI

/// Your keyboard shortcuts: the defaults, plus any you changed in Settings (saved as
/// "key|modifiers"; an empty value means "no shortcut").
@Observable
final class ShortcutStore {
    static let shared = ShortcutStore()
    private static let key = "customShortcuts"

    private(set) var overrides: [String: String] = UserDefaults.standard.dictionary(forKey: ShortcutStore.key) as? [String: String] ?? [:]

    func shortcut(_ command: ScoutShortcut) -> KeyboardShortcut? {
        guard let saved = overrides[command.rawValue] else { return command.defaultShortcut }
        return Self.decode(saved)
    }

    func isCustomized(_ command: ScoutShortcut) -> Bool { overrides[command.rawValue] != nil }

    /// Sets a shortcut (nil = none). Another command using the same keys loses it; returns that command.
    @discardableResult
    func set(_ command: ScoutShortcut, to shortcut: KeyboardShortcut?) -> ScoutShortcut? {
        var clash: ScoutShortcut?
        if let shortcut {
            clash = ScoutShortcut.allCases.first { $0 != command && Self.same(self.shortcut($0), shortcut) }
            if let clash { overrides[clash.rawValue] = "" }
        }
        overrides[command.rawValue] = shortcut.map(Self.encode) ?? ""
        if let shortcut, Self.same(shortcut, command.defaultShortcut) { overrides[command.rawValue] = nil }
        save()
        return clash
    }

    func reset(_ command: ScoutShortcut) {
        overrides[command.rawValue] = nil
        save()
    }

    func resetAll() {
        overrides = [:]
        save()
    }

    private func save() { UserDefaults.standard.set(overrides, forKey: Self.key) }

    // MARK: - Encoding and display

    static func encode(_ shortcut: KeyboardShortcut) -> String {
        "\(shortcut.key.character)|\(shortcut.modifiers.rawValue)"
    }

    static func decode(_ string: String) -> KeyboardShortcut? {
        guard let bar = string.lastIndex(of: "|"), let first = string.first, string.first != "|",
              let raw = Int(string[string.index(after: bar)...]) else { return nil }
        return KeyboardShortcut(KeyEquivalent(first), modifiers: EventModifiers(rawValue: raw))
    }

    static func same(_ a: KeyboardShortcut?, _ b: KeyboardShortcut?) -> Bool {
        guard let a, let b else { return false }
        return a.key.character == b.key.character && a.modifiers == b.modifiers
    }

    /// "⇧⌘K", "⌥⇥", "F5".
    static func display(_ shortcut: KeyboardShortcut?) -> String {
        guard let shortcut else { return "None" }
        var text = ""
        if shortcut.modifiers.contains(.control) { text += "⌃" }
        if shortcut.modifiers.contains(.option) { text += "⌥" }
        if shortcut.modifiers.contains(.shift) { text += "⇧" }
        if shortcut.modifiers.contains(.command) { text += "⌘" }
        return text + keyName(shortcut.key)
    }

    static func keyName(_ key: KeyEquivalent) -> String {
        switch key {
        case .upArrow: return "↑"
        case .downArrow: return "↓"
        case .leftArrow: return "←"
        case .rightArrow: return "→"
        case .delete: return "⌫"
        case .deleteForward: return "⌦"
        case .tab: return "⇥"
        case .return: return "↩"
        case .space: return "Space"
        case .escape: return "⎋"
        default: break
        }
        if let scalar = key.character.unicodeScalars.first,
           (0xF704...0xF70F).contains(scalar.value) {
            return "F\(scalar.value - 0xF704 + 1)"
        }
        return String(key.character).uppercased()
    }

    /// The shortcut a key press means, or nil if it can't be one (needs ⌘, ⌃ or ⌥, unless it's an F-key).
    static func shortcut(from event: NSEvent) -> KeyboardShortcut? {
        let special: [UInt16: KeyEquivalent] = [
            126: .upArrow, 125: .downArrow, 123: .leftArrow, 124: .rightArrow, 51: .delete, 117: .deleteForward,
            48: .tab, 36: .return, 49: .space,
        ]
        let functionKeys: [UInt16: Int] = [122: 1, 120: 2, 99: 3, 118: 4, 96: 5, 97: 6, 98: 7, 100: 8, 101: 9, 109: 10, 103: 11, 111: 12]
        var modifiers: EventModifiers = []
        let flags = event.modifierFlags
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if let number = functionKeys[event.keyCode] {
            let scalar = UnicodeScalar(0xF704 + number - 1)!
            return KeyboardShortcut(KeyEquivalent(Character(scalar)), modifiers: modifiers)
        }
        guard !modifiers.isDisjoint(with: [.command, .control, .option]) else { return nil }
        if let key = special[event.keyCode] { return KeyboardShortcut(key, modifiers: modifiers) }
        guard let character = event.charactersIgnoringModifiers?.lowercased().first else { return nil }
        return KeyboardShortcut(KeyEquivalent(character), modifiers: modifiers)
    }
}

extension View {
    /// The shortcut for a command, as you've set it in Settings.
    func customizableShortcut(_ command: ScoutShortcut) -> some View {
        keyboardShortcut(ShortcutStore.shared.shortcut(command))
    }
}

/// Settings ▸ Keyboard Shortcuts: click a shortcut, press the new keys. Esc cancels, ⌫ clears.
struct ShortcutRecorderList: View {
    @State private var store = ShortcutStore.shared
    @State private var recording: ScoutShortcut?
    @State private var monitor: Any?
    @State private var search = ""
    @State private var note: String?

    private var commands: [ScoutShortcut] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return ScoutShortcut.allCases.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }
            .sorted { $0.title < $1.title }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Search commands", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 220)
                Spacer()
                if let note { Text(note).font(.caption).foregroundStyle(.orange) }
                Button("Restore Defaults") {
                    store.resetAll()
                    note = nil
                }
                .disabled(store.overrides.isEmpty)
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(commands) { command in
                        HStack {
                            Text(command.title)
                            Spacer()
                            if store.isCustomized(command) {
                                Button("Reset") { store.reset(command) }.buttonStyle(.link).font(.caption)
                            }
                            Button {
                                recording == command ? stopRecording() : startRecording(command)
                            } label: {
                                Text(recording == command ? "Press keys…" : ShortcutStore.display(store.shortcut(command)))
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .frame(minWidth: 84)
                            }
                            .buttonStyle(.bordered)
                            .tint(recording == command ? .accentColor : nil)
                        }
                        .padding(.vertical, 4)
                        Divider()
                    }
                }
            }
            .frame(height: 260)
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording(_ command: ScoutShortcut) {
        stopRecording()
        recording = command
        note = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            nonisolated(unsafe) let event = event
            MainActor.assumeIsolated {
                guard let command = recording else { return }
                if event.keyCode == 53 { stopRecording(); return } // Esc
                if event.keyCode == 51, event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
                    store.set(command, to: nil) // ⌫ alone: no shortcut
                    stopRecording()
                    return
                }
                guard let shortcut = ShortcutStore.shortcut(from: event) else {
                    note = "Use ⌘, ⌃ or ⌥ with a key (or an F-key)."
                    return
                }
                if let clash = store.set(command, to: shortcut) { note = "Removed it from “\(clash.title)”." }
                stopRecording()
            }
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = nil
    }
}
