import SwiftUI
import UIKit

struct MultiSelectCollectionPayload: Identifiable {
    let id = UUID()
    let cards: [Card]
}

struct MultiSelectAddToCollectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppServices.self) private var services

    let cards: [Card]

    @State private var acquisitionKind: CollectionAcquisitionKind = .packed
    @State private var quantity: Int = 1
    @State private var cardCondition: CardCondition = .raw
    @State private var gradingCompany: GradingCompany = .psa
    @State private var priceText: String = ""
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
                    Text("\(cards.count) card\(cards.count == 1 ? "" : "s") selected")
                        .font(.headline)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(cards, id: \.masterCardId) { card in
                                Text(card.cardName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
                            }
                        }
                        .padding(.vertical, 2)
                    }
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
                    Picker("Condition", selection: $cardCondition) {
                        ForEach(CardCondition.allCases, id: \.self) { condition in
                            Text(condition.title).tag(condition)
                        }
                    }
                    .pickerStyle(.segmented)

                    if cardCondition == .graded {
                        Picker("Grading company", selection: $gradingCompany) {
                            ForEach(GradingCompany.allCases, id: \.self) { company in
                                Text(company.title).tag(company)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                } footer: {
                    if cardCondition == .graded {
                        Text("Graded card value uses the \(gradingCompany.title) 10 market price.")
                    }
                }

                Section {
                    Stepper("Quantity per card: \(quantity)", value: $quantity, in: 1...999)
                }

                Group {
                    switch acquisitionKind {
                    case .bought:
                        boughtFields
                    case .packed, .gifted:
                        EmptyView()
                    case .trade:
                        tradePlaceholder
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
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Add to Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .disabled(acquisitionKind == .trade)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { dismissDecimalKeyboard() }
                }
            }
        }
    }

    private func dismissDecimalKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    @ViewBuilder
    private var boughtFields: some View {
        Section {
            HStack(alignment: .firstTextBaseline) {
                Text("Price paid per card")
                Spacer()
                HStack(spacing: 6) {
                    Text(currencySymbol)
                        .foregroundStyle(.secondary)
                    TextField("0.00", text: $priceText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(minWidth: 72)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Price paid per card")
        } footer: {
            Text("This price is applied to each selected card.")
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

    private func parseRequiredPrice(_ text: String) throws -> Double {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MultiSelectCollectionValidation.missingPrice }
        guard let v = Double(trimmed.replacingOccurrences(of: ",", with: ".")) else {
            throw MultiSelectCollectionValidation.invalidPrice
        }
        return v
    }

    private var resolvedGradingCompany: String? {
        cardCondition == .graded ? gradingCompany.rawValue : nil
    }

    private var resolvedGrade: String? {
        cardCondition == .graded ? "10" : nil
    }

    private func save() {
        errorMessage = nil
        guard acquisitionKind != .trade else { return }
        guard let ledger = services.collectionLedger else {
            errorMessage = "Collection isn't ready. Try again."
            return
        }

        do {
            let unitPrice: Double? = acquisitionKind == .bought ? try parseRequiredPrice(priceText) : nil

            for card in cards {
                switch acquisitionKind {
                case .bought:
                    try ledger.recordSingleCardAcquisition(
                        cardID: card.masterCardId,
                        variantKey: "normal",
                        kind: .bought,
                        quantity: quantity,
                        currencyCode: currencyCode,
                        cardDisplayName: card.cardName,
                        unitPrice: unitPrice,
                        gradingCompany: resolvedGradingCompany,
                        grade: resolvedGrade,
                        packedOpenedFrom: nil,
                        tradeCounterparty: nil,
                        tradeGaveAway: nil,
                        giftFrom: nil,
                        boughtFrom: nil
                    )
                case .packed:
                    try ledger.recordSingleCardAcquisition(
                        cardID: card.masterCardId,
                        variantKey: "normal",
                        kind: .packed,
                        quantity: quantity,
                        currencyCode: currencyCode,
                        cardDisplayName: card.cardName,
                        unitPrice: nil,
                        gradingCompany: resolvedGradingCompany,
                        grade: resolvedGrade,
                        packedOpenedFrom: nil,
                        tradeCounterparty: nil,
                        tradeGaveAway: nil,
                        giftFrom: nil,
                        boughtFrom: nil
                    )
                case .gifted:
                    try ledger.recordSingleCardAcquisition(
                        cardID: card.masterCardId,
                        variantKey: "normal",
                        kind: .gifted,
                        quantity: quantity,
                        currencyCode: currencyCode,
                        cardDisplayName: card.cardName,
                        unitPrice: nil,
                        gradingCompany: resolvedGradingCompany,
                        grade: resolvedGrade,
                        packedOpenedFrom: nil,
                        tradeCounterparty: nil,
                        tradeGaveAway: nil,
                        giftFrom: nil,
                        boughtFrom: nil
                    )
                case .trade:
                    break
                }
            }
            dismiss()
        } catch MultiSelectCollectionValidation.missingPrice {
            errorMessage = "Enter a unit price."
        } catch MultiSelectCollectionValidation.invalidPrice {
            errorMessage = "Enter a valid unit price."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum MultiSelectCollectionValidation: Error {
    case missingPrice
    case invalidPrice
}
