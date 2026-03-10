import XCTest
@testable import MarkdownParser

final class UpdateTests: XCTestCase {

    let parser = MarkdownParser()

    func testUpdateTodoCompletion() {
        let content = "- [ ] Task 1\n- [ ] Task 2"
        let todos = parser.extractTodos(from: content)

        let toggled = todos[0].toggled()
        let updated = parser.updateTodoInContent(content, todo: toggled)

        XCTAssertTrue(updated.contains("- [x] Task 1"))
        XCTAssertTrue(updated.contains("- [ ] Task 2"))
    }

    func testApplyTodosRemoveDeleted() {
        let content = "- [ ] Keep\n- [ ] Delete"
        let todos = parser.extractTodos(from: content)
        let remaining = [todos[0]]

        let updated = parser.applyTodosToContent(content, todos: remaining)
        XCTAssertTrue(updated.contains("- [ ] Keep"))
        XCTAssertFalse(updated.contains("Delete"))
    }

    func testApplyTodosAppendNew() {
        let content = "- [ ] Existing"
        let todos = parser.extractTodos(from: content)
        var allTodos = todos
        allTodos.append(TodoItem(text: "New task", isCompleted: false, lineNumber: -1, originalLine: ""))

        let updated = parser.applyTodosToContent(content, todos: allTodos)
        XCTAssertTrue(updated.contains("- [ ] Existing"))
        XCTAssertTrue(updated.contains("- [ ] New task"))
    }

    func testAddTodoToContent() {
        let content = "# Tasks\n"
        let updated = parser.addTodoToContent(content, text: "New task")
        XCTAssertTrue(updated.contains("- [ ] New task"))
    }

    func testAddEmptyTextDoesNothing() {
        let content = "# Tasks\n"
        let updated = parser.addTodoToContent(content, text: "  ")
        XCTAssertEqual(updated, content)
    }

    func testGenerateContent() {
        let todos = [
            TodoItem(text: "Pending", isCompleted: false, lineNumber: 0, originalLine: ""),
            TodoItem(text: "Done", isCompleted: true, lineNumber: 1, originalLine: ""),
        ]
        let content = parser.generateContent(from: todos)
        XCTAssertTrue(content.contains("## Pending Tasks"))
        XCTAssertTrue(content.contains("- [ ] Pending"))
        XCTAssertTrue(content.contains("## Completed Tasks"))
        XCTAssertTrue(content.contains("- [x] Done"))
    }

    func testPreserveNonCheckboxLines() {
        let content = "# Header\n\n- [ ] Task\n\nSome notes"
        let todos = parser.extractTodos(from: content)
        let updated = parser.applyTodosToContent(content, todos: todos)
        XCTAssertTrue(updated.contains("# Header"))
        XCTAssertTrue(updated.contains("Some notes"))
    }

    // MARK: - Edge Cases

    func testUpdateWithOutOfRangeLineNumber() {
        let content = "- [ ] Task"
        let todo = TodoItem(text: "Task", isCompleted: true, lineNumber: 999, originalLine: "")
        let updated = parser.updateTodoInContent(content, todo: todo)
        XCTAssertEqual(updated, content, "Out-of-range line number should leave content unchanged")
    }

    func testApplyTodosToEmptyContent() {
        let content = ""
        let todos = [TodoItem(text: "New", isCompleted: false, lineNumber: -1, originalLine: "")]
        let updated = parser.applyTodosToContent(content, todos: todos)
        XCTAssertTrue(updated.contains("- [ ] New"))
    }

    func testGenerateContentAllPending() {
        let todos = [
            TodoItem(text: "A", isCompleted: false, lineNumber: 0, originalLine: ""),
            TodoItem(text: "B", isCompleted: false, lineNumber: 1, originalLine: ""),
        ]
        let content = parser.generateContent(from: todos)
        XCTAssertTrue(content.contains("## Pending Tasks"))
        XCTAssertFalse(content.contains("## Completed Tasks"))
    }

    func testGenerateContentAllCompleted() {
        let todos = [
            TodoItem(text: "A", isCompleted: true, lineNumber: 0, originalLine: ""),
            TodoItem(text: "B", isCompleted: true, lineNumber: 1, originalLine: ""),
        ]
        let content = parser.generateContent(from: todos)
        XCTAssertFalse(content.contains("## Pending Tasks"))
        XCTAssertTrue(content.contains("## Completed Tasks"))
    }

    func testGenerateContentEmpty() {
        let content = parser.generateContent(from: [])
        XCTAssertTrue(content.contains("# Todo List"))
        XCTAssertFalse(content.contains("## Pending Tasks"))
        XCTAssertFalse(content.contains("## Completed Tasks"))
    }

    func testIsCheckboxLine() {
        XCTAssertTrue(parser.isCheckboxLine("- [ ] task"))
        XCTAssertTrue(parser.isCheckboxLine("- [x] task"))
        XCTAssertTrue(parser.isCheckboxLine("- [X] task"))
        XCTAssertTrue(parser.isCheckboxLine("  - [ ] indented"))
        XCTAssertFalse(parser.isCheckboxLine("- Regular item"))
        XCTAssertFalse(parser.isCheckboxLine("# Header"))
        XCTAssertFalse(parser.isCheckboxLine(""))
    }

    func testApplyTodosRemoveAll() {
        let content = "# Header\n- [ ] Task1\n- [ ] Task2\nFooter"
        let updated = parser.applyTodosToContent(content, todos: [])
        XCTAssertTrue(updated.contains("# Header"))
        XCTAssertTrue(updated.contains("Footer"))
        XCTAssertFalse(updated.contains("Task1"))
        XCTAssertFalse(updated.contains("Task2"))
    }
}
