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
        }
    }
}

extension Notification.Name {
    static let jungoCreateTask = Notification.Name("jungo.createTask")
}
