import Foundation

/// Provides thread-safe file read/write using NSFileCoordinator.
///
/// All iCloud Documents file operations should go through this class
/// to avoid data corruption from concurrent access.
public final class FileCoordinator: Sendable {

    public init() {}

    // MARK: - Coordinated Read

    /// Reads file content using NSFileCoordinator for safe concurrent access.
    ///
    /// - Parameter url: The file URL to read.
    /// - Returns: The file content as a string.
    /// - Throws: File coordination or reading errors.
    public func readFile(at url: URL) throws -> String {
        var coordinatorError: NSError?
        var readResult: Result<String, Error> = .failure(
            CocoaError(.fileReadUnknown)
        )

        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(
            readingItemAt: url,
            options: .withoutChanges,
            error: &coordinatorError
        ) { coordinatedURL in
            do {
                let content = try String(contentsOf: coordinatedURL, encoding: .utf8)
                readResult = .success(content)
            } catch {
                readResult = .failure(error)
            }
        }

        if let error = coordinatorError {
            throw error
        }

        return try readResult.get()
    }

    // MARK: - Coordinated Write

    /// Writes content to a file using NSFileCoordinator for safe concurrent access.
    ///
    /// - Parameters:
    ///   - content: The string content to write.
    ///   - url: The destination file URL.
    /// - Throws: File coordination or writing errors.
    public func writeFile(_ content: String, to url: URL) throws {
        var coordinatorError: NSError?
        var writeError: Error?

        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(
            writingItemAt: url,
            options: .forReplacing,
            error: &coordinatorError
        ) { coordinatedURL in
            do {
                try content.write(to: coordinatedURL, atomically: true, encoding: .utf8)
            } catch {
                writeError = error
            }
        }

        if let error = coordinatorError {
            throw error
        }
        if let error = writeError {
            throw error
        }
    }

    // MARK: - File Metadata

    /// Returns the modification date of the file at the given URL.
    ///
    /// - Parameter url: The file URL.
    /// - Returns: The modification date, or nil if unavailable.
    public func modificationDate(of url: URL) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }
}
