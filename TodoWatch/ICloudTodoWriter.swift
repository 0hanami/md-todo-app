//
//  ICloudTodoWriter.swift
//  TodoWatch
//
//  iCloud Drive上のtodo.mdにタスクを追記するクラス
//  NSFileCoordinatorで安全に書き込む
//

import Foundation

enum TodoWriteError: LocalizedError {
    case iCloudNotAvailable
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .iCloudNotAvailable:
            return "iCloud Driveが利用できません"
        case .writeFailed(let reason):
            return "書き込み失敗: \(reason)"
        }
    }
}

class ICloudTodoWriter {
    private let containerIdentifier = "iCloud.com.0hanami.mdtodo"

    /// iCloud Documents ディレクトリのURL
    var iCloudDocumentsURL: URL? {
        FileManager.default.url(
            forUbiquityContainerIdentifier: containerIdentifier
        )?.appendingPathComponent("Documents")
    }

    /// todo.md のURL
    var todoFileURL: URL? {
        iCloudDocumentsURL?.appendingPathComponent("todo.md")
    }

    /// iCloudが利用可能かチェック
    var isAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    /// タスクを追記
    /// - ファイルが存在しない場合は新規作成
    /// - 既存ファイルの末尾に `- [ ] テキスト` を追記
    /// - NSFileCoordinator を使用してiCloud同期との競合を防ぐ
    func appendTodo(_ text: String) async throws {
        guard let fileURL = todoFileURL else {
            throw TodoWriteError.iCloudNotAvailable
        }

        // Documentsディレクトリがなければ作成
        if let docsURL = iCloudDocumentsURL,
           !FileManager.default.fileExists(atPath: docsURL.path) {
            try FileManager.default.createDirectory(
                at: docsURL,
                withIntermediateDirectories: true
            )
        }

        let newLine = "- [ ] \(text)\n"

        // NSFileCoordinatorで安全に書き込み
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
                        // ファイルが存在しない場合は新規作成
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
