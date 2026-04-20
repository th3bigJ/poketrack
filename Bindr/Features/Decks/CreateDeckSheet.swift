import SwiftUI
import SwiftData

struct CreateDeckSheet: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var selectedBrand: TCGBrand = .pokemon
    @State private var selectedFormat: DeckFormat = .pokemonStandard

    private var availableFormats: [DeckFormat] {
        DeckFormat.formats(for: selectedBrand)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Deck name", text: $name)
                }

                Section("Game") {
                    LabeledContent("Active Game") {
                        Text(selectedBrand.displayTitle)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Format") {
                    Picker("Format", selection: $selectedFormat) {
                        ForEach(availableFormats, id: \.self) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

                    Text(selectedFormat.rulesDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .navigationTitle("New Deck")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                let activeBrand = services.brandSettings.selectedCatalogBrand
                selectedBrand = activeBrand
                selectedFormat = DeckFormat.formats(for: activeBrand).first ?? .pokemonStandard
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func create() {
        let deck = Deck(
            title: name.trimmingCharacters(in: .whitespaces),
            brand: selectedBrand,
            format: selectedFormat
        )
        modelContext.insert(deck)
        dismiss()
    }
}
