import Foundation
import SwiftData

/// Row counts for every SwiftData library type stored on this device.
struct LibraryInventoryCounts: Equatable {
    var collectionCards: Int = 0
    var wishlistItems: Int = 0
    var binders: Int = 0
    var decks: Int = 0
    var ledgerLines: Int = 0
    var dailyValueSnapshots: Int = 0
    var weeklyAverages: Int = 0
    var monthlyAverages: Int = 0

    var isEmpty: Bool {
        collectionCards == 0
            && wishlistItems == 0
            && binders == 0
            && decks == 0
            && ledgerLines == 0
            && dailyValueSnapshots == 0
            && weeklyAverages == 0
            && monthlyAverages == 0
    }

    static func load(from modelContext: ModelContext) -> LibraryInventoryCounts {
        LibraryInventoryCounts(
            collectionCards: modelContext.collectionTotalCardQuantity(),
            wishlistItems: (try? modelContext.fetchCount(FetchDescriptor<WishlistItem>())) ?? 0,
            binders: (try? modelContext.fetchCount(FetchDescriptor<Binder>())) ?? 0,
            decks: (try? modelContext.fetchCount(FetchDescriptor<Deck>())) ?? 0,
            ledgerLines: (try? modelContext.fetchCount(FetchDescriptor<LedgerLine>())) ?? 0,
            dailyValueSnapshots: (try? modelContext.fetchCount(FetchDescriptor<CollectionValueSnapshot>())) ?? 0,
            weeklyAverages: (try? modelContext.fetchCount(FetchDescriptor<CollectionWeeklyAverage>())) ?? 0,
            monthlyAverages: (try? modelContext.fetchCount(FetchDescriptor<CollectionMonthlyAverage>())) ?? 0
        )
    }
}
