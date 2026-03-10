# watchOS 音声入力アプリ 技術設計書

**作成日**: 2026-03-09
**ステータス**: 設計完了・実装待ち
**対象**: mdTodo watchOSコンパニオンアプリ

---

## 1. 概要

Apple Watch上で音声入力によりタスクを素早く追加する最小構成アプリ。
iCloud Drive上の `todo.md` に直接 `- [ ] テキスト` 形式で追記する。
iPhone側アプリとの連携は WatchConnectivity や App Group を使わず、iCloud Drive を唯一の同期ポイントとする。

## 2. アーキテクチャ

```
┌─────────────────────────────┐
│   Apple Watch (watchOS 10+) │
│                             │
│  Complication ──tap──► App  │
│                     │       │
│              VoiceInputView │
│                     │       │
│         ICloudTodoWriter    │
│              │              │
└──────────────│──────────────┘
               │ FileManager.url(forUbiquityContainerIdentifier:)
               ▼
┌─────────────────────────────┐
│   iCloud Drive              │
│   iCloud.com.0hanami.mdtodo │
│   └── Documents/todo.md    │
└─────────────────────────────┘
               ▲
               │ 同じiCloud Container
┌──────────────│──────────────┐
│   iPhone (iOS 17+)          │
│   TodoApp                   │
│   iCloudに切替済みなら同一  │
│   ファイルを読み書き        │
└─────────────────────────────┘
```

### 設計方針
- **単一ファイルアーキテクチャ**: Watch側もiOS側と同様、1つのSwiftファイルで完結させる
- **iCloud直接アクセス**: `FileManager.url(forUbiquityContainerIdentifier:)` でiCloud Containerに直接アクセス
- **WatchConnectivity不使用**: iCloud Driveが同期レイヤーのため不要
- **App Group不使用**: Watch↔iPhone間でローカルデータ共有は行わない

## 3. ターゲット構成

### 新規追加ターゲット

| ターゲット名 | 種別 | Bundle ID | 備考 |
|-------------|------|-----------|------|
| TodoWatch | watchOS App | `com.0hanami.mdtodo.watchkitapp` | watchOS 10+ |

**注意**: Xcode 15以降では WatchKit App は単一ターゲットで構成される（WatchKit Extension は不要）。

### Xcode プロジェクト設定（GUI操作）

1. **File → New → Target → watchOS → App**
2. Bundle Identifier: `com.0hanami.mdtodo.watchkitapp`
3. Interface: SwiftUI
4. Language: Swift
5. Deployment Target: watchOS 10.0
6. 「Include Complication」にチェック

### Entitlements (TodoWatch.entitlements)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
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
</dict>
</plist>
```

### Apple Developer Portal 設定

1. 新規 App ID `com.0hanami.mdtodo.watchkitapp` を登録
2. iCloud capability を有効化（CloudKit ではなく iCloud Documents）
3. iCloud Container `iCloud.com.0hanami.mdtodo` を紐付け（既存のものを共有）
4. Provisioning Profile を作成

## 4. ファイル構成

```
TodoWatch/
├── TodoWatchApp.swift          # @main、アプリエントリポイント
├── VoiceInputView.swift        # 音声入力UI + テキスト入力
├── ICloudTodoWriter.swift      # iCloud Drive書き込みロジック
├── Assets.xcassets/            # Complication用アイコン含む
│   ├── AppIcon.appiconset/
│   └── Complication/           # Complication画像アセット
├── TodoWatch.entitlements
└── Info.plist
```

## 5. 各コンポーネント詳細設計

### 5.1 TodoWatchApp.swift

```swift
// エントリポイント
// NavigationStack不要（画面1つのみ）
// アプリ起動 → 即VoiceInputViewを表示

@main
struct TodoWatchApp: App {
    var body: some Scene {
        WindowGroup {
            VoiceInputView()
        }
    }
}
```

### 5.2 VoiceInputView.swift

**画面構成**:
- アプリアイコンまたはチェックマーク（上部、小さく）
- 「タスクを追加」ラベル
- テキスト入力フィールド（タップで音声入力 or キーボード）
- 追加ボタン
- 成功時: チェックマークアニメーション + ハプティクス → 自動リセット

**音声入力API**:

watchOS 10では `TextField` に `.textInputAutocapitalization` 修飾子を付けると、タップ時に自動的にwatchOS標準の入力UI（音声入力、手書き、絵文字）が表示される。専用の音声認識APIは不要。

```swift
struct VoiceInputView: View {
    @State private var inputText = ""
    @State private var showSuccess = false
    @State private var isProcessing = false
    private let writer = ICloudTodoWriter()

