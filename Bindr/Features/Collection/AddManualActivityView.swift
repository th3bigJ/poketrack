import SwiftData
import SwiftUI

/// User-facing activity types for manual add/edit, including sealed "Opened" (stored separately from ``LedgerDirection``).
private enum ManualActivityType: String, CaseIterable, Hashable {
    case bought
    case packed
    case sold
    case tradedIn
    case tradedOut
    case giftedIn
    case giftedOut
    case adjustmentIn
    case adjustmentOut
    case importedIn
    case opened

    var title: String {
        switch self {
        case .bought: return "Bought"
        case .packed: return "Packed"
        case .sold: return "Sold"
        case .tradedIn: return "Trade In"
        case .tradedOut: return "Trade Out"
        case .giftedIn: return "Gift In"
        case .giftedOut: return "Gift Out"
        case .adjustmentIn: return "Adjustment In"
        case .adjustmentOut: return "Adjustment Out"
        case .importedIn: return "Imported"
        case .opened: return "Opened"
        }
    }

    static func from(line: LedgerLine) -> ManualActivityType {
        if line.productKind == ProductKind.sealedProduct.rawValue,
           line.sealedStatus == SealedInventoryStatus.opened.rawValue {
            return .opened
        }
        return ManualActivityType(rawValue: line.direction) ?? .bought
    }

    func apply(to line: LedgerLine) {
        let isSealedProduct = line.productKind == ProductKind.sealedProduct.rawValue
        switch self {
        case .opened:
            line.direction = LedgerDirection.adjustmentOut.rawValue
            line.sealedStatus = SealedInventoryStatus.opened.rawValue
            line.channel = "opened"
        default:
            line.direction = rawValue
            line.sealedStatus = isSealedProduct ? SealedInventoryStatus.sealed.rawValue : nil
            if line.channel == "opened" { line.channel = nil }
        }
    }
}

struct AddManualActivityView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    private let ledgerLineToEdit: LedgerLine?

    @State private var activityType: ManualActivityType = .bought
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
                    Picker(selection: $activityType) {
                        ForEach(availableActivityTypes, id: \.self) { type in
                            Text(type.title).tag(type)
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
            .onChange(of: productKind) { _, newKind in
                if activityType == .opened, newKind != .sealedProduct {
                    activityType = .bought
                }
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
                existing.productKind = productKind.rawValue
                existing.lineDescription = lineDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                existing.quantity = quantity
                existing.unitPrice = unitPrice
                existing.currencyCode = selectedCurrencyCode
                existing.counterparty = cleanedCounterparty
                activityType.apply(to: existing)
            } else {
                let line = LedgerLine(
                    occurredAt: occurredAt,
                    direction: LedgerDirection.bought.rawValue,
                    productKind: productKind.rawValue,
                    lineDescription: lineDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                    quantity: quantity,
                    unitPrice: unitPrice,
                    currencyCode: selectedCurrencyCode,
                    counterparty: cleanedCounterparty
                )
                activityType.apply(to: line)
                modelContext.insert(line)
            }
            try modelContext.save()
            HapticManager.notification(.success)
            dismiss()
        } catch {
            HapticManager.notification(.error)
        }
    }

    private var cleanedCounterparty: String? {
        let trimmed = counterparty.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var availableActivityTypes: [ManualActivityType] {
        if productKind == .sealedProduct {
            return ManualActivityType.allCases
        }
        return ManualActivityType.allCases.filter { $0 != .opened }
    }

    private func populateFieldsIfEditing() {
        guard let line = ledgerLineToEdit else { return }
        occurredAt = line.occurredAt
        activityType = ManualActivityType.from(line: line)
        productKind = ProductKind(rawValue: line.productKind) ?? .other
        lineDescription = line.lineDescription
        quantity = line.quantity
        unitPriceText = line.unitPrice.map { String($0) } ?? ""
        counterparty = line.counterparty ?? ""
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
