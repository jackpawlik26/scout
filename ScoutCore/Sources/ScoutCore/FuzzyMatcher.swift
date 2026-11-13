import Foundation

public struct FuzzyMatch: Sendable, Equatable {
    public var score: Int
    /// Character offsets in the candidate that matched, for bolding.
    public var indices: [Int]
}

/// Fuzzy matching in the style of fzf / VS Code's ⌘P.
///
/// "dl" matches "Downloads", "scpr" matches "Scout/Projects". Letters must appear in
/// order. Matches at word starts and runs of consecutive letters score higher.
/// Spaces split the query into words that must all match.
public enum FuzzyMatcher {
    public static func match(_ query: String, in candidate: String) -> FuzzyMatch? {
        let tokens = query.lowercased().split(whereSeparator: \.isWhitespace).map { Array($0) }
        guard !tokens.isEmpty else { return FuzzyMatch(score: 0, indices: []) }

        let chars = Array(candidate)
        let lower = chars.map { $0.lowercased().first ?? $0 }

        var total = 0
        var indices = Set<Int>()
        for token in tokens {
            guard let m = matchToken(token, chars: chars, lower: lower) else { return nil }
            total += m.score
            indices.formUnion(m.indices)
        }

        let candidateLower = candidate.lowercased()
        let queryLower = query.lowercased().trimmingCharacters(in: .whitespaces)
        if candidateLower == queryLower {
            total += 40
        } else if candidateLower.hasPrefix(queryLower) {
            total += 15
        }
        // Slight preference for shorter candidates.
        total -= chars.count / 6
        return FuzzyMatch(score: total, indices: indices.sorted())
    }

    /// Cheap check that every query byte appears in order. Used to skip most
    /// candidates before the real scoring. Never rejects a real match.
    public static func mightMatch(queryUTF8: [UInt8], candidateLower: String) -> Bool {
        var qi = 0
        guard !queryUTF8.isEmpty else { return true }
        for byte in candidateLower.utf8 where byte == queryUTF8[qi] {
            qi += 1
            if qi == queryUTF8.count { return true }
        }
        return false
    }

    private static func matchToken(_ q: [Character], chars: [Character], lower: [Character]) -> FuzzyMatch? {
        guard let firstChar = q.first else { return FuzzyMatch(score: 0, indices: []) }
        var best: FuzzyMatch?
        var attempts = 0

        // Try each place the first letter appears and keep the best-scoring run.
        for start in lower.indices where lower[start] == firstChar {
            attempts += 1
            if attempts > 16 { break }
            var idx = [start]
            var qi = 1
            var i = start + 1
            while qi < q.count, i < lower.count {
                if lower[i] == q[qi] {
                    idx.append(i)
                    qi += 1
                }
                i += 1
            }
            // If this start can't finish, no later start can either.
            if qi < q.count { break }
            let s = score(idx, chars)
            if best == nil || s > best!.score { best = FuzzyMatch(score: s, indices: idx) }
        }
        return best
    }

    private static func score(_ idx: [Int], _ chars: [Character]) -> Int {
        var s = 0
        for (k, i) in idx.enumerated() {
            s += 16 + boundaryBonus(at: i, chars)
            if k > 0 {
                let gap = i - idx[k - 1] - 1
                s += gap == 0 ? 8 : -(3 + min(gap - 1, 12))
            }
        }
        if idx.first == 0 { s += 6 }
        return s
    }

    private static func boundaryBonus(at i: Int, _ chars: [Character]) -> Int {
        if i == 0 { return 12 }
        let prev = chars[i - 1], cur = chars[i]
        if prev == "/" { return 12 }
        if prev == " " || prev == "_" || prev == "-" || prev == "." || prev.isWhitespace { return 10 }
        if prev.isLowercase && cur.isUppercase { return 8 }
        if prev.isLetter && cur.isNumber { return 4 }
        return 0
    }
}
