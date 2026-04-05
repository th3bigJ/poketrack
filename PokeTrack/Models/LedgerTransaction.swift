import Foundation
import SwiftData

/// User financial / trade log (not StoreKit).
@Model
final class LedgerTransaction {
    var id: UUID = UUID()
    var direction: String = ""
    var transactionDescription: String = ""
    var productTypeId: String?
    var quantity: Int = 1
    var unitPrice: Double?
    var totalPrice: Double?
    var notes: String?
    var date: Date = Date()
    var sourceReference: String?
    var addedAt: Date = Date()

    init(
        direction: String,
        transactionDescription: String,
        quantity: Int = 1,
        date: Date = .now,
        addedAt: Date = .now
    ) {
        self.id = UUID()
        self.direction = direction
        self.transactionDescription = transactionDescription
        self.quantity = quantity
        self.date = date
        self.addedAt = addedAt
    }
}
