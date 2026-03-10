# Tech Debt

## Critical
1. **git未コミット** - 6ヶ月分のコードが未追跡。データ消失リスク

## High Priority
2. **テスト未実装** - 全テストがXCTFail()テンプレート状態。TDD RED段階で停滞
3. **CloudKitSync スケルトン** - SyncStatus定義のみ。実同期ロジック未実装
4. **TodoManager スケルトン** - モデル定義のみ。ビジネスロジック未実装

## Medium Priority
5. **UI Views** - MainView, TodoItemView, FilePickerView存在するが実装状況要確認
6. **CI/CD未構築** - ビルド・テスト・デプロイの自動化なし
