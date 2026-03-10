import XCTest
@testable import TodoManager
import MarkdownParser

final class TodoStatisticsTests: XCTestCase {

    func testEmptyStatistics() {
        let stats = TodoStatistics()
        XCTAssertEqual(stats.total, 0)
        XCTAssertEqual(stats.completed, 0)
        XCTAssertEqual(stats.pending, 0)
        XCTAssertEqual(stats.completionPercentage, 0.0)
    }

    func testFromTodos() {
        let todos = [
            TodoItem(text: "A", isCompleted: false, lineNumber: 0, originalLine: ""),
            TodoItem(text: "B", isCompleted: true, lineNumber: 1, originalLine: ""),
            TodoItem(text: "C", isCompleted: true, lineNumber: 2, originalLine: ""),
        ]

        let stats = TodoStatistics.from(todos: todos)
        XCTAssertEqual(stats.total, 3)
        XCTAssertEqual(stats.completed, 2)
        XCTAssertEqual(stats.pending, 1)
        XCTAssertEqual(stats.completionPercentage, 200.0 / 3.0, accuracy: 0.1)
    }

    func testCompletionPercentageString() {
        let stats = TodoStatistics(total: 4, completed: 3, pending: 1, completionPercentage: 75.0)
        XCTAssertEqual(stats.completionPercentageString, "75.0%")
    }
}
