import Foundation
#if canImport(ImageIO)
import ImageIO
#endif

// MARK: - Steps

/// One step of a rename. Steps run in order, each on the result of the one before.
public struct RenameStep: Codable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Identifiable, Sendable {
        /// Find text (or a regular expression) and replace it. An empty replacement removes it.
        case replace
        /// Add text at the start or end.
        case add
        /// Replace the whole name with a template, e.g. "Trip {n}".
        case newName
        /// Remove the first or last few characters.
        case removeCharacters
        /// lowercase, UPPERCASE, Title Case…
        case changeCase
        /// Trim the ends and squeeze repeated spaces.
        case trimSpaces

        public var id: Self { self }
        public var title: String {
            switch self {
            case .replace: "Replace Text"
            case .add: "Add Text"
            case .newName: "New Name"
            case .removeCharacters: "Remove Characters"
            case .changeCase: "Change Case"
            case .trimSpaces: "Trim Spaces"
            }
        }
        public var symbol: String {
            switch self {
            case .replace: "arrow.left.arrow.right"
            case .add: "plus"
            case .newName: "character.cursor.ibeam"
            case .removeCharacters: "delete.left"
            case .changeCase: "textformat"
            case .trimSpaces: "space"
            }
        }
    }

    public enum Position: String, Codable, CaseIterable, Identifiable, Sendable {
        case start, end
        public var id: Self { self }
    }

    public enum CaseStyle: String, Codable, CaseIterable, Identifiable, Sendable {
        case lower, upper, title, sentence, kebab, snake
        public var id: Self { self }
        public var title: String {
            switch self {
            case .lower: "lowercase"
            case .upper: "UPPERCASE"
            case .title: "Title Case"
            case .sentence: "Sentence case"
            case .kebab: "kebab-case"
            case .snake: "snake_case"
            }
        }
    }

    public var id = UUID()
    public var kind: Kind
    /// Replace: what to find. Add: the text. New Name: the template.
    public var text = ""
    /// Replace: what to put instead (variables and, with regex, $1 groups work).
    public var replacement = ""
    public var regex = false
    public var matchCase = false
    public var position = Position.end
    /// Remove Characters: how many.
    public var count = 1
    public var caseStyle = CaseStyle.lower

    public init(_ kind: Kind, text: String = "", replacement: String = "", regex: Bool = false,
                matchCase: Bool = false, position: Position = .end, count: Int = 1, caseStyle: CaseStyle = .lower) {
        self.kind = kind
        self.text = text
        self.replacement = replacement
        self.regex = regex
        self.matchCase = matchCase
        self.position = position
        self.count = count
        self.caseStyle = caseStyle
    }

    /// A problem with the step itself (an invalid regular expression), if any.
    public var problem: String? {
        guard kind == .replace, regex, !text.isEmpty else { return nil }
        do { _ = try NSRegularExpression(pattern: text, options: matchCase ? [] : [.caseInsensitive]) } catch {
            return "That regular expression isn’t valid."
        }
        return nil
    }
}

/// A whole rename: steps plus options. Codable so it can be saved as a preset.
public struct RenamePipeline: Codable, Hashable, Sendable {
    public var steps: [RenameStep]
    /// Apply the steps to the extension too (".JPG" → ".jpg").
    public var includeExtension = false
    /// When two new names clash (or a name is taken), add " 2", " 3"… instead of stopping.
    public var autoNumberConflicts = false
    /// {n}: first number, how much it goes up, and digits (0 = just enough to sort).
    public var startNumber = 1
    public var numberStep = 1
    public var digits = 0

    public init(steps: [RenameStep] = [RenameStep(.replace)]) {
        self.steps = steps
    }

    public var problem: String? { steps.lazy.compactMap(\.problem).first }

    /// True when a step uses {width} or {height} (they need the image read).
    public var needsImageSize: Bool {
        steps.contains { ($0.text + $0.replacement).contains("{width") || ($0.text + $0.replacement).contains("{height") }
    }
}

