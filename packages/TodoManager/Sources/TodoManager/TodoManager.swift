import Foundation
import Combine
import MarkdownParser
import CloudKitSync

/// Central business logic for todo CRUD operations.
///
/// Integrates MarkdownParser for reading/writing Markdown content
/// and CloudSyncManager for file I/O and sync.
///
/// Usage:
/// ```swift
/// let syncManager = CloudSyncManager()
/// let todoManager = TodoManager(syncManager: syncManager)
/// todoManager.loadTodos()
/// todoManager.addTodo(text: "Buy milk")
/// todoManager.toggleTodo(id: someId)
/// ```
@MainActor
public final class TodoManager: ObservableObject {

    // MARK: - Published State

    @Published public var todos: [TodoItem] = []
    @Published public var statistics: TodoStatistics = TodoStatistics()
    @Published public var errorMessage: String?

    // MARK: - Dependencies

    public let syncManager: CloudSyncManager
    private let parser: MarkdownParser
    private var originalFileContent: String?
    private var cancellables = Set<AnyCancellable>()

    /// Callback invoked whenever todos change, for widget data sync etc.
    public var onTodosChanged: (([TodoItem]) -> Void)?

    // MARK: - Init

    /// Creates a TodoManager with the given sync manager.
    ///
    /// - Parameters:
    ///   - syncManager: The CloudSyncManager for file I/O.
    ///   - parser: The MarkdownParser instance (default: new instance).
    public init(syncManager: CloudSyncManager, parser: MarkdownParser = MarkdownParser()) {
        self.syncManager = syncManager
        self.parser = parser

        setupSubscriptions()
    }

    // MARK: - File Operations

    /// Loads todos from the current file.
    public func loadTodos() {
        guard let content = syncManager.readCurrentFile() else {
            originalFileContent = nil
            todos = []
            updateStatistics()
            return
        }

        originalFileContent = content
        todos = parser.extractTodos(from: content)
        updateStatistics()
        notifyChanged()
    }

    /// Opens an external file and loads its todos.
    ///
    /// - Parameter url: The file URL to open.
    public func openFile(url: URL) {
        syncManager.selectExternalFile(url: url)
        loadTodos()
    }

    /// Creates a new file and sets it as current.
    ///
    /// - Parameter name: The file name (e.g. "notes.md").
    public func createNewFile(name: String) {
        let title = name.replacingOccurrences(of: ".md", with: "")
        let initialContent = "# \(title)\n\n"

        if syncManager.createNewFile(name: name, content: initialContent) {
            originalFileContent = initialContent
            todos = []
            updateStatistics()
            notifyChanged()
        }
    }

    /// Resets to the default file for the current storage location.
    public func resetToDefaultFile() {
        syncManager.resetToDefault()
        loadTodos()
    }

    // MARK: - CRUD Operations

    /// Adds a new todo with the given text.
    ///
    /// - Parameter text: The todo text (whitespace-trimmed).
    public func addTodo(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let newTodo = TodoItem(
            text: trimmed,
            isCompleted: false,
            lineNumber: -1,
            originalLine: "- [ ] \(trimmed)"
        )

        todos.append(newTodo)
        updateStatistics()
        saveToFile()
        notifyChanged()
    }

    /// Adds a new empty todo for inline editing.
    ///
    /// - Returns: The ID of the created todo.
    @discardableResult
    public func addEmptyTodo() -> String {
        let newTodo = TodoItem(
            text: "",
            isCompleted: false,
            lineNumber: -1,
            originalLine: "- [ ] "
        )
        todos.append(newTodo)
        updateStatistics()
        return newTodo.id
    }

    /// Toggles the completion state of a todo.
    ///
    /// - Parameter id: The todo's ID.
    public func toggleTodo(id: String) {
        guard let index = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[index] = todos[index].toggled()
        updateStatistics()
        saveToFile()
        notifyChanged()
    }

    /// Removes a todo by ID.
    ///
    /// - Parameter id: The todo's ID.
    public func removeTodo(id: String) {
        todos.removeAll { $0.id == id }
        updateStatistics()
        saveToFile()
        notifyChanged()
    }

    /// Removes all completed todos.
    public func removeCompletedTodos() {
        todos.removeAll { $0.isCompleted }
        updateStatistics()
        saveToFile()
        notifyChanged()
    }

    /// Updates the text of a todo (for inline editing).
    ///
    /// - Parameters:
    ///   - id: The todo's ID.
    ///   - text: The new text.
    public func updateTodoText(id: String, text: String) {
        guard let index = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[index] = todos[index].withText(text)
    }

    /// Finalizes editing of a todo. Removes if empty, saves if not.
    ///
    /// - Parameter id: The todo's ID.
    /// - Returns: Whether the todo was kept (true) or removed (false).
    @discardableResult
    public func finishEditing(id: String) -> Bool {
        guard let index = todos.firstIndex(where: { $0.id == id }) else { return false }

        if todos[index].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            todos.remove(at: index)
            updateStatistics()
            notifyChanged()
            return false
        } else {
            updateStatistics()
            saveToFile()
            notifyChanged()
            return true
        }
    }

    /// Moves todos from source indices to a destination index.
    ///
    /// - Parameters:
    ///   - source: Source index set.
    ///   - destination: Destination index.
    public func moveTodos(from source: IndexSet, to destination: Int) {
        // Replicate Array.move(fromOffsets:toOffset:) without SwiftUI dependency
        var items = todos
        let moved = source.map { items[$0] }
        // Remove in reverse to keep indices valid
        for index in source.sorted().reversed() {
            items.remove(at: index)
        }
        let adjustedDestination = min(destination, items.count)
        items.insert(contentsOf: moved, at: adjustedDestination)
        todos = items

        // Update line numbers to reflect new order
        for (index, _) in todos.enumerated() {
            todos[index] = todos[index].withLineNumber(index + 1)
        }

        updateStatistics()
        saveToFile()
        notifyChanged()
    }

    // MARK: - Sync

    /// Switches storage to iCloud Drive.
    public func switchToICloud() {
        syncManager.switchToICloud()
        loadTodos()
    }

    /// Switches storage to local device.
    public func switchToLocal() {
        syncManager.switchToLocal()
        loadTodos()
    }

    /// Manually triggers a file save.
    public func saveToFile() {
        let content: String

        if syncManager.isExternalFile, let originalContent = originalFileContent {
            content = parser.applyTodosToContent(originalContent, todos: todos)
        } else {
            content = parser.generateContent(from: todos)
        }

        originalFileContent = content
        syncManager.writeCurrentFile(content)
    }

    // MARK: - Private

    private func setupSubscriptions() {
        syncManager.contentChanged
            .sink { [weak self] content in
                self?.handleExternalContentChange(content)
            }
            .store(in: &cancellables)
    }

    private func handleExternalContentChange(_ content: String) {
        originalFileContent = content
        todos = parser.extractTodos(from: content)
        updateStatistics()
        notifyChanged()
    }

    public func updateStatistics() {
        statistics = TodoStatistics.from(todos: todos)
    }

    private func notifyChanged() {
        onTodosChanged?(todos)
    }
}
