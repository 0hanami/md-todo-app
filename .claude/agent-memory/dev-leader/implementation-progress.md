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
- TodoApp.swift: パッケージベースに移行済み（712行）

## Phase 3.4: 統合 (T032-T037)
- **完了**: TodoApp.swift をパッケージベースに移行完了
  - TodoManager, CloudKitSync, MarkdownParser パッケージをimport
  - SharedDataManager: App Group経由ウィジェットJSON共有（維持）
  - DocumentPicker: UIViewControllerRepresentable（md/plainText対応）
  - NewFileSheet: 新規ファイル作成UI
  - ContentView: メニューUI統合（ファイル操作、Storage切替、Obsidian連携）
  - fileInfoFooter: iCloud/外部ファイル状態表示
  - ナビタイトル動的化（syncManager.currentFileName）
  - エラーハンドリング（alert表示）

## Phase 3.5: 仕上げ (T038-T047)
- ビルド確認: `xcodebuild -scheme TodoApp` BUILD SUCCEEDED (2026-03-16)
- Entitlements: iCloud関連設定済み（iCloud.com.0hanami.mdtodo）
- Info.plist: UIFileSharingEnabled, LSSupportsOpeningDocumentsInPlace, CFBundleDocumentTypes 設定済み

## iCloud & ファイルピッカー設計書対応状況
| Task | 内容 | 状態 |
|------|------|------|
| Phase1 #1 | FileLocationManager | CloudSyncManagerに統合済み |
| Phase1 #2 | SimpleTodoManager改修 | TodoManagerパッケージに実装済み |
| Phase1 #3 | mdパーサー改修 | MarkdownParser.applyTodosToContent()で実装済み |
| Phase1 #4 | DocumentPicker | TodoApp.swiftに実装済み |
| Phase1 #5 | UI統合 | メニュー・ナビタイトル・フッター実装済み |
| Phase2 #7 | Entitlements更新 | TodoApp.entitlementsに設定済み |
| Phase2 #8 | iCloud保存先実装 | CloudSyncManagerに実装済み |
| Phase2 #9 | ファイル監視 | ICloudFilePresenter + ICloudMetadataMonitor実装済み |
| Phase2 #10 | 保存先切替UI | Storageメニューセクションに実装済み |
