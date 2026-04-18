import SwiftUI
import SwiftData

struct CreateBinderSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private let layoutOptions: [BinderPageLayout] = [
        .fixed(rows: 2, columns: 2),
        .fixed(rows: 3, columns: 2),
        .fixed(rows: 3, columns: 3),
        .fixed(rows: 4, columns: 3),
        .fixed(rows: 3, columns: 4),
        .fixed(rows: 4, columns: 4),
        .fixed(rows: 5, columns: 4),
        .fixed(rows: 5, columns: 5),
        .freeScroll
    ]

    @State private var name = ""
    @State private var layout = BinderPageLayout.fixed(rows: 3, columns: 3)
    @State private var colour = "blue"

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Binder name", text: $name)
                }

                Section("Layout") {
                    VStack(spacing: 10) {
                        ForEach(layoutOptions, id: \.self) { option in
                            Button {
                                layout = option
                            } label: {
                                layoutOptionRow(for: option)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }

                Section("Colour") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(BinderColourPalette.options, id: \.name) { swatch in
                            Circle()
                                .fill(swatch.color)
                                .frame(width: 32, height: 32)
                                .overlay {
                                    if colour == swatch.name {
                                        Image(systemName: "checkmark")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                                .onTapGesture {
                                    colour = swatch.name
                                }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                }
            }
            .navigationTitle("New Binder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        create()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func create() {
        let binder = Binder(
            title: name.trimmingCharacters(in: .whitespaces),
            pageLayout: layout,
            colour: colour
        )
        modelContext.insert(binder)
        dismiss()
    }

    @ViewBuilder
    private func layoutOptionRow(for option: BinderPageLayout) -> some View {
        let isSelected = layout == option
        let borderColor: Color = isSelected ? Color.accentColor.opacity(0.45) : .clear

        HStack {
            Text(layoutLabel(for: option))
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        }
    }

    private func layoutLabel(for option: BinderPageLayout) -> String {
        option.isFreeScroll ? "Free flow" : "\(option.columns) x \(option.rows)"
    }
}
