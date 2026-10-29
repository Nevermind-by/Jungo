import SwiftUI
import SwiftData
import AppKit

struct VaultSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var isMovingVault = false
    @State private var errorMessage: String?
    @State private var showMoveConfirmation = false
    @State private var showRestartRequired = false
    @State private var destinationFolder: URL?

    private var folderPath: String {
        VaultStore.currentFolderURL.path
    }

    var body: some View {
        Form {
            Section("Локальное хранилище") {
                LabeledContent("Расположение") {
                    Text(folderPath)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }

                LabeledContent("Файл базы") {
                    Text(VaultStore.currentStoreURL.lastPathComponent)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button("Открыть в Finder", systemImage: "folder") {
                        VaultStore.openCurrentFolderInFinder()
                    }

                    Spacer()

                    Button("Выбрать папку…", systemImage: "folder.badge.gearshape") {
                        chooseDestinationFolder()
                    }
                    .disabled(isMovingVault)
                }
            }

            Section("Перенос данных") {
                Text("Jungo перенесёт доски, колонки, задачи, корзину и чек-листы в новую локальную базу. ID и связи сохраняются. Исходная база не удаляется.")
                    .foregroundStyle(.secondary)

                Label("После проверки новой базы приложение завершится. Открой Jungo снова, чтобы продолжить работу с новым расположением.", systemImage: "arrow.clockwise")
                    .foregroundStyle(.secondary)
            }

            Section("Резервная копия") {
                Text("Для отдельной копии используй «Экспорт» на боковой панели. Экспорт JSON не меняет расположение активной базы и не заменяет перенос хранилища.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(width: 620, height: 400)
        .padding(.top, 8)
        .background(JungoCanvasBackground())
        .confirmationDialog(
            "Перенести хранилище Jungo?",
            isPresented: $showMoveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Перенести и завершить Jungo", role: .destructive) {
                moveVault()
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Будет создан файл Jungo.store в выбранной папке. Если там уже есть такой файл, перенос остановится без перезаписи. Перед переносом текущие изменения будут сохранены.")
        }
        .alert("Не удалось перенести хранилище", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("ОК", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("Хранилище перенесено", isPresented: $showRestartRequired) {
            Button("Завершить Jungo") {
                NSApp.terminate(nil)
            }
        } message: {
            Text("Новая база проверена. Исходная база оставлена на месте. Открой Jungo снова, чтобы использовать новое хранилище.")
        }
    }

    private func chooseDestinationFolder() {
        let panel = NSOpenPanel()
        panel.title = "Выбери папку для хранилища Jungo"
        panel.message = "В выбранной папке будет создан файл Jungo.store."
        panel.prompt = "Выбрать папку"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = VaultStore.currentFolderURL

        guard panel.runModal() == .OK, let url = panel.url else { return }
        destinationFolder = url
        showMoveConfirmation = true
    }

    private func moveVault() {
        guard let destinationFolder else { return }
        isMovingVault = true
        defer { isMovingVault = false }

        do {
            try VaultStore.moveVault(from: modelContext, to: destinationFolder)
            showRestartRequired = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct VaultUnavailableView: View {
    let message: String
    @State private var recoveryError: String?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text("Не удалось открыть хранилище")
                .font(.title2.weight(.semibold))
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 480)
            if UserDefaults.standard.data(forKey: VaultStore.bookmarkDefaultsKey) != nil {
                VStack(spacing: 5) {
                    Text("Ожидаемое расположение")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(VaultStore.currentFolderURL.path)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: 520)
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
            Text("Подключи диск или верни доступ к выбранной папке, затем заверши и снова открой Jungo. Приложение намеренно не создаёт пустую базу вместо недоступного хранилища.")
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
            Button("Указать папку существующего хранилища…", systemImage: "folder.badge.questionmark") {
                recoverExistingVault()
            }
            Button("Завершить Jungo") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(36)
        .frame(minWidth: 620, minHeight: 360)
        .background(JungoCanvasBackground())
        .alert("Не удалось восстановить доступ", isPresented: Binding(
            get: { recoveryError != nil },
            set: { if !$0 { recoveryError = nil } }
        )) {
            Button("ОК", role: .cancel) { recoveryError = nil }
        } message: {
            Text(recoveryError ?? "")
        }
    }

    private func recoverExistingVault() {
        let panel = NSOpenPanel()
        panel.title = "Найди папку с существующим Jungo.store"
        panel.message = "Будет принят только уже существующий файл Jungo.store. Новая пустая база не создаётся."
        panel.prompt = "Выбрать папку"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let folder = panel.url else { return }
        do {
            try VaultStore.restoreAccess(to: folder)
            NSApp.terminate(nil)
        } catch {
            recoveryError = error.localizedDescription
        }
    }
}
