import Foundation
import Testing
@testable import ScoutCore

@Suite struct FileStatsTests {
    func item(_ name: String, type: String?, size: Int64? = 100, folder: Bool = false) -> FileItem {
        FileItem(url: URL(filePath: "/x/\(name)"), name: name, isDirectory: folder,
                 size: folder ? nil : size, typeIdentifier: type)
    }

    @Test func categorizesCommonTypes() {
        #expect(FileCategory.of(item("a.png", type: "public.png")) == .images)
        #expect(FileCategory.of(item("a.pdf", type: "com.adobe.pdf")) == .documents)
        #expect(FileCategory.of(item("a.xlsx", type: "org.openxmlformats.spreadsheetml.sheet")) == .documents)
        #expect(FileCategory.of(item("a.mov", type: "com.apple.quicktime-movie")) == .videos)
        #expect(FileCategory.of(item("a.zip", type: "public.zip-archive")) == .archives)
        #expect(FileCategory.of(item("a.dmg", type: "com.apple.disk-image-udif")) == .archives)
        #expect(FileCategory.of(item("a.swift", type: "public.swift-source")) == .code)
        #expect(FileCategory.of(item("a", type: nil)) == .other)
        #expect(FileCategory.of(item("dir", type: "public.folder", folder: true)) == .folders)
    }

    @Test func breakdownSumsAndSorts() {
        let items = [
            item("a.png", type: "public.png", size: 300),
            item("b.png", type: "public.png", size: 200),
            item("c.pdf", type: "com.adobe.pdf", size: 100),
            item("dir", type: "public.folder", folder: true),
        ]
        let inside: [FileCategory: Int64] = [.videos: 1_000, .images: 50]
        let result = FolderStats.breakdown(items, folderBreakdowns: [URL(filePath: "/x/dir"): inside])
        #expect(result.map(\.0) == [.videos, .images, .documents])
        #expect(result.map(\.1) == [1_000, 550, 100])
    }

    @Test func measuresRealFolders() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "Stats-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appending(path: "sub"), withIntermediateDirectories: true)
        try Data(count: 10_000).write(to: root.appending(path: "a.bin"))
        try Data(count: 5_000).write(to: root.appending(path: "sub/b.bin"))
        try Data(count: 8_000).write(to: root.appending(path: "photo.png"))
        let app = root.appending(path: "Thing.app/Contents")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try Data(count: 4_000).write(to: app.appending(path: "Info.plist"))
        let size = FolderStats.size(of: root)
        #expect(size.files == 4)
        #expect((size.byCategory[.images] ?? 0) >= 8_000)
        #expect((size.byCategory[.apps] ?? 0) >= 4_000) // counted as the app, not a plist
        #expect(size.byCategory[.code] == nil)
        #expect(size.bytes >= 27_000)
        #expect(!size.isPartial)
        #expect(FolderStats.itemCount(of: root) == 4)
    }
}
