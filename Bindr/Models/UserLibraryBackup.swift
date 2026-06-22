import Foundation
import SwiftData

/// Full user library snapshot stored at `user-collections/{userID}/collection.json`.
/// Schema v1: top-level `collection` + `wishlist` only (trade friend previews).
/// Schema v2: adds `library` with binders, decks, ledger, and value history.
/// Schema v3: adds `preferences` (theme, currency, grid, filters, offline toggles).
struct UserLibraryBackup: Codable {
    static let currentSchemaVersion = 3

    struct CardEntry: Codable {
        let cardID: String
        let variantKey: String
        let qty: Int

        enum CodingKeys: String, CodingKey {
            case cardID = "cardID"
            case variantKey
            case qty
        }
    }

    struct WishlistEntry: Codable {
        let cardID: String
        let variantKey: String
        let dateAdded: String?
        let notes: String?
        let collectionName: String?

        enum CodingKeys: String, CodingKey {
            case cardID
            case cardIDSnake = "card_id"
            case variantKey
            case variantKeySnake = "variant_key"
            case dateAdded
            case notes
            case collectionName
        }

        init(
            cardID: String,
            variantKey: String,
            dateAdded: String? = nil,
            notes: String? = nil,
            collectionName: String? = nil
        ) {
            self.cardID = cardID
            self.variantKey = variantKey
            self.dateAdded = dateAdded
            self.notes = notes
            self.collectionName = collectionName
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            cardID = try container.decodeIfPresent(String.self, forKey: .cardID)
                ?? container.decodeIfPresent(String.self, forKey: .cardIDSnake)
                ?? ""
            variantKey = try container.decodeIfPresent(String.self, forKey: .variantKey)
                ?? container.decodeIfPresent(String.self, forKey: .variantKeySnake)
                ?? "normal"
            dateAdded = try container.decodeIfPresent(String.self, forKey: .dateAdded)
            notes = try container.decodeIfPresent(String.self, forKey: .notes)
            collectionName = try container.decodeIfPresent(String.self, forKey: .collectionName)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(cardID, forKey: .cardID)
            try container.encode(variantKey, forKey: .variantKey)
            try container.encodeIfPresent(dateAdded, forKey: .dateAdded)
            try container.encodeIfPresent(notes, forKey: .notes)
            try container.encodeIfPresent(collectionName, forKey: .collectionName)
        }
    }

    struct LibraryPayload: Codable {
        let collectionItems: [CollectionItemRecord]
        let wishlistItems: [WishlistItemRecord]
        let ledgerLines: [LedgerLineRecord]
        let costLots: [CostLotRecord]
        let saleAllocations: [SaleAllocationRecord]
        let binders: [BinderRecord]
        let binderSlots: [BinderSlotRecord]
        let decks: [DeckRecord]
        let deckCards: [DeckCardRecord]
        let valueSnapshots: [ValueSnapshotRecord]
        let weeklyAverages: [PeriodAverageRecord]
        let monthlyAverages: [PeriodAverageRecord]
    }

    struct CollectionItemRecord: Codable {
        let exportID: UUID
        let cardID: String
        let variantKey: String
        let dateAcquired: String
        let purchasePrice: Double?
        let quantity: Int
        let notes: String
        let itemKind: String
        let gradingCompany: String?
        let grade: String?
        let certNumber: String?
        let sealedProductId: String?
        let sealedStatus: String?
    }

    struct WishlistItemRecord: Codable {
        let cardID: String
        let variantKey: String
        let dateAdded: String
        let notes: String
        let collectionName: String?
    }

    struct LedgerLineRecord: Codable {
        let id: UUID
        let occurredAt: String
        let direction: String
        let productKind: String
        let lineDescription: String
        let cardID: String?
        let variantKey: String?
        let sealedProductId: String?
        let gradingCompany: String?
        let grade: String?
        let certNumber: String?
        let quantity: Int
        let unitPrice: Double?
        let currencyCode: String
        let feesAmount: Double?
        let sealedStatus: String?
        let counterparty: String?
        let channel: String?
        let externalRef: String?
        let transactionGroupId: UUID?
    }

    struct CostLotRecord: Codable {
        let id: UUID
        let collectionItemExportID: UUID?
        let sourceLedgerLineID: UUID?
        let quantityRemaining: Int
        let unitCost: Double
        let currencyCode: String
        let createdAt: String
    }

    struct SaleAllocationRecord: Codable {
        let id: UUID
        let saleLedgerLineID: UUID
        let costLotID: UUID
        let quantity: Int
        let allocatedCost: Double
    }

