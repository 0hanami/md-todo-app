//
//  TodoApp.swift
//  TodoApp
//
//  iCloud Markdown Todo App - 完全単一ファイル版
//  UI改善版: タイトル変更、フォントサイズ縮小、フローティングボタン、インライン編集、幅調整
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Shared Data Manager

class SharedDataManager {
    static let shared = SharedDataManager()
    private let appGroupIdentifier = "group.com.0hanami.mdtodo.shared"
    
    private var sharedContainerURL: URL? {
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }
    
    private var sharedTodoDataURL: URL? {
        guard let containerURL = sharedContainerURL else { return nil }
        return containerURL.appendingPathComponent("shared_todo_data.json")
    }
    
    func saveWidgetData(todos: [TodoItem]) {
        guard let url = sharedTodoDataURL else { return }
        
        let widgetData = WidgetTodoData(
            todos: todos.map { WidgetTodoItem(id: $0.id, text: $0.text, isCompleted: $0.isCompleted) },
            lastUpdated: Date()
        )
        
        do {
            let data = try JSONEncoder().encode(widgetData)
            try data.write(to: url)
        } catch {
            #if DEBUG
            print("Failed to save widget data: \(error)")
            #endif
        }
    }
    
    func loadWidgetData() -> WidgetTodoData? {
        guard let url = sharedTodoDataURL else { return nil }
        
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(WidgetTodoData.self, from: data)
        } catch {
            #if DEBUG
            print("Failed to load widget data: \(error)")
            #endif
            return nil
        }
    }
}

struct WidgetTodoData: Codable {
    let todos: [WidgetTodoItem]
    let lastUpdated: Date
}

struct WidgetTodoItem: Codable, Identifiable {
    let id: String
    let text: String
    let isCompleted: Bool
}

// MARK: - Models

/// 単一のTodoアイテムを表現する構造体
struct TodoItem: Identifiable, Hashable {
    let id: String
    let text: String
    let isCompleted: Bool
    let lineNumber: Int
    let originalLine: String
    
    init(id: String, text: String, isCompleted: Bool, lineNumber: Int, originalLine: String) {
        self.id = id
        self.text = text
        self.isCompleted = isCompleted
        self.lineNumber = lineNumber
        self.originalLine = originalLine
    }
    
    func toggled() -> TodoItem {
        return TodoItem(
            id: id,
            text: text,
            isCompleted: !isCompleted,
            lineNumber: lineNumber,
            originalLine: originalLine
        )
    }
}

/// Todo統計情報を管理する構造体
struct TodoStatistics {
    let total: Int
    let completed: Int
    let pending: Int
    let completionPercentage: Double
    
    init(total: Int = 0, completed: Int = 0, pending: Int = 0, completionPercentage: Double = 0.0) {
        self.total = total
        self.completed = completed
        self.pending = pending
        self.completionPercentage = completionPercentage
    }
    
    /// 完了率の表示用文字列
    var completionPercentageString: String {
        return String(format: "%.1f%%", completionPercentage)
    }
}

// MARK: - Todo Manager

/// Todoの管理を行うObservableObjectクラス
class SimpleTodoManager: ObservableObject {
    @Published var todos: [TodoItem] = []
    @Published var statistics: TodoStatistics = TodoStatistics()
    
    init() {
        loadTodosFromFile()
    }
    
    // MARK: - Public Methods
    
    /// Todoの完了状態を切り替える
    func toggleTodo(id todoId: String) {
        guard let index = todos.firstIndex(where: { $0.id == todoId }) else {
            return
        }
        
        todos[index] = todos[index].toggled()
        updateStatistics()
        syncToMarkdownFile()
        syncToWidget()
    }
    
    /// 新しいTodoを追加する
    func addTodo(text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        
        let newTodo = TodoItem(
            id: UUID().uuidString,
            text: trimmedText,
            isCompleted: false,
            lineNumber: todos.count + 1,
            originalLine: "- [ ] \(trimmedText)"
        )
        
        todos.append(newTodo)
        updateStatistics()
        syncToMarkdownFile()
        syncToWidget()
    }
    
    /// 完了済みTodoを削除する
    func removeCompletedTodos() {
        todos.removeAll { $0.isCompleted }
        updateStatistics()
    }
    
