import AppKit
import SwiftUI

/// Scout's colors and shared controls. The window is a tinted "chrome" frame
/// with content on rounded "canvas" cards floating on it.
extension Color {
    /// The window frame and sidebar: faintly purple.
    static let chrome = Color(light: 0xEEEDF6, dark: 0x141319)
    /// Content cards.
    static let canvas = Color(light: 0xFFFFFF, dark: 0x1C1B22)
    /// Panels inside a card (inspector boxes, search header).
    static let raised = Color(light: 0xF6F5FB, dark: 0x25242C)
    /// Thin borders.
    static let hairline = Color(light: NSColor.black.withAlphaComponent(0.08), dark: NSColor.white.withAlphaComponent(0.07))
    /// Selected rows: the accent, softened.
    static let accentSoft = Color.accentColor.opacity(0.16)

    init(light: Int, dark: Int) {
        self.init(light: NSColor(hex: light), dark: NSColor(hex: dark))
    }

    init(light: NSColor, dark: NSColor) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}

extension NSColor {
    convenience init(hex: Int) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension View {
    /// A rounded content card on the chrome.
    func canvasCard(radius: CGFloat = 12) -> some View {
        self
            .background(CanvasFill())
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Color.hairline))
            .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }
}

// MARK: - Transparency

/// Settings ▸ Appearance ▸ Transparency: how much of the desktop shows through
/// (0 = solid), and whether it's blurred. Cards stay more solid than the frame so text reads.
enum Transparency {
    static let amountKey = "transparency"
    static let blurKey = "transparencyBlur"

    /// Opacity of the window frame (sidebar, gaps) for a transparency amount.
    static func chromeOpacity(_ amount: Double) -> Double { 1 - amount * 0.92 }
    /// Opacity of the content cards.
    static func canvasOpacity(_ amount: Double) -> Double { 1 - amount * 0.7 }
    /// Opacity of panels inside cards (they sit on a card that's already partly see-through).
    static func raisedOpacity(_ amount: Double) -> Double { 1 - amount * 0.6 }
}

/// The window's background: solid chrome, or chrome over the (blurred) desktop.
struct WindowBackdrop: View {
    @AppStorage(Transparency.amountKey) private var amount = 0.0
    @AppStorage(Transparency.blurKey) private var blur = true

    var body: some View {
        ZStack {
            if amount > 0, blur { BehindWindowBlur() }
            Color.chrome.opacity(Transparency.chromeOpacity(amount))
        }
    }
}

/// A content card's fill.
struct CanvasFill: View {
    @AppStorage(Transparency.amountKey) private var amount = 0.0

    var body: some View {
        Color.canvas.opacity(Transparency.canvasOpacity(amount))
    }
}

/// A panel inside a card (info boxes, the search and workspace bars).
struct RaisedFill<S: Shape>: View {
    var shape: S
    @AppStorage(Transparency.amountKey) private var amount = 0.0

    var body: some View {
        shape.fill(Color.raised.opacity(Transparency.raisedOpacity(amount)))
    }
}

/// Blurs whatever is behind the window (the desktop, other apps).
private struct BehindWindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active // keep the blur when the window isn't frontmost
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

extension NSWindow {
    /// See-through when transparency is on, a normal solid window otherwise.
    func applyTransparency(_ amount: Double) {
        let clear = amount > 0
        isOpaque = !clear
        backgroundColor = clear ? .clear : .windowBackgroundColor
        invalidateShadow()
    }
}

enum Layout {
    /// Height of the row that holds the traffic lights. In a hidden-title-bar window
    /// macOS centers them 16pt from the top (measured: the close button spans
    /// 9–23pt), so 28pt controls centered in a 32pt row line up with them.
    static let titleRowHeight: CGFloat = 32
    /// Room the traffic lights take from the window's left edge.
    static let trafficLightsWidth: CGFloat = 78
    static let sidebarWidth: CGFloat = 236
    /// Gap around the floating cards.
    static let gutter: CGFloat = 8
}

