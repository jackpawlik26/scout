import Quartz
import ScoutCore
import SwiftUI
import UniformTypeIdentifiers

/// The big preview at the top of the info panel: rendered markdown, highlighted code,
/// scrollable PDFs and playable media (via Quick Look), or a thumbnail for the rest.
struct PreviewPane: View {
    let item: FileItem
    @State private var isEditing = false

    enum Style { case markdown, code, text, quickLook, thumbnail }

    nonisolated static let textLimit = 400_000

    static func style(for item: FileItem) -> Style {
        guard !item.isNavigable else { return .thumbnail }
        let ext = item.url.pathExtension.lowercased()
        let type = item.typeIdentifier.flatMap(UTType.init) ?? UTType(filenameExtension: ext)
        let small = (item.size ?? 0) <= textLimit
        if ["md", "markdown", "mdown"].contains(ext) { return small ? .markdown : .thumbnail }
        if CodeHighlighter.languages.keys.contains(ext) || type?.conforms(to: .sourceCode) == true {
            return small ? .code : .thumbnail
        }
        if let type, type.conforms(to: .plainText) || type.conforms(to: .json) || type.conforms(to: .xml) {
            return small ? .text : .thumbnail
        }
        if let type, [UTType.pdf, .movie, .audio, .presentation, .spreadsheet, .rtf, .html].contains(where: type.conforms(to:))
            || ["doc", "docx", "pages", "key", "numbers", "xlsx", "pptx"].contains(ext) {
            return .quickLook
        }
        return .thumbnail
    }

    var body: some View {
        switch Self.style(for: item) {
        case .markdown, .code, .text:
            TextPreview(item: item, style: Self.style(for: item))
                .frame(height: 300)
                .background(RaisedFill(shape: RoundedRectangle(cornerRadius: 10)))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .topTrailing) {
                    if Self.style(for: item) != .code {
                        Button("Edit") { isEditing = true }
                            .controlSize(.small)
                            .padding(8)
                            .help("Edit this file (⌘S saves)")
                    }
                }
                .sheet(isPresented: $isEditing) {
                    TextFileEditor(item: item, isMarkdown: Self.style(for: item) == .markdown)
                }
        case .quickLook:
            QuickLookPreview(url: item.url)
                .frame(height: 300)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        case .thumbnail:
            ThumbnailView(item: item, size: 180)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
    }
}

// MARK: - Quick Look

/// macOS's own previewer, embedded: PDFs scroll, videos play, Office files render.
private struct QuickLookPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .compact)!
        view.shouldCloseWithWindow = false
        view.autostarts = false
        view.previewItem = url as NSURL
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        if (view.previewItem as? NSURL) as URL? != url { view.previewItem = url as NSURL }
    }

    static func dismantleNSView(_ view: QLPreviewView, coordinator: ()) { view.close() }
}

// MARK: - Text, code, markdown

private struct TextPreview: View {
    let item: FileItem
    let style: PreviewPane.Style
    @State private var lines: [String]?

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            if let lines {
                switch style {
                case .markdown: MarkdownLines(lines: lines).padding(12)
                default: CodeLines(lines: lines, language: CodeHighlighter.language(for: item.url)).padding(10)
                }
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(.top, 40)
            }
        }
        .task(id: item.id) {
            lines = nil
            lines = await Self.read(item.url)
        }
    }

    /// The first 400 lines (enough to see what the file is).
    @concurrent nonisolated static func read(_ url: URL) async -> [String] {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return ["Can’t read this file."] }
        let text = String(decoding: data.prefix(PreviewPane.textLimit), as: UTF8.self)
        var lines = text.components(separatedBy: .newlines)
        if lines.count > 400 { lines = Array(lines.prefix(400)) + ["…"] }
        return lines
    }
}

/// Edits a markdown or text file, with a live preview for markdown. Saving checks the file
/// wasn't changed somewhere else in the meantime.
private struct TextFileEditor: View {
    let item: FileItem
    let isMarkdown: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var original = ""
    @State private var loadedDate: Date?
    @State private var problem: String?
    @State private var confirmOverwrite = false

