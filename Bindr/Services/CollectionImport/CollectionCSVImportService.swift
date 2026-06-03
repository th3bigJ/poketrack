import Foundation
import SwiftData

enum CollectionImportSource: String, CaseIterable, Identifiable, Sendable {
    case dex = "Dex"

    var id: String { rawValue }

    var subtitle: String {
        switch self {
        case .dex:
            return "Export your collection from Dex, then choose the CSV file here."
        }
    }
}

struct CollectionCSVImportOutcome: Sendable {
    let importedCardCount: Int
    let importedCopyCount: Int
    let skippedUnknownCards: Int
    let skippedZeroQuantity: Int
    let skippedInvalidRows: Int
    let stoppedByFreeTierLimit: Bool
}

struct CollectionImportSkippedRow: Identifiable, Sendable {
    var id: String { "\(cardID)|\(variantDisplayName)" }
    let cardID: String
    let cardName: String?
    let variantDisplayName: String
    let quantity: Int
    let reason: String
}

struct CollectionImportRowPlan: Sendable {
    let cardID: String
    let cardName: String
    let variantKey: String
    let variantDisplayName: String
    let quantity: Int
}

/// Resolved import plan after matching CSV rows to the on-device catalog.
struct CollectionImportPlan: Sendable {
    let importable: [CollectionImportRowPlan]
    let skipped: [CollectionImportSkippedRow]
    let skippedZeroQuantity: Int
    let skippedInvalidRows: Int

    var importableRowCount: Int { importable.count }
    var importableCopyCount: Int { importable.reduce(0) { $0 + $1.quantity } }
}

@MainActor
enum CollectionCSVImportService {

    enum ServiceError: LocalizedError {
        case ledgerUnavailable

        var errorDescription: String? {
            switch self {
            case .ledgerUnavailable:
                return "Collection isn't ready. Try again."
            }
        }
    }

    static func buildImportPlan(
        parseResult: DexCollectionCSVImporter.ParseResult,
        services: AppServices
    ) async -> CollectionImportPlan {
        var importable: [CollectionImportRowPlan] = []
        var skipped: [CollectionImportSkippedRow] = []

        let catalogIds = Array(Set(parseResult.rows.map(\.cardID)))
        let cardsByCatalogId = await services.cardData.loadCardsByCatalogIds(catalogIds)

        for row in parseResult.rows {
            guard let card = cardsByCatalogId[row.cardID] else {
                skipped.append(CollectionImportSkippedRow(
                    cardID: row.cardID,
                    cardName: row.cardName,
                    variantDisplayName: row.variantDisplayName,
                    quantity: row.quantity,
                    reason: "Not in catalog"
                ))
                continue
            }

            let availableKeys = await services.pricing.variantKeys(for: card)
            let variantKey = DexCollectionCSVImporter.variantKey(
                forDexVariant: row.variantDisplayName,
                availableKeys: availableKeys
            )
            importable.append(CollectionImportRowPlan(
                cardID: card.masterCardId,
                cardName: row.cardName ?? card.cardName,
                variantKey: variantKey,
                variantDisplayName: row.variantDisplayName,
                quantity: row.quantity
            ))
        }

        return CollectionImportPlan(
            importable: importable,
            skipped: skipped,
            skippedZeroQuantity: parseResult.skippedZeroQuantity,
            skippedInvalidRows: parseResult.skippedInvalidRows
        )
    }

    static func importFile(
        url: URL,
        source: CollectionImportSource,
        services: AppServices,
        modelContext: ModelContext
    ) async -> Result<CollectionCSVImportOutcome, Error> {
        do {
            switch source {
            case .dex:
                let parseResult = try DexCollectionCSVImporter.parse(fileURL: url)
                let plan = await buildImportPlan(parseResult: parseResult, services: services)
                return await importPlan(plan, services: services, modelContext: modelContext)
            }
        } catch {
            return .failure(error)
        }
    }

    static func importPlan(
        _ plan: CollectionImportPlan,
        services: AppServices,
        modelContext: ModelContext
    ) async -> Result<CollectionCSVImportOutcome, Error> {
        services.setupCollectionLedger(modelContext: modelContext)
        guard let ledger = services.collectionLedger else {
            return .failure(ServiceError.ledgerUnavailable)
        }

        let currencyCode = services.priceDisplay.currency == .gbp ? "GBP" : "USD"
        var importedCards = 0
        var importedCopies = 0
        var stoppedByLimit = false

        for row in plan.importable {
            do {
                try ledger.recordSingleCardAcquisition(
                    cardID: row.cardID,
                    variantKey: row.variantKey,
                    kind: .imported,
                    quantity: row.quantity,
                    currencyCode: currencyCode,
                    cardDisplayName: row.cardName,
                    unitPrice: nil,
                    packedOpenedFrom: nil,
                    tradeCounterparty: nil,
                    tradeGaveAway: nil,
                    giftFrom: nil,
                    boughtFrom: nil
                )
                importedCards += 1
                importedCopies += row.quantity
            } catch CollectionLedgerError.freeTierLimitReached {
                stoppedByLimit = true
                break
            } catch {
                return .failure(error)
            }
        }

        let outcome = CollectionCSVImportOutcome(
            importedCardCount: importedCards,
            importedCopyCount: importedCopies,
            skippedUnknownCards: plan.skipped.count,
            skippedZeroQuantity: plan.skippedZeroQuantity,
            skippedInvalidRows: plan.skippedInvalidRows,
            stoppedByFreeTierLimit: stoppedByLimit
        )
        return .success(outcome)
    }
}
