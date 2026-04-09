import Foundation
import SwiftData

/// Creates ledger lines, collection rows, and cost lots for purchases (and future sales).
@MainActor
final class CollectionLedgerService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Records acquiring raw (non-graded) single cards: bought, from a pack, trade in, or gift.
    func recordSingleCardAcquisition(
        cardID: String,
        variantKey: String,
        kind: CollectionAcquisitionKind,
        quantity: Int,
        currencyCode: String,
        cardDisplayName: String,
        /// Unit price / estimated value for cost basis (bought, trade, gift); ignored for packed unless you extend later.
        unitPrice: Double?,
        /// Packed: what was opened (e.g. booster box name).
        packedOpenedFrom: String?,
        /// Trade: other party.
        tradeCounterparty: String?,
        /// Trade: what the user gave away.
        tradeGaveAway: String?,
        /// Gift: who gave the card.
        giftFrom: String?,
        /// Bought: seller / store (logged on ``LedgerLine/counterparty``).
        boughtFrom: String?
    ) throws {
        guard quantity > 0 else { return }

        let productKind = ProductKind.singleCard.rawValue
        let direction = kind.ledgerDirection.rawValue

        let (lineDescription, counterparty, channel) = buildLedgerMetadata(
            kind: kind,
            cardDisplayName: cardDisplayName,
            packedOpenedFrom: packedOpenedFrom,
            tradeCounterparty: tradeCounterparty,
            tradeGaveAway: tradeGaveAway,
            giftFrom: giftFrom,
            boughtFrom: boughtFrom
        )

        let line = LedgerLine(
            direction: direction,
            productKind: productKind,
            lineDescription: lineDescription,
            cardID: cardID,
            variantKey: variantKey,
            quantity: quantity,
            unitPrice: unitPrice,
            currencyCode: currencyCode,
            feesAmount: nil,
            sealedStatus: SealedInventoryStatus.notApplicable.rawValue,
            counterparty: counterparty,
            channel: channel,
            externalRef: nil,
            transactionGroupId: nil
        )
        modelContext.insert(line)

        let item = try findOrCreateSingleCardStack(cardID: cardID, variantKey: variantKey)
        item.quantity += quantity
        item.dateAcquired = Date()
        if let unitPrice {
            item.purchasePrice = unitPrice
        }

        let costPerUnit = resolvedUnitCost(kind: kind, unitPrice: unitPrice)
        let lot = CostLot(
            quantityRemaining: quantity,
            unitCost: costPerUnit,
            currencyCode: currencyCode,
            collectionItem: item,
            sourceLedgerLine: line
        )
        modelContext.insert(lot)

        try modelContext.save()
    }

    // MARK: - Manual quantity edit (card stack)

    /// Applies a manual quantity change for a single-card stack: **FIFO** reduces ``CostLot/quantityRemaining`` on decrease; **weighted-average** new lot on increase.
    func applySingleCardStackQuantityChange(
        item: CollectionItem,
        newQuantity: Int,
        cardDisplayName: String
    ) throws {
        guard item.itemKind == ProductKind.singleCard.rawValue else {
            throw CollectionLedgerError.notSingleCardStack
        }
        guard newQuantity > 0 else { throw CollectionLedgerError.invalidQuantity }

        let oldQuantity = item.quantity
        let delta = newQuantity - oldQuantity
        guard delta != 0 else { return }

        if delta < 0 {
            try applyDecreaseSingleCardStack(
                item: item,
                unitsToRemove: -delta,
                newQuantity: newQuantity,
                cardDisplayName: cardDisplayName
            )
        } else {
            try applyIncreaseSingleCardStack(
                item: item,
                unitsToAdd: delta,
                newQuantity: newQuantity,
                cardDisplayName: cardDisplayName
            )
        }
        try modelContext.save()
    }

    private func applyDecreaseSingleCardStack(
        item: CollectionItem,
        unitsToRemove: Int,
        newQuantity: Int,
        cardDisplayName: String
    ) throws {
        var remaining = unitsToRemove
        var totalCostRemoved = 0.0

        let sortedLots = (item.costLots ?? []).sorted { $0.createdAt < $1.createdAt }
        for lot in sortedLots where remaining > 0 {
            guard lot.quantityRemaining > 0 else { continue }
            let take = min(remaining, lot.quantityRemaining)
            totalCostRemoved += Double(take) * lot.unitCost
            lot.quantityRemaining -= take
            remaining -= take
            if lot.quantityRemaining == 0 {
                if (lot.saleAllocations ?? []).isEmpty {
                    modelContext.delete(lot)
                }
            }
        }

        let fallbackUnit = item.purchasePrice ?? 0
        if remaining > 0 {
            totalCostRemoved += Double(remaining) * fallbackUnit
        }

        let currency = currencyCode(for: item)
        let avgUnit = Double(unitsToRemove) > 0 ? totalCostRemoved / Double(unitsToRemove) : 0

        let description: String
        if remaining > 0 {
            description = "Manual quantity decrease (inventory exceeded cost lots; remainder at cached price) · \(cardDisplayName)"
        } else {
            description = "Manual quantity decrease · \(cardDisplayName)"
        }

        let line = LedgerLine(
            direction: LedgerDirection.adjustmentOut.rawValue,
            productKind: ProductKind.singleCard.rawValue,
            lineDescription: description,
            cardID: item.cardID,
            variantKey: item.variantKey,
            quantity: unitsToRemove,
            unitPrice: avgUnit,
            currencyCode: currency,
            feesAmount: nil,
            sealedStatus: SealedInventoryStatus.notApplicable.rawValue,
            counterparty: nil,
            channel: "manual_edit",
            externalRef: nil,
            transactionGroupId: nil
        )
        modelContext.insert(line)

        item.quantity = newQuantity
    }

    private func applyIncreaseSingleCardStack(
        item: CollectionItem,
        unitsToAdd: Int,
        newQuantity: Int,
        cardDisplayName: String
    ) throws {
        let wac = weightedAverageUnitCost(for: item)
        let currency = currencyCode(for: item)

        let line = LedgerLine(
            direction: LedgerDirection.adjustmentIn.rawValue,
            productKind: ProductKind.singleCard.rawValue,
            lineDescription: "Manual quantity increase · \(cardDisplayName)",
            cardID: item.cardID,
            variantKey: item.variantKey,
            quantity: unitsToAdd,
            unitPrice: wac,
            currencyCode: currency,
            feesAmount: nil,
            sealedStatus: SealedInventoryStatus.notApplicable.rawValue,
            counterparty: nil,
            channel: "manual_edit",
            externalRef: nil,
            transactionGroupId: nil
        )
        modelContext.insert(line)

        let lot = CostLot(
            quantityRemaining: unitsToAdd,
            unitCost: wac,
            currencyCode: currency,
            collectionItem: item,
            sourceLedgerLine: line
        )
        modelContext.insert(lot)

        item.quantity = newQuantity
        if item.purchasePrice == nil, wac > 0 {
            item.purchasePrice = wac
        }
    }

    private func weightedAverageUnitCost(for item: CollectionItem) -> Double {
        let active = (item.costLots ?? []).filter { $0.quantityRemaining > 0 }
        let totalUnits = active.reduce(0) { $0 + $1.quantityRemaining }
        guard totalUnits > 0 else { return item.purchasePrice ?? 0 }
        let totalCost = active.reduce(0.0) { $0 + Double($1.quantityRemaining) * $1.unitCost }
        return totalCost / Double(totalUnits)
    }

    private func currencyCode(for item: CollectionItem) -> String {
        let lots = item.costLots ?? []
        if let c = lots.first(where: { $0.quantityRemaining > 0 })?.currencyCode { return c }
        if let c = lots.first?.currencyCode { return c }
        return "USD"
    }

    /// Legacy path — same as ``CollectionAcquisitionKind/bought``.
    func recordBoughtSingleCard(
        cardID: String,
        variantKey: String,
        quantity: Int,
        unitPrice: Double?,
        currencyCode: String,
        lineDescription: String = ""
    ) throws {
        try recordSingleCardAcquisition(
            cardID: cardID,
            variantKey: variantKey,
            kind: .bought,
            quantity: quantity,
            currencyCode: currencyCode,
            cardDisplayName: lineDescription,
            unitPrice: unitPrice,
            packedOpenedFrom: nil,
            tradeCounterparty: nil,
            tradeGaveAway: nil,
            giftFrom: nil,
            boughtFrom: nil
        )
    }

    private func resolvedUnitCost(kind: CollectionAcquisitionKind, unitPrice: Double?) -> Double {
        switch kind {
        case .bought, .trade, .gifted:
            return unitPrice ?? 0
        case .packed:
            return 0
        }
    }

    private func buildLedgerMetadata(
        kind: CollectionAcquisitionKind,
        cardDisplayName: String,
        packedOpenedFrom: String?,
        tradeCounterparty: String?,
        tradeGaveAway: String?,
        giftFrom: String?,
        boughtFrom: String?
    ) -> (lineDescription: String, counterparty: String?, channel: String?) {
        switch kind {
        case .bought:
            return (cardDisplayName, cleanOptionalString(boughtFrom), "purchase")
        case .packed:
            let extra = packedOpenedFrom?.trimmingCharacters(in: .whitespacesAndNewlines)
            let desc: String
            if let extra, !extra.isEmpty {
                desc = "\(cardDisplayName) · Opened: \(extra)"
            } else {
                desc = "\(cardDisplayName) · From pack"
            }
            return (desc, nil, "pack")
        case .trade:
            return (cardDisplayName, cleanOptionalString(tradeCounterparty), "trade")
        case .gifted:
            return (cardDisplayName, cleanOptionalString(giftFrom), "gift")
        }
    }

    private func cleanOptionalString(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }

    private func findOrCreateSingleCardStack(cardID: String, variantKey: String) throws -> CollectionItem {
        let kind = ProductKind.singleCard.rawValue
        let descriptor = FetchDescriptor<CollectionItem>()
        let all = try modelContext.fetch(descriptor)
        if let match = all.first(where: {
            $0.cardID == cardID && $0.variantKey == variantKey && $0.itemKind == kind
        }) {
            return match
        }
        let created = CollectionItem(
            cardID: cardID,
            variantKey: variantKey,
            dateAcquired: Date(),
            purchasePrice: nil,
            quantity: 0,
            notes: "",
            itemKind: kind
        )
        modelContext.insert(created)
        return created
    }
}

// MARK: - Errors

enum CollectionLedgerError: LocalizedError {
    case notSingleCardStack
    case invalidQuantity

    var errorDescription: String? {
        switch self {
        case .notSingleCardStack:
            return "This edit only applies to single-card stacks."
        case .invalidQuantity:
            return "Quantity must be at least 1."
        }
    }
}
