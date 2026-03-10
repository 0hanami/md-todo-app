import Foundation
import MarkdownParser

/// Aggregated statistics for a list of todo items.
public struct TodoStatistics: Equatable, Sendable {
    public let total: Int
    public let completed: Int
    public let pending: Int
    public let completionPercentage: Double

    public init(total: Int = 0, completed: Int = 0, pending: Int = 0, completionPercentage: Double = 0.0) {
        self.total = total
        self.completed = completed
        self.pending = pending
        self.completionPercentage = completionPercentage
    }

    public var completionPercentageString: String {
        String(format: "%.1f%%", completionPercentage)
    }

    /// Creates statistics from a list of todo items.
    public static func from(todos: [TodoItem]) -> TodoStatistics {
        let total = todos.count
        let completed = todos.filter { $0.isCompleted }.count
        let pending = total - completed
        let percentage = total > 0 ? Double(completed) / Double(total) * 100.0 : 0.0
        return TodoStatistics(total: total, completed: completed, pending: pending, completionPercentage: percentage)
    }
}
