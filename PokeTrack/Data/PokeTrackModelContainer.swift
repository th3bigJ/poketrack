import SwiftData
import SwiftUI

enum PokeTrackModelContainer {
    /// Local SQLite only — works with **Personal Team** signing (free Apple ID).
    /// When you enroll in the **Apple Developer Program**, add iCloud + CloudKit back in entitlements and switch to `cloudKitDatabase: .automatic` for sync.
    static func makeProduction() throws -> ModelContainer {
        let schema = Schema([
            CollectionCard.self,
            WishlistItem.self,
            SealedCollectionItem.self,
            LedgerTransaction.self,
            PortfolioSnapshot.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try ModelContainer(for: schema, configurations: [config])
    }

    static func makePreview() -> ModelContainer {
        let schema = Schema([
            CollectionCard.self,
            WishlistItem.self,
            SealedCollectionItem.self,
            LedgerTransaction.self,
            PortfolioSnapshot.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }
}
