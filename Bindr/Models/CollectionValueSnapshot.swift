import Foundation
import SwiftData

/// One locked-in daily value record per calendar day per brand.
/// Today's row is never written here — it is computed live from current prices.
/// Synced to iCloud via the same CloudKit container as the rest of user data.
@Model
final class CollectionValueSnapshot {
    var date: Date = Date.distantPast
    var totalGbp: Double = 0.0
    var pokemonGbp: Double = 0.0
    var onePieceGbp: Double = 0.0
    var lorcanaGbp: Double = 0.0

    init(date: Date, totalGbp: Double, pokemonGbp: Double, onePieceGbp: Double, lorcanaGbp: Double) {
        self.date = date
        self.totalGbp = totalGbp
        self.pokemonGbp = pokemonGbp
        self.onePieceGbp = onePieceGbp
        self.lorcanaGbp = lorcanaGbp
    }
}
