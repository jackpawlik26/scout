import AppKit
import QuickLookThumbnailing
import ScoutCore
import SwiftUI
import UniformTypeIdentifiers

enum Format {
    static func size(_ item: FileItem) -> String {
        if item.isNavigable {
            return item.folderBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "--"
        }
        guard let size = item.size else { return "--" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    /// Finder-style dates: "Today at 3:41 PM", "Yesterday at 9:02 AM", "Nov 3, 2026 at 1:15 PM".
    static func date(_ date: Date?) -> String {
        guard let date else { return "--" }
        let time = date.formatted(date: .omitted, time: .shortened)
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today at \(time)" }
        if calendar.isDateInYesterday(date) { return "Yesterday at \(time)" }
        return "\(date.formatted(date: .abbreviated, time: .omitted)) at \(time)"
    }
}

/// A date that shortens to fit its column, like Finder:
/// "Mar 24, 2026 at 10:48 PM" → "Mar 24, 2026" → "3/24/26".
struct FittingDate: View {
    let date: Date?

    var body: some View {
        if let date {
            ViewThatFits(in: .horizontal) {
                Text(Format.date(date))
                Text(Calendar.current.isDateInToday(date) ? "Today" : date.formatted(date: .abbreviated, time: .omitted))
                Text(date.formatted(date: .numeric, time: .omitted))
            }
            .lineLimit(1)
        } else {
            Text("--")
        }
    }
}

/// File icons, cached so scrolling stays smooth.
enum IconCache {
    private static let cache = NSCache<NSString, NSImage>()

    static func icon(for item: FileItem) -> NSImage {
        // Folders and apps can have their own icons; plain files share one per type.
        let byType = !item.isDirectory && !item.isPackage && item.typeIdentifier != nil
        let key = byType ? "type:\(item.typeIdentifier!)" : item.path
        if let cached = cache.object(forKey: key as NSString) { return cached }
        let image = byType
            ? NSWorkspace.shared.icon(for: UTType(item.typeIdentifier!) ?? .data)
            : NSWorkspace.shared.icon(forFile: item.path)
        cache.setObject(image, forKey: key as NSString)
        return image
    }

    static func icon(forPath path: String) -> NSImage {
        if let cached = cache.object(forKey: path as NSString) { return cached }
        let image = NSWorkspace.shared.icon(forFile: path)
        cache.setObject(image, forKey: path as NSString)
        return image
    }
}

struct FileIconView: View {
    let item: FileItem
    var size: CGFloat = 16

    var body: some View {
        Image(nsImage: IconCache.icon(for: item))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}

/// Real previews (photo, PDF page, video frame) for the icon view, falling back to the icon.
struct ThumbnailView: View {
    let item: FileItem
    let size: CGFloat
    @State private var thumbnail: NSImage?

    var body: some View {
        Group {
            if let thumbnail {
                // Real previews get rounded corners and a soft shadow so they read as objects.
                Image(nsImage: thumbnail)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: max(3, size / 28)))
                    .overlay(RoundedRectangle(cornerRadius: max(3, size / 28)).strokeBorder(.black.opacity(0.08)))
                    .shadow(color: .black.opacity(0.18), radius: size / 40, y: size / 80)
            } else {
                Image(nsImage: IconCache.icon(for: item))
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            }
        }
        .frame(width: size, height: size)
            .task(id: item) {
                thumbnail = nil
                guard !item.isDirectory else { return }
                thumbnail = await Self.makeThumbnail(for: item.url, size: size)
            }
    }

    static func makeThumbnail(for url: URL, size: CGFloat) async -> NSImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: size, height: size),
            scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
        guard let cgImage = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).cgImage
        else { return nil }
        return NSImage(cgImage: cgImage, size: .zero)
    }
}
