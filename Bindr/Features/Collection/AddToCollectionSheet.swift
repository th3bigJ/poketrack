import SwiftUI
import UIKit

/// Identifies which card + variant to add (sheet item).
struct AddToCollectionSheetPayload: Identifiable {
    let id = UUID()
    let card: Card
    let variantKey: String
    let availableVariantKeys: [String]
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

/// Button-backed replacement for the native segmented picker. It preserves the
/// quiet white-on-grey system appearance while giving every segment an explicit
/// full-width hit target on physical devices.
struct GreySegmentedPicker<SelectionValue: Hashable>: View {
    @Binding var selection: SelectionValue
    let items: [SelectionValue]
    let title: (SelectionValue) -> String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.self) { item in
                let isSelected = selection == item

                Button {
                    guard selection != item else { return }
                    selection = item
                    Haptics.selectionChanged()
                } label: {
                    Text(title(item))
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .contentShape(Rectangle())
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(selectedBackground)
                                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.18 : 0.10), radius: 1.5, y: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(trackBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var trackBackground: Color {
        Color(uiColor: colorScheme == .dark ? .tertiarySystemFill : .systemGray5)
    }

    private var selectedBackground: Color {
        Color(uiColor: colorScheme == .dark ? .secondarySystemFill : .systemBackground)
    }
}

/// Add a card to the collection with purchase type–specific fields.
struct AddToCollectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppServices.self) private var services

    let card: Card
    let availableVariantKeys: [String]
    var onSaved: ((AddToCollectionSuccessContext) -> Void)?

    @State private var selectedVariantKey: String
    @State private var acquisitionKind: CollectionAcquisitionKind = .packed
    @State private var quantity: Int = 1

    init(
        card: Card,
        variantKey: String,
        availableVariantKeys: [String] = ["normal"],
        onSaved: ((AddToCollectionSuccessContext) -> Void)? = nil
    ) {
        self.card = card
        self.availableVariantKeys = availableVariantKeys.isEmpty ? ["normal"] : availableVariantKeys
        self.onSaved = onSaved
        _selectedVariantKey = State(initialValue: variantKey)
    }

    // Grading
    @State private var cardCondition: CardCondition = .raw
    @State private var gradingCompany: GradingCompany = .psa

    // Bought
    @State private var priceText: String = ""
    @State private var occurredAt: Date = Date()

    @State private var errorMessage: String?
    @State private var showPaywall = false
    @State private var isSaving = false

    private var currencyCode: String {
        switch services.priceDisplay.currency {
        case .usd: return "USD"
        case .gbp: return "GBP"
        }
    }

    private var currencySymbol: String {
        services.priceDisplay.currency.symbol
    }

    private var headerButtonColor: Color {
        colorScheme == .dark ? .white : .black
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(card.cardName)
                        .font(.headline)
                    if availableVariantKeys.count > 1 {
                        Picker("Variant", selection: $selectedVariantKey) {
                            ForEach(availableVariantKeys, id: \.self) { key in
                                Text(variantLabel(key)).tag(key)
                            }
                        }
                    } else {
                        Text(variantLabel(selectedVariantKey))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    GreySegmentedPicker(
                        selection: $acquisitionKind,
                        items: CollectionAcquisitionKind.manualAddCases,
                        title: \.title
                    )
                }

                Section {
                    GreySegmentedPicker(
                        selection: $cardCondition,
                        items: CardCondition.allCases,
                        title: \.title
                    )

                    if cardCondition == .graded {
                        GreySegmentedPicker(
                            selection: $gradingCompany,
                            items: GradingCompany.allCases,
                            title: \.title
                        )
                    }
                } footer: {
                    if cardCondition == .graded {
                        Text("Graded card value uses the \(gradingCompany.title) 10 market price.")
                    }
                }

                Section {
                    Stepper("Quantity: \(quantity)", value: $quantity, in: 1...999)
                }

                Section {
                    DatePicker("Date", selection: $occurredAt, displayedComponents: .date)
                }

                Group {
                    switch acquisitionKind {
                    case .bought:
                        boughtFields
                    case .packed, .gifted, .imported, .trade:
                        EmptyView()
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
            .disabled(isSaving)
            .navigationTitle("Add to collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(headerButtonColor)
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Adding..." : "Add") { save() }
                        .foregroundStyle(headerButtonColor)
                        .disabled(isSaving)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { dismissDecimalKeyboard() }
                        .foregroundStyle(headerButtonColor)
                }
            }
        }
        .tint(headerButtonColor)
        .interactiveDismissDisabled(isSaving)
        .sheet(isPresented: $showPaywall) {
            PaywallSheet().environment(services)
        }
    }

    private func dismissDecimalKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    @ViewBuilder
    private var boughtFields: some View {
        Section {
            HStack(alignment: .firstTextBaseline) {
                Text("Price per unit")
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
            .accessibilityLabel("Price per unit")
        } footer: {
            Text("What you paid for this card (cost basis).")
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

    @MainActor
    private func save() {
        guard !isSaving else { return }
        errorMessage = nil
        guard let ledger = services.collectionLedger else {
            errorMessage = "Collection isn't ready. Try again."
            return
        }

        isSaving = true
        do {
            try recordAcquisition(using: ledger)
            Haptics.success()
            onSaved?(AddToCollectionSuccessContext(
                card: card,
                variantKey: selectedVariantKey,
                variantLabel: variantLabel(selectedVariantKey),
                gradeKey: cardCondition == .graded ? gradingCompany.priceGradeKey : "raw"
            ))
            dismiss()
        } catch AddToCollectionValidation.missingPrice {
            errorMessage = "Enter a unit price."
            isSaving = false
        } catch AddToCollectionValidation.invalidPrice {
            errorMessage = "Enter a valid unit price."
            isSaving = false
        } catch CollectionLedgerError.freeTierLimitReached {
            errorMessage = CollectionLedgerError.freeTierLimitReached.errorDescription
            showPaywall = true
            isSaving = false
        } catch {
            errorMessage = error.localizedDescription
            isSaving = false
        }
    }

    @MainActor
    private func recordAcquisition(using ledger: CollectionLedgerService) throws {
        switch acquisitionKind {
        case .bought:
            let unit = try parseRequiredPrice(priceText)
            try ledger.recordSingleCardAcquisition(
                cardID: card.masterCardId,
                variantKey: selectedVariantKey,
                kind: .bought,
                quantity: quantity,
                occurredAt: occurredAt,
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
                variantKey: selectedVariantKey,
                kind: .packed,
                quantity: quantity,
                occurredAt: occurredAt,
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
                variantKey: selectedVariantKey,
                kind: .gifted,
                quantity: quantity,
                occurredAt: occurredAt,
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
            try ledger.recordSingleCardAcquisition(
                cardID: card.masterCardId,
                variantKey: selectedVariantKey,
                kind: .trade,
                quantity: quantity,
                occurredAt: occurredAt,
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
        case .imported:
            break
        }
    }

}

private enum AddToCollectionValidation: Error {
    case missingPrice
    case invalidPrice
}
