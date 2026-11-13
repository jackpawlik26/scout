import Foundation

/// Calls back when a folder's contents change (files added, removed or renamed),
/// including changes made by other apps.
final class DirectoryWatcher {
    let url: URL
    private let source: DispatchSourceFileSystemObject

    init?(url: URL, onChange: @escaping @MainActor () -> Void) {
        let fd = open(url.path(percentEncoded: false), O_EVTONLY)
        guard fd >= 0 else { return nil }
        self.url = url
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .delete, .rename, .link], queue: .main)
        source.setEventHandler { MainActor.assumeIsolated { onChange() } }
        source.setCancelHandler { close(fd) }
        source.resume()
    }

    deinit { source.cancel() }
}
