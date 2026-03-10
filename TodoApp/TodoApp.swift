//
//  TodoApp.swift
//  TodoApp
//
//  mdTodo App
//  File Picker + iCloud Drive integration
//

import SwiftUI
import UniformTypeIdentifiers
import TodoManager
import CloudKitSync
import MarkdownParser

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

// MARK: - Document Picker

struct DocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        var contentTypes: [UTType] = [.plainText]
        if let markdownType = UTType("net.daringfireball.markdown") {
            contentTypes.insert(markdownType, at: 0)
        }
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: contentTypes
        )
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void

        init(onPick: @escaping (URL) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }
    }
}

// MARK: - New File Sheet

struct NewFileSheet: View {
    @Binding var isPresented: Bool
    let onCreate: (String) -> Void
    @State private var fileName: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("File name") {
                    HStack {
                        TextField("Enter file name", text: $fileName)
                            .focused($isFocused)
                            .autocorrectionDisabled()
                        Text(".md")
                            .foregroundColor(.secondary)
                    }
                }

                Section {
                    Text("Will be created in the app's Documents folder")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("New File")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let name = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty else { return }
                        let fullName = name.hasSuffix(".md") ? name : "\(name).md"
                        onCreate(fullName)
                        isPresented = false
                    }
                    .disabled(fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { isFocused = true }
        }
    }
}

// MARK: - Views

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
            .accessibilityLabel(todo.isCompleted ? "Mark \(todo.text) incomplete" : "Mark \(todo.text) complete")
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: todo.isCompleted)

            if isEditing {
                TextField("Enter todo", text: $editingText)
                    .font(.body)
                    .focused($isTextFieldFocused)
                    .onSubmit {
                        finishEditing()
                    }
                    .onChange(of: editingText) { oldValue, newValue in
                        onTextChange(todo.id, newValue)
                    }
            } else {
                Text(todo.text.isEmpty ? "Empty todo" : todo.text)
                    .font(.body)
                    .foregroundColor(todo.isCompleted ? .secondary : (todo.text.isEmpty ? .secondary : .primary))
                    .strikethrough(todo.isCompleted)
                    .multilineTextAlignment(.leading)
                    .lineLimit(nil)
                    .opacity(todo.text.isEmpty ? 0.6 : 1.0)
            }

            Spacer(minLength: 8)

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 16))
                .foregroundColor(.gray.opacity(0.6))
                .padding(.leading, 8)
                .accessibilityHidden(true)
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

// MARK: - Main View

struct ContentView: View {
    @StateObject private var todoManager: TodoManager

    @State private var newTodoText: String = ""
    @FocusState private var isNewTodoFocused: Bool
    @State private var editingTodoId: String? = nil
    @State private var showCompletedTodos: Bool = false
    @State private var recentlyCompletedTodos: Set<String> = []
    @State private var showDocumentPicker: Bool = false
    @State private var showNewFileSheet: Bool = false
    @State private var showErrorAlert: Bool = false
    @State private var errorMessage: String = ""

    init() {
        let syncManager = CloudSyncManager()
        let manager = TodoManager(syncManager: syncManager)
        manager.onTodosChanged = { todos in
            SharedDataManager.shared.saveWidgetData(todos: todos)
        }
        _todoManager = StateObject(wrappedValue: manager)
    }

    // MARK: - Computed

    private var completedAndHiddenTodos: [TodoItem] {
        todoManager.todos.filter { $0.isCompleted && !recentlyCompletedTodos.contains($0.id) }
    }

    private var activeTodos: [TodoItem] {
        todoManager.todos.filter { !$0.isCompleted || recentlyCompletedTodos.contains($0.id) }
    }

    // MARK: - Todo List Section

