import Foundation
import SwiftData

@Model
final class SealedCollectionItem {
    var id: UUID = UUID()
    var pokedataProductId: Int = 0
    var productName: String = ""
    var productType: String = ""
    var quantity: Int = 1
    var sealedState: String = "sealed"
    var pricePaid: Double?
    var purchaseDate: Date?
    var notes: String?
    var addedAt: Date = Date()

    init(
        pokedataProductId: Int,
        productName: String,
        productType: String,
        quantity: Int = 1,
        sealedState: String = "sealed",
        addedAt: Date = .now
    ) {
        self.id = UUID()
        self.pokedataProductId = pokedataProductId
        self.productName = productName
        self.productType = productType
        self.quantity = quantity
        self.sealedState = sealedState
        self.addedAt = addedAt
    }
}
