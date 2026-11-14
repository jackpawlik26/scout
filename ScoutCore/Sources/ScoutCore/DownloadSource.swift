import Foundation

/// Where a file came from, as macOS records it when a browser downloads a file or
/// Mail saves an attachment (the `kMDItemWhereFroms` attribute).
public struct DownloadSource: Hashable, Sendable {
    /// The address the file itself was downloaded from.
    public let fileURL: URL?
    /// The page you were on when you downloaded it.
    public let pageURL: URL?
    /// For Mail attachments: who sent the message.
    public let sender: String?
    /// For Mail attachments: the message's subject.
    public let subject: String?
    /// For Mail attachments: a `message:` link that opens the message in Mail.
    public let messageURL: URL?

    /// The extended attribute browsers and Mail write. Spotlight indexes it as `kMDItemWhereFroms`.
    static let attribute = "com.apple.metadata:kMDItemWhereFroms"

    public init(fileURL: URL? = nil, pageURL: URL? = nil, sender: String? = nil,
                subject: String? = nil, messageURL: URL? = nil) {
        self.fileURL = fileURL
        self.pageURL = pageURL
        self.sender = sender
        self.subject = subject
        self.messageURL = messageURL
    }

    /// Makes sense of the raw list. Browsers write the file's address, then usually the
    /// page's; Mail writes the sender, the subject and a `message:` link.
    public init?(whereFroms entries: [String]) {
        var web: [URL] = []
        var message: URL?
        var text: [String] = []
        for raw in entries {
            var entry = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !entry.isEmpty else { continue }
            // Chrome sometimes records "blob:https://site/…".
            if entry.hasPrefix("blob:") { entry.removeFirst(5) }
            if let url = URL(string: entry), let scheme = url.scheme?.lowercased() {
                if scheme == "http" || scheme == "https" || scheme == "ftp", url.host() != nil {
                    web.append(url)
                    continue
                }
                if scheme == "message" {
                    message = url
                    continue
                }
                if scheme == "data" || scheme == "about" || scheme == "file" { continue }
            }
            text.append(entry)
        }
        let sender = text.first { $0.contains("@") }
        let subject = text.first { $0 != sender }
        guard !web.isEmpty || sender != nil || message != nil else { return nil }
        self.init(
            fileURL: web.first,
            pageURL: web.count > 1 ? web[1] : nil,
            sender: sender,
            subject: subject,
            messageURL: message
        )
    }

    /// True for a Mail attachment.
    public var isMail: Bool { sender != nil || messageURL != nil }

    /// The website to name, e.g. "canvas.depaul.edu": the page you were on if it was
    /// recorded (the file itself often comes from a storage server), otherwise the file's host.
    public var site: String? {
        Self.site(of: pageURL) ?? Self.site(of: fileURL)
    }

    /// The host the file itself came from, e.g. a storage server like "s3.amazonaws.com".
    public var fileSite: String? { Self.site(of: fileURL) }

    /// A one-line answer to "where did this come from?".
    public var summary: String? {
        if let site { return site }
        if let sender { return Self.senderName(sender) }
        return isMail ? "Mail" : nil
    }

    /// The best link to open: the page, then the file's address, then the Mail message.
    public var openURL: URL? { pageURL ?? fileURL ?? messageURL }

    /// "Jane Doe <jane@example.com>" → "Jane Doe"; a bare address stays as it is.
    static func senderName(_ sender: String) -> String {
        guard let open = sender.firstIndex(of: "<") else { return sender }
        let name = sender[..<open].trimmingCharacters(in: CharacterSet.whitespaces.union(["\""]))
        return name.isEmpty ? sender : name
    }

    static func site(of url: URL?) -> String? {
        guard var host = url?.host()?.lowercased(), !host.isEmpty else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }

    // MARK: - Reading and writing

    #if canImport(Darwin)
    /// Reads where a file came from, or nil when macOS didn't record it.
    public static func read(_ url: URL) -> DownloadSource? {
        guard let entries = readEntries(url) else { return nil }
        return DownloadSource(whereFroms: entries)
    }

    /// The raw list, read straight from the extended attribute (no Spotlight needed).
    static func readEntries(_ url: URL) -> [String]? {
        let path = url.filePath
        let size = getxattr(path, attribute, nil, 0, 0, XATTR_NOFOLLOW)
        guard size > 0 else { return nil }
        var data = Data(count: size)
        let read = data.withUnsafeMutableBytes { getxattr(path, attribute, $0.baseAddress, size, 0, XATTR_NOFOLLOW) }
        guard read == size else { return nil }
        return try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String]
    }

    /// Records a source the way browsers do (used by tests).
    static func writeEntries(_ entries: [String], to url: URL) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: entries, format: .binary, options: 0)
        let result = data.withUnsafeBytes { setxattr(url.filePath, attribute, $0.baseAddress, data.count, 0, XATTR_NOFOLLOW) }
        if result != 0 { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
    #endif
}
