import Foundation

/// A fully validated, ID-remapped snapshot ready to be persisted by the app layer.
/// Building the plan is pure and does not touch SwiftData or any existing records.
public struct JungoArchiveImportPlan {
    public let boards: [JungoArchiveDocument.BoardRecord]
    public let columns: [JungoArchiveDocument.ColumnRecord]
    public let tasks: [JungoArchiveDocument.TaskRecord]
    public let checklistItems: [JungoArchiveDocument.ChecklistRecord]
    public let lastImportedBoardID: UUID?

    private init(
        boards: [JungoArchiveDocument.BoardRecord],
        columns: [JungoArchiveDocument.ColumnRecord],
        tasks: [JungoArchiveDocument.TaskRecord],
        checklistItems: [JungoArchiveDocument.ChecklistRecord],
        lastImportedBoardID: UUID?
    ) {
        self.boards = boards
        self.columns = columns
        self.tasks = tasks
        self.checklistItems = checklistItems
        self.lastImportedBoardID = lastImportedBoardID
    }

    /// Validates the source archive and resolves every new ID and parent reference
    /// before the caller creates or inserts any persistent model.
    public static func build(
        from archive: JungoArchiveDocument,
        nextBoardSortOrder: Int
    ) throws -> JungoArchiveImportPlan {
        try archive.validate()

        var boardIDMap: [UUID: UUID] = [:]
        var columnIDMap: [UUID: UUID] = [:]
        var taskIDMap: [UUID: UUID] = [:]

        let importedBoards = archive.boards
            .sorted { $0.sortOrder < $1.sortOrder }
            .enumerated()
            .map { offset, record in
                let newID = UUID()
                boardIDMap[record.id] = newID
                return JungoArchiveDocument.BoardRecord(
                    id: newID,
                    title: record.title,
                    sortOrder: nextBoardSortOrder + offset,
                    createdAt: record.createdAt,
                    isArchived: record.isArchived ?? false
                )
            }

        let importedColumns = archive.columns
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { record in
                let newID = UUID()
                columnIDMap[record.id] = newID
                return JungoArchiveDocument.ColumnRecord(
                    id: newID,
                    title: record.title,
                    sortOrder: record.sortOrder,
                    boardID: boardIDMap[record.boardID]!
                )
            }

        let importedTasks = archive.tasks.map { record in
            let newID = UUID()
            taskIDMap[record.id] = newID
            return JungoArchiveDocument.TaskRecord(
                id: newID,
                title: record.title,
                details: record.details,
                labelsText: record.labelsText ?? "",
                priorityRawValue: record.priorityRawValue,
                sortOrder: record.sortOrder,
                columnID: columnIDMap[record.columnID]!,
                createdAt: record.createdAt,
                dueDate: record.dueDate,
                isInTrash: record.isInTrash ?? false
            )
        }

        let importedChecklistItems = (archive.checklistItems ?? []).map { record in
            JungoArchiveDocument.ChecklistRecord(
                id: UUID(),
                title: record.title,
                isCompleted: record.isCompleted,
                sortOrder: record.sortOrder,
                taskID: taskIDMap[record.taskID]!
            )
        }

        return JungoArchiveImportPlan(
            boards: importedBoards,
            columns: importedColumns,
            tasks: importedTasks,
            checklistItems: importedChecklistItems,
            lastImportedBoardID: importedBoards.last?.id
        )
    }
}
