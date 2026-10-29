import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Board.sortOrder) private var boards: [Board]
    @Query(sort: \BoardColumn.sortOrder) private var allColumns: [BoardColumn]
    @Query(sort: \TaskCard.sortOrder) private var allTasks: [TaskCard]
    @Query(sort: \TaskChecklistItem.sortOrder) private var allChecklistItems: [TaskChecklistItem]

    @AppStorage("jungo.selectedBoardID") private var persistedSelectedBoardID = ""
    @State private var selectedBoardID: UUID?
    @State private var editingBoardID: UUID?
    @State private var editingColumnID: UUID?
    @State private var isNamingBoard = false
    @State private var isNamingColumn = false
    @State private var nameInput = ""
    @State private var selectedTask: TaskCard?
    @State private var showQuickAdd = false
    @State private var taskPendingDeletionID: UUID?
    @State private var taskPendingPermanentDeletionID: UUID?
    @State private var columnPendingDeletionID: UUID?
    @State private var showDeleteBoardConfirmation = false
    @State private var searchText = ""
    @State private var priorityFilter: PriorityFilter = .all
    @State private var selectedLabel = ""
    @State private var showOverdueOnly = false
    @State private var showTrash = false
    @FocusState private var isSearchFocused: Bool
    @State private var errorMessage: String?
    @State private var statusMessage: String?

    private enum PriorityFilter: String, CaseIterable, Identifiable {
        case all, low, normal, high
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: "Все приоритеты"
            case .low: "Низкий"
            case .normal: "Обычный"
            case .high: "Высокий"
            }
        }
        var value: TaskPriority? {
            switch self {
            case .all: nil
            case .low: .low
            case .normal: .normal
            case .high: .high
            }
        }
    }

    private var selectedBoard: Board? {
        boards.first(where: { $0.id == selectedBoardID }) ?? boards.first
    }

    private var visibleColumns: [BoardColumn] {
        guard let board = selectedBoard else { return [] }
        return allColumns.filter { $0.boardID == board.id }.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var availableLabels: [String] {
        let columnIDs = Set(visibleColumns.map(\.id))
        let labels = allTasks
            .filter { !$0.isInTrash && columnIDs.contains($0.columnID) }
            .flatMap { $0.labels }
        return Array(Set(labels)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            if let board = selectedBoard {
                boardWorkspace(board)
            } else {
                ContentUnavailableView("Создай первую доску", systemImage: "rectangle.split.3x1", description: Text("Jungo хранит задачи локально на этом Mac."))
            }
        }
        .navigationSplitViewStyle(.balanced)
        .task { seedIfNeeded() }
        .onChange(of: selectedBoardID) { _, newValue in
            if let newValue { persistedSelectedBoardID = newValue.uuidString }
            selectedLabel = ""
        }
        .onReceive(NotificationCenter.default.publisher(for: .jungoCreateTask)) { _ in
            guard !showTrash, let column = visibleColumns.first else { return }
            createTask(in: column)
        }
        .onReceive(NotificationCenter.default.publisher(for: .jungoCreateBoard)) { _ in
            editingBoardID = nil
            nameInput = ""
            isNamingBoard = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .jungoQuickAddTask)) { _ in
            guard !showTrash, !visibleColumns.isEmpty else { return }
            showQuickAdd = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .jungoToggleTrash)) { _ in
            showTrash.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .jungoFocusSearch)) { _ in
            if !showTrash { isSearchFocused = true }
        }
        .sheet(item: $selectedTask) { task in TaskEditorSheet(task: task, onSave: saveChanges) }
        .confirmationDialog("Удалить доску и все её задачи?", isPresented: $showDeleteBoardConfirmation, titleVisibility: .visible) {
            Button("Удалить доску", role: .destructive, action: deleteSelectedBoard)
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Это действие нельзя отменить. Перед удалением можно экспортировать данные в JSON.")
        }
        .confirmationDialog("Удалить колонку?", isPresented: Binding(get: { columnPendingDeletionID != nil }, set: { if !$0 { columnPendingDeletionID = nil } }), titleVisibility: .visible) {
            Button("Удалить и перенести задачи", role: .destructive) { deletePendingColumn() }
            Button("Отмена", role: .cancel) { columnPendingDeletionID = nil }
        } message: {
            Text("Карточки будут перемещены в первую оставшуюся колонку этой доски. Последнюю колонку удалить нельзя.")
        }
        .confirmationDialog("Переместить задачу в корзину?", isPresented: Binding(get: { taskPendingDeletionID != nil }, set: { if !$0 { taskPendingDeletionID = nil } }), titleVisibility: .visible) {
            Button("В корзину", role: .destructive) { deletePendingTask() }
            Button("Отмена", role: .cancel) { taskPendingDeletionID = nil }
        }
        .confirmationDialog("Удалить задачу навсегда?", isPresented: Binding(get: { taskPendingPermanentDeletionID != nil }, set: { if !$0 { taskPendingPermanentDeletionID = nil } }), titleVisibility: .visible) {
            Button("Удалить навсегда", role: .destructive) { permanentlyDeletePendingTask() }
            Button("Отмена", role: .cancel) { taskPendingPermanentDeletionID = nil }
        }
        .alert("Jungo", isPresented: Binding(get: { errorMessage != nil || statusMessage != nil }, set: { if !$0 { errorMessage = nil; statusMessage = nil } })) {
            Button("ОК") { errorMessage = nil; statusMessage = nil }
        } message: {
            Text(errorMessage ?? statusMessage ?? "")
        }
    }

    private var sidebar: some View {
        List(selection: $selectedBoardID) {
            Section("Доски") {
                ForEach(boards.sorted(by: { $0.sortOrder < $1.sortOrder })) { board in
                    Label(board.title, systemImage: "rectangle.split.3x1")
                        .tag(board.id)
                        .contextMenu {
                            Button("Переименовать") {
                                editingBoardID = board.id
                                nameInput = board.title
                                isNamingBoard = true
                            }
                            Button("Удалить доску…", role: .destructive) {
                                selectedBoardID = board.id
                                showDeleteBoardConfirmation = true
                            }
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Jungo")
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                Button {
                    editingBoardID = nil
                    nameInput = ""
                    isNamingBoard = true
                } label: {
                    Label("Новая доска", systemImage: "plus").frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                HStack(spacing: 8) {
                    Button(action: exportArchive) { Label("Экспорт", systemImage: "square.and.arrow.up") }
                    Button(action: importArchive) { Label("Импорт", systemImage: "square.and.arrow.down") }
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            .padding()
        }
        .alert("Название доски", isPresented: $isNamingBoard) {
            TextField("Название", text: $nameInput)
            Button("Отмена", role: .cancel) { nameInput = ""; editingBoardID = nil }
            Button("Сохранить", action: saveBoardName).disabled(nameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func boardWorkspace(_ board: Board) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(showTrash ? "Корзина" : board.title).font(.largeTitle.weight(.bold))
                    Text(showTrash ? "\(trashedTasks(for: board).count) в корзине" : "\(visibleColumns.reduce(0) { $0 + tasks(in: $1).count }) задач")
                        .foregroundStyle(.secondary).font(.subheadline)
                }
                Spacer()
                if showTrash {
                    Button("Вернуться к доске", systemImage: "arrow.uturn.backward") { showTrash = false }
                        .buttonStyle(.bordered)
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Поиск задач", text: $searchText).textFieldStyle(.plain).frame(width: 145)
                            .focused($isSearchFocused)
                            .accessibilityLabel("Поиск задач")
                    }
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 9))
                    Picker("Приоритет", selection: $priorityFilter) {
                        ForEach(PriorityFilter.allCases) { filter in Text(filter.title).tag(filter) }
                    }
                    .labelsHidden().frame(width: 145)
                    Toggle(isOn: $showOverdueOnly) {
                        Image(systemName: "calendar.badge.exclamationmark")
                    }
                    .toggleStyle(.button).help("Только просроченные задачи")
                    .accessibilityLabel("Только просроченные задачи")
                    Button(action: { if let first = visibleColumns.first { createTask(in: first) } }) {
                        Label("Новая задача", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(22)
            Divider()
            if showTrash {
                trashWorkspace(for: board)
            } else if visibleColumns.isEmpty {
                ContentUnavailableView("Пока нет колонок", systemImage: "rectangle.split.3x1")
            } else {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(visibleColumns) { column in columnView(column).frame(width: 270) }
                        addColumnTile
                    }
                    .padding(20)
                }
            }
            Spacer(minLength: 0)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showQuickAdd) {
            QuickAddTaskSheet(
                columns: visibleColumns,
                initialColumnID: visibleColumns.first?.id,
                onCreate: createQuickTask
            )
        }
        .toolbar {
            ToolbarItemGroup {
                Menu {
                    Button(showTrash ? "Вернуться к доске" : "Открыть корзину (\(trashedTasks(for: board).count))", systemImage: showTrash ? "arrow.uturn.backward" : "trash") {
                        showTrash.toggle()
                    }
                    if !showTrash {
                        Button("Быстро добавить задачу…", systemImage: "text.badge.plus") {
                            showQuickAdd = true
                        }
                        .disabled(visibleColumns.isEmpty)
                        Menu {
                            Button {
                                selectedLabel = ""
                            } label: {
                                Label("Все метки", systemImage: selectedLabel.isEmpty ? "checkmark" : "tag")
                            }
                            ForEach(availableLabels, id: \.self) { label in
                                Button {
                                    selectedLabel = label
                                } label: {
                                    if selectedLabel == label {
                                        Label(label, systemImage: "checkmark")
                                    } else {
                                        Text(label)
                                    }
                                }
                            }
                        } label: {
                            Label(selectedLabel.isEmpty ? "Фильтр по метке" : selectedLabel, systemImage: "tag")
                        }
                        .disabled(availableLabels.isEmpty)
                    }
                    Divider()
                    if !showTrash {
                        Button("Добавить колонку", action: beginAddColumn)
                    }
                    Button("Экспортировать данные…", action: exportArchive)
                    Button("Импортировать данные…", action: importArchive)
                    Divider()
                    Button("Удалить доску…", role: .destructive) { showDeleteBoardConfirmation = true }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .alert("Название колонки", isPresented: $isNamingColumn) {
            TextField("Название", text: $nameInput)
            Button("Отмена", role: .cancel) { nameInput = ""; editingColumnID = nil }
            Button("Сохранить", action: saveColumnName).disabled(nameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var addColumnTile: some View {
        Button(action: beginAddColumn) {
            Label("Добавить колонку", systemImage: "plus")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .foregroundStyle(.secondary)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .frame(width: 220)
    }

    private func columnView(_ column: BoardColumn) -> some View {
        let columnTasks = tasks(in: column)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle().fill(columnColor(column.sortOrder)).frame(width: 8, height: 8)
                Text(column.title).font(.headline).lineLimit(1)
                Text("\(columnTasks.count)").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2).background(.quaternary, in: Capsule())
                Spacer()
                Menu {
                    Button("Переименовать") {
                        editingColumnID = column.id
                        nameInput = column.title
                        isNamingColumn = true
                    }
                    Button("Переместить влево", systemImage: "arrow.left") { moveColumn(column, by: -1) }
                        .disabled(column.sortOrder == 0)
                    Button("Переместить вправо", systemImage: "arrow.right") { moveColumn(column, by: 1) }
                        .disabled(column.sortOrder >= visibleColumns.count - 1)
                    Divider()
                    Button("Добавить задачу", systemImage: "plus") { createTask(in: column) }
                    Button("Удалить колонку…", role: .destructive) { columnPendingDeletionID = column.id }
                        .disabled(visibleColumns.count <= 1)
                } label: {
                    Image(systemName: "ellipsis").foregroundStyle(.secondary).frame(width: 24, height: 24)
                }
                .menuStyle(.borderlessButton)
            }
            ForEach(columnTasks) { task in
                Button {
                    selectedTask = task
                } label: {
                    TaskCardView(task: task, checklistItems: allChecklistItems.filter { $0.taskID == task.id }.sorted { $0.sortOrder < $1.sortOrder })
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Задача: \(task.title), приоритет: \(task.priority.title)")
                .draggable(task.id.uuidString)
                    .dropDestination(for: String.self) { identifiers, _ in
                        guard let rawID = identifiers.first, let draggedID = UUID(uuidString: rawID) else { return false }
                        moveTask(draggedID, to: column, before: task.id)
                        return true
                    }
                    .contextMenu {
                        Button("Редактировать") { selectedTask = task }
                        Menu("Переместить в") {
                            ForEach(visibleColumns.filter { $0.id != column.id }) { destination in
                                Button(destination.title) { moveTask(task.id, to: destination, before: nil) }
                            }
                        }
                        Divider()
                        Button("Удалить…", role: .destructive) { taskPendingDeletionID = task.id }
                    }
            }
            Button { createTask(in: column) } label: {
                Label("Добавить задачу", systemImage: "plus")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(.quaternary, lineWidth: 1) }
        .dropDestination(for: String.self) { identifiers, _ in
            guard let rawID = identifiers.first, let draggedID = UUID(uuidString: rawID) else { return false }
            moveTask(draggedID, to: column, before: nil)
            return true
        }
    }

    private func tasks(in column: BoardColumn) -> [TaskCard] {
        allTasks.filter { task in
            guard task.columnID == column.id, !task.isInTrash else { return false }
            let matchesSearch = searchText.isEmpty ||
                task.title.localizedCaseInsensitiveContains(searchText) ||
                task.details.localizedCaseInsensitiveContains(searchText) ||
                task.labels.contains { $0.localizedCaseInsensitiveContains(searchText) }
            let matchesPriority = priorityFilter.value == nil || task.priority == priorityFilter.value
            let matchesLabel = selectedLabel.isEmpty || task.labels.contains { $0.caseInsensitiveCompare(selectedLabel) == .orderedSame }
            let matchesOverdue = !showOverdueOnly || (task.dueDate.map { $0 < Calendar.current.startOfDay(for: .now) } ?? false)
            return matchesSearch && matchesPriority && matchesLabel && matchesOverdue
        }.sorted { $0.sortOrder < $1.sortOrder }
    }

    private func createTask(in column: BoardColumn) {
        let task = TaskCard(title: "Новая задача", sortOrder: tasks(in: column).count, columnID: column.id)
        modelContext.insert(task)
        guard saveChanges() else { return }
        selectedTask = task
    }

    private func createQuickTask(title: String, details: String, columnID: UUID) -> Bool {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty, let column = visibleColumns.first(where: { $0.id == columnID }) else { return false }
        let task = TaskCard(title: cleanTitle, details: details.trimmingCharacters(in: .whitespacesAndNewlines), sortOrder: tasks(in: column).count, columnID: column.id)
        modelContext.insert(task)
        guard saveChanges() else { return false }
        statusMessage = "Задача «\(cleanTitle)» создана."
        return true
    }

    private func moveTask(_ taskID: UUID, to destination: BoardColumn, before targetID: UUID?) {
        guard let task = allTasks.first(where: { $0.id == taskID }), !task.isInTrash, task.id != targetID,
              let destinationBoard = boards.first(where: { $0.id == destination.boardID }),
              destinationBoard.id == selectedBoard?.id else { return }

        let sourceColumnID = task.columnID
        var sourceTasks = allTasks.filter { $0.columnID == sourceColumnID && $0.id != taskID && !$0.isInTrash }.sorted { $0.sortOrder < $1.sortOrder }
        var destinationTasks = allTasks.filter { $0.columnID == destination.id && $0.id != taskID && !$0.isInTrash }.sorted { $0.sortOrder < $1.sortOrder }
        let insertion: Int
        if let targetID, let targetIndex = destinationTasks.firstIndex(where: { $0.id == targetID }) {
            insertion = targetIndex
        } else {
            insertion = destinationTasks.count
        }
        task.columnID = destination.id
        destinationTasks.insert(task, at: min(insertion, destinationTasks.count))
        for (index, item) in destinationTasks.enumerated() { item.sortOrder = index }
        for (index, item) in sourceTasks.enumerated() { item.sortOrder = index }
        if sourceColumnID == destination.id {
            sourceTasks = destinationTasks
            for (index, item) in sourceTasks.enumerated() { item.sortOrder = index }
        }
        _ = saveChanges()
    }

    private func beginAddColumn() {
        editingColumnID = nil
        nameInput = ""
        isNamingColumn = true
    }

    private func saveColumnName() {
        let title = nameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let board = selectedBoard else { return }
        if let editingColumnID, let column = visibleColumns.first(where: { $0.id == editingColumnID }) {
            column.title = title
        } else {
            modelContext.insert(BoardColumn(title: title, sortOrder: visibleColumns.count, boardID: board.id))
        }
        nameInput = ""
        editingColumnID = nil
        _ = saveChanges()
    }

    private func moveColumn(_ column: BoardColumn, by offset: Int) {
        var ordered = visibleColumns
        guard let index = ordered.firstIndex(where: { $0.id == column.id }) else { return }
        let destination = index + offset
        guard ordered.indices.contains(destination) else { return }
        ordered.swapAt(index, destination)
        for (order, item) in ordered.enumerated() { item.sortOrder = order }
        _ = saveChanges()
    }

    private func deletePendingColumn() {
        defer { columnPendingDeletionID = nil }
        guard let id = columnPendingDeletionID,
              let column = visibleColumns.first(where: { $0.id == id }),
              visibleColumns.count > 1,
              let destination = visibleColumns.first(where: { $0.id != id }) else { return }
        let movingTasks = allTasks.filter { $0.columnID == column.id }.sorted { $0.sortOrder < $1.sortOrder }
        let start = allTasks.filter { $0.columnID == destination.id }.count
        for (offset, task) in movingTasks.enumerated() {
            task.columnID = destination.id
            task.sortOrder = start + offset
        }
        modelContext.delete(column)
        let remaining = visibleColumns.filter { $0.id != id }
        for (index, item) in remaining.enumerated() { item.sortOrder = index }
        _ = saveChanges()
    }

    private func deletePendingTask() {
        defer { taskPendingDeletionID = nil }
        guard let id = taskPendingDeletionID, let task = allTasks.first(where: { $0.id == id }) else { return }
        task.isInTrash = true
        let remaining = allTasks.filter { $0.columnID == task.columnID && $0.id != id && !$0.isInTrash }.sorted { $0.sortOrder < $1.sortOrder }
        for (index, item) in remaining.enumerated() { item.sortOrder = index }
        _ = saveChanges()
    }

    private func trashedTasks(for board: Board) -> [TaskCard] {
        let columnIDs = Set(allColumns.filter { $0.boardID == board.id }.map(\.id))
        return allTasks.filter { $0.isInTrash && columnIDs.contains($0.columnID) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private func restoreTask(_ task: TaskCard) {
        task.isInTrash = false
        let existing = allTasks.filter { $0.columnID == task.columnID && $0.id != task.id && !$0.isInTrash }
        task.sortOrder = existing.count
        if saveChanges() {
            statusMessage = "Задача восстановлена."
        }
    }

    private func permanentlyDeletePendingTask() {
        defer { taskPendingPermanentDeletionID = nil }
        guard let id = taskPendingPermanentDeletionID,
              let task = allTasks.first(where: { $0.id == id }),
              task.isInTrash else { return }
        for item in allChecklistItems where item.taskID == id { modelContext.delete(item) }
        modelContext.delete(task)
        if saveChanges() {
            statusMessage = "Задача удалена навсегда."
        }
    }

    private func trashWorkspace(for board: Board) -> some View {
        let tasks = trashedTasks(for: board)
        return Group {
            if tasks.isEmpty {
                ContentUnavailableView("Корзина пуста", systemImage: "trash", description: Text("Удалённые задачи можно будет восстановить здесь."))
            } else {
                List {
                    ForEach(tasks) { task in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(task.title).font(.headline)
                                if !task.details.isEmpty {
                                    Text(task.details).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                                Text("Доска: \(board.title) · Удалена в корзину")
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Button("Восстановить", systemImage: "arrow.uturn.backward") {
                                restoreTask(task)
                            }
                            .buttonStyle(.bordered)
                            Button(role: .destructive) {
                                taskPendingPermanentDeletionID = task.id
                            } label: {
                                Image(systemName: "trash.slash")
                            }
                            .buttonStyle(.borderless)
                            .help("Удалить навсегда")
                            .accessibilityLabel("Удалить задачу навсегда: \(task.title)")
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private func saveBoardName() {
        let title = nameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        if let editingBoardID, let board = boards.first(where: { $0.id == editingBoardID }) {
            board.title = title
        } else {
            let board = Board(title: title, sortOrder: boards.count)
            modelContext.insert(board)
            for (index, title) in ["К выполнению", "В работе", "Готово"].enumerated() {
                modelContext.insert(BoardColumn(title: title, sortOrder: index, boardID: board.id))
            }
            selectedBoardID = board.id
        }
        nameInput = ""
        editingBoardID = nil
        _ = saveChanges()
    }

    private func deleteSelectedBoard() {
        guard let board = selectedBoard else { return }
        let columns = allColumns.filter { $0.boardID == board.id }
        let taskIDs = Set(allTasks.filter { task in columns.contains(where: { $0.id == task.columnID }) }.map(\.id))
        for item in allChecklistItems where taskIDs.contains(item.taskID) { modelContext.delete(item) }
        for task in allTasks where taskIDs.contains(task.id) { modelContext.delete(task) }
        for column in columns { modelContext.delete(column) }
        modelContext.delete(board)
        selectedBoardID = boards.first(where: { $0.id != board.id })?.id
        _ = saveChanges()
    }

    private func seedIfNeeded() {
        guard boards.isEmpty else {
            if let restoredID = UUID(uuidString: persistedSelectedBoardID), boards.contains(where: { $0.id == restoredID }) {
                selectedBoardID = restoredID
            } else if selectedBoardID == nil {
                selectedBoardID = boards.sorted(by: { $0.sortOrder < $1.sortOrder }).first?.id
            }
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
        _ = saveChanges()
    }

    @discardableResult
    private func saveChanges() -> Bool {
        do {
            try modelContext.save()
            return true
        } catch {
            errorMessage = "Не удалось сохранить изменения: \(error.localizedDescription)"
            return false
        }
    }

    private func exportArchive() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Jungo-Backup-\(Date.now.formatted(.iso8601.year().month().day())).json"
        panel.title = "Экспортировать данные Jungo"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let archive = JungoArchive.capture(boards: boards, columns: allColumns, tasks: allTasks, checklistItems: allChecklistItems)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(archive).write(to: url, options: .atomic)
            statusMessage = "Экспорт завершён: \(url.lastPathComponent)"
        } catch {
            errorMessage = "Не удалось экспортировать данные: \(error.localizedDescription)"
        }
    }

    private func importArchive() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Импортировать архив Jungo"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let archive = try decoder.decode(JungoArchive.self, from: Data(contentsOf: url))
            try archive.importInto(modelContext)
            selectedBoardID = boards.sorted(by: { $0.sortOrder < $1.sortOrder }).last?.id
            statusMessage = "Импортировано досок: \(archive.boards.count). Существующие данные не заменялись."
        } catch {
            errorMessage = "Не удалось импортировать архив: \(error.localizedDescription)"
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
    let checklistItems: [TaskChecklistItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(task.title).font(.system(size: 14, weight: .medium)).foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !task.details.isEmpty {
                Text(task.details).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !task.labels.isEmpty {
                HStack(spacing: 5) {
                    ForEach(task.labels, id: \.self) { label in
                        TaskLabelPill(label: label)
                    }
                }
            }
            if !checklistItems.isEmpty {
                Label("\(checklistItems.filter(\.isCompleted).count)/\(checklistItems.count)", systemImage: "checklist")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            HStack {
                Label(task.priority.title, systemImage: task.priority.symbol)
                    .font(.caption2)
                    .foregroundStyle(task.priority == .high ? .orange : .secondary)
                Spacer()
                if let dueDate = task.dueDate {
                    Label {
                        Text(dueDate, format: .dateTime.month(.abbreviated).day())
                    } icon: {
                        Image(systemName: "calendar")
                    }
                    .font(.caption2)
                    .foregroundStyle(dueDate < Calendar.current.startOfDay(for: .now) ? .red : .secondary)
                } else {
                    Text(task.createdAt, format: .dateTime.month(.abbreviated).day())
                        .font(.caption2).foregroundStyle(.tertiary)
                }
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
    @Query(sort: \TaskChecklistItem.sortOrder) private var allChecklistItems: [TaskChecklistItem]
    @Bindable var task: TaskCard
    let onSave: () -> Bool
    @State private var hasDueDate = false
    @State private var showDescriptionPreview = false
    @State private var newChecklistTitle = ""

    private var checklistItems: [TaskChecklistItem] {
        allChecklistItems.filter { $0.taskID == task.id }.sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Задача").font(.title2.bold())
            TextField("Название", text: $task.title).textFieldStyle(.roundedBorder).font(.title3)
            TextField("Метки через запятую", text: $task.labelsText).textFieldStyle(.roundedBorder)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Описание").font(.subheadline.weight(.medium))
                    Spacer()
                    Picker("Режим описания", selection: $showDescriptionPreview) {
                        Text("Редактировать").tag(false)
                        Text("Просмотр Markdown").tag(true)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 210)
                }
                if showDescriptionPreview {
                    ScrollView {
                        Group {
                            if let rendered = try? AttributedString(markdown: task.details) {
                                Text(rendered)
                            } else {
                                Text(task.details)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                    }
                    .frame(minHeight: 120)
                    .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
                } else {
                    TextEditor(text: $task.details).frame(minHeight: 120).padding(4)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                }
            }
            Picker("Приоритет", selection: $task.priority) {
                ForEach(TaskPriority.allCases) { priority in Text(priority.title).tag(priority) }
            }
            .pickerStyle(.segmented)
            Toggle("Установить срок", isOn: $hasDueDate)
                .onChange(of: hasDueDate) { _, enabled in if enabled && task.dueDate == nil { task.dueDate = .now }; if !enabled { task.dueDate = nil } }
            if hasDueDate {
                DatePicker("Срок", selection: Binding(get: { task.dueDate ?? .now }, set: { task.dueDate = $0 }), displayedComponents: .date)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Чек-лист").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(checklistItems.filter(\.isCompleted).count)/\(checklistItems.count)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(checklistItems) { item in
                    ChecklistItemRow(item: item, onSave: onSave)
                }
                HStack {
                    TextField("Новый пункт", text: $newChecklistTitle)
                        .textFieldStyle(.roundedBorder)
                    Button("Добавить", systemImage: "plus", action: addChecklistItem)
                        .disabled(newChecklistTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            HStack {
                Spacer()
                Button("Отмена", role: .cancel) { dismiss() }
                Button("Сохранить") {
                    if onSave() { dismiss() }
                }
                .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 460)
        .onAppear { hasDueDate = task.dueDate != nil }
    }

    private func addChecklistItem() {
        let title = newChecklistTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        modelContext.insert(TaskChecklistItem(title: title, sortOrder: checklistItems.count, taskID: task.id))
        newChecklistTitle = ""
        _ = onSave()
    }
}

private struct ChecklistItemRow: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var item: TaskChecklistItem
    let onSave: () -> Bool

    var body: some View {
        HStack(spacing: 8) {
            Toggle(isOn: $item.isCompleted) {
                Text(item.title).strikethrough(item.isCompleted).foregroundStyle(item.isCompleted ? .secondary : .primary)
            }
            .toggleStyle(.checkbox)
            Button(role: .destructive) {
                modelContext.delete(item)
                _ = onSave()
            } label: {
                Image(systemName: "xmark.circle").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Удалить пункт")
        }
        .onChange(of: item.isCompleted) { _, _ in _ = onSave() }
    }
}


private struct TaskLabelPill: View {
    let label: String

    private var tint: Color {
        let hash = label.unicodeScalars.reduce(0) { ($0 * 31 + Int($1.value)) % 997 }
        let palette: [Color] = [.blue, .purple, .green, .orange, .pink, .teal, .indigo]
        return palette[hash % palette.count]
    }

    var body: some View {
        Text(label)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(tint)
            .background(tint.opacity(0.13), in: Capsule())
            .accessibilityLabel("Метка: \(label)")
    }
}


private struct QuickAddTaskSheet: View {
    @Environment(\.dismiss) private var dismiss
    let columns: [BoardColumn]
    let onCreate: (String, String, UUID) -> Bool

    @State private var title = ""
    @State private var details = ""
    @State private var selectedColumnID: UUID?

    init(columns: [BoardColumn], initialColumnID: UUID?, onCreate: @escaping (String, String, UUID) -> Bool) {
        self.columns = columns
        self.onCreate = onCreate
        _selectedColumnID = State(initialValue: initialColumnID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Быстро добавить задачу").font(.title2.bold())
            TextField("Название задачи", text: $title)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
            TextField("Описание (необязательно)", text: $details)
                .textFieldStyle(.roundedBorder)
            Picker("Колонка", selection: $selectedColumnID) {
                ForEach(columns) { column in
                    Text(column.title).tag(Optional(column.id))
                }
            }
            .disabled(columns.isEmpty)
            HStack {
                Spacer()
                Button("Отмена", role: .cancel) { dismiss() }
                Button("Создать") {
                    guard let selectedColumnID, onCreate(title, details, selectedColumnID) else { return }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedColumnID == nil)
            }
        }
        .padding(24)
        .frame(width: 440)
        .onAppear {
            if selectedColumnID == nil { selectedColumnID = columns.first?.id }
        }
    }
}
