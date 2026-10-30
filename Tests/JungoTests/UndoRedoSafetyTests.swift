import XCTest
import SwiftData
import JungoCore
@testable import Jungo

final class UndoRedoSafetyTests: XCTestCase {
    @MainActor
    private static func makeContext() throws -> (ModelContainer, ModelContext, UndoManager) {
        let schema = Schema([Board.self, BoardColumn.self, TaskCard.self, TaskChecklistItem.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let undoManager = UndoManager()
        context.undoManager = undoManager
        return (container, context, undoManager)
    }

    func testUndoAndRedoRestoreCascadeDeletedBoardGraph() async throws {
        try await MainActor.run {
            print("UndoRedoSafetyTests: creating in-memory context")
            let (_, context, undoManager) = try Self.makeContext()
            let board = Board(title: "Board")
            let column = BoardColumn(title: "Todo", sortOrder: 0, boardID: board.id)
            let task = TaskCard(title: "Task", columnID: column.id)
            let checklist = TaskChecklistItem(title: "Step", sortOrder: 0, taskID: task.id)

            context.insert(board)
            context.insert(column)
            context.insert(task)
            context.insert(checklist)
            try context.save()
            undoManager.removeAllActions()

            // Mirrors deleteSelectedBoard(): remove children before their parents.
            context.delete(checklist)
            context.delete(task)
            context.delete(column)
            context.delete(board)
            try context.save()

            XCTAssertEqual(try context.fetch(FetchDescriptor<Board>()).count, 0)
            XCTAssertEqual(try context.fetch(FetchDescriptor<BoardColumn>()).count, 0)
            XCTAssertEqual(try context.fetch(FetchDescriptor<TaskCard>()).count, 0)
            XCTAssertEqual(try context.fetch(FetchDescriptor<TaskChecklistItem>()).count, 0)

            print("UndoRedoSafetyTests: before cascade undo")
            undoManager.undo()
            print("UndoRedoSafetyTests: after cascade undo")

            let restoredBoards = try context.fetch(FetchDescriptor<Board>())
            let restoredColumns = try context.fetch(FetchDescriptor<BoardColumn>())
            let restoredTasks = try context.fetch(FetchDescriptor<TaskCard>())
            let restoredChecklist = try context.fetch(FetchDescriptor<TaskChecklistItem>())

            XCTAssertEqual(restoredBoards.map(\.id), [board.id])
            XCTAssertEqual(restoredColumns.map(\.id), [column.id])
            XCTAssertEqual(restoredTasks.map(\.id), [task.id])
            XCTAssertEqual(restoredChecklist.map(\.id), [checklist.id])
            XCTAssertEqual(restoredColumns.first?.boardID, board.id)
            XCTAssertEqual(restoredTasks.first?.columnID, column.id)
            XCTAssertEqual(restoredChecklist.first?.taskID, task.id)

            undoManager.redo()

            XCTAssertEqual(try context.fetch(FetchDescriptor<Board>()).count, 0)
            XCTAssertEqual(try context.fetch(FetchDescriptor<BoardColumn>()).count, 0)
            XCTAssertEqual(try context.fetch(FetchDescriptor<TaskCard>()).count, 0)
            XCTAssertEqual(try context.fetch(FetchDescriptor<TaskChecklistItem>()).count, 0)
        }
    }

    func testUndoAndRedoRestoreTaskMoveAcrossColumns() async throws {
        try await MainActor.run {
            let (_, context, undoManager) = try makeContext()
            let board = Board(title: "Board")
            let source = BoardColumn(title: "Todo", sortOrder: 0, boardID: board.id)
            let destination = BoardColumn(title: "Doing", sortOrder: 1, boardID: board.id)
            let task = TaskCard(title: "Move me", sortOrder: 0, columnID: source.id)

            context.insert(board)
            context.insert(source)
            context.insert(destination)
            context.insert(task)
            try context.save()
            undoManager.removeAllActions()

            task.columnID = destination.id
            task.sortOrder = 0
            try context.save()

            undoManager.undo()
            XCTAssertEqual(task.columnID, source.id)
            XCTAssertEqual(task.sortOrder, 0)

            undoManager.redo()
            XCTAssertEqual(task.columnID, destination.id)
            XCTAssertEqual(task.sortOrder, 0)
        }
    }

    func testUndoAndRedoRestoreTrashStateWithoutDeletingTask() async throws {
        try await MainActor.run {
            let (_, context, undoManager) = try makeContext()
            let board = Board(title: "Board")
            let column = BoardColumn(title: "Todo", sortOrder: 0, boardID: board.id)
            let task = TaskCard(title: "Recoverable task", columnID: column.id)

            context.insert(board)
            context.insert(column)
            context.insert(task)
            try context.save()
            undoManager.removeAllActions()

            task.isInTrash = true
            try context.save()

            undoManager.undo()
            XCTAssertFalse(task.isInTrash)
            XCTAssertEqual(try context.fetch(FetchDescriptor<TaskCard>()).count, 1)

            undoManager.redo()
            XCTAssertTrue(task.isInTrash)
            XCTAssertEqual(try context.fetch(FetchDescriptor<TaskCard>()).count, 1)
        }
    }
}
