import Foundation
import SwiftData

// MARK: - Enums (stored as String on @Model types)

/// Buy / sell / trade / gift direction for ledger lines.
enum LedgerDirection: String, Codable, CaseIterable, Sendable {
    case bought
    /// Pulled from opened sealed product (pack, box, ETB).
    case packed
    case sold
    case tradedIn
    case tradedOut
    case giftedIn
    case giftedOut
    /// Manual stack increase (new ``CostLot`` at weighted-average unit cost).
    case adjustmentIn
    /// Manual stack decrease (FIFO consumption of ``CostLot`` layers).
    case adjustmentOut
}

/// How the user acquired the card when adding to collection (maps to ``LedgerDirection``).
/// Order is user-facing (e.g. segmented pickers): packed first as the common default.
enum CollectionAcquisitionKind: String, CaseIterable, Sendable {
    case packed
    case bought
    case trade
    case gifted

    var title: String {
        switch self {
        case .packed: return "Packed"
        case .bought: return "Bought"
        case .trade: return "Trade"
        case .gifted: return "Gifted"
        }
    }

    var ledgerDirection: LedgerDirection {
        switch self {
        case .packed: return .packed
        case .bought: return .bought
        case .trade: return .tradedIn
        case .gifted: return .giftedIn
        }
    }
}

/// What the line refers to (card, slab, sealed, etc.).
enum ProductKind: String, Codable, CaseIterable, Sendable {
    case singleCard
    case gradedItem
    case sealedProduct
    case boosterPack
    case etb
    case other
}

/// Sealed product state when relevant.
enum SealedInventoryStatus: String, Codable, CaseIterable, Sendable {
    case sealed
    case opened
    case notApplicable
}

// MARK: - Collection (current holdings)

/// One row = something the user owns now (raw card stack, graded slab, sealed product, …).
@Model
final class CollectionItem {
    /// Same as catalog `masterCardId` when `itemKind` is card-like.
    var cardID: String = ""
    var variantKey: String = "normal"
    var dateAcquired: Date = Date()
    /// Optional cached last purchase (lots hold authoritative cost).
    var purchasePrice: Double?
    var quantity: Int = 1
    var notes: String = ""

    /// e.g. `singleCard`, `gradedItem`, `sealedProduct`
    var itemKind: String = ProductKind.singleCard.rawValue

    var gradingCompany: String?
    var grade: String?
    var certNumber: String?

    var sealedProductId: String?
    var sealedStatus: String?

    @Relationship(deleteRule: .cascade, inverse: \CostLot.collectionItem)
    var costLots: [CostLot]?

    init(
        cardID: String,
        variantKey: String = "normal",
        dateAcquired: Date = Date(),
        purchasePrice: Double? = nil,
        quantity: Int = 1,
        notes: String = "",
        itemKind: String = ProductKind.singleCard.rawValue,
        gradingCompany: String? = nil,
        grade: String? = nil,
        certNumber: String? = nil,
        sealedProductId: String? = nil,
        sealedStatus: String? = nil
    ) {
        self.cardID = cardID
        self.variantKey = variantKey
        self.dateAcquired = dateAcquired
        self.purchasePrice = purchasePrice
        self.quantity = quantity
        self.notes = notes
        self.itemKind = itemKind
        self.gradingCompany = gradingCompany
        self.grade = grade
        self.certNumber = certNumber
        self.sealedProductId = sealedProductId
        self.sealedStatus = sealedStatus
    }
}

// MARK: - Ledger (immutable history lines)

/// One row = one ledger line (buy, sell, trade leg, gift, …).
@Model
final class LedgerLine {
    var id: UUID = UUID()
    var occurredAt: Date = Date()

    var direction: String = LedgerDirection.bought.rawValue
    var productKind: String = ProductKind.singleCard.rawValue
    /// User-visible description (not `description` — avoids NSObject collision).
    var lineDescription: String = ""

    var cardID: String?
    var variantKey: String?
    var sealedProductId: String?

    var gradingCompany: String?
    var grade: String?
    var certNumber: String?

