import Foundation
import Combine

/// Monitors iCloud metadata queries for file download/upload status.
///
/// Uses NSMetadataQuery to track iCloud Documents sync state and
/// publishes status updates via Combine.
public final class ICloudMetadataMonitor: NSObject, @unchecked Sendable {

    private var metadataQuery: NSMetadataQuery?
    private var monitoredFileName: String?
    private var cancellables = Set<AnyCancellable>()

    private let _syncStatusChanged = PassthroughSubject<SyncStatus, Never>()

    /// Publishes sync status changes detected through iCloud metadata.
    public var syncStatusChanged: AnyPublisher<SyncStatus, Never> {
        _syncStatusChanged.eraseToAnyPublisher()
    }

    private let _fileUpdated = PassthroughSubject<Void, Never>()

    /// Publishes when the monitored file has been updated in iCloud.
    public var fileUpdated: AnyPublisher<Void, Never> {
        _fileUpdated.eraseToAnyPublisher()
    }

    public override init() {
        super.init()
    }

    // MARK: - Start / Stop

    /// Begins monitoring the named file in iCloud Documents.
    ///
    /// - Parameter fileName: The file name to watch (e.g. "todo.md").
    public func startMonitoring(fileName: String) {
        stopMonitoring()
        monitoredFileName = fileName

        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K LIKE %@", NSMetadataItemFSNameKey, fileName)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleQueryGatheringComplete(_:)),
            name: .NSMetadataQueryDidFinishGathering,
            object: query
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleQueryUpdate(_:)),
            name: .NSMetadataQueryDidUpdate,
            object: query
        )

        query.start()
        metadataQuery = query
    }

    /// Stops monitoring iCloud metadata.
    public func stopMonitoring() {
        metadataQuery?.stop()
        metadataQuery = nil
        monitoredFileName = nil
        NotificationCenter.default.removeObserver(self)
    }

    deinit {
        stopMonitoring()
    }

    // MARK: - Handlers

    @objc private func handleQueryGatheringComplete(_ notification: Notification) {
        processQueryResults()
    }

    @objc private func handleQueryUpdate(_ notification: Notification) {
        processQueryResults()
        _fileUpdated.send()
    }

    private func processQueryResults() {
        guard let query = metadataQuery else { return }

        query.disableUpdates()
        defer { query.enableUpdates() }

        guard query.resultCount > 0,
              let item = query.result(at: 0) as? NSMetadataItem else {
            return
        }

        let downloadStatus = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
        let isUploading = item.value(forAttribute: NSMetadataUbiquitousItemIsUploadingKey) as? Bool ?? false
        let isDownloading = item.value(forAttribute: NSMetadataUbiquitousItemIsDownloadingKey) as? Bool ?? false
        let hasConflicts = item.value(forAttribute: NSMetadataUbiquitousItemHasUnresolvedConflictsKey) as? Bool ?? false

        if hasConflicts {
            _syncStatusChanged.send(.conflict(local: Date(), remote: Date()))
        } else if isUploading || isDownloading {
            _syncStatusChanged.send(.syncing)
        } else if downloadStatus == NSMetadataUbiquitousItemDownloadingStatusCurrent {
            _syncStatusChanged.send(.synced)
        } else if downloadStatus == NSMetadataUbiquitousItemDownloadingStatusNotDownloaded {
            // Trigger download
            if let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL {
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            }
            _syncStatusChanged.send(.syncing)
        }
    }
}
