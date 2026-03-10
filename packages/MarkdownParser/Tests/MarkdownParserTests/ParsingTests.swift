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

    // MARK: - Edge Cases

    func testEmptyString() {
        let todos = parser.extractTodos(from: "")
        XCTAssertEqual(todos.count, 0)
    }

    func testWhitespaceOnlyContent() {
        let todos = parser.extractTodos(from: "   \n\n   \n")
        XCTAssertEqual(todos.count, 0)
    }

    func testLargeFile() {
        var content = "# Large File\n\n"
        for i in 0..<1000 {
            content += "- [ ] Task \(i)\n"
        }
        let todos = parser.extractTodos(from: content)
        XCTAssertEqual(todos.count, 1000)
        XCTAssertEqual(todos.first?.text, "Task 0")
        XCTAssertEqual(todos.last?.text, "Task 999")
    }

    func testMalformedCheckboxes() {
        let content = """
        - [] Missing space
        - [y] Invalid marker
        * [ ] Asterisk list
        """
        let todos = parser.extractTodos(from: content)
        XCTAssertEqual(todos.count, 0)
    }

    func testFlexibleDashSpacing() {
        // Parser accepts optional whitespace between dash and bracket
        let content = "-[ ] No space after dash\n-[x] Completed no space"
        let todos = parser.extractTodos(from: content)
        XCTAssertEqual(todos.count, 2)
    }

    func testSpecialCharactersInText() {
        let content = "- [ ] Task with emoji 🎉 and `code` and [link](url)"
        let todos = parser.extractTodos(from: content)
        XCTAssertEqual(todos.count, 1)
        XCTAssertTrue(todos[0].text.contains("🎉"))
    }

    func testUnicodeContent() {
        let content = "- [ ] 日本語タスク\n- [x] 完了済みタスク"
        let todos = parser.extractTodos(from: content)
        XCTAssertEqual(todos.count, 2)
        XCTAssertEqual(todos[0].text, "日本語タスク")
        XCTAssertTrue(todos[1].isCompleted)
    }

    func testOnlyHeadersNoTodos() {
        let content = "# Header 1\n## Header 2\n### Header 3\n"
        let todos = parser.extractTodos(from: content)
        XCTAssertEqual(todos.count, 0)
    }

    func testCheckboxLineWithTrailingWhitespace() {
        let content = "- [ ] Task with trailing spaces   "
        let todos = parser.extractTodos(from: content)
        XCTAssertEqual(todos.count, 1)
        XCTAssertEqual(todos[0].text, "Task with trailing spaces")
    }

    func testNoNewlineAtEnd() {
        let content = "- [ ] Last task without newline"
        let todos = parser.extractTodos(from: content)
        XCTAssertEqual(todos.count, 1)
    }
}
