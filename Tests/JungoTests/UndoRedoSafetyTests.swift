import SwiftData
import AppKit
import Testing
import JungoCore
@testable import Jungo

@Suite("SwiftData Undo/Redo safety", .serialized)
struct UndoRedoSafetyTests {
    @MainActor
    private static func makeContext() throws -> (ModelContainer, ModelContext, UndoManager) {
        let schema = Schema([Board.self, BoardColumn.self, TaskCard.self, TaskChecklistItem.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        context.undoManager = undoManager
        return (container, context, undoManager)
    }

    @Test
    @MainActor
    func undoAndRedoRestoreCascadeDeletedBoardGraph() throws {
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

        undoManager.beginUndoGrouping()
        context.delete(checklist)
        context.delete(task)
        context.delete(column)
        context.delete(board)
        try context.save()
        undoManager.endUndoGrouping()

        #expect(try context.fetch(FetchDescriptor<Board>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<BoardColumn>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<TaskCard>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<TaskChecklistItem>()).isEmpty)

        undoManager.undo()

        let restoredBoards = try context.fetch(FetchDescriptor<Board>())
        let restoredColumns = try context.fetch(FetchDescriptor<BoardColumn>())
        let restoredTasks = try context.fetch(FetchDescriptor<TaskCard>())
        let restoredChecklist = try context.fetch(FetchDescriptor<TaskChecklistItem>())

        #expect(restoredBoards.map { $0.id } == [board.id])
        #expect(restoredColumns.map { $0.id } == [column.id])
        #expect(restoredTasks.map { $0.id } == [task.id])
        #expect(restoredChecklist.map { $0.id } == [checklist.id])
        #expect(restoredColumns.first?.boardID == board.id)
        #expect(restoredTasks.first?.columnID == column.id)
        #expect(restoredChecklist.first?.taskID == task.id)

        undoManager.redo()

        #expect(try context.fetch(FetchDescriptor<Board>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<BoardColumn>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<TaskCard>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<TaskChecklistItem>()).isEmpty)
    }

    @Test
    @MainActor
    func undoAndRedoRestoreTaskMoveAcrossColumns() throws {
        let (_, context, undoManager) = try Self.makeContext()
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

        undoManager.beginUndoGrouping()
        task.columnID = destination.id
        task.sortOrder = 0
        try context.save()
        undoManager.endUndoGrouping()

        undoManager.undo()
        #expect(task.columnID == source.id)
        #expect(task.sortOrder == 0)

        undoManager.redo()
        #expect(task.columnID == destination.id)
        #expect(task.sortOrder == 0)
    }

    @Test
    @MainActor
    func undoAndRedoRestoreTrashStateWithoutDeletingTask() throws {
        let (_, context, undoManager) = try Self.makeContext()
        let board = Board(title: "Board")
        let column = BoardColumn(title: "Todo", sortOrder: 0, boardID: board.id)
        let task = TaskCard(title: "Recoverable task", columnID: column.id)

        context.insert(board)
        context.insert(column)
        context.insert(task)
        try context.save()
        undoManager.removeAllActions()

        undoManager.beginUndoGrouping()
        task.isInTrash = true
        try context.save()
        undoManager.endUndoGrouping()

        undoManager.undo()
        #expect(task.isInTrash == false)
        #expect(try context.fetch(FetchDescriptor<TaskCard>()).count == 1)

        undoManager.redo()
        #expect(task.isInTrash == true)
        #expect(try context.fetch(FetchDescriptor<TaskCard>()).count == 1)
    }
}
