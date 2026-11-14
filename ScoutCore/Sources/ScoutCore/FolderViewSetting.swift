import Foundation

/// A folder's remembered sort and grouping, stored as "field|ascending|group|2".
///
/// `group` is nil when the folder follows Settings' default grouping. Entries saved
/// before the default existed have no "|2"; their "none" only meant "never chosen",
/// so it reads as "follow the default", while any other grouping stays the folder's own.
public struct FolderViewSetting: Equatable, Sendable {
    public var sortField: String
    public var ascending: Bool
    /// The folder's own grouping, or nil to follow the default.
    public var group: GroupBy?

    public init(sortField: String, ascending: Bool, group: GroupBy?) {
        self.sortField = sortField
        self.ascending = ascending
        self.group = group
    }

    public init?(saved: String) {
        let parts = saved.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 3 else { return nil }
        sortField = parts[0]
        ascending = parts[1] == "1"
        let isCurrentFormat = parts.count >= 4
        if parts[2] == "default" || (!isCurrentFormat && parts[2] == GroupBy.none.rawValue) {
            group = nil
        } else {
            group = GroupBy(rawValue: parts[2])
        }
    }

    public var saved: String {
        "\(sortField)|\(ascending ? 1 : 0)|\(group?.rawValue ?? "default")|2"
    }
}
