import Foundation
import SwiftData
import AppKit

/// Owns the on-disk SwiftData location. The original default.store location is retained
/// until the user explicitly moves the vault.
@MainActor
enum VaultStore {
    static let bookmarkDefaultsKey = "jungo.vault.folderBookmark"
    static let pathDefaultsKey = "jungo.vault.folderPath"
    static let schema = Schema([Board.self, BoardColumn.self, TaskCard.self, TaskChecklistItem.self])

    private(set) static var activeScopedFolderURL: URL?

    enum VaultError: LocalizedError {
        case selectedFolderUnavailable
        case destinationAlreadyExists(URL)
        case invalidReferences
        case verificationFailed
        case existingVaultNotFound
        case invalidStore

        var errorDescription: String? {
            switch self {
            case .selectedFolderUnavailable:
                "Папка хранилища недоступна. Jungo не переключился на пустую базу: исходные данные не изменены."
            case .destinationAlreadyExists(let url):
                "В выбранной папке уже есть файл хранилища: \(url.lastPathComponent). Чтобы не перезаписать данные, перенос остановлен."
            case .invalidReferences:
                "В базе найдены связи между досками, колонками и задачами, которые не удалось проверить. Операция отменена."
            case .verificationFailed:
                "Проверка новой базы не прошла. Активное хранилище осталось прежним."
            case .existingVaultNotFound:
                "В выбранной папке не найден Jungo.store. Восстановление доступа не изменило настройки и данные."
            case .invalidStore:
                "Файл Jungo.store пустой или не похож на существующее хранилище Jungo. Настройки доступа не изменены."
            }
        }
    }

    static var currentFolderURL: URL {
        if let url = resolveSelectedFolder() { return url }
        // Keep showing the configured location when a bookmark cannot currently
        // resolve (for example, while an external drive is disconnected). Container
        // creation still requires a successfully resolved bookmark and never falls
        // back to the default store.
        if UserDefaults.standard.data(forKey: bookmarkDefaultsKey) != nil,
           let savedPath = UserDefaults.standard.string(forKey: pathDefaultsKey),
           !savedPath.isEmpty {
            return URL(fileURLWithPath: savedPath, isDirectory: true)
        }
        return defaultFolderURL
    }

    static var currentStoreURL: URL {
        if UserDefaults.standard.data(forKey: bookmarkDefaultsKey) != nil {
            return currentFolderURL.appendingPathComponent("Jungo.store")
        }
        return defaultStoreURL
    }

    /// Use SwiftData's own default configuration to discover its URL instead of
    /// guessing where the framework stores the database. This keeps the Finder
    /// location aligned with the same configuration used for existing installs.
    private static var defaultConfiguration: ModelConfiguration {
        ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
    }

    static var defaultFolderURL: URL {
        defaultStoreURL.deletingLastPathComponent()
    }

    static var defaultStoreURL: URL {
        defaultConfiguration.url
    }

    static func makeContainer() throws -> ModelContainer {
        let configuration: ModelConfiguration
        if UserDefaults.standard.data(forKey: bookmarkDefaultsKey) != nil {
            guard let folder = resolveSelectedFolder(),
                  FileManager.default.fileExists(atPath: folder.path) else {
                throw VaultError.selectedFolderUnavailable
            }
            configuration = ModelConfiguration(
                "JungoVault",
                schema: schema,
                url: folder.appendingPathComponent("Jungo.store"),
                allowsSave: true,
                cloudKitDatabase: .none
            )
        } else {
            // Keep the same SwiftData default configuration used before Vault settings.
            configuration = defaultConfiguration
        }

        let container = try ModelContainer(for: schema, configurations: [configuration])
        container.mainContext.undoManager = UndoManager()
        return container
    }

