import SwiftData
import SwiftUI

struct CollectionCardDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services
    @Bindable var collectionCard: CollectionCard
    @Environment(\.dismiss) private var dismiss

    @State private var priceText = ""

    var body: some View {
        Form {
            if let card = services.cardData.card(
                masterCardId: collectionCard.masterCardId,
                setCode: collectionCard.setCode
            ) {
                Section {
                    HStack {
                        AsyncImage(url: AppConfiguration.imageURL(relativePath: card.imageLowSrc)) { p in
                            p.resizable().scaledToFit()
                        } placeholder: {
                            ProgressView()
                        }
                        .frame(height: 200)
                    }
                    Text(card.cardName).font(.title2.bold())
                    Text(card.setCode).foregroundStyle(.secondary)
                }
            }

            Section("Details") {
                Stepper("Quantity: \(collectionCard.quantity)", value: $collectionCard.quantity, in: 1...999)
                Picker("Printing", selection: $collectionCard.printing) {
                    Text("Standard").tag("Standard")
                    Text("Holo").tag("Holo")
                    Text("Reverse Holo").tag("Reverse Holo")
                }
                Picker("Condition", selection: $collectionCard.conditionId) {
                    ForEach(CardCondition.allCases, id: \.rawValue) { c in
                        Text(c.displayName).tag(c.rawValue)
                    }
                }
            }

            Section("Pricing") {
                TextField("Manual GBP override (optional)", text: $priceText)
                    .keyboardType(.decimalPad)
                    .onAppear {
                        if let u = collectionCard.unlistedPrice {
                            priceText = String(format: "%.2f", u)
                        }
                    }
            }

            Section {
                Button("Remove from collection", role: .destructive) {
                    modelContext.delete(collectionCard)
                    dismiss()
                }
            }
        }
        .navigationTitle("Edit")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: priceText) { _, new in
            let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                collectionCard.unlistedPrice = nil
            } else if let v = Double(trimmed) {
                collectionCard.unlistedPrice = v
            }
        }
    }
}
