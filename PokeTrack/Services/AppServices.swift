import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class AppServices {
    let cardData = CardDataService()
    let pricing = PricingService()
    let priceDisplay = PriceDisplaySettings()
    let store = StoreKitService()
    let cloudSettings = CloudSettingsService()
    
    // Wishlist service - initialized after model context is available
    private(set) var wishlist: WishlistService?

    /// Collection + ledger (SwiftData) — initialized with `ModelContext`.
    private(set) var collectionLedger: CollectionLedgerService?

    private(set) var isReady = false

    func bootstrap() async {
        await CatalogSyncCoordinator.shared.syncAllIfNeeded()
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.pricing.refreshFXRate() }
            group.addTask { await self.cardData.loadSets() }
            group.addTask { await self.cardData.loadNationalDexPokemon() }
            group.addTask { await self.store.loadProducts() }
        }
        await store.checkEntitlements()
        isReady = true
    }
    
    /// Call this from your root view with the model context
    func setupWishlist(modelContext: ModelContext) {
        guard wishlist == nil else { return }
        wishlist = WishlistService(modelContext: modelContext, store: store)
    }

    func setupCollectionLedger(modelContext: ModelContext) {
        guard collectionLedger == nil else { return }
        collectionLedger = CollectionLedgerService(modelContext: modelContext)
    }
}
