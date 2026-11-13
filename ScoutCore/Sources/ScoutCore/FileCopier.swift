import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// What to do when an item with the same name is already there.
public enum ConflictChoice: Sendable, Equatable {
    /// Move the existing one to the Trash, then put the new one in its place.
    case replace
    /// Keep both: the new one gets "copy" / "2" added to its name.
    case keepBoth
    /// Leave this one out.
    case skip
}

#if os(macOS)
/// Copies and moves with byte-level progress (macOS `copyfile`, which clones on APFS when it can).
public enum FileCopier {
    /// Called with bytes copied so far (for the whole item). Return false to cancel.
    public typealias Progress = @Sendable (Int64) -> Bool

    public enum Failure: LocalizedError {
        case cancelled
        case failed(String, Int32)
        public var errorDescription: String? {
            switch self {
            case .cancelled: "Cancelled."
            case .failed(let name, let code): "Couldn’t copy “\(name)”: \(String(cString: strerror(code)))."
            }
        }
    }

    /// Copies `source` (file or folder) to `destination`, which must not exist yet.
    public static func copy(_ source: URL, to destination: URL, progress: Progress? = nil) throws {
        let box = ProgressBox(progress: progress)
        let state = copyfile_state_alloc()
        defer { copyfile_state_free(state) }
        let context = Unmanaged.passUnretained(box).toOpaque()
        copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CB), unsafeBitCast(copyCallback, to: UnsafeRawPointer.self))
        copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CTX), context)
        let flags = copyfile_flags_t(COPYFILE_ALL | COPYFILE_RECURSIVE | COPYFILE_CLONE | COPYFILE_NOFOLLOW_SRC)
        let result = copyfile(source.filePath, destination.filePath, state, flags)
        if box.cancelled {
            try? FileManager.default.removeItem(at: destination)
            throw Failure.cancelled
        }
        if result != 0 {
            let code = errno
            try? FileManager.default.removeItem(at: destination)
            throw Failure.failed(source.lastPathComponent, code)
        }
    }

    /// Moves `source` to `destination`: a rename on the same disk, copy-then-delete across disks.
    public static func move(_ source: URL, to destination: URL, progress: Progress? = nil) throws {
        if sameVolume(source, destination.deletingLastPathComponent()) {
            try FileManager.default.moveItem(at: source, to: destination)
            return
        }
        try copy(source, to: destination, progress: progress)
        try FileManager.default.removeItem(at: source)
    }

    public static func sameVolume(_ a: URL, _ b: URL) -> Bool {
        let key = URLResourceKey.volumeIdentifierKey
        guard let va = try? a.resourceValues(forKeys: [key]).volumeIdentifier as? NSObject,
              let vb = try? b.resourceValues(forKeys: [key]).volumeIdentifier as? NSObject else { return false }
        return va == vb
    }

    /// Total bytes in a file or folder (to size a progress bar).
    public static func totalBytes(_ url: URL) -> Int64 {
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        if !isDir { return Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        // Logical bytes (what copyfile reports), not space on disk.
        var total: Int64 = 0
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey])
        while let item = enumerator?.nextObject() as? URL {
            if let values = try? item.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]), values.isRegularFile == true {
                total += Int64(values.fileSize ?? 0)
            }
        }
        return total
    }

    /// Where an item would land if `choice` is applied (nil for skip).
    public static func destination(for source: URL, in folder: URL, choice: ConflictChoice?, isCopy: Bool) -> URL? {
        let target = folder.appending(path: source.lastPathComponent)
        guard FileManager.default.fileExists(atPath: target.filePath) else { return target }
        switch choice {
        case .skip, nil: return nil
        case .replace: return target
        case .keepBoth:
            let isDir = (try? source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return LocalFileSource.availableURL(in: folder, preferredName: source.lastPathComponent,
                                                isDirectory: isDir, style: isCopy ? .copy : .numbered)
        }
    }
}

/// Carries progress through copyfile's C callback.
private final class ProgressBox: @unchecked Sendable {
    let progress: FileCopier.Progress?
    /// Bytes of files already finished.
    var finished: Int64 = 0
    var cancelled = false
    init(progress: FileCopier.Progress?) { self.progress = progress }
}

private let copyCallback: @convention(c) (Int32, Int32, copyfile_state_t?, UnsafePointer<CChar>?, UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> Int32 = { what, stage, state, _, _, context in
    guard let context else { return COPYFILE_CONTINUE }
    let box = Unmanaged<ProgressBox>.fromOpaque(context).takeUnretainedValue()
    var copied: off_t = 0
    if what == COPYFILE_COPY_DATA, stage == COPYFILE_PROGRESS {
        copyfile_state_get(state, UInt32(COPYFILE_STATE_COPIED), &copied)
    } else if what == COPYFILE_RECURSE_FILE, stage == COPYFILE_FINISH {
        copyfile_state_get(state, UInt32(COPYFILE_STATE_COPIED), &copied)
        box.finished += Int64(copied)
        copied = 0
    } else {
        return COPYFILE_CONTINUE
    }
    if let progress = box.progress, !progress(box.finished + Int64(copied)) {
        box.cancelled = true
        return COPYFILE_QUIT
    }
    return COPYFILE_CONTINUE
}
#endif
