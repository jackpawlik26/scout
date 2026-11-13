import Foundation
import ScoutCore

/// Runs one Spotlight search. With `live`, it keeps running and reports changes
/// (files added, renamed, deleted) as they happen.
final class SpotlightSearch {
    static let maxResults = 3000

    private let query = NSMetadataQuery()
    private var observers: [NSObjectProtocol] = []
    private let live: Bool
    private let onResults: (_ hits: [FileHit], _ finished: Bool) -> Void

    convenience init?(spec: SearchSpec, home: String, live: Bool,
                      onResults: @escaping (_ hits: [FileHit], _ finished: Bool) -> Void) {
        guard let string = SpotlightQueryBuilder.queryString(for: spec) else { return nil }
        let scopes: [Any]
        if let within = spec.withinPath {
            scopes = [URL.folder(within)]
        } else if spec.kind == .apps {
            scopes = [URL.folder("/Applications"), URL.folder("/System/Applications"), URL.folder(home)]
        } else {
            scopes = [NSMetadataQueryUserHomeScope]
        }
        self.init(queryString: string, scopes: scopes, live: live, onResults: onResults)
    }

    /// Runs a raw Spotlight query string (`mdfind` syntax) in the given scopes.
    init?(queryString: String, scopes: [Any], live: Bool,
          onResults: @escaping (_ hits: [FileHit], _ finished: Bool) -> Void) {
        guard let predicate = NSPredicate(fromMetadataQueryString: queryString) else { return nil }
        self.live = live
        self.onResults = onResults
        query.predicate = predicate
        query.searchScopes = scopes
        query.notificationBatchingInterval = 0.2

        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            .NSMetadataQueryGatheringProgress, .NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate,
        ]
        for name in names {
            observers.append(center.addObserver(forName: name, object: query, queue: .main) { [weak self] note in
                let finished = note.name != .NSMetadataQueryGatheringProgress
                MainActor.assumeIsolated { self?.deliver(finished: finished) }
            })
        }
        query.start()
    }

    isolated deinit {
        query.stop()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    private func deliver(finished: Bool) {
        query.disableUpdates()
        let count = min(query.resultCount, Self.maxResults)
        var hits: [FileHit] = []
        hits.reserveCapacity(count)
        for i in 0..<count {
            guard let item = query.result(at: i) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { continue }
            let type = item.value(forAttribute: NSMetadataItemContentTypeKey) as? String
            hits.append(FileHit(
                path: path,
                name: item.value(forAttribute: NSMetadataItemFSNameKey) as? String ?? (path as NSString).lastPathComponent,
                isFolder: type == "public.folder",
                modified: item.value(forAttribute: NSMetadataItemFSContentChangeDateKey) as? Date,
                lastUsed: item.value(forAttribute: NSMetadataItemLastUsedDateKey) as? Date,
                contentType: type
            ))
        }
        query.enableUpdates()
        if finished, !live { query.stop() }
        onResults(hits, finished)
    }
}
