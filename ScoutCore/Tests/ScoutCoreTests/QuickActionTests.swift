import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import Testing
import UniformTypeIdentifiers
@testable import ScoutCore

@Suite struct QuickActionTests {
    let dir = FileManager.default.temporaryDirectory.appending(path: "Quick-\(UUID().uuidString)")

    private func makePNG(_ name: String, width: Int, height: Int) throws -> URL {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(red: 0.4, green: 0.3, blue: 0.9, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let url = dir.appending(path: name)
        let writer = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(writer, context.makeImage()!, nil)
        CGImageDestinationFinalize(writer)
        return url
    }

    @Test func convertsAndResizes() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let png = try makePNG("shot.png", width: 2000, height: 1000)
        let jpg = try QuickActions.convert(png, to: .jpeg)
        #expect(jpg.lastPathComponent == "shot.jpg")
        #expect(QuickActions.pixelSize(jpg)?.width == 2000)
        let small = try QuickActions.resize(png, maxPixels: 800)
        #expect(small.lastPathComponent == "shot 800.png")
        #expect(QuickActions.pixelSize(small).map { [$0.width, $0.height] } == [800, 400])
        #expect(FileManager.default.fileExists(atPath: png.filePath)) // original kept
    }

    @Test func flipsAndWritesAVIF() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        // Left half red, right half blue: flipping horizontally swaps them.
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let context = CGContext(data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        context.setFillColor(red: 0, green: 0, blue: 1, alpha: 1)
        context.fill(CGRect(x: 20, y: 0, width: 20, height: 20))
        let png = dir.appending(path: "halves.png")
        let writer = CGImageDestinationCreateWithURL(png as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(writer, context.makeImage()!, nil)
        CGImageDestinationFinalize(writer)

        let flipped = try QuickActions.flip(png, .horizontal)
        #expect(flipped.lastPathComponent == "halves flipped.png")
        let image = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(flipped as CFURL, nil)!, 0, nil)!
        let pixels = CGContext(data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 160,
                               space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        pixels.draw(image, in: CGRect(x: 0, y: 0, width: 40, height: 20))
        let bytes = pixels.data!.assumingMemoryBound(to: UInt8.self)
        #expect(bytes[2] > 200 && bytes[0] < 50) // leftmost pixel is now blue
        #expect(bytes[39 * 4] > 200)              // rightmost pixel is now red

        let avif = try QuickActions.convert(png, to: .avif)
        #expect(avif.lastPathComponent == "halves.avif")
        #expect(QuickActions.pixelSize(avif)?.width == 40)
    }

    @Test func combinesPDFs() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var urls: [URL] = []
        for (index, pages) in [2, 3].enumerated() {
            let document = PDFDocument()
            for _ in 0..<pages { document.insert(PDFPage(), at: document.pageCount) }
            let url = dir.appending(path: "part\(index).pdf")
            #expect(document.write(to: url))
            urls.append(url)
        }
        let combined = try QuickActions.combinePDFs(urls)
        #expect(combined.lastPathComponent == "Combined.pdf")
        #expect(PDFDocument(url: combined)?.pageCount == 5)
    }
}