    struct BinderRecord: Codable {
        let id: UUID
        let title: String
        let brand: String
        let pageLayout: String
        let colour: String
        let texture: String
        let showCardPreview: Bool
        let showValueOnCover: Bool
        let showPriceOverlay: Bool
        let titleTextColor: String
        let titleFontStyle: String
        let embossedCardID: String?
        let embossedPokemonImageUrl: String?
        let embossMode: String
        let createdAt: String
    }

    struct BinderSlotRecord: Codable {
        let binderID: UUID
        let position: Int
        let cardID: String
        let variantKey: String
        let cardName: String
    }

    struct DeckRecord: Codable {
        let id: UUID
        let title: String
        let brand: String
        let format: String
        let createdAt: String
        let mainCardID: String?
    }

    struct DeckCardRecord: Codable {
        let deckID: UUID
        let cardID: String
        let variantKey: String
        let cardName: String
        let quantity: Int
        let isBasicEnergy: Bool
        let isAceSpec: Bool
        let isRadiant: Bool
        let isBasicPokemon: Bool
        let isRuleBox: Bool
        let setKey: String
        let localId: String?
        let regulationMark: String?
        let elementTypes: [String]?
        let trainerType: String?
        let isEnergy: Bool
        let imageLowSrc: String
        let catalogCategory: String?
        let catalogSubtype: String?
        let catalogStage: String?
        let opCost: Int?
        let opPower: Int?
        let opCounter: Int?
    }

    struct ValueSnapshotRecord: Codable {
        let date: String
        let totalGbp: Double
        let pokemonGbp: Double
        let onePieceGbp: Double
        let cardsGbp: Double
        let sealedGbp: Double
    }

    struct PeriodAverageRecord: Codable {
        let periodStart: String
        let totalGbp: Double
        let pokemonGbp: Double
        let onePieceGbp: Double
        let cardsGbp: Double
        let sealedGbp: Double
    }

    let schemaVersion: Int
    let userID: String
    let updatedAt: String
    let collection: [CardEntry]
    let wishlist: [WishlistEntry]
    let library: LibraryPayload?
    let preferences: AppPreferencesBackup?

    init(
        schemaVersion: Int = UserLibraryBackup.currentSchemaVersion,
        userID: String,
        updatedAt: String,
        collection: [CardEntry],
        wishlist: [WishlistEntry],
        library: LibraryPayload? = nil,
        preferences: AppPreferencesBackup? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.userID = userID
        self.updatedAt = updatedAt
        self.collection = collection
        self.wishlist = wishlist
        self.library = library
        self.preferences = preferences
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        userID = try container.decode(String.self, forKey: .userID)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
        collection = try container.decodeIfPresent([CardEntry].self, forKey: .collection) ?? []
        wishlist = try container.decodeIfPresent([WishlistEntry].self, forKey: .wishlist) ?? []
        library = try container.decodeIfPresent(LibraryPayload.self, forKey: .library)
        preferences = try container.decodeIfPresent(AppPreferencesBackup.self, forKey: .preferences)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case userID
        case updatedAt
        case collection
        case wishlist
        case library
        case preferences
    }

    var hasAnyData: Bool {
        if !collection.isEmpty || !wishlist.isEmpty { return true }
        guard let library else { return false }
        return !library.collectionItems.isEmpty
            || !library.wishlistItems.isEmpty
            || !library.ledgerLines.isEmpty
            || !library.binders.isEmpty
            || !library.decks.isEmpty
            || !library.valueSnapshots.isEmpty
            || !library.weeklyAverages.isEmpty
            || !library.monthlyAverages.isEmpty
    }

    var backupSummaryLine: String {
        if let library {
            let cards = library.collectionItems.reduce(0) { $0 + max($1.quantity, 0) }
            return "\(cards) cards · \(library.binders.count) binders · \(library.decks.count) decks · \(library.ledgerLines.count) ledger lines"
        }
        let cards = collection.reduce(0) { $0 + max($1.qty, 0) }
        return "\(cards) cards · \(wishlist.count) wishlist"
    }
}

/// Trade builder and legacy call sites.
typealias FriendCollectionSnapshot = UserLibraryBackup

// MARK: - Codec

enum UserLibraryBackupCodec {
    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func encodeDate(_ date: Date) -> String {
        iso8601.string(from: date)
    }

    private static func decodeDate(_ raw: String) -> Date {
        iso8601.date(from: raw) ?? ISO8601DateFormatter().date(from: raw) ?? Date()
    }

