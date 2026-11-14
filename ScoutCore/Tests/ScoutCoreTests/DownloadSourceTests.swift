import Foundation
import Testing
@testable import ScoutCore

@Suite struct DownloadSourceTests {
    @Test func browserDownloadNamesThePage() throws {
        let source = try #require(DownloadSource(whereFroms: [
            "https://instructure-uploads.s3.amazonaws.com/files/123/syllabus.pdf?sig=abc",
            "https://www.canvas.depaul.edu/courses/42/files",
        ]))
        #expect(source.site == "canvas.depaul.edu")
        #expect(source.summary == "canvas.depaul.edu")
        #expect(source.openURL?.absoluteString == "https://www.canvas.depaul.edu/courses/42/files")
        #expect(source.fileSite == "instructure-uploads.s3.amazonaws.com")
        #expect(!source.isMail)
    }

    @Test func fileAddressAloneIsEnough() throws {
        let source = try #require(DownloadSource(whereFroms: ["https://www.figma.com/file/x"]))
        #expect(source.site == "figma.com")
        #expect(source.pageURL == nil)
    }

    @Test func chromeBlobAddresses() throws {
        let source = try #require(DownloadSource(whereFroms: ["blob:https://app.example.com/5f2c", "about:blank"]))
        #expect(source.site == "app.example.com")
    }

    @Test func mailAttachment() throws {
        let source = try #require(DownloadSource(whereFroms: [
            "Jane Doe <jane@example.com>", "Q3 numbers", "message:%3C1234@mail.example.com%3E",
        ]))
        #expect(source.isMail)
        #expect(source.site == nil)
        #expect(source.summary == "Jane Doe")
        #expect(source.subject == "Q3 numbers")
        #expect(source.openURL?.scheme == "message")
    }

    @Test func nothingUseful() {
        #expect(DownloadSource(whereFroms: []) == nil)
        #expect(DownloadSource(whereFroms: ["", "data:image/png;base64,AAAA"]) == nil)
    }

    @Test func readsTheAttributeBrowsersWrite() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "source-\(UUID().uuidString).zip")
        try "x".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(DownloadSource.read(url) == nil)

        try DownloadSource.writeEntries(["https://github.com/x/y/releases/a.zip", "https://github.com/x/y"], to: url)
        #expect(DownloadSource.read(url)?.site == "github.com")
        #expect(LocalFileSource.item(for: url)?.source?.site == "github.com")
    }
}

@Suite struct SourceSearchTests {
    @Test func fromWordBecomesAFilter() {
        let spec = SearchSpec(query: "syllabus from:canvas.depaul.edu", scope: .files)
        #expect(spec.source == "canvas.depaul.edu")
        #expect(spec.words == ["syllabus"])
        #expect(spec.nameQuery == "syllabus")
        #expect(spec.hasFileFilters)
        #expect(!spec.includesIndexedFolders)
        #expect(spec.summary == "“syllabus” · from canvas.depaul.edu")

        let q = SpotlightQueryBuilder.queryString(for: spec)
        #expect(q == #"(kMDItemFSName == "*syllabus*"cd || kMDItemTextContent == "syllabus*"cdw) && "#
            + #"kMDItemWhereFroms == "*canvas.depaul.edu*"cd && kMDItemContentType != "public.folder""#)
    }

    @Test func fromAloneSearches() {
        let spec = SearchSpec(query: "FROM:github")
        #expect(spec.source == "github")
        #expect(spec.words.isEmpty)
        #expect(spec.includesSpotlight)
        #expect(SpotlightQueryBuilder.queryString(for: spec) == #"kMDItemWhereFroms == "*github*"cd"#)
    }

    @Test func bareFromIsAWord() {
        let spec = SearchSpec(query: "from:")
        #expect(spec.source == nil)
        #expect(spec.words == ["from:"])
    }
}
