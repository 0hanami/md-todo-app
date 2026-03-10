import Foundation

/// Parses Markdown content to extract and manipulate todo checkbox items.
///
/// Handles the standard Markdown checkbox syntax:
/// - `- [ ] task` for uncompleted items
/// - `- [x] task` or `- [X] task` for completed items
///
/// Preserves original Markdown formatting for non-checkbox lines.
public final class MarkdownParser: Sendable {

    // MARK: - Regex Patterns

    /// Matches `- [ ] text`, `- [x] text`, `- [X] text` with optional leading whitespace.
    private static let checkboxPattern = try! NSRegularExpression(
        pattern: #"^(\s*)-\s*\[([ xX])\]\s*(.*)"#,
        options: []
    )

    public init() {}

    // MARK: - Extraction

    /// Extracts all todo items from Markdown content.
    ///
    /// - Parameter content: Raw Markdown string.
    /// - Returns: Array of `TodoItem` with line numbers corresponding to the source.
    public func extractTodos(from content: String) -> [TodoItem] {
        let lines = content.components(separatedBy: "\n")
        var todos: [TodoItem] = []

        for (index, line) in lines.enumerated() {
            if let todo = parseLine(line, at: index) {
                todos.append(todo)
            }
        }

        return todos
    }

    // MARK: - Content Update

    /// Returns updated Markdown content with the given todo's completion state applied.
    ///
    /// Only the line at `todo.lineNumber` is modified; all other lines are preserved.
    ///
    /// - Parameters:
    ///   - content: Original Markdown content.
    ///   - todo: The todo item with updated state.
    /// - Returns: Updated Markdown string.
    public func updateTodoInContent(_ content: String, todo: TodoItem) -> String {
        var lines = content.components(separatedBy: "\n")
        guard todo.lineNumber >= 0, todo.lineNumber < lines.count else { return content }

        let originalLine = lines[todo.lineNumber]
        let range = NSRange(originalLine.startIndex..., in: originalLine)

        guard let match = Self.checkboxPattern.firstMatch(in: originalLine, range: range) else {
            return content
        }

        let leadingWhitespace = extractGroup(match, group: 1, in: originalLine)
        let checkbox = todo.isCompleted ? "x" : " "
        lines[todo.lineNumber] = "\(leadingWhitespace)- [\(checkbox)] \(todo.text)"

        return lines.joined(separator: "\n")
    }

    /// Returns updated Markdown content with all provided todos applied.
    ///
    /// Handles:
    /// - Updating existing checkbox lines
    /// - Removing deleted checkbox lines
    /// - Appending new todos (lineNumber < 0)
    ///
    /// - Parameters:
    ///   - content: Original Markdown content.
    ///   - todos: Current list of todo items.
    /// - Returns: Updated Markdown string.
    public func applyTodosToContent(_ content: String, todos: [TodoItem]) -> String {
        var lines = content.components(separatedBy: "\n")

        // Map existing todos by line number
        var todosByLine: [Int: TodoItem] = [:]
        for todo in todos where todo.lineNumber >= 0 && todo.lineNumber < lines.count {
            todosByLine[todo.lineNumber] = todo
        }

        // Update existing checkbox lines
        for (lineNum, todo) in todosByLine {
            let originalLine = lines[lineNum]
            let range = NSRange(originalLine.startIndex..., in: originalLine)
            if let match = Self.checkboxPattern.firstMatch(in: originalLine, range: range) {
                let leadingWhitespace = extractGroup(match, group: 1, in: originalLine)
                let checkbox = todo.isCompleted ? "x" : " "
                lines[lineNum] = "\(leadingWhitespace)- [\(checkbox)] \(todo.text)"
            }
        }

        // Remove lines for deleted todos (checkbox lines not in todosByLine)
        let existingLineNumbers = Set(todosByLine.keys)
        var linesToRemove: [Int] = []
        for (index, line) in lines.enumerated() {
            if isCheckboxLine(line) && !existingLineNumbers.contains(index) {
                linesToRemove.append(index)
            }
        }
        for index in linesToRemove.sorted().reversed() {
            lines.remove(at: index)
        }

        // Append new todos
        let newTodos = todos.filter { $0.lineNumber < 0 }
        for todo in newTodos {
            let checkbox = todo.isCompleted ? "x" : " "
            lines.append("- [\(checkbox)] \(todo.text)")
        }

        return lines.joined(separator: "\n")
    }

    /// Adds a new todo line to the end of the content.
    ///
    /// - Parameters:
    ///   - content: Original Markdown content.
    ///   - text: The todo text.
    /// - Returns: Updated Markdown string with the new checkbox appended.
    public func addTodoToContent(_ content: String, text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return content }

        let newLine = "- [ ] \(trimmed)"
        if content.hasSuffix("\n") {
            return content + newLine + "\n"
        } else {
            return content + "\n" + newLine
        }
    }

    /// Generates Markdown content from scratch for internal (non-external) files.
    ///
    /// - Parameter todos: List of todo items.
    /// - Returns: Formatted Markdown string.
    public func generateContent(from todos: [TodoItem]) -> String {
        var content = "# Todo List\n\n"

        let pending = todos.filter { !$0.isCompleted }
        if !pending.isEmpty {
            content += "## Pending Tasks\n\n"
            for todo in pending {
                content += "- [ ] \(todo.text)\n"
            }
            content += "\n"
        }

        let completed = todos.filter { $0.isCompleted }
        if !completed.isEmpty {
            content += "## Completed Tasks\n\n"
            for todo in completed {
                content += "- [x] \(todo.text)\n"
            }
            content += "\n"
        }

        return content
    }

    // MARK: - Helpers

    /// Checks if a line is a Markdown checkbox line.
    public func isCheckboxLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("- [ ]") || trimmed.hasPrefix("- [x]") || trimmed.hasPrefix("- [X]")
    }

    /// Parses a single line into a TodoItem if it matches checkbox syntax.
    private func parseLine(_ line: String, at lineNumber: Int) -> TodoItem? {
        let range = NSRange(line.startIndex..., in: line)
        guard let match = Self.checkboxPattern.firstMatch(in: line, range: range) else {
            return nil
        }

        let checkboxChar = extractGroup(match, group: 2, in: line)
        let text = extractGroup(match, group: 3, in: line)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else { return nil }

        let isCompleted = checkboxChar.lowercased() == "x"

        return TodoItem(
            text: text,
            isCompleted: isCompleted,
            lineNumber: lineNumber,
            originalLine: line
        )
    }

    private func extractGroup(_ match: NSTextCheckingResult, group: Int, in string: String) -> String {
        guard group < match.numberOfRanges,
              let range = Range(match.range(at: group), in: string) else {
            return ""
        }
        return String(string[range])
    }
}
