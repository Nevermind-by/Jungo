import SwiftUI
import SwiftData
import AppKit

@main
struct JungoApp: App {
    private let modelContainer: ModelContainer?
    private let startupError: String?

    init() {
        GlobalHotKeyManager.shared.start()
        do {
            let container = try VaultStore.makeContainer()
            modelContainer = container
            startupError = nil
        } catch {
            modelContainer = nil
            startupError = error.localizedDescription
        }
    }

    var body: some Scene {
        WindowGroup("Jungo", id: "main") {
            Group {
                if let modelContainer {
                    RootView()
                        .frame(minWidth: 860, minHeight: 560)
                        .modelContainer(modelContainer)
                } else {
                    VaultUnavailableView(message: startupError ?? "Неизвестная ошибка хранилища.")
                }
            }
        }
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

        Settings {
            Group {
                if let modelContainer {
                    VaultSettingsView()
                        .modelContainer(modelContainer)
                } else {
                    VaultUnavailableView(message: startupError ?? "Неизвестная ошибка хранилища.")
                }
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
    @ObservedObject private var hotKeyManager = GlobalHotKeyManager.shared

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
            if hotKeyManager.isRegistered {
                Label("Глобальная клавиша активна: ⌘⌥Space", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            } else {
                Label(hotKeyManager.registrationError ?? "Глобальная клавиша не зарегистрирована", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                Button("Повторить регистрацию клавиши") {
                    hotKeyManager.start()
                }
            }
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