    private var isChanged: Bool { text != original }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(item.name).font(.headline)
                if isChanged { Text("Edited").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save(force: false) }
                    .keyboardShortcut("s")
                    .disabled(!isChanged)
            }
            .padding(12)
            Divider()
            HStack(spacing: 0) {
                TextEditor(text: $text)
                    .font(.system(size: 12.5, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                if isMarkdown {
                    Divider()
                    ScrollView {
                        MarkdownLines(lines: text.components(separatedBy: .newlines), width: 340)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(width: 370)
                }
            }
            if let problem {
                Text(problem).font(.callout).foregroundStyle(.red).padding(8)
            }
        }
        .frame(width: isMarkdown ? 860 : 620, height: 560)
        .onWindowKey(.escape) {
            dismiss()
            return true
        }
        .task {
            guard let data = try? Data(contentsOf: item.url) else {
                problem = "Couldn’t read this file."
                return
            }
            text = String(decoding: data, as: UTF8.self)
            original = text
            loadedDate = Self.modified(item.url)
        }
        .alert("“\(item.name)” changed somewhere else", isPresented: $confirmOverwrite) {
            Button("Overwrite", role: .destructive) { save(force: true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Another app saved it after you started editing. Overwrite it with your version?")
        }
    }

    private static func modified(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    private func save(force: Bool) {
        if !force, let loadedDate, let now = Self.modified(item.url), now > loadedDate.addingTimeInterval(0.5) {
            confirmOverwrite = true
            return
        }
        do {
            try Data(text.utf8).write(to: item.url, options: .atomic)
            original = text
            loadedDate = Self.modified(item.url)
            dismiss()
        } catch {
            problem = "Couldn’t save: \(error.localizedDescription)"
        }
    }
}

/// Markdown, rendered a line at a time: headings, bullets, quotes, code blocks, inline styles.
private struct MarkdownLines: View {
    let lines: [String]
    var width: CGFloat = 260

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in block }
        }
        .frame(maxWidth: width, alignment: .leading)
        .textSelection(.enabled)
    }

    private var blocks: [AnyView] {
        var views: [AnyView] = []
        var code: [String]?
        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if let block = code {
                    views.append(AnyView(
                        Text(block.joined(separator: "\n"))
                            .font(.system(size: 10.5, design: .monospaced))
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))))
                    code = nil
                } else {
                    code = []
                }
                continue
            }
            if code != nil {
                code?.append(line)
                continue
            }
            views.append(AnyView(render(line)))
        }
        if let block = code { views.append(AnyView(Text(block.joined(separator: "\n")).font(.system(size: 10.5, design: .monospaced)))) }
        return views
    }

    @ViewBuilder private func render(_ line: String) -> some View {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            Spacer().frame(height: 2)
        } else if let level = headingLevel(trimmed) {
            inline(String(trimmed.drop(while: { $0 == "#" }).dropFirst()))
                .font(.system(size: [17, 15, 13.5, 12.5][min(level, 4) - 1], weight: .semibold))
                .padding(.top, 4)
        } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("•").foregroundStyle(.secondary)
                inline(String(trimmed.dropFirst(2)))
            }
            .padding(.leading, CGFloat(line.prefix(while: { $0 == " " }).count) * 4)
            .font(.system(size: 12))
        } else if trimmed.hasPrefix(">") {
            inline(String(trimmed.dropFirst().drop(while: { $0 == " " })))
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .padding(.leading, 8)
                .overlay(alignment: .leading) { Rectangle().fill(Color.accentColor.opacity(0.5)).frame(width: 2) }
        } else if trimmed == "---" || trimmed == "***" {
            Divider()
        } else {
            inline(trimmed).font(.system(size: 12))
        }
    }

    private func headingLevel(_ line: String) -> Int? {
        let hashes = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return hashes
    }

    private func inline(_ text: String) -> Text {
        let attributed = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
        return Text(attributed)
    }
}

/// Source code with line numbers and simple highlighting.
private struct CodeLines: View {
    let lines: [String]
    let language: CodeHighlighter.Language

