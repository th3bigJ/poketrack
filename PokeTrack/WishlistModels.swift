import Foundation
import SwiftData

// MARK: - SwiftData (local)

/// Wishlist and collection rows use `cardID` (= catalog `masterCardId`) plus `variantKey`.
/// Variant keys align with Scrydex / pricing JSON (e.g. `normal`, `holofoil`, `reverseHolofoil`).
/// Physical **condition** (NM/LP/etc.) is intentionally not tracked—revisit product design before adding.

/// A card the user wants to acquire.
@Model
final class WishlistItem {
    /// Catalog `masterCardId`.
    var cardID: String
    /// Print / price variant (Scrydex key).
    var variantKey: String
    var dateAdded: Date
    var notes: String
    var collectionName: String?

    init(cardID: String, variantKey: String = "normal", dateAdded: Date = Date(), notes: String = "", collectionName: String? = nil) {
        self.cardID = cardID
        self.variantKey = variantKey
        self.dateAdded = dateAdded
        self.notes = notes
        self.collectionName = collectionName
    }
}

/// An owned copy (or quantity) of a card in the user’s collection.
@Model
final class CollectionItem {
    /// Catalog `masterCardId`.
    var cardID: String
    /// Print / price variant (Scrydex key); distinguishes holo vs non-holo, etc.
    var variantKey: String
    var dateAcquired: Date
    var purchasePrice: Double?
    var quantity: Int
    var notes: String

    @Relationship(deleteRule: .cascade, inverse: \TransactionRecord.collectionItem)
    var transactions: [TransactionRecord] = []

    init(
        cardID: String,
        variantKey: String = "normal",
        dateAcquired: Date = Date(),
        purchasePrice: Double? = nil,
        quantity: Int = 1,
        notes: String = ""
    ) {
        self.cardID = cardID
        self.variantKey = variantKey
        self.dateAcquired = dateAcquired
        self.purchasePrice = purchasePrice
        self.quantity = quantity
        self.notes = notes
    }
}

/// Transaction log; variant for a line is usually carried on `collectionItem` when linked.
@Model
final class TransactionRecord {
    var id: UUID
    var date: Date
    var type: String
    var amountUSD: Double
    var notes: String
    var collectionItem: CollectionItem?

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        type: String,
        amountUSD: Double,
        notes: String = ""
    ) {
        self.id = id
        self.date = date
        self.type = type
        self.amountUSD = amountUSD
        self.notes = notes
    }
}
