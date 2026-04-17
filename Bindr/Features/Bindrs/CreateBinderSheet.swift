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
                    Picker("Layout", selection: $layout) {
                        ForEach(BinderPageLayout.allCases, id: \.self) { l in
                            Text(l.displayName).tag(l)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
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
}
