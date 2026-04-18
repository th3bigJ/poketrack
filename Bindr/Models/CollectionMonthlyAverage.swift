import Foundation
import SwiftData

/// Average collection value for a completed calendar month.
/// `monthStart` is the 1st of that month at midnight local time.
@Model
final class CollectionMonthlyAverage {
    var monthStart: Date = Date.distantPast
    var totalGbp: Double = 0.0
    var pokemonGbp: Double = 0.0
    var onePieceGbp: Double = 0.0
    var lorcanaGbp: Double = 0.0

    init(monthStart: Date, totalGbp: Double, pokemonGbp: Double, onePieceGbp: Double, lorcanaGbp: Double) {
        self.monthStart = monthStart
        self.totalGbp = totalGbp
        self.pokemonGbp = pokemonGbp
        self.onePieceGbp = onePieceGbp
        self.lorcanaGbp = lorcanaGbp
    }
}