    @discardableResult
    static func moveVault(from sourceContext: ModelContext, to folderURL: URL) throws -> URL {
        let folder = folderURL.standardizedFileURL
        let didStartAccess = folderURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess { folderURL.stopAccessingSecurityScopedResource() }
        }
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: folder.path) else {
            throw VaultError.selectedFolderUnavailable
        }

        let targetURL = folder.appendingPathComponent("Jungo.store")
        if targetURL.standardizedFileURL == currentStoreURL.standardizedFileURL {
            return targetURL
        }
        // A SwiftData/SQLite store can have sidecar files even when the main
        // database file is absent (for example after an interrupted cleanup).
        // Treat any existing artifact as occupied so a failed attempt never
        // removes data that was already present in the destination folder.
        let destinationArtifacts = [
            targetURL,
            URL(fileURLWithPath: targetURL.path + "-wal"),
            URL(fileURLWithPath: targetURL.path + "-shm"),
            URL(fileURLWithPath: targetURL.path + "-journal")
        ]
        if let existingArtifact = destinationArtifacts.first(where: {
            fileManager.fileExists(atPath: $0.path)
        }) {
            throw VaultError.destinationAlreadyExists(existingArtifact)
        }

        // Create the bookmark before touching data, but do not activate it until
        // the destination has been fully copied and verified.
        let bookmark = try makeBookmark(for: folder)
        try sourceContext.save()

        do {
            try copyAndVerify(sourceContext: sourceContext, targetURL: targetURL)
            UserDefaults.standard.set(bookmark, forKey: bookmarkDefaultsKey)
            UserDefaults.standard.set(folder.path, forKey: pathDefaultsKey)
            _ = resolveSelectedFolder()
            return targetURL
        } catch {
            // The destination did not exist before this operation, so remove only
            // the files created by this failed attempt. The source store is untouched.
            removeStoreFiles(at: targetURL)
            throw error
        }
    }

    static func restoreAccess(to folderURL: URL) throws {
        let folder = folderURL.standardizedFileURL
        let didStartAccess = folderURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess { folderURL.stopAccessingSecurityScopedResource() }
        }
        let storeURL = folder.appendingPathComponent("Jungo.store")
        guard FileManager.default.fileExists(atPath: storeURL.path) else {
            throw VaultError.existingVaultNotFound
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: storeURL.path)
        guard let fileSize = attributes[.size] as? NSNumber, fileSize.intValue > 0 else {
            throw VaultError.invalidStore
        }
        // Do not persist a bookmark to a file that merely exists. Open the
        // database and validate its complete object graph first; otherwise a
        // corrupt or unrelated file could become the active vault.
        try validateStore(at: storeURL)

        let bookmark = try makeBookmark(for: folder)
        UserDefaults.standard.set(bookmark, forKey: bookmarkDefaultsKey)
        UserDefaults.standard.set(folder.path, forKey: pathDefaultsKey)
    }

    static func openCurrentFolderInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([currentStoreURL])
    }

    private static func resolveSelectedFolder() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkDefaultsKey) else { return nil }
        var stale = false
        let url: URL
        if let scopedURL = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) {
            url = scopedURL
        } else {
            // Bookmarks created by a non-sandboxed build may be ordinary bookmarks.
            stale = false
            guard let ordinaryURL = try? URL(
                resolvingBookmarkData: data,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) else { return nil }
            url = ordinaryURL
        }

        if stale, let refreshed = try? makeBookmark(for: url) {
            UserDefaults.standard.set(refreshed, forKey: bookmarkDefaultsKey)
            UserDefaults.standard.set(url.path, forKey: pathDefaultsKey)
        }
        if activeScopedFolderURL?.standardizedFileURL != url.standardizedFileURL {
            // Clear the old URL immediately after releasing its scope. If access to
            // the new folder fails, retaining the old URL would falsely imply that
            // its security scope is still active and prevent a later retry.
            _ = activeScopedFolderURL?.stopAccessingSecurityScopedResource()
            activeScopedFolderURL = nil
            if url.startAccessingSecurityScopedResource() {
                activeScopedFolderURL = url
            }
        }
        return url
    }

    private static func makeBookmark(for url: URL) throws -> Data {
        do {
            return try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            // Non-sandboxed local builds can use ordinary bookmarks on macOS.
            return try url.bookmarkData(
                options: [.minimalBookmark],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }
    }

    private static func validateStore(at storeURL: URL) throws {
        let configuration = ModelConfiguration(
            "JungoVault",
            schema: schema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let boards = try context.fetch(FetchDescriptor<Board>())
        let columns = try context.fetch(FetchDescriptor<BoardColumn>())
        let tasks = try context.fetch(FetchDescriptor<TaskCard>())
        let checklistItems = try context.fetch(FetchDescriptor<TaskChecklistItem>())

        try validateReferences(
            boards: boards,
            columns: columns,
            tasks: tasks,
            checklistItems: checklistItems
        )
    }

    private static func validateReferences(
        boards: [Board],
        columns: [BoardColumn],
        tasks: [TaskCard],
        checklistItems: [TaskChecklistItem]
    ) throws {
        let boardIDs = Set(boards.map(\.id))
        let columnIDs = Set(columns.map(\.id))
        let taskIDs = Set(tasks.map(\.id))
        let checklistIDs = Set(checklistItems.map(\.id))

        guard boardIDs.count == boards.count,
              columnIDs.count == columns.count,
              taskIDs.count == tasks.count,
              checklistIDs.count == checklistItems.count,
              columns.allSatisfy({ boardIDs.contains($0.boardID) }),
              tasks.allSatisfy({ columnIDs.contains($0.columnID) }),
              checklistItems.allSatisfy({ taskIDs.contains($0.taskID) }) else {
            throw VaultError.invalidReferences
        }
    }

    private static func copyAndVerify(sourceContext: ModelContext, targetURL: URL) throws {
        let boards = try sourceContext.fetch(FetchDescriptor<Board>())
        let columns = try sourceContext.fetch(FetchDescriptor<BoardColumn>())
        let tasks = try sourceContext.fetch(FetchDescriptor<TaskCard>())
        let checklistItems = try sourceContext.fetch(FetchDescriptor<TaskChecklistItem>())

        try validateReferences(
            boards: boards,
            columns: columns,
            tasks: tasks,
            checklistItems: checklistItems
        )

        // Retain source ID sets for the post-copy equality check below.
        let boardIDs = Set(boards.map(\.id))
        let columnIDs = Set(columns.map(\.id))
        let taskIDs = Set(tasks.map(\.id))
        let checklistIDs = Set(checklistItems.map(\.id))

        let targetConfiguration = ModelConfiguration(
            "JungoVault",
            schema: schema,
            url: targetURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        let targetContainer = try ModelContainer(for: schema, configurations: [targetConfiguration])
        let targetContext = ModelContext(targetContainer)

        for item in boards {
            targetContext.insert(Board(id: item.id, title: item.title, sortOrder: item.sortOrder, createdAt: item.createdAt, isArchived: item.isArchived))
        }
        for item in columns {
            targetContext.insert(BoardColumn(id: item.id, title: item.title, sortOrder: item.sortOrder, boardID: item.boardID))
        }
        for item in tasks {
            let copiedTask = TaskCard(
                id: item.id,
                title: item.title,
                details: item.details,
                labelsText: item.labelsText,
                priority: item.priority,
                sortOrder: item.sortOrder,
                columnID: item.columnID,
                createdAt: item.createdAt,
                dueDate: item.dueDate,
                isInTrash: item.isInTrash
            )
            // Preserve the stored raw value exactly, including values introduced by
            // a newer app version. The computed enum may map unknown values to .normal.
            copiedTask.priorityRawValue = item.priorityRawValue
            targetContext.insert(copiedTask)
        }
        for item in checklistItems {
            targetContext.insert(TaskChecklistItem(
                id: item.id,
                title: item.title,
                isCompleted: item.isCompleted,
                sortOrder: item.sortOrder,
                taskID: item.taskID
            ))
        }

        try targetContext.save()
        let copiedBoards = try targetContext.fetch(FetchDescriptor<Board>())
        let copiedColumns = try targetContext.fetch(FetchDescriptor<BoardColumn>())
        let copiedTasks = try targetContext.fetch(FetchDescriptor<TaskCard>())
        let copiedChecklistItems = try targetContext.fetch(FetchDescriptor<TaskChecklistItem>())

        let copiedBoardsByID = Dictionary(uniqueKeysWithValues: copiedBoards.map { ($0.id, $0) })
        let copiedColumnsByID = Dictionary(uniqueKeysWithValues: copiedColumns.map { ($0.id, $0) })
        let copiedTasksByID = Dictionary(uniqueKeysWithValues: copiedTasks.map { ($0.id, $0) })
        let copiedChecklistByID = Dictionary(uniqueKeysWithValues: copiedChecklistItems.map { ($0.id, $0) })

        let boardValuesMatch = boards.allSatisfy { source in
            guard let copy = copiedBoardsByID[source.id] else { return false }
            return copy.title == source.title
                && copy.sortOrder == source.sortOrder
                && copy.createdAt == source.createdAt
                && copy.isArchived == source.isArchived
        }
        let columnValuesMatch = columns.allSatisfy { source in
            guard let copy = copiedColumnsByID[source.id] else { return false }
            return copy.title == source.title
                && copy.sortOrder == source.sortOrder
                && copy.boardID == source.boardID
        }
        let taskValuesMatch = tasks.allSatisfy { source in
            guard let copy = copiedTasksByID[source.id] else { return false }
            return copy.title == source.title
                && copy.details == source.details
                && copy.labelsText == source.labelsText
                && copy.priorityRawValue == source.priorityRawValue
                && copy.sortOrder == source.sortOrder
                && copy.columnID == source.columnID
                && copy.createdAt == source.createdAt
                && copy.dueDate == source.dueDate
                && copy.isInTrash == source.isInTrash
        }
        let checklistValuesMatch = checklistItems.allSatisfy { source in
            guard let copy = copiedChecklistByID[source.id] else { return false }
            return copy.title == source.title
                && copy.isCompleted == source.isCompleted
                && copy.sortOrder == source.sortOrder
                && copy.taskID == source.taskID
        }

        guard copiedBoards.count == boards.count,
              copiedColumns.count == columns.count,
              copiedTasks.count == tasks.count,
              copiedChecklistItems.count == checklistItems.count,
              Set(copiedBoards.map(\.id)) == boardIDs,
              Set(copiedColumns.map(\.id)) == columnIDs,
              Set(copiedTasks.map(\.id)) == taskIDs,
              Set(copiedChecklistItems.map(\.id)) == checklistIDs,
              boardValuesMatch,
              columnValuesMatch,
              taskValuesMatch,
              checklistValuesMatch else {
            throw VaultError.verificationFailed
        }
    }

    private static func removeStoreFiles(at url: URL) {
        let fileManager = FileManager.default
        for candidate in [
            url,
            URL(fileURLWithPath: url.path + "-wal"),
            URL(fileURLWithPath: url.path + "-shm"),
            URL(fileURLWithPath: url.path + "-journal")
        ] where fileManager.fileExists(atPath: candidate.path) {
            try? fileManager.removeItem(at: candidate)
        }
    }
}
