import SwiftData
import SwiftUI

struct AddCollectionCardSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppServices.self) private var services

    @State private var query = ""
    @State private var results: [Card] = []
    @State private var isSearching = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Search cards", text: $query)
                        .textInputAutocapitalization(.never)
                        .onSubmit { Task { await runSearch() } }
                    Button("Search") {
                        Task { await runSearch() }
                    }
                    .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if isSearching {
                    Section { ProgressView() }
                }

                Section("Results") {
                    ForEach(results) { card in
                        Button {
                            add(card)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(card.cardName).foregroundStyle(.primary)
                                Text("\(card.setCode) · \(card.cardNumber)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add to collection")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func runSearch() async {
        isSearching = true
        defer { isSearching = false }
        results = await services.cardData.search(query: query)
    }

    private func add(_ card: Card) {
        let row = CollectionCard(
            masterCardId: card.masterCardId,
            setCode: card.setCode,
            quantity: 1,
            printing: "Standard",
            language: "English",
            conditionId: CardCondition.nearMint.rawValue
        )
        modelContext.insert(row)
        dismiss()
    }
}
