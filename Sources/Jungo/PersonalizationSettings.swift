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
        VStack(spacing: 0) {
            sheetHeader("Сохранить фильтр", subtitle: "Дай набору условий понятное название", symbol: "bookmark")
            VStack(alignment: .leading, spacing: 12) {
                JungoSectionSurface("Название фильтра") {
                    TextField("Например: Срочные задачи", text: $name)
                        .textFieldStyle(.plain)
                        .font(.system(.body).weight(.medium))
                        .padding(10)
                        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: JungoDesign.inputRadius))
                        .onSubmit(save)
                }
            }
            .padding(20)
            Spacer(minLength: 0)
            sheetFooter(cancel: { dismiss() }, confirmTitle: "Сохранить", confirm: save, disabled: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .frame(minWidth: 360, idealWidth: 430, maxWidth: 520, minHeight: 250, idealHeight: 280, maxHeight: 380)
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
        VStack(spacing: 0) {
            sheetHeader("Сохранённые фильтры", subtitle: "Быстро возвращайся к нужному представлению задач", symbol: "line.3.horizontal.decrease.circle")
            if filters.isEmpty {
                ContentUnavailableView("Нет фильтров", systemImage: "bookmark", description: Text("Сохрани текущий набор поиска и условий фильтрации."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filters) { filter in
                    HStack(spacing: 12) {
                        Button {
                            onSelect(filter)
                            dismiss()
                        } label: {
                            HStack(spacing: 11) {
                                Image(systemName: "line.3.horizontal.decrease.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(Color.accentColor)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(filter.name).font(.system(.subheadline).weight(.semibold)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                                    Text(filter.summary)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.system(.caption).weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Button(role: .destructive) {
                            onDelete(filter)
                        } label: {
                            Image(systemName: "trash")
                                .font(.subheadline)
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.borderless)
                        .help("Удалить фильтр «\(filter.name)»")
                    }
                    .padding(.vertical, 5)
                    .listRowBackground(Color.clear)
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
            sheetFooter(cancel: { dismiss() }, confirmTitle: "Готово", confirm: { dismiss() })
        }
        .frame(minWidth: 420, idealWidth: 510, maxWidth: 620, minHeight: 360, idealHeight: 420, maxHeight: 600)
        .background(JungoCanvasBackground())
    }
}

struct LabelColorSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("jungo.labelColorsJSON") private var labelColorsJSON = "{}"
    let labels: [String]

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader("Цвета меток", subtitle: "Цвет применяется ко всем задачам с такой меткой на этом Mac", symbol: "paintpalette")
            if labels.isEmpty {
                ContentUnavailableView("Нет меток", systemImage: "tag", description: Text("Добавь метки задачам, чтобы настроить их цвета."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(labels, id: \.self) { label in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(TaskLabelPalette.color(for: label, storedJSON: labelColorsJSON))
                            .frame(width: 10, height: 10)
                        Text(label).font(.system(.subheadline).weight(.medium)).lineLimit(2).fixedSize(horizontal: false, vertical: true).layoutPriority(1)
                        Spacer()
                        Picker("Цвет метки \(label)", selection: colorBinding(for: label)) {
                            Text("Авто").tag("")
                            ForEach(TaskLabelPalette.options) { option in
                                Text(option.title).tag(option.id)
                            }
                        }
                        .labelsHidden()
                        .frame(minWidth: 120, idealWidth: 145)
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(Color.clear)
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
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 13)
            .background(.bar)
        }
        .frame(minWidth: 420, idealWidth: 490, maxWidth: 600, minHeight: 380, idealHeight: 450, maxHeight: 620)
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

private func sheetHeader(_ title: String, subtitle: String, symbol: String) -> some View {
    HStack(spacing: 12) {
        Image(systemName: symbol)
            .font(.system(.title3).weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .frame(width: 40, height: 40)
            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(.body).weight(.bold))
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        Text("JUNGO")
            .font(.system(.caption2, design: .rounded).weight(.bold))
            .tracking(1.4)
            .foregroundStyle(.tertiary)
    }
    .padding(20)
    .background(.bar)
    .overlay(alignment: .bottom) { Divider().opacity(0.6) }
}

private func sheetFooter(cancel: @escaping () -> Void, confirmTitle: String, confirm: @escaping () -> Void, disabled: Bool = false) -> some View {
    HStack {
        Spacer()
        Button("Отмена", role: .cancel, action: cancel)
            .keyboardShortcut(.cancelAction)
        Button(confirmTitle, action: confirm)
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(disabled)
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 13)
    .background(.bar)
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
