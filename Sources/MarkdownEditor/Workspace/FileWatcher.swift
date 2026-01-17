import Foundation

/// Watches a directory tree for file changes using FSEvents.
///
/// FSEvents is efficient for large directories - monitors the entire
/// tree with a single system resource.
final class FileWatcher {

    /// Callbacks for file system events.
    var onFileChanged: ((URL) -> Void)?
    var onFileDeleted: ((URL) -> Void)?
    var onFileCreated: ((URL) -> Void)?

    /// FSEvent stream for workspace watching.
    private var eventStream: FSEventStreamRef?

    /// Root directory being watched.
    private var watchedRoot: URL?

    // MARK: - Workspace Watching

    func watchWorkspace(at root: URL) {
        stopWatchingWorkspace()

        watchedRoot = root

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { (
            streamRef,
            clientCallBackInfo,
            numEvents,
            eventPaths,
            eventFlags,
            eventIds
        ) in
            guard let clientCallBackInfo = clientCallBackInfo else { return }
            let watcher = Unmanaged<FileWatcher>.fromOpaque(clientCallBackInfo).takeUnretainedValue()

            let paths = unsafeBitCast(eventPaths, to: NSArray.self)

            for i in 0..<numEvents {
                guard let pathString = paths[i] as? String else { continue }
                let url = URL(fileURLWithPath: pathString)
                let flags = eventFlags[i]

                DispatchQueue.main.async {
                    if flags & UInt32(kFSEventStreamEventFlagItemRemoved) != 0 {
                        watcher.onFileDeleted?(url)
                    } else if flags & UInt32(kFSEventStreamEventFlagItemCreated) != 0 {
                        watcher.onFileCreated?(url)
                    } else if flags & UInt32(kFSEventStreamEventFlagItemModified) != 0 {
                        watcher.onFileChanged?(url)
                    } else {
                        // Generic change
                        watcher.onFileChanged?(url)
                    }
                }
            }
        }

        let pathsToWatch = [root.path] as CFArray

        eventStream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,  // Latency in seconds
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        )

        if let stream = eventStream {
            FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
            FSEventStreamStart(stream)
        }
    }

    func stopWatchingWorkspace() {
        if let stream = eventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            eventStream = nil
        }
        watchedRoot = nil
    }

    deinit {
        stopWatchingWorkspace()
    }
}