    static func build(userID: UUID, modelContext: ModelContext) throws -> UserLibraryBackup {
        let collectionItems = try modelContext.fetch(FetchDescriptor<CollectionItem>())
        let wishlistItems = try modelContext.fetch(FetchDescriptor<WishlistItem>())
        let ledgerLines = try modelContext.fetch(FetchDescriptor<LedgerLine>())
        let costLots = try modelContext.fetch(FetchDescriptor<CostLot>())
        let saleAllocations = try modelContext.fetch(FetchDescriptor<SaleAllocation>())
        let binders = try modelContext.fetch(FetchDescriptor<Binder>())
        let decks = try modelContext.fetch(FetchDescriptor<Deck>())
        let valueSnapshots = try modelContext.fetch(FetchDescriptor<CollectionValueSnapshot>())
        let weeklyAverages = try modelContext.fetch(FetchDescriptor<CollectionWeeklyAverage>())
        let monthlyAverages = try modelContext.fetch(FetchDescriptor<CollectionMonthlyAverage>())

        var exportIDByCollectionItem = [ObjectIdentifier: UUID]()
        let collectionRecords: [UserLibraryBackup.CollectionItemRecord] = collectionItems.map { item in
            let exportID = UUID()
            exportIDByCollectionItem[ObjectIdentifier(item)] = exportID
            return UserLibraryBackup.CollectionItemRecord(
                exportID: exportID,
                cardID: item.cardID,
                variantKey: item.variantKey,
                dateAcquired: encodeDate(item.dateAcquired),
                purchasePrice: item.purchasePrice,
                quantity: item.quantity,
                notes: item.notes,
                itemKind: item.itemKind,
                gradingCompany: item.gradingCompany,
                grade: item.grade,
                certNumber: item.certNumber,
                sealedProductId: item.sealedProductId,
                sealedStatus: item.sealedStatus
            )
        }
        let consolidatedCollection = consolidateCollectionItemRecords(collectionRecords)

        let legacyCollection: [UserLibraryBackup.CardEntry] = consolidatedCollection.records.compactMap { item in
            guard item.quantity > 0, !item.cardID.isEmpty else { return nil }
            return UserLibraryBackup.CardEntry(
                cardID: item.cardID,
                variantKey: item.variantKey,
                qty: item.quantity
            )
        }

        let legacyWishlist: [UserLibraryBackup.WishlistEntry] = wishlistItems.compactMap { item in
            guard !item.cardID.isEmpty else { return nil }
            return UserLibraryBackup.WishlistEntry(
                cardID: item.cardID,
                variantKey: item.variantKey,
                dateAdded: encodeDate(item.dateAdded),
                notes: item.notes.isEmpty ? nil : item.notes,
                collectionName: item.collectionName
            )
        }

        let wishlistRecords = wishlistItems.map {
            UserLibraryBackup.WishlistItemRecord(
                cardID: $0.cardID,
                variantKey: $0.variantKey,
                dateAdded: encodeDate($0.dateAdded),
                notes: $0.notes,
                collectionName: $0.collectionName
            )
        }

        let ledgerRecords = ledgerLines.map {
            UserLibraryBackup.LedgerLineRecord(
                id: $0.id,
                occurredAt: encodeDate($0.occurredAt),
                direction: $0.direction,
                productKind: $0.productKind,
                lineDescription: $0.lineDescription,
                cardID: $0.cardID,
                variantKey: $0.variantKey,
                sealedProductId: $0.sealedProductId,
                gradingCompany: $0.gradingCompany,
                grade: $0.grade,
                certNumber: $0.certNumber,
                quantity: $0.quantity,
                unitPrice: $0.unitPrice,
                currencyCode: $0.currencyCode,
                feesAmount: $0.feesAmount,
                sealedStatus: $0.sealedStatus,
                counterparty: $0.counterparty,
                channel: $0.channel,
                externalRef: $0.externalRef,
                transactionGroupId: $0.transactionGroupId
            )
        }

        let costLotRecords = costLots.map { lot in
            let rawExportID = lot.collectionItem.flatMap { exportIDByCollectionItem[ObjectIdentifier($0)] }
            let mappedExportID = rawExportID.flatMap { consolidatedCollection.exportIDRemap[$0] ?? $0 }
            return UserLibraryBackup.CostLotRecord(
                id: lot.id,
                collectionItemExportID: mappedExportID,
                sourceLedgerLineID: lot.sourceLedgerLine?.id,
                quantityRemaining: lot.quantityRemaining,
                unitCost: lot.unitCost,
                currencyCode: lot.currencyCode,
                createdAt: encodeDate(lot.createdAt)
            )
        }

        let saleAllocationRecords: [UserLibraryBackup.SaleAllocationRecord] = saleAllocations.compactMap { allocation in
            guard let saleID = allocation.saleLedgerLine?.id,
                  let lotID = allocation.costLot?.id else { return nil }
            return UserLibraryBackup.SaleAllocationRecord(
                id: allocation.id,
                saleLedgerLineID: saleID,
                costLotID: lotID,
                quantity: allocation.quantity,
                allocatedCost: allocation.allocatedCost
            )
        }

        let binderRecords = binders.map {
            UserLibraryBackup.BinderRecord(
                id: $0.id,
                title: $0.title,
                brand: $0.brand,
                pageLayout: $0.pageLayout,
                colour: $0.colour,
                texture: $0.texture,
                showCardPreview: $0.showCardPreview,
                showValueOnCover: $0.showValueOnCover,
                showPriceOverlay: $0.showPriceOverlay,
                titleTextColor: $0.titleTextColor,
                titleFontStyle: $0.titleFontStyle,
                embossedCardID: $0.embossedCardID,
                embossedPokemonImageUrl: $0.embossedPokemonImageUrl,
                embossMode: $0.embossMode,
                createdAt: encodeDate($0.createdAt)
            )
        }

        let binderSlotRecords = binders.flatMap { binder in
            binder.slotList.map { slot in
                UserLibraryBackup.BinderSlotRecord(
                    binderID: binder.id,
                    position: slot.position,
                    cardID: slot.cardID,
                    variantKey: slot.variantKey,
                    cardName: slot.cardName
                )
            }
        }

        let deckRecords = decks.map {
            UserLibraryBackup.DeckRecord(
                id: $0.id,
                title: $0.title,
                brand: $0.brand,
                format: $0.format,
                createdAt: encodeDate($0.createdAt),
                mainCardID: $0.mainCardID
            )
        }

        let deckCardRecords = decks.flatMap { deck in
            deck.cardList.map { card in
                UserLibraryBackup.DeckCardRecord(
                    deckID: deck.id,
                    cardID: card.cardID,
                    variantKey: card.variantKey,
                    cardName: card.cardName,
                    quantity: card.quantity,
                    isBasicEnergy: card.isBasicEnergy,
                    isAceSpec: card.isAceSpec,
                    isRadiant: card.isRadiant,
                    isBasicPokemon: card.isBasicPokemon,
                    isRuleBox: card.isRuleBox,
                    setKey: card.setKey,
                    localId: card.localId,
                    regulationMark: card.regulationMark,
                    elementTypes: card.elementTypes,
                    trainerType: card.trainerType,
                    isEnergy: card.isEnergy,
                    imageLowSrc: card.imageLowSrc,
                    catalogCategory: card.catalogCategory,
                    catalogSubtype: card.catalogSubtype,
                    catalogStage: card.catalogStage,
                    opCost: card.opCost,
                    opPower: card.opPower,
                    opCounter: card.opCounter
                )
            }
        }

        let valueSnapshotRecords = valueSnapshots.map {
            UserLibraryBackup.ValueSnapshotRecord(
                date: encodeDate($0.date),
                totalGbp: $0.totalGbp,
                pokemonGbp: $0.pokemonGbp,
                onePieceGbp: $0.onePieceGbp,
                cardsGbp: $0.cardsGbp,
                sealedGbp: $0.sealedGbp
            )
        }

        let weeklyRecords = weeklyAverages.map {
            UserLibraryBackup.PeriodAverageRecord(
                periodStart: encodeDate($0.weekStart),
                totalGbp: $0.totalGbp,
                pokemonGbp: $0.pokemonGbp,
                onePieceGbp: $0.onePieceGbp,
                cardsGbp: $0.cardsGbp,
                sealedGbp: $0.sealedGbp
            )
        }

        let monthlyRecords = monthlyAverages.map {
            UserLibraryBackup.PeriodAverageRecord(
                periodStart: encodeDate($0.monthStart),
                totalGbp: $0.totalGbp,
                pokemonGbp: $0.pokemonGbp,
                onePieceGbp: $0.onePieceGbp,
                cardsGbp: $0.cardsGbp,
                sealedGbp: $0.sealedGbp
            )
        }

        let library = UserLibraryBackup.LibraryPayload(
            collectionItems: consolidatedCollection.records,
            wishlistItems: wishlistRecords,
            ledgerLines: ledgerRecords,
            costLots: costLotRecords,
            saleAllocations: saleAllocationRecords,
            binders: binderRecords,
            binderSlots: binderSlotRecords,
            decks: deckRecords,
            deckCards: deckCardRecords,
            valueSnapshots: valueSnapshotRecords,
            weeklyAverages: weeklyRecords,
            monthlyAverages: monthlyRecords
        )

        return UserLibraryBackup(
            userID: userID.uuidString.lowercased(),
            updatedAt: encodeDate(Date()),
            collection: legacyCollection,
            wishlist: legacyWishlist,
            library: library,
            preferences: AppPreferencesBackup.capture()
        )
    }

