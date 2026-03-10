import Foundation

/// A single todo item parsed from a Markdown checkbox line.
public struct TodoItem: Identifiable, Hashable, Equatable, Sendable {
    public let id: String
    public var text: String
    public var isCompleted: Bool
    public var lineNumber: Int
    public var originalLine: String

    public init(
        id: String = UUID().uuidString,
        text: String,
        isCompleted: Bool,
        lineNumber: Int,
        originalLine: String
    ) {
        self.id = id
        self.text = text
        self.isCompleted = isCompleted
        self.lineNumber = lineNumber
        self.originalLine = originalLine
    }

    /// Returns a copy with toggled completion state.
    public func toggled() -> TodoItem {
        TodoItem(
            id: id,
            text: text,
            isCompleted: !isCompleted,
            lineNumber: lineNumber,
            originalLine: originalLine
        )
    }

    /// Returns a copy with updated text.
    public func withText(_ newText: String) -> TodoItem {
        TodoItem(
            id: id,
            text: newText,
            isCompleted: isCompleted,
            lineNumber: lineNumber,
            originalLine: originalLine
        )
    }

    /// Returns a copy with updated line number.
    public func withLineNumber(_ newLineNumber: Int) -> TodoItem {
        TodoItem(
            id: id,
            text: text,
            isCompleted: isCompleted,
            lineNumber: newLineNumber,
            originalLine: originalLine
        )
    }
}
