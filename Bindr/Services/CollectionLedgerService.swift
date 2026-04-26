import Foundation
import SwiftData

/// Creates ledger lines, collection rows, and cost lots for purchases (and future sales).
@MainActor
final class CollectionLedgerService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Records acquiring single cards (raw or graded): bought, from a pack, trade in, or gift.
    func recordSingleCardAcquisition(
        cardID: String,
        variantKey: String,
        kind: CollectionAcquisitionKind,
        quantity: Int,
        currencyCode: String,
        cardDisplayName: String,
        /// Unit price / estimated value for cost basis (bought, trade, gift); ignored for packed unless you extend later.
        unitPrice: Double?,
        /// Grading company name (e.g. "PSA", "ACE"). Nil for raw cards.
        gradingCompany: String? = nil,
        /// Grade string (e.g. "10"). Nil for raw cards.
        grade: String? = nil,
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

        let isGraded = gradingCompany != nil
        let productKind = isGraded ? ProductKind.gradedItem.rawValue : ProductKind.singleCard.rawValue
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
            gradingCompany: gradingCompany,
            grade: grade,
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

        let item = try findOrCreateCardStack(
            cardID: cardID,
            variantKey: variantKey,
            productKind: productKind,
            gradingCompany: gradingCompany,
            grade: grade
        )
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

    /// Records that a card stack left the collection via sale, trade, or gift.
    func recordSingleCardDisposition(
        item: CollectionItem,
        kind: CollectionDispositionKind,
        quantity: Int,
        currencyCode: String,
        cardDisplayName: String,
        unitPrice: Double? = nil,
        counterparty: String? = nil,
        notes: String? = nil
    ) throws {
        guard item.itemKind == ProductKind.singleCard.rawValue || item.itemKind == ProductKind.gradedItem.rawValue else {
            throw CollectionLedgerError.notSingleCardStack
        }
        guard quantity > 0 else { throw CollectionLedgerError.invalidQuantity }
        guard quantity <= item.quantity else { throw CollectionLedgerError.insufficientQuantity }

        let productKind = item.itemKind
        let direction = kind.ledgerDirection.rawValue
        let cleanCounterparty = cleanOptionalString(counterparty)
        let cleanNotes = cleanOptionalString(notes)
        let descriptionParts = [cardDisplayName, cleanNotes].compactMap { $0 }
        let line = LedgerLine(
            direction: direction,
            productKind: productKind,
            lineDescription: descriptionParts.joined(separator: " · "),
            cardID: item.cardID,
            variantKey: item.variantKey,
            gradingCompany: item.gradingCompany,
            grade: item.grade,
            quantity: quantity,
            unitPrice: unitPrice,
            currencyCode: currencyCode,
            feesAmount: nil,
            sealedStatus: SealedInventoryStatus.notApplicable.rawValue,
            counterparty: cleanCounterparty,
            channel: dispositionChannel(for: kind),
            externalRef: nil,
            transactionGroupId: nil
        )
        modelContext.insert(line)

        var remaining = quantity
        let sortedLots = (item.costLots ?? []).sorted { $0.createdAt < $1.createdAt }
        for lot in sortedLots where remaining > 0 {
            guard lot.quantityRemaining > 0 else { continue }
            let take = min(remaining, lot.quantityRemaining)
            lot.quantityRemaining -= take
            remaining -= take

            if kind == .sold {
                let allocation = SaleAllocation(
                    quantity: take,
                    allocatedCost: Double(take) * lot.unitCost,
                    saleLedgerLine: line,
                    costLot: lot
                )
                modelContext.insert(allocation)
            } else if lot.quantityRemaining == 0, (lot.saleAllocations ?? []).isEmpty {
                modelContext.delete(lot)
            }
        }

        item.quantity -= quantity
        if item.quantity <= 0 {
            removeDepletedCollectionItem(item)
        }

        try modelContext.save()
    }

    /// Deletes a ledger line and reconciles current collection quantities for card stacks.
    /// Inbound lines (`bought`, `packed`, `tradedIn`, `giftedIn`, `adjustmentIn`) are subtracted.
    /// Outbound lines (`sold`, `tradedOut`, `giftedOut`, `adjustmentOut`) are added back.
    func deleteLedgerLineAndReconcileCollection(_ line: LedgerLine) throws {
        defer { modelContext.delete(line) }

        guard let direction = LedgerDirection(rawValue: line.direction) else {
            try modelContext.save()
            return
        }

        guard line.quantity > 0 else {
            try modelContext.save()
            return
        }

        guard let cardID = cleanOptionalString(line.cardID) else {
            try modelContext.save()
            return
        }

        let quantityDelta: Int
        switch direction {
        case .bought, .packed, .tradedIn, .giftedIn, .adjustmentIn:
            quantityDelta = -line.quantity
        case .sold, .tradedOut, .giftedOut, .adjustmentOut:
            quantityDelta = line.quantity
        }

        if line.productKind == ProductKind.singleCard.rawValue || line.productKind == ProductKind.gradedItem.rawValue {
            let variantKey = cleanOptionalString(line.variantKey) ?? "normal"
            try reconcileCardStackQuantity(
                cardID: cardID,
                variantKey: variantKey,
                productKind: line.productKind,
                gradingCompany: line.gradingCompany,
                grade: line.grade,
                quantityDelta: quantityDelta
            )
        } else if line.productKind == ProductKind.sealedProduct.rawValue {
            let sealedProductId = cleanOptionalString(line.sealedProductId)
            try reconcileSealedStackQuantity(
                cardID: cardID,
                sealedProductId: sealedProductId,
                quantityDelta: quantityDelta
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

    private func reconcileCardStackQuantity(
        cardID: String,
        variantKey: String,
        productKind: String,
        gradingCompany: String?,
        grade: String?,
        quantityDelta: Int
    ) throws {
        guard quantityDelta != 0 else { return }

        let existing = try findCardStack(
            cardID: cardID,
            variantKey: variantKey,
            productKind: productKind,
            gradingCompany: gradingCompany,
            grade: grade
        )

        if quantityDelta > 0 {
            if let existing {
                existing.quantity += quantityDelta
                existing.dateAcquired = Date()
            } else {
                let created = CollectionItem(
                    cardID: cardID,
                    variantKey: variantKey,
                    dateAcquired: Date(),
                    purchasePrice: nil,
                    quantity: quantityDelta,
                    notes: "",
                    itemKind: productKind,
                    gradingCompany: gradingCompany,
                    grade: grade
                )
                modelContext.insert(created)
            }
            return
        }

        guard let existing else { return }
        existing.quantity = max(existing.quantity + quantityDelta, 0)
        if existing.quantity == 0 {
            removeDepletedCollectionItem(existing)
        }
    }

    private func reconcileSealedStackQuantity(
        cardID: String,
        sealedProductId: String?,
        quantityDelta: Int
    ) throws {
        guard quantityDelta != 0 else { return }

        let existing = try findSealedStack(
            cardID: cardID,
            sealedProductId: sealedProductId
        )

        if quantityDelta > 0 {
            if let existing {
                existing.quantity += quantityDelta
                existing.dateAcquired = Date()
                existing.sealedStatus = SealedInventoryStatus.sealed.rawValue
            } else if let sealedProductId {
                let created = try findOrCreateSealedStack(cardID: cardID, sealedProductId: sealedProductId)
                created.quantity = quantityDelta
                created.dateAcquired = Date()
                created.sealedStatus = SealedInventoryStatus.sealed.rawValue
            } else {
                let created = CollectionItem(
                    cardID: cardID,
                    variantKey: "sealed",
                    dateAcquired: Date(),
                    purchasePrice: nil,
                    quantity: quantityDelta,
                    notes: "",
                    itemKind: ProductKind.sealedProduct.rawValue,
                    gradingCompany: nil,
                    grade: nil,
                    certNumber: nil,
                    sealedProductId: nil,
                    sealedStatus: SealedInventoryStatus.sealed.rawValue
                )
                modelContext.insert(created)
            }
            return
        }

        guard let existing else { return }
        existing.quantity = max(existing.quantity + quantityDelta, 0)
        if existing.quantity == 0 {
            removeDepletedCollectionItem(existing)
        }
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

    /// Records acquiring a sealed product stack.
    func recordSealedProductAcquisition(
        sealedProductId: String,
        productName: String,
        quantity: Int,
        kind: CollectionAcquisitionKind,
        currencyCode: String,
        unitPrice: Double?,
        cardID: String
    ) throws {
        guard quantity > 0 else { return }

        let description = productName.trimmingCharacters(in: .whitespacesAndNewlines)
        let line = LedgerLine(
            direction: kind.ledgerDirection.rawValue,
            productKind: ProductKind.sealedProduct.rawValue,
            lineDescription: description.isEmpty ? "Sealed product" : description,
            cardID: cardID,
            variantKey: "sealed",
            sealedProductId: sealedProductId,
            quantity: quantity,
            unitPrice: unitPrice,
            currencyCode: currencyCode,
            feesAmount: nil,
            sealedStatus: SealedInventoryStatus.sealed.rawValue,
            counterparty: nil,
            channel: kind == .packed ? "opened_product" : "sealed",
            externalRef: nil,
            transactionGroupId: nil
        )
        modelContext.insert(line)

        let item = try findOrCreateSealedStack(
            cardID: cardID,
            sealedProductId: sealedProductId
        )
        item.quantity += quantity
        item.dateAcquired = Date()
        item.sealedStatus = SealedInventoryStatus.sealed.rawValue
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

    /// Removes a current-holdings row once the stack is fully depleted.
    /// Keeps historical cost-lot + sale-allocation links by detaching those lots first.
    private func removeDepletedCollectionItem(_ item: CollectionItem) {
        let attachedLots = item.costLots ?? []
        for lot in attachedLots {
            if (lot.saleAllocations ?? []).isEmpty {
                modelContext.delete(lot)
            } else {
                lot.quantityRemaining = 0
                lot.collectionItem = nil
            }
        }
        modelContext.delete(item)
    }

    private func dispositionChannel(for kind: CollectionDispositionKind) -> String {
        switch kind {
        case .sold: return "sale"
        case .traded: return "trade"
        case .gifted: return "gift"
        }
    }

    private func findOrCreateCardStack(
        cardID: String,
        variantKey: String,
        productKind: String,
        gradingCompany: String?,
        grade: String?
    ) throws -> CollectionItem {
        let descriptor = FetchDescriptor<CollectionItem>()
        let all = try modelContext.fetch(descriptor)
        if let match = all.first(where: {
            $0.cardID == cardID
                && $0.variantKey == variantKey
                && $0.itemKind == productKind
                && $0.gradingCompany == gradingCompany
                && $0.grade == grade
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
            itemKind: productKind,
            gradingCompany: gradingCompany,
            grade: grade
        )
        modelContext.insert(created)
        return created
    }

    private func findCardStack(
        cardID: String,
        variantKey: String,
        productKind: String,
        gradingCompany: String?,
        grade: String?
    ) throws -> CollectionItem? {
        let descriptor = FetchDescriptor<CollectionItem>()
        let all = try modelContext.fetch(descriptor)
        return all.first(where: {
            $0.cardID == cardID
                && $0.variantKey == variantKey
                && $0.itemKind == productKind
                && $0.gradingCompany == gradingCompany
                && $0.grade == grade
        })
    }

    private func findSealedStack(
        cardID: String,
        sealedProductId: String?
    ) throws -> CollectionItem? {
        let descriptor = FetchDescriptor<CollectionItem>()
        let all = try modelContext.fetch(descriptor)
        return all.first(where: { item in
            guard item.cardID == cardID, item.itemKind == ProductKind.sealedProduct.rawValue else {
                return false
            }
            if let sealedProductId {
                return item.sealedProductId == sealedProductId
            }
            return true
        })
    }

    private func findOrCreateSealedStack(
        cardID: String,
        sealedProductId: String
    ) throws -> CollectionItem {
        let descriptor = FetchDescriptor<CollectionItem>()
        let all = try modelContext.fetch(descriptor)
        if let match = all.first(where: {
            $0.cardID == cardID
                && $0.itemKind == ProductKind.sealedProduct.rawValue
                && $0.sealedProductId == sealedProductId
        }) {
            return match
        }
        let created = CollectionItem(
            cardID: cardID,
            variantKey: "sealed",
            dateAcquired: Date(),
            purchasePrice: nil,
            quantity: 0,
            notes: "",
            itemKind: ProductKind.sealedProduct.rawValue,
            gradingCompany: nil,
            grade: nil,
            certNumber: nil,
            sealedProductId: sealedProductId,
            sealedStatus: SealedInventoryStatus.sealed.rawValue
        )
        modelContext.insert(created)
        return created
    }
}

// MARK: - Errors

enum CollectionLedgerError: LocalizedError {
    case notSingleCardStack
    case invalidQuantity
    case insufficientQuantity

    var errorDescription: String? {
        switch self {
        case .notSingleCardStack:
            return "This edit only applies to single-card stacks."
        case .invalidQuantity:
            return "Quantity must be at least 1."
        case .insufficientQuantity:
            return "You don't have that many copies in this stack."
        }
    }
}