    @discardableResult
    static func apply(
        _ snapshot: UserLibraryBackup,
        modelContext: ModelContext,
        replaceExisting: Bool
    ) throws -> Int {
        if replaceExisting {
            try clearLibrary(modelContext: modelContext)
        }

        let restoredCount: Int
        if let library = snapshot.library, snapshot.schemaVersion >= 2 {
            restoredCount = try applyFullLibrary(library, modelContext: modelContext)
        } else {
            restoredCount = try applyLegacySnapshot(snapshot, modelContext: modelContext)
        }

        if let preferences = snapshot.preferences, !preferences.isEmpty {
            preferences.apply()
        }

        return restoredCount
    }

    static func clearLocalLibrary(modelContext: ModelContext) throws {
        try clearLibrary(modelContext: modelContext)
    }

    static func localLibraryIsEmpty(_ modelContext: ModelContext) -> Bool {
        let checks: [() -> Int] = [
            { modelContext.collectionTotalCardQuantity() },
            { (try? modelContext.fetchCount(FetchDescriptor<WishlistItem>())) ?? 0 },
            { (try? modelContext.fetchCount(FetchDescriptor<LedgerLine>())) ?? 0 },
            { (try? modelContext.fetchCount(FetchDescriptor<Binder>())) ?? 0 },
            { (try? modelContext.fetchCount(FetchDescriptor<Deck>())) ?? 0 },
            { (try? modelContext.fetchCount(FetchDescriptor<CollectionValueSnapshot>())) ?? 0 },
        ]
        return checks.allSatisfy { $0() == 0 }
    }

