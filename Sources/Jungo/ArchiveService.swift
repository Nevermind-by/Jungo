import Foundation
import SwiftData

struct JungoArchive: Codable {
    var formatVersion: Int
    var exportedAt: Date
    var boards: [BoardRecord]
    var columns: [ColumnRecord]
    var tasks: [TaskRecord]

    struct BoardRecord: Codable {
        var id: UUID
        var title: String
        var sortOrder: Int
        var createdAt: Date
    }

    struct ColumnRecord: Codable {
        var id: UUID
        var title: String
        var sortOrder: Int
        var boardID: UUID
    }

    struct TaskRecord: Codable {
        var id: UUID
        var title: String
        var details: String
        var priorityRawValue: String
        var sortOrder: Int
        var columnID: UUID
        var createdAt: Date
    }

    static func capture(boards: [Board], columns: [BoardColumn], tasks: [TaskCard]) -> JungoArchive {
        JungoArchive(
            formatVersion: 1,
            exportedAt: .now,
            boards: boards.map { .init(id: $0.id, title: $0.title, sortOrder: $0.sortOrder, createdAt: $0.createdAt) },
            columns: columns.map { .init(id: $0.id, title: $0.title, sortOrder: $0.sortOrder, boardID: $0.boardID) },
            tasks: tasks.map { .init(id: $0.id, title: $0.title, details: $0.details, priorityRawValue: $0.priorityRawValue, sortOrder: $0.sortOrder, columnID: $0.columnID, createdAt: $0.createdAt) }
        )
    }

    func validate() throws {
        guard formatVersion == 1 else { throw ArchiveError.unsupportedVersion(formatVersion) }
        let boardIDs = Set(boards.map(\.id))
        let columnIDs = Set(columns.map(\.id))
        guard boardIDs.count == boards.count, columnIDs.count == columns.count else { throw ArchiveError.duplicateIdentifiers }
        guard columns.allSatisfy({ boardIDs.contains($0.boardID) }),
              tasks.allSatisfy({ columnIDs.contains($0.columnID) }) else { throw ArchiveError.brokenReferences }
        guard boards.allSatisfy({ !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              columns.allSatisfy({ !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              tasks.allSatisfy({ !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { throw ArchiveError.emptyTitles }
    }

    /// Imports as additional boards to avoid silently replacing existing local data.
    func importInto(_ context: ModelContext) throws {
        try validate()
        var boardIDMap: [UUID: UUID] = [:]
        var columnIDMap: [UUID: UUID] = [:]
        for record in boards.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            let newID = UUID()
            boardIDMap[record.id] = newID
            context.insert(Board(id: newID, title: record.title, sortOrder: record.sortOrder, createdAt: record.createdAt))
        }
        for record in columns.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            guard let boardID = boardIDMap[record.boardID] else { throw ArchiveError.brokenReferences }
            let newID = UUID()
            columnIDMap[record.id] = newID
            context.insert(BoardColumn(id: newID, title: record.title, sortOrder: record.sortOrder, boardID: boardID))
        }
        for record in tasks {
            guard let columnID = columnIDMap[record.columnID] else { throw ArchiveError.brokenReferences }
            context.insert(TaskCard(id: UUID(), title: record.title, details: record.details, priority: TaskPriority(rawValue: record.priorityRawValue) ?? .normal, sortOrder: record.sortOrder, columnID: columnID, createdAt: record.createdAt))
        }
        try context.save()
    }
}

enum ArchiveError: LocalizedError {
    case unsupportedVersion(Int)
    case duplicateIdentifiers
    case brokenReferences
    case emptyTitles

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version): "Версия архива \(version) не поддерживается."
        case .duplicateIdentifiers: "Архив содержит повторяющиеся идентификаторы."
        case .brokenReferences: "В архиве есть задачи или колонки без родительской записи."
        case .emptyTitles: "В архиве есть записи без названия."
        }
    }
}
