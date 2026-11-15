import CryptoKit
import Foundation

/// A connection to an S3-compatible bucket: Cloudflare R2, AWS S3, Backblaze B2, MinIO…
/// The secret key isn't stored here (the app keeps it in the Keychain).
public struct BucketConfig: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    /// What the sidebar calls it ("Phreno assets").
    public var name: String
    /// "https://<account>.r2.cloudflarestorage.com" or "https://s3.us-east-1.amazonaws.com".
    public var endpoint: String
    /// "auto" for R2; the AWS region otherwise.
    public var region: String
    public var bucket: String
    public var accessKeyID: String

    public init(id: UUID = UUID(), name: String, endpoint: String, region: String = "auto",
                bucket: String, accessKeyID: String) {
        self.id = id
        self.name = name
        self.endpoint = endpoint
        self.region = region
        self.bucket = bucket
        self.accessKeyID = accessKeyID
    }
}

/// AWS Signature Version 4, the way S3-compatible services authenticate requests.
public enum SigV4 {
    public static let emptyPayloadHash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

    /// Adds `x-amz-date`, `x-amz-content-sha256` and `Authorization` to `request`.
    public static func sign(_ request: inout URLRequest, accessKey: String, secretKey: String, region: String,
                            service: String = "s3", payloadHash: String = emptyPayloadHash, date: Date = .now) {
        let stamp = timestamp(date)
        let day = String(stamp.prefix(8))
        request.setValue(stamp, forHTTPHeaderField: "x-amz-date")
        request.setValue(payloadHash, forHTTPHeaderField: "x-amz-content-sha256")
        guard let url = request.url, let host = url.host() else { return }
        let hostHeader = url.port.map { "\(host):\($0)" } ?? host

        var headers: [String: String] = ["host": hostHeader]
        for (name, value) in request.allHTTPHeaderFields ?? [:] {
            headers[name.lowercased()] = value.trimmingCharacters(in: .whitespaces)
        }
        let names = headers.keys.sorted()
        let signedHeaders = names.joined(separator: ";")
        let canonicalHeaders = names.map { "\($0):\(headers[$0]!)\n" }.joined()

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = components?.percentEncodedQueryItems ?? []
        var pairs: [(name: String, value: String)] = []
        for item in items {
            let name = encode(item.name.removingPercentEncoding ?? item.name)
            let value = encode(item.value?.removingPercentEncoding ?? "")
            pairs.append((name, value))
        }
        pairs.sort { a, b in a.name != b.name ? a.name < b.name : a.value < b.value }
        let canonicalQuery = pairs.map { "\($0.name)=\($0.value)" }.joined(separator: "&")
        let path = url.path(percentEncoded: true)
        let canonicalRequest = [request.httpMethod ?? "GET", path.isEmpty ? "/" : path, canonicalQuery,
                                canonicalHeaders, signedHeaders, payloadHash].joined(separator: "\n")

        let scope = "\(day)/\(region)/\(service)/aws4_request"
        let stringToSign = ["AWS4-HMAC-SHA256", stamp, scope, hex(SHA256.hash(data: Data(canonicalRequest.utf8)))]
            .joined(separator: "\n")
        var key = SymmetricKey(data: Data("AWS4\(secretKey)".utf8))
        for part in [day, region, service, "aws4_request"] {
            key = SymmetricKey(data: Data(HMAC<SHA256>.authenticationCode(for: Data(part.utf8), using: key)))
        }
        let signature = hex(HMAC<SHA256>.authenticationCode(for: Data(stringToSign.utf8), using: key))
        request.setValue("AWS4-HMAC-SHA256 Credential=\(accessKey)/\(scope), SignedHeaders=\(signedHeaders), Signature=\(signature)",
                         forHTTPHeaderField: "Authorization")
    }

    static func timestamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return f.string(from: date)
    }

    /// RFC 3986 unreserved characters stay; everything else is %XX (as SigV4 requires).
    public static func encode(_ s: String, keepSlash: Bool = false) -> String {
        var allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        if keepSlash { allowed.insert("/") }
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    static func hex<D: Sequence>(_ bytes: D) -> String where D.Element == UInt8 {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    public static func sha256Hex(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hex(hasher.finalize())
    }
}

/// One "folder" level of a bucket: sub-prefixes and objects.
public struct BucketListing: Equatable, Sendable {
    public struct Object: Equatable, Sendable, Identifiable {
        public var id: String { key }
        public let key: String
        public let size: Int64
        public let modified: Date?
        public var name: String { String(key.split(separator: "/").last ?? Substring(key)) }
    }

    public var folders: [String] = []
    public var objects: [Object] = []
    public var nextToken: String?

    public init(folders: [String] = [], objects: [Object] = [], nextToken: String? = nil) {
        self.folders = folders
        self.objects = objects
        self.nextToken = nextToken
    }

    /// Reads a ListObjectsV2 response.
    public static func parse(_ data: Data) -> BucketListing {
        let parser = ListParser()
        let xml = XMLParser(data: data)
        xml.delegate = parser
        xml.parse()
        return parser.listing
    }

    private final class ListParser: NSObject, XMLParserDelegate {
        var listing = BucketListing()
        private var text = ""
        private var key = "", size: Int64 = 0, modified: Date?
        private var inContents = false, inPrefixes = false
        private let iso = ISO8601DateFormatter()

        override init() {
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String] = [:]) {
            text = ""
            if name == "Contents" { inContents = true; key = ""; size = 0; modified = nil }
            if name == "CommonPrefixes" { inPrefixes = true }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            switch name {
            case "Key" where inContents: key = text
            case "Size" where inContents: size = Int64(text) ?? 0
            case "LastModified" where inContents:
                modified = iso.date(from: text) ?? ISO8601DateFormatter().date(from: text)
            case "Contents":
                inContents = false
                // "folder/" placeholder objects aren't files.
                if !key.hasSuffix("/") { listing.objects.append(.init(key: key, size: size, modified: modified)) }
            case "Prefix" where inPrefixes: listing.folders.append(text)
            case "CommonPrefixes": inPrefixes = false
            case "NextContinuationToken": listing.nextToken = text
            default: break
            }
        }
    }
}

