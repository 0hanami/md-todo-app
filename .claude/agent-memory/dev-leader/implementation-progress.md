# Implementation Progress (47 Tasks)

## Phase 3.1: セットアップ (T001-T007)
- T001-T007: 部分的完了（Xcodeプロジェクト・パッケージ構成存在）

## Phase 3.2: テストファースト TDD (T008-T018)
- 全テストファイル作成済み、XCTFail()テンプレート状態
- UIテスト: AppLaunchTests, TodoDisplayTests, TodoToggleTests, ExternalChangeTests, OfflineTests
- ユニットテスト: ParsingTests, UpdateTests, LoadTodosTests, ToggleTodoTests, RefreshTests, SyncTests
- パッケージテスト: 25テスト全パス（MarkdownParser 15, CloudKitSync 7, TodoManager 3）

## Phase 3.3: コア実装 (T019-T031)
- データモデル: 実装済み（TodoItem in MarkdownParser, TodoStatistics in TodoManager, SyncStatus in CloudKitSync）
- MarkdownParser: 完成（extractTodos, updateTodoInContent, applyTodosToContent, addTodoToContent, generateContent）
- CloudKitSync: 完成
  - SyncStatus / StorageLocation 列挙型
  - FileCoordinator: NSFileCoordinator による安全なファイルRead/Write
  - ICloudFilePresenter: NSFilePresenter で外部変更検知、Combine Publisher
  - ICloudMetadataMonitor: NSMetadataQuery でiCloud同期状態監視
  - ConflictResolver: NSFileVersion コンフリクト検出・解決（keepNewest/keepLocal/keepRemote/merge）
  - CloudSyncManager: 統合マネージャ（ファイルI/O、同期状態、セキュリティスコープ、ブックマーク）
- TodoManager: 完成
  - CRUD操作: addTodo, addEmptyTodo, toggleTodo, removeTodo, removeCompletedTodos, updateTodoText, finishEditing, moveTodos
  - MarkdownParser連携: パース・シリアライズ（外部ファイルはフォーマット保持、内部ファイルはセクション生成）
  - CloudSyncManager連携: ファイルI/O委譲、外部変更自動検知・反映
  - TodoStatistics: 統計情報の自動更新
  - onTodosChanged コールバック（ウィジェット同期用）
- TodoApp.swift: 既存単一ファイル版（パッケージ移行前の状態、動作中）

## Phase 3.4: 統合 (T032-T037)
- 未着手（TodoApp.swift をパッケージベースに移行する作業）

## Phase 3.5: 仕上げ (T038-T047)
- 未着手
