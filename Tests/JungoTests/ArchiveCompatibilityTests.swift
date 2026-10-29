import XCTest
import JungoCore

final class ArchiveCompatibilityTests: XCTestCase {
    func testDecodesLegacyArchiveWithoutOptionalFields() throws {
        let json = """
        {
          "formatVersion": 1,
          "exportedAt": "2025-01-01T00:00:00Z",
          "boards": [
            {
              "id": "00000000-0000-0000-0000-000000000001",
              "title": "Board",
              "sortOrder": 0,
              "createdAt": "2025-01-01T00:00:00Z"
            }
          ],
          "columns": [
            {
              "id": "00000000-0000-0000-0000-000000000002",
              "title": "Todo",
              "sortOrder": 0,
              "boardID": "00000000-0000-0000-0000-000000000001"
            }
          ],
          "tasks": [
            {
              "id": "00000000-0000-0000-0000-000000000003",
              "title": "Task",
              "details": "Legacy details",
              "priorityRawValue": "normal",
              "sortOrder": 0,
              "columnID": "00000000-0000-0000-0000-000000000002",
              "createdAt": "2025-01-01T00:00:00Z"
            }
          ]
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let archive = try decoder.decode(JungoArchiveDocument.self, from: Data(json.utf8))

        XCTAssertNil(archive.checklistItems)
        XCTAssertNil(archive.boards[0].isArchived)
        XCTAssertNil(archive.tasks[0].labelsText)
        XCTAssertNil(archive.tasks[0].dueDate)
        XCTAssertNil(archive.tasks[0].isInTrash)
        XCTAssertEqual(archive.tasks[0].details, "Legacy details")
        try ArchiveValidation.validate(
            formatVersion: archive.formatVersion,
            boards: archive.boards.map { .init(id: $0.id, title: $0.title) },
            columns: archive.columns.map { .init(id: $0.id, title: $0.title, boardID: $0.boardID) },
            tasks: archive.tasks.map { .init(id: $0.id, title: $0.title, columnID: $0.columnID) },
            checklistItems: (archive.checklistItems ?? []).map { .init(id: $0.id, title: $0.title, taskID: $0.taskID) }
        )
    }

    func testRoundTripsCurrentArchiveFields() throws {
        let boardID = UUID()
        let columnID = UUID()
        let taskID = UUID()
        let archive = JungoArchiveDocument(
            formatVersion: 1,
            exportedAt: Date(timeIntervalSince1970: 1_735_689_600),
            boards: [.init(id: boardID, title: "Board", sortOrder: 0, createdAt: Date(timeIntervalSince1970: 1_735_689_600), isArchived: true)],
            columns: [.init(id: columnID, title: "Todo", sortOrder: 0, boardID: boardID)],
            tasks: [.init(id: taskID, title: "Task", details: "Details", labelsText: "QA", priorityRawValue: "high", sortOrder: 0, columnID: columnID, createdAt: Date(timeIntervalSince1970: 1_735_689_600), dueDate: nil, isInTrash: true)],
            checklistItems: [.init(id: UUID(), title: "Step", isCompleted: true, sortOrder: 0, taskID: taskID)]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(archive)
        let decoded = try decoder.decode(JungoArchiveDocument.self, from: data)

        XCTAssertEqual(decoded.boards.first?.isArchived, true)
        XCTAssertEqual(decoded.tasks.first?.labelsText, "QA")
        XCTAssertEqual(decoded.tasks.first?.isInTrash, true)
        XCTAssertEqual(decoded.checklistItems?.first?.isCompleted, true)
    }
}