    private static func clearLibrary(modelContext: ModelContext) throws {
        try modelContext.delete(model: SaleAllocation.self)
        try modelContext.delete(model: CostLot.self)
        try modelContext.delete(model: LedgerLine.self)
        try modelContext.delete(model: CollectionItem.self)
        try modelContext.delete(model: WishlistItem.self)
        try modelContext.delete(model: BinderSlot.self)
        try modelContext.delete(model: Binder.self)
        try modelContext.delete(model: DeckCard.self)
        try modelContext.delete(model: Deck.self)
        try modelContext.delete(model: CollectionValueSnapshot.self)
        try modelContext.delete(model: CollectionWeeklyAverage.self)
        try modelContext.delete(model: CollectionMonthlyAverage.self)
        try modelContext.save()
    }

    private static func applyLegacySnapshot(
        _ snapshot: UserLibraryBackup,
        modelContext: ModelContext
    ) throws -> Int {
        var restoredCards = 0
        let restoreDate = Date()
        var mergedByKey: [String: Int] = [:]
        var variantByCard: [String: String] = [:]

        for entry in snapshot.collection where entry.qty > 0 && !entry.cardID.isEmpty {
            let variantKey = entry.variantKey.isEmpty ? "normal" : entry.variantKey
            let key = "\(entry.cardID)\u{1F}\(variantKey)"
            mergedByKey[key, default: 0] += entry.qty
            variantByCard[key] = variantKey
        }

        for (key, qty) in mergedByKey {
            let cardID = key.split(separator: "\u{1F}", maxSplits: 1).first.map(String.init) ?? ""
            guard !cardID.isEmpty else { continue }
            let variantKey = variantByCard[key] ?? "normal"
            let item = CollectionItem(
                cardID: cardID,
                variantKey: variantKey,
                dateAcquired: restoreDate,
                purchasePrice: nil,
                quantity: qty,
                notes: "Restored from cloud backup"
            )
            modelContext.insert(item)
            restoredCards += qty
        }

        let existingWishlist = try modelContext.fetch(FetchDescriptor<WishlistItem>())
        for entry in snapshot.wishlist where !entry.cardID.isEmpty {
            let variantKey = entry.variantKey.isEmpty ? "normal" : entry.variantKey
            let alreadyExists = existingWishlist.contains {
                $0.cardID == entry.cardID && $0.variantKey == variantKey
            }
            guard !alreadyExists else { continue }
            modelContext.insert(
                WishlistItem(
                    cardID: entry.cardID,
                    variantKey: variantKey,
                    dateAdded: entry.dateAdded.map(decodeDate) ?? restoreDate,
                    notes: entry.notes ?? "",
                    collectionName: entry.collectionName
                )
            )
        }

        try modelContext.save()
        return restoredCards
    }

