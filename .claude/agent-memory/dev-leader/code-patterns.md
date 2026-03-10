# Code Patterns

## データモデル
```swift
struct TodoItem: Identifiable, Equatable {
    let id: UUID
    var text: String
    var isCompleted: Bool
    var lineNumber: Int
    var originalLine: String
}
```

## ViewModel パターン
```swift
@MainActor
class TodoViewModel: ObservableObject {
    @Published var todos: [TodoItem] = []
    @Published var errorMessage: String?
    // Combine で非同期処理
}
```

## MarkdownParser パターン
```swift
class MarkdownParser {
    func extractTodos(from content: String) -> [TodoItem]
    func updateTodoInContent(_ content: String, todo: TodoItem) -> String
    func addTodoToContent(_ content: String, text: String) -> String
}
```

## テスト（TDD RED）
```swift
func testExample() {
    // TODO: Implement
    XCTFail("Not yet implemented")
}
```

## 命名規則
- ファイル: PascalCase.swift
- 型: PascalCase
- プロパティ/メソッド: camelCase
- パッケージ: PascalCase（MarkdownParser, CloudKitSync, TodoManager）
