import SwiftUI
import SwiftData

@main
struct JungoApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .frame(minWidth: 860, minHeight: 560)
        }
        .modelContainer(for: [Board.self, BoardColumn.self, TaskCard.self, TaskChecklistItem.self])
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Новая задача") {
                    NotificationCenter.default.post(name: .jungoCreateTask, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
            CommandGroup(after: .newItem) {
                Button("Новая доска") {
                    NotificationCenter.default.post(name: .jungoCreateBoard, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("Поиск задач") {
                    NotificationCenter.default.post(name: .jungoFocusSearch, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command])
                Button("Быстро добавить задачу") {
                    NotificationCenter.default.post(name: .jungoQuickAddTask, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command, .option])
                Button("Корзина") {
                    NotificationCenter.default.post(name: .jungoToggleTrash, object: nil)
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            }
        }
    }
}

extension Notification.Name {
    static let jungoCreateTask = Notification.Name("jungo.createTask")
    static let jungoCreateBoard = Notification.Name("jungo.createBoard")
    static let jungoFocusSearch = Notification.Name("jungo.focusSearch")
    static let jungoQuickAddTask = Notification.Name("jungo.quickAddTask")
    static let jungoToggleTrash = Notification.Name("jungo.toggleTrash")
}
