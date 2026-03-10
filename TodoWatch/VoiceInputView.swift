//
//  VoiceInputView.swift
//  TodoWatch
//
//  音声入力UI + 成功/エラーフィードバック
//  TextFieldタップでwatchOS標準入力UI（音声/手書き/絵文字）が起動する
//

import SwiftUI
import WatchKit

struct VoiceInputView: View {
    @State private var inputText = ""
    @State private var showSuccess = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isProcessing = false
    private let writer = ICloudTodoWriter()

    var body: some View {
        VStack(spacing: 12) {
            if !writer.isAvailable {
                // iCloud未利用時の案内
                iCloudUnavailableView
            } else if showSuccess {
                // 成功フィードバック
                successView
            } else {
                // 通常の入力UI
                inputView
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showSuccess)
    }

    // MARK: - 入力UI

    private var inputView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checklist")
                .font(.title3)
                .foregroundColor(.blue)

            TextField("タスクを入力", text: $inputText)
                .textInputAutocapitalization(.sentences)

            if showError {
                Text(errorMessage)
                    .font(.caption2)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }

            Button(action: addTodo) {
                if isProcessing {
                    ProgressView()
                } else {
                    Label("追加", systemImage: "plus.circle.fill")
                }
            }
            .disabled(inputText.isEmpty || isProcessing)
            .tint(.green)
        }
    }

    // MARK: - 成功フィードバック

    private var successView: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundColor(.green)

            Text("追加しました")
                .font(.headline)
        }
    }

    // MARK: - iCloud未利用

    private var iCloudUnavailableView: some View {
        VStack(spacing: 8) {
            Image(systemName: "icloud.slash")
                .font(.title2)
                .foregroundColor(.orange)

            Text("iCloud Driveに\nサインインしてください")
                .font(.caption)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - アクション

    private func addTodo() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        isProcessing = true
        showError = false

        Task {
            do {
                try await writer.appendTodo(text)

                await MainActor.run {
                    isProcessing = false
                    inputText = ""
                    showSuccess = true
                    WKInterfaceDevice.current().play(.success)
                }

                // 1.5秒後にリセット
                try? await Task.sleep(nanoseconds: 1_500_000_000)

                await MainActor.run {
                    showSuccess = false
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                    showError = true
                    errorMessage = error.localizedDescription
                    WKInterfaceDevice.current().play(.failure)
                }
            }
        }
    }
}
