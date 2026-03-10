import Foundation
import Combine

/// Manages iCloud Documents file synchronization.
///
/// Coordinates between NSFilePresenter (external change detection),
/// NSMetadataQuery (sync status), NSFileCoordinator (safe I/O),
/// and ConflictResolver (version conflicts).
///
/// Usage:
/// ```swift
/// let syncManager = CloudSyncManager()
/// syncManager.configure(containerIdentifier: "iCloud.com.example.app")
/// syncManager.startSync(fileName: "todo.md")
/// ```
@MainActor
public final class CloudSyncManager: ObservableObject {

    // MARK: - Published State

    @Published public var syncStatus: SyncStatus = .idle
    @Published public var storageLocation: StorageLocation = .local
    @Published public var currentFileURL: URL?
    @Published public var currentFileName: String = "todo.md"
    @Published public var isExternalFile: Bool = false

    // MARK: - Publishers

    private let _contentChanged = PassthroughSubject<String, Never>()

    /// Emits updated file content when an external change is detected.
    public var contentChanged: AnyPublisher<String, Never> {
        _contentChanged.eraseToAnyPublisher()
    }

    // MARK: - Dependencies

    private let fileCoordinator = FileCoordinator()
    private let filePresenter = ICloudFilePresenter()
    private let metadataMonitor = ICloudMetadataMonitor()
    private let conflictResolver = ConflictResolver()

    // MARK: - Private State

    private var containerIdentifier: String = "iCloud.com.0hanami.mdtodo"
    private var cancellables = Set<AnyCancellable>()
    private var isAccessingSecurityScope = false
    private let bookmarkKey = "selectedFileBookmark"
    private let storageLocationKey = "storageLocation"
    private var lastKnownModDate: Date?

    // MARK: - Computed

