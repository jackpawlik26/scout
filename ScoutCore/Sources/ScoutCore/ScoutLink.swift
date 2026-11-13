import Foundation

/// `scout://` links that let other apps (Raycast, Terminal, a future phone app) drive Scout.
///
///     scout://open?path=~/Downloads              open a folder (or reveal a file)
///     scout://open?path=/tmp/a.pdf&newTab=1      …in a new tab
///     scout://open?path=~/Documents&split=1      …in the other pane (splitting the window)
///     scout://jump?query=taxes                   open the ⌘K palette, optionally pre-filled
///     scout://workspace?name=Taxes               open a workspace by name
///     scout://cleanup                            open Clean Up
///     scout://packages                           open Packages (Homebrew, npm)
///     scout://settings                           open Settings
///     scout://changes?path=~/Scout               every changed file in a git repository
public enum ScoutLink: Equatable, Sendable {
    case open(path: String, newTab: Bool, split: Bool = false)
    case jump(query: String?)
    case workspace(name: String)
    case cleanup
    case packages
    case settings
    case changes(path: String)

    public static let scheme = "scout"

    public init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        var query: [String: String] = [:]
        for item in components.queryItems ?? [] { query[item.name.lowercased()] = item.value ?? "" }

        switch (components.host ?? "").lowercased() {
        case "open", "reveal":
            guard let path = query["path"], !path.isEmpty else { return nil }
            func flag(_ name: String) -> Bool { ["1", "true", "yes"].contains((query[name] ?? "").lowercased()) }
            self = .open(path: path, newTab: flag("newtab"), split: flag("split"))
        case "jump":
            let q = query["query"]
            self = .jump(query: q?.isEmpty == false ? q : nil)
        case "workspace":
            guard let name = query["name"], !name.isEmpty else { return nil }
            self = .workspace(name: name)
        case "cleanup":
            self = .cleanup
        case "packages":
            self = .packages
        case "settings", "preferences":
            self = .settings
        case "changes":
            guard let path = query["path"], !path.isEmpty else { return nil }
            self = .changes(path: path)
        default:
            return nil
        }
    }

    public var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .open(let path, let newTab, let split):
            components.host = "open"
            components.queryItems = [URLQueryItem(name: "path", value: path)]
            if newTab { components.queryItems?.append(URLQueryItem(name: "newTab", value: "1")) }
            if split { components.queryItems?.append(URLQueryItem(name: "split", value: "1")) }
        case .jump(let query):
            components.host = "jump"
            if let query { components.queryItems = [URLQueryItem(name: "query", value: query)] }
        case .workspace(let name):
            components.host = "workspace"
            components.queryItems = [URLQueryItem(name: "name", value: name)]
        case .cleanup:
            components.host = "cleanup"
        case .packages:
            components.host = "packages"
        case .settings:
            components.host = "settings"
        case .changes(let path):
            components.host = "changes"
            components.queryItems = [URLQueryItem(name: "path", value: path)]
        }
        return components.url!
    }
}
