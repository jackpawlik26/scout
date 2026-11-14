import CoreGraphics
import Foundation

/// Lays out sizes as rectangles whose areas match (the disk map). Uses the "squarified"
/// method (Bruls, Huizing, van Wijk), which keeps blocks close to square so they're easy
/// to see and click.
public enum Treemap {
    /// One rectangle per size, in the same order as `sizes`. Zero and negative sizes get an
    /// empty rectangle. Works best with sizes sorted biggest first.
    public static func layout(_ sizes: [Double], in rect: CGRect) -> [CGRect] {
        var result = Array(repeating: CGRect.zero, count: sizes.count)
        let total = sizes.reduce(0) { $0 + max($1, 0) }
        guard total > 0, rect.width > 0, rect.height > 0 else { return result }
        // Areas in points², with their original positions.
        let scale = Double(rect.width * rect.height) / total
        var items = sizes.enumerated().filter { $0.element > 0 }.map { (index: $0.offset, area: $0.element * scale) }
        items.sort { $0.area > $1.area }

        var free = rect
        var row: [(index: Int, area: Double)] = []
        var i = 0
        while i < items.count {
            let side = Double(min(free.width, free.height))
            let candidate = row + [items[i]]
            if row.isEmpty || worst(candidate, side: side) <= worst(row, side: side) {
                row = candidate
                i += 1
            } else {
                free = place(row, in: free, into: &result)
                row = []
            }
        }
        if !row.isEmpty { _ = place(row, in: free, into: &result) }
        return result
    }

    /// The worst aspect ratio in a row laid along a side of length `side`.
    static func worst(_ row: [(index: Int, area: Double)], side: Double) -> Double {
        let sum = row.reduce(0) { $0 + $1.area }
        guard sum > 0, side > 0 else { return .infinity }
        let biggest = row.map(\.area).max()!, smallest = row.map(\.area).min()!
        let s2 = side * side, sum2 = sum * sum
        return max(s2 * biggest / sum2, sum2 / (s2 * smallest))
    }

    /// Lays a row along the shorter side of `free`; returns what's left.
    static func place(_ row: [(index: Int, area: Double)], in free: CGRect, into result: inout [CGRect]) -> CGRect {
        let sum = row.reduce(0) { $0 + $1.area }
        if free.width >= free.height {
            // A column on the left.
            let width = CGFloat(sum / Double(free.height))
            var y = free.minY
            for item in row {
                let height = CGFloat(item.area) / width
                result[item.index] = CGRect(x: free.minX, y: y, width: width, height: height)
                y += height
            }
            return CGRect(x: free.minX + width, y: free.minY, width: max(0, free.width - width), height: free.height)
        } else {
            // A row along the top.
            let height = CGFloat(sum / Double(free.width))
            var x = free.minX
            for item in row {
                let width = CGFloat(item.area) / height
                result[item.index] = CGRect(x: x, y: free.minY, width: width, height: height)
                x += width
            }
            return CGRect(x: free.minX, y: free.minY + height, width: free.width, height: max(0, free.height - height))
        }
    }
}
