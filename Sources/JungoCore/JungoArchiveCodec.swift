import Foundation

/// The single JSON boundary for Jungo backups. Archives are validated before
/// they are written or handed to the persistence layer.
public enum JungoArchiveCodec {
    public static func encode(_ archive: JungoArchiveDocument) throws -> Data {
        try validate(archive)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(archive)
    }

    public static func decode(_ data: Data) throws -> JungoArchiveDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(JungoArchiveDocument.self, from: data)
        try validate(archive)
        return archive
    }

    private static func validate(_ archive: JungoArchiveDocument) throws {
        try ArchiveValidation.validate(
            formatVersion: archive.formatVersion,
            boards: archive.boards.map { .init(id: $0.id, title: $0.title) },
            columns: archive.columns.map { .init(id: $0.id, title: $0.title, boardID: $0.boardID) },
            tasks: archive.tasks.map { .init(id: $0.id, title: $0.title, columnID: $0.columnID) },
            checklistItems: (archive.checklistItems ?? []).map {
                .init(id: $0.id, title: $0.title, taskID: $0.taskID)
            }
        )
    }
}