    var body: some View {
        VStack(spacing: 12) {
            // アイコン
            Image(systemName: "checklist")
                .font(.title3)
                .foregroundColor(.blue)

            // テキスト入力（タップでwatchOS標準入力UI起動）
            TextField("タスクを入力", text: $inputText)
                .textInputAutocapitalization(.sentences)

            // 追加ボタン
            Button(action: addTodo) {
                Label("追加", systemImage: "plus.circle.fill")
            }
            .disabled(inputText.isEmpty || isProcessing)
            .tint(.green)
        }
        .overlay {
            if showSuccess {
                // 成功フィードバック表示
                SuccessFeedbackView()
            }
        }
    }

    private func addTodo() {
        // 1. ボタン無効化
        // 2. ICloudTodoWriter.appendTodo()
        // 3. 成功 → ハプティクス + チェック表示 → 1.5秒後リセット
        // 4. 失敗 → エラーハプティクス + メッセージ
    }
}
```

**ハプティクスフィードバック**:
```swift
// 成功時
WKInterfaceDevice.current().play(.success)
// 失敗時
WKInterfaceDevice.current().play(.failure)
```

### 5.3 ICloudTodoWriter.swift

iCloud Drive上の `todo.md` にタスクを追記する責務を持つ。

```swift
class ICloudTodoWriter {
    private let containerIdentifier = "iCloud.com.0hanami.mdtodo"

    /// iCloud Documents ディレクトリのURL
    var iCloudDocumentsURL: URL? {
        FileManager.default.url(
            forUbiquityContainerIdentifier: containerIdentifier
        )?.appendingPathComponent("Documents")
    }

    /// todo.md のURL
    var todoFileURL: URL? {
        iCloudDocumentsURL?.appendingPathComponent("todo.md")
    }

    /// iCloudが利用可能かチェック
    var isAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    /// タスクを追記
    /// - ファイルが存在しない場合は新規作成
    /// - 既存ファイルの末尾に `\n- [ ] テキスト` を追記
    /// - NSFileCoordinator を使用してiCloud同期との競合を防ぐ
    func appendTodo(_ text: String) async throws {
        guard let fileURL = todoFileURL else {
            throw TodoWriteError.iCloudNotAvailable
        }

        // Documentsディレクトリがなければ作成
        if let docsURL = iCloudDocumentsURL,
           !FileManager.default.fileExists(atPath: docsURL.path) {
            try FileManager.default.createDirectory(
                at: docsURL,
                withIntermediateDirectories: true
            )
        }

        let newLine = "- [ ] \(text)\n"

        // NSFileCoordinatorで安全に書き込み
        let coordinator = NSFileCoordinator()
        var coordinatorError: NSError?

        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            coordinator.coordinate(
                writingItemAt: fileURL,
                options: .forMerging,
                error: &coordinatorError
            ) { url in
                do {
                    if FileManager.default.fileExists(atPath: url.path) {
                        let handle = try FileHandle(forWritingTo: url)
                        handle.seekToEndOfFile()
                        if let data = newLine.data(using: .utf8) {
                            handle.write(data)
                        }
                        handle.closeFile()
                    } else {
                        try newLine.write(to: url, atomically: true, encoding: .utf8)
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            if let error = coordinatorError {
                continuation.resume(throwing: error)
            }
        }
    }
}

enum TodoWriteError: LocalizedError {
    case iCloudNotAvailable
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .iCloudNotAvailable:
            return "iCloud Driveが利用できません"
        case .writeFailed(let reason):
            return "書き込み失敗: \(reason)"
        }
    }
}
```

**重要: NSFileCoordinator の使用理由**

iCloud Drive上のファイルは複数デバイスから同時にアクセスされる可能性がある。`NSFileCoordinator` を使うことで:
- iCloudデーモンとの書き込み競合を防ぐ
- `.forMerging` オプションにより既存内容を保持して追記可能
- iOS側が同時編集中でも安全

### 5.4 Complication

**採用するComplication種別**: `CLKComplicationFamily` ではなく、WidgetKit ベースの Complication（watchOS 10以降推奨）

#### WidgetKit Complication 構成

watchOS 10以降では、ComplicationはWidgetKitで実装する。ただし今回のComplicationは「アプリを開くだけ」のシンプルなもので、データ表示は不要。

```swift
// TodoWatch内に追加（別ファイルまたはTodoWatchApp.swift内）

