import Foundation
#if canImport(ImageIO)
import ImageIO
import UniformTypeIdentifiers
#endif
#if canImport(PDFKit)
import PDFKit
#endif

/// Image and PDF actions. Originals are never changed: results land next to them.
public enum QuickActions {
    public enum ImageFormat: String, CaseIterable, Sendable, Identifiable {
        case jpeg, png, heic, avif, webp, tiff
        public var id: Self { self }
        public var title: String {
            switch self {
            case .jpeg: "JPEG"
            case .webp: "WebP"
            default: rawValue.uppercased()
            }
        }
        public var fileExtension: String { self == .jpeg ? "jpg" : rawValue }
        var type: UTType {
            switch self {
            case .jpeg: .jpeg
            case .png: .png
            case .heic: .heic
            case .avif: UTType("public.avif") ?? .heic
            case .webp: .webP
            case .tiff: .tiff
            }
        }

        /// Formats this Mac can write. Apple's ImageIO writes everything but WebP, which
        /// needs Google's `cwebp` (`brew install webp`).
        public static var available: [ImageFormat] {
            allCases.filter { $0 != .webp || WebPEncoder.path != nil }
        }
    }

    public enum FlipDirection: String, CaseIterable, Sendable, Identifiable {
        case horizontal, vertical
        public var id: Self { self }
        public var title: String { self == .horizontal ? "Flip Horizontally" : "Flip Vertically" }
    }

    public enum Failure: LocalizedError {
        case failed(String)
        public var errorDescription: String? {
            if case .failed(let message) = self { return message }
            return nil
        }
    }

    public static func isImage(_ url: URL) -> Bool {
        (UTType(filenameExtension: url.pathExtension.lowercased())?.conforms(to: .image)) ?? false
    }

    public static func isPDF(_ url: URL) -> Bool { url.pathExtension.lowercased() == "pdf" }

    #if canImport(ImageIO)
    /// Saves a copy in another format ("photo.heic" → "photo.jpg"), optionally no wider or taller
    /// than `maxPixels`. Returns the new file.
    @discardableResult
    public static func convert(_ url: URL, to format: ImageFormat, maxPixels: Int? = nil, suffix: String = "") throws -> URL {
        let source = try openImage(url)
        let image: CGImage?
        if let maxPixels {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixels,
                kCGImageSourceCreateThumbnailWithTransform: true,
            ]
            image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        } else {
            image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        guard let image else { throw Failure.failed("Couldn’t read “\(url.lastPathComponent)”.") }
        return try save(image, from: source, original: url, format: format, suffix: suffix, upright: maxPixels != nil)
    }

