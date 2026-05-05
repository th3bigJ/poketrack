import SwiftData
import SwiftUI

struct AddManualActivityView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    private let ledgerLineToEdit: LedgerLine?

    @State private var direction: LedgerDirection = .bought
    @State private var productKind: ProductKind = .singleCard
    @State private var lineDescription: String = ""
    @State private var quantity: Int = 1
    @State private var unitPriceText: String = ""
    @State private var counterparty: String = ""
    @State private var occurredAt: Date = Date()

    private var unitPrice: Double? {
        Double(unitPriceText.replacingOccurrences(of: ",", with: "."))
    }

    private var isEditing: Bool { ledgerLineToEdit != nil }

    private var selectedCurrencyCode: String {
        services.priceDisplay.currency == .gbp ? "GBP" : "USD"
    }

    private var sheetActionColor: Color {
        colorScheme == .dark ? .white : .black
    }

    init(ledgerLineToEdit: LedgerLine? = nil) {
        self.ledgerLineToEdit = ledgerLineToEdit
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    Picker(selection: $direction) {
                        ForEach(LedgerDirection.allCases, id: \.self) { dir in
                            Text(directionTitle(dir)).tag(dir)
                        }
                    } label: {
                        Text("Type")
                            .foregroundStyle(sheetActionColor)
                    }
                    Picker(selection: $productKind) {
                        ForEach(ProductKind.allCases, id: \.self) { kind in
                            Text(productKindTitle(kind)).tag(kind)
                        }
                    } label: {
                        Text("Item")
                            .foregroundStyle(sheetActionColor)
                    }
                    TextField("Description", text: $lineDescription)
                }

                Section("Transaction") {
                    Stepper("Quantity: \(quantity)", value: $quantity, in: 1...9999)
                    HStack {
                        Text("Price per unit")
                        Spacer()
                        TextField("Optional", text: $unitPriceText)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                    }
                    TextField("Counterparty", text: $counterparty)
                    DatePicker("Date", selection: $occurredAt, displayedComponents: .date)
                }
            }
            .navigationTitle(isEditing ? "Edit Activity" : "Add Activity")
            .navigationBarTitleDisplayMode(.inline)
            .tint(sheetActionColor)
            .onAppear {
                populateFieldsIfEditing()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(sheetActionColor)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") { save() }
                        .foregroundStyle(sheetActionColor)
                        .disabled(lineDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        do {
            if let existing = ledgerLineToEdit {
                existing.occurredAt = occurredAt
                existing.direction = direction.rawValue
                existing.productKind = productKind.rawValue
                existing.lineDescription = lineDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                existing.quantity = quantity
                existing.unitPrice = unitPrice
                existing.currencyCode = selectedCurrencyCode
                existing.counterparty = cleanedCounterparty
            } else {
                let line = LedgerLine(
                    occurredAt: occurredAt,
                    direction: direction.rawValue,
                    productKind: productKind.rawValue,
                    lineDescription: lineDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                    quantity: quantity,
                    unitPrice: unitPrice,
                    currencyCode: selectedCurrencyCode,
                    counterparty: cleanedCounterparty
                )
                modelContext.insert(line)
            }
            try modelContext.save()
            HapticManager.notification(.success)
            dismiss()
        } catch {
            HapticManager.notification(.error)
            print("[Transactions] Failed to save manual activity: \(error.localizedDescription)")
        }
    }

    private var cleanedCounterparty: String? {
        let trimmed = counterparty.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func populateFieldsIfEditing() {
        guard let line = ledgerLineToEdit else { return }
        occurredAt = line.occurredAt
        direction = LedgerDirection(rawValue: line.direction) ?? .bought
        productKind = ProductKind(rawValue: line.productKind) ?? .other
        lineDescription = line.lineDescription
        quantity = line.quantity
        unitPriceText = line.unitPrice.map { String($0) } ?? ""
        counterparty = line.counterparty ?? ""
    }

    private func directionTitle(_ dir: LedgerDirection) -> String {
        switch dir {
        case .bought: return "Bought"
        case .packed: return "Packed"
        case .sold: return "Sold"
        case .tradedIn: return "Trade In"
        case .tradedOut: return "Trade Out"
        case .giftedIn: return "Gift In"
        case .giftedOut: return "Gift Out"
        case .adjustmentIn: return "Adjustment In"
        case .adjustmentOut: return "Adjustment Out"
        }
    }

    private func productKindTitle(_ kind: ProductKind) -> String {
        switch kind {
        case .singleCard: return "Single card"
        case .gradedItem: return "Graded item"
        case .sealedProduct: return "Sealed product"
        case .boosterPack: return "Booster pack"
        case .etb: return "ETB"
        case .other: return "Other"
        }
    }
}
