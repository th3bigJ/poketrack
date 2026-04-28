import SwiftUI
import UIKit

/// Identifies which card + variant to add (sheet item).
struct AddToCollectionSheetPayload: Identifiable {
    let id = UUID()
    let card: Card
    let variantKey: String
}

enum CardCondition: String, CaseIterable, Sendable {
    case raw
    case graded

    var title: String {
        switch self {
        case .raw: return "Raw"
        case .graded: return "Graded"
        }
    }
}

enum GradingCompany: String, CaseIterable, Sendable {
    case psa = "PSA"
    case ace = "ACE"

    var title: String { rawValue }
    var priceGradeKey: String {
        switch self {
        case .psa: return "psa10"
        case .ace: return "ace10"
        }
    }
}

/// Add a card to the collection with purchase type–specific fields.
struct AddToCollectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppServices.self) private var services

    let card: Card
    let variantKey: String

    @State private var acquisitionKind: CollectionAcquisitionKind = .packed
    @State private var quantity: Int = 1

    // Grading
    @State private var cardCondition: CardCondition = .raw
    @State private var gradingCompany: GradingCompany = .psa

    // Bought
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
                    Stepper("Quantity: \(quantity)", value: $quantity, in: 1...999)
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
            .tint(colorScheme == .dark ? .white : .black)
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
                Text("Price paid")
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
            .accessibilityLabel("Price paid")
        } footer: {
            Text("What you paid for this card (cost basis).")
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
            switch acquisitionKind {
            case .bought:
                let unit = try parseRequiredPrice(priceText)
                try ledger.recordSingleCardAcquisition(
                    cardID: card.masterCardId,
                    variantKey: variantKey,
                    kind: .bought,
                    quantity: quantity,
                    currencyCode: currencyCode,
                    cardDisplayName: card.cardName,
                    unitPrice: unit,
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
                    variantKey: variantKey,
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
                    variantKey: variantKey,
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