    /// A mirrored copy ("photo flipped.jpg"), same format when possible.
    @discardableResult
    public static func flip(_ url: URL, _ direction: FlipDirection) throws -> URL {
        let source = try openImage(url)
        guard let upright = uprightImage(source), let space = upright.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: upright.width, height: upright.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space.model == .rgb ? space : CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw Failure.failed("Couldn’t read “\(url.lastPathComponent)”.") }
        let width = CGFloat(upright.width), height = CGFloat(upright.height)
        switch direction {
        case .horizontal: context.concatenate(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: width, ty: 0))
        case .vertical: context.concatenate(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: height))
        }
        context.draw(upright, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let flipped = context.makeImage() else { throw Failure.failed("Couldn’t flip “\(url.lastPathComponent)”.") }
        return try save(flipped, from: source, original: url, format: sameFormat(as: url), suffix: " flipped", upright: true)
    }

    private static func openImage(_ url: URL) throws -> CGImageSource {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw Failure.failed("“\(url.lastPathComponent)” isn’t an image Scout can read.")
        }
        return source
    }

    /// The full-size image with its EXIF rotation applied.
    private static func uprightImage(_ source: CGImageSource) -> CGImage? {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int, let height = props[kCGImagePropertyPixelHeight] as? Int
        else { return CGImageSourceCreateImageAtIndex(source, 0, nil) }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height),
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// The format a copy of `url` keeps: its own when Scout can write it, else JPEG.
    static func sameFormat(as url: URL) -> ImageFormat {
        let ext = url.pathExtension.lowercased()
        let format = ImageFormat.available.first { $0.fileExtension == ext || $0.rawValue == ext || (ext == "jpeg" && $0 == .jpeg) }
        return format ?? (ext == "png" || ext == "gif" ? .png : .jpeg)
    }

    /// Writes `image` next to `original` as "<name><suffix>.<ext>", keeping color and EXIF info.
    /// `upright`: the pixels already have the photo's rotation applied.
    private static func save(_ image: CGImage, from source: CGImageSource, original url: URL, format: ImageFormat,
                             suffix: String, upright: Bool) throws -> URL {
        let stem = url.deletingPathExtension().lastPathComponent + suffix
        let destination = LocalFileSource.availableURL(in: url.deletingLastPathComponent(),
                                                       preferredName: stem + "." + format.fileExtension,
                                                       isDirectory: false, style: .numbered)
        if format == .webp {
            try WebPEncoder.write(image, to: destination)
            return destination
        }
        guard let writer = CGImageDestinationCreateWithURL(destination as CFURL, format.type.identifier as CFString, 1, nil) else {
            throw Failure.failed("This Mac can’t write \(format.title) files.")
        }
        // Keep orientation and color info; lossy formats at good quality.
        var properties = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
        if upright { properties[kCGImagePropertyOrientation] = 1 }
        properties[kCGImageDestinationLossyCompressionQuality] = 0.88
        CGImageDestinationAddImage(writer, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(writer) else { throw Failure.failed("Couldn’t save “\(destination.lastPathComponent)”.") }
        return destination
    }

    /// A smaller copy no bigger than `maxPixels` on its longest side ("photo 1280.jpg"), same format when possible.
    @discardableResult
    public static func resize(_ url: URL, maxPixels: Int) throws -> URL {
        try convert(url, to: sameFormat(as: url), maxPixels: maxPixels, suffix: " \(maxPixels)")
    }

    /// Pixel size of an image.
    public static func pixelSize(_ url: URL) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int, let height = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return (width, height)
    }
    #endif

    #if canImport(PDFKit)
    /// Joins PDFs in the order given into "Combined.pdf" next to the first one.
    @discardableResult
    public static func combinePDFs(_ urls: [URL]) throws -> URL {
        guard let first = urls.first else { throw Failure.failed("Pick at least two PDFs.") }
        let combined = PDFDocument()
        for url in urls {
            guard let document = PDFDocument(url: url) else { throw Failure.failed("Couldn’t read “\(url.lastPathComponent)”.") }
            if document.isLocked { throw Failure.failed("“\(url.lastPathComponent)” is password-protected.") }
            for index in 0..<document.pageCount {
                if let page = document.page(at: index) { combined.insert(page, at: combined.pageCount) }
            }
        }
        let destination = LocalFileSource.availableURL(in: first.deletingLastPathComponent(), preferredName: "Combined.pdf",
                                                       isDirectory: false, style: .numbered)
        guard combined.write(to: destination) else { throw Failure.failed("Couldn’t save the combined PDF.") }
        return destination
    }
    #endif
}

#if canImport(ImageIO) && os(macOS)
/// WebP through Google's `cwebp`, since ImageIO reads WebP but can't write it.
enum WebPEncoder {
    static let path: String? = ["/opt/homebrew/bin/cwebp", "/usr/local/bin/cwebp"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }

    static func write(_ image: CGImage, to destination: URL) throws {
        guard let path else { throw QuickActions.Failure.failed("WebP needs cwebp. Install it with “brew install webp”.") }
        let png = FileManager.default.temporaryDirectory.appending(path: "scout-webp-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: png) }
        guard let writer = CGImageDestinationCreateWithURL(png as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw QuickActions.Failure.failed("Couldn’t prepare the WebP file.")
        }
        CGImageDestinationAddImage(writer, image, nil)
        guard CGImageDestinationFinalize(writer) else { throw QuickActions.Failure.failed("Couldn’t prepare the WebP file.") }
        let process = Process()
        process.executableURL = URL(filePath: path)
        process.arguments = ["-quiet", "-q", "88", "-metadata", "icc", png.path, "-o", destination.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            try? FileManager.default.removeItem(at: destination)
            throw QuickActions.Failure.failed("cwebp couldn’t convert “\(destination.lastPathComponent)”.")
        }
    }
}
#endif