    /// 指定されたTodoを削除する
    func removeTodo(id todoId: String) {
        todos.removeAll { $0.id == todoId }
        updateStatistics()
        syncToMarkdownFile()
        syncToWidget()
    }
    
    /// Todoの順序を変更する
    func moveTodos(from source: IndexSet, to destination: Int) {
        todos.move(fromOffsets: source, toOffset: destination)
        // 行番号を更新
        for (index, todo) in todos.enumerated() {
            todos[index] = TodoItem(
                id: todo.id,
                text: todo.text,
                isCompleted: todo.isCompleted,
                lineNumber: index + 1,
                originalLine: todo.originalLine
            )
        }
        updateStatistics()
        syncToMarkdownFile()
        syncToWidget()
    }
    
    /// Markdownファイルとの同期
    public func syncToMarkdownFile() {
        #if DEBUG
        print("📝 Markdownファイルに同期中...")
        #endif

        // Markdownコンテンツを生成
        var markdownContent = "# Todo List\n\n"
        markdownContent += "Generated by TodoApp at \(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short))\n\n"
        
        // 未完了Todoを追加
        let pendingTodos = todos.filter { !$0.isCompleted }
        if !pendingTodos.isEmpty {
            markdownContent += "## Pending Tasks\n\n"
            for todo in pendingTodos {
                markdownContent += "- [ ] \(todo.text)\n"
            }
            markdownContent += "\n"
        }
        
        // 完了済みTodoを追加
        let completedTodos = todos.filter { $0.isCompleted }
        if !completedTodos.isEmpty {
            markdownContent += "## Completed Tasks\n\n"
            for todo in completedTodos {
                markdownContent += "- [x] \(todo.text)\n"
            }
            markdownContent += "\n"
        }
        
        // ファイルに保存
        saveToFile(content: markdownContent)
        
        #if DEBUG
        print("✅ 同期完了")
        #endif
    }

    /// ファイル保存処理
    private func saveToFile(content: String) {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            #if DEBUG
            print("⚠️ Documents ディレクトリにアクセスできませんでした")
            #endif
            return
        }

        let fileURL = documentsDirectory.appendingPathComponent("todo.md")

        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            #if DEBUG
            print("📁 Markdownファイルを保存しました: \(fileURL.path)")
            #endif
        } catch {
            #if DEBUG
            print("❌ ファイル保存に失敗しました: \(error)")
            #endif
        }
    }
    
    /// Widget用データの同期
    private func syncToWidget() {
        SharedDataManager.shared.saveWidgetData(todos: todos)
        #if DEBUG
        print("🎯 Widgetにデータを同期しました")
        #endif
    }
    
    /// Markdownファイルからの読み込み
    private func loadTodosFromFile() {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            #if DEBUG
            print("⚠️ Documents ディレクトリにアクセスできませんでした")
            #endif
            return
        }

        let fileURL = documentsDirectory.appendingPathComponent("todo.md")

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            #if DEBUG
            print("📄 todo.md ファイルが存在しません")
            #endif
            return
        }

        do {
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            parseTodosFromMarkdown(content: content)
            #if DEBUG
            print("📁 Markdownファイルから読み込みました: \(todos.count)件")
            #endif
        } catch {
            #if DEBUG
            print("❌ ファイル読み込みに失敗しました: \(error)")
            #endif
        }
    }
    
    /// Markdownコンテンツの解析
    private func parseTodosFromMarkdown(content: String) {
        var loadedTodos: [TodoItem] = []
        let lines = content.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // チェックボックス行の解析
            if trimmedLine.hasPrefix("- [ ]") {
                // 未完了Todo
                let todoText = trimmedLine.replacingOccurrences(of: "- [ ]", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !todoText.isEmpty {
                    let todo = TodoItem(
                        id: UUID().uuidString,
                        text: todoText,
                        isCompleted: false,
                        lineNumber: loadedTodos.count + 1,
                        originalLine: trimmedLine
                    )
                    loadedTodos.append(todo)
                }
            } else if trimmedLine.hasPrefix("- [x]") || trimmedLine.hasPrefix("- [X]") {
                // 完了済みTodo
                let todoText = trimmedLine.replacingOccurrences(of: "- [x]", with: "")
                    .replacingOccurrences(of: "- [X]", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !todoText.isEmpty {
                    let todo = TodoItem(
                        id: UUID().uuidString,
                        text: todoText,
                        isCompleted: true,
                        lineNumber: loadedTodos.count + 1,
                        originalLine: trimmedLine
                    )
                    loadedTodos.append(todo)
                }
            }
        }
        
        self.todos = loadedTodos
        updateStatistics()
    }
    
    // MARK: - Private Methods

    /// 統計情報を更新する
    public func updateStatistics() {
        let total = todos.count
        let completed = todos.filter { $0.isCompleted }.count
        let pending = total - completed
        let completionPercentage = total > 0 ? Double(completed) / Double(total) * 100 : 0
        
        statistics = TodoStatistics(
            total: total,
            completed: completed,
            pending: pending,
            completionPercentage: completionPercentage
        )
    }
}

