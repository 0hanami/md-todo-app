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
}