    public var isICloudAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    public var iCloudDocumentsURL: URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: containerIdentifier)?
            .appendingPathComponent("Documents")
    }

    public var localDocumentsURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }

    public var defaultFileURL: URL? {
        localDocumentsURL?.appendingPathComponent("todo.md")
    }

    public var iCloudDefaultFileURL: URL? {
        iCloudDocumentsURL?.appendingPathComponent("todo.md")
    }

    // MARK: - Init

    public init() {
        let savedLocation = UserDefaults.standard.string(forKey: storageLocationKey) ?? "local"
        storageLocation = StorageLocation(rawValue: savedLocation) ?? .local

        setupSubscriptions()
        restoreFileLocation()
    }

    /// Sets the iCloud container identifier.
    ///
    /// - Parameter identifier: The container ID (e.g. "iCloud.com.example.app").
    public func configure(containerIdentifier: String) {
        self.containerIdentifier = containerIdentifier
    }

    // MARK: - File Location

    /// Starts sync monitoring for the current file.
    public func startSync() {
        guard let url = currentFileURL else { return }

        filePresenter.startMonitoring(url: url)

        if storageLocation == .icloud {
            metadataMonitor.startMonitoring(fileName: currentFileName)
            syncStatus = .synced
        }

        lastKnownModDate = fileCoordinator.modificationDate(of: url)
    }

    /// Stops all sync monitoring.
    public func stopSync() {
        filePresenter.stopMonitoring()
        metadataMonitor.stopMonitoring()
        syncStatus = .idle
    }

    /// Switches storage to iCloud Drive, migrating the local file if needed.
    public func switchToICloud() {
        guard isICloudAvailable, let iCloudDocsURL = iCloudDocumentsURL else { return }

        // Create iCloud Documents directory if needed
        if !FileManager.default.fileExists(atPath: iCloudDocsURL.path) {
            try? FileManager.default.createDirectory(at: iCloudDocsURL, withIntermediateDirectories: true)
        }

        // Migrate local file if iCloud file doesn't exist
        let iCloudFileURL = iCloudDocsURL.appendingPathComponent("todo.md")
        if let localURL = defaultFileURL,
           FileManager.default.fileExists(atPath: localURL.path),
           !FileManager.default.fileExists(atPath: iCloudFileURL.path) {
            try? FileManager.default.copyItem(at: localURL, to: iCloudFileURL)
        }

        stopAccessingSecurityScope()
        clearBookmark()
        storageLocation = .icloud
        UserDefaults.standard.set(storageLocation.rawValue, forKey: storageLocationKey)
        currentFileURL = iCloudFileURL
        currentFileName = "todo.md"
        isExternalFile = false
        syncStatus = .synced

        startSync()
    }

    /// Switches storage to local device.
    public func switchToLocal() {
        stopSync()
        stopAccessingSecurityScope()
        clearBookmark()
        storageLocation = .local
        UserDefaults.standard.set(storageLocation.rawValue, forKey: storageLocationKey)
        currentFileURL = defaultFileURL
        currentFileName = "todo.md"
        isExternalFile = false
        syncStatus = .idle
    }

    /// Opens an external file via document picker.
    ///
    /// - Parameter url: The URL of the file selected by the user.
    public func selectExternalFile(url: URL) {
        stopSync()
        stopAccessingSecurityScope()

        do {
            let bookmarkData = try url.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmarkData, forKey: bookmarkKey)
        } catch {
            #if DEBUG
            print("Failed to save bookmark: \(error)")
            #endif
        }

        currentFileURL = url
        currentFileName = url.lastPathComponent
        isExternalFile = true

        filePresenter.startMonitoring(url: url)
    }

    /// Resets to the default file for the current storage location.
    public func resetToDefault() {
        stopSync()
        stopAccessingSecurityScope()
        clearBookmark()
        isExternalFile = false

        if storageLocation == .icloud && isICloudAvailable {
            setupICloudLocation()
        } else {
            currentFileURL = defaultFileURL
            currentFileName = "todo.md"
        }

        startSync()
    }

    // MARK: - File I/O

    /// Reads the current file content using coordinated I/O.
    ///
    /// - Returns: The file content, or nil if the file doesn't exist or can't be read.
    public func readCurrentFile() -> String? {
        guard let url = currentFileURL else { return nil }

        let accessed = startAccessingSecurityScope()
        defer {
            if isExternalFile { stopAccessingSecurityScope() }
        }
        guard accessed else { return nil }

        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        do {
            let content = try fileCoordinator.readFile(at: url)
            lastKnownModDate = fileCoordinator.modificationDate(of: url)
            return content
        } catch {
            #if DEBUG
            print("Failed to read file: \(error)")
            #endif
            syncStatus = .error(error.localizedDescription)
            return nil
        }
    }

    /// Writes content to the current file using coordinated I/O.
    ///
    /// - Parameter content: The string content to write.
    /// - Returns: Whether the write succeeded.
    @discardableResult
    public func writeCurrentFile(_ content: String) -> Bool {
        guard let url = currentFileURL else { return false }

        let accessed = startAccessingSecurityScope()
        defer {
            if isExternalFile { stopAccessingSecurityScope() }
        }
        guard accessed else { return false }

        do {
            try fileCoordinator.writeFile(content, to: url)
            lastKnownModDate = fileCoordinator.modificationDate(of: url)
            return true
        } catch {
            #if DEBUG
            print("Failed to write file: \(error)")
            #endif
            syncStatus = .error(error.localizedDescription)
            return false
        }
    }

    /// Creates a new file in the local Documents directory.
    ///
    /// - Parameters:
    ///   - name: The file name (e.g. "notes.md").
    ///   - content: Initial content for the file.
    /// - Returns: Whether the creation succeeded.
    @discardableResult
    public func createNewFile(name: String, content: String) -> Bool {
        guard let docsDir = localDocumentsURL else { return false }
        let fileURL = docsDir.appendingPathComponent(name)

        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            stopSync()
            clearBookmark()
            currentFileURL = fileURL
            currentFileName = name
            isExternalFile = false
            startSync()
            return true
        } catch {
            #if DEBUG
            print("Failed to create file: \(error)")
            #endif
            return false
        }
    }

    // MARK: - Conflict Resolution

    /// Attempts to resolve any file version conflicts.
    ///
    /// - Parameter strategy: The resolution strategy to use.
    /// - Returns: The resolved content, or nil if no conflicts.
    public func resolveConflicts(
        strategy: ConflictResolutionStrategy = .keepNewest
    ) -> String? {
        guard let url = currentFileURL else { return nil }

        do {
            let resolved = try conflictResolver.resolveConflicts(at: url, strategy: strategy)
            if let content = resolved {
                writeCurrentFile(content)
                syncStatus = .synced
            }
            return resolved
        } catch {
            #if DEBUG
            print("Failed to resolve conflicts: \(error)")
            #endif
            syncStatus = .error(error.localizedDescription)
            return nil
        }
    }

    // MARK: - Security Scoped Access

    public func startAccessingSecurityScope() -> Bool {
        guard let url = currentFileURL, isExternalFile else { return true }
        if isAccessingSecurityScope { return true }
        isAccessingSecurityScope = url.startAccessingSecurityScopedResource()
        return isAccessingSecurityScope
    }

    public func stopAccessingSecurityScope() {
        guard isAccessingSecurityScope, let url = currentFileURL else { return }
        url.stopAccessingSecurityScopedResource()
        isAccessingSecurityScope = false
    }

    // MARK: - Private

    private func setupSubscriptions() {
        filePresenter.fileChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] url in
                self?.handleExternalChange(url: url)
            }
            .store(in: &cancellables)

        filePresenter.conflictDetected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] url in
                self?.handleConflict(url: url)
            }
            .store(in: &cancellables)

        metadataMonitor.syncStatusChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.syncStatus = status
            }
            .store(in: &cancellables)

        metadataMonitor.fileUpdated
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self = self, let url = self.currentFileURL else { return }
                self.handleExternalChange(url: url)
            }
            .store(in: &cancellables)
    }

    private func handleExternalChange(url: URL) {
        // Avoid reloading if we just wrote the file
        let currentModDate = fileCoordinator.modificationDate(of: url)
        if let lastKnown = lastKnownModDate, let current = currentModDate,
           abs(lastKnown.timeIntervalSince(current)) < 0.5 {
            return
        }

        guard let content = readCurrentFile() else { return }
        _contentChanged.send(content)
    }

    private func handleConflict(url: URL) {
        syncStatus = .conflict(local: Date(), remote: Date())
    }

    private func restoreFileLocation() {
        if let restoredURL = restoreBookmark() {
            currentFileURL = restoredURL
            currentFileName = restoredURL.lastPathComponent
            isExternalFile = true
        } else if storageLocation == .icloud && isICloudAvailable {
            setupICloudLocation()
        } else {
            currentFileURL = defaultFileURL
            currentFileName = "todo.md"
            isExternalFile = false
        }
    }

    private func setupICloudLocation() {
        guard let iCloudDocsURL = iCloudDocumentsURL else {
            currentFileURL = defaultFileURL
            currentFileName = "todo.md"
            storageLocation = .local
            return
        }

        if !FileManager.default.fileExists(atPath: iCloudDocsURL.path) {
            try? FileManager.default.createDirectory(at: iCloudDocsURL, withIntermediateDirectories: true)
        }

        currentFileURL = iCloudDocsURL.appendingPathComponent("todo.md")
        currentFileName = "todo.md"
        syncStatus = .synced
    }

    private func restoreBookmark() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }

        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if isStale {
                let newData = try url.bookmarkData(
                    options: .minimalBookmark,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                UserDefaults.standard.set(newData, forKey: bookmarkKey)
            }
            return url
        } catch {
            UserDefaults.standard.removeObject(forKey: bookmarkKey)
            return nil
        }
    }

    private func clearBookmark() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
    }
}
