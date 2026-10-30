import XCTest
import JungoCore

final class ArchiveCodecTests: XCTestCase {
    private let timestamp = Date(timeIntervalSince1970: 1_735_689_600)

    func testRoundTripsAllArchiveFieldsThroughCodec() throws {
        let boardID = UUID()
        let columnID = UUID()
        let taskID = UUID()
        let checklistID = UUID()
        let archive = JungoArchiveDocument(
            formatVersion: 1,
            exportedAt: timestamp,
            boards: [
                .init(id: boardID, title: "Board", sortOrder: 3, createdAt: timestamp, isArchived: true)
            ],
            columns: [
                .init(id: columnID, title: "Doing", sortOrder: 2, boardID: boardID)
            ],
            tasks: [
                .init(
                    id: taskID,
                    title: "Task",
                    details: "Details",
                    labelsText: "QA, Regression",
                    priorityRawValue: "critical_v2",
                    sortOrder: 4,
                    columnID: columnID,
                    createdAt: timestamp,
                    dueDate: timestamp,
                    isInTrash: true
                )
            ],
            checklistItems: [
                .init(id: checklistID, title: "Verify", isCompleted: true, sortOrder: 1, taskID: taskID)
            ]
        )

        let data = try JungoArchiveCodec.encode(archive)
        let decoded = try JungoArchiveCodec.decode(data)

        XCTAssertEqual(decoded.formatVersion, 1)
        XCTAssertEqual(decoded.boards.first?.isArchived, true)
        XCTAssertEqual(decoded.columns.first?.sortOrder, 2)
        XCTAssertEqual(decoded.tasks.first?.labelsText, "QA, Regression")
        XCTAssertEqual(decoded.tasks.first?.priorityRawValue, "critical_v2")
        XCTAssertEqual(decoded.tasks.first?.dueDate, timestamp)
        XCTAssertEqual(decoded.tasks.first?.isInTrash, true)
        XCTAssertEqual(decoded.checklistItems?.first?.isCompleted, true)
    }

    func testDecodeRejectsBrokenReferencesBeforeImport() throws {
        let archive = makeArchive(columnBoardID: UUID())
        let data = try rawEncode(archive)

        XCTAssertThrowsError(try JungoArchiveCodec.decode(data)) {
            XCTAssertEqual($0 as? ArchiveValidationError, .brokenReferences)
        }
    }

    func testDecodeRejectsEmptyTitlesBeforeImport() throws {
        let archive = makeArchive(boardTitle: "  ")
        let data = try rawEncode(archive)

        XCTAssertThrowsError(try JungoArchiveCodec.decode(data)) {
            XCTAssertEqual($0 as? ArchiveValidationError, .emptyTitles)
        }
    }

    func testEncodeRejectsUnsupportedArchiveVersion() {
        let archive = makeArchive(version: 99)

        XCTAssertThrowsError(try JungoArchiveCodec.encode(archive)) {
            XCTAssertEqual($0 as? ArchiveValidationError, .unsupportedVersion(99))
        }
    }

    func testDecodeRejectsMalformedJSON() {
        XCTAssertThrowsError(try JungoArchiveCodec.decode(Data("{ invalid".utf8)))
    }

    private func makeArchive(
        version: Int = 1,
        boardTitle: String = "Board",
        columnBoardID: UUID? = nil
    ) -> JungoArchiveDocument {
        let boardID = UUID()
        let columnID = UUID()
        return JungoArchiveDocument(
            formatVersion: version,
            exportedAt: timestamp,
            boards: [.init(id: boardID, title: boardTitle, sortOrder: 0, createdAt: timestamp)],
            columns: [.init(id: columnID, title: "Todo", sortOrder: 0, boardID: columnBoardID ?? boardID)],
            tasks: [],
            checklistItems: []
        )
    }

    private func rawEncode(_ archive: JungoArchiveDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(archive)
    }
}
