# iCloud Drive連携 & ファイルピッカー機能 技術設計書

**作成日**: 2026-03-09
**作成者**: dev-leader
**対象**: mdTodo (TodoApp-Final)
**ステータス**: 設計完了・実装待ち

---

## 1. 現状分析

### 1.1 現在のアーキテクチャ

```
TodoApp.swift (812行・単一ファイル構成)
├── SharedDataManager      - App Group経由でウィジェットとJSON共有
├── Models                 - TodoItem, TodoStatistics, WidgetTodoData/Item
├── SimpleTodoManager      - Todo管理（CRUD + md読み書き）
├── SimpleTodoItemView     - 個別Todo行のUI
├── ContentView            - メイン画面（一覧・追加・編集・Obsidian連携）
└── TodoApp                - @main エントリポイント

TodoWidget.swift (401行)
├── Provider               - ウィジェットタイムラインプロバイダ
├── Small/Medium/Large     - ウィジェットビュー
└── TodoWidgetBundle       - @main エントリポイント
```

### 1.2 現在のデータフロー

```
SimpleTodoManager
  ├── loadTodosFromFile()   → Documents/todo.md から読み込み
  ├── saveToFile()          → Documents/todo.md に書き込み
  ├── syncToWidget()        → App Group共有コンテナに JSON保存
  └── parseTodosFromMarkdown() → md解析（- [ ] / - [x] 行を抽出）
```

**重要な特徴**:
- ファイルパスは `FileManager.default.urls(for: .documentDirectory)` + `"todo.md"` でハードコード
- 保存時にヘッダー（タイトル・タイムスタンプ）とセクション見出し（Pending/Completed）を自動生成
- 読み込み時はチェックボックス行のみ抽出（ヘッダー・見出しは無視）
- Info.plistに `UIFileSharingEnabled` / `LSSupportsOpeningDocumentsInPlace` / `CFBundleDocumentTypes` は設定済みだが、コード側の実装はない

### 1.3 Entitlements

- `com.apple.security.application-groups`: `group.com.0hanami.mdtodo.shared` （アプリ・ウィジェット共通）
- iCloud関連のentitlementは未設定

---

## 2. 技術設計

### 2.1 全体方針

**段階的アプローチ**を採用する:
1. まずファイルピッカーで任意のmdファイルを開けるようにする（Phase 1）
2. 次にiCloud Drive連携を追加する（Phase 2）

この順序にする理由:
- ファイルピッカーはiCloud Driveの前提条件（iCloud上のファイルもピッカーで選べる）
- ファイルピッカーの方が実装がシンプルで、早期にテスト可能
- iCloud Drive対応には Xcode上でのCapability設定やプロビジョニング変更が必要

### 2.2 Phase 1: ファイルパス管理の抽象化 + ファイルピッカー

#### 2.2.1 FileLocationManager（新規クラス）

現在ハードコードされているファイルパスを管理するクラスを導入する。

```swift
class FileLocationManager: ObservableObject {
    @Published var currentFileURL: URL?
    @Published var currentFileName: String = "todo.md"

    private let userDefaultsKey = "selectedFileBookmark"

    /// デフォルトのDocuments/todo.md
    var defaultFileURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("todo.md")
    }

    /// セキュリティスコープ付きブックマーク保存・復元
    func saveBookmark(for url: URL) throws { ... }
    func restoreBookmark() -> URL? { ... }

    /// ファイルアクセス開始・終了（セキュリティスコープ管理）
    func startAccessing() -> Bool { ... }
    func stopAccessing() { ... }
}
```

**設計ポイント**:
- iCloud Drive上のファイルは「セキュリティスコープ付きブックマーク」で参照を永続化する必要がある
- `url.startAccessingSecurityScopedResource()` / `stopAccessingSecurityScopedResource()` で囲む
- UserDefaultsにブックマークデータ（Data型）を保存し、アプリ再起動後も同じファイルを開ける

