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
        case jpeg, png, heic, tiff
        public var id: Self { self }
        public var title: String { rawValue == "jpeg" ? "JPEG" : rawValue.uppercased() }
        public var fileExtension: String { self == .jpeg ? "jpg" : rawValue }
        var type: UTType {
            switch self {
            case .jpeg: .jpeg
            case .png: .png
            case .heic: .heic
            case .tiff: .tiff
            }
        }
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
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw Failure.failed("“\(url.lastPathComponent)” isn’t an image Scout can read.")
        }
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
        let stem = url.deletingPathExtension().lastPathComponent + suffix
        let destination = LocalFileSource.availableURL(in: url.deletingLastPathComponent(),
                                                       preferredName: stem + "." + format.fileExtension,
                                                       isDirectory: false, style: .numbered)
        guard let writer = CGImageDestinationCreateWithURL(destination as CFURL, format.type.identifier as CFString, 1, nil) else {
            throw Failure.failed("This Mac can’t write \(format.title) files.")
        }
        // Keep orientation and color info; JPEG/HEIC at good quality.
        var properties = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
        if maxPixels != nil { properties[kCGImagePropertyOrientation] = 1 } // thumbnail is already upright
        properties[kCGImageDestinationLossyCompressionQuality] = 0.88
        CGImageDestinationAddImage(writer, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(writer) else { throw Failure.failed("Couldn’t save “\(destination.lastPathComponent)”.") }
        return destination
    }

    /// A smaller copy no bigger than `maxPixels` on its longest side ("photo 1280.jpg"), same format when possible.
    @discardableResult
    public static func resize(_ url: URL, maxPixels: Int) throws -> URL {
        let ext = url.pathExtension.lowercased()
        let format = ImageFormat.allCases.first { $0.fileExtension == ext || $0.rawValue == ext } ?? .jpeg
        return try convert(url, to: format, maxPixels: maxPixels, suffix: " \(maxPixels)")
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
