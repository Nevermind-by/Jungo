import Foundation
import SwiftData
import AppKit

/// Owns the on-disk SwiftData location. The original default.store location is retained
/// until the user explicitly moves the vault.
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

        var errorDescription: String? {
            switch self {
            case .selectedFolderUnavailable:
                "Папка хранилища недоступна. Jungo не переключился на пустую базу: исходные данные не изменены."
            case .destinationAlreadyExists(let url):
                "В выбранной папке уже есть файл хранилища: \(url.lastPathComponent). Чтобы не перезаписать данные, перенос остановлен."
            case .invalidReferences:
                "В базе найдены связи между досками, колонками и задачами, которые не удалось проверить. Перенос отменён."
            case .verificationFailed:
                "Проверка новой базы не прошла. Активное хранилище осталось прежним."
            }
        }
    }

    static var currentFolderURL: URL {
        if let url = resolveSelectedFolder() { return url }
        return defaultFolderURL
    }

    static var currentStoreURL: URL {
        if UserDefaults.standard.data(forKey: bookmarkDefaultsKey) != nil {
            return currentFolderURL.appendingPathComponent("Jungo.store")
        }
        return defaultStoreURL
    }

    static var defaultFolderURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    static var defaultStoreURL: URL {
        defaultFolderURL.appendingPathComponent("default.store")
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
            // Keep the original SwiftData default configuration for existing installs.
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        }

        let container = try ModelContainer(for: schema, configurations: [configuration])
        container.mainContext.undoManager = UndoManager()
        return container
    }

    @discardableResult
    static func moveVault(from sourceContext: ModelContext, to folderURL: URL) throws -> URL {
        let folder = folderURL.standardizedFileURL
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: folder.path) else {
            throw VaultError.selectedFolderUnavailable
        }

        let targetURL = folder.appendingPathComponent("Jungo.store")
        if targetURL.standardizedFileURL == currentStoreURL.standardizedFileURL {
            return targetURL
        }
        guard !fileManager.fileExists(atPath: targetURL.path) else {
            throw VaultError.destinationAlreadyExists(targetURL)
        }

        // Create the bookmark before touching data, but do not activate it until
        // the destination has been fully copied and verified.
        let bookmark = try makeBookmark(for: folder)
        try sourceContext.save()

        do {
            try copyAndVerify(sourceContext: sourceContext, targetURL: targetURL)
            UserDefaults.standard.set(bookmark, forKey: bookmarkDefaultsKey)
            UserDefaults.standard.set(folder.path, forKey: pathDefaultsKey)
            return targetURL
        } catch {
            // The destination did not exist before this operation, so remove only
            // the files created by this failed attempt. The source store is untouched.
            removeStoreFiles(at: targetURL)
            throw error
        }
    }

    static func openCurrentFolderInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([currentStoreURL])
    }

    private static func resolveSelectedFolder() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkDefaultsKey) else { return nil }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return nil }

        if stale, let refreshed = try? makeBookmark(for: url) {
            UserDefaults.standard.set(refreshed, forKey: bookmarkDefaultsKey)
            UserDefaults.standard.set(url.path, forKey: pathDefaultsKey)
        }
        if activeScopedFolderURL?.standardizedFileURL != url.standardizedFileURL {
            _ = activeScopedFolderURL?.stopAccessingSecurityScopedResource()
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

    private static func copyAndVerify(sourceContext: ModelContext, targetURL: URL) throws {
        let boards = try sourceContext.fetch(FetchDescriptor<Board>())
        let columns = try sourceContext.fetch(FetchDescriptor<BoardColumn>())
        let tasks = try sourceContext.fetch(FetchDescriptor<TaskCard>())
        let checklistItems = try sourceContext.fetch(FetchDescriptor<TaskChecklistItem>())

        let boardIDs = Set(boards.map(\.id))
        let columnIDs = Set(columns.map(\.id))
        let taskIDs = Set(tasks.map(\.id))
        guard columns.allSatisfy({ boardIDs.contains($0.boardID) }),
              tasks.allSatisfy({ columnIDs.contains($0.columnID) }),
              checklistItems.allSatisfy({ taskIDs.contains($0.taskID) }) else {
            throw VaultError.invalidReferences
        }

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
            targetContext.insert(TaskCard(
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
            ))
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

        guard copiedBoards.count == boards.count,
              copiedColumns.count == columns.count,
              copiedTasks.count == tasks.count,
              copiedChecklistItems.count == checklistItems.count,
              Set(copiedBoards.map(\.id)) == boardIDs,
              Set(copiedColumns.map(\.id)) == columnIDs,
              Set(copiedTasks.map(\.id)) == taskIDs,
              Set(copiedChecklistItems.map(\.id)) == Set(checklistItems.map(\.id)) else {
            throw VaultError.verificationFailed
        }
    }

    private static func removeStoreFiles(at url: URL) {
        let fileManager = FileManager.default
        for candidate in [
            url,
            URL(fileURLWithPath: url.path + "-wal"),
            URL(fileURLWithPath: url.path + "-shm")
        ] where fileManager.fileExists(atPath: candidate.path) {
            try? fileManager.removeItem(at: candidate)
        }
    }
}
