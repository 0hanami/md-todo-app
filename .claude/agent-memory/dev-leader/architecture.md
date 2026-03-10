# Architecture Decisions

## Library-First アーキテクチャ
3つの独立Swift Packageでロジックを分離し、iOSアプリはそれらに依存する構成:
- packages/MarkdownParser - Markdownチェックボックスの解析・更新
- packages/CloudKitSync - iCloud Documents同期
- packages/TodoManager - Todoビジネスロジック
- ios/TodoApp - SwiftUI アプリケーション

## MVVM + Combine
- ViewModel: @MainActor, @Published で状態管理
- View: SwiftUI宣言的UI
- Model: Equatableデータ構造体

## iCloud方式: CloudKit Documents + NSDocument
- ネイティブ同期、オフライン対応
- 外部エディタ（Obsidian）互換性
- NSFilePresenterで外部変更検知

## Markdownパーサー: 正規表現ベース
- NSRegularExpression使用
- ASTパーサー不要（チェックボックスのみ対象）
- フォーマット保持（元のMarkdown構造を壊さない）

## TDD: RED-GREEN-Refactor
- テスト順序: UI → 統合 → ユニット
- 実CloudKitサンドボックス使用（モック不使用）
