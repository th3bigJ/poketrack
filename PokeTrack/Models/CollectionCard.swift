import Foundation
import SwiftData

@Model
final class CollectionCard {
    var id: UUID = UUID()
    var masterCardId: String = ""
    var setCode: String = ""
    var quantity: Int = 1
    var printing: String = "Standard"
    var language: String = "English"
    var conditionId: String = "near-mint"
    var purchaseType: String?
    var pricePaid: Double?
    var purchaseDate: Date?
    var unlistedPrice: Double?
    var gradingCompany: String?
    var gradeValue: String?
    var gradedImageUrl: String?
    var gradedSerial: String?
    var addedAt: Date = Date()

    init(
        masterCardId: String,
        setCode: String,
        quantity: Int = 1,
        printing: String = "Standard",
        language: String = "English",
        conditionId: String = CardCondition.nearMint.rawValue,
        addedAt: Date = .now
    ) {
        self.id = UUID()
        self.masterCardId = masterCardId
        self.setCode = setCode
        self.quantity = quantity
        self.printing = printing
        self.language = language
        self.conditionId = conditionId
        self.addedAt = addedAt
    }
}