import WidgetKit

struct TodoWatchComplication: Widget {
    let kind = "TodoWatchComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: SimpleProvider()
        ) { entry in
            // タップでアプリが開く
            Image(systemName: "plus.circle.fill")
                .foregroundColor(.green)
                .widgetURL(URL(string: "mdtodo://add"))
        }
        .configurationDisplayName("タスク追加")
        .description("タップしてタスクを音声入力")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryCorner,
            .accessoryInline
        ])
    }
}

struct SimpleProvider: TimelineProvider {
    struct SimpleEntry: TimelineEntry {
        let date: Date
    }

    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        completion(SimpleEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        let entry = SimpleEntry(date: Date())
        // 更新不要（静的表示のみ）
        let timeline = Timeline(entries: [entry], policy: .never)
        completion(timeline)
    }
}
```

**Complication種別の選定理由**:

| Family | 用途 | 採用 |
|--------|------|------|
| `accessoryCircular` | 丸型、文字盤の角に配置 | 採用（メイン） |
| `accessoryCorner` | 角、一部の文字盤で使用 | 採用 |
| `accessoryInline` | テキスト1行、文字盤上部 | 採用（「タスク追加」テキスト） |
| `accessoryRectangular` | 長方形 | 不採用（表示するデータがない） |

### 5.5 WidgetBundle 統合

watchOSアプリ内で `@main` が `App` と `WidgetBundle` で競合しないよう、以下の構成とする:

- `TodoWatchApp.swift` に `@main` を置く（App プロトコル）
- Complication用の Widget は別ターゲット（Widget Extension）として追加する

**修正**: watchOS の Complication は Widget Extension として別ターゲットが必要。

```
TodoWatch/                    # watchOS App ターゲット
├── TodoWatchApp.swift
├── VoiceInputView.swift
├── ICloudTodoWriter.swift
├── Assets.xcassets/
├── TodoWatch.entitlements
└── Info.plist

