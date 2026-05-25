import Foundation
import SwiftData

/// Average collection value for a completed ISO week (Monday–Sunday).
/// `weekStart` is the Monday of that week at midnight local time.
@Model
final class CollectionWeeklyAverage {
    var weekStart: Date = Date.distantPast
    var totalGbp: Double = 0.0
    var pokemonGbp: Double = 0.0
    var onePieceGbp: Double = 0.0
    var cardsGbp: Double = 0.0
    var sealedGbp: Double = 0.0

    init(
        weekStart: Date,
        totalGbp: Double,
        pokemonGbp: Double,
        onePieceGbp: Double,
        cardsGbp: Double = 0.0,
        sealedGbp: Double = 0.0
    ) {
        self.weekStart = weekStart
        self.totalGbp = totalGbp
        self.pokemonGbp = pokemonGbp
        self.onePieceGbp = onePieceGbp
        self.cardsGbp = cardsGbp
        self.sealedGbp = sealedGbp
    }
}
