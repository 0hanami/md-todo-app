//
//  VoiceInputView.swift
//  TodoWatch
//
//  Voice input UI with success/error feedback.
//  Tapping the TextField launches the standard watchOS input UI
//  (voice, scribble, emoji).
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
                iCloudUnavailableView
            } else if showSuccess {
                successView
            } else {
                inputView
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showSuccess)
    }

    // MARK: - Input UI

    private var inputView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checklist")
                .font(.title3)
                .foregroundColor(.blue)

            TextField("Add task", text: $inputText)
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
                    Label("Add", systemImage: "plus.circle.fill")
                }
            }
            .disabled(inputText.isEmpty || isProcessing)
            .tint(.green)
        }
    }

    // MARK: - Success Feedback

    private var successView: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundColor(.green)

            Text("Added")
                .font(.headline)
        }
    }

    // MARK: - iCloud Unavailable

    private var iCloudUnavailableView: some View {
        VStack(spacing: 8) {
            Image(systemName: "icloud.slash")
                .font(.title2)
                .foregroundColor(.orange)

            Text("Please sign in\nto iCloud Drive")
                .font(.caption)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Actions

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

                // Reset after 1.5 seconds
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
