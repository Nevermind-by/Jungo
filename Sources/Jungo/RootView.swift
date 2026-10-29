import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
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
    @AppStorage("jungo.savedTaskFiltersJSON") private var savedTaskFiltersJSON = "[]"
    @State private var showSaveTaskFilter = false
    @State private var showManageSavedFilters = false
    @State private var showLabelColorSettings = false
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
        boards.first(where: { $0.id == selectedBoardID })
            ?? boards.filter { !$0.isArchived }.sorted { $0.sortOrder < $1.sortOrder }.first
            ?? boards.sorted { $0.sortOrder < $1.sortOrder }.first
    }

    private var activeBoards: [Board] {
        boards.filter { !$0.isArchived }.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var archivedBoards: [Board] {
        boards.filter(\.isArchived).sorted { $0.sortOrder < $1.sortOrder }
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

    private var savedTaskFilters: [SavedTaskFilter] {
        guard let data = savedTaskFiltersJSON.data(using: .utf8),
              let filters = try? JSONDecoder().decode([SavedTaskFilter].self, from: data) else {
            return []
        }
        return filters.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var hasActiveFilters: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || priorityFilter != .all
            || !selectedLabel.isEmpty
            || showOverdueOnly
    }

    private func applySavedFilter(_ filter: SavedTaskFilter) {
        searchText = filter.searchText
        priorityFilter = PriorityFilter(rawValue: filter.priorityRawValue) ?? .all
        selectedLabel = filter.label
        showOverdueOnly = filter.showOverdueOnly
        showTrash = false
    }

    private func saveTaskFilter(named name: String) {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { return }
        var filters = savedTaskFilters
        filters.removeAll { $0.name.localizedCaseInsensitiveCompare(normalizedName) == .orderedSame }
        filters.append(SavedTaskFilter(
            id: UUID(),
            name: normalizedName,
            searchText: searchText,
            priorityRawValue: priorityFilter.rawValue,
            label: selectedLabel,
            showOverdueOnly: showOverdueOnly
        ))
        guard let data = try? JSONEncoder().encode(filters),
              let json = String(data: data, encoding: .utf8) else {
            errorMessage = "Не удалось сохранить фильтр."
            return
        }
        savedTaskFiltersJSON = json
        statusMessage = "Фильтр «\(normalizedName)» сохранён."
    }

    private func deleteSavedFilter(_ filter: SavedTaskFilter) {
        let filters = savedTaskFilters.filter { $0.id != filter.id }
        guard let data = try? JSONEncoder().encode(filters),
              let json = String(data: data, encoding: .utf8) else { return }
        savedTaskFiltersJSON = json
    }

    private func clearFilters() {
        searchText = ""
        priorityFilter = .all
        selectedLabel = ""
        showOverdueOnly = false
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            if let board = selectedBoard {
                boardWorkspace(board)
            } else {
                VStack(spacing: 14) {
                    ContentUnavailableView(
                        "Создай первую доску",
                        systemImage: "rectangle.split.3x1",
                        description: Text("Jungo хранит задачи локально на этом Mac.")
                    )
                    Button("Создать первую доску", systemImage: "plus") {
                        editingBoardID = nil
                        nameInput = ""
                        isNamingBoard = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .task {
            seedIfNeeded()
            if UserDefaults.standard.bool(forKey: "jungo.pendingQuickCapture") {
                UserDefaults.standard.set(false, forKey: "jungo.pendingQuickCapture")
                showQuickAdd = true
            }
        }
        .onAppear {
            GlobalHotKeyManager.shared.configure(openWindow: { openWindow(id: "main") })
        }
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
        .sheet(isPresented: $showSaveTaskFilter) {
            SaveTaskFilterSheet { name in saveTaskFilter(named: name) }
        }
        .sheet(isPresented: $showManageSavedFilters) {
            ManageSavedFiltersSheet(
                filters: savedTaskFilters,
                onSelect: applySavedFilter,
                onDelete: deleteSavedFilter
            )
        }
        .sheet(isPresented: $showLabelColorSettings) {
            LabelColorSettingsSheet(labels: availableLabels)
        }
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
                ForEach(activeBoards) { board in
                    Label(board.title, systemImage: "rectangle.split.3x1")
                        .tag(board.id)
                        .contextMenu {
                            Button("Переименовать") {
                                editingBoardID = board.id
                                nameInput = board.title
                                isNamingBoard = true
                            }
                            Button("Дублировать доску", systemImage: "plus.square.on.square") {
                                duplicateBoard(board)
                            }
                            Button("В архив", systemImage: "archivebox") {
                                archiveBoard(board)
                            }
                            Button("Удалить доску…", role: .destructive) {
                                selectedBoardID = board.id
                                showDeleteBoardConfirmation = true
                            }
                        }
                }
            }
            if !archivedBoards.isEmpty {
                Section("Архив · \(archivedBoards.count)") {
                    ForEach(archivedBoards) { board in
                        Label(board.title, systemImage: "archivebox")
                            .tag(board.id)
                            .foregroundStyle(.secondary)
                            .contextMenu {
                                Button("Восстановить из архива", systemImage: "arrow.uturn.backward") {
                                    restoreBoardFromArchive(board)
                                }
                                Button("Дублировать доску", systemImage: "plus.square.on.square") {
                                    duplicateBoard(board)
                                }
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
                    Label("Новая доска", systemImage: "plus")
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .lineLimit(1)
                .padding(.bottom, 2)

                HStack(alignment: .center, spacing: 10) {
                    Button(action: exportArchive) {
                        Label {
                            Text("Экспорт")
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "square.and.arrow.up")
                                .frame(width: 15)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .contentShape(Rectangle())
                    }
                    .help("Экспортировать резервную копию")

                    Button(action: importArchive) {
                        Label {
                            Text("Импорт")
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "square.and.arrow.down")
                                .frame(width: 15)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .contentShape(Rectangle())
                    }
                    .help("Импортировать архив")
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11, weight: .medium))
                .controlSize(.small)
            }
            .padding(14)
            .background(.regularMaterial)
        }
        .alert("Название доски", isPresented: $isNamingBoard) {
            TextField("Название", text: $nameInput)
            Button("Отмена", role: .cancel) { nameInput = ""; editingBoardID = nil }
            Button("Сохранить", action: saveBoardName).disabled(nameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func boardWorkspace(_ board: Board) -> some View {
        // Group once per workspace render instead of rescanning every task and
        // checklist for every column/card. This keeps large boards responsive.
        let taskCandidatesByColumn = Dictionary(grouping: allTasks, by: \.columnID)
        let checklistItemsByTask = Dictionary(grouping: allChecklistItems, by: \.taskID)
            .mapValues { $0.sorted { $0.sortOrder < $1.sortOrder } }

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(showTrash ? "Корзина" : board.title).font(.largeTitle.weight(.bold))
                    if board.isArchived && !showTrash {
                        Label("В архиве", systemImage: "archivebox")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    Text(showTrash ? "\(trashedTasks(for: board).count) в корзине" : "\(visibleColumns.reduce(0) { $0 + tasks(in: $1, candidates: taskCandidatesByColumn[$1.id] ?? []).count }) задач")
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
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .jungoGlassPanel(radius: JungoDesign.controlRadius)
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
            .padding(20)
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 12)
            if showTrash {
                trashWorkspace(for: board)
            } else if visibleColumns.isEmpty {
                VStack(spacing: 12) {
                    ContentUnavailableView(
                        "Пока нет колонок",
                        systemImage: "rectangle.split.3x1",
                        description: Text("Добавь колонку, чтобы начать раскладывать задачи.")
                    )
                    Button("Добавить колонку", systemImage: "plus", action: beginAddColumn)
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(visibleColumns) { column in
                            columnView(
                                column,
                                taskCandidates: taskCandidatesByColumn[column.id] ?? [],
                                checklistItemsByTask: checklistItemsByTask
                            )
                            .frame(width: 270)
                        }
                        addColumnTile
                    }
                    .padding(20)
                }
            }
            Spacer(minLength: 0)
        }
        .background {
            JungoCanvasBackground()
        }
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
                            if savedTaskFilters.isEmpty {
                                Text("Нет сохранённых фильтров")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(savedTaskFilters) { filter in
                                    Button {
                                        applySavedFilter(filter)
                                    } label: {
                                        Label(filter.name, systemImage: "line.3.horizontal.decrease.circle")
                                    }
                                }
                                Divider()
                                Button("Управление фильтрами…", systemImage: "slider.horizontal.3") {
                                    showManageSavedFilters = true
                                }
                            }
                            Button("Сохранить текущий фильтр…", systemImage: "bookmark") {
                                showSaveTaskFilter = true
                            }
                            .disabled(!hasActiveFilters)
                        } label: {
                            Label("Сохранённые фильтры", systemImage: "bookmark")
                        }
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
                            Divider()
                            Button("Настроить цвета меток…", systemImage: "paintpalette") {
                                showLabelColorSettings = true
                            }
                        } label: {
                            Label(selectedLabel.isEmpty ? "Фильтр по метке" : selectedLabel, systemImage: "tag")
                        }
                        .disabled(availableLabels.isEmpty)
                        if hasActiveFilters {
                            Button("Сбросить фильтры", systemImage: "xmark.circle") {
                                clearFilters()
                            }
                        }
                    }
                    Divider()
                    if !showTrash {
                        Button("Добавить колонку", action: beginAddColumn)
                        Button("Дублировать доску", systemImage: "plus.square.on.square") {
                            duplicateBoard(board)
                        }
                        if board.isArchived {
                            Button("Восстановить доску из архива", systemImage: "arrow.uturn.backward") {
                                restoreBoardFromArchive(board)
                            }
                        } else {
                            Button("Переместить доску в архив", systemImage: "archivebox") {
                                archiveBoard(board)
                            }
                        }
                    }
                    Button("Экспортировать данные…", action: exportArchive)
                    Button("Импортировать данные…", action: importArchive)
                    Divider()
                    Button("Удалить доску…", role: .destructive) { showDeleteBoardConfirmation = true }
                } label: { Image(systemName: "ellipsis.circle").accessibilityLabel("Действия с доской") }
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
                .jungoGlassPanel(radius: 18)
        }
        .buttonStyle(.plain)
        .frame(width: 220)
    }

    private func taskAccessibilitySummary(for task: TaskCard, checklistItems taskChecklist: [TaskChecklistItem]) -> String {
        let checklistSummary = taskChecklist.isEmpty
            ? ""
            : ", чек-лист: \(taskChecklist.filter(\.isCompleted).count) из \(taskChecklist.count) выполнено"
        let labelsSummary = task.labels.isEmpty
            ? ""
            : ", метки: \(task.labels.joined(separator: ", "))"
        let dueDateSummary = task.dueDate.map {
            ", срок: \($0.formatted(date: .abbreviated, time: .omitted))"
        } ?? ""
        return "Задача: \(task.title), приоритет: \(task.priority.title)\(dueDateSummary)\(labelsSummary)\(checklistSummary)"
    }

    private func columnView(
        _ column: BoardColumn,
        taskCandidates: [TaskCard],
        checklistItemsByTask: [UUID: [TaskChecklistItem]]
    ) -> some View {
        let columnTasks = tasks(in: column, candidates: taskCandidates)
        let hasTasksBeforeFilters = taskCandidates.contains { !$0.isInTrash }
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
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .accessibilityLabel("Действия с колонкой \(column.title)")
                }
                .menuStyle(.borderlessButton)
            }
            if columnTasks.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: hasTasksBeforeFilters && hasActiveFilters ? "line.3.horizontal.decrease.circle" : "tray")
                        .font(.title2)
                    Text(hasTasksBeforeFilters && hasActiveFilters ? "Нет совпадений" : "Пока нет задач")
                        .font(.subheadline.weight(.medium))
                    Text(hasTasksBeforeFilters && hasActiveFilters
                         ? "Измени условия или сбрось фильтры."
                         : "Добавь первую задачу в эту колонку.")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                    if hasTasksBeforeFilters && hasActiveFilters {
                        Button("Сбросить фильтры", action: clearFilters)
                            .buttonStyle(.bordered)
                    } else {
                        Button("Создать первую задачу", systemImage: "plus") {
                            createTask(in: column)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            }
            ForEach(columnTasks) { task in
                Button {
                    selectedTask = task
                } label: {
                    TaskCardView(task: task, checklistItems: checklistItemsByTask[task.id] ?? [])
                }
                .buttonStyle(.plain)
                .accessibilityLabel(taskAccessibilitySummary(for: task, checklistItems: checklistItemsByTask[task.id] ?? []))
                .accessibilityHint("Используй стрелки, чтобы менять порядок задачи или перемещать её между колонками.")
                .onMoveCommand { direction in
                    moveTask(task, using: direction)
                }
                .draggable(task.id.uuidString)
                    .dropDestination(for: String.self) { identifiers, _ in
                        guard let rawID = identifiers.first, let draggedID = UUID(uuidString: rawID) else { return false }
                        moveTask(draggedID, to: column, before: task.id)
                        return true
                    }
                    .contextMenu {
                        Button("Редактировать") { selectedTask = task }
                        Button("Дублировать задачу", systemImage: "plus.square.on.square") {
                            duplicateTask(task)
                        }
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
        .jungoTaskSurface(radius: 20)
        .dropDestination(for: String.self) { identifiers, _ in
            guard let rawID = identifiers.first, let draggedID = UUID(uuidString: rawID) else { return false }
            moveTask(draggedID, to: column, before: nil)
            return true
        }
    }

    private func tasks(in column: BoardColumn, candidates: [TaskCard]? = nil) -> [TaskCard] {
        let normalizedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return (candidates ?? allTasks).filter { task in
            guard task.columnID == column.id, !task.isInTrash else { return false }
            let matchesSearch = normalizedSearchText.isEmpty ||
                task.title.localizedCaseInsensitiveContains(normalizedSearchText) ||
                task.details.localizedCaseInsensitiveContains(normalizedSearchText) ||
                task.labels.contains { $0.localizedCaseInsensitiveContains(normalizedSearchText) }
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

    private func duplicateBoard(_ source: Board) {
        let sourceColumns = allColumns
            .filter { $0.boardID == source.id }
            .sorted { $0.sortOrder < $1.sortOrder }
        let sourceColumnIDs = Set(sourceColumns.map(\.id))
        let sourceTasks = allTasks
            .filter { sourceColumnIDs.contains($0.columnID) && !$0.isInTrash }
            .sorted { lhs, rhs in
                guard lhs.columnID == rhs.columnID else {
                    let leftOrder = sourceColumns.first(where: { $0.id == lhs.columnID })?.sortOrder ?? 0
                    let rightOrder = sourceColumns.first(where: { $0.id == rhs.columnID })?.sortOrder ?? 0
                    return leftOrder < rightOrder
                }
                return lhs.sortOrder < rhs.sortOrder
            }

        let nextBoardOrder = (boards.map(\.sortOrder).max() ?? -1) + 1
        let duplicate = Board(title: "Копия: \(source.title)", sortOrder: nextBoardOrder)
        modelContext.insert(duplicate)

        var columnIDMap: [UUID: UUID] = [:]
        for column in sourceColumns {
            let copy = BoardColumn(title: column.title, sortOrder: column.sortOrder, boardID: duplicate.id)
            modelContext.insert(copy)
            columnIDMap[column.id] = copy.id
        }

        var taskIDMap: [UUID: UUID] = [:]
        for task in sourceTasks {
            guard let newColumnID = columnIDMap[task.columnID] else { continue }
            let copy = TaskCard(
                title: task.title,
                details: task.details,
                labelsText: task.labelsText,
                priority: task.priority,
                sortOrder: task.sortOrder,
                columnID: newColumnID,
                dueDate: task.dueDate
            )
            // Preserve unknown raw values even when the current UI falls back
            // to .normal for priorities introduced by a newer app version.
            copy.priorityRawValue = task.priorityRawValue
            modelContext.insert(copy)
            taskIDMap[task.id] = copy.id
        }

        let sourceChecklist = allChecklistItems
            .filter { taskIDMap[$0.taskID] != nil }
            .sorted { $0.sortOrder < $1.sortOrder }
        for item in sourceChecklist {
            guard let newTaskID = taskIDMap[item.taskID] else { continue }
            modelContext.insert(TaskChecklistItem(
                title: item.title,
                isCompleted: false,
                sortOrder: item.sortOrder,
                taskID: newTaskID
            ))
        }

        guard saveChanges() else { return }
        selectedBoardID = duplicate.id
        selectedTask = nil
        showTrash = false
        clearFilters()
        statusMessage = "Создана копия доски «\(source.title)»."
    }

    private func duplicateTask(_ source: TaskCard) {
        guard !source.isInTrash,
              let column = allColumns.first(where: { $0.id == source.columnID }),
              column.boardID == selectedBoard?.id else { return }

        let columnTasks = allTasks
            .filter { $0.columnID == source.columnID && !$0.isInTrash }
            .sorted { $0.sortOrder < $1.sortOrder }
        guard let sourceIndex = columnTasks.firstIndex(where: { $0.id == source.id }) else { return }

        let duplicate = TaskCard(
            title: "Копия: \(source.title)",
            details: source.details,
            labelsText: source.labelsText,
            priority: source.priority,
            sortOrder: source.sortOrder + 1,
            columnID: source.columnID,
            dueDate: source.dueDate
        )
        // Duplication must not normalize a priority value this app doesn't know.
        duplicate.priorityRawValue = source.priorityRawValue
        modelContext.insert(duplicate)

        var reorderedTasks = columnTasks
        reorderedTasks.insert(duplicate, at: sourceIndex + 1)
        for (index, task) in reorderedTasks.enumerated() {
            task.sortOrder = index
        }

        let sourceChecklist = allChecklistItems
            .filter { $0.taskID == source.id }
            .sorted { $0.sortOrder < $1.sortOrder }
        for item in sourceChecklist {
            modelContext.insert(TaskChecklistItem(
                title: item.title,
                isCompleted: false,
                sortOrder: item.sortOrder,
                taskID: duplicate.id
            ))
        }

        guard saveChanges() else { return }
        selectedTask = duplicate
        statusMessage = "Создана копия задачи «\(source.title)»."
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
        guard let task = allTasks.first(where: { $0.id == taskID }),
              !task.isInTrash,
              task.id != targetID,
              let destinationBoard = boards.first(where: { $0.id == destination.boardID }),
              destinationBoard.id == selectedBoard?.id else { return }

        let sourceColumnID = task.columnID
        let isReorderingWithinColumn = sourceColumnID == destination.id

        // Scan the fetched tasks once, rather than filtering the entire collection
        // separately for source and destination on every drop.
        var sourceTasks: [TaskCard] = []
        var destinationTasks: [TaskCard] = []
        for candidate in allTasks where !candidate.isInTrash && candidate.id != taskID {
            if candidate.columnID == sourceColumnID {
                sourceTasks.append(candidate)
            }
            if candidate.columnID == destination.id {
                destinationTasks.append(candidate)
            }
        }

        if isReorderingWithinColumn {
            destinationTasks.sort { $0.sortOrder < $1.sortOrder }
        } else {
            sourceTasks.sort { $0.sortOrder < $1.sortOrder }
            destinationTasks.sort { $0.sortOrder < $1.sortOrder }
        }

        let insertion: Int
        if let targetID, let targetIndex = destinationTasks.firstIndex(where: { $0.id == targetID }) {
            insertion = targetIndex
        } else {
            insertion = destinationTasks.count
        }

        // Reordering a SwiftData-backed ForEach with implicit animations can
        // make a drop feel sticky. Apply the whole relationship/order update
        // as one non-animated transaction, then persist once.
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            if !isReorderingWithinColumn {
                task.columnID = destination.id
            }
            destinationTasks.insert(task, at: min(insertion, destinationTasks.count))
            for (index, item) in destinationTasks.enumerated() {
                item.sortOrder = index
            }
            if !isReorderingWithinColumn {
                for (index, item) in sourceTasks.enumerated() {
                    item.sortOrder = index
                }
            }
        }

        _ = saveChanges()
    }

    /// Supports keyboard-only task management while a task card has focus.
    /// Up/Down reorders within the current column; Left/Right moves to an adjacent column.
    private func moveTask(_ task: TaskCard, using direction: MoveCommandDirection) {
        guard !showTrash, !hasActiveFilters,
              let sourceIndex = visibleColumns.firstIndex(where: { $0.id == task.columnID }) else { return }

        switch direction {
        case .up, .down:
            let ordered = allTasks
                .filter { $0.columnID == task.columnID && !$0.isInTrash }
                .sorted { $0.sortOrder < $1.sortOrder }
            guard let currentIndex = ordered.firstIndex(where: { $0.id == task.id }) else { return }
            let targetIndex = currentIndex + (direction == .up ? -1 : 1)
            guard ordered.indices.contains(targetIndex) else { return }

            var reordered = ordered
            reordered.swapAt(currentIndex, targetIndex)
            for (index, item) in reordered.enumerated() {
                item.sortOrder = index
            }
            _ = saveChanges()

        case .left:
            guard sourceIndex > 0 else { return }
            moveTask(task.id, to: visibleColumns[sourceIndex - 1], before: nil)

        case .right:
            guard sourceIndex + 1 < visibleColumns.count else { return }
            moveTask(task.id, to: visibleColumns[sourceIndex + 1], before: nil)

        @unknown default:
            return
        }
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
        selectedBoardID = activeBoards.first(where: { $0.id != board.id })?.id
            ?? boards.first(where: { $0.id != board.id })?.id
        _ = saveChanges()
    }

    private func archiveBoard(_ board: Board) {
        guard !board.isArchived else { return }
        board.isArchived = true
        if selectedBoardID == board.id {
            selectedBoardID = activeBoards.first(where: { $0.id != board.id })?.id ?? board.id
            showTrash = false
        }
        if saveChanges() {
            statusMessage = "Доска «\(board.title)» перемещена в архив."
        }
    }

    private func restoreBoardFromArchive(_ board: Board) {
        guard board.isArchived else { return }
        board.isArchived = false
        selectedBoardID = board.id
        showTrash = false
        if saveChanges() {
            statusMessage = "Доска «\(board.title)» восстановлена из архива."
        }
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
            modelContext.rollback()
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
            let importedBoardID = try archive.importInto(modelContext)
            if let importedBoardID {
                selectedBoardID = importedBoardID
                showTrash = false
                clearFilters()
            }
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

    private var isOverdue: Bool {
        task.dueDate.map { $0 < Calendar.current.startOfDay(for: .now) } ?? false
    }

    private var accentColor: Color? {
        if isOverdue { return .red }
        if task.priority == .high { return .orange }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(task.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !task.details.isEmpty {
                Text(task.details).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !task.labels.isEmpty {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 54), alignment: .leading)],
                    alignment: .leading,
                    spacing: 5
                ) {
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
        .jungoTaskSurface(radius: 14)
        .overlay(alignment: .leading) {
            if let accentColor {
                Capsule()
                    .fill(accentColor)
                    .frame(width: 3)
                    .padding(.vertical, 10)
                    .padding(.leading, 1)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct ChecklistDraft: Identifiable {
    let id: UUID
    var title: String
    var isCompleted: Bool
}

private struct TaskEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TaskChecklistItem.sortOrder) private var allChecklistItems: [TaskChecklistItem]

    let task: TaskCard
    let onSave: () -> Bool

    @State private var draftTitle = ""
    @State private var draftLabelsText = ""
    @State private var draftDetails = ""
    @State private var draftPriority: TaskPriority = .normal
    @State private var draftHasDueDate = false
    @State private var draftDueDate = Date.now
    @State private var draftChecklistItems: [ChecklistDraft] = []
    @State private var showDescriptionPreview = false
    @State private var newChecklistTitle = ""

    private var checklistItems: [TaskChecklistItem] {
        allChecklistItems.filter { $0.taskID == task.id }.sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Редактирование задачи")
                .font(.title2.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            TextField("Название задачи", text: $draftTitle)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
            TextField("Метки через запятую", text: $draftLabelsText)
                .textFieldStyle(.roundedBorder)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 12) {
                    Text("Описание")
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 8)
                    Picker("Режим описания", selection: $showDescriptionPreview) {
                        Text("Правка").tag(false)
                        Text("Предпросмотр").tag(true)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 224)
                }
                if showDescriptionPreview {
                    ScrollView {
                        Group {
                            if let rendered = try? AttributedString(markdown: draftDetails) {
                                Text(rendered)
                            } else {
                                Text(draftDetails)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                    }
                    .frame(minHeight: 150)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
                } else {
                    TextEditor(text: $draftDetails)
                        .frame(minHeight: 150)
                        .padding(6)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
                }
            }
            Picker("Приоритет", selection: $draftPriority) {
                ForEach(TaskPriority.allCases) { priority in Text(priority.title).tag(priority) }
            }
            .pickerStyle(.segmented)
            Toggle("Установить срок", isOn: $draftHasDueDate)
            if draftHasDueDate {
                DatePicker("Срок", selection: $draftDueDate, displayedComponents: .date)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Чек-лист").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(draftChecklistItems.filter(\.isCompleted).count)/\(draftChecklistItems.count)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach($draftChecklistItems) { $item in
                    HStack(spacing: 8) {
                        Toggle("Выполнено", isOn: $item.isCompleted)
                            .labelsHidden()
                            .accessibilityLabel("Выполнено: \(item.title)")
                        TextField("Пункт чек-листа", text: $item.title)
                            .textFieldStyle(.roundedBorder)
                        Button(role: .destructive) {
                            draftChecklistItems.removeAll { $0.id == item.id }
                        } label: {
                            Image(systemName: "xmark.circle")
                        }
                        .buttonStyle(.plain)
                        .help("Удалить пункт")
                        .accessibilityLabel("Удалить пункт: \(item.title)")
                    }
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
                Button("Сохранить", action: saveDraft)
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 560)
        .frame(minHeight: 560)
        .background(JungoCanvasBackground())
        .onAppear {
            draftTitle = task.title
            draftLabelsText = task.labelsText
            draftDetails = task.details
            draftPriority = task.priority
            draftHasDueDate = task.dueDate != nil
            draftDueDate = task.dueDate ?? .now
            draftChecklistItems = checklistItems.map {
                ChecklistDraft(id: $0.id, title: $0.title, isCompleted: $0.isCompleted)
            }
        }
    }

    private func addChecklistItem() {
        let title = newChecklistTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        draftChecklistItems.append(ChecklistDraft(id: UUID(), title: title, isCompleted: false))
        newChecklistTitle = ""
    }

    private func saveDraft() {
        task.title = draftTitle
        task.labelsText = draftLabelsText
        task.details = draftDetails
        // Keep unknown future priority values intact unless the user changes the selection.
        if draftPriority != task.priority {
            task.priority = draftPriority
        }
        task.dueDate = draftHasDueDate ? draftDueDate : nil

        let draftIDs = Set(draftChecklistItems.map(\.id))
        for item in checklistItems where !draftIDs.contains(item.id) {
            modelContext.delete(item)
        }
        let existingByID = Dictionary(uniqueKeysWithValues: checklistItems.map { ($0.id, $0) })
        for (index, draft) in draftChecklistItems.enumerated() {
            if let existing = existingByID[draft.id] {
                existing.title = draft.title
                existing.isCompleted = draft.isCompleted
                existing.sortOrder = index
            } else {
                modelContext.insert(TaskChecklistItem(
                    id: draft.id,
                    title: draft.title,
                    isCompleted: draft.isCompleted,
                    sortOrder: index,
                    taskID: task.id
                ))
            }
        }

        if onSave() {
            dismiss()
        }
    }
}


private struct TaskLabelPill: View {
    let label: String
    @AppStorage("jungo.labelColorsJSON") private var labelColorsJSON = "{}"

    private var tint: Color {
        TaskLabelPalette.color(for: label, storedJSON: labelColorsJSON)
    }

    var body: some View {
        Text(label)
            .font(.caption2.weight(.medium))
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
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
        .padding(26)
        .frame(width: 460)
        .background(JungoCanvasBackground())
        .onAppear {
            if selectedColumnID == nil { selectedColumnID = columns.first?.id }
        }
    }
}
