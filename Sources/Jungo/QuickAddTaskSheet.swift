import SwiftUI

/// Compact, adaptive quick capture sheet.
/// The header and actions remain fixed while the form scrolls when vertical space is limited.
struct QuickAddTaskSheet: View {
    @Environment(\.dismiss) private var dismiss

    let columns: [BoardColumn]
    let onCreate: (String, String, UUID) -> Bool

    @State private var title = ""
    @State private var details = ""
    @State private var selectedColumnID: UUID?

    init(
        columns: [BoardColumn],
        initialColumnID: UUID?,
        onCreate: @escaping (String, String, UUID) -> Bool
    ) {
        self.columns = columns
        self.onCreate = onCreate
        _selectedColumnID = State(initialValue: initialColumnID)
    }

    private var normalizedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 14) {
                    taskDetailsSection
                    destinationSection
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.automatic)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                footer
            }
        }
        .frame(
            minWidth: 500,
            idealWidth: 540,
            maxWidth: 580,
            minHeight: 520,
            idealHeight: 640,
            maxHeight: 720
        )
        .background(JungoCanvasBackground())
        .onAppear {
            if selectedColumnID == nil {
                selectedColumnID = columns.first?.id
            }
        }
        .onChange(of: columns.map(\.id)) { _, ids in
            if let selectedColumnID, ids.contains(selectedColumnID) { return }
            selectedColumnID = ids.first
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                Image(systemName: "bolt.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text("Быстрое добавление")
                    .font(.system(.headline, weight: .bold))
                    .lineLimit(1)
                Text("Запиши задачу и возвращайся к работе")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            Text("JUNGO")
                .font(.system(.caption2, design: .rounded).weight(.bold))
                .tracking(1.5)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.6)
        }
    }

    private var taskDetailsSection: some View {
        JungoSectionSurface("Новая задача", subtitle: "Начни с короткого и понятного названия") {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Что нужно сделать?", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(.title3, weight: .semibold))
                    .padding(.horizontal, 13)
                    .padding(.vertical, 12)
                    .frame(minHeight: 48)
                    .background(
                        Color.primary.opacity(0.045),
                        in: RoundedRectangle(cornerRadius: JungoDesign.inputRadius, style: .continuous)
                    )
                    .onSubmit(createTask)

                VStack(alignment: .leading, spacing: 6) {
                    Text("ОПИСАНИЕ")
                        .font(.system(.caption2, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(.tertiary)

                    TextField("Добавь контекст (необязательно)", text: $details, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(2...3)
                        .font(.subheadline)
                        .padding(12)
                        .frame(minHeight: 68, alignment: .topLeading)
                        .background(
                            Color.primary.opacity(0.035),
                            in: RoundedRectangle(cornerRadius: JungoDesign.inputRadius, style: .continuous)
                        )
                }
            }
        }
    }

    private var destinationSection: some View {
        JungoSectionSurface("Куда добавить", subtitle: "Задача появится в выбранной колонке") {
            if columns.isEmpty {
                ContentUnavailableView("Нет доступных колонок", systemImage: "rectangle.split.3x1")
                    .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 7) {
                    ForEach(columns) { column in
                        let isSelected = selectedColumnID == column.id

                        Button {
                            selectedColumnID = column.id
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                                    .font(.system(size: 17, weight: .regular))
                                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)

                                Text(column.title)
                                    .font(.system(.subheadline, weight: isSelected ? .semibold : .medium))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .foregroundStyle(.primary)

                                Spacer(minLength: 8)

                                if isSelected {
                                    Text("Выбрано")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 12)
                            .frame(maxWidth: .infinity, minHeight: 42)
                            .background(
                                isSelected ? Color.accentColor.opacity(0.09) : Color.primary.opacity(0.035),
                                in: RoundedRectangle(cornerRadius: JungoDesign.inputRadius, style: .continuous)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: JungoDesign.inputRadius, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.65)

            HStack(spacing: 12) {
                HStack(spacing: 5) {
                    Text("⌘↩︎")
                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                    Text("создать")
                        .font(.caption)
                }
                .foregroundStyle(.tertiary)

                Spacer(minLength: 8)

                Button("Отмена", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Создать задачу", systemImage: "plus", action: createTask)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(normalizedTitle.isEmpty || selectedColumnID == nil)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.bar)
        }
    }

    private func createTask() {
        guard !normalizedTitle.isEmpty,
              let selectedColumnID,
              onCreate(
                normalizedTitle,
                details.trimmingCharacters(in: .whitespacesAndNewlines),
                selectedColumnID
              ) else { return }

        dismiss()
    }
}