#### 2.2.2 SimpleTodoManager の変更

```swift
class SimpleTodoManager: ObservableObject {
    @Published var todos: [TodoItem] = []
    @Published var statistics: TodoStatistics = TodoStatistics()
    @Published var currentFileURL: URL?           // 追加
    @Published var currentFileName: String = ""    // 追加（ナビバー表示用）

    // 変更: 引数なしの初期化ではブックマーク復元 or デフォルトファイル
    init() {
        restoreLastFile()
    }

    // 追加: 外部ファイルを開く
    func openFile(url: URL) { ... }

    // 変更: saveToFile() を currentFileURL ベースに変更
    private func saveToFile(content: String) { ... }

    // 変更: loadTodosFromFile() を currentFileURL ベースに変更
    private func loadTodosFromFile() { ... }
}
```

**mdファイル保存フォーマットの変更検討**:

現在の保存フォーマットは「ヘッダー + Pending/Completed セクション」に分割しているが、
外部mdファイルを開く場合、このフォーマットを強制すると元のファイルのヘッダーや構造が壊れる。

**方針**:
- **自分で作成したファイル（新規作成・デフォルト）**: 現在のフォーマットを維持
- **外部から開いたファイル**: チェックボックス行のみ更新し、それ以外の行は保持する

これにはパーサーの改修が必要（後述 Task 3）。

#### 2.2.3 DocumentPicker（UIViewControllerRepresentable）

```swift
struct DocumentPicker: UIViewControllerRepresentable {
    let contentTypes: [UTType]  // [.plainText] or カスタムmd type
    let onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentType: contentTypes,
            asCopy: false  // 重要: コピーではなく元ファイルへの参照
        )
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }
}
```

**注意点**:
- `asCopy: false` でないとiCloud上のファイルへの書き戻しができない
- `UIDocumentPickerViewController(forOpeningContentTypes:)` を使用（iOS 14+）
- `UTType.plainText` でmdファイルも選択可能（markdownはplain-textのサブタイプ）

#### 2.2.4 UI変更（ContentView）

ナビゲーションバーのメニューに以下を追加:

```
Menu (ellipsis.circle)
├── 完了済みを削除
├── ── 連携 ──
│   ├── Obsidianで開く
│   ├── ファイルを開く...     ← 新規
│   └── 新規ファイルを作成...  ← 新規（Phase 2で追加も可）
└── ── ファイル情報 ──        ← 新規
    └── 現在: {ファイル名}
```

ナビゲーションタイトルも動的に変更:
- 現在: `"todo.md"` 固定
- 変更後: `currentFileName`（選択されたファイル名）

### 2.3 Phase 2: iCloud Drive連携

#### 2.3.1 Xcode設定（手動作業）

1. **Signing & Capabilities** で「iCloud」を追加
2. 「iCloud Documents」にチェック
3. Containerを設定: `iCloud.com.0hanami.mdtodo`
4. Entitlements に以下が自動追加される:
   ```xml
   <key>com.apple.developer.icloud-container-identifiers</key>
   <array>
       <string>iCloud.com.0hanami.mdtodo</string>
   </array>
   <key>com.apple.developer.icloud-services</key>
   <array>
       <string>CloudDocuments</string>
   </array>
   <key>com.apple.developer.ubiquity-container-identifiers</key>
   <array>
       <string>iCloud.com.0hanami.mdtodo</string>
   </array>
   ```

5. **Apple Developer Portal** でApp IDのiCloud Capabilityを有効化
6. プロビジョニングプロファイルを再生成

#### 2.3.2 iCloud Driveのデフォルト保存先

```swift
extension FileLocationManager {
    /// iCloud Drive上のアプリ専用フォルダ
    var iCloudDocumentsURL: URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents")
    }

    /// iCloud利用可能かチェック
    var isICloudAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }
}
```

