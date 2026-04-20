import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class AppServices {
    let brandsManifest = BrandsManifestService()
    let brandSettings: BrandSettings
    let cardData: CardDataService
    let pricing = PricingService()
    let cloudSettings: CloudSettingsService
    let priceDisplay: PriceDisplaySettings
    let browseGridOptions: BrowseGridOptionsSettings
    let store = StoreKitService()
    let socialAuth: SocialAuthService
    let socialProfile: SocialProfileService
    let socialFriend: SocialFriendService
    let socialShare: SocialShareService
    let socialFeed: SocialFeedService
    let socialPush: SocialPushService
    
    // Wishlist service - initialized after model context is available
    private(set) var wishlist: WishlistService?

    /// Collection + ledger (SwiftData) — initialized with `ModelContext`.
    private(set) var collectionLedger: CollectionLedgerService?

    /// Daily value snapshots (SwiftData) — initialized with `ModelContext`.
    private(set) var collectionValue: CollectionValueService?

    private(set) var isReady = false
    private(set) var isBootstrapping = false
    /// Until `true`, the root UI should not mount the main tab shell (Browse, etc.) so the cold launch catalog pipeline does not race the same SQLite + network work on the main actor.
    private(set) var isLaunchCatalogPipelineComplete = false
    /// Set in `init` when the user already completed the one-time blocking bootstrap; consumed by the first `.task` on the main UI to refresh catalogs in the background.
    private(set) var shouldRunBackgroundCatalogRefreshOnLaunch = false
    private var isBackgroundCatalogRefreshInFlight = false
    /// Set when a catalog pipeline run just finished; ``BrowseView`` consumes once to skip duplicate ``CardDataService/reloadAfterBrandChange()`` (same `loadSets` + search index work).
    private var pendingLightBrowseTabEntry = false
    /// When true, ``RootView`` shows the full ``LoadingScreen`` with byte counts; otherwise a simple indeterminate busy state until sync actually transfers data.
    private(set) var bootstrapShowsDownloadProgressUI = false
    private(set) var bootstrapMessage = "Updating card data, please wait."
    private(set) var bootstrapStatus = "Preparing downloads…"
    private(set) var bootstrapProgress: Double = 0
    private(set) var bootstrapDownloadedBytes: Int64 = 0
    private(set) var bootstrapEstimatedTotalBytes: Int64 = 0

    /// Full-screen catalog download (Account toggles on) — mirrors bootstrap progress but does not block app launch.
    private(set) var isCatalogDownloadInProgress = false
    /// Heavy download UI only after bytes are observed (warm re-launch may stay on a light spinner).
    private(set) var catalogDownloadShowsByteProgressUI = false
    private(set) var catalogDownloadMessage = "Downloading catalog data…"
    private(set) var catalogDownloadStatus = ""
    private(set) var catalogDownloadProgress: Double = 0
    private(set) var catalogDownloadDownloadedBytes: Int64 = 0
    private(set) var catalogDownloadEstimatedTotalBytes: Int64 = 0

    init() {
        let socialAuth = SocialAuthService()
        self.socialAuth = socialAuth
        self.socialProfile = SocialProfileService(authService: socialAuth)
        self.socialFriend = SocialFriendService(authService: socialAuth, storeService: store)
        self.socialFeed = SocialFeedService(authService: socialAuth)
        self.socialPush = SocialPushService(authService: socialAuth, profileService: socialProfile)
        let cloudSettings = CloudSettingsService()
        self.cloudSettings = cloudSettings
        self.priceDisplay = PriceDisplaySettings(cloudSettings: cloudSettings)
        self.browseGridOptions = BrowseGridOptionsSettings(cloudSettings: cloudSettings)
        let brandSettings = BrandSettings()
        self.brandSettings = brandSettings
        self.cardData = CardDataService(brandSettings: brandSettings)
        self.socialShare = SocialShareService(
            authService: socialAuth,
            storeService: store,
            cardDataService: cardData,
            pricingService: pricing
        )
        if brandSettings.hasCompletedBrandOnboarding && brandSettings.hasCompletedInitialAppBootstrap {
            isReady = true
            shouldRunBackgroundCatalogRefreshOnLaunch = true
            isLaunchCatalogPipelineComplete = false
        }
        Task {
            await socialAuth.restoreSession()
        }
    }

    /// Browse calls this once after launch pipeline: if `true`, skip heavy reload (catalog + search index already warmed).
    func consumeLightBrowseTabEntryIfNeeded() -> Bool {
        guard pendingLightBrowseTabEntry else { return false }
        pendingLightBrowseTabEntry = false
        return true
    }

    /// One-time blocking gate for brand-new users (after onboarding). Later launches use ``bootstrapCatalogInBackgroundIfNeeded()`` from the root view.
    func bootstrap() async {
        guard !isReady, !isBootstrapping else { return }
        isBootstrapping = true
        defer { isBootstrapping = false }
        await runStartupCatalogPipeline(updateBootstrapProgressUI: true)
        brandSettings.markInitialAppBootstrapCompleted()
        pendingLightBrowseTabEntry = true
        isLaunchCatalogPipelineComplete = true
        isReady = true
    }

    /// Cold-launch refresh for returning users. Finishes before ``isLaunchCatalogPipelineComplete`` becomes `true` so the tab shell does not mount until catalog work is done.
    func bootstrapCatalogInBackgroundIfNeeded() async {
        guard shouldRunBackgroundCatalogRefreshOnLaunch else {
            isLaunchCatalogPipelineComplete = true
            return
        }
        shouldRunBackgroundCatalogRefreshOnLaunch = false
        await bootstrapCatalogInBackground()
        isLaunchCatalogPipelineComplete = true
    }

    private func bootstrapCatalogInBackground() async {
        guard !isBootstrapping else { return }
        guard !isBackgroundCatalogRefreshInFlight else { return }
        isBackgroundCatalogRefreshInFlight = true
        defer { isBackgroundCatalogRefreshInFlight = false }
        await runStartupCatalogPipeline(updateBootstrapProgressUI: false)
        pendingLightBrowseTabEntry = true
    }

    private func runStartupCatalogPipeline(updateBootstrapProgressUI: Bool) async {
        await brandsManifest.refresh()
        if updateBootstrapProgressUI {
            bootstrapShowsDownloadProgressUI = false
            let enabled = brandSettings.enabledBrands
            if enabled.count == 1, enabled.contains(.onePiece) {
                bootstrapMessage = "Updating ONE PIECE card data…"
            } else if enabled.count == 1, enabled.contains(.pokemon) {
                bootstrapMessage = "Updating Pokémon card data…"
            } else {
                bootstrapMessage = "Updating card data, please wait."
            }
            bootstrapStatus = "Preparing downloads…"
            bootstrapProgress = 0
            bootstrapDownloadedBytes = 0
            bootstrapEstimatedTotalBytes = 0
            await Task.yield()
            await Task.yield()
        }

        let weightSync: Double = 0.62
        let weightLoadSets: Double = 0.18
        let weightDex: Double = brandSettings.enabledBrands.contains(.pokemon) ? 0.12 : 0
        let weightOnePieceBrowse: Double = brandSettings.enabledBrands.contains(.onePiece) ? 0.06 : 0
        let weightStore: Double = max(0.04, 1.0 - weightSync - weightLoadSets - weightDex - weightOnePieceBrowse)

        let progressHandler: (@MainActor @Sendable (CatalogSyncProgressSnapshot) -> Void)?
        if updateBootstrapProgressUI {
            progressHandler = { [weak self] snapshot in
                guard let self else { return }
                if snapshot.downloadedBytes > 0 {
                    self.bootstrapShowsDownloadProgressUI = true
                }
                self.bootstrapStatus = snapshot.status
                self.bootstrapDownloadedBytes = snapshot.downloadedBytes
                self.bootstrapEstimatedTotalBytes = max(snapshot.estimatedTotalBytes, snapshot.downloadedBytes)
                self.bootstrapProgress = min(max(snapshot.fractionCompleted * weightSync, 0), weightSync)
            }
        } else {
            progressHandler = nil
        }
        await CatalogSyncCoordinator.shared.syncAllIfNeeded(
            enabledBrands: brandSettings.enabledBrands,
            progressHandler: progressHandler
        )

        if updateBootstrapProgressUI {
            bootstrapProgress = weightSync
            bootstrapStatus = "Refreshing catalog…"
        }
        await cardData.loadSets(preferSyncedCatalog: true)
        if updateBootstrapProgressUI {
            bootstrapProgress = weightSync + weightLoadSets
        }

        if brandSettings.enabledBrands.contains(.pokemon) {
            if updateBootstrapProgressUI {
                bootstrapStatus = "Loading Pokemon index…"
            }
            await cardData.loadNationalDexPokemon()
        } else {
            cardData.clearNationalDexForDisabledPokemon()
        }
        if updateBootstrapProgressUI {
            bootstrapProgress = weightSync + weightLoadSets + weightDex
        }

        if brandSettings.enabledBrands.contains(.onePiece) {
            if updateBootstrapProgressUI {
                bootstrapStatus = "Loading ONE PIECE browse lists…"
            }
            await cardData.loadOnePieceBrowseMetadata()
        } else {
            cardData.clearOnePieceBrowseMetadata()
        }
        if updateBootstrapProgressUI {
            bootstrapProgress = weightSync + weightLoadSets + weightDex + weightOnePieceBrowse
        }

        if updateBootstrapProgressUI {
            bootstrapStatus = "Checking purchases…"
        }
        await pricing.refreshFXRate()
        await store.loadProducts()
        await store.checkEntitlements()
        if updateBootstrapProgressUI {
            bootstrapProgress = weightSync + weightLoadSets + weightDex + weightOnePieceBrowse + weightStore
            bootstrapStatus = "Card data is ready."
        }

    }

    /// Runs after the user turns **on** a catalog in Account: network sync + reload browse data, with UI progress (`RootView` overlay).
    func performCatalogSyncAfterEnablingBrands() async {
        guard !isCatalogDownloadInProgress else { return }
        pricing.clearSetPricingMemoryCache()
        isCatalogDownloadInProgress = true
        catalogDownloadShowsByteProgressUI = false
        catalogDownloadMessage = "Downloading catalog data…"
        catalogDownloadStatus = "Preparing downloads…"
        catalogDownloadProgress = 0
        catalogDownloadDownloadedBytes = 0
        catalogDownloadEstimatedTotalBytes = 0

        // Let the overlay paint 0% before heavy sync work runs in the same frame.
        await Task.yield()

        /// Network import is only part of the story; reserve the tail for SQLite + dex so the bar is not stuck at 100% early.
        let syncPhaseWeight = 0.82

        await CatalogSyncCoordinator.shared.syncAllIfNeeded(enabledBrands: brandSettings.enabledBrands) { [weak self] snapshot in
            guard let self else { return }
            if snapshot.downloadedBytes > 0 {
                self.catalogDownloadShowsByteProgressUI = true
            }
            self.catalogDownloadStatus = snapshot.status
            self.catalogDownloadDownloadedBytes = snapshot.downloadedBytes
            self.catalogDownloadEstimatedTotalBytes = max(snapshot.estimatedTotalBytes, snapshot.downloadedBytes)
            let raw = min(max(snapshot.fractionCompleted, 0), 1)
            self.catalogDownloadProgress = raw * syncPhaseWeight
        }

        catalogDownloadStatus = "Refreshing catalog…"
        catalogDownloadProgress = 0.84
        await cardData.loadSets(preferSyncedCatalog: true)

        if brandSettings.enabledBrands.contains(.pokemon) {
            catalogDownloadStatus = "Loading Pokémon index…"
            catalogDownloadProgress = 0.92
            await cardData.loadNationalDexPokemon()
        } else {
            cardData.clearNationalDexForDisabledPokemon()
            catalogDownloadProgress = 0.94
        }

        if brandSettings.enabledBrands.contains(.onePiece) {
            catalogDownloadStatus = "Loading ONE PIECE browse lists…"
            catalogDownloadProgress = 0.97
            await cardData.loadOnePieceBrowseMetadata()
        } else {
            cardData.clearOnePieceBrowseMetadata()
            catalogDownloadProgress = 0.98
        }

        catalogDownloadStatus = "Done."
        catalogDownloadProgress = 1

        isCatalogDownloadInProgress = false
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

    func setupCollectionValue(modelContext: ModelContext) {
        guard collectionValue == nil else { return }
        collectionValue = CollectionValueService(modelContext: modelContext, pricing: pricing, cardData: cardData)
    }
}
