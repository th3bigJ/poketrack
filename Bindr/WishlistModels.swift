import Foundation
import SwiftData

// MARK: - SwiftData (local)

/// Wishlist rows use `cardID` (= catalog `masterCardId`) plus `variantKey`.
/// Variant keys align with Scrydex / pricing JSON (e.g. `normal`, `holofoil`, `reverseHolofoil`).
/// Collection / ledger / P/L models live in ``CollectionLedgerModels``.

/// A card the user wants to acquire.
@Model
final class WishlistItem {
    /// Catalog `masterCardId`.
    var cardID: String = ""
    /// Print / price variant (Scrydex key).
    var variantKey: String = "normal"
    var dateAdded: Date = Date()
    var notes: String = ""
    var collectionName: String?

    init(cardID: String, variantKey: String = "normal", dateAdded: Date = Date(), notes: String = "", collectionName: String? = nil) {
        self.cardID = cardID
        self.variantKey = variantKey
        self.dateAdded = dateAdded
        self.notes = notes
        self.collectionName = collectionName
    }
}
