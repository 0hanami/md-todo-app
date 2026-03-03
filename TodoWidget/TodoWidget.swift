//
//  TodoWidget.swift
//  TodoWidget
//
//  iOSウィジェット拡張機能
//

import WidgetKit
import SwiftUI

// MARK: - Widget Entry

struct TodoEntry: TimelineEntry {
    let date: Date
    let todos: [WidgetTodoItem]
    let pendingCount: Int
    let completedCount: Int
}

struct WidgetTodoItem: Codable, Identifiable {
    let id: String
    let text: String
    let isCompleted: Bool
}

struct WidgetTodoData: Codable {
    let todos: [WidgetTodoItem]
    let lastUpdated: Date
}

// MARK: - Widget Provider

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> TodoEntry {
        TodoEntry(
            date: Date(),
            todos: [
                WidgetTodoItem(id: "1", text: "サンプルタスク", isCompleted: false),
                WidgetTodoItem(id: "2", text: "完了したタスク", isCompleted: true)
            ],
            pendingCount: 3,
            completedCount: 2
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (TodoEntry) -> ()) {
        let entry = TodoEntry(
            date: Date(),
            todos: getSampleTodos(),
            pendingCount: 3,
            completedCount: 2
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        var entries: [TodoEntry] = []
        
        // 現在のTodoデータを取得
        let currentDate = Date()
        let todos = loadTodosFromSharedContainer()
        
        let entry = TodoEntry(
            date: currentDate,
            todos: todos,
            pendingCount: todos.filter { !$0.isCompleted }.count,
            completedCount: todos.filter { $0.isCompleted }.count
        )
        entries.append(entry)
        
        // 15分後に更新
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: currentDate)!
        let timeline = Timeline(entries: entries, policy: .after(nextUpdate))
        
        completion(timeline)
    }
    
    private func getSampleTodos() -> [WidgetTodoItem] {
        return [
            WidgetTodoItem(id: "1", text: "朝のランニング", isCompleted: false),
            WidgetTodoItem(id: "2", text: "メールチェック", isCompleted: false),
            WidgetTodoItem(id: "3", text: "会議の準備", isCompleted: true)
        ]
    }
    
    private func loadTodosFromSharedContainer() -> [WidgetTodoItem] {
        let appGroupIdentifier = "group.com.0hanami.mdtodo.shared"
        
        guard let sharedContainerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            #if DEBUG
            print("⚠️ App Groupの共有コンテナにアクセスできませんでした")
            #endif
            return getSampleTodos()
        }

        let dataURL = sharedContainerURL.appendingPathComponent("shared_todo_data.json")

        do {
            let data = try Data(contentsOf: dataURL)
            let widgetTodoData = try JSONDecoder().decode(WidgetTodoData.self, from: data)
            #if DEBUG
            print("✅ Widget用データを正常に読み込みました: \(widgetTodoData.todos.count)件")
            #endif
            return widgetTodoData.todos
        } catch {
            #if DEBUG
            print("⚠️ Widget用データの読み込みに失敗しました: \(error)")
            #endif
            return getSampleTodos()
        }
    }
}

// MARK: - Small Widget View

struct SmallWidgetView: View {
    let entry: TodoEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // ヘッダー
            HStack {
                Image(systemName: "checklist")
                    .font(.system(size: 14))
                    .foregroundColor(.blue)
                
                Text("Todo")
                    .font(.system(size: 14, weight: .semibold))
                
                Spacer()
            }
            
            // 未完了数
            HStack {
                Text("\(entry.pendingCount)")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.orange)
                
                VStack(alignment: .leading) {
                    Text("未完了")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("タスク")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            Divider()
            
            // 直近のTodo（最大2件）
            VStack(alignment: .leading, spacing: 4) {
                ForEach(entry.todos.filter { !$0.isCompleted }.prefix(2), id: \.id) { todo in
                    HStack(spacing: 4) {
                        Image(systemName: "circle")
                            .font(.system(size: 8))
                            .foregroundColor(.gray)
                        
                        Text(todo.text)
                            .font(.caption2)
                            .lineLimit(1)
                            .foregroundColor(.primary)
                    }
                }
            }
            
            Spacer(minLength: 0)
        }
        .padding()
        .background(Color(.systemGray6))
    }
}

// MARK: - Medium Widget View

struct MediumWidgetView: View {
    let entry: TodoEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // ヘッダー
            HStack {
                Image(systemName: "checklist")
                    .font(.system(size: 16))
                    .foregroundColor(.blue)
                
                Text("Todo List")
                    .font(.system(size: 16, weight: .semibold))
                
                Spacer()
                
                Text("\(entry.pendingCount) 未完了")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
            
            Divider()
            
            // Todo一覧（最大4件）
            VStack(alignment: .leading, spacing: 6) {
                ForEach(entry.todos.filter { !$0.isCompleted }.prefix(4), id: \.id) { todo in
                    HStack(spacing: 8) {
                        Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 14))
                            .foregroundColor(todo.isCompleted ? .green : .gray)
                        
                        Text(todo.text)
                            .font(.system(size: 13))
                            .lineLimit(1)
                            .foregroundColor(todo.isCompleted ? .secondary : .primary)
                            .strikethrough(todo.isCompleted)
                        
                        Spacer()
                    }
                }
                
