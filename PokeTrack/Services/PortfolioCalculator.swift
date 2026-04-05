import Foundation

enum PortfolioCalculator {
    static func calculatePortfolioValueGBP(
        collectionCards: [CollectionCard],
        cardLookup: (String, String) -> Card?,
        pricing: (Card, String) async -> Double?
    ) async -> Double {
        var total = 0.0
        for row in collectionCards {
            guard let card = cardLookup(row.masterCardId, row.setCode) else { continue }
            let qty = Double(row.quantity)
            if let manual = row.unlistedPrice {
                total += manual * qty
                continue
            }
            if let p = await pricing(card, row.printing) {
                total += p * qty
            }
        }
        return total
    }
}
