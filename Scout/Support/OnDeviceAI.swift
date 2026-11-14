import Foundation
import FoundationModels
import PDFKit
import ScoutCore
import UniformTypeIdentifiers
import Vision

/// Apple's on-device model (Apple Intelligence) and Vision's text reading. Nothing
/// leaves the Mac. Every feature here has a plain fallback when the model isn't
/// available (older Macs, Apple Intelligence turned off).
nonisolated enum OnDeviceAI {
    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    // MARK: - Ask Scout

    @Generable
    struct Plan {
        @Guide(description: "One or two distinctive words likely in the file's name or text. Not dates, seasons, amounts, or words like file, document, photo.")
        var keywords: [String]
        @Guide(description: "One of: any, documents, pdfs, images, videos, audio, spreadsheets, presentations, code, archives, apps")
        var kind: String
        @Guide(description: "Start of the time the file was last changed, yyyy-MM-dd, or empty if no time was mentioned")
        var after: String
        @Guide(description: "End of that time, yyyy-MM-dd (inclusive), or empty")
        var before: String
    }

    /// Turns "the lease I signed last spring" into a search.
    static func searchPlan(for query: String, now: Date = .now) async throws -> SearchPlan {
        let today = now.formatted(.iso8601.year().month().day())
        let session = LanguageModelSession(instructions: """
            You turn a person's description of a file on their Mac into a search. Today is \(today).
            "last spring" means March 1 to May 31 of the most recent spring; "this month" means from the 1st of this month to today; "last week" means the 7 days before today.
            Screenshots and photos are images. Receipts, leases, contracts and letters are documents unless a type is named.
            """)
        let plan = try await session.respond(to: query, generating: Plan.self).content
        return SearchPlan(keywords: plan.keywords, kind: plan.kind, after: plan.after, before: plan.before)
    }

    // MARK: - Smart names

    @Generable
    struct Name {
        @Guide(description: "A short file name in Title Case, 2 to 6 words, saying what the file is. No extension, no date, no punctuation except hyphens.")
        var name: String
    }

    /// A short name for what's in a file ("Xcode Build Error", "Acme Invoice March"), or nil.
    static func describe(_ url: URL) async -> String? {
        guard isAvailable else { return nil }
        let text = await contents(of: url, limit: 1500) ?? ""
        let kind = (try? url.resourceValues(forKeys: [.localizedTypeDescriptionKey]).localizedTypeDescription) ?? ""
        let session = LanguageModelSession(instructions: "You name files on a Mac so they're easy to find later.")
        let prompt = """
            Name this file.
            Current name: \(url.lastPathComponent)
            Kind: \(kind)
            \(text.isEmpty ? "Its contents can't be read; go by the current name." : "Text in it:\n\(text)")
            """
        guard let name = try? await session.respond(to: prompt, generating: Name.self).content.name else { return nil }
        return clean(name)
    }

    /// Safe as a file name: no slashes or colons, single spaces, at most 60 characters.
    static func clean(_ name: String) -> String? {
        var result = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        result = result.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: ".-_ \"'"))
        if result.count > 60 { result = String(result.prefix(60)).trimmingCharacters(in: .whitespaces) }
        return result.isEmpty ? nil : result
    }

    // MARK: - Reading what's in a file

    /// Text from an image (read by Vision), a PDF's first pages, or a text file's start.
    static func contents(of url: URL, limit: Int) async -> String? {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return nil }
        if type.conforms(to: .image) { return await imageText(url).map { String($0.prefix(limit)) } }
        if type.conforms(to: .pdf) {
            guard let document = PDFDocument(url: url) else { return nil }
            var text = ""
            for i in 0..<min(document.pageCount, 2) { text += document.page(at: i)?.string ?? "" }
            return text.isEmpty ? nil : String(text.prefix(limit))
        }
        if type.conforms(to: .text) || type.conforms(to: .sourceCode) {
            guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
            defer { try? handle.close() }
            let data = (try? handle.read(upToCount: limit * 2)) ?? Data()
            return String(decoding: data, as: UTF8.self).prefix(limit).description
        }
        return nil
    }

    /// Lines of text Vision finds in an image, or nil if none. `fast` for the background
    /// index (screenshots read fine), accurate for naming.
    static func imageText(_ url: URL, fast: Bool = false) async -> String? {
        var request = RecognizeTextRequest()
        request.recognitionLevel = fast ? .fast : .accurate
        request.usesLanguageCorrection = true
        guard let observations = try? await request.perform(on: url) else { return nil }
        let lines = observations.compactMap { $0.topCandidates(1).first?.string }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}