    private static func applyFullLibrary(
        _ library: UserLibraryBackup.LibraryPayload,
        modelContext: ModelContext
    ) throws -> Int {
        var restoredCards = 0
        var collectionItemByExportID: [UUID: CollectionItem] = [:]
        var ledgerLineByID: [UUID: LedgerLine] = [:]
        var costLotByID: [UUID: CostLot] = [:]
        var binderByID: [UUID: Binder] = [:]
        var deckByID: [UUID: Deck] = [:]

        let consolidated = consolidateCollectionItemRecords(library.collectionItems)
        for record in consolidated.records where record.quantity > 0 && !record.cardID.isEmpty {
            let item = CollectionItem(
                cardID: record.cardID,
                variantKey: record.variantKey.isEmpty ? "normal" : record.variantKey,
                dateAcquired: decodeDate(record.dateAcquired),
                purchasePrice: record.purchasePrice,
                quantity: record.quantity,
                notes: record.notes,
                itemKind: record.itemKind,
                gradingCompany: record.gradingCompany,
                grade: record.grade,
                certNumber: record.certNumber,
                sealedProductId: record.sealedProductId,
                sealedStatus: record.sealedStatus
            )
            modelContext.insert(item)
            collectionItemByExportID[record.exportID] = item
            restoredCards += record.quantity
        }

        for record in library.ledgerLines {
            let line = LedgerLine(
                id: record.id,
                occurredAt: decodeDate(record.occurredAt),
                direction: record.direction,
                productKind: record.productKind,
                lineDescription: record.lineDescription,
                cardID: record.cardID,
                variantKey: record.variantKey,
                sealedProductId: record.sealedProductId,
                gradingCompany: record.gradingCompany,
                grade: record.grade,
                certNumber: record.certNumber,
                quantity: record.quantity,
                unitPrice: record.unitPrice,
                currencyCode: record.currencyCode,
                feesAmount: record.feesAmount,
                sealedStatus: record.sealedStatus,
                counterparty: record.counterparty,
                channel: record.channel,
                externalRef: record.externalRef,
                transactionGroupId: record.transactionGroupId
            )
            modelContext.insert(line)
            ledgerLineByID[record.id] = line
        }

        for record in library.costLots {
            let mappedExportID = record.collectionItemExportID.flatMap { consolidated.exportIDRemap[$0] ?? $0 }
            let lot = CostLot(
                id: record.id,
                quantityRemaining: record.quantityRemaining,
                unitCost: record.unitCost,
                currencyCode: record.currencyCode,
                createdAt: decodeDate(record.createdAt),
                collectionItem: mappedExportID.flatMap { collectionItemByExportID[$0] },
                sourceLedgerLine: record.sourceLedgerLineID.flatMap { ledgerLineByID[$0] }
            )
            modelContext.insert(lot)
            costLotByID[record.id] = lot
        }

        for record in library.saleAllocations {
            guard let saleLine = ledgerLineByID[record.saleLedgerLineID],
                  let costLot = costLotByID[record.costLotID] else { continue }
            let allocation = SaleAllocation(
                id: record.id,
                quantity: record.quantity,
                allocatedCost: record.allocatedCost,
                saleLedgerLine: saleLine,
                costLot: costLot
            )
            modelContext.insert(allocation)
        }

        for record in library.wishlistItems where !record.cardID.isEmpty {
            modelContext.insert(
                WishlistItem(
                    cardID: record.cardID,
                    variantKey: record.variantKey.isEmpty ? "normal" : record.variantKey,
                    dateAdded: decodeDate(record.dateAdded),
                    notes: record.notes,
                    collectionName: record.collectionName
                )
            )
        }

        for record in library.binders {
            let binder = Binder(
                title: record.title,
                brand: TCGBrand(rawValue: record.brand) ?? .pokemon,
                pageLayout: BinderPageLayout(rawValue: record.pageLayout),
                colour: record.colour,
                texture: BinderTexture(rawValue: record.texture) ?? .smooth,
                showCardPreview: record.showCardPreview,
                showValueOnCover: record.showValueOnCover,
                showPriceOverlay: record.showPriceOverlay,
                titleTextColor: BinderTitleTextColor(rawValue: record.titleTextColor) ?? .gold,
                titleFontStyle: BinderTitleFontStyle(rawValue: record.titleFontStyle) ?? .serif
            )
            binder.id = record.id
            binder.embossedCardID = record.embossedCardID
            binder.embossedPokemonImageUrl = record.embossedPokemonImageUrl
            binder.embossMode = record.embossMode
            binder.createdAt = decodeDate(record.createdAt)
            modelContext.insert(binder)
            binderByID[record.id] = binder
        }

        for record in library.binderSlots {
            guard let binder = binderByID[record.binderID] else { continue }
            let slot = BinderSlot(
                position: record.position,
                cardID: record.cardID,
                variantKey: record.variantKey,
                cardName: record.cardName
            )
            slot.binder = binder
            modelContext.insert(slot)
        }

        for record in library.decks {
            let deck = Deck(
                title: record.title,
                brand: TCGBrand(rawValue: record.brand) ?? .pokemon,
                format: DeckFormat(rawValue: record.format) ?? .pokemonStandard
            )
            deck.id = record.id
            deck.createdAt = decodeDate(record.createdAt)
            deck.mainCardID = record.mainCardID
            modelContext.insert(deck)
            deckByID[record.id] = deck
        }

        for record in library.deckCards {
            guard let deck = deckByID[record.deckID] else { continue }
            let card = DeckCard(
                cardID: record.cardID,
                variantKey: record.variantKey,
                cardName: record.cardName,
                quantity: record.quantity,
                isBasicEnergy: record.isBasicEnergy,
                isAceSpec: record.isAceSpec,
                isRadiant: record.isRadiant,
                isBasicPokemon: record.isBasicPokemon,
                isRuleBox: record.isRuleBox,
                setKey: record.setKey,
                localId: record.localId,
                regulationMark: record.regulationMark,
                elementTypes: record.elementTypes,
                trainerType: record.trainerType,
                isEnergy: record.isEnergy,
                imageLowSrc: record.imageLowSrc,
                catalogCategory: record.catalogCategory,
                catalogSubtype: record.catalogSubtype,
                catalogStage: record.catalogStage,
                opCost: record.opCost,
                opPower: record.opPower,
                opCounter: record.opCounter
            )
            card.deck = deck
            modelContext.insert(card)
        }

        for record in library.valueSnapshots {
            modelContext.insert(
                CollectionValueSnapshot(
                    date: decodeDate(record.date),
                    totalGbp: record.totalGbp,
                    pokemonGbp: record.pokemonGbp,
                    onePieceGbp: record.onePieceGbp,
                    cardsGbp: record.cardsGbp,
                    sealedGbp: record.sealedGbp
                )
            )
        }

        for record in library.weeklyAverages {
            modelContext.insert(
                CollectionWeeklyAverage(
                    weekStart: decodeDate(record.periodStart),
                    totalGbp: record.totalGbp,
                    pokemonGbp: record.pokemonGbp,
                    onePieceGbp: record.onePieceGbp,
                    cardsGbp: record.cardsGbp,
                    sealedGbp: record.sealedGbp
                )
            )
        }

        for record in library.monthlyAverages {
            modelContext.insert(
                CollectionMonthlyAverage(
                    monthStart: decodeDate(record.periodStart),
                    totalGbp: record.totalGbp,
                    pokemonGbp: record.pokemonGbp,
                    onePieceGbp: record.onePieceGbp,
                    cardsGbp: record.cardsGbp,
                    sealedGbp: record.sealedGbp
                )
            )
        }

        try modelContext.save()
        try CollectionCostLotRepair.relinkActiveLots(in: modelContext)
        return restoredCards
    }

