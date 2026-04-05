import Foundation
import SwiftData

@Model
final class PortfolioSnapshot {
    var id: UUID = UUID()
    var date: Date = Date()
    var totalValueGBP: Double = 0
    var cardCount: Int = 0
    var sealedValueGBP: Double = 0

    init(
        date: Date,
        totalValueGBP: Double,
        cardCount: Int,
        sealedValueGBP: Double = 0
    ) {
        self.id = UUID()
        self.date = date
        self.totalValueGBP = totalValueGBP
        self.cardCount = cardCount
        self.sealedValueGBP = sealedValueGBP
    }
}
