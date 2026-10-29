import SwiftUI

struct SavedTaskFilter: Codable, Identifiable, Equatable {
    let id: UUID
    let name: String
    let searchText: String
    let priorityRawValue: String
    let label: String
    let showOverdueOnly: Bool

    var summary: String {
        var parts: [String] = []
        if !searchText.isEmpty { parts.append("Поиск: \(searchText)") }
        if priorityRawValue != "all" {
            let title = ["low": "Низкий", "normal": "Обычный", "high": "Высокий"][priorityRawValue] ?? priorityRawValue
            parts.append("Приоритет: \(title)")
        }
        if !label.isEmpty { parts.append("Метка: \(label)") }
        if showOverdueOnly { parts.append("Просроченные") }
        return parts.isEmpty ? "Без фильтров" : parts.joined(separator: " · ")
    }
}

struct SaveTaskFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    let onSave: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Сохранить фильтр").font(.title2.bold())
            TextField("Название фильтра", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
            HStack {
                Spacer()
                Button("Отмена", role: .cancel) { dismiss() }
                Button("Сохранить", action: save)
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 380)
        .background(JungoCanvasBackground())
    }

    private func save() {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        onSave(value)
        dismiss()
    }
}

struct ManageSavedFiltersSheet: View {
    @Environment(\.dismiss) private var dismiss
    let filters: [SavedTaskFilter]
    let onSelect: (SavedTaskFilter) -> Void
    let onDelete: (SavedTaskFilter) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Сохранённые фильтры").font(.title2.bold())
            if filters.isEmpty {
                ContentUnavailableView("Нет фильтров", systemImage: "bookmark", description: Text("Сохрани текущий набор поиска и условий фильтрации."))
                    .frame(minHeight: 140)
            } else {
                List(filters) { filter in
                    HStack(spacing: 10) {
                        Button {
                            onSelect(filter)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(filter.name).font(.body.weight(.medium))
                                Text(filter.summary).font(.caption).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Button(role: .destructive) {
                            onDelete(filter)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("Удалить фильтр «\(filter.name)»")
                    }
                    .padding(.vertical, 3)
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
            HStack {
                Spacer()
                Button("Готово") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 460, height: 380)
        .background(JungoCanvasBackground())
    }
}

struct LabelColorSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("jungo.labelColorsJSON") private var labelColorsJSON = "{}"
    let labels: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Цвета меток").font(.title2.bold())
            Text("Цвет применяется ко всем задачам с такой меткой на этом Mac.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if labels.isEmpty {
                ContentUnavailableView("Нет меток", systemImage: "tag", description: Text("Добавь метки задачам, чтобы настроить их цвета."))
                    .frame(minHeight: 120)
            } else {
                List(labels, id: \.self) { label in
                    HStack {
                        Text(label)
                        Spacer()
                        Picker("Цвет метки \(label)", selection: colorBinding(for: label)) {
                            Text("Авто").tag("")
                            ForEach(TaskLabelPalette.options) { option in
                                Text(option.title).tag(option.id)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 140)
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
            HStack {
                Button("Сбросить цвета") { labelColorsJSON = "{}" }
                    .disabled(labelColorsJSON == "{}")
                Spacer()
                Button("Готово") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 440, height: 440)
        .background(JungoCanvasBackground())
    }

    private func colorBinding(for label: String) -> Binding<String> {
        Binding(
            get: { TaskLabelPalette.selectedColorID(for: label, storedJSON: labelColorsJSON) },
            set: { newValue in
                var colors = TaskLabelPalette.colorMap(from: labelColorsJSON)
                let key = label.lowercased()
                if newValue.isEmpty {
                    colors.removeValue(forKey: key)
                } else {
                    colors[key] = newValue
                }
                labelColorsJSON = TaskLabelPalette.encode(colors)
            }
        )
    }
}

enum TaskLabelPalette {
    struct Option: Identifiable {
        let id: String
        let title: String
        let color: Color
    }

    static let options: [Option] = [
        Option(id: "blue", title: "Синий", color: .blue),
        Option(id: "purple", title: "Фиолетовый", color: .purple),
        Option(id: "green", title: "Зелёный", color: .green),
        Option(id: "orange", title: "Оранжевый", color: .orange),
        Option(id: "pink", title: "Розовый", color: .pink),
        Option(id: "teal", title: "Бирюзовый", color: .teal),
        Option(id: "indigo", title: "Индиго", color: .indigo),
        Option(id: "red", title: "Красный", color: .red),
        Option(id: "yellow", title: "Жёлтый", color: .yellow),
        Option(id: "gray", title: "Серый", color: .gray)
    ]

    static func colorMap(from json: String) -> [String: String] {
        guard let data = json.data(using: .utf8),
              let map = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return map
    }

    static func encode(_ map: [String: String]) -> String {
        guard let data = try? JSONEncoder().encode(map),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    static func selectedColorID(for label: String, storedJSON: String) -> String {
        colorMap(from: storedJSON)[label.lowercased()] ?? ""
    }

    static func color(for label: String, storedJSON: String) -> Color {
        if let colorID = colorMap(from: storedJSON)[label.lowercased()],
           let option = options.first(where: { $0.id == colorID }) {
            return option.color
        }
        let hash = label.unicodeScalars.reduce(0) { ($0 * 31 + Int($1.value)) % 997 }
        let automaticPalette: [Color] = [.blue, .purple, .green, .orange, .pink, .teal, .indigo]
        return automaticPalette[hash % automaticPalette.count]
    }
}
