import SwiftUI
import SwiftData

struct CreateBinderSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var layout = BinderPageLayout.nineSlot
    @State private var colour = "blue"

    private let colours: [(name: String, color: Color)] = [
        ("red", .red), ("orange", .orange), ("yellow", .yellow),
        ("green", .green), ("blue", .blue), ("purple", .purple),
        ("pink", .pink), ("grey", Color(uiColor: .systemGray2))
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Binder name", text: $name)
                }

                Section("Layout") {
                    VStack(spacing: 10) {
                        ForEach(BinderPageLayout.allCases, id: \.self) { option in
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
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 10) {
                        ForEach(colours, id: \.name) { swatch in
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
            Text(option.displayName)
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
}
