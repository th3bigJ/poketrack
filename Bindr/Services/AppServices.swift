import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class AppServices {
    let brandSettings: BrandSettings
    let cardData: CardDataService
    let pricing = PricingService()
    let cloudSettings: CloudSettingsService
    let priceDisplay: PriceDisplaySettings
    let browseGridOptions: BrowseGridOptionsSettings
    let store = StoreKitService()
    
    // Wishlist service - initialized after model context is available
    private(set) var wishlist: WishlistService?

    /// Collection + ledger (SwiftData) — initialized with `ModelContext`.
    private(set) var collectionLedger: CollectionLedgerService?

    private(set) var isReady = false
    private(set) var isBootstrapping = false
    private(set) var bootstrapMessage = "Updating card data, please wait."
    private(set) var bootstrapStatus = "Preparing downloads…"
    private(set) var bootstrapProgress: Double = 0
    private(set) var bootstrapDownloadedBytes: Int64 = 0
    private(set) var bootstrapEstimatedTotalBytes: Int64 = 0

    init() {
        let cloudSettings = CloudSettingsService()
        self.cloudSettings = cloudSettings
        self.priceDisplay = PriceDisplaySettings(cloudSettings: cloudSettings)
        self.browseGridOptions = BrowseGridOptionsSettings(cloudSettings: cloudSettings)
        let brandSettings = BrandSettings()
        self.brandSettings = brandSettings
        self.cardData = CardDataService(brandSettings: brandSettings)
    }

    func bootstrap() async {
        guard !isReady, !isBootstrapping else { return }
        isBootstrapping = true
        bootstrapMessage = "Updating card data, please wait."
        bootstrapStatus = "Preparing downloads…"
        bootstrapProgress = 0
        bootstrapDownloadedBytes = 0
        bootstrapEstimatedTotalBytes = 0

        await CatalogSyncCoordinator.shared.syncAllIfNeeded { [weak self] snapshot in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.bootstrapStatus = snapshot.status
                self.bootstrapDownloadedBytes = snapshot.downloadedBytes
                self.bootstrapEstimatedTotalBytes = max(snapshot.estimatedTotalBytes, snapshot.downloadedBytes)
                self.bootstrapProgress = min(max(snapshot.fractionCompleted * 0.85, self.bootstrapProgress), 0.85)
            }
        }

        bootstrapStatus = "Refreshing catalog…"
        await cardData.loadSets()
        bootstrapProgress = max(bootstrapProgress, 0.90)

        if brandSettings.enabledBrands.contains(.pokemon) {
            bootstrapStatus = "Loading Pokemon index…"
            await cardData.loadNationalDexPokemon()
        } else {
            cardData.clearNationalDexForDisabledPokemon()
        }
        bootstrapProgress = max(bootstrapProgress, 0.95)

        bootstrapStatus = "Checking purchases…"
        await pricing.refreshFXRate()
        await store.loadProducts()
        await store.checkEntitlements()
        bootstrapProgress = 1
        bootstrapStatus = "Card data is ready."
        isReady = true
        isBootstrapping = false
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