    /// Collapses duplicate rows in an R2 snapshot before restore or upload.
    private static func consolidateCollectionItemRecords(
        _ records: [UserLibraryBackup.CollectionItemRecord]
    ) -> (records: [UserLibraryBackup.CollectionItemRecord], exportIDRemap: [UUID: UUID]) {
        var canonicalByKey: [String: UserLibraryBackup.CollectionItemRecord] = [:]
        var exportIDRemap: [UUID: UUID] = [:]

        for record in records where record.quantity > 0 && !record.cardID.isEmpty {
            let key = collectionRecordStackKey(record)
            if let existing = canonicalByKey[key] {
                exportIDRemap[record.exportID] = existing.exportID
                canonicalByKey[key] = UserLibraryBackup.CollectionItemRecord(
                    exportID: existing.exportID,
                    cardID: existing.cardID,
                    variantKey: existing.variantKey,
                    dateAcquired: min(existing.dateAcquired, record.dateAcquired),
                    purchasePrice: existing.purchasePrice ?? record.purchasePrice,
                    quantity: existing.quantity + record.quantity,
                    notes: mergedNotes(existing.notes, record.notes),
                    itemKind: existing.itemKind,
                    gradingCompany: existing.gradingCompany,
                    grade: existing.grade,
                    certNumber: existing.certNumber,
                    sealedProductId: existing.sealedProductId,
                    sealedStatus: existing.sealedStatus
                )
            } else {
                canonicalByKey[key] = record
            }
        }

        return (Array(canonicalByKey.values), exportIDRemap)
    }

    private static func collectionRecordStackKey(_ record: UserLibraryBackup.CollectionItemRecord) -> String {
        [
            record.itemKind,
            record.cardID,
            record.variantKey.isEmpty ? "normal" : record.variantKey,
            record.gradingCompany ?? "",
            record.grade ?? "",
            record.certNumber ?? "",
            record.sealedProductId ?? "",
            record.sealedStatus ?? "",
        ].joined(separator: "\u{1F}")
    }

