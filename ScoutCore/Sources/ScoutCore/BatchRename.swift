import Foundation

/// How to rename many files at once. Rules apply in order: find & replace, case,
/// numbering, then prefix and suffix. Extensions are left alone unless you turn that off.
public struct RenameRules: Equatable, Sendable {
    public enum CaseChange: String, CaseIterable, Sendable, Identifiable {
        case keep, lower, upper, title
        public var id: Self { self }
        public var title: String {
            switch self {
            case .keep: "Keep"
            case .lower: "lowercase"
            case .upper: "UPPERCASE"
            case .title: "Title Case"
            }
        }
    }

    public enum Numbering: String, CaseIterable, Sendable, Identifiable {
        /// No numbers.
        case off
        /// "Report" → "Report 1".
        case append
        /// Every name becomes "Base 1", "Base 2"…
        case replace
        public var id: Self { self }
        public var title: String {
            switch self {
            case .off: "Off"
            case .append: "Add numbers"
            case .replace: "Replace names"
            }
        }
    }

    public var find = ""
    public var replace = ""
    public var matchCase = false
    public var prefix = ""
    public var suffix = ""
    public var caseChange = CaseChange.keep
    public var numbering = Numbering.off
    /// The name for `.replace` numbering ("Trip" → "Trip 01").
    public var baseName = ""
    public var startNumber = 1
    public var separator = " "
    /// Keep ".pdf" etc. out of the rules.
    public var keepExtension = true

    public init() {}

    public var isEmpty: Bool {
        find.isEmpty && prefix.isEmpty && suffix.isEmpty && caseChange == .keep && numbering == .off
    }
}

public enum BatchRename {
    /// New names for `names`, in the same order.
    public static func newNames(for names: [String], rules: RenameRules) -> [String] {
        // Zero-pad so they sort: 01…12, 001…120.
        let lastNumber = rules.startNumber + max(names.count - 1, 0)
        let digits = max(String(lastNumber).count, names.count >= 10 ? 2 : 1)
        return names.enumerated().map { index, name in
            var (stem, ext) = split(name, keepExtension: rules.keepExtension)
            if !rules.find.isEmpty {
                stem = stem.replacingOccurrences(of: rules.find, with: rules.replace,
                                                 options: rules.matchCase ? [] : [.caseInsensitive])
            }
            switch rules.caseChange {
            case .keep: break
            case .lower: stem = stem.lowercased()
            case .upper: stem = stem.uppercased()
            case .title: stem = stem.capitalized
            }
            let number = String(format: "%0\(digits)d", rules.startNumber + index)
            switch rules.numbering {
            case .off: break
            case .append: stem += rules.separator + number
            case .replace:
                let base = rules.baseName.trimmingCharacters(in: .whitespaces)
                stem = base.isEmpty ? number : base + rules.separator + number
            }
            stem = rules.prefix + stem + rules.suffix
            return ext.isEmpty ? stem : stem + "." + ext
        }
    }

    /// Why a new name can't be used, by index: empty, has "/", used twice, or taken by
    /// another file in the folder (`existing`, names not being renamed).
    public static func problems(old: [String], new: [String], existing: Set<String>) -> [Int: String] {
        var problems: [Int: String] = [:]
        let renaming = Set(old)
        var seen: [String: Int] = [:]
        for (index, name) in new.enumerated() {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed == "." || trimmed == ".." {
                problems[index] = "Empty name"
            } else if name.contains("/") || name.contains(":") {
                problems[index] = "Can’t contain / or :"
            } else if name.hasPrefix(".") && !old[index].hasPrefix(".") {
                problems[index] = "Would be hidden"
            } else if let other = seen[name.lowercased()] {
                problems[index] = "Same as another"
                problems[other] = problems[other] ?? "Same as another"
            } else if existing.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame })
                        && !renaming.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
                problems[index] = "Already in this folder"
            }
            seen[name.lowercased()] = index
        }
        return problems
    }

    /// "Report.final.pdf" → ("Report.final", "pdf"). Folders and dotfiles keep the whole name.
    static func split(_ name: String, keepExtension: Bool) -> (stem: String, ext: String) {
        guard keepExtension, let dot = name.lastIndex(of: "."), dot != name.startIndex else { return (name, "") }
        let ext = String(name[name.index(after: dot)...])
        guard !ext.isEmpty, ext.count <= 8, !ext.contains(" ") else { return (name, "") }
        return (String(name[..<dot]), ext)
    }
}
