import SwiftData
import SwiftUI

struct TransactionsView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \LedgerLine.occurredAt, order: .reverse) private var ledgerLines: [LedgerLine]

    @State private var cardNamesByID: [String: String] = [:]
    @State private var showAddActivity = false

    private var activeBrand: TCGBrand { services.brandSettings.selectedCatalogBrand }

    private var visibleLedgerLines: [LedgerLine] {
        return ledgerLines.filter { line in
            guard let cid = line.cardID?.trimmingCharacters(in: .whitespacesAndNewlines), !cid.isEmpty else {
                return false
            }
            return TCGBrand.inferredFromMasterCardId(cid) == activeBrand
        }
    }

    private var ledgerSignature: String {
        let brandKey = activeBrand.rawValue
        return visibleLedgerLines.map { "\($0.id.uuidString)|\($0.occurredAt.timeIntervalSince1970)" }.joined(separator: "§") + "|" + brandKey
    }

    var body: some View {
        VStack(spacing: 0) {
            transactionsHeader
            Group {
                if ledgerLines.isEmpty {
                    emptyState
                } else if visibleLedgerLines.isEmpty {
                    hiddenByBrandEmptyState
                } else {
                    transactionList
                }
            }
        }
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: ledgerSignature) {
            await resolveCardNames()
        }
        .onAppear {
            services.setupCollectionLedger(modelContext: modelContext)
        }
        .sheet(isPresented: $showAddActivity) {
            AddManualActivityView()
        }
    }

    private var transactionsHeader: some View {
        ZStack {
            Text("Activity")
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)

            HStack {
                ChromeGlassCircleButton(accessibilityLabel: "Back") {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.primary)
                }

                Spacer(minLength: 0)

                ChromeGlassCircleButton(accessibilityLabel: "Add activity") {
                    showAddActivity = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.primary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 16) {
                ContentUnavailableView(
                    "No transactions yet",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Add cards to your collection and the ledger will appear here.")
                )
                .frame(minHeight: 280)
            }
            .padding(.top, 16)
        }
    }

    private var hiddenByBrandEmptyState: some View {
        ScrollView {
            VStack(spacing: 16) {
                ContentUnavailableView(
                    "No \(activeBrand.displayTitle) transactions",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text("Transactions only appear for the active game selected in More.")
                )
                .frame(minHeight: 280)
            }
            .padding(.top, 16)
        }
    }

    private var transactionList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LazyVStack(spacing: 12) {
                    ForEach(visibleLedgerLines, id: \.persistentModelID) { line in
                        transactionRow(for: line)
                            .contextMenu {
                                Button(role: .destructive) {
                                    modelContext.delete(line)
                                    HapticManager.notification(.success)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 16)
        }
    }

    private func transactionRow(for line: LedgerLine) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: directionIcon(for: line))
                    .font(.headline)
                    .foregroundStyle(directionColor(for: line))
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text(primaryTitle(for: line))
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(secondarySubtitle(for: line))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Text(line.occurredAt, format: .dateTime.day().month(.abbreviated).year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }

            HStack(spacing: 8) {
                infoChip(label: directionTitle(for: line))
                infoChip(label: "Qty \(line.quantity)")
                if let variant = cleaned(line.variantKey) {
                    infoChip(label: variantTitle(variant))
                }
                if let value = moneySummary(for: line) {
                    infoChip(label: value)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func infoChip(label: String) -> some View {
        Text(label)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
    }

    private func resolveCardNames() async {
        var next = cardNamesByID
        for line in visibleLedgerLines {
            guard let cardID = cleaned(line.cardID), next[cardID] == nil else { continue }
            if let card = await services.cardData.loadCard(masterCardId: cardID) {
                next[cardID] = card.cardName
            }
        }
        cardNamesByID = next
    }

    private func primaryTitle(for line: LedgerLine) -> String {
        if let cardID = cleaned(line.cardID), let name = cardNamesByID[cardID] {
            return name
        }
        if let cardID = cleaned(line.cardID) {
            return cardID
        }
        if !line.lineDescription.isEmpty {
            return line.lineDescription
        }
        return directionTitle(for: line)
    }

    private func secondarySubtitle(for line: LedgerLine) -> String {
        let description = cleaned(line.lineDescription)
        let counterparty = cleaned(line.counterparty)

        if let description, let counterparty, !description.contains(counterparty) {
            return "\(description) · \(counterparty)"
        }
        if let description {
            return description
        }
        if let counterparty {
            return counterparty
        }
        return productKindTitle(for: line)
    }

    private func directionTitle(for line: LedgerLine) -> String {
        guard let direction = LedgerDirection(rawValue: line.direction) else { return line.direction.capitalized }
        switch direction {
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

    private func productKindTitle(for line: LedgerLine) -> String {
        guard let kind = ProductKind(rawValue: line.productKind) else { return line.productKind }
        switch kind {
        case .singleCard: return "Single card"
        case .gradedItem: return "Graded item"
        case .sealedProduct: return "Sealed product"
        case .boosterPack: return "Booster pack"
        case .etb: return "ETB"
        case .other: return "Other"
        }
    }

    private func directionIcon(for line: LedgerLine) -> String {
        guard let direction = LedgerDirection(rawValue: line.direction) else { return "arrow.left.arrow.right" }
        switch direction {
        case .bought: return "cart.fill"
        case .packed: return "shippingbox.fill"
        case .sold: return "dollarsign.circle.fill"
        case .tradedIn, .tradedOut: return "arrow.left.arrow.right.circle.fill"
        case .giftedIn, .giftedOut: return "gift.fill"
        case .adjustmentIn: return "plus.circle.fill"
        case .adjustmentOut: return "minus.circle.fill"
        }
    }

    private func directionColor(for line: LedgerLine) -> Color {
        guard let direction = LedgerDirection(rawValue: line.direction) else { return .secondary }
        switch direction {
        case .bought, .packed, .tradedIn, .giftedIn, .adjustmentIn:
            return .green
        case .sold, .tradedOut, .giftedOut, .adjustmentOut:
            return .orange
        }
    }

    private func moneySummary(for line: LedgerLine) -> String? {
        guard let unitPrice = line.unitPrice else { return nil }
        let total = unitPrice * Double(line.quantity)
        return total.formatted(
            .currency(code: line.currencyCode)
            .precision(.fractionLength(2))
        )
    }

    private func cleaned(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private func variantTitle(_ key: String) -> String {
        let spaced = key
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "([A-Z])", with: " $1", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return spaced.split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }
}

// MARK: - Add Manual Activity Sheet

private struct AddManualActivityView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

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

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    Picker("Type", selection: $direction) {
                        ForEach(LedgerDirection.allCases, id: \.self) { dir in
                            Text(directionTitle(dir)).tag(dir)
                        }
                    }
                    Picker("Item", selection: $productKind) {
                        ForEach(ProductKind.allCases, id: \.self) { kind in
                            Text(productKindTitle(kind)).tag(kind)
                        }
                    }
                    TextField("Description", text: $lineDescription)
                }

                Section("Transaction") {
                    Stepper("Quantity: \(quantity)", value: $quantity, in: 1...9999)
                    HStack {
                        Text("Unit price")
                        Spacer()
                        TextField("Optional", text: $unitPriceText)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                    }
                    TextField("Counterparty", text: $counterparty)
                    DatePicker("Date", selection: $occurredAt, displayedComponents: .date)
                }
            }
            .navigationTitle("Add Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .disabled(lineDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        let line = LedgerLine(
            occurredAt: occurredAt,
            direction: direction.rawValue,
            productKind: productKind.rawValue,
            lineDescription: lineDescription.trimmingCharacters(in: .whitespacesAndNewlines),
            quantity: quantity,
            unitPrice: unitPrice,
            counterparty: counterparty.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : counterparty.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        modelContext.insert(line)
        HapticManager.notification(.success)
        dismiss()
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