// MARK: - Views

/// 個々のTodoアイテムを表示するビュー
struct SimpleTodoItemView: View {
    let todo: TodoItem
    let onToggle: (String) -> Void
    let onDelete: (String) -> Void
    let isEditing: Bool
    let onTextChange: (String, String) -> Void
    let onEditingFinished: (String) -> Void
    
    @State private var isPressed: Bool = false
    @State private var editingText: String = ""
    @FocusState private var isTextFieldFocused: Bool
    private let hapticFeedback = UIImpactFeedbackGenerator(style: .medium)
    
    var body: some View {
        HStack(spacing: 12) {
            // チェックボックス
            Button {
                performToggle()
            } label: {
                ZStack {
                    Circle()
                        .fill(todo.isCompleted ? Color.green : Color.gray.opacity(0.2))
                        .frame(width: 28, height: 28)
                    
                    if todo.isCompleted {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        Circle()
                            .stroke(Color.gray.opacity(0.5), lineWidth: 2)
                            .frame(width: 22, height: 22)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: todo.isCompleted)
            
            // Todoテキスト（編集対応）
            if isEditing {
                TextField("Todoを入力", text: $editingText)
                    .font(.body)
                    .focused($isTextFieldFocused)
                    .onSubmit {
                        finishEditing()
                    }
                    .onChange(of: editingText) { oldValue, newValue in
                        onTextChange(todo.id, newValue)
                    }
            } else {
                Text(todo.text.isEmpty ? "空のTodo" : todo.text)
                    .font(.body)
                    .foregroundColor(todo.isCompleted ? .secondary : (todo.text.isEmpty ? .secondary : .primary))
                    .strikethrough(todo.isCompleted)
                    .multilineTextAlignment(.leading)
                    .lineLimit(nil)
                    .opacity(todo.text.isEmpty ? 0.6 : 1.0)
            }
            
            Spacer(minLength: 8)
            
            // ハンバーガーメニューアイコン（ドラッグハンドル）
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 16))
                .foregroundColor(.gray.opacity(0.6))
                .padding(.leading, 8)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 12)
        .background(todo.isCompleted ? Color.green.opacity(0.1) : Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
        .onTapGesture {
            performToggle()
        }
        .onLongPressGesture(minimumDuration: 0.01) {
            // 長押し終了時
        } onPressingChanged: { isPressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = isPressing
            }
            
            if isPressing {
                hapticFeedback.prepare()
            }
        }
        .onAppear {
            editingText = todo.text
            if isEditing {
                isTextFieldFocused = true
            }
        }
        .onChange(of: isEditing) { oldValue, newValue in
            if newValue {
                editingText = todo.text
                isTextFieldFocused = true
            }
        }
    }
    
    private func finishEditing() {
        isTextFieldFocused = false
        onEditingFinished(todo.id)
    }
    
    private func performToggle() {
        hapticFeedback.impactOccurred()
        onToggle(todo.id)
    }
}

/// メイン画面ビュー
struct ContentView: View {
    @StateObject private var todoManager = SimpleTodoManager()
    @State private var newTodoText: String = ""
    @FocusState private var isNewTodoFocused: Bool
    @State private var editingTodoId: String? = nil
    @State private var showCompletedTodos: Bool = false
    @State private var recentlyCompletedTodos: Set<String> = []
    
    // MARK: - Todo一覧セクション
    