/// A saved rename.
public struct RenamePreset: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var name: String
    public var pipeline: RenamePipeline
    public var isBuiltIn = false

    public init(name: String, pipeline: RenamePipeline, isBuiltIn: Bool = false) {
        self.name = name
        self.pipeline = pipeline
        self.isBuiltIn = isBuiltIn
    }

    /// Presets that come with Scout.
    public static let builtIn: [RenamePreset] = [
        RenamePreset(name: "Web-friendly names", pipeline: {
            var p = RenamePipeline(steps: [RenameStep(.trimSpaces), RenameStep(.changeCase, caseStyle: .kebab)])
            p.includeExtension = false
            return p
        }(), isBuiltIn: true),
        RenamePreset(name: "Date + number", pipeline: {
            var p = RenamePipeline(steps: [RenameStep(.newName, text: "{created:yyyy-MM-dd} {n}")])
            p.digits = 0
            return p
        }(), isBuiltIn: true),
        RenamePreset(name: "Remove “copy” and numbers like (1)", pipeline: RenamePipeline(steps: [
            RenameStep(.replace, text: #"( copy( \d+)?| \(\d+\))+$"#, regex: true),
        ]), isBuiltIn: true),
        RenamePreset(name: "Lowercase extensions", pipeline: {
            var p = RenamePipeline(steps: [RenameStep(.replace, text: #"\.([^.]+)$"#, replacement: ".{ext:lower}", regex: true)])
            p.includeExtension = true
            return p
        }(), isBuiltIn: true),
    ]
}

// MARK: - Variables

/// What a rename knows about each file, for variables like {created} and {n}.
public struct RenameContext: Sendable {
    public var name: String
    public var parent: String
    public var created: Date?
    public var modified: Date?
    public var added: Date?
    public var width: Int?
    public var height: Int?

    public init(name: String, parent: String = "", created: Date? = nil, modified: Date? = nil,
                added: Date? = nil, width: Int? = nil, height: Int? = nil) {
        self.name = name
        self.parent = parent
        self.created = created
        self.modified = modified
        self.added = added
        self.width = width
        self.height = height
    }

    #if canImport(ImageIO)
    /// Pixel size of an image file, if it is one.
    public static func imageSize(_ url: URL) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return (w, h)
    }
    #endif
}

public enum RenameVariable: CaseIterable, Sendable {
    case name, ext, number, parent, created, modified, added, today, now, width, height, uuid

    public var token: String {
        switch self {
        case .name: "{name}"
        case .ext: "{ext}"
        case .number: "{n}"
        case .parent: "{parent}"
        case .created: "{created}"
        case .modified: "{modified}"
        case .added: "{added}"
        case .today: "{today}"
        case .now: "{now}"
        case .width: "{width}"
        case .height: "{height}"
        case .uuid: "{uuid}"
        }
    }

    public var title: String {
        switch self {
        case .name: "Original name"
        case .ext: "Extension"
        case .number: "Number (1, 2, 3…)"
        case .parent: "Folder name"
        case .created: "Date created"
        case .modified: "Date modified"
        case .added: "Date added"
        case .today: "Today’s date"
        case .now: "Date and time now"
        case .width: "Image width"
        case .height: "Image height"
        case .uuid: "Unique ID"
        }
    }
}

// MARK: - Renaming

public enum BatchRename {
    /// New names for each file, in order. `existing` is the other names in the folder,
    /// used only when the pipeline auto-numbers conflicts.
    public static func newNames(for items: [RenameContext], pipeline: RenamePipeline,
                                existing: Set<String> = [], now: Date = .now) -> [String] {
        guard pipeline.problem == nil else { return items.map(\.name) }
        let lastNumber = pipeline.startNumber + pipeline.numberStep * max(items.count - 1, 0)
        let digits = pipeline.digits > 0 ? pipeline.digits
            : max(String(lastNumber).count, items.count >= 10 ? 2 : 1)
        var names = items.enumerated().map { index, item in
            let number = pipeline.startNumber + pipeline.numberStep * index
            return rename(item, pipeline: pipeline, number: String(format: "%0\(digits)d", number), now: now)
        }
        if pipeline.autoNumberConflicts { names = numberConflicts(names, old: items.map(\.name), existing: existing) }
        return names
    }

    static func rename(_ item: RenameContext, pipeline: RenamePipeline, number: String, now: Date) -> String {
        var (stem, ext) = split(item.name, keepExtension: !pipeline.includeExtension)
        let originalStem = split(item.name, keepExtension: true).stem
        let originalExt = split(item.name, keepExtension: true).ext
        let vars = Variables(item: item, stem: originalStem, ext: originalExt, number: number, now: now)
        for step in pipeline.steps {
            stem = apply(step, to: stem, vars: vars)
        }
        return ext.isEmpty ? stem : stem + "." + ext
    }

    static func apply(_ step: RenameStep, to name: String, vars: Variables) -> String {
        switch step.kind {
        case .replace:
            guard !step.text.isEmpty else { return name }
            if step.regex {
                guard let regex = try? NSRegularExpression(pattern: step.text, options: step.matchCase ? [] : [.caseInsensitive])
                else { return name }
                let template = vars.expand(step.replacement, escapeForRegex: true)
                return regex.stringByReplacingMatches(in: name, range: NSRange(name.startIndex..., in: name), withTemplate: template)
            }
            return name.replacingOccurrences(of: step.text, with: vars.expand(step.replacement),
                                             options: step.matchCase ? [] : [.caseInsensitive])
        case .add:
            let text = vars.expand(step.text)
            return step.position == .start ? text + name : name + text
        case .newName:
            let text = vars.expand(step.text)
            return text.isEmpty ? name : text
        case .removeCharacters:
            let n = max(0, min(step.count, name.count))
            return step.position == .start ? String(name.dropFirst(n)) : String(name.dropLast(n))
        case .changeCase:
            return changeCase(name, to: step.caseStyle)
        case .trimSpaces:
            return name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
    }

    static func changeCase(_ name: String, to style: RenameStep.CaseStyle) -> String {
        switch style {
        case .lower: return name.lowercased()
        case .upper: return name.uppercased()
        case .title: return name.capitalized
        case .sentence: return name.prefix(1).uppercased() + name.dropFirst().lowercased()
        case .kebab, .snake:
            let words = name.lowercased().split { !$0.isLetter && !$0.isNumber }
            return words.joined(separator: style == .kebab ? "-" : "_")
        }
    }

    /// Adds " 2", " 3"… to names that clash with each other or with other files in the folder.
    static func numberConflicts(_ names: [String], old: [String], existing: Set<String>) -> [String] {
        let renaming = Set(old.map { $0.lowercased() })
        var taken = Set(existing.map { $0.lowercased() }.filter { !renaming.contains($0) })
        return names.map { name in
            guard taken.contains(name.lowercased()) else {
                taken.insert(name.lowercased())
                return name
            }
            let (stem, ext) = split(name, keepExtension: true)
            var n = 2
            while true {
                let candidate = ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)"
                if !taken.contains(candidate.lowercased()) {
                    taken.insert(candidate.lowercased())
                    return candidate
                }
                n += 1
            }
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

/// Expands {variables} for one file. Unknown {words} are left as typed; "{{" and "}}" are
/// a literal "{" and "}".
struct Variables {
    let item: RenameContext
    let stem: String
    let ext: String
    let number: String
    let now: Date

    func expand(_ text: String, escapeForRegex: Bool = false) -> String {
        guard text.contains("{") || text.contains("}}") else { return text }
        var output = ""
        var rest = Substring(text)
        func plain(_ s: Substring) -> String { s.replacingOccurrences(of: "}}", with: "}") }
        while let open = rest.firstIndex(of: "{") {
            output += plain(rest[..<open])
            let after = rest.index(after: open)
            if after < rest.endIndex, rest[after] == "{" {
                output += "{"
                rest = rest[rest.index(after: after)...]
                continue
            }
            guard let close = rest[after...].firstIndex(of: "}") else {
                output += rest[open...]
                rest = ""
                break
            }
            let token = String(rest[after..<close])
            if let value = value(for: token) {
                output += escapeForRegex ? NSRegularExpression.escapedTemplate(for: value) : value
            } else {
                output += rest[open...close]
            }
            rest = rest[rest.index(after: close)...]
        }
        return output + plain(rest)
    }

    /// "created:yyyy-MM-dd" → the date in that format; "ext:lower" → lowercased extension.
    func value(for token: String) -> String? {
        let parts = token.split(separator: ":", maxSplits: 1).map(String.init)
        let key = parts[0].lowercased()
        let format = parts.count > 1 ? parts[1] : nil
        func date(_ d: Date?, _ fallback: String) -> String {
            guard let d else { return "" }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format ?? fallback
            return formatter.string(from: d).replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: ".")
        }
        func cased(_ s: String) -> String {
            switch format?.lowercased() {
            case "lower": s.lowercased()
            case "upper": s.uppercased()
            default: s
            }
        }
        switch key {
        case "name": return cased(stem)
        case "ext": return cased(ext)
        case "n": return number
        case "parent": return cased(item.parent)
        case "created": return date(item.created, "yyyy-MM-dd")
        case "modified": return date(item.modified, "yyyy-MM-dd")
        case "added": return date(item.added, "yyyy-MM-dd")
        case "today": return date(now, "yyyy-MM-dd")
        case "now": return date(now, "yyyy-MM-dd HHmm")
        case "width": return item.width.map(String.init) ?? ""
        case "height": return item.height.map(String.init) ?? ""
        case "uuid": return String(UUID().uuidString.prefix(8)).lowercased()
        default: return nil
        }
    }
}