TodoWatchComplication/        # watchOS Widget Extension ターゲット
├── TodoWatchComplication.swift  # @main WidgetBundle
├── Assets.xcassets/
│   └── Complication/
└── Info.plist
```

**追加ターゲット（修正版）**:

| ターゲット名 | 種別 | Bundle ID |
|-------------|------|-----------|
| TodoWatch | watchOS App | `com.0hanami.mdtodo.watchkitapp` |
| TodoWatchComplication | Widget Extension (watchOS) | `com.0hanami.mdtodo.watchkitapp.complication` |

## 6. ハンドジェスチャ対応

watchOS標準の **Assistive Touch**（設定 → アクセシビリティ → AssistiveTouch）で対応。

- ダブルピンチ → 文字盤のComplicationを選択 → アプリ起動
- アプリ内操作も標準のAssistiveTouchジェスチャで操作可能
- 追加のコード実装は不要

## 7. エラーハンドリング

| 状況 | 対応 |
|------|------|
| iCloud未ログイン | 「iCloudにサインインしてください」メッセージ表示 |
| iCloud容量不足 | 書き込みエラーをキャッチしてメッセージ表示 |
| ネットワーク未接続 | iCloud Driveはオフライン書き込み可能なため問題なし（後で同期） |
| todo.md未作成 | 新規作成して書き込み |
| 同時書き込み競合 | NSFileCoordinatorが調停 |

## 8. テスト方針

1. **シミュレータテスト**: Xcode watchOS Simulator で UI表示・遷移を確認
2. **iCloud書き込みテスト**: 実機（Apple Watch + iPhone ペアリング）でiCloudサインイン状態で書き込み確認
3. **同期テスト**: Watch で追加 → iPhone側アプリで表示されることを確認
4. **オフラインテスト**: 機内モード → 追加 → オンライン復帰後に同期確認
5. **Complicationテスト**: 文字盤にComplication配置 → タップでアプリ起動確認

---

## 9. タスク分解（実装順序）

### Phase 1: プロジェクト基盤（所要: 30分）
- [ ] **T1-1**: Xcode で watchOS App ターゲット `TodoWatch` を追加
  - File → New → Target → watchOS → App
  - Bundle ID: `com.0hanami.mdtodo.watchkitapp`
  - Deployment Target: watchOS 10.0
- [ ] **T1-2**: Apple Developer Portal で App ID 登録 + iCloud capability 設定
  - iCloud Container `iCloud.com.0hanami.mdtodo` を紐付け
- [ ] **T1-3**: TodoWatch.entitlements を作成（iCloud Documents 有効化）
- [ ] **T1-4**: Provisioning Profile 作成・ダウンロード・適用
- [ ] **T1-5**: ビルド確認（空のwatchOSアプリがシミュレータで起動すること）

### Phase 2: iCloud書き込みロジック（所要: 1時間）
- [ ] **T2-1**: `ICloudTodoWriter.swift` を作成
  - iCloud Container アクセス
  - iCloud利用可能チェック
  - todo.mdへの追記ロジック
  - NSFileCoordinator による安全な書き込み
- [ ] **T2-2**: `TodoWriteError` エラー型を定義
- [ ] **T2-3**: 単体テスト（任意: iCloudアクセスは実機のみ）

### Phase 3: 音声入力UI（所要: 1時間）
- [ ] **T3-1**: `VoiceInputView.swift` を作成
  - TextField（タップでwatchOS標準入力UI表示）
  - 追加ボタン
  - 処理中インジケータ
- [ ] **T3-2**: 成功フィードバック実装
  - `WKInterfaceDevice.current().play(.success)` ハプティクス
  - チェックマークアニメーション表示
  - 1.5秒後に自動リセット（次の入力を受付可能に）
- [ ] **T3-3**: エラーフィードバック実装
  - `WKInterfaceDevice.current().play(.failure)` ハプティクス
  - エラーメッセージ表示
- [ ] **T3-4**: iCloud未利用時の案内表示

### Phase 4: アプリエントリポイント（所要: 15分）
- [ ] **T4-1**: `TodoWatchApp.swift` を作成（@main、VoiceInputView表示）
- [ ] **T4-2**: シミュレータでの動作確認

### Phase 5: Complication（所要: 1時間）
- [ ] **T5-1**: Widget Extension ターゲット `TodoWatchComplication` を追加
  - File → New → Target → watchOS → Widget Extension
  - Bundle ID: `com.0hanami.mdtodo.watchkitapp.complication`
- [ ] **T5-2**: `TodoWatchComplication.swift` を実装
  - StaticConfiguration + SimpleProvider
  - accessoryCircular / accessoryCorner / accessoryInline 対応
- [ ] **T5-3**: Complication用アセット作成（Assets.xcassets内）
- [ ] **T5-4**: `widgetURL` でアプリ起動を設定
- [ ] **T5-5**: 文字盤プレビューで表示確認

### Phase 6: 結合テスト・仕上げ（所要: 1時間）
- [ ] **T6-1**: 実機ペアリング + watchOSアプリインストール
- [ ] **T6-2**: 音声入力 → iCloud Drive書き込み → iPhone側で確認
- [ ] **T6-3**: Complicationタップ → アプリ起動 → 入力フロー確認
- [ ] **T6-4**: オフライン時の動作確認
- [ ] **T6-5**: AssistiveTouch（ダブルピンチ）での操作確認
- [ ] **T6-6**: アプリアイコン設定

**合計見積もり: 約4.5時間**

---

## 10. 依存関係・リスク

| リスク | 影響度 | 対策 |
|--------|--------|------|
| watchOS で iCloud Documents へのアクセスが制限される可能性 | 高 | 実機で早期検証（Phase 2完了時点）。不可の場合は WatchConnectivity 経由に切替 |
| NSFileCoordinator が watchOS で期待通り動作しない可能性 | 中 | 代替: 直接FileHandle操作（同期競合リスクは許容） |
| Complication更新が反映されない | 低 | 静的表示のみのため影響小 |
| Apple Developer Portal でのiCloud Container共有設定 | 中 | 親App IDとwatchOS App IDで同一Containerを使用可能か事前確認 |

## 11. 将来の拡張可能性（スコープ外）

- Watch側でのタスク一覧表示
- タスク完了操作
- カテゴリ選択
- 定型タスクのクイック追加
- Digital Crown による操作