    @ViewBuilder 
    private var todoListSection: some View {
        if todoManager.todos.isEmpty {
            // 空状態
            VStack(spacing: 24) {
                Spacer()
                
                Image(systemName: "checkmark.circle.badge.xmark")
                    .font(.system(size: 64))
                    .foregroundColor(.secondary)
                
                VStack(spacing: 8) {
                    Text("Todoがありません")
                        .font(.title2)
                        .fontWeight(.medium)
                    
                    Text("下のフィールドから新しいTodoを追加しましょう")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                Spacer()
            }
            .padding(.horizontal, 40)
        } else {
            VStack(spacing: 0) {
                // Todo一覧
                List {
                    // 未完了のTodo + 最近完了したTodo（ディレイ用）
                    ForEach(todoManager.todos.filter { !$0.isCompleted || recentlyCompletedTodos.contains($0.id) }) { todo in
                        SimpleTodoItemView(
                            todo: todo,
                            onToggle: { todoId in
                                handleTodoToggle(todoId: todoId)
                            },
                            onDelete: { todoId in
                                withAnimation(.spring()) {
                                    recentlyCompletedTodos.remove(todoId)
                                    todoManager.removeTodo(id: todoId)
                                }
                            },
                            isEditing: editingTodoId == todo.id,
                            onTextChange: { todoId, newText in
                                updateTodoText(todoId: todoId, newText: newText)
                            },
                            onEditingFinished: { todoId in
                                finishEditingTodo(todoId: todoId)
                            }
                        )
                        .listRowSeparator(.hidden)
                    }
                    .onDelete { indexSet in
                        withAnimation(.spring()) {
                            let visibleTodos = todoManager.todos.filter { !$0.isCompleted || recentlyCompletedTodos.contains($0.id) }
                            for index in indexSet {
                                let todoId = visibleTodos[index].id
                                recentlyCompletedTodos.remove(todoId)
                                todoManager.removeTodo(id: todoId)
                            }
                        }
                    }
                    .onMove { source, destination in
                        withAnimation(.spring()) {
                            todoManager.moveTodos(from: source, to: destination)
                        }
                    }
                    
                    // 完了済みTodoの表示/非表示トグル
                    if !todoManager.todos.filter({ $0.isCompleted && !recentlyCompletedTodos.contains($0.id) }).isEmpty {
                        Section {
                            Button {
                                withAnimation(.spring()) {
                                    showCompletedTodos.toggle()
                                }
                            } label: {
                                HStack {
                                    Image(systemName: showCompletedTodos ? "chevron.down" : "chevron.right")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                    
                                    Text("完了済み (\(todoManager.todos.filter({ $0.isCompleted && !recentlyCompletedTodos.contains($0.id) }).count)件)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    Spacer()
                                }
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PlainButtonStyle())
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        }
                    }
                    
                    // 完了済みTodoの表示
                    if showCompletedTodos {
                        ForEach(todoManager.todos.filter { $0.isCompleted && !recentlyCompletedTodos.contains($0.id) }) { todo in
                            SimpleTodoItemView(
                                todo: todo,
                                onToggle: { todoId in
                                    todoManager.toggleTodo(id: todoId)
                                },
                                onDelete: { todoId in
                                    withAnimation(.spring()) {
                                        todoManager.removeTodo(id: todoId)
                                    }
                                },
                                isEditing: false,
                                onTextChange: { _, _ in },
                                onEditingFinished: { _ in }
                            )
                            .listRowSeparator(.hidden)
                            .opacity(0.6)
                        }
                        .onDelete { indexSet in
                            withAnimation(.spring()) {
                                let completedTodos = todoManager.todos.filter { $0.isCompleted && !recentlyCompletedTodos.contains($0.id) }
                                for index in indexSet {
                                    let todoId = completedTodos[index].id
                                    recentlyCompletedTodos.remove(todoId)
                                    todoManager.removeTodo(id: todoId)
                                }
                            }
                        }
                    }
                }
                .listStyle(PlainListStyle())
            }
        }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            NavigationStack {
                VStack(spacing: 0) {
                    // Todo一覧
                    todoListSection
                }
                .navigationTitle("todo.md")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            todoManager.removeCompletedTodos()
                        } label: {
                            Label("完了済みを削除", systemImage: "trash")
                        }
                        .disabled(todoManager.todos.filter({ $0.isCompleted }).isEmpty)
                        
                        Section("連携") {
                            Button {
                                openInObsidian()
                            } label: {
                                Label("Obsidianで開く", systemImage: "link")
                            }
                        }
                        
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            }
            
            // フローティング追加ボタン
            Button(action: addNewTodo) {
                Image(systemName: "plus")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(width: 56, height: 56)
                    .background(Color.blue)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
            }
            .padding(.trailing, 24)
            .padding(.bottom, 34)
        }
    }
    