**デフォルト保存先の優先順位**:
1. ユーザーが明示的に選択したファイル（ブックマーク保存済み）
2. iCloud Drive利用可能 → `iCloud Drive/mdTodo/todo.md`
3. iCloud Drive利用不可 → ローカル `Documents/todo.md`（現行動作）

#### 2.3.3 ファイル競合の検出

iCloud Driveでは同期競合が発生しうる。`NSMetadataQuery` を使って監視する:

```swift
class ICloudFileMonitor {
    private var metadataQuery: NSMetadataQuery?

    func startMonitoring(fileURL: URL) {
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K == %@",
            NSMetadataItemFSNameKey, fileURL.lastPathComponent)

        // 変更通知を受け取る
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleQueryUpdate),
            name: .NSMetadataQueryDidUpdate, object: query
        )
        query.start()
    }
}
```

#### 2.3.4 設定画面（オプション・Phase 2後半）

```
設定
├── 保存先: [ローカル / iCloud Drive]  トグル
├── iCloud同期状態: 同期済み / 同期中...
└── ファイルパス: /iCloud Drive/mdTodo/todo.md
```

### 2.4 mdパーサーの改修（外部ファイル対応）

現在のパーサーは保存時にファイル全体を再生成している。
外部ファイル（Obsidian等）を開く場合、チェックボックス以外の内容（見出し、本文、リンク等）を保持する必要がある。

#### 方針: 行ベースの差分更新

```swift
/// 外部ファイル更新用: チェックボックス行のみ更新し、他の行は保持
func updateMarkdownFilePreservingStructure(
    originalContent: String,
    updatedTodos: [TodoItem]
) -> String {
    var lines = originalContent.components(separatedBy: "\n")

    for todo in updatedTodos {
        // lineNumberで元の行を特定し、チェック状態のみ更新
        if todo.lineNumber < lines.count {
            let checkbox = todo.isCompleted ? "- [x]" : "- [ ]"
            lines[todo.lineNumber] = "\(checkbox) \(todo.text)"
        }
    }

    return lines.joined(separator: "\n")
}
```

**注意**:
- 行の追加・削除があるとlineNumberがずれる → 保存前に再マッピングが必要
- 新規Todo追加時はファイル末尾（または最後のチェックボックス行の次）に挿入

---

## 3. リスクと注意点

### 3.1 セキュリティスコープの管理
- `startAccessingSecurityScopedResource()` を呼んだら必ず `stopAccessingSecurityScopedResource()` を呼ぶ
- `defer` ブロックで確実に解放するか、アプリのライフサイクルで管理する
- ブックマークが無効化される場合がある（ファイル移動・削除時）→ エラーハンドリング必須

### 3.2 iCloud同期の遅延・競合
- iCloudの同期はリアルタイムではない（数秒〜数分の遅延あり）
- 同じファイルを複数デバイスで同時編集すると競合バージョンが生成される
- **MVP段階**: 競合検出のみ行い、最新版を採用（複雑なマージは行わない）

### 3.3 ウィジェットとの整合性
- 現在のウィジェット連携（App Group + JSON）は変更不要
- ファイル保存先が変わっても、Widget用のJSON同期は引き続きApp Group経由で行う
- iCloud上のファイルをウィジェットから直接読むことはできない（ウィジェットにはiCloud権限がない）

### 3.4 Obsidian連携との両立
- ファイルピッカーでObsidian Vault内のmdファイルを開けるようになる
- Obsidianとの双方向同期は「同じiCloud Drive上のファイルを共有する」形で実現
- ただしObsidianが独自フォーマット（YAML frontmatter等）を使っている場合、パーサーの互換性に注意

### 3.5 App Store審査
- iCloud Capabilityの追加はプロビジョニング変更が必要
- ファイルピッカー単体は審査上のリスクなし
- `UIFileSharingEnabled` は既に設定済みなので問題なし

