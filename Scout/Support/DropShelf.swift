import AppKit
import ScoutCore
import SwiftUI

/// Settings ▸ Drop shelf: drag files from any app to the top edge of the screen and a strip
/// slides down under the menu bar with your favorite folders and the Shelf. Drop on a folder
/// to move the files into it (⌥ copies, another disk copies), or on the Shelf to hold them.
///
/// Watching for drags uses a global mouse monitor, which macOS allows without Accessibility
/// permission (only keyboard monitoring needs it).
@MainActor
final class DropShelf {
    static let shared = DropShelf()
    static let key = "dropShelf"
    static var isOn: Bool { UserDefaults.standard.bool(forKey: key) }

    weak var services: AppServices?
    private var monitors: [Any] = []
    private var panel: NSPanel?
    private var dragChangeCount = NSPasteboard(name: .drag).changeCount
    private var hideTask: Task<Void, Never>?
    /// How close to the top of the screen (points) the pointer has to come.
    private let edge: CGFloat = 6

    /// Starts or stops watching, to match the setting.
    func apply() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors = []
        guard Self.isOn else {
            hide()
            return
        }
        let dragged: (NSEvent) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerDragged() }
        }
        let released: (NSEvent) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.dragEnded() }
        }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged, handler: dragged) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: released) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged, handler: { dragged($0); return $0 }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp, handler: { released($0); return $0 }) { monitors.append(m) }
    }

    private func pointerDragged() {
        guard panel?.isVisible != true else { return }
        let point = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }),
              point.y >= screen.frame.maxY - edge else { return }
        // Only for a drag that carries files.
        let pasteboard = NSPasteboard(name: .drag)
        guard pasteboard.changeCount != dragChangeCount,
              pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
        else { return }
        show(on: screen)
    }

    private func dragEnded() {
        dragChangeCount = NSPasteboard(name: .drag).changeCount
        guard panel?.isVisible == true else { return }
        // Let a drop land before the strip goes away.
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            hide()
        }
    }

    private func show(on screen: NSScreen) {
        guard let services else { return }
        hideTask?.cancel()
        let size = NSSize(width: 560, height: 96)
        let top = screen.visibleFrame.maxY
        let frame = NSRect(x: screen.frame.midX - size.width / 2, y: top - size.height - 4, width: size.width, height: size.height)
        let panel = self.panel ?? makePanel()
        panel.contentView = NSHostingView(rootView: DropShelfStrip(onDone: { [weak self] in self?.hide() }).environment(services))
        panel.setFrame(frame.offsetBy(dx: 0, dy: 24), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().setFrame(frame, display: true)
            panel.animator().alphaValue = 1
        }
        self.panel = panel
    }

    func hide() {
        hideTask?.cancel()
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated { panel.orderOut(nil) }
        })
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        return panel
    }
}

/// The strip itself: favorite folders, then the Shelf.
private struct DropShelfStrip: View {
    @Environment(AppServices.self) private var services
    let onDone: () -> Void

    var body: some View {
        let folders = services.favorites.filter { $0.url.hasDirectoryPath }.prefix(6)
        HStack(spacing: 6) {
            ForEach(Array(folders)) { place in
                DropTarget(title: place.name, symbol: place.symbol) { urls in
                    guard let browser = services.frontWindow?.current else { return false }
                    let taken = browser.receiveDrop(urls, into: place.url)
                    if taken { onDone() }
                    return taken
                }
            }
            Divider().frame(height: 56)
            DropTarget(title: services.shelf.isEmpty ? "Shelf" : "Shelf (\(services.shelf.count))", symbol: "tray.and.arrow.down") { urls in
                services.addToShelf(urls.filter(\.isFileURL))
                onDone()
                return true
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct DropTarget: View {
    let title: String
    let symbol: String
    let receive: ([URL]) -> Bool
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 20))
            Text(title).font(.ui(11, .medium)).lineLimit(1).truncationMode(.middle)
        }
        .frame(width: 76, height: 64)
        .background(RoundedRectangle(cornerRadius: 12).fill(isTargeted ? Color.accentColor.opacity(0.25) : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(isTargeted ? Color.accentColor : Color.clear, lineWidth: 1.5))
        .scaleEffect(isTargeted ? 1.06 : 1)
        .animation(.snappy(duration: 0.15), value: isTargeted)
        .dropDestination(for: URL.self) { urls, _ in receive(urls) } isTargeted: { isTargeted = $0 }
    }
}