    private static func mergedNotes(_ lhs: String, _ rhs: String) -> String {
        let left = lhs.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = rhs.trimmingCharacters(in: .whitespacesAndNewlines)
        if left.isEmpty { return right }
        if right.isEmpty || left == right { return left }
        return "\(left)\n\(right)"
    }
}

// MARK: - Friend grid date helpers

extension UserLibraryBackup {
    private static let snapshotDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func parsedSnapshotDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        return snapshotDateFormatter.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }

    /// Newest acquisition date per card ID from a friend's cloud snapshot.
    func collectionDateByCardID() -> [String: Date] {
        var dates: [String: Date] = [:]
        if let items = library?.collectionItems {
            for item in items where !item.cardID.isEmpty {
                guard let parsed = Self.parsedSnapshotDate(item.dateAcquired) else { continue }
                dates[item.cardID] = max(dates[item.cardID] ?? .distantPast, parsed)
            }
        }
        return dates
    }

    /// Newest date-added per card ID from a friend's cloud snapshot.
    func wishlistDateByCardID() -> [String: Date] {
        var dates: [String: Date] = [:]
        if let items = library?.wishlistItems, !items.isEmpty {
            for item in items where !item.cardID.isEmpty {
                guard let parsed = Self.parsedSnapshotDate(item.dateAdded) else { continue }
                dates[item.cardID] = max(dates[item.cardID] ?? .distantPast, parsed)
            }
        } else {
            for entry in wishlist where !entry.cardID.isEmpty {
                guard let parsed = Self.parsedSnapshotDate(entry.dateAdded) else { continue }
                dates[entry.cardID] = max(dates[entry.cardID] ?? .distantPast, parsed)
            }
        }
        return dates
    }

    func collectionCardIDsByNewestAcquired() -> [String] {
        let dates = collectionDateByCardID()
        return orderedUniqueCardIDs(from: collection.map(\.cardID))
            .sorted { lhs, rhs in
                compareSnapshotDates(
                    dates[lhs],
                    dates[rhs],
                    lhs: lhs,
                    rhs: rhs
                )
            }
    }

    func wishlistCardIDsByNewestAdded() -> [String] {
        let dates = wishlistDateByCardID()
        let orderedIDs = orderedUniqueCardIDs(from: wishlist.map(\.cardID))
        return orderedIDs.sorted { lhs, rhs in
            compareSnapshotDates(dates[lhs], dates[rhs], lhs: lhs, rhs: rhs)
        }
    }

    private func orderedUniqueCardIDs(from rawIDs: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for id in rawIDs where !id.isEmpty {
            if seen.insert(id).inserted {
                ordered.append(id)
            }
        }
        return ordered
    }

    private func compareSnapshotDates(_ lhs: Date?, _ rhs: Date?, lhs lhsID: String, rhs rhsID: String) -> Bool {
        let lDate = lhs ?? .distantPast
        let rDate = rhs ?? .distantPast
        if lDate != rDate { return lDate > rDate }
        return lhsID.localizedStandardCompare(rhsID) == .orderedAscending
    }
}

enum FriendBrowsableCardSort {
    static func sortedCards(
        _ cards: [Card],
        sortBy: BrowseCardGridSortOption,
        priceByCardID: [String: Double],
        dateByCardID: [String: Date],
        stableOrderIDs: [String]
    ) -> [Card] {
        switch sortBy {
        case .acquiredDateNewest:
            let orderIndex = Dictionary(uniqueKeysWithValues: stableOrderIDs.enumerated().map { ($1, $0) })
            return cards.sorted { lhs, rhs in
                let lDate = dateByCardID[lhs.masterCardId] ?? .distantPast
                let rDate = dateByCardID[rhs.masterCardId] ?? .distantPast
                if lDate != rDate { return lDate > rDate }
                let lIndex = orderIndex[lhs.masterCardId] ?? Int.max
                let rIndex = orderIndex[rhs.masterCardId] ?? Int.max
                if lIndex != rIndex { return lIndex < rIndex }
                return lhs.masterCardId.localizedStandardCompare(rhs.masterCardId) == .orderedAscending
            }
        case .cardName:
            return cards.sorted {
                $0.cardName.localizedCaseInsensitiveCompare($1.cardName) == .orderedAscending
            }
        case .price:
            return cards.sorted {
                (priceByCardID[$0.masterCardId] ?? 0) > (priceByCardID[$1.masterCardId] ?? 0)
            }
        default:
            return cards
        }
    }
}
