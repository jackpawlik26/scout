import AppKit
import ScoutCore
import SwiftUI

extension FileTag {
    var nsColor: NSColor {
        switch color {
        case 1: .systemGray
        case 2: .systemGreen
        case 3: .systemPurple
        case 4: .systemBlue
        case 5: .systemYellow
        case 6: .systemRed
        case 7: .systemOrange
        default: .tertiaryLabelColor
        }
    }

    var swiftUIColor: Color { Color(nsColor: nsColor) }

    /// A colored dot for menus (menu images are otherwise drawn in one color).
    var menuImage: NSImage {
        let image = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            self.nsColor.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            if self.color == 0 {
                NSColor.secondaryLabelColor.setStroke()
                NSBezierPath(ovalIn: rect.insetBy(dx: 1.5, dy: 1.5)).stroke()
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}

/// Finder-style overlapping tag dots.
struct TagDots: View {
    let tags: [FileTag]
    var size: CGFloat = 9

    var body: some View {
        if !tags.isEmpty {
            HStack(spacing: -size * 0.35) {
                ForEach(tags.prefix(4)) { tag in
                    Circle()
                        .fill(tag.color == 0 ? Color.clear : tag.swiftUIColor)
                        .overlay(Circle().strokeBorder(tag.color == 0 ? Color.secondary : Color.black.opacity(0.15), lineWidth: 1))
                        .frame(width: size, height: size)
                }
            }
            .help(tags.map(\.name).joined(separator: ", "))
        }
    }
}

/// Right-click ▸ Tags: Finder's colors plus your own tags, ticked when every item has it.
struct TagsMenu: View {
    let browser: BrowserModel
    let items: [FileItem]

    var body: some View {
        Menu("Tags") {
            ForEach(browser.services.allTags) { tag in
                Toggle(isOn: Binding(
                    get: { !items.isEmpty && items.allSatisfy { $0.tags.contains { $0.name == tag.name } } },
                    set: { _ in browser.toggleTag(tag, on: items) }
                )) {
                    Label { Text(tag.name) } icon: { Image(nsImage: tag.menuImage) }
                }
            }
            Divider()
            Button("New Tag…") { browser.newTagItems = items }
            if items.contains(where: { !$0.tags.isEmpty }) {
                Button("Remove All Tags") { browser.removeTags(from: items) }
            }
        }
    }
}
