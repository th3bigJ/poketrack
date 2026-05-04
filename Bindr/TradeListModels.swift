import Foundation
import SwiftData

/// A card from the user's collection that they are willing to trade away.
/// Items are always a subset of CollectionItems — only collection cards can be added.
@Model
final class TradeListItem {
    /// Catalog `masterCardId`.
    var cardID: String = ""
    /// Print / price variant (Scrydex key).
    var variantKey: String = "normal"
    var quantity: Int = 1
    var dateAdded: Date = Date()
    var notes: String = ""

    init(cardID: String, variantKey: String = "normal", quantity: Int = 1, dateAdded: Date = Date(), notes: String = "") {
        self.cardID = cardID
        self.variantKey = variantKey
        self.quantity = max(1, quantity)
        self.dateAdded = dateAdded
        self.notes = notes
    }
}
