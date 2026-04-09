import SwiftUI

/// Identifies which card + variant to add (sheet item).
struct AddToCollectionSheetPayload: Identifiable {
    let id = UUID()
    let card: Card
    let variantKey: String
}

/// Add a card to the collection with purchase type–specific fields.
struct AddToCollectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppServices.self) private var services

    let card: Card
    let variantKey: String

    @State private var acquisitionKind: CollectionAcquisitionKind = .bought
    @State private var quantity: Int = 1

    // Bought
    @State private var boughtFrom: String = ""
    @State private var priceText: String = ""

    // Packed
    @State private var packedOpenedFrom: String = ""

    // Gifted
    @State private var giftFrom: String = ""

    @State private var errorMessage: String?

    private var currencyCode: String {
        switch services.priceDisplay.currency {
        case .usd: return "USD"
        case .gbp: return "GBP"
        }
    }

    private var currencySymbol: String {
        services.priceDisplay.currency.symbol
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(card.cardName)
                        .font(.headline)
                    Text(variantLabel(variantKey))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Picker("Purchase type", selection: $acquisitionKind) {
                        ForEach(CollectionAcquisitionKind.allCases, id: \.self) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Stepper("Quantity: \(quantity)", value: $quantity, in: 1...999)
                }

                Group {
                    switch acquisitionKind {
                    case .bought:
                        boughtFields
                    case .packed:
                        packedFields
                    case .trade:
                        tradePlaceholder
                    case .gifted:
                        giftedFields
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Add to collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .disabled(acquisitionKind == .trade)
                }
            }
        }
    }

    @ViewBuilder
    private var boughtFields: some View {
        Section("Bought") {
            TextField("Bought from", text: $boughtFrom)
            HStack {
                Text("Unit price")
                Spacer()
                TextField("0.00", text: $priceText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 120)
                Text(currencySymbol)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var packedFields: some View {
        Section("From pack") {
            TextField("Opened from (optional)", text: $packedOpenedFrom, axis: .vertical)
                .lineLimit(1...4)
            Text("Later you’ll link this to a sealed product transaction.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var tradePlaceholder: some View {
        Section {
            ContentUnavailableView(
                "Trades",
                systemImage: "arrow.left.arrow.right",
                description: Text("Trades feature coming soon.")
            )
            .frame(minHeight: 120)
            .listRowInsets(EdgeInsets())
        }
    }

    @ViewBuilder
    private var giftedFields: some View {
        Section("Gift") {
            TextField("From (optional)", text: $giftFrom)
        }
    }

    private func variantLabel(_ key: String) -> String {
        let spaced = key
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "([A-Z])", with: " $1", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return spaced.split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }

    private func parseRequiredPrice(_ text: String) throws -> Double {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AddToCollectionValidation.missingPrice }
        guard let v = Double(trimmed.replacingOccurrences(of: ",", with: ".")) else {
            throw AddToCollectionValidation.invalidPrice
        }
        return v
    }

    private func save() {
        errorMessage = nil
        guard acquisitionKind != .trade else { return }
        guard let ledger = services.collectionLedger else {
            errorMessage = "Collection isn’t ready. Try again."
            return
        }

        do {
            switch acquisitionKind {
            case .bought:
                let unit = try parseRequiredPrice(priceText)
                let from = boughtFrom.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !from.isEmpty else {
                    errorMessage = "Enter where you bought this card."
                    return
                }
                try ledger.recordSingleCardAcquisition(
                    cardID: card.masterCardId,
                    variantKey: variantKey,
                    kind: .bought,
                    quantity: quantity,
                    currencyCode: currencyCode,
                    cardDisplayName: card.cardName,
                    unitPrice: unit,
                    packedOpenedFrom: nil,
                    tradeCounterparty: nil,
                    tradeGaveAway: nil,
                    giftFrom: nil,
                    boughtFrom: from
                )
            case .packed:
                try ledger.recordSingleCardAcquisition(
                    cardID: card.masterCardId,
                    variantKey: variantKey,
                    kind: .packed,
                    quantity: quantity,
                    currencyCode: currencyCode,
                    cardDisplayName: card.cardName,
                    unitPrice: nil,
                    packedOpenedFrom: packedOpenedFrom.isEmpty ? nil : packedOpenedFrom,
                    tradeCounterparty: nil,
                    tradeGaveAway: nil,
                    giftFrom: nil,
                    boughtFrom: nil
                )
            case .gifted:
                try ledger.recordSingleCardAcquisition(
                    cardID: card.masterCardId,
                    variantKey: variantKey,
                    kind: .gifted,
                    quantity: quantity,
                    currencyCode: currencyCode,
                    cardDisplayName: card.cardName,
                    unitPrice: nil,
                    packedOpenedFrom: nil,
                    tradeCounterparty: nil,
                    tradeGaveAway: nil,
                    giftFrom: giftFrom.isEmpty ? nil : giftFrom,
                    boughtFrom: nil
                )
            case .trade:
                break
            }
            dismiss()
        } catch AddToCollectionValidation.missingPrice {
            errorMessage = "Enter a unit price."
        } catch AddToCollectionValidation.invalidPrice {
            errorMessage = "Enter a valid unit price."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum AddToCollectionValidation: Error {
    case missingPrice
    case invalidPrice
}
