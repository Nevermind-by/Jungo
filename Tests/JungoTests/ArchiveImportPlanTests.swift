import XCTest
import JungoCore

final class ArchiveImportPlanTests: XCTestCase {
    func testBuildRemapsEveryIDAndKeepsRelationshipsInternal() throws {
        let boardA = UUID()
        let boardB = UUID()
        let columnA = UUID()
        let columnB = UUID()
        let taskA = UUID()
        let checklistA = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_735_689_600)
        let dueDate = Date(timeIntervalSince1970: 1_736_000_000)

        let archive = JungoArchiveDocument(
            formatVersion: 1,
            exportedAt: createdAt,
            boards: [
                .init(id: boardA, title: "Archived board", sortOrder: 4, createdAt: createdAt, isArchived: true),
                .init(id: boardB, title: "Active board", sortOrder: 1, createdAt: createdAt, isArchived: false)
            ],
            columns: [
                .init(id: columnA, title: "Doing", sortOrder: 2, boardID: boardA),
                .init(id: columnB, title: "Backlog", sortOrder: 0, boardID: boardB)
            ],
            tasks: [
                .init(
                    id: taskA,
                    title: "Keep all fields",
                    details: "Details",
                    labelsText: "QA, Release",
                    priorityRawValue: "critical_v2",
                    sortOrder: 7,
                    columnID: columnA,
                    createdAt: createdAt,
                    dueDate: dueDate,
                    isInTrash: true
                )
            ],
            checklistItems: [
                .init(id: checklistA, title: "Verify mapping", isCompleted: true, sortOrder: 3, taskID: taskA)
            ]
        )

        let plan = try JungoArchiveImportPlan.build(from: archive, nextBoardSortOrder: 8)

        XCTAssertEqual(plan.boards.map(\.sortOrder), [8, 9])
        XCTAssertEqual(plan.boards.map(\.title), ["Active board", "Archived board"])
        XCTAssertEqual(plan.boards.last?.isArchived, true)
        XCTAssertEqual(plan.columns.count, 2)
        XCTAssertEqual(plan.tasks.first?.priorityRawValue, "critical_v2")
        XCTAssertEqual(plan.tasks.first?.labelsText, "QA, Release")
        XCTAssertEqual(plan.tasks.first?.dueDate, dueDate)
        XCTAssertEqual(plan.tasks.first?.isInTrash, true)
        XCTAssertEqual(plan.checklistItems.first?.isCompleted, true)

        let importedBoardA = try XCTUnwrap(plan.boards.first { $0.title == "Archived board" })
        let importedColumnA = try XCTUnwrap(plan.columns.first { $0.title == "Doing" })
        let importedTaskA = try XCTUnwrap(plan.tasks.first)
        let importedChecklistA = try XCTUnwrap(plan.checklistItems.first)

        XCTAssertNotEqual(importedBoardA.id, boardA)
        XCTAssertNotEqual(importedColumnA.id, columnA)
        XCTAssertNotEqual(importedTaskA.id, taskA)
        XCTAssertNotEqual(importedChecklistA.id, checklistA)
        XCTAssertEqual(importedColumnA.boardID, importedBoardA.id)
        XCTAssertEqual(importedTaskA.columnID, importedColumnA.id)
        XCTAssertEqual(importedChecklistA.taskID, importedTaskA.id)
        XCTAssertEqual(plan.lastImportedBoardID, plan.boards.last?.id)

        let generatedIDs = plan.boards.map(\.id)
            + plan.columns.map(\.id)
            + plan.tasks.map(\.id)
            + plan.checklistItems.map(\.id)
        XCTAssertEqual(Set(generatedIDs).count, generatedIDs.count)
    }

    func testRepeatedPlansCreateIndependentCopies() throws {
        let boardID = UUID()
        let columnID = UUID()
        let taskID = UUID()
        let date = Date(timeIntervalSince1970: 1_735_689_600)
        let archive = JungoArchiveDocument(
            formatVersion: 1,
            exportedAt: date,
            boards: [.init(id: boardID, title: "Board", sortOrder: 0, createdAt: date)],
            columns: [.init(id: columnID, title: "Todo", sortOrder: 0, boardID: boardID)],
            tasks: [.init(id: taskID, title: "Task", details: "", priorityRawValue: "high", sortOrder: 0, columnID: columnID, createdAt: date)],
            checklistItems: []
        )

        let first = try JungoArchiveImportPlan.build(from: archive, nextBoardSortOrder: 0)
        let second = try JungoArchiveImportPlan.build(from: archive, nextBoardSortOrder: 1)

        XCTAssertNotEqual(first.boards.first?.id, second.boards.first?.id)
        XCTAssertNotEqual(first.columns.first?.id, second.columns.first?.id)
        XCTAssertNotEqual(first.tasks.first?.id, second.tasks.first?.id)
        XCTAssertEqual(first.tasks.first?.columnID, first.columns.first?.id)
        XCTAssertEqual(second.tasks.first?.columnID, second.columns.first?.id)
        XCTAssertNotEqual(first.tasks.first?.columnID, second.tasks.first?.columnID)
    }

    func testBuildRejectsInvalidArchiveBeforeProducingPlan() {
        let date = Date(timeIntervalSince1970: 1_735_689_600)
        let archive = JungoArchiveDocument(
            formatVersion: 1,
            exportedAt: date,
            boards: [.init(id: UUID(), title: "Board", sortOrder: 0, createdAt: date)],
            columns: [.init(id: UUID(), title: "Orphan", sortOrder: 0, boardID: UUID())],
            tasks: [],
            checklistItems: []
        )

        XCTAssertThrowsError(try JungoArchiveImportPlan.build(from: archive, nextBoardSortOrder: 0)) {
            XCTAssertEqual($0 as? ArchiveValidationError, .brokenReferences)
        }
    }
}
