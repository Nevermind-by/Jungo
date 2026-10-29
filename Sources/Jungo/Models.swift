import Foundation
import SwiftData

@Model
final class Board {
    @Attribute(.unique) var id: UUID
    var title: String
    var sortOrder: Int
    var createdAt: Date

    init(id: UUID = UUID(), title: String, sortOrder: Int = 0, createdAt: Date = .now) {
        self.id = id
        self.title = title
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }
}

@Model
final class BoardColumn {
    @Attribute(.unique) var id: UUID
    var title: String
    var sortOrder: Int
    var boardID: UUID

    init(id: UUID = UUID(), title: String, sortOrder: Int, boardID: UUID) {
        self.id = id
        self.title = title
        self.sortOrder = sortOrder
        self.boardID = boardID
    }
}

@Model
final class TaskCard {
    @Attribute(.unique) var id: UUID
    var title: String
    var details: String
    var priorityRawValue: String
    var sortOrder: Int
    var columnID: UUID
    var createdAt: Date

    var priority: TaskPriority {
        get { TaskPriority(rawValue: priorityRawValue) ?? .normal }
        set { priorityRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        title: String,
        details: String = "",
        priority: TaskPriority = .normal,
        sortOrder: Int = 0,
        columnID: UUID,
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.details = details
        self.priorityRawValue = priority.rawValue
        self.sortOrder = sortOrder
        self.columnID = columnID
        self.createdAt = createdAt
    }
}

enum TaskPriority: String, CaseIterable, Identifiable {
    case low
    case normal
    case high

    var id: String { rawValue }

    var title: String {
        switch self {
        case .low: "Низкий"
        case .normal: "Обычный"
        case .high: "Высокий"
        }
    }

    var symbol: String {
        switch self {
        case .low: "arrow.down"
        case .normal: "minus"
        case .high: "arrow.up"
        }
    }
}
