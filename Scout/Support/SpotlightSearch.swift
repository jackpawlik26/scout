import Foundation
import ScoutCore

/// Runs one Spotlight search. With `live`, it keeps running and reports changes
/// (files added, renamed, deleted) as they happen.
///
/// Everything slow happens off the main thread: Spotlight gathers on a private queue,
/// the attributes Scout needs come back with the results (`valueListAttributes`; asking
/// each result for them separately took about 1 ms a file), and `process` (ranking,
/// reading files from disk) runs there too. Only the finished output reaches the main
/// thread, so typing in ⌘K never waits on Spotlight.
nonisolated final class SpotlightSearch: @unchecked Sendable {
    static let maxResults = 3000

    private let query = NSMetadataQuery()
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        queue.name = "Scout Spotlight"
        return queue
    }()
    private var observers: [NSObjectProtocol] = []
    private let live: Bool
    /// Runs on `queue`; turns the raw hits into what the caller shows.
    private let handle: (_ hits: [FileHit], _ finished: Bool) -> Void

    private static let attributes = [
        NSMetadataItemPathKey, NSMetadataItemFSNameKey, NSMetadataItemContentTypeKey,
        NSMetadataItemFSContentChangeDateKey, NSMetadataItemLastUsedDateKey,
    ]

    /// Searches for a `SearchSpec` (⌘K, search tabs).
    @MainActor
    convenience init?<Output: Sendable>(
        spec: SearchSpec, home: String, live: Bool,
        process: @escaping @Sendable (_ hits: [FileHit]) -> Output,
        onResults: @escaping @MainActor (_ output: Output, _ finished: Bool) -> Void
    ) {
        guard let string = SpotlightQueryBuilder.queryString(for: spec) else { return nil }
        let scopes: [Any]
        if let within = spec.withinPath {
            scopes = [URL.folder(within)]
        } else if spec.kind == .apps {
            scopes = [URL.folder("/Applications"), URL.folder("/System/Applications"), URL.folder(home)]
        } else {
            scopes = [NSMetadataQueryUserHomeScope]
        }
        self.init(queryString: string, scopes: scopes, live: live, process: process, onResults: onResults)
    }

    /// Runs a raw Spotlight query string (`mdfind` syntax) and hands back the hits as they are.
    @MainActor
    convenience init?(queryString: String, scopes: [Any], live: Bool,
                      onResults: @escaping @MainActor (_ hits: [FileHit], _ finished: Bool) -> Void) {
        self.init(queryString: queryString, scopes: scopes, live: live, process: { $0 }, onResults: onResults)
    }

    /// Runs a raw Spotlight query string (`mdfind` syntax) in the given scopes.
    /// `process` runs in the background on each batch; `onResults` gets its output on the main thread.
    @MainActor
    init?<Output: Sendable>(
        queryString: String, scopes: [Any], live: Bool,
        process: @escaping @Sendable (_ hits: [FileHit]) -> Output,
        onResults: @escaping @MainActor (_ output: Output, _ finished: Bool) -> Void
    ) {
        guard let predicate = NSPredicate(fromMetadataQueryString: queryString) else { return nil }
        self.live = live
        // `self` is captured weakly so a replaced or closed search delivers nothing more.
        weak var weakSelf: SpotlightSearch?
        handle = { hits, finished in
            let output = process(hits)
            DispatchQueue.main.async {
                guard weakSelf != nil else { return }
                MainActor.assumeIsolated { onResults(output, finished) }
            }
        }
        query.predicate = predicate
        query.searchScopes = scopes
        query.notificationBatchingInterval = 0.2
        query.valueListAttributes = Self.attributes
        query.operationQueue = queue
        weakSelf = self

        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            .NSMetadataQueryGatheringProgress, .NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate,
        ]
        for name in names {
            // Posted on `queue`; a nil queue here runs the block right there.
            observers.append(center.addObserver(forName: name, object: query, queue: nil) { [weak self] note in
                self?.deliver(finished: note.name != .NSMetadataQueryGatheringProgress)
            })
        }
        let query = query
        queue.addOperation { query.start() }
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        let query = query
        queue.addOperation { query.stop() }
    }

    /// On `queue`.
    private func deliver(finished: Bool) {
        query.disableUpdates()
        let count = min(query.resultCount, Self.maxResults)
        var hits: [FileHit] = []
        hits.reserveCapacity(count)
        for i in 0..<count {
            guard let path = query.value(ofAttribute: NSMetadataItemPathKey, forResultAt: i) as? String else { continue }
            let type = query.value(ofAttribute: NSMetadataItemContentTypeKey, forResultAt: i) as? String
            hits.append(FileHit(
                path: path,
                name: query.value(ofAttribute: NSMetadataItemFSNameKey, forResultAt: i) as? String
                    ?? (path as NSString).lastPathComponent,
                isFolder: type == "public.folder",
                modified: query.value(ofAttribute: NSMetadataItemFSContentChangeDateKey, forResultAt: i) as? Date,
                lastUsed: query.value(ofAttribute: NSMetadataItemLastUsedDateKey, forResultAt: i) as? Date,
                contentType: type
            ))
        }
        query.enableUpdates()
        if finished, !live { query.stop() }
        handle(hits, finished)
    }
}
