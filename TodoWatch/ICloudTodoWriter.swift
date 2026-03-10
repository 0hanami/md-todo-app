//
//  ICloudTodoWriter.swift
//  TodoWatch
//
//  Writes tasks to todo.md on iCloud Drive.
//  Uses NSFileCoordinator for safe concurrent access.
//

import Foundation

enum TodoWriteError: LocalizedError {
    case iCloudNotAvailable
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .iCloudNotAvailable:
            return "iCloud Drive is not available"
        case .writeFailed(let reason):
            return "Write failed: \(reason)"
        }
    }
}

class ICloudTodoWriter {
    private let containerIdentifier = "iCloud.com.0hanami.mdtodo"

    /// URL for the iCloud Documents directory
    var iCloudDocumentsURL: URL? {
        FileManager.default.url(
            forUbiquityContainerIdentifier: containerIdentifier
        )?.appendingPathComponent("Documents")
    }

    /// URL for todo.md
    var todoFileURL: URL? {
        iCloudDocumentsURL?.appendingPathComponent("todo.md")
    }

    /// Check if iCloud is available
    var isAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    /// Append a task to todo.md
    /// - Creates the file if it doesn't exist
    /// - Appends `\n- [ ] text` to the end of the existing file
    /// - Uses NSFileCoordinator to prevent conflicts with iCloud sync
    func appendTodo(_ text: String) async throws {
        guard let fileURL = todoFileURL else {
            throw TodoWriteError.iCloudNotAvailable
        }

        // Create Documents directory if needed
        if let docsURL = iCloudDocumentsURL,
           !FileManager.default.fileExists(atPath: docsURL.path) {
            try FileManager.default.createDirectory(
                at: docsURL,
                withIntermediateDirectories: true
            )
        }

        let newLine = "- [ ] \(text)\n"

        // Write safely using NSFileCoordinator
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let coordinator = NSFileCoordinator()
            var coordinatorError: NSError?

            coordinator.coordinate(
                writingItemAt: fileURL,
                options: .forMerging,
                error: &coordinatorError
            ) { url in
                do {
                    if FileManager.default.fileExists(atPath: url.path) {
                        let handle = try FileHandle(forWritingTo: url)
                        handle.seekToEndOfFile()
                        if let data = newLine.data(using: .utf8) {
                            handle.write(data)
                        }
                        handle.closeFile()
                    } else {
                        // File doesn't exist; create with header
                        let header = "# Todo\n\n\(newLine)"
                        try header.write(to: url, atomically: true, encoding: .utf8)
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }

            if let error = coordinatorError {
                continuation.resume(throwing: error)
            }
        }
    }
}
