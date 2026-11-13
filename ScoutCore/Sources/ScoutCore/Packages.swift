import Foundation

/// Where an installed package came from.
public enum PackageSource: String, CaseIterable, Sendable, Identifiable {
    case homebrew, cask, npm

    public var id: Self { self }

    public var title: String {
        switch self {
        case .homebrew: "Homebrew"
        case .cask: "Homebrew apps"
        case .npm: "npm (global)"
        }
    }

    public var symbol: String {
        switch self {
        case .homebrew: "mug"
        case .cask: "macwindow"
        case .npm: "shippingbox"
        }
    }
}

/// One installed command-line tool, app or library.
public struct Package: Identifiable, Hashable, Sendable {
    public var id: String { "\(source.rawValue):\(name)" }
    public let source: PackageSource
    public let name: String
    public var version: String
    /// Newer version available, if it's outdated.
    public var latest: String?
    public var summary: String?
    public var homepage: URL?
    /// Where it lives on disk (Cellar folder, app, node_modules folder).
    public var path: String?
    /// Installed only because something else needs it.
    public var isDependency = false

    public init(source: PackageSource, name: String, version: String, latest: String? = nil, summary: String? = nil,
                homepage: URL? = nil, path: String? = nil, isDependency: Bool = false) {
        self.source = source
        self.name = name
        self.version = version
        self.latest = latest
        self.summary = summary
        self.homepage = homepage
        self.path = path
        self.isDependency = isDependency
    }

    public var isOutdated: Bool { latest != nil && latest != version }

    public var upgradeCommand: String {
        switch source {
        case .homebrew: "brew upgrade \(name)"
        case .cask: "brew upgrade --cask \(name)"
        case .npm: "npm install -g \(name)@latest"
        }
    }

    public var uninstallCommand: String {
        switch source {
        case .homebrew: "brew uninstall \(name)"
        case .cask: "brew uninstall --cask \(name)"
        case .npm: "npm uninstall -g \(name)"
        }
    }

    /// The package's page (homepage, or its npm page).
    public var webPage: URL? {
        homepage ?? (source == .npm ? URL(string: "https://www.npmjs.com/package/\(name)") : nil)
    }
}

/// Reads the JSON that `brew` and `npm` print.
public enum PackageParser {
    /// `brew info --json=v2 --installed` plus (optionally) `brew outdated --json=v2`.
    public static func homebrew(info: Data, outdated: Data?, prefix: String) -> [Package] {
        guard let root = try? JSONSerialization.jsonObject(with: info) as? [String: Any] else { return [] }
        var newer: [String: String] = [:]
        if let outdated, let json = try? JSONSerialization.jsonObject(with: outdated) as? [String: Any] {
            for entry in (json["formulae"] as? [[String: Any]] ?? []) + (json["casks"] as? [[String: Any]] ?? []) {
                if let name = entry["name"] as? String, let current = entry["current_version"] as? String {
                    newer[name] = current
                }
            }
        }

        var packages: [Package] = []
        for formula in root["formulae"] as? [[String: Any]] ?? [] {
            guard let name = formula["name"] as? String,
                  let installed = (formula["installed"] as? [[String: Any]])?.last else { continue }
            let version = installed["version"] as? String ?? "?"
            packages.append(Package(
                source: .homebrew, name: name, version: version, latest: newer[name],
                summary: formula["desc"] as? String,
                homepage: (formula["homepage"] as? String).flatMap(URL.init(string:)),
                path: "\(prefix)/Cellar/\(name)",
                isDependency: !(installed["installed_on_request"] as? Bool ?? true)
            ))
        }
        for cask in root["casks"] as? [[String: Any]] ?? [] {
            guard let token = cask["token"] as? String else { continue }
            let app = (cask["artifacts"] as? [[String: Any]] ?? [])
                .compactMap { ($0["app"] as? [Any])?.first as? String }.first
            packages.append(Package(
                source: .cask, name: token, version: cask["installed"] as? String ?? "?",
                latest: newer[token] ?? ((cask["outdated"] as? Bool) == true ? cask["version"] as? String : nil),
                summary: cask["desc"] as? String ?? (cask["name"] as? [String])?.first,
                homepage: (cask["homepage"] as? String).flatMap(URL.init(string:)),
                path: app.map { "/Applications/\($0)" } ?? "\(prefix)/Caskroom/\(token)"
            ))
        }
        return packages
    }

    /// `npm ls -g --depth=0 --json` plus (optionally) `npm outdated -g --json`.
    public static func npm(list: Data, outdated: Data?, root: String) -> [Package] {
        guard let json = try? JSONSerialization.jsonObject(with: list) as? [String: Any],
              let dependencies = json["dependencies"] as? [String: [String: Any]] else { return [] }
        let newer = (outdated.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: [String: Any]]) ?? [:]
        return dependencies.map { name, info in
            Package(source: .npm, name: name, version: info["version"] as? String ?? "?",
                    latest: newer[name]?["latest"] as? String, path: "\(root)/\(name)")
        }
        .sorted { $0.name < $1.name }
    }
}

#if os(macOS)
/// Asks Homebrew and npm what's installed. Each returns nil when the tool isn't installed.
public enum PackageScanner {
    public static let brewCandidates = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
    public static let npmCandidates = ["/opt/homebrew/bin/npm", "/usr/local/bin/npm"]

    static let brewEnvironment = ["HOMEBREW_NO_AUTO_UPDATE": "1", "HOMEBREW_NO_ENV_HINTS": "1", "NO_COLOR": "1"]

    public static var brew: String? { brewCandidates.first(where: FileManager.default.isExecutableFile(atPath:)) }
    public static var npmPath: String? { npmCandidates.first(where: FileManager.default.isExecutableFile(atPath:)) }

    public static func homebrew() -> [Package]? {
        guard let brew,
              let info = CommandRunner.run(brew, ["info", "--json=v2", "--installed"], timeout: 30, environment: brewEnvironment)
        else { return nil }
        let outdated = CommandRunner.run(brew, ["outdated", "--json=v2"], timeout: 30, environment: brewEnvironment)
        let prefix = ((brew as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent
        return PackageParser.homebrew(info: Data(info.utf8), outdated: outdated.map { Data($0.utf8) }, prefix: prefix)
    }

    /// `brew update`: fetches the latest package lists so "outdated" is current (needs the network).
    public static func updateHomebrew() -> Bool {
        guard let brew else { return false }
        return CommandRunner.run(brew, ["update", "--quiet"], timeout: 120, environment: ["NO_COLOR": "1"]) != nil
    }

    public static func npm() -> [Package]? {
        guard let npm = npmPath,
              let list = CommandRunner.run(npm, ["ls", "-g", "--depth=0", "--json"], timeout: 30, allowFailure: true)
        else { return nil }
        let root = CommandRunner.run(npm, ["root", "-g"])?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "/usr/local/lib/node_modules"
        // Needs the network; without it, everything just shows as current.
        let outdated = CommandRunner.run(npm, ["outdated", "-g", "--json"], timeout: 30, allowFailure: true)
        return PackageParser.npm(list: Data(list.utf8), outdated: outdated.map { Data($0.utf8) }, root: root)
    }
}
#endif
