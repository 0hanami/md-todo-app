//
//  TodoApp.swift
//  TodoApp
//
//  mdTodo App - 完全単一ファイル版
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

// MARK: - File Location Manager

enum StorageLocation: String {
    case local
    case icloud
}

class FileLocationManager: ObservableObject {
    @Published var currentFileURL: URL?
    @Published var currentFileName: String = "todo.md"
    @Published var isExternalFile: Bool = false
    @Published var storageLocation: StorageLocation = .local
    @Published var iCloudSyncStatus: String = ""

    private let bookmarkKey = "selectedFileBookmark"
    private let storageLocationKey = "storageLocation"
    private var isAccessingSecurityScope = false

    var defaultFileURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("todo.md")
    }

    var isICloudAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    var iCloudDocumentsURL: URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.com.0hanami.mdtodo")?
            .appendingPathComponent("Documents")
    }

    var iCloudDefaultFileURL: URL? {
        iCloudDocumentsURL?.appendingPathComponent("todo.md")
    }

    init() {
        let savedLocation = UserDefaults.standard.string(forKey: storageLocationKey) ?? "local"
        storageLocation = StorageLocation(rawValue: savedLocation) ?? .local

        if let restoredURL = restoreBookmark() {
            currentFileURL = restoredURL
            currentFileName = restoredURL.lastPathComponent
            isExternalFile = true
        } else if storageLocation == .icloud && isICloudAvailable {
            setupICloudStorage()
        } else {
            currentFileURL = defaultFileURL
            currentFileName = "todo.md"
            isExternalFile = false
        }
    }

    func switchToICloud() {
        guard isICloudAvailable, let iCloudDocsURL = iCloudDocumentsURL else { return }

        // Create iCloud Documents folder if needed
        if !FileManager.default.fileExists(atPath: iCloudDocsURL.path) {
            do {
                try FileManager.default.createDirectory(at: iCloudDocsURL, withIntermediateDirectories: true)
            } catch {
                #if DEBUG
                print("Failed to create iCloud directory: \(error)")
                #endif
                return
            }
        }

        // Migrate local file to iCloud if it exists and iCloud file doesn't
        let iCloudFileURL = iCloudDocsURL.appendingPathComponent("todo.md")
        if let localURL = defaultFileURL,
           FileManager.default.fileExists(atPath: localURL.path),
           !FileManager.default.fileExists(atPath: iCloudFileURL.path) {
            do {
                try FileManager.default.copyItem(at: localURL, to: iCloudFileURL)
            } catch {
                #if DEBUG
                print("Failed to migrate to iCloud: \(error)")
                #endif
            }
        }

        stopAccessing()
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        storageLocation = .icloud
        UserDefaults.standard.set(storageLocation.rawValue, forKey: storageLocationKey)
        currentFileURL = iCloudFileURL
        currentFileName = "todo.md"
        isExternalFile = false
        iCloudSyncStatus = "iCloud Drive"
    }

    func switchToLocal() {
        stopAccessing()
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        storageLocation = .local
        UserDefaults.standard.set(storageLocation.rawValue, forKey: storageLocationKey)
        currentFileURL = defaultFileURL
        currentFileName = "todo.md"
        isExternalFile = false
        iCloudSyncStatus = ""
    }

    func selectFile(url: URL) {
        stopAccessing()

        do {
            try saveBookmark(for: url)
            currentFileURL = url
            currentFileName = url.lastPathComponent
            isExternalFile = true
        } catch {
            #if DEBUG
            print("Failed to save bookmark: \(error)")
            #endif
            currentFileURL = url
            currentFileName = url.lastPathComponent
            isExternalFile = true
        }
    }

    func resetToDefault() {
        stopAccessing()
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        isExternalFile = false

        if storageLocation == .icloud && isICloudAvailable {
            setupICloudStorage()
        } else {
            currentFileURL = defaultFileURL
            currentFileName = "todo.md"
        }
    }

    func startAccessing() -> Bool {
        guard let url = currentFileURL, isExternalFile else { return true }
        if isAccessingSecurityScope { return true }
        isAccessingSecurityScope = url.startAccessingSecurityScopedResource()
        return isAccessingSecurityScope
    }

    func stopAccessing() {
        guard isAccessingSecurityScope, let url = currentFileURL else { return }
        url.stopAccessingSecurityScopedResource()
        isAccessingSecurityScope = false
    }

    private func setupICloudStorage() {
        guard let iCloudDocsURL = iCloudDocumentsURL else {
            // iCloud not available, fall back to local
            currentFileURL = defaultFileURL
            currentFileName = "todo.md"
            storageLocation = .local
            return
        }

        if !FileManager.default.fileExists(atPath: iCloudDocsURL.path) {
            try? FileManager.default.createDirectory(at: iCloudDocsURL, withIntermediateDirectories: true)
        }

        currentFileURL = iCloudDocsURL.appendingPathComponent("todo.md")
        currentFileName = "todo.md"
        iCloudSyncStatus = "iCloud Drive"
    }

    private func saveBookmark(for url: URL) throws {
        let bookmarkData = try url.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(bookmarkData, forKey: bookmarkKey)
    }

    private func restoreBookmark() -> URL? {
        guard let bookmarkData = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }

        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale {
                try saveBookmark(for: url)
            }

            return url
        } catch {
            #if DEBUG
            print("Failed to restore bookmark: \(error)")
            #endif
            UserDefaults.standard.removeObject(forKey: bookmarkKey)
            return nil
        }
    }
}