                if entry.todos.filter({ !$0.isCompleted }).count > 4 {
                    Text("他 \(entry.todos.filter { !$0.isCompleted }.count - 4) 件...")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer(minLength: 0)
        }
        .padding()
        .background(Color(.systemGray6))
    }
}

// MARK: - Large Widget View

struct LargeWidgetView: View {
    let entry: TodoEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // ヘッダー
            HStack {
                Image(systemName: "checklist")
                    .font(.system(size: 18))
                    .foregroundColor(.blue)
                
                Text("Todo List")
                    .font(.system(size: 18, weight: .semibold))
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text("\(entry.pendingCount) 未完了")
                        .font(.caption)
                        .foregroundColor(.orange)
                    
                    Text("\(entry.completedCount) 完了")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
            
            Divider()
            
            // Todo一覧（最大8件）
            VStack(alignment: .leading, spacing: 8) {
                ForEach(entry.todos.prefix(8), id: \.id) { todo in
                    HStack(spacing: 10) {
                        Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 16))
                            .foregroundColor(todo.isCompleted ? .green : .gray)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(todo.text)
                                .font(.system(size: 14))
                                .lineLimit(2)
                                .foregroundColor(todo.isCompleted ? .secondary : .primary)
                                .strikethrough(todo.isCompleted)
                        }
                        
                        Spacer()
                    }
                    
                    if todo.id != entry.todos.prefix(8).last?.id {
                        Divider()
                    }
                }
                
                if entry.todos.count > 8 {
                    HStack {
                        Spacer()
                        Text("他 \(entry.todos.count - 8) 件のタスク")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
            }
            
            Spacer(minLength: 0)
        }
        .padding()
        .background(Color(.systemGray6))
    }
}

// MARK: - Widget Entry View

struct TodoWidgetEntryView : View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(entry: entry)
        case .systemMedium:
            MediumWidgetView(entry: entry)
        case .systemLarge:
            LargeWidgetView(entry: entry)
        default:
            SmallWidgetView(entry: entry)
        }
    }
}

// MARK: - Widget Configuration

struct TodoWidget: Widget {
    let kind: String = "TodoWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            TodoWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Todo Widget")
        .description("Todoリストを素早く確認")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Widget Bundle

@main
struct TodoWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodoWidget()
    }
}

// MARK: - Preview

struct TodoWidget_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            TodoWidgetEntryView(entry: TodoEntry(
                date: Date(),
                todos: [
                    WidgetTodoItem(id: "1", text: "朝のランニング", isCompleted: false),
                    WidgetTodoItem(id: "2", text: "メールチェック", isCompleted: false),
                    WidgetTodoItem(id: "3", text: "会議の準備", isCompleted: true)
                ],
                pendingCount: 2,
                completedCount: 1
            ))
            .previewContext(WidgetPreviewContext(family: .systemSmall))
            .previewDisplayName("Small")
            
            TodoWidgetEntryView(entry: TodoEntry(
                date: Date(),
                todos: [
                    WidgetTodoItem(id: "1", text: "朝のランニング", isCompleted: false),
                    WidgetTodoItem(id: "2", text: "メールチェック", isCompleted: false),
                    WidgetTodoItem(id: "3", text: "会議の準備", isCompleted: true),
                    WidgetTodoItem(id: "4", text: "レポート作成", isCompleted: false)
                ],
                pendingCount: 3,
                completedCount: 1
            ))
            .previewContext(WidgetPreviewContext(family: .systemMedium))
            .previewDisplayName("Medium")
            
            TodoWidgetEntryView(entry: TodoEntry(
                date: Date(),
                todos: [
                    WidgetTodoItem(id: "1", text: "朝のランニング", isCompleted: false),
                    WidgetTodoItem(id: "2", text: "メールチェック", isCompleted: false),
                    WidgetTodoItem(id: "3", text: "会議の準備", isCompleted: true),
                    WidgetTodoItem(id: "4", text: "レポート作成", isCompleted: false),
                    WidgetTodoItem(id: "5", text: "買い物リスト作成", isCompleted: false),
                    WidgetTodoItem(id: "6", text: "ジムに行く", isCompleted: false),
                    WidgetTodoItem(id: "7", text: "本を読む", isCompleted: true),
                    WidgetTodoItem(id: "8", text: "明日の準備", isCompleted: false)
                ],
                pendingCount: 6,
                completedCount: 2
            ))
            .previewContext(WidgetPreviewContext(family: .systemLarge))
            .previewDisplayName("Large")
        }
    }
}