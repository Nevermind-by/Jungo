import XCTest
import JungoCore

final class ArchiveValidationTests: XCTestCase {
    private let boardID = UUID()
    private let columnID = UUID()
    private let taskID = UUID()
    private let checklistID = UUID()

    func testAcceptsValidArchiveWithChecklist() throws {
        try validate(checklistItems: [
            .init(id: checklistID, title: "Subtask", taskID: taskID)
        ])
    }

    func testRejectsUnsupportedFormatVersion() {
        XCTAssertThrowsError(try validate(version: 2)) {
            XCTAssertEqual($0 as? ArchiveValidationError, .unsupportedVersion(2))
        }
    }

    func testRejectsDuplicateIdentifiersWithinEntityType() {
        let duplicateTasks = [
            ArchiveValidation.TaskRecord(id: taskID, title: "First", columnID: columnID),
            ArchiveValidation.TaskRecord(id: taskID, title: "Second", columnID: columnID)
        ]
        XCTAssertThrowsError(try validate(tasks: duplicateTasks)) {
            XCTAssertEqual($0 as? ArchiveValidationError, .duplicateIdentifiers)
        }
    }

    func testRejectsColumnWithoutBoard() {
        let columns = [
            ArchiveValidation.ColumnRecord(id: columnID, title: "Column", boardID: UUID())
        ]
        XCTAssertThrowsError(try validate(columns: columns)) {
            XCTAssertEqual($0 as? ArchiveValidationError, .brokenReferences)
        }
    }

    func testRejectsTaskWithoutColumn() {
        let tasks = [
            ArchiveValidation.TaskRecord(id: taskID, title: "Task", columnID: UUID())
        ]
        XCTAssertThrowsError(try validate(tasks: tasks)) {
            XCTAssertEqual($0 as? ArchiveValidationError, .brokenReferences)
        }
    }

    func testRejectsChecklistItemWithoutTask() {
        let items = [
            ArchiveValidation.ChecklistRecord(id: checklistID, title: "Subtask", taskID: UUID())
        ]
        XCTAssertThrowsError(try validate(checklistItems: items)) {
            XCTAssertEqual($0 as? ArchiveValidationError, .brokenReferences)
        }
    }

    func testRejectsBlankTitlesAcrossAllRecordTypes() {
        XCTAssertThrowsError(try validate(boards: [.init(id: boardID, title: "  ")])) {
            XCTAssertEqual($0 as? ArchiveValidationError, .emptyTitles)
        }
        XCTAssertThrowsError(try validate(columns: [.init(id: columnID, title: "", boardID: boardID)])) {
            XCTAssertEqual($0 as? ArchiveValidationError, .emptyTitles)
        }
        XCTAssertThrowsError(try validate(tasks: [.init(id: taskID, title: "\n", columnID: columnID)])) {
            XCTAssertEqual($0 as? ArchiveValidationError, .emptyTitles)
        }
        XCTAssertThrowsError(try validate(checklistItems: [.init(id: checklistID, title: " ", taskID: taskID)])) {
            XCTAssertEqual($0 as? ArchiveValidationError, .emptyTitles)
        }
    }

    private func validate(
        version: Int = 1,
        boards: [ArchiveValidation.BoardRecord]? = nil,
        columns: [ArchiveValidation.ColumnRecord]? = nil,
        tasks: [ArchiveValidation.TaskRecord]? = nil,
        checklistItems: [ArchiveValidation.ChecklistRecord] = []
    ) throws {
        try ArchiveValidation.validate(
            formatVersion: version,
            boards: boards ?? [.init(id: boardID, title: "Board")],
            columns: columns ?? [.init(id: columnID, title: "Column", boardID: boardID)],
            tasks: tasks ?? [.init(id: taskID, title: "Task", columnID: columnID)],
            checklistItems: checklistItems
        )
    }
}
