import CoreGraphics
import Foundation
import Testing
@testable import ScoutCore

@Suite struct TreemapTests {
    @Test func areasMatchAndNothingOverlaps() {
        let sizes: [Double] = [6, 6, 4, 3, 2, 2, 1, 0]
        let bounds = CGRect(x: 0, y: 0, width: 600, height: 400)
        let rects = Treemap.layout(sizes, in: bounds)
        #expect(rects.count == sizes.count)
        #expect(rects[7] == .zero) // zero-size items get nothing
        let total = sizes.reduce(0, +)
        for (size, rect) in zip(sizes, rects) where size > 0 {
            let expected = Double(bounds.width * bounds.height) * size / total
            #expect(abs(Double(rect.width * rect.height) - expected) < 0.5)
            #expect(bounds.insetBy(dx: -0.01, dy: -0.01).contains(rect))
        }
        for a in rects.indices where sizes[a] > 0 {
            for b in rects.indices where b > a && sizes[b] > 0 {
                #expect(rects[a].intersection(rects[b]).width * rects[a].intersection(rects[b]).height < 0.01)
            }
        }
        // Squarified: no sliver worse than 1:4 for this data.
        for (size, rect) in zip(sizes, rects) where size > 0 {
            #expect(max(rect.width / rect.height, rect.height / rect.width) < 4)
        }
    }

    @Test func emptyCases() {
        #expect(Treemap.layout([], in: CGRect(x: 0, y: 0, width: 10, height: 10)).isEmpty)
        #expect(Treemap.layout([0, 0], in: CGRect(x: 0, y: 0, width: 10, height: 10)) == [.zero, .zero])
        #expect(Treemap.layout([1], in: .zero) == [.zero])
        #expect(Treemap.layout([5], in: CGRect(x: 2, y: 3, width: 10, height: 20)) == [CGRect(x: 2, y: 3, width: 10, height: 20)])
    }
}
