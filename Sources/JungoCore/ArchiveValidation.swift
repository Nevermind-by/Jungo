import Foundation

public enum ArchiveValidationError: Error, Equatable, LocalizedError {
    case unsupportedVersion(Int)
    case duplicateIdentifiers
    case brokenReferences
    case emptyTitles

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "Версия архива \(version) не поддерживается."
        case .duplicateIdentifiers:
            return "Архив содержит повторяющиеся идентификаторы."
        case .brokenReferences:
            return "В архиве есть записи без существующей родительской записи."
        case .emptyTitles:
            return "В архиве есть записи без названия."
        }
    }
}

/// Pure validation for a JSON archive, independent of SwiftData so the rules can be unit-tested.
public enum ArchiveValidation {
    public struct BoardRecord {
        public let id: UUID
        public let title: String

        public init(id: UUID, title: String) {
            self.id = id
            self.title = title
        }
    }

    public struct ColumnRecord {
        public let id: UUID
        public let title: String
        public let boardID: UUID

        public init(id: UUID, title: String, boardID: UUID) {
            self.id = id
            self.title = title
            self.boardID = boardID
        }
    }

    public struct TaskRecord {
        public let id: UUID
        public let title: String
        public let columnID: UUID

        public init(id: UUID, title: String, columnID: UUID) {
            self.id = id
            self.title = title
            self.columnID = columnID
        }
    }

    public struct ChecklistRecord {
        public let id: UUID
        public let title: String
        public let taskID: UUID

        public init(id: UUID, title: String, taskID: UUID) {
            self.id = id
            self.title = title
            self.taskID = taskID
        }
    }

    public static func validate(
        formatVersion: Int,
        boards: [BoardRecord],
        columns: [ColumnRecord],
        tasks: [TaskRecord],
        checklistItems: [ChecklistRecord]
    ) throws {
        guard formatVersion == 1 else {
            throw ArchiveValidationError.unsupportedVersion(formatVersion)
        }

        let boardIDs = Set(boards.map(\.id))
        let columnIDs = Set(columns.map(\.id))
        let taskIDs = Set(tasks.map(\.id))
        let checklistIDs = Set(checklistItems.map(\.id))
        guard boardIDs.count == boards.count,
              columnIDs.count == columns.count,
              taskIDs.count == tasks.count,
              checklistIDs.count == checklistItems.count else {
            throw ArchiveValidationError.duplicateIdentifiers
        }

        guard columns.allSatisfy({ boardIDs.contains($0.boardID) }),
              tasks.allSatisfy({ columnIDs.contains($0.columnID) }),
              checklistItems.allSatisfy({ taskIDs.contains($0.taskID) }) else {
            throw ArchiveValidationError.brokenReferences
        }

        let allTitles = boards.map(\.title)
            + columns.map(\.title)
            + tasks.map(\.title)
            + checklistItems.map(\.title)
        guard allTitles.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw ArchiveValidationError.emptyTitles
        }
    }
}
