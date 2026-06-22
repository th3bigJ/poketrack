import Foundation
import SwiftData

/// Re-links active ``CostLot`` rows to the correct ``CollectionItem`` stack using each lot's source ledger line.
enum CollectionCostLotRepair {
    @discardableResult
    static func relinkActiveLots(in modelContext: ModelContext) throws -> Int {
        let items = try modelContext.fetch(FetchDescriptor<CollectionItem>())
            .filter { $0.quantity > 0 && !$0.cardID.isEmpty }

        var itemByStackKey: [String: CollectionItem] = [:]
        itemByStackKey.reserveCapacity(items.count)
        for item in items {
            itemByStackKey[stackKey(for: item)] = item
        }

        let lots = try modelContext.fetch(FetchDescriptor<CostLot>())
        var relinked = 0

        for lot in lots where lot.quantityRemaining > 0 {
            guard let line = lot.sourceLedgerLine else { continue }
            guard let cardID = cleaned(line.cardID) else { continue }

            let key = stackKey(for: line)
            guard let target = itemByStackKey[key], target.cardID == cardID else { continue }

            if lot.collectionItem?.persistentModelID != target.persistentModelID {
                lot.collectionItem = target
                relinked += 1
            }
        }

        if relinked > 0 {
            try modelContext.save()
        }
        return relinked
    }

    static func stackKey(for item: CollectionItem) -> String {
        stackKey(
            cardID: item.cardID,
            variantKey: item.variantKey,
            itemKind: item.itemKind,
            gradingCompany: item.gradingCompany,
            grade: item.grade,
            certNumber: item.certNumber,
            sealedProductId: item.sealedProductId,
            sealedStatus: item.sealedStatus
        )
    }

    static func stackKey(for line: LedgerLine) -> String {
        stackKey(
            cardID: cleaned(line.cardID) ?? "",
            variantKey: cleaned(line.variantKey) ?? "normal",
            itemKind: line.productKind,
            gradingCompany: line.gradingCompany,
            grade: line.grade,
            certNumber: line.certNumber,
            sealedProductId: line.sealedProductId,
            sealedStatus: line.sealedStatus
        )
    }

    private static func stackKey(
        cardID: String,
        variantKey: String,
        itemKind: String,
        gradingCompany: String?,
        grade: String?,
        certNumber: String?,
        sealedProductId: String?,
        sealedStatus: String?
    ) -> String {
        [
            itemKind,
            cardID,
            variantKey.isEmpty ? "normal" : variantKey,
            cleaned(gradingCompany) ?? "",
            cleaned(grade) ?? "",
            cleaned(certNumber) ?? "",
            cleaned(sealedProductId) ?? "",
            cleaned(sealedStatus) ?? "",
        ].joined(separator: "\u{1F}")
    }

    private static func cleaned(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