### 3.6 単一ファイル構成の維持
- 現在TodoApp.swiftは812行。機能追加で1000行超えが見込まれる
- **当面は単一ファイルを維持**し、Phase 2完了後にファイル分割を検討
- `// MARK:` セクションで明確に区切ることで可読性を維持

---

## 4. タスク分解

### Phase 1: ファイルピッカー対応（合計: 約4-6時間）

| # | タスク | 内容 | 工数 | 依存 |
|---|--------|------|------|------|
| 1 | FileLocationManager導入 | ファイルパス管理クラス作成、ブックマーク保存/復元、セキュリティスコープ管理 | 1.5h | - |
| 2 | SimpleTodoManager改修 | saveToFile/loadTodosFromFileをURL引数ベースに変更、openFile()追加、currentFileURL/Name管理 | 1.5h | #1 |
| 3 | mdパーサー改修 | 外部ファイル読み込み時の行保持ロジック、lineNumber再マッピング、新規Todo挿入位置の決定 | 1h | #2 |
| 4 | DocumentPicker実装 | UIViewControllerRepresentable、UTType設定、コールバック処理 | 0.5h | - |
| 5 | UI統合 | メニューに「ファイルを開く」追加、ナビタイトル動的化、ファイル名表示 | 0.5h | #2, #4 |
| 6 | テスト・デバッグ | ローカルmdファイル開閉、再起動後のブックマーク復元、エッジケース確認 | 1h | #1-5 |

### Phase 2: iCloud Drive連携（合計: 約3-5時間）

| # | タスク | 内容 | 工数 | 依存 |
|---|--------|------|------|------|
| 7 | Xcode設定 | iCloud Capability追加、Container設定、Entitlements更新、プロビジョニング再生成 | 0.5h | - |
| 8 | iCloud保存先実装 | ubiquityContainerURL取得、デフォルト保存先切替ロジック、フォルダ自動作成 | 1h | #7, #1 |
| 9 | ファイル監視 | NSMetadataQuery導入、ファイル変更検出、自動リロード | 1.5h | #8 |
| 10 | 保存先切替UI | 設定メニューまたは初回起動時の選択UI、iCloud可否判定、状態表示 | 1h | #8 |
| 11 | 統合テスト | 複数デバイス同期テスト、オフライン動作確認、Obsidian Vaultとの相互運用テスト | 1h | #7-10 |

### 実装順序

```
Phase 1:
  #1 FileLocationManager → #2 Manager改修 → #3 パーサー改修
  #4 DocumentPicker（#1と並行可能）
  → #5 UI統合 → #6 テスト

Phase 2:
  #7 Xcode設定 → #8 iCloud保存先 → #9 ファイル監視
  → #10 UI → #11 統合テスト
```

---

## 5. 変更対象ファイル一覧

| ファイル | 変更内容 |
|----------|----------|
| `TodoApp/TodoApp.swift` | FileLocationManager追加、SimpleTodoManager改修、DocumentPicker追加、ContentView改修 |
| `TodoApp/TodoApp.entitlements` | iCloud関連entitlement追加（Phase 2） |
| `TodoApp.xcodeproj/project.pbxproj` | iCloud Capability追加（Phase 2、Xcode GUIで操作） |
| `TodoWidget/TodoWidget.swift` | 変更なし（Widget連携はApp Group JSON経由のまま） |
| `TodoApp/Info.plist` | 変更なし（必要な設定は既にある） |

---

## 6. MVP定義

### MVP（最小実装）: Phase 1 の #1-#5
- ファイルピッカーで既存mdファイルを開ける
- 開いたファイルのTodo行を表示・操作できる
- チェック状態の変更がファイルに保存される
- アプリ再起動後も最後に開いたファイルを覚えている

### 次のマイルストーン: Phase 2 の #7-#8
- iCloud Driveにデフォルト保存
- 基本的なデバイス間同期

### フル実装: Phase 2 の #9-#11
- リアルタイムファイル監視
- 同期状態の可視化
