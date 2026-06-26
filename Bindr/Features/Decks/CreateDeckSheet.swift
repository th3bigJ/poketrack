import SwiftUI
import SwiftData

struct CreateDeckSheet: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// When set, the sheet edits an existing deck instead of creating one.
    var editingDeck: Deck? = nil

    @State private var name = ""
    @State private var selectedBrand: TCGBrand = .pokemon
    @State private var selectedFormat: DeckFormat = .pokemonStandard

    private var isEditing: Bool { editingDeck != nil }

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
            .navigationTitle(isEditing ? "Edit Deck" : "New Deck")
            .navigationBarTitleDisplayMode(.inline)
            .tint(.primary)
            .onAppear {
                if let deck = editingDeck {
                    name = deck.title
                    selectedBrand = deck.tcgBrand
                    selectedFormat = deck.deckFormat
                } else {
                    let activeBrand = services.brandSettings.selectedCatalogBrand
                    selectedBrand = activeBrand
                    selectedFormat = DeckFormat.formats(for: activeBrand).first ?? .pokemonStandard
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .tint(.primary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Create") { save() }
                        .bold()
                        .foregroundStyle(.primary)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        if let deck = editingDeck {
            deck.title = trimmedName
            deck.brand = selectedBrand.rawValue
            deck.format = selectedFormat.rawValue
        } else {
            let deck = Deck(
                title: trimmedName,
                brand: selectedBrand,
                format: selectedFormat
            )
            modelContext.insert(deck)
        }
        services.scheduleLibraryCloudBackup()
        dismiss()
    }
}
