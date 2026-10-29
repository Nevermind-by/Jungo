import Foundation
import SwiftData
import JungoCore

typealias JungoArchive = JungoArchiveDocument

extension JungoArchiveDocument {
    static func capture(boards: [Board], columns: [BoardColumn], tasks: [TaskCard], checklistItems: [TaskChecklistItem]) -> JungoArchiveDocument {
        JungoArchiveDocument(
            formatVersion: 1,
            exportedAt: .now,
            boards: boards.map { .init(id: $0.id, title: $0.title, sortOrder: $0.sortOrder, createdAt: $0.createdAt, isArchived: $0.isArchived) },
            columns: columns.map { .init(id: $0.id, title: $0.title, sortOrder: $0.sortOrder, boardID: $0.boardID) },
            tasks: tasks.map {
                .init(id: $0.id, title: $0.title, details: $0.details, labelsText: $0.labelsText, priorityRawValue: $0.priorityRawValue, sortOrder: $0.sortOrder, columnID: $0.columnID, createdAt: $0.createdAt, dueDate: $0.dueDate, isInTrash: $0.isInTrash)
            },
            checklistItems: checklistItems.map { .init(id: $0.id, title: $0.title, isCompleted: $0.isCompleted, sortOrder: $0.sortOrder, taskID: $0.taskID) }
        )
    }

    func validate() throws {
        do {
            try ArchiveValidation.validate(
                formatVersion: formatVersion,
                boards: boards.map { .init(id: $0.id, title: $0.title) },
                columns: columns.map { .init(id: $0.id, title: $0.title, boardID: $0.boardID) },
                tasks: tasks.map { .init(id: $0.id, title: $0.title, columnID: $0.columnID) },
                checklistItems: (checklistItems ?? []).map { .init(id: $0.id, title: $0.title, taskID: $0.taskID) }
            )
        } catch let validationError as ArchiveValidationError {
            switch validationError {
            case .unsupportedVersion(let version): throw ArchiveError.unsupportedVersion(version)
            case .duplicateIdentifiers: throw ArchiveError.duplicateIdentifiers
            case .brokenReferences: throw ArchiveError.brokenReferences
            case .emptyTitles: throw ArchiveError.emptyTitles
            }
        }
    }

    /// Imports additional boards in an isolated context so a failed import cannot
    /// roll back unrelated edits in the UI context or leave a partial import there.
    func importInto(_ context: ModelContext) throws {
        try validate()

        let importContext = ModelContext(context.container)
        importContext.undoManager = nil

        do {
            var boardIDMap: [UUID: UUID] = [:]
            var columnIDMap: [UUID: UUID] = [:]
            var taskIDMap: [UUID: UUID] = [:]

            let existingBoards = try importContext.fetch(FetchDescriptor<Board>())
            let nextBoardSortOrder = (existingBoards.map(\\.sortOrder).max() ?? -1) + 1

            for record in boards.sorted(by: { $0.sortOrder < $1.sortOrder }) {
                let newID = UUID()
                boardIDMap[record.id] = newID
                importContext.insert(Board(
                    id: newID,
                    title: record.title,
                    sortOrder: nextBoardSortOrder + record.sortOrder,
                    createdAt: record.createdAt,
                    isArchived: record.isArchived ?? false
                ))
            }

            for record in columns.sorted(by: { $0.sortOrder < $1.sortOrder }) {
                guard let boardID = boardIDMap[record.boardID] else {
                    throw ArchiveError.brokenReferences
                }
                let newID = UUID()
                columnIDMap[record.id] = newID
                importContext.insert(BoardColumn(
                    id: newID,
                    title: record.title,
                    sortOrder: record.sortOrder,
                    boardID: boardID
                ))
            }

            for record in tasks {
                guard let columnID = columnIDMap[record.columnID] else {
                    throw ArchiveError.brokenReferences
                }
                let newID = UUID()
                taskIDMap[record.id] = newID
                importContext.insert(TaskCard(
                    id: newID,
                    title: record.title,
                    details: record.details,
                    labelsText: record.labelsText ?? "",
                    priority: TaskPriority(rawValue: record.priorityRawValue) ?? .normal,
                    sortOrder: record.sortOrder,
                    columnID: columnID,
                    createdAt: record.createdAt,
                    dueDate: record.dueDate,
                    isInTrash: record.isInTrash ?? false
                ))
            }

            for record in checklistItems ?? [] {
                guard let taskID = taskIDMap[record.taskID] else {
                    throw ArchiveError.brokenReferences
                }
                importContext.insert(TaskChecklistItem(
                    id: UUID(),
                    title: record.title,
                    isCompleted: record.isCompleted,
                    sortOrder: record.sortOrder,
                    taskID: taskID
                ))
            }

            try importContext.save()
        } catch {
            importContext.rollback()
            throw error
        }
    }
}

enum ArchiveError: LocalizedError {
    case unsupportedVersion(Int)
    case duplicateIdentifiers
    case brokenReferences
    case emptyTitles

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version): "Версия архива \\(version) не поддерживается."
        case .duplicateIdentifiers: "Архив содержит повторяющиеся идентификаторы."
        case .brokenReferences: "В архиве есть задачи или колонки без родительской записи."
        case .emptyTitles: "В архиве есть записи без названия."
        }
    }
}