    // MARK: - アクション
    
    /// Todoの完了状態を切り替える（ディレイ処理付き）
    private func handleTodoToggle(todoId: String) {
        todoManager.toggleTodo(id: todoId)
        
        // 完了状態になった場合、2.5秒間未完了セクションに留める
        if let todo = todoManager.todos.first(where: { $0.id == todoId }), todo.isCompleted {
            recentlyCompletedTodos.insert(todoId)
            
            // 2.5秒後に完了セクションに移動
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                recentlyCompletedTodos.remove(todoId)
            }
        } else {
            // 未完了に戻した場合は即座にrecentlyCompletedTodosから削除
            recentlyCompletedTodos.remove(todoId)
        }
    }
    
    /// 新しいTodoを追加する
    private func addNewTodo() {
        // 新しい空のTodoを追加して編集モードにする
        let newTodoId = UUID().uuidString
        let newTodo = TodoItem(
            id: newTodoId,
            text: "",
            isCompleted: false,
            lineNumber: todoManager.todos.count + 1,
            originalLine: "- [ ] "
        )
        
        withAnimation(.spring()) {
            todoManager.todos.append(newTodo)
            todoManager.updateStatistics()
            editingTodoId = newTodoId
        }
    }
    
    /// Todoのテキストを更新
    private func updateTodoText(todoId: String, newText: String) {
        guard let index = todoManager.todos.firstIndex(where: { $0.id == todoId }) else { return }
        todoManager.todos[index] = TodoItem(
            id: todoManager.todos[index].id,
            text: newText,
            isCompleted: todoManager.todos[index].isCompleted,
            lineNumber: todoManager.todos[index].lineNumber,
            originalLine: todoManager.todos[index].originalLine
        )
    }
    
    /// Todo編集を完了
    private func finishEditingTodo(todoId: String) {
        guard let index = todoManager.todos.firstIndex(where: { $0.id == todoId }) else { return }
        
        // 空のテキストの場合は削除
        if todoManager.todos[index].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            withAnimation(.spring()) {
                todoManager.removeTodo(id: todoId)
                editingTodoId = nil
            }
        } else {
            todoManager.updateStatistics()
            todoManager.syncToMarkdownFile()
            withAnimation(.spring()) {
                editingTodoId = nil
            }
        }
    }
    
    // MARK: - Obsidian連携
    
    /// ObsidianでTodoリストを開く
    private func openInObsidian() {
        // 現在のTodo項目をMarkdown形式に変換
        let markdownContent = generateMarkdownContent()
        
        // ObsidianのURLスキーム（新規ファイル作成）
        let obsidianURL = "obsidian://new?name=TodoList_\(Date().timeIntervalSince1970)&content=\(markdownContent.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        
        if let url = URL(string: obsidianURL) {
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            } else {
                // Obsidianがインストールされていない場合の代替手段
                shareMarkdownContent(markdownContent)
            }
        }
    }
    
    /// 現在のTodo項目をMarkdown形式に変換
    private func generateMarkdownContent() -> String {
        let dateString = Date().formatted(date: .complete, time: .shortened)
        var markdown = "# Todo List - \(dateString)\n\n"
        
        if todoManager.todos.isEmpty {
            markdown += "No todos available.\n"
        } else {
            markdown += "## Tasks\n\n"
        }
        
        for todo in todoManager.todos {
            let checkbox = todo.isCompleted ? "- [x]" : "- [ ]"
            markdown += "\(checkbox) \(todo.text)\n"
        }
        
        markdown += "\n---\n*Generated by iCloud Markdown Todo App*"
        return markdown
    }
    
    /// Markdownコンテンツを共有
    private func shareMarkdownContent(_ content: String) {
        let activityVC = UIActivityViewController(
            activityItems: [content],
            applicationActivities: nil
        )
        
        // iPadでの表示設定
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            if let rootVC = window.rootViewController {
                activityVC.popoverPresentationController?.sourceView = rootVC.view
                activityVC.popoverPresentationController?.sourceRect = CGRect(x: rootVC.view.bounds.midX, y: rootVC.view.bounds.midY, width: 0, height: 0)
                rootVC.present(activityVC, animated: true)
            }
        }
    }
}

// MARK: - App

@main
struct TodoApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}