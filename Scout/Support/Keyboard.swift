import AppKit
import SwiftUI

/// A key, as `NSEvent` reports it. (SwiftUI's `onKeyPress` never sees Esc while a
/// text field is editing, because the field editor eats it, so these are caught at the window.)
enum Key: UInt16 {
    case escape = 53
    case downArrow = 125
    case upArrow = 126
    case leftArrow = 123
    case rightArrow = 124
}

extension View {
    /// Runs `action` when `key` is pressed in this view's window, before any text field
    /// or list gets it. Return true to swallow the key.
    func onWindowKey(_ key: Key, modifiers: NSEvent.ModifierFlags = [], perform action: @escaping () -> Bool) -> some View {
        background(KeyCatcher(key: key, modifiers: modifiers, action: action))
    }

    /// Hands the view's NSWindow to `found` once it's in one.
    func onNSWindow(_ found: @escaping (NSWindow) -> Void) -> some View {
        background(WindowReader(found: found))
    }
}

private struct KeyCatcher: NSViewRepresentable {
    let key: Key
    let modifiers: NSEvent.ModifierFlags
    let action: () -> Bool

    func makeNSView(context: Context) -> KeyCatcherView {
        let view = KeyCatcherView()
        view.update(key: key, modifiers: modifiers, action: action)
        return view
    }

    func updateNSView(_ view: KeyCatcherView, context: Context) {
        view.update(key: key, modifiers: modifiers, action: action)
    }

    static func dismantleNSView(_ view: KeyCatcherView, coordinator: ()) { view.stop() }
}

final class KeyCatcherView: NSView {
    private var monitor: Any?
    private var key = Key.escape
    private var modifiers: NSEvent.ModifierFlags = []
    private var action: () -> Bool = { false }

    func update(key: Key, modifiers: NSEvent.ModifierFlags, action: @escaping () -> Bool) {
        self.key = key
        self.modifiers = modifiers
        self.action = action
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stop()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Local monitors run on the main thread.
            nonisolated(unsafe) let event = event
            let swallow = MainActor.assumeIsolated { self?.handle(event) ?? false }
            return swallow ? nil : event
        }
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard let window, event.window === window, event.keyCode == key.rawValue,
              event.modifierFlags.intersection([.command, .option, .control, .shift]) == modifiers
        else { return false }
        return action()
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    isolated deinit { stop() }
}

private struct WindowReader: NSViewRepresentable {
    let found: (NSWindow) -> Void

    func makeNSView(context: Context) -> WindowReaderView {
        let view = WindowReaderView()
        view.found = found
        return view
    }

    func updateNSView(_ view: WindowReaderView, context: Context) {}
}

final class WindowReaderView: NSView {
    var found: ((NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window { found?(window) }
    }
}

/// True while the user is typing in a text field (so plain keys shouldn't act on files).
@MainActor var isEditingText: Bool {
    NSApp.keyWindow?.firstResponder is NSText
}