// MARK: - iCloud File Monitor

class ICloudFileMonitor: ObservableObject {
    @Published var fileChanged: Bool = false
    private var metadataQuery: NSMetadataQuery?
    private var monitoredFileName: String?

    func startMonitoring(fileName: String) {
        stopMonitoring()
        monitoredFileName = fileName

        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K LIKE %@", NSMetadataItemFSNameKey, fileName)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleQueryUpdate(_:)),
            name: .NSMetadataQueryDidUpdate,
            object: query
        )

        query.start()
        metadataQuery = query
    }

    func stopMonitoring() {
        metadataQuery?.stop()
        metadataQuery = nil
        monitoredFileName = nil
        NotificationCenter.default.removeObserver(self)
    }

    func consumeChange() {
        fileChanged = false
    }

    @objc private func handleQueryUpdate(_ notification: Notification) {
        DispatchQueue.main.async {
            self.fileChanged = true
        }
    }

    deinit {
        stopMonitoring()
    }
}

// MARK: - Document Picker

struct DocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [UTType.plainText]
        )
        picker.allowsMultipleSelection = false
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
                Section("ファイル名") {
                    HStack {
                        TextField("ファイル名を入力", text: $fileName)
                            .focused($isFocused)
                            .autocorrectionDisabled()
                        Text(".md")
                            .foregroundColor(.secondary)
                    }
                }

                Section {
                    Text("アプリ内のDocumentsフォルダに作成されます")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("新規ファイル")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("作成") {
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

// MARK: - Models

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

    var completionPercentageString: String {
        return String(format: "%.1f%%", completionPercentage)
    }
}

// MARK: - Todo Manager

class SimpleTodoManager: ObservableObject {
    @Published var todos: [TodoItem] = []
    @Published var statistics: TodoStatistics = TodoStatistics()

    let fileManager: FileLocationManager
    private var originalFileContent: String?

    init(fileManager: FileLocationManager) {
        self.fileManager = fileManager
        loadTodosFromCurrentFile()
    }

    // MARK: - File Operations

    func openFile(url: URL) {
        fileManager.selectFile(url: url)
        loadTodosFromCurrentFile()
    }

    func createNewFile(name: String) {
        guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let fileURL = documentsDir.appendingPathComponent(name)

        let initialContent = "# \(name.replacingOccurrences(of: ".md", with: ""))\n\n"
        do {
            try initialContent.write(to: fileURL, atomically: true, encoding: .utf8)
            fileManager.resetToDefault()
            fileManager.currentFileURL = fileURL
            fileManager.currentFileName = name
            fileManager.isExternalFile = false
            originalFileContent = initialContent
            todos = []
            updateStatistics()
            syncToWidget()
        } catch {
            #if DEBUG
            print("Failed to create file: \(error)")
            #endif
        }
    }

    func resetToDefaultFile() {
        fileManager.resetToDefault()
        loadTodosFromCurrentFile()
    }

    func loadTodosFromCurrentFile() {
        guard let fileURL = fileManager.currentFileURL else { return }

        let accessed = fileManager.startAccessing()
        defer { if fileManager.isExternalFile { fileManager.stopAccessing() } }

        guard accessed else {
            #if DEBUG
            print("Failed to access security scoped resource")
            #endif
            return
        }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            #if DEBUG
            print("File does not exist: \(fileURL.path)")
            #endif
            originalFileContent = nil
            todos = []
            updateStatistics()
            return
        }

        do {
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            originalFileContent = content
            parseTodosFromMarkdown(content: content)
            #if DEBUG
            print("Loaded \(todos.count) todos from \(fileURL.lastPathComponent)")
            #endif
        } catch {
            #if DEBUG
            print("Failed to load file: \(error)")
            #endif
        }
    }

    // MARK: - Public Methods

    func toggleTodo(id todoId: String) {
        guard let index = todos.firstIndex(where: { $0.id == todoId }) else { return }
        todos[index] = todos[index].toggled()
        updateStatistics()
        syncToMarkdownFile()
        syncToWidget()
    }

    func addTodo(text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        let newTodo = TodoItem(
            id: UUID().uuidString,
            text: trimmedText,
            isCompleted: false,
            lineNumber: -1,
            originalLine: "- [ ] \(trimmedText)"
        )

        todos.append(newTodo)
        updateStatistics()
        syncToMarkdownFile()
        syncToWidget()
    }

    func removeCompletedTodos() {
        todos.removeAll { $0.isCompleted }
        updateStatistics()
        syncToMarkdownFile()
        syncToWidget()
    }

    func removeTodo(id todoId: String) {
        todos.removeAll { $0.id == todoId }
        updateStatistics()
        syncToMarkdownFile()
        syncToWidget()
    }

    func moveTodos(from source: IndexSet, to destination: Int) {
        todos.move(fromOffsets: source, toOffset: destination)
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

    // MARK: - Markdown Sync

    public func syncToMarkdownFile() {
        if fileManager.isExternalFile, let originalContent = originalFileContent {
            saveExternalFile(originalContent: originalContent)
        } else {
            saveInternalFile()
        }
    }

    private func saveInternalFile() {
        var markdownContent = "# Todo List\n\n"
        markdownContent += "Generated by TodoApp at \(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short))\n\n"

        let pendingTodos = todos.filter { !$0.isCompleted }
        if !pendingTodos.isEmpty {
            markdownContent += "## Pending Tasks\n\n"
            for todo in pendingTodos {
                markdownContent += "- [ ] \(todo.text)\n"
            }
            markdownContent += "\n"
        }

        let completedTodos = todos.filter { $0.isCompleted }
        if !completedTodos.isEmpty {
            markdownContent += "## Completed Tasks\n\n"
            for todo in completedTodos {
                markdownContent += "- [x] \(todo.text)\n"
            }
            markdownContent += "\n"
        }

        saveToFile(content: markdownContent)
    }

    private func saveExternalFile(originalContent: String) {
        var lines = originalContent.components(separatedBy: "\n")

        // Build a map of existing todo line numbers to updated states
        var todosByLine: [Int: TodoItem] = [:]
        for todo in todos where todo.lineNumber >= 0 && todo.lineNumber < lines.count {
            todosByLine[todo.lineNumber] = todo
        }

        // Update existing checkbox lines
        for (lineNum, todo) in todosByLine {
            let checkbox = todo.isCompleted ? "- [x]" : "- [ ]"
            lines[lineNum] = "\(checkbox) \(todo.text)"
        }

        // Remove lines for deleted todos (reverse order to keep indices valid)
        let existingLineNumbers = Set(todosByLine.keys)
        var linesToRemove: [Int] = []
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let isCheckboxLine = trimmed.hasPrefix("- [ ]") || trimmed.hasPrefix("- [x]") || trimmed.hasPrefix("- [X]")
            if isCheckboxLine && !existingLineNumbers.contains(index) {
                linesToRemove.append(index)
            }
        }
        for index in linesToRemove.reversed() {
            lines.remove(at: index)
        }

        // Append new todos (lineNumber == -1)
        let newTodos = todos.filter { $0.lineNumber < 0 }
        for todo in newTodos {
            let checkbox = todo.isCompleted ? "- [x]" : "- [ ]"
            lines.append("\(checkbox) \(todo.text)")
        }

        let updatedContent = lines.joined(separator: "\n")
        originalFileContent = updatedContent
        saveToFile(content: updatedContent)
    }

    private func saveToFile(content: String) {
        guard let fileURL = fileManager.currentFileURL else { return }

        let accessed = fileManager.startAccessing()
        defer { if fileManager.isExternalFile { fileManager.stopAccessing() } }

        guard accessed else { return }

        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            #if DEBUG
            print("Failed to save file: \(error)")
            #endif
        }
    }

    private func syncToWidget() {
        SharedDataManager.shared.saveWidgetData(todos: todos)
    }

    // MARK: - Parser

    private func parseTodosFromMarkdown(content: String) {
        var loadedTodos: [TodoItem] = []
        let lines = content.components(separatedBy: "\n")

        for (index, line) in lines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmedLine.hasPrefix("- [ ]") {
                let todoText = trimmedLine.replacingOccurrences(of: "- [ ]", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !todoText.isEmpty {
                    let todo = TodoItem(
                        id: UUID().uuidString,
                        text: todoText,
                        isCompleted: false,
                        lineNumber: index,
                        originalLine: trimmedLine
                    )
                    loadedTodos.append(todo)
                }
            } else if trimmedLine.hasPrefix("- [x]") || trimmedLine.hasPrefix("- [X]") {
                let todoText = trimmedLine.replacingOccurrences(of: "- [x]", with: "")
                    .replacingOccurrences(of: "- [X]", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !todoText.isEmpty {
                    let todo = TodoItem(
                        id: UUID().uuidString,
                        text: todoText,
                        isCompleted: true,
                        lineNumber: index,
                        originalLine: trimmedLine
                    )
                    loadedTodos.append(todo)
                }
            }
        }

        self.todos = loadedTodos
        updateStatistics()
    }

    // MARK: - Statistics

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
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: todo.isCompleted)

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
    @StateObject private var fileManager = FileLocationManager()
    @StateObject private var todoManager: SimpleTodoManager
    @StateObject private var iCloudMonitor = ICloudFileMonitor()
    @State private var newTodoText: String = ""
    @FocusState private var isNewTodoFocused: Bool
    @State private var editingTodoId: String? = nil
    @State private var showCompletedTodos: Bool = false
    @State private var recentlyCompletedTodos: Set<String> = []
    @State private var showDocumentPicker: Bool = false
    @State private var showNewFileSheet: Bool = false
    @State private var showStorageSettings: Bool = false

    init() {
        let fm = FileLocationManager()
        _fileManager = StateObject(wrappedValue: fm)
        _todoManager = StateObject(wrappedValue: SimpleTodoManager(fileManager: fm))
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
                List {
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
                    todoListSection
                }
                .navigationTitle(fileManager.currentFileName)
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

                            Section("ファイル") {
                                Button {
                                    showDocumentPicker = true
                                } label: {
                                    Label("ファイルを開く...", systemImage: "doc.badge.plus")
                                }

                                Button {
                                    showNewFileSheet = true
                                } label: {
                                    Label("新規ファイルを作成", systemImage: "doc.badge.gearshape")
                                }

                                if fileManager.isExternalFile {
                                    Button {
                                        todoManager.resetToDefaultFile()
                                    } label: {
                                        Label("デフォルトに戻す", systemImage: "arrow.uturn.backward")
                                    }
                                }
                            }

                            Section("保存先") {
                                if fileManager.isICloudAvailable {
                                    if fileManager.storageLocation == .icloud {
                                        Button {
                                            fileManager.switchToLocal()
                                            todoManager.loadTodosFromCurrentFile()
                                        } label: {
                                            Label("ローカルに切替", systemImage: "iphone")
                                        }
                                    } else {
                                        Button {
                                            fileManager.switchToICloud()
                                            todoManager.loadTodosFromCurrentFile()
                                            iCloudMonitor.startMonitoring(fileName: fileManager.currentFileName)
                                        } label: {
                                            Label("iCloud Driveに切替", systemImage: "icloud")
                                        }
                                    }
                                }

                                Label(
                                    fileManager.storageLocation == .icloud ? "iCloud Drive" : "ローカル",
                                    systemImage: fileManager.storageLocation == .icloud ? "checkmark.icloud" : "internaldrive"
                                )
                                .font(.caption)
                            }

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
        .onAppear {
            if fileManager.storageLocation == .icloud {
                iCloudMonitor.startMonitoring(fileName: fileManager.currentFileName)
            }
        }
        .onChange(of: iCloudMonitor.fileChanged) { _, changed in
            if changed {
                iCloudMonitor.consumeChange()
                todoManager.loadTodosFromCurrentFile()
            }
        }
    }

    // MARK: - Actions

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
        let newTodoId = UUID().uuidString
        let newTodo = TodoItem(
            id: newTodoId,
            text: "",
            isCompleted: false,
            lineNumber: -1,
            originalLine: "- [ ] "
        )

        withAnimation(.spring()) {
            todoManager.todos.append(newTodo)
            todoManager.updateStatistics()
            editingTodoId = newTodoId
        }
    }

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

    private func finishEditingTodo(todoId: String) {
        guard let index = todoManager.todos.firstIndex(where: { $0.id == todoId }) else { return }

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
