import SwiftUI
import SwiftData

struct AddToTradeListRequest: Identifiable {
    let id = UUID()
    let cardID: String
    let variantKey: String
    let cardName: String
    let ownedQuantity: Int
}

struct AddToTradeListSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Query private var tradeListItems: [TradeListItem]

    let request: AddToTradeListRequest

    @State private var quantity: Int = 1

    private var existingItem: TradeListItem? {
        tradeListItems.first { $0.cardID == request.cardID && $0.variantKey == request.variantKey }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(request.cardName)
                        .font(.headline)
                    if request.variantKey != "normal" {
                        Text(displayVariant(request.variantKey))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    Stepper("Quantity: \(quantity)", value: $quantity, in: 1...request.ownedQuantity)
                } footer: {
                    Text("You own \(request.ownedQuantity) \(request.ownedQuantity == 1 ? "copy" : "copies") of this card.")
                }
            }
            .navigationTitle("Add to Trade List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
                }
            }
            .onAppear {
                if let existing = existingItem {
                    quantity = min(existing.quantity + 1, request.ownedQuantity)
                }
            }
        }
    }

    private func save() {
        if let existing = existingItem {
            existing.quantity = quantity
        } else {
            modelContext.insert(TradeListItem(
                cardID: request.cardID,
                variantKey: request.variantKey,
                quantity: quantity
            ))
        }
        try? modelContext.save()
        Haptics.success()
        dismiss()
    }

    private func displayVariant(_ variantKey: String) -> String {
        let normalized = variantKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "Normal" }
        let spaced = normalized
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
        return spaced
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }
}
