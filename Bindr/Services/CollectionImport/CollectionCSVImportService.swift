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

    static func importFile(
        url: URL,
        source: CollectionImportSource,
        services: AppServices,
        modelContext: ModelContext
    ) async -> Result<CollectionCSVImportOutcome, Error> {
        services.setupCollectionLedger(modelContext: modelContext)
        guard let ledger = services.collectionLedger else {
            return .failure(ServiceError.ledgerUnavailable)
        }

        do {
            switch source {
            case .dex:
                let parseResult = try DexCollectionCSVImporter.parse(fileURL: url)
                return await importDexRows(parseResult, ledger: ledger, services: services)
            }
        } catch {
            return .failure(error)
        }
    }

    private static func importDexRows(
        _ parseResult: DexCollectionCSVImporter.ParseResult,
        ledger: CollectionLedgerService,
        services: AppServices
    ) async -> Result<CollectionCSVImportOutcome, Error> {
        let currencyCode = services.priceDisplay.currency == .gbp ? "GBP" : "USD"
        var importedCards = 0
        var importedCopies = 0
        var skippedUnknown = 0
        var stoppedByLimit = false

        for row in parseResult.rows {
            guard let card = await services.cardData.loadCard(masterCardId: row.cardID) else {
                skippedUnknown += 1
                continue
            }

            let availableKeys = await services.pricing.variantKeys(for: card)
            let variantKey = DexCollectionCSVImporter.variantKey(
                forDexVariant: row.variantDisplayName,
                availableKeys: availableKeys
            )
            let displayName = row.cardName ?? card.cardName

            do {
                try ledger.recordSingleCardAcquisition(
                    cardID: card.masterCardId,
                    variantKey: variantKey,
                    kind: .imported,
                    quantity: row.quantity,
                    currencyCode: currencyCode,
                    cardDisplayName: displayName,
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
            skippedUnknownCards: skippedUnknown,
            skippedZeroQuantity: parseResult.skippedZeroQuantity,
            skippedInvalidRows: parseResult.skippedInvalidRows,
            stoppedByFreeTierLimit: stoppedByLimit
        )
        return .success(outcome)
    }
}