    var quantity: Int = 1
    var unitPrice: Double?
    var currencyCode: String = "USD"
    var feesAmount: Double?

    var sealedStatus: String?

    var counterparty: String?
    var channel: String?
    var externalRef: String?
    var transactionGroupId: UUID?

    @Relationship(deleteRule: .cascade, inverse: \CostLot.sourceLedgerLine)
    var createdCostLots: [CostLot]?

    @Relationship(deleteRule: .cascade, inverse: \SaleAllocation.saleLedgerLine)
    var saleAllocations: [SaleAllocation]?

    init(
        id: UUID = UUID(),
        occurredAt: Date = Date(),
        direction: String,
        productKind: String,
        lineDescription: String = "",
        cardID: String? = nil,
        variantKey: String? = nil,
        sealedProductId: String? = nil,
        gradingCompany: String? = nil,
        grade: String? = nil,
        certNumber: String? = nil,
        quantity: Int = 1,
        unitPrice: Double? = nil,
        currencyCode: String = "USD",
        feesAmount: Double? = nil,
        sealedStatus: String? = nil,
        counterparty: String? = nil,
        channel: String? = nil,
        externalRef: String? = nil,
        transactionGroupId: UUID? = nil
    ) {
        self.id = id
        self.occurredAt = occurredAt
        self.direction = direction
        self.productKind = productKind
        self.lineDescription = lineDescription
        self.cardID = cardID
        self.variantKey = variantKey
        self.sealedProductId = sealedProductId
        self.gradingCompany = gradingCompany
        self.grade = grade
        self.certNumber = certNumber
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.currencyCode = currencyCode
        self.feesAmount = feesAmount
        self.sealedStatus = sealedStatus
        self.counterparty = counterparty
        self.channel = channel
        self.externalRef = externalRef
        self.transactionGroupId = transactionGroupId
    }
}

// MARK: - Cost lots (basis for P/L)

/// One layer of cost from an inbound `LedgerLine` (usually a purchase), consumed by sales via `SaleAllocation`.
@Model
final class CostLot {
    var id: UUID = UUID()
    var quantityRemaining: Int = 0
    var unitCost: Double = 0
    var currencyCode: String = "USD"
    var createdAt: Date = Date()

    /// Inverse: ``CollectionItem/costLots`` (no `@Relationship` here — avoids circular macro expansion).
    var collectionItem: CollectionItem?

    /// Inverse: ``LedgerLine/createdCostLots``.
    var sourceLedgerLine: LedgerLine?

    @Relationship(deleteRule: .cascade, inverse: \SaleAllocation.costLot)
    var saleAllocations: [SaleAllocation]?

    init(
        id: UUID = UUID(),
        quantityRemaining: Int,
        unitCost: Double,
        currencyCode: String,
        createdAt: Date = Date(),
        collectionItem: CollectionItem? = nil,
        sourceLedgerLine: LedgerLine? = nil
    ) {
        self.id = id
        self.quantityRemaining = quantityRemaining
        self.unitCost = unitCost
        self.currencyCode = currencyCode
        self.createdAt = createdAt
        self.collectionItem = collectionItem
        self.sourceLedgerLine = sourceLedgerLine
    }
}

// MARK: - Sale allocations (link sells to cost)

/// Connects a **sale** `LedgerLine` to `CostLot`(s) for realized P/L.
@Model
final class SaleAllocation {
    var id: UUID = UUID()
    var quantity: Int = 0
    var allocatedCost: Double = 0

    /// Inverse: ``LedgerLine/saleAllocations``.
    var saleLedgerLine: LedgerLine?

    /// Inverse: ``CostLot/saleAllocations``.
    var costLot: CostLot?

    init(
        id: UUID = UUID(),
        quantity: Int,
        allocatedCost: Double,
        saleLedgerLine: LedgerLine? = nil,
        costLot: CostLot? = nil
    ) {
        self.id = id
        self.quantity = quantity
        self.allocatedCost = allocatedCost
        self.saleLedgerLine = saleLedgerLine
        self.costLot = costLot
    }
}
