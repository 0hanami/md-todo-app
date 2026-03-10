# Decisions Log

## 2026-03-08: アプリ名を「mdTodo」に変更
- 旧名「iCloud Markdown Todo」はApple商標「iCloud」を含み、App Review Guideline 5.2.5で却下された
- 新名称: mdTodo
- フォルダ名・コード内の呼称も統一して変更

## 2026-03-05: App Store v1.0.0 却下
- Guideline 5.2.5: アプリ名にiCloudを含む（商標問題）
- Guideline 1.5: サポートURLがGitHubプロフィールで不適切
- 対応: アプリ名変更 + サポートページ作成で再申請予定

## 2026-03: Phase 2完了・Phase 3開始
- 47タスクの定義完了
- Library-Firstアーキテクチャ（3 Swift Packages + iOS App）
- TDD方針: RED-GREEN-Refactor
- Spec-Driven Developmentワークフロー採用

## 2026: 技術スタック決定
- Swift 5.9+ / SwiftUI / CloudKit / MVVM + Combine
- 外部依存なし（純粋Appleフレームワークのみ）
- Obsidian互換性を重視
