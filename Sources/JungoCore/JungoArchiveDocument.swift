import Foundation

/// Codable JSON backup format shared by the app and unit tests.
/// Optional fields intentionally decode as nil when loading older backups.
public struct JungoArchiveDocument: Codable {
    public var formatVersion: Int
    public var exportedAt: Date
    public var boards: [BoardRecord]
    public var columns: [ColumnRecord]
    public var tasks: [TaskRecord]
    public var checklistItems: [ChecklistRecord]?

    public init(
        formatVersion: Int,
        exportedAt: Date,
        boards: [BoardRecord],
        columns: [ColumnRecord],
        tasks: [TaskRecord],
        checklistItems: [ChecklistRecord]?
    ) {
        self.formatVersion = formatVersion
        self.exportedAt = exportedAt
        self.boards = boards
        self.columns = columns
        self.tasks = tasks
        self.checklistItems = checklistItems
    }

    public struct BoardRecord: Codable {
        public var id: UUID
        public var title: String
        public var sortOrder: Int
        public var createdAt: Date
        public var isArchived: Bool?

        public init(id: UUID, title: String, sortOrder: Int, createdAt: Date, isArchived: Bool? = nil) {
            self.id = id
            self.title = title
            self.sortOrder = sortOrder
            self.createdAt = createdAt
            self.isArchived = isArchived
        }
    }

    public struct ColumnRecord: Codable {
        public var id: UUID
        public var title: String
        public var sortOrder: Int
        public var boardID: UUID

        public init(id: UUID, title: String, sortOrder: Int, boardID: UUID) {
            self.id = id
            self.title = title
            self.sortOrder = sortOrder
            self.boardID = boardID
        }
    }

    public struct TaskRecord: Codable {
        public var id: UUID
        public var title: String
        public var details: String
        public var labelsText: String?
        public var priorityRawValue: String
        public var sortOrder: Int
        public var columnID: UUID
        public var createdAt: Date
        public var dueDate: Date?
        public var isInTrash: Bool?

        public init(
            id: UUID,
            title: String,
            details: String,
            labelsText: String? = nil,
            priorityRawValue: String,
            sortOrder: Int,
            columnID: UUID,
            createdAt: Date,
            dueDate: Date? = nil,
            isInTrash: Bool? = nil
        ) {
            self.id = id
            self.title = title
            self.details = details
            self.labelsText = labelsText
            self.priorityRawValue = priorityRawValue
            self.sortOrder = sortOrder
            self.columnID = columnID
            self.createdAt = createdAt
            self.dueDate = dueDate
            self.isInTrash = isInTrash
        }
    }

    public struct ChecklistRecord: Codable {
        public var id: UUID
        public var title: String
        public var isCompleted: Bool
        public var sortOrder: Int
        public var taskID: UUID

        public init(id: UUID, title: String, isCompleted: Bool, sortOrder: Int, taskID: UUID) {
            self.id = id
            self.title = title
            self.isCompleted = isCompleted
            self.sortOrder = sortOrder
            self.taskID = taskID
        }
    }
}