/// Requests to an S3-compatible bucket (path-style, so any endpoint works).
public struct S3Client: Sendable {
    public let config: BucketConfig
    let secretKey: String
    let session: URLSession

    public init(config: BucketConfig, secretKey: String, session: URLSession = .shared) {
        self.config = config
        self.secretKey = secretKey
        self.session = session
    }

    public enum Failure: LocalizedError {
        case http(Int, String)
        public var errorDescription: String? {
            switch self {
            case .http(let status, let body):
                let code = body.range(of: "<Code>").flatMap { start in
                    body.range(of: "</Code>").map { String(body[start.upperBound..<$0.lowerBound]) }
                }
                return "The bucket said \(status)\(code.map { " (\($0))" } ?? "")."
            }
        }
    }

    /// endpoint/bucket/key, with each part of the key escaped.
    public func url(key: String = "", query: [URLQueryItem] = []) -> URL {
        let base = config.endpoint.hasSuffix("/") ? String(config.endpoint.dropLast()) : config.endpoint
        var components = URLComponents(string: base + "/" + SigV4.encode(config.bucket) + "/" + SigV4.encode(key, keepSlash: true))!
        if !query.isEmpty {
            components.percentEncodedQuery = query
                .map { "\(SigV4.encode($0.name))=\(SigV4.encode($0.value ?? ""))" }
                .joined(separator: "&")
        }
        return components.url!
    }

    func request(_ method: String, key: String = "", query: [URLQueryItem] = [],
                 payloadHash: String = SigV4.emptyPayloadHash, headers: [String: String] = [:]) -> URLRequest {
        var request = URLRequest(url: url(key: key, query: query))
        request.httpMethod = method
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        SigV4.sign(&request, accessKey: config.accessKeyID, secretKey: secretKey, region: config.region,
                   payloadHash: payloadHash)
        return request
    }

    private func check(_ response: URLResponse, _ data: Data) throws {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw Failure.http(status, String(decoding: data, as: UTF8.self)) }
    }

    /// One level under `prefix` ("photos/2026/"), following continuation tokens.
    public func list(prefix: String) async throws -> BucketListing {
        var all = BucketListing()
        var token: String?
        repeat {
            var query = [URLQueryItem(name: "list-type", value: "2"), URLQueryItem(name: "delimiter", value: "/"),
                         URLQueryItem(name: "prefix", value: prefix)]
            if let token { query.append(URLQueryItem(name: "continuation-token", value: token)) }
            let (data, response) = try await session.data(for: request("GET", query: query))
            try check(response, data)
            let page = BucketListing.parse(data)
            all.folders += page.folders
            all.objects += page.objects
            token = page.nextToken
        } while token != nil
        return all
    }

    /// Downloads an object to `destination` (which must not exist).
    public func download(_ key: String, to destination: URL) async throws {
        let (temp, response) = try await session.download(for: request("GET", key: key))
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let body = (try? Data(contentsOf: temp)) ?? Data()
            throw Failure.http(http.statusCode, String(decoding: body, as: UTF8.self))
        }
        try FileManager.default.moveItem(at: temp, to: destination)
    }

    /// Uploads a file as `key`.
    public func upload(_ file: URL, as key: String) async throws {
        let hash = try SigV4.sha256Hex(of: file)
        let (data, response) = try await session.upload(for: request("PUT", key: key, payloadHash: hash), fromFile: file)
        try check(response, data)
    }

    public func delete(_ key: String) async throws {
        let (data, response) = try await session.data(for: request("DELETE", key: key))
        try check(response, data)
    }

    /// An empty "folder/" object, so the folder shows up before anything is in it.
    public func makeFolder(_ prefix: String) async throws {
        let key = prefix.hasSuffix("/") ? prefix : prefix + "/"
        var request = request("PUT", key: key)
        request.httpBody = Data()
        let (data, response) = try await session.data(for: request)
        try check(response, data)
    }
}

extension ScoutStore {
    public static var bucketsURL: URL { directory.appending(path: "buckets.json") }

    public static func loadBuckets(from url: URL = bucketsURL) -> [BucketConfig] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([BucketConfig].self, from: data)) ?? []
    }

    public static func saveBuckets(_ buckets: [BucketConfig], to url: URL = bucketsURL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(buckets).write(to: url, options: .atomic)
    }
}
