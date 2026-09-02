import CoreServices
import Foundation

final class FSEventsDirectoryWatcher: @unchecked Sendable {
    typealias EventHandler = @Sendable ([String]) -> Void

    private final class CallbackBox {
        let handler: EventHandler

        init(handler: @escaping EventHandler) {
            self.handler = handler
        }
    }

    private let path: String
    private let handler: EventHandler
    private let queue = DispatchQueue(label: "dev.obssync.fsevents", qos: .utility)
    private var stream: FSEventStreamRef?

    init(path: String, handler: @escaping EventHandler) {
        self.path = path
        self.handler = handler
    }

    deinit {
        stop()
    }

    func start() throws {
        guard stream == nil else { return }
        guard FileManager.default.fileExists(atPath: path) else {
            throw FileWatcherError.pathUnavailable(path)
        }

        let box = CallbackBox(handler: handler)
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passRetained(box).toOpaque(),
            retain: nil,
            release: { info in
                guard let info else { return }
                Unmanaged<CallbackBox>.fromOpaque(info).release()
            },
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, info, count, rawPaths, _, _ in
            guard let info else { return }
            let box = Unmanaged<CallbackBox>.fromOpaque(info).takeUnretainedValue()
            let array = unsafeBitCast(rawPaths, to: CFArray.self) as NSArray
            let paths = (array as? [String]) ?? []
            if !paths.isEmpty, count > 0 {
                box.handler(paths)
            }
        }

        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagNoDefer |
            kFSEventStreamCreateFlagWatchRoot
        )
        guard let newStream = FSEventStreamCreate(
            nil,
            callback,
            &context,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,
            flags
        ) else {
            Unmanaged<CallbackBox>.fromOpaque(context.info!).release()
            throw FileWatcherError.couldNotCreateStream
        }

        stream = newStream
        FSEventStreamSetDispatchQueue(newStream, queue)
        guard FSEventStreamStart(newStream) else {
            FSEventStreamInvalidate(newStream)
            FSEventStreamRelease(newStream)
            stream = nil
            throw FileWatcherError.couldNotStartStream
        }
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}

enum FileWatcherError: LocalizedError {
    case pathUnavailable(String)
    case couldNotCreateStream
    case couldNotStartStream

    var errorDescription: String? {
        switch self {
        case let .pathUnavailable(path): "The watched folder is unavailable: \(path)"
        case .couldNotCreateStream: "Could not create a file-system event stream."
        case .couldNotStartStream: "Could not start the file-system event stream."
        }
    }
}
