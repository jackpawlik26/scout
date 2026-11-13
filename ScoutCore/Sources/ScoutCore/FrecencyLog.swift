import Foundation

/// Remembers which folders you visit, so the ones you use often and recently
/// rank first ("frecency" = frequency + recency, the way Firefox ranks URLs).
public struct FrecencyLog: Codable, Sendable, Equatable {
    /// Path → recent visit times, oldest first.
    public private(set) var entries: [String: [Date]] = [:]

    public static let visitsKept = 10
    public static let pathsKept = 1500
    /// Visits closer together than this count once (e.g. clicking back and forth).
    public static let minimumGap: TimeInterval = 30

    public init() {}

    public mutating func record(_ path: String, at date: Date = .now) {
        var visits = entries[path, default: []]
        if let last = visits.last, date.timeIntervalSince(last) < Self.minimumGap { return }
        visits.append(date)
        if visits.count > Self.visitsKept { visits.removeFirst(visits.count - Self.visitsKept) }
        entries[path] = visits
        if entries.count > Self.pathsKept { prune(now: date) }
    }

    public mutating func forget(_ path: String) {
        entries[path] = nil
    }

    public func score(for path: String, now: Date = .now) -> Double {
        guard let visits = entries[path] else { return 0 }
        return visits.reduce(0) { $0 + Self.weight(age: now.timeIntervalSince($1)) }
    }

    /// The highest-scoring paths, best first.
    public func top(_ count: Int, now: Date = .now) -> [String] {
        entries.keys
            .map { ($0, score(for: $0, now: now)) }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
            .prefix(count)
            .map(\.0)
    }

    static func weight(age: TimeInterval) -> Double {
        let days = age / 86_400
        switch days {
        case ..<1: return 120
        case ..<4: return 100
        case ..<14: return 70
        case ..<31: return 50
        case ..<90: return 30
        default: return 10
        }
    }

    private mutating func prune(now: Date) {
        let keep = Set(top(Self.pathsKept * 9 / 10, now: now))
        entries = entries.filter { keep.contains($0.key) }
    }
}