/// Light, dark, or follow the Mac (View → Appearance).
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: Self { self }

    var title: String {
        switch self {
        case .system: "Match System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    static var saved: AppAppearance {
        AppAppearance(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "") ?? .system
    }

    func apply() {
        UserDefaults.standard.set(rawValue, forKey: "appearance")
        switch self {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

/// A small square icon button with a hover state, used in headers.
struct IconButton: View {
    let symbol: String
    var isOn = false
    let help: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 28)
                .foregroundStyle(isOn ? Color.accentColor : .secondary)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isOn ? Color.accentSoft : (isHovering ? Color.primary.opacity(0.07) : .clear))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(help)
    }
}

/// A keyboard shortcut shown as a little key cap, e.g. ⌘K.
struct KeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.hairline))
    }
}

/// A SwiftUI host whose clicks are clicks, never window drags. Scout's window has
/// no visible title bar, but macOS still treats the top 32pt as one: a click there
/// drags the window if the view under it allows it.
final class ClickableHostingView<Content: View>: NSHostingView<Content> {
    required init(rootView: Content) {
        super.init(rootView: rootView)
        // Sitting in the title-bar zone, it would otherwise inset its content
        // below the title bar (pushing the button down out of line).
        safeAreaRegions = []
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var mouseDownCanMoveWindow: Bool { false }
}

/// Lets an empty area drag the window around (we draw our own title bar).
struct WindowDragArea: View {
    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(WindowDragGesture())
            .allowsWindowActivationEvents(true)
    }
}

// MARK: - Accent color

/// Settings ▸ Appearance ▸ Accent color. Stored as AppKit's own per-app override
/// (`AppleAccentColor` in Scout's defaults), so lists, switches and Scout's highlights all
/// follow it. AppKit reads it at launch, so changing it asks for a restart.
enum AccentChoice: Int, CaseIterable, Identifiable {
    /// Scout's own purple (the AccentColor asset): no override.
    case scout = 99
    case blue = 4, purple = 5, pink = 6, red = 0, orange = 1, yellow = 2, green = 3, graphite = -1

    var id: Int { rawValue }
    static let key = "AppleAccentColor"

    var title: String {
        switch self {
        case .scout: "Scout"
        case .blue: "Blue"
        case .purple: "Purple"
        case .pink: "Pink"
        case .red: "Red"
        case .orange: "Orange"
        case .yellow: "Yellow"
        case .green: "Green"
        case .graphite: "Graphite"
        }
    }

    var swatch: Color {
        switch self {
        case .scout: Color(light: 0x6553F0, dark: 0x7D70F3)
        case .blue: Color(nsColor: .systemBlue)
        case .purple: Color(nsColor: .systemPurple)
        case .pink: Color(nsColor: .systemPink)
        case .red: Color(nsColor: .systemRed)
        case .orange: Color(nsColor: .systemOrange)
        case .yellow: Color(nsColor: .systemYellow)
        case .green: Color(nsColor: .systemGreen)
        case .graphite: Color(nsColor: .systemGray)
        }
    }

    /// What's saved now (applies from the next launch).
    static var saved: AccentChoice {
        guard UserDefaults.standard.object(forKey: key) != nil else { return .scout }
        return AccentChoice(rawValue: UserDefaults.standard.integer(forKey: key)) ?? .scout
    }

    func save() {
        if self == .scout {
            UserDefaults.standard.removeObject(forKey: Self.key)
        } else {
            UserDefaults.standard.set(rawValue, forKey: Self.key)
        }
    }

    /// The color Scout launched with.
    static let launched = saved
}

enum Relaunch {
    /// Quits and reopens Scout (windows and tabs come back).
    static func now() {
        let path = Bundle.main.bundlePath
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = ["-c", "while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.1; done; /usr/bin/open \"$0\"", path]
        try? process.run()
        NSApp.terminate(nil)
    }
}
