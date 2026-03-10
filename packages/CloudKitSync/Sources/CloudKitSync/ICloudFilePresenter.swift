@preconcurrency import Foundation
import Combine

/// NSFilePresenter implementation that monitors iCloud Documents files for external changes.
///
/// Publishes change notifications through a Combine publisher so the UI layer can react.
public final class ICloudFilePresenter: NSObject, NSFilePresenter, @unchecked Sendable {

    // MARK: - NSFilePresenter

    public var presentedItemURL: URL?

    public var presentedItemOperationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.0hanami.mdtodo.file-presenter"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    // MARK: - Publishers

    private let _fileChanged = PassthroughSubject<URL, Never>()

    /// Emits the URL of the file whenever an external change is detected.
    public var fileChanged: AnyPublisher<URL, Never> {
        _fileChanged.eraseToAnyPublisher()
    }

    private let _conflictDetected = PassthroughSubject<URL, Never>()

    /// Emits when a version conflict is detected on the file.
    public var conflictDetected: AnyPublisher<URL, Never> {
        _conflictDetected.eraseToAnyPublisher()
    }

    // MARK: - Lifecycle

    public override init() {
        super.init()
    }

    /// Starts observing changes to the file at the given URL.
    ///
    /// - Parameter url: The file URL to monitor.
    public func startMonitoring(url: URL) {
        stopMonitoring()
        presentedItemURL = url
        NSFileCoordinator.addFilePresenter(self)
    }

    /// Stops observing file changes.
    public func stopMonitoring() {
        if presentedItemURL != nil {
            NSFileCoordinator.removeFilePresenter(self)
            presentedItemURL = nil
        }
    }

    deinit {
        stopMonitoring()
    }

    // MARK: - NSFilePresenter Callbacks

    public func presentedItemDidChange() {
        guard let url = presentedItemURL else { return }
        _fileChanged.send(url)
    }

    public func presentedItemDidGain(_ version: NSFileVersion) {
        guard let url = presentedItemURL else { return }

        if NSFileVersion.unresolvedConflictVersionsOfItem(at: url)?.isEmpty == false {
            _conflictDetected.send(url)
        }
    }

    public func presentedItemDidLose(_ version: NSFileVersion) {
        // Version removed, no action needed
    }

    public func presentedItemDidResolveConflict(_ version: NSFileVersion) {
        guard let url = presentedItemURL else { return }
        _fileChanged.send(url)
    }

    /// Called when another process wants to read the file.
    public func relinquishPresentedItem(toReader reader: @escaping @Sendable ((@Sendable () -> Void)?) -> Void) {
        reader {
            // Re-acquire after reader finishes
        }
    }

    /// Called when another process wants to write the file.
    public func relinquishPresentedItem(toWriter writer: @escaping @Sendable ((@Sendable () -> Void)?) -> Void) {
        writer { [weak self] in
            // Re-acquire and notify after writer finishes
            guard let self = self, let url = self.presentedItemURL else { return }
            self._fileChanged.send(url)
        }
    }
}
