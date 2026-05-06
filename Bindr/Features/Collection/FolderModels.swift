import Foundation
import SwiftData

@Model
final class CardFolderItem {
    var cardID: String = ""
    var variantKey: String = "normal"
    var quantity: Int = 1
    var dateAdded: Date = Date()
    var folder: CardFolder?

    init(cardID: String, variantKey: String = "normal", quantity: Int = 1) {
        self.cardID = cardID
        self.variantKey = variantKey
        self.quantity = quantity
        self.dateAdded = Date()
    }
}

@Model
final class CardFolder {
    var id: UUID = UUID()
    var title: String = ""
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade)
    var items: [CardFolderItem]?

    init(title: String) {
        self.id = UUID()
        self.title = title
        self.createdAt = Date()
    }
}