    var body: some View {
        let width = String(lines.count).count
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(String(index + 1).leftPad(width))
                        .foregroundStyle(.tertiary)
                    Text(CodeHighlighter.highlight(line, language: language))
                        .fixedSize()
                }
            }
        }
        .font(.system(size: 10.5, design: .monospaced))
        .textSelection(.enabled)
    }
}

private extension String {
    func leftPad(_ width: Int) -> String { String(repeating: " ", count: max(0, width - count)) + self }
}

/// A small, forgiving highlighter: comments, strings, numbers and common keywords.
enum CodeHighlighter {
    struct Language {
        var keywords: Set<String>
        var lineComment: String
    }

    static let cLike: Set<String> = [
        "import", "func", "let", "var", "if", "else", "for", "while", "return", "struct", "class", "enum", "case",
        "switch", "guard", "in", "true", "false", "nil", "null", "self", "static", "private", "public", "const",
        "function", "export", "default", "async", "await", "try", "catch", "throw", "new", "interface", "type",
        "extends", "implements", "from", "package", "fn", "pub", "use", "mut", "impl", "match", "break", "continue",
    ]
    static let scripting: Set<String> = [
        "def", "class", "import", "from", "as", "if", "elif", "else", "for", "while", "return", "in", "not", "and",
        "or", "True", "False", "None", "with", "try", "except", "raise", "lambda", "yield", "async", "await",
        "then", "fi", "do", "done", "echo", "export", "local", "case", "esac", "function",
    ]

    static let languages: [String: Language] = {
        var map: [String: Language] = [:]
        for ext in ["swift", "js", "jsx", "ts", "tsx", "c", "h", "m", "cpp", "go", "rs", "java", "kt", "cs", "css", "scss"] {
            map[ext] = Language(keywords: cLike, lineComment: "//")
        }
        for ext in ["py", "sh", "zsh", "bash", "rb", "yml", "yaml", "toml", "r"] {
            map[ext] = Language(keywords: scripting, lineComment: "#")
        }
        map["sql"] = Language(keywords: ["select", "from", "where", "join", "insert", "update", "delete", "create",
                                         "table", "and", "or", "not", "null", "group", "by", "order", "limit"], lineComment: "--")
        return map
    }()

    static func language(for url: URL) -> Language {
        languages[url.pathExtension.lowercased()] ?? Language(keywords: [], lineComment: "")
    }

    static func highlight(_ line: String, language: Language) -> AttributedString {
        var result = AttributedString()
        var index = line.startIndex
        var word = ""

        func flushWord() {
            guard !word.isEmpty else { return }
            var piece = AttributedString(word)
            if language.keywords.contains(word) {
                piece.foregroundColor = .pink
            } else if word.first?.isNumber == true {
                piece.foregroundColor = .blue
            } else if word.first?.isUppercase == true {
                piece.foregroundColor = .teal
            }
            result += piece
            word = ""
        }

        while index < line.endIndex {
            let rest = line[index...]
            if !language.lineComment.isEmpty, rest.hasPrefix(language.lineComment) {
                flushWord()
                var comment = AttributedString(String(rest))
                comment.foregroundColor = .gray
                result += comment
                return result
            }
            let char = line[index]
            if char == "\"" || char == "'" || char == "`" {
                flushWord()
                var end = line.index(after: index)
                while end < line.endIndex, line[end] != char {
                    if line[end] == "\\" { end = line.index(end, offsetBy: 1, limitedBy: line.endIndex) ?? line.endIndex }
                    if end < line.endIndex { end = line.index(after: end) }
                }
                if end < line.endIndex { end = line.index(after: end) }
                var string = AttributedString(String(line[index..<end]))
                string.foregroundColor = .orange
                result += string
                index = end
                continue
            }
            if char.isLetter || char.isNumber || char == "_" {
                word.append(char)
            } else {
                flushWord()
                result += AttributedString(String(char))
            }
            index = line.index(after: index)
        }
        flushWord()
        return result
    }
}
