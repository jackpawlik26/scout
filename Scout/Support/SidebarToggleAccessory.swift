import AppKit
import SwiftUI

/// Puts the sidebar toggle in the window's real title bar, right after the traffic
/// lights, so macOS delivers its clicks (anything SwiftUI draws up there gets
/// treated as part of the title bar and drags the window instead).
///
/// With the sidebar shown, the accessory stretches to the sidebar's right edge and
/// the toggle sits at its end; with it hidden, the toggle sits next to the lights.
struct SidebarToggleAccessory: NSViewRepresentable {
    let window: BrowserWindowModel

    func makeNSView(context: Context) -> AccessoryInstaller {
        AccessoryInstaller(model: window)
    }

    func updateNSView(_ view: AccessoryInstaller, context: Context) {
        view.update(sidebarShown: window.isSidebarShown)
    }
}

final class AccessoryInstaller: NSView {
    private let model: BrowserWindowModel
    private var controller: NSTitlebarAccessoryViewController?

    init(model: BrowserWindowModel) {
        self.model = model
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window, controller == nil else { return }
        let host = ClickableHostingView(rootView: SidebarToggleBar(window: model))
        host.frame = NSRect(x: 0, y: 0, width: Self.width(sidebarShown: model.isSidebarShown), height: Layout.titleRowHeight)
        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .leading
        accessory.view = host
        window.addTitlebarAccessoryViewController(accessory)
        controller = accessory
    }

    func update(sidebarShown: Bool) {
        guard let view = controller?.view else { return }
        let width = Self.width(sidebarShown: sidebarShown)
        if view.frame.width != width { view.frame.size.width = width }
    }

    /// The accessory starts where the traffic lights end; stretch it so the toggle
    /// lands at the sidebar's right edge (10pt in), or keep it tight when hidden.
    static func width(sidebarShown: Bool) -> CGFloat {
        sidebarShown ? Layout.sidebarWidth - 10 - Layout.trafficLightsWidth : 36
    }
}

private struct SidebarToggleBar: View {
    let window: BrowserWindowModel

    var body: some View {
        HStack(spacing: 0) {
            WindowDragArea() // the empty stretch still drags the window
            IconButton(symbol: "sidebar.left",
                       help: window.isSidebarShown ? "Hide Sidebar (⌃⌘S)" : "Show Sidebar (⌃⌘S)") {
                withAnimation(.snappy(duration: 0.25)) { window.isSidebarShown.toggle() }
            }
        }
        .frame(maxHeight: .infinity)
    }
}
