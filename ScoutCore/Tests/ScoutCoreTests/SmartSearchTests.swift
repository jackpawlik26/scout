import Foundation
import Testing
@testable import ScoutCore

@Suite struct SmartSearchTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Chicago")!
        return c
    }()

    @Test func cleansTheModelsAnswer() throws {
        // What the model actually said for "the lease I signed last spring".
        let plan = SearchPlan(keywords: ["lease", "spring"], kind: "documents", after: "2026-03-01", before: "2026-05-31")
        let spec = try #require(plan.spec(calendar: calendar))
        #expect(spec.query == "lease")
        #expect(spec.kind == .documents)
        #expect(spec.scope == .files)
        #expect(spec.after == calendar.date(from: DateComponents(year: 2026, month: 3, day: 1)))
        // "before" includes the whole last day.
        #expect(spec.before == calendar.date(from: DateComponents(year: 2026, month: 6, day: 1)))

        let query = try #require(SpotlightQueryBuilder.queryString(for: spec))
        #expect(query.contains("kMDItemFSContentChangeDate >= $time.iso(2026-03-01T06:00:00Z)"))
        #expect(query.contains("kMDItemFSContentChangeDate < $time.iso(2026-06-01T05:00:00Z)"))
    }

    @Test func dropsAmountsFillerAndBadDates() throws {
        let spec = try #require(SearchPlan(keywords: ["receipt", "$100", "Receipt", "files"], kind: "nonsense",
                                           after: "2026-11-30", before: "2026-11-01").spec(calendar: calendar))
        #expect(spec.query == "receipt")
        #expect(spec.kind == nil)
        #expect(spec.after != nil)
        #expect(spec.before == nil) // reversed range: keep only the start
        #expect(SearchPlan(keywords: ["the", "files"], kind: "any", after: "2026-13-40").spec(calendar: calendar) == nil)
    }

    @Test func dateRangeTitle() {
        var spec = SearchSpec(query: "lease")
        spec.after = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1))
        #expect(spec.dateRangeTitle?.hasPrefix("since ") == true)
        #expect(spec.hasFileFilters)
        #expect(!spec.includesIndexedFolders)
    }

    @Test func whatLooksLikeAQuestion() {
        #expect(SearchPlan.looksLikeQuestion("the lease I signed"))
        #expect(!SearchPlan.looksLikeQuestion("lease"))
        #expect(!SearchPlan.looksLikeQuestion("~/Documents/a b c"))
        #expect(!SearchPlan.looksLikeQuestion("syllabus from:canvas spring"))
    }

    @Test func imageText() throws {
        var index = ImageTextIndex()
        let old = Date(timeIntervalSince1970: 1_000)
        index.set("/u/Desktop/Screenshot 1.png", modified: old, text: "Error: Disk Full\nTry again")
        index.set("/u/Desktop/Screenshot 2.png", modified: old.addingTimeInterval(60), text: "Invoice total $40")
        #expect(index.matches("disk error") == ["/u/Desktop/Screenshot 1.png"])
        #expect(index.matches("xy").isEmpty) // too short to mean anything
        #expect(!index.needsReading("/u/Desktop/Screenshot 1.png", modified: old))
        #expect(index.needsReading("/u/Desktop/Screenshot 1.png", modified: old.addingTimeInterval(10)))
        #expect(index.needsReading("/u/new.png", modified: old))

        index.keep(only: ["/u/Desktop/Screenshot 2.png"])
        #expect(index.entries.count == 1)

        let url = FileManager.default.temporaryDirectory.appending(path: "image-text-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try index.save(to: url)
        #expect(ImageTextIndex.load(from: url) == index)
    }

    @Test func aboutVariable() {
        let pipeline = RenamePipeline(steps: [RenameStep(.newName, text: "{created:yyyy-MM-dd} {about}")])
        #expect(pipeline.needsDescriptions)
        let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 12))!
        let described = RenameContext(name: "Screenshot 2026-11-05 at 10.43.51.png", created: date, about: "Xcode Build Error")
        let pending = RenameContext(name: "IMG_4821.jpg", created: date)
        let names = BatchRename.newNames(for: [described, pending], pipeline: pipeline, existing: [])
        #expect(names[0].hasSuffix(" Xcode Build Error.png"))
        // No description (yet): the original name stays.
        #expect(names[1].hasSuffix(" IMG_4821.jpg"))
    }
}
