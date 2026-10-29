import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Board.sortOrder) private var boards: [Board]
    @Query(sort: \BoardColumn.sortOrder) private var allColumns: [BoardColumn]
    @Query(sort: \TaskCard.sortOrder) private var allTasks: [TaskCard]

    @State private var selectedBoardID: UUID?
    @State private var editingBoardID: UUID?
    @State private var isCreatingBoard = false
    @State private var newBoardTitle = ""
    @State private var selectedTask: TaskCard?
    @State private var searchText = ""

    private var selectedBoard: Board? {
        boards.first(where: { $0.id == selectedBoardID }) ?? boards.first
    }

    private var visibleColumns: [BoardColumn] {
        guard let board = selectedBoard else { return [] }
        return allColumns.filter { $0.boardID == board.id }.sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            if let board = selectedBoard {
                boardWorkspace(board)
            } else {
                ContentUnavailableView(
                    "Создай первую доску",
                    systemImage: "rectangle.split.3x1",
                    description: Text("Jungo хранит задачи локально на этом Mac.")
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
        .task { seedIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: .jungoCreateTask)) { _ in
            if let column = visibleColumns.first { createTask(in: column) }
        }
        .sheet(item: $selectedTask) { task in
            TaskEditorSheet(task: task)
        }
        .alert(editingBoardID == nil ? "Новая доска" : "Переименовать доску", isPresented: $isCreatingBoard) {
            TextField("Название доски", text: $newBoardTitle)
            Button("Отмена", role: .cancel) {
                newBoardTitle = ""
                editingBoardID = nil
            }
            Button("Сохранить") { createOrRenameBoard() }
                .disabled(newBoardTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Например, «Личные задачи» или «Jungo».")
        }
    }

    private var sidebar: some View {
        List(selection: $selectedBoardID) {
            Section("Рабочее пространство") {
                ForEach(boards) { board in
                    Label(board.title, systemImage: "rectangle.split.3x1")
                        .tag(board.id)
                        .contextMenu {
                            Button("Переименовать") {
                                editingBoardID = board.id
                                newBoardTitle = board.title
                                selectedBoardID = board.id
                                isCreatingBoard = true
                            }
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Jungo")
        .safeAreaInset(edge: .bottom) {
            Button {
                editingBoardID = nil
                newBoardTitle = ""
                isCreatingBoard = true
            } label: {
                Label("Новая доска", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding()
        }
    }

    private func boardWorkspace(_ board: Board) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(board.title).font(.largeTitle.weight(.bold))
                    Text("\(visibleColumns.reduce(0) { $0 + tasks(in: $1).count }) задач")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
                Spacer()
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Поиск задач", text: $searchText)
                        .textFieldStyle(.plain)
                        .frame(width: 160)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 9))
                Button {
                    if let first = visibleColumns.first { createTask(in: first) }
                } label: {
                    Label("Новая задача", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
                .buttonStyle(.borderedProminent)
            }
            .padding(24)
            Divider()
            if visibleColumns.isEmpty {
                ContentUnavailableView("Пока нет колонок", systemImage: "rectangle.split.3x1")
            } else {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(visibleColumns) { column in
                            columnView(column).frame(width: 260)
                        }
                    }
                    .padding(20)
                }
            }
            Spacer(minLength: 0)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func columnView(_ column: BoardColumn) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle().fill(columnColor(column.sortOrder)).frame(width: 8, height: 8)
                Text(column.title).font(.headline)
                Text("\(tasks(in: column).count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                Spacer()
                Menu {
                    Button("Добавить задачу") { createTask(in: column) }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
            }
            ForEach(tasks(in: column)) { task in
                TaskCardView(task: task)
                    .onTapGesture { selectedTask = task }
                    .contextMenu {
                        Button("Редактировать") { selectedTask = task }
                        Menu("Переместить в") {
                            ForEach(visibleColumns.filter { $0.id != column.id }) { destination in
                                Button(destination.title) { move(task, to: destination) }
                            }
                        }
                        Divider()
                        Button("Удалить задачу", role: .destructive) {
                            modelContext.delete(task)
                            saveChanges()
                        }
                    }
            }
            Button {
                createTask(in: column)
            } label: {
                Label("Добавить задачу", systemImage: "plus")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(.quaternary, lineWidth: 1) }
    }

    private func tasks(in column: BoardColumn) -> [TaskCard] {
        allTasks.filter {
            $0.columnID == column.id &&
            (searchText.isEmpty ||
             $0.title.localizedCaseInsensitiveContains(searchText) ||
             $0.details.localizedCaseInsensitiveContains(searchText))
        }.sorted { $0.sortOrder < $1.sortOrder }
    }

    private func createTask(in column: BoardColumn) {
        let task = TaskCard(title: "Новая задача", sortOrder: tasks(in: column).count, columnID: column.id)
        modelContext.insert(task)
        saveChanges()
        selectedTask = task
    }

    private func move(_ task: TaskCard, to destination: BoardColumn) {
        let destinationCount = allTasks.filter { $0.columnID == destination.id }.count
        task.columnID = destination.id
        task.sortOrder = destinationCount
        saveChanges()
    }

    private func createOrRenameBoard() {
        let title = newBoardTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        if let editingBoardID, let existing = boards.first(where: { $0.id == editingBoardID }) {
            existing.title = title
        } else {
            let board = Board(title: title, sortOrder: boards.count)
            modelContext.insert(board)
            for (index, name) in ["К выполнению", "В работе", "Готово"].enumerated() {
                modelContext.insert(BoardColumn(title: name, sortOrder: index, boardID: board.id))
            }
            selectedBoardID = board.id
        }
        saveChanges()
        newBoardTitle = ""
        editingBoardID = nil
    }

    private func seedIfNeeded() {
        guard boards.isEmpty else {
            if selectedBoardID == nil { selectedBoardID = boards.first?.id }
            return
        }
        let board = Board(title: "Моя доска")
        let todo = BoardColumn(title: "К выполнению", sortOrder: 0, boardID: board.id)
        let doing = BoardColumn(title: "В работе", sortOrder: 1, boardID: board.id)
        let done = BoardColumn(title: "Готово", sortOrder: 2, boardID: board.id)
        modelContext.insert(board)
        modelContext.insert(todo)
        modelContext.insert(doing)
        modelContext.insert(done)
        modelContext.insert(TaskCard(title: "Познакомиться с Jungo", details: "Это пример карточки. Можно изменить её или удалить.", columnID: todo.id))
        modelContext.insert(TaskCard(title: "Настроить рабочий процесс", details: "Создавай задачи, перемещай их между колонками и сохраняй порядок.", priority: .high, columnID: doing.id))
        selectedBoardID = board.id
        saveChanges()
    }

    private func saveChanges() {
        do {
            try modelContext.save()
        } catch {
            assertionFailure("SwiftData save failed: \(error.localizedDescription)")
        }
    }

    private func columnColor(_ index: Int) -> Color {
        switch index % 3 {
        case 0: .blue
        case 1: .orange
        default: .green
        }
    }
}

private struct TaskCardView: View {
    let task: TaskCard

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(task.title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !task.details.isEmpty {
                Text(task.details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Label(task.priority.title, systemImage: task.priority.symbol)
                    .font(.caption2)
                    .foregroundStyle(task.priority == .high ? .orange : .secondary)
                Spacer()
                Text(task.createdAt, format: .dateTime.month(.abbreviated).day())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary, lineWidth: 1) }
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct TaskEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var task: TaskCard

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Задача").font(.title2.bold())
            TextField("Название", text: $task.title)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
            VStack(alignment: .leading, spacing: 6) {
                Text("Описание").font(.subheadline.weight(.medium))
                TextEditor(text: $task.details)
                    .frame(minHeight: 120)
                    .padding(4)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
            }
            Picker("Приоритет", selection: $task.priority) {
                ForEach(TaskPriority.allCases) { priority in
                    Text(priority.title).tag(priority)
                }
            }
            .pickerStyle(.segmented)
            HStack {
                Spacer()
                Button("Отмена", role: .cancel) { dismiss() }
                Button("Готово") {
                    do { try modelContext.save() } catch { assertionFailure(error.localizedDescription) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}
