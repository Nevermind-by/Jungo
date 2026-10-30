import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    @FocusState private var focusedTaskID: UUID?
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var targetedDropColumnID: UUID?
    @State private var targetedDropTaskID: UUID?
    @Namespace private var taskMoveNamespace

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
            targetedDropColumnID = nil
            targetedDropTaskID = nil
        }
        .onChange(of: showTrash) { _, _ in
            targetedDropColumnID = nil
            targetedDropTaskID = nil
            focusedTaskID = nil
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
                    Label {
                        Text(board.title)
                            .font(.system(.subheadline).weight(selectedBoardID == board.id ? .semibold : .medium))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "rectangle.split.3x1")
                            .foregroundStyle(Color.accentColor.opacity(0.85))
                    }
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
                        Label {
                            Text(board.title)
                                .font(.system(.footnote).weight(.medium))
                        } icon: {
                            Image(systemName: "archivebox")
                                .foregroundStyle(.tertiary)
                        }
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
                .font(.system(.footnote).weight(.medium))
                .controlSize(.small)
            }
            .padding(12)
            .jungoGlassPanel(radius: 16)
        }
        .alert("Название доски", isPresented: $isNamingBoard) {
            TextField("Название", text: $nameInput)
            Button("Отмена", role: .cancel) { nameInput = ""; editingBoardID = nil }
            Button("Сохранить", action: saveBoardName).disabled(nameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var searchControl: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Поиск задач", text: $searchText)
                .textFieldStyle(.plain)
                .frame(minWidth: 100, idealWidth: 145, maxWidth: 180)
                .focused($isSearchFocused)
                .accessibilityLabel("Поиск задач")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .jungoGlassPanel(radius: JungoDesign.controlRadius)
    }

    private var filterControls: some View {
        HStack(spacing: 8) {
            Picker("Приоритет", selection: $priorityFilter) {
                ForEach(PriorityFilter.allCases) { filter in Text(filter.title).tag(filter) }
            }
            .labelsHidden()
            .frame(width: 130)
            Toggle(isOn: $showOverdueOnly) {
                Image(systemName: "calendar.badge.exclamationmark")
            }
            .toggleStyle(.button)
            .help("Только просроченные задачи")
            .accessibilityLabel("Только просроченные задачи")
        }
    }

    private var newTaskButton: some View {
        Button {
            showQuickAdd = true
        } label: {
            Label("Новая задача", systemImage: "plus")
        }
        .buttonStyle(.borderedProminent)
        .disabled(visibleColumns.isEmpty)
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
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            searchControl
                            filterControls
                            newTaskButton
                        }
                        VStack(alignment: .trailing, spacing: 8) {
                            HStack(spacing: 8) {
                                searchControl
                                filterControls
                            }
                            newTaskButton
                        }
                    }
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
                                checklistItemsByTask: checklistItemsByTask,
                                taskMoveNamespace: taskMoveNamespace
                            )
                            .frame(minWidth: JungoDesign.columnMinimumWidth, idealWidth: JungoDesign.columnIdealWidth, maxWidth: 300)
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
        .frame(minWidth: 200, idealWidth: 220, maxWidth: 240)
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
        checklistItemsByTask: [UUID: [TaskChecklistItem]],
        taskMoveNamespace: Namespace.ID
    ) -> some View {
        let columnTasks = tasks(in: column, candidates: taskCandidates)
        let hasTasksBeforeFilters = taskCandidates.contains { !$0.isInTrash }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(columnColor(column.sortOrder))
                    .frame(width: 4, height: 19)
                Text(column.title)
                    .font(.system(.subheadline).weight(.semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(columnTasks.count)")
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.10), in: Capsule())
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
                VStack(spacing: 8) {
                    Image(systemName: hasTasksBeforeFilters && hasActiveFilters ? "line.3.horizontal.decrease.circle" : "tray")
                        .font(.title2)
                    Text(hasTasksBeforeFilters && hasActiveFilters ? "Нет совпадений" : "Пусто")
                        .font(.subheadline.weight(.medium))
                    if targetedDropColumnID == column.id && !hasActiveFilters {
                        Label("Отпустите, чтобы переместить", systemImage: "arrow.down.to.line")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.accentColor)
                            .transition(.opacity)
                    }
                    if hasTasksBeforeFilters && hasActiveFilters {
                        Button("Сбросить фильтры", action: clearFilters)
                            .buttonStyle(.bordered)
                    }
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                // Keep empty columns quiet: the global “Новая задача” action
                // creates tasks, while the per-column add control appears only
                // once the column has content. Avoid repeating three CTAs.
            }
            ForEach(columnTasks) { task in
                taskCardButton(
                    task,
                    in: column,
                    checklistItems: checklistItemsByTask[task.id] ?? [],
                    moveNamespace: taskMoveNamespace
                )
            }
            if !hasActiveFilters {
                Button {
                    createTask(in: column)
                } label: {
                    Label("Добавить задачу", systemImage: "plus")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 10)
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.secondary.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
                .help("Создать задачу в колонке «\(column.title)»")
                .accessibilityHint("Создаёт задачу непосредственно в этой колонке.")
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background {
            RoundedRectangle(cornerRadius: JungoDesign.columnRadius, style: .continuous)
                .fill(Color.accentColor.opacity(targetedDropColumnID == column.id ? 0.055 : 0))
                .padding(1)
        }
        .jungoTaskSurface(radius: JungoDesign.columnRadius)
        .overlay {
            RoundedRectangle(cornerRadius: JungoDesign.columnRadius, style: .continuous)
                .strokeBorder(
                    Color.accentColor.opacity(targetedDropColumnID == column.id ? 0.72 : 0),
                    lineWidth: targetedDropColumnID == column.id ? 2 : 0
                )
                .padding(1)
                .allowsHitTesting(false)
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: targetedDropColumnID)
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: columnTasks.map(\.id))
        .dropDestination(
            for: String.self,
            action: { identifiers, _ in
                acceptTaskDrop(identifiers, in: column, before: nil)
            },
            isTargeted: Binding(
                get: { targetedDropColumnID == column.id },
                set: { isTargeted in
                    if isTargeted {
                        targetedDropColumnID = column.id
                        targetedDropTaskID = nil
                    } else if targetedDropColumnID == column.id {
                        targetedDropColumnID = nil
                        targetedDropTaskID = nil
                    }
                }
            )
        )
    }

    private func taskCardButton(
        _ task: TaskCard,
        in column: BoardColumn,
        checklistItems: [TaskChecklistItem],
        moveNamespace: Namespace.ID
    ) -> some View {
        let dropTarget = Binding<Bool>(
            get: { targetedDropTaskID == task.id },
            set: { isTargeted in
                if isTargeted {
                    targetedDropTaskID = task.id
                    targetedDropColumnID = column.id
                } else if targetedDropTaskID == task.id {
                    targetedDropTaskID = nil
                }
            }
        )

        return Button {
            selectedTask = task
        } label: {
            TaskCardView(
                task: task,
                checklistItems: checklistItems,
                moveNamespace: moveNamespace
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(taskAccessibilitySummary(for: task, checklistItems: checklistItems))
        .accessibilityHint("Используй стрелки вверх и вниз для изменения порядка, влево и вправо — для переноса между колонками.")
        .accessibilityAction(named: Text("Переместить вверх")) { moveTask(task, using: .up) }
        .accessibilityAction(named: Text("Переместить вниз")) { moveTask(task, using: .down) }
        .accessibilityAction(named: Text("Переместить в предыдущую колонку")) { moveTask(task, using: .left) }
        .accessibilityAction(named: Text("Переместить в следующую колонку")) { moveTask(task, using: .right) }
        .focused($focusedTaskID, equals: task.id)
        .focusable()
        .overlay {
            if focusedTaskID == task.id {
                RoundedRectangle(cornerRadius: JungoDesign.cardRadius, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.9), lineWidth: JungoDesign.focusRingWidth)
                    .padding(1)
                    .allowsHitTesting(false)
            }
        }
        .onMoveCommand { direction in
            moveTask(task, using: direction)
        }
        .draggable(task.id.uuidString)
        .overlay(alignment: .top) {
            if targetedDropTaskID == task.id {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(height: JungoDesign.dragIndicatorHeight)
                    .padding(.horizontal, 7)
                    .offset(y: -2)
                    .shadow(color: Color.accentColor.opacity(0.25), radius: 3, y: 1)
                    .accessibilityHidden(true)
            }
        }
        .dropDestination(
            for: String.self,
            action: { identifiers, _ in
                acceptTaskDrop(identifiers, in: column, before: task.id)
            },
            isTargeted: dropTarget
        )
        .contextMenu {
            taskContextMenu(for: task, in: column)
        }
    }

    @ViewBuilder
    private func taskContextMenu(for task: TaskCard, in column: BoardColumn) -> some View {
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

    private func acceptTaskDrop(_ identifiers: [String], in destination: BoardColumn, before targetID: UUID?) -> Bool {
        guard let rawID = identifiers.first,
              let draggedID = UUID(uuidString: rawID) else { return false }
        moveTask(draggedID, to: destination, before: targetID)
        targetedDropTaskID = nil
        targetedDropColumnID = nil
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

        // Animate the model update as one coordinated move. A short spring
        // lets the source and destination columns settle together without the
        // long, bouncy motion that makes a Kanban board feel sluggish.
        withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.88)) {
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
                ContentUnavailableView(
                    "Корзина пуста",
                    systemImage: "trash",
                    description: Text("Удалённые задачи появятся здесь. Их можно восстановить или удалить навсегда.")
                )
            } else {
                List {
                    ForEach(tasks) { task in
                        HStack(spacing: 13) {
                            Image(systemName: "doc.text")
                                .font(.system(.body).weight(.medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 34, height: 34)
                                .background(Color.secondary.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(task.title)
                                    .font(.system(.subheadline).weight(.semibold))
                                    .lineLimit(3)
                                    .fixedSize(horizontal: false, vertical: true)
                                if !task.details.isEmpty {
                                    Text(task.details)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(3)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Text("Доска: \(board.title) · В корзине")
                                    .font(.system(.caption2).weight(.medium))
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer(minLength: 8)
                            Button("Восстановить", systemImage: "arrow.uturn.backward") {
                                restoreTask(task)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            Button(role: .destructive) {
                                taskPendingPermanentDeletionID = task.id
                            } label: {
                                Image(systemName: "trash.slash")
                                    .frame(width: 28, height: 28)
                            }
                            .buttonStyle(.borderless)
                            .help("Удалить навсегда")
                            .accessibilityLabel("Удалить задачу навсегда: \(task.title)")
                        }
                        .padding(9)
                        .jungoTaskSurface(radius: 13)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .padding(.vertical, 3)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var titleFontSize: CGFloat = 14
    @ScaledMetric(relativeTo: .footnote) private var detailFontSize: CGFloat = 11.5
    @ScaledMetric(relativeTo: .caption) private var metadataFontSize: CGFloat = 10
    @State private var isHovering = false

    let task: TaskCard
    let checklistItems: [TaskChecklistItem]
    let moveNamespace: Namespace.ID

    private var isOverdue: Bool {
        task.dueDate.map { $0 < Calendar.current.startOfDay(for: .now) } ?? false
    }

    private var completedChecklistCount: Int {
        checklistItems.filter(\.isCompleted).count
    }

    private var priorityTint: Color {
        switch task.priority {
        case .high: .orange
        case .low: .secondary
        case .normal: .blue
        }
    }

    private var accentColor: Color? {
        if isOverdue { return .red }
        if task.priority == .high { return .orange }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 6) {
                Label(task.priority.title, systemImage: task.priority.symbol)
                    .font(.system(size: metadataFontSize, weight: .semibold))
                    .foregroundStyle(priorityTint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(priorityTint.opacity(0.11), in: Capsule())

                Spacer(minLength: 4)

                if let dueDate = task.dueDate {
                    Label {
                        Text(dueDate, format: .dateTime.month(.abbreviated).day())
                    } icon: {
                        Image(systemName: "calendar")
                    }
                    .font(.system(size: metadataFontSize, weight: .medium))
                    .foregroundStyle(isOverdue ? .red : .secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background((isOverdue ? Color.red : Color.secondary).opacity(0.09), in: Capsule())
                    .help(isOverdue ? "Срок выполнения просрочен" : "Срок выполнения")
                }
            }

            Text(task.title)
                .font(.system(size: titleFontSize, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !task.details.isEmpty {
                Text(task.details)
                    .font(.system(size: detailFontSize))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !task.labels.isEmpty {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 58), alignment: .leading)],
                    alignment: .leading,
                    spacing: 5
                ) {
                    ForEach(task.labels, id: \.self) { label in
                        TaskLabelPill(label: label)
                    }
                }
            }

            if !checklistItems.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "checklist")
                            .font(.system(size: metadataFontSize, weight: .medium))
                        Text("Чек-лист")
                            .font(.system(size: metadataFontSize, weight: .medium))
                        Spacer()
                        Text("\(completedChecklistCount) из \(checklistItems.count)")
                            .font(.system(size: metadataFontSize, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: Double(completedChecklistCount), total: Double(checklistItems.count))
                        .tint(completedChecklistCount == checklistItems.count ? .green : .accentColor)
                        .controlSize(.mini)
                }
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Чек-лист: \(completedChecklistCount) из \(checklistItems.count) выполнено")
            } else {
                HStack {
                    Image(systemName: "clock")
                        .font(.caption2)
                    Text(task.createdAt, format: .dateTime.month(.abbreviated).day())
                        .font(.system(size: metadataFontSize, weight: .medium))
                }
                .foregroundStyle(.tertiary)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .jungoTaskSurface(radius: JungoDesign.cardRadius)
        .overlay {
            RoundedRectangle(cornerRadius: JungoDesign.cardRadius, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(isHovering ? 0.38 : 0), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(isHovering ? 0.08 : 0.025), radius: isHovering ? 9 : 3, y: isHovering ? 4 : 1)
        .onHover { hovering in
            if reduceMotion {
                isHovering = hovering
            } else {
                withAnimation(.easeOut(duration: 0.16)) {
                    isHovering = hovering
                }
            }
        }
        .overlay(alignment: .leading) {
            if let accentColor {
                Capsule()
                    .fill(accentColor)
                    .frame(width: 3)
                    .padding(.vertical, 11)
                    .padding(.leading, 1)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: JungoDesign.cardRadius, style: .continuous))
        .matchedGeometryEffect(id: task.id, in: moveNamespace, properties: .frame)
    }
}

private struct ChecklistDraft: Identifiable {
    let id: UUID
    var title: String
    var isCompleted: Bool
}

private struct TaskEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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

    private var completedCount: Int {
        draftChecklistItems.filter(\.isCompleted).count
    }

    private var isTitleValid: Bool {
        !draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            editorHeader
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    JungoSectionSurface("Основное", subtitle: "Название и контекст задачи") {
                        VStack(alignment: .leading, spacing: 10) {
                            TextField("Название задачи", text: $draftTitle)
                                .textFieldStyle(.plain)
                                .font(.system(.title2).weight(.semibold))
                                .padding(12)
                                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: JungoDesign.inputRadius))
                            VStack(alignment: .leading, spacing: 6) {
                                Text("МЕТКИ")
                                    .font(.system(.caption2).weight(.bold))
                                    .tracking(0.8)
                                    .foregroundStyle(.tertiary)
                                TextField("Например: дизайн, срочно, личное", text: $draftLabelsText)
                                    .textFieldStyle(.plain)
                                    .padding(.vertical, 5)
                            }
                        }
                    }

                    JungoSectionSurface("Описание", subtitle: "Поддерживается Markdown-разметка") {
                        VStack(spacing: 10) {
                            HStack {
                                Label("Содержание", systemImage: "text.alignleft")
                                    .font(.system(.footnote).weight(.medium))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Picker("Режим описания", selection: $showDescriptionPreview) {
                                    Text("Правка").tag(false)
                                    Text("Просмотр").tag(true)
                                }
                                .labelsHidden()
                                .pickerStyle(.segmented)
                                .frame(width: 170)
                                .controlSize(.small)
                            }
                            if showDescriptionPreview {
                                ScrollView {
                                    Group {
                                        if draftDetails.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                            ContentUnavailableView("Пока пусто", systemImage: "text.alignleft", description: Text("Добавь описание в режиме правки."))
                                        } else if let rendered = try? AttributedString(markdown: draftDetails) {
                                            Text(rendered)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        } else {
                                            Text(draftDetails).frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                    }
                                    .padding(12)
                                }
                                .frame(minHeight: 145, maxHeight: 190)
                                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: JungoDesign.inputRadius))
                            } else {
                                TextEditor(text: $draftDetails)
                                    .font(.subheadline)
                                    .scrollContentBackground(.hidden)
                                    .padding(7)
                                    .frame(minHeight: 145, maxHeight: 190)
                                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: JungoDesign.inputRadius))
                                    .overlay(alignment: .topLeading) {
                                        if draftDetails.isEmpty {
                                            Text("Опиши задачу, добавь детали или Markdown…")
                                                .font(.subheadline)
                                                .foregroundStyle(.tertiary)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 15)
                                                .allowsHitTesting(false)
                                        }
                                    }
                            }
                        }
                    }

                    JungoSectionSurface("Планирование", subtitle: "Приоритет и срок выполнения") {
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 7) {
                                Text("ПРИОРИТЕТ")
                                    .font(.system(.caption2).weight(.bold))
                                    .tracking(0.8)
                                    .foregroundStyle(.tertiary)
                                HStack(spacing: 7) {
                                    ForEach(TaskPriority.allCases) { priority in
                                        let selected = draftPriority == priority
                                        Button {
                                            draftPriority = priority
                                        } label: {
                                            HStack(spacing: 6) {
                                                Image(systemName: priority.symbol)
                                                Text(priority.title)
                                            }
                                            .font(.system(.footnote).weight(.semibold))
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 9)
                                            .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                                            .background(selected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: JungoDesign.inputRadius))
                                            .overlay {
                                                RoundedRectangle(cornerRadius: JungoDesign.inputRadius)
                                                    .strokeBorder(selected ? Color.accentColor.opacity(0.35) : Color.clear, lineWidth: 1)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityAddTraits(selected ? .isSelected : [])
                                    }
                                }
                            }
                            Divider().opacity(0.6)
                            Toggle(isOn: $draftHasDueDate) {
                                Label("Срок выполнения", systemImage: "calendar")
                                    .font(.system(.subheadline).weight(.medium))
                            }
                            .toggleStyle(.switch)
                            if draftHasDueDate {
                                DatePicker("Выполнить до", selection: $draftDueDate, displayedComponents: .date)
                                    .datePickerStyle(.compact)
                                    .padding(.leading, 25)
                                    .transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: draftHasDueDate)
                    }

                    JungoSectionSurface("Чек-лист", subtitle: "Разбей работу на небольшие шаги") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("Прогресс")
                                    .font(.system(.footnote).weight(.medium))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(completedCount) из \(draftChecklistItems.count)")
                                    .font(.system(.footnote, design: .monospaced).weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            if !draftChecklistItems.isEmpty {
                                ProgressView(value: Double(completedCount), total: Double(draftChecklistItems.count))
                                    .tint(completedCount == draftChecklistItems.count ? .green : .accentColor)
                                    .controlSize(.small)
                            }
                            ForEach($draftChecklistItems) { $item in
                                HStack(spacing: 9) {
                                    Toggle("Выполнено", isOn: $item.isCompleted)
                                        .labelsHidden()
                                        .toggleStyle(.checkbox)
                                        .accessibilityLabel("Выполнено: \(item.title)")
                                    TextField("Пункт чек-листа", text: $item.title)
                                        .textFieldStyle(.plain)
                                        .font(.subheadline)
                                    Spacer(minLength: 0)
                                    Button(role: .destructive) {
                                        draftChecklistItems.removeAll { $0.id == item.id }
                                    } label: {
                                        Image(systemName: "minus.circle")
                                            .font(.subheadline)
                                            .foregroundStyle(.tertiary)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Удалить пункт")
                                    .accessibilityLabel("Удалить пункт: \(item.title)")
                                }
                                .padding(.vertical, 5)
                                if item.id != draftChecklistItems.last?.id {
                                    Divider().opacity(0.45)
                                }
                            }
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                                TextField("Добавить пункт…", text: $newChecklistTitle)
                                    .textFieldStyle(.plain)
                                    .font(.subheadline)
                                    .onSubmit(addChecklistItem)
                                Button("Добавить", action: addChecklistItem)
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .disabled(newChecklistTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                            .padding(.top, 3)
                        }
                    }
                }
                .padding(20)
            }
            .scrollIndicators(.automatic)

            Divider().opacity(0.65)
            HStack {
                Text("Изменения сохраняются только по кнопке «Сохранить».")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Spacer()
                Button("Отмена", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Сохранить", action: saveDraft)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!isTitleValid)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 13)
            .background(.bar)
        }
        .frame(minWidth: 440, idealWidth: 600, maxWidth: 720, minHeight: 520, idealHeight: 760)
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

    private var editorHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                Image(systemName: "square.and.pencil")
                    .font(.system(.title3).weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("Редактор задачи")
                    .font(.system(.headline).weight(.bold))
                Text("Настрой детали и план выполнения")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("JUNGO")
                .font(.system(.caption2, design: .rounded).weight(.bold))
                .tracking(1.5)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider().opacity(0.6) }
    }

    private func addChecklistItem() {
        let title = newChecklistTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        draftChecklistItems.append(ChecklistDraft(id: UUID(), title: title, isCompleted: false))
        newChecklistTitle = ""
    }

    private func saveDraft() {
        let normalizedTitle = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else { return }

        task.title = normalizedTitle
        task.labelsText = draftLabelsText
        task.details = draftDetails
        // Неизвестные значения приоритета сохраняются, пока пользователь явно не выберет другой.
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

    private var normalizedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                    Image(systemName: "bolt.fill")
                        .font(.system(.title3).weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Быстрое добавление")
                        .font(.system(.headline).weight(.bold))
                    Text("Запиши задачу и возвращайся к работе")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("JUNGO")
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .tracking(1.5)
                    .foregroundStyle(.tertiary)
            }
            .padding(20)
            .background(.bar)
            .overlay(alignment: .bottom) { Divider().opacity(0.6) }

            VStack(alignment: .leading, spacing: 16) {
                JungoSectionSurface("Новая задача", subtitle: "Начни с короткого и понятного названия") {
                    TextField("Что нужно сделать?", text: $title)
                        .textFieldStyle(.plain)
                        .font(.system(.title2).weight(.semibold))
                        .padding(12)
                        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: JungoDesign.inputRadius))
                        .onSubmit(createTask)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("ОПИСАНИЕ")
                            .font(.system(.caption2).weight(.bold))
                            .tracking(0.8)
                            .foregroundStyle(.tertiary)
                        TextField("Добавь контекст (необязательно)", text: $details, axis: .vertical)
                            .textFieldStyle(.plain)
                            .lineLimit(2...4)
                            .font(.subheadline)
                            .padding(10)
                            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: JungoDesign.inputRadius))
                    }
                }

                JungoSectionSurface("Куда добавить", subtitle: "Задача появится в выбранной колонке") {
                    if columns.isEmpty {
                        ContentUnavailableView("Нет доступных колонок", systemImage: "rectangle.split.3x1")
                    } else {
                        VStack(spacing: 6) {
                            ForEach(columns) { column in
                                let isSelected = selectedColumnID == column.id
                                Button {
                                    selectedColumnID = column.id
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                                            .font(.body)
                                            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                                        Text(column.title)
                                            .font(.system(.subheadline).weight(isSelected ? .semibold : .medium))
                                            .lineLimit(2)
                                            .fixedSize(horizontal: false, vertical: true)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        if isSelected {
                                            Text("Выбрано")
                                                .font(.system(.caption).weight(.medium))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 10)
                                    .background(isSelected ? Color.accentColor.opacity(0.09) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: JungoDesign.inputRadius))
                                    .contentShape(RoundedRectangle(cornerRadius: JungoDesign.inputRadius))
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(isSelected ? .isSelected : [])
                            }
                        }
                    }
                }
            }
            .padding(20)

            Divider().opacity(0.65)
            HStack {
                Text("⌘↩︎")
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.tertiary)
                Text("создать")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Отмена", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Создать задачу", systemImage: "plus", action: createTask)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(normalizedTitle.isEmpty || selectedColumnID == nil)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 13)
            .background(.bar)
        }
        .frame(minWidth: 420, idealWidth: 500, maxWidth: 560, minHeight: 450, idealHeight: 560)
        .background(JungoCanvasBackground())
        .onAppear {
            if selectedColumnID == nil { selectedColumnID = columns.first?.id }
        }
    }

    private func createTask() {
        guard !normalizedTitle.isEmpty,
              let selectedColumnID,
              onCreate(normalizedTitle, details.trimmingCharacters(in: .whitespacesAndNewlines), selectedColumnID) else { return }
        dismiss()
    }
}
