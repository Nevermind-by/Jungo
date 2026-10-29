import SwiftUI
import SwiftData
import AppKit

@main
struct JungoApp: App {
    init() {
        GlobalHotKeyManager.shared.start()
    }

    var body: some Scene {
        WindowGroup("Jungo", id: "main") {
            RootView()
                .frame(minWidth: 860, minHeight: 560)
        }
        .modelContainer(for: [Board.self, BoardColumn.self, TaskCard.self, TaskChecklistItem.self], isUndoEnabled: true)
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
                    GlobalHotKeyManager.shared.requestQuickCapture()
                }
                .keyboardShortcut("n", modifiers: [.command, .option])
                Button("Корзина") {
                    NotificationCenter.default.post(name: .jungoToggleTrash, object: nil)
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra("Jungo", systemImage: "checklist") {
            MenuBarQuickCaptureMenu()
        }
        .menuBarExtraStyle(.menu)
    }
}

struct MenuBarQuickCaptureMenu: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            Button("Быстро добавить задачу") {
                GlobalHotKeyManager.shared.requestQuickCapture()
            }
            .keyboardShortcut("n", modifiers: [.command, .option])

            Button("Открыть Jungo") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }

            Divider()
            Text("Глобальная клавиша: ⌘⌥Space")
                .foregroundStyle(.secondary)
        }
        .onAppear {
            GlobalHotKeyManager.shared.configure(openWindow: { openWindow(id: "main") })
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