    @ViewBuilder
    private var todoListSection: some View {
        if todoManager.todos.isEmpty {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "checkmark.circle.badge.xmark")
                    .font(.system(size: 64))
                    .foregroundColor(.secondary)

                VStack(spacing: 8) {
                    Text("No todos")
                        .font(.title2)
                        .fontWeight(.medium)

                    Text("Tap + to add a new todo")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                Spacer()
            }
            .padding(.horizontal, 40)
        } else {
            VStack(spacing: 0) {
                List {
                    ForEach(activeTodos) { todo in
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
                            let visibleTodos = activeTodos
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

                    if !completedAndHiddenTodos.isEmpty {
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

                                    Text("Completed (\(completedAndHiddenTodos.count))")
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

                    if showCompletedTodos {
                        ForEach(completedAndHiddenTodos) { todo in
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
                                let completedTodos = completedAndHiddenTodos
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

    // MARK: - File Info Footer

    @ViewBuilder
    private var fileInfoFooter: some View {
        let syncManager = todoManager.syncManager
        if syncManager.isExternalFile || syncManager.storageLocation == .icloud {
            HStack(spacing: 6) {
                if syncManager.storageLocation == .icloud {
                    Image(systemName: "checkmark.icloud")
                        .font(.system(size: 10))
                        .foregroundColor(.blue)
                }
                if syncManager.isExternalFile {
                    Image(systemName: "doc.badge.arrow.up")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                }
                Text(syncManager.currentFileName)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemGroupedBackground))
        }
    }

    var body: some View {
        let syncManager = todoManager.syncManager
        ZStack(alignment: .bottomTrailing) {
            NavigationStack {
                VStack(spacing: 0) {
                    todoListSection
                    fileInfoFooter
                }
                .navigationTitle(syncManager.currentFileName)
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            Button {
                                todoManager.removeCompletedTodos()
                            } label: {
                                Label("Remove completed", systemImage: "trash")
                            }
                            .disabled(todoManager.todos.filter({ $0.isCompleted }).isEmpty)

                            Section("File") {
                                Button {
                                    showDocumentPicker = true
                                } label: {
                                    Label("Open file...", systemImage: "doc.badge.plus")
                                }

                                Button {
                                    showNewFileSheet = true
                                } label: {
                                    Label("New file", systemImage: "doc.badge.gearshape")
                                }

                                if syncManager.isExternalFile {
                                    Button {
                                        todoManager.resetToDefaultFile()
                                    } label: {
                                        Label("Reset to default", systemImage: "arrow.uturn.backward")
                                    }
                                }

                                Button {
                                    todoManager.loadTodos()
                                } label: {
                                    Label("Reload", systemImage: "arrow.clockwise")
                                }
                            }

                            Section("Storage") {
                                if syncManager.isICloudAvailable {
                                    if syncManager.storageLocation == .icloud {
                                        Button {
                                            todoManager.switchToLocal()
                                        } label: {
                                            Label("Switch to local", systemImage: "iphone")
                                        }
                                    } else {
                                        Button {
                                            todoManager.switchToICloud()
                                        } label: {
                                            Label("Switch to iCloud Drive", systemImage: "icloud")
                                        }
                                    }
                                }

                                Label(
                                    syncManager.storageLocation == .icloud ? "iCloud Drive" : "Local",
                                    systemImage: syncManager.storageLocation == .icloud ? "checkmark.icloud" : "internaldrive"
                                )
                                .font(.caption)
                            }

                            Section("Integration") {
                                Button {
                                    openInObsidian()
                                } label: {
                                    Label("Open in Obsidian", systemImage: "link")
                                }
                            }

                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }

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
            .accessibilityLabel("Add new todo")
            .padding(.trailing, 24)
            .padding(.bottom, 34)
        }
        .sheet(isPresented: $showDocumentPicker) {
            DocumentPicker { url in
                todoManager.openFile(url: url)
            }
        }
        .sheet(isPresented: $showNewFileSheet) {
            NewFileSheet(isPresented: $showNewFileSheet) { fileName in
                todoManager.createNewFile(name: fileName)
            }
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK") { showErrorAlert = false }
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            ensureDefaultFileExists()
            todoManager.loadTodos()
            syncManager.startSync()
        }
        .onChange(of: todoManager.errorMessage) { _, newError in
            if let error = newError, !error.isEmpty {
                errorMessage = error
                showErrorAlert = true
                todoManager.errorMessage = nil
            }
        }
    }

    // MARK: - Actions

    private func ensureDefaultFileExists() {
        let syncManager = todoManager.syncManager
        guard let fileURL = syncManager.currentFileURL else { return }
        guard !syncManager.isExternalFile else { return }

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            let initialContent = "# Todo List\n\n"
            try? initialContent.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }

    private func handleTodoToggle(todoId: String) {
        todoManager.toggleTodo(id: todoId)

        if let todo = todoManager.todos.first(where: { $0.id == todoId }), todo.isCompleted {
            recentlyCompletedTodos.insert(todoId)

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                recentlyCompletedTodos.remove(todoId)
            }
        } else {
            recentlyCompletedTodos.remove(todoId)
        }
    }

    private func addNewTodo() {
        withAnimation(.spring()) {
            let newTodoId = todoManager.addEmptyTodo()
            editingTodoId = newTodoId
        }
    }

    private func updateTodoText(todoId: String, newText: String) {
        todoManager.updateTodoText(id: todoId, text: newText)
    }

    private func finishEditingTodo(todoId: String) {
        todoManager.finishEditing(id: todoId)
        withAnimation(.spring()) {
            editingTodoId = nil
        }
    }

    // MARK: - Obsidian

    private func openInObsidian() {
        let markdownContent = generateMarkdownContent()

        let obsidianURL = "obsidian://new?name=TodoList_\(Date().timeIntervalSince1970)&content=\(markdownContent.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"

        if let url = URL(string: obsidianURL) {
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            } else {
                shareMarkdownContent(markdownContent)
            }
        }
    }

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

        markdown += "\n---\n*Generated by mdTodo*"
        return markdown
    }

    private func shareMarkdownContent(_ content: String) {
        let activityVC = UIActivityViewController(
            activityItems: [content],
            applicationActivities: nil
        )

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
struct TodoAppMain: App {
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
