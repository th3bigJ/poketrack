import Foundation
import SwiftData

@Model
final class CardFolderItem {
    var cardID: String = ""
    var variantKey: String = "normal"
    var dateAdded: Date = Date()
    var folder: CardFolder?

    init(cardID: String, variantKey: String = "normal") {
        self.cardID = cardID
        self.variantKey = variantKey
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
