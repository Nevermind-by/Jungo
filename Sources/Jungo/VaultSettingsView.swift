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
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "externaldrive.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 42, height: 42)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Хранилище Jungo")
                        .font(.system(size: 16, weight: .bold))
                    Text("Локальная база данных и резервное копирование")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("LOCAL")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.3)
                    .foregroundStyle(.tertiary)
            }
            .padding(20)
            .background(.bar)
            .overlay(alignment: .bottom) { Divider().opacity(0.6) }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    JungoSectionSurface("Текущее расположение", subtitle: "Активная база, используемая приложением") {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Папка хранилища", systemImage: "folder")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text(folderPath)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
                            HStack {
                                Label(VaultStore.currentStoreURL.lastPathComponent, systemImage: "cylinder.split.1x2")
                                    .font(.system(size: 11, weight: .medium))
                                Spacer()
                                Button("Открыть в Finder", systemImage: "folder") {
                                    VaultStore.openCurrentFolderInFinder()
                                }
                                .controlSize(.small)
                            }
                        }
                    }

                    JungoSectionSurface("Перенос хранилища", subtitle: "Перемести локальную базу в другую папку") {
                        Text("Доски, колонки, задачи, корзина и чек-листы будут перенесены с сохранением ID и связей. Исходная база останется на месте.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Выбрать новую папку…", systemImage: "folder.badge.gearshape") {
                            chooseDestinationFolder()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isMovingVault)
                        if isMovingVault {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Перенос данных…")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Label("После проверки новой базы Jungo завершит работу. Открой приложение снова, чтобы продолжить.", systemImage: "info.circle")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    JungoSectionSurface("Резервная копия", subtitle: "Отдельный файл для переноса или восстановления") {
                        Label("Используй «Экспорт» на боковой панели, чтобы сохранить JSON-копию досок и задач. Экспорт не меняет расположение активной базы и не заменяет перенос Vault.", systemImage: "archivebox")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(20)
            }

            HStack {
                Spacer()
                Button("Готово") { NSApp.keyWindow?.close() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.bar)
        }
        .frame(width: 640, height: 540)
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
