import XCTest
@testable import MarkdownParser

final class ParsingTests: XCTestCase {

    let parser = MarkdownParser()

    func testExtractUncheckedTodo() {
        let content = "- [ ] Buy milk"
        let todos = parser.extractTodos(from: content)
        XCTAssertEqual(todos.count, 1)
        XCTAssertEqual(todos[0].text, "Buy milk")
        XCTAssertFalse(todos[0].isCompleted)
        XCTAssertEqual(todos[0].lineNumber, 0)
    }

    func testExtractCheckedTodo() {
        let content = "- [x] Done task"
        let todos = parser.extractTodos(from: content)
        XCTAssertEqual(todos.count, 1)
        XCTAssertEqual(todos[0].text, "Done task")
        XCTAssertTrue(todos[0].isCompleted)
    }

    func testExtractUppercaseX() {
        let content = "- [X] Done task"
        let todos = parser.extractTodos(from: content)
        XCTAssertEqual(todos.count, 1)
        XCTAssertTrue(todos[0].isCompleted)
    }

    func testExtractMultipleTodos() {
        let content = """
        # Tasks

        - [ ] Task 1
        - [x] Task 2
        - [ ] Task 3

        Some other text
        """
        let todos = parser.extractTodos(from: content)
        XCTAssertEqual(todos.count, 3)
    }

    func testSkipEmptyCheckbox() {
        let content = "- [ ] "
        let todos = parser.extractTodos(from: content)
        XCTAssertEqual(todos.count, 0)
    }

    func testPreserveLineNumbers() {
        let content = "# Header\n\n- [ ] First\n- [ ] Second"
        let todos = parser.extractTodos(from: content)
        XCTAssertEqual(todos[0].lineNumber, 2)
        XCTAssertEqual(todos[1].lineNumber, 3)
    }

    func testNonCheckboxLinesIgnored() {
        let content = "# Header\nSome text\n- Regular list item"
        let todos = parser.extractTodos(from: content)
        XCTAssertEqual(todos.count, 0)
    }

    func testIndentedCheckbox() {
        let content = "  - [ ] Indented task"
        let todos = parser.extractTodos(from: content)
        XCTAssertEqual(todos.count, 1)
        XCTAssertEqual(todos[0].text, "Indented task")
    }
}
