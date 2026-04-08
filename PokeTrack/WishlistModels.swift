import Foundation
import SwiftData

/// A card that the user wants to collect
@Model
final class WishlistItem {
    var cardID: String
    var dateAdded: Date
    var notes: String
    var collectionName: String?
    
    init(cardID: String, dateAdded: Date = Date(), notes: String = "", collectionName: String? = nil) {
        self.cardID = cardID
        self.dateAdded = dateAdded
        self.notes = notes
        self.collectionName = collectionName
    }
}

/// A card in the user's collection (for future use)
@Model
final class CollectionItem {
    var cardID: String
    var dateAcquired: Date
    var purchasePrice: Double?
    var condition: String
    var quantity: Int
    var notes: String
    
    @Relationship(deleteRule: .cascade, inverse: \TransactionRecord.collectionItem)
    var transactions: [TransactionRecord] = []
    
    init(
        cardID: String,
        dateAcquired: Date = Date(),
        purchasePrice: Double? = nil,
        condition: String = "Near Mint",
        quantity: Int = 1,
        notes: String = ""
    ) {
        self.cardID = cardID
        self.dateAcquired = dateAcquired
        self.purchasePrice = purchasePrice
        self.condition = condition
        self.quantity = quantity
        self.notes = notes
    }
}

/// Transaction log (for future use)
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
