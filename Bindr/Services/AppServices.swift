import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class AppServices {
    enum TradePrefillSide: Sendable {
        case mySide
        case theirSide
    }

    struct PendingTradeSeed: Sendable {
        let cardID: String
        let preferredSide: TradePrefillSide
    }

    private let launchDailyRefreshTimeoutNanoseconds: UInt64 = 10_000_000_000
    let brandsManifest = BrandsManifestService()
    let brandSettings: BrandSettings
    let cardData: CardDataService
    let sealedProducts = SealedProductService()
    let pricing = PricingService()
    let cloudSettings: CloudSettingsService
    let priceDisplay: PriceDisplaySettings
    let browseGridOptions: BrowseGridOptionsSettings
    let store = StoreKitService()
    let socialAuth: SocialAuthService
    let socialProfile: SocialProfileService
    let socialFriend: SocialFriendService
    let socialShare: SocialShareService
    let socialCardLibrary: SocialCardLibraryService
    let socialFeed: SocialFeedService
    let socialPush: SocialPushService
    let trade: TradeService
    let theme: ThemeSettings
    let offlineImageSettings: OfflineImageSettings
    let offlineImageDownload: OfflineImageDownloadService
    let essentialAssetsDownload: EssentialAssetsDownloadService

    // Wishlist service - initialized after model context is available
    private(set) var wishlist: WishlistService?

    /// Collection + ledger (SwiftData) — initialized with `ModelContext`.
    private(set) var collectionLedger: CollectionLedgerService?

    /// Daily value snapshots (SwiftData) — initialized with `ModelContext`.
    private(set) var collectionValue: CollectionValueService?
    private var socialSyncModelContext: ModelContext?

    private(set) var isReady = false
    private(set) var isBootstrapping = false
    /// Until `true`, the root UI should not mount the main tab shell (Browse, etc.) so the cold launch catalog pipeline does not race the same SQLite + network work on the main actor.
    private(set) var isLaunchCatalogPipelineComplete = false
    /// Set in `init` when the user already completed the one-time blocking bootstrap; consumed by the first `.task` on the main UI to refresh catalogs in the background.
    private(set) var shouldRunBackgroundCatalogRefreshOnLaunch = false
    /// Mirrors card-detail root overlay behavior for sealed detail sheets so underlying UI is fully obscured.
    var isSealedDetailPresentationActive = false
    /// Temporary handoff when trade starts from non-social surfaces (e.g. Collect tab),
    /// then the user chooses a friend profile to complete the trade composer.
    var pendingTradeSeed: PendingTradeSeed?
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
    private(set) var catalogCardsLastUpdatedAt: Date?

    init() {
        let socialAuth = SocialAuthService()
        self.socialAuth = socialAuth
        self.socialProfile = SocialProfileService(authService: socialAuth)
        let socialFriend = SocialFriendService(authService: socialAuth, storeService: store)
        self.socialFriend = socialFriend
        self.socialFeed = SocialFeedService(authService: socialAuth, friendService: socialFriend)
        self.socialPush = SocialPushService(authService: socialAuth, profileService: socialProfile)
        let cloudSettings = CloudSettingsService()
        self.cloudSettings = cloudSettings
        self.priceDisplay = PriceDisplaySettings(cloudSettings: cloudSettings)
        self.browseGridOptions = BrowseGridOptionsSettings(cloudSettings: cloudSettings)
        let brandSettings = BrandSettings()
        self.brandSettings = brandSettings
        self.cardData = CardDataService(brandSettings: brandSettings)
        self.socialCardLibrary = SocialCardLibraryService(authService: socialAuth)
        self.trade = TradeService(authService: socialAuth)
        self.socialShare = SocialShareService(
            authService: socialAuth,
            storeService: store,
            cardDataService: cardData,
            pricingService: pricing
        )
        self.theme = ThemeSettings(cloudSettings: cloudSettings)
        let offlineImageSettings = OfflineImageSettings()
        self.offlineImageSettings = offlineImageSettings
        self.offlineImageDownload = OfflineImageDownloadService(settings: offlineImageSettings)
        self.essentialAssetsDownload = EssentialAssetsDownloadService()
        if brandSettings.hasCompletedBrandOnboarding && brandSettings.hasCompletedInitialAppBootstrap {
            let requiresBlockingDailyRefresh = CatalogSyncCoordinator.shared.requiresDailyBlockingRefresh(
                enabledBrands: brandSettings.enabledBrands
            )
            isReady = true
            shouldRunBackgroundCatalogRefreshOnLaunch = requiresBlockingDailyRefresh
            isLaunchCatalogPipelineComplete = !requiresBlockingDailyRefresh
        }
        Task { await refreshCatalogCardsLastUpdatedAtFromStore() }
        Task {
            // Delay social init until after the launch wordmark animation (~1.8s)
            // so that network callbacks don't hitch the main thread mid-animation.
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await socialAuth.restoreSession()
            await syncSocialLibrariesIfPossible()
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

    /// Returning-user launch path: quickly prime local catalog data, then refresh network-backed data in the background.
    func bootstrapCatalogInBackgroundIfNeeded() async {
        guard shouldRunBackgroundCatalogRefreshOnLaunch else {
            isLaunchCatalogPipelineComplete = true
            return
        }
        shouldRunBackgroundCatalogRefreshOnLaunch = false
        // First launch after the daily 03:00 boundary: block app shell until pricing/trends are refreshed
        // and stored locally to avoid visible value changes after the user is already in the app.
        if !isLaunchCatalogPipelineComplete {
            bootstrapMessage = "Updating Market data…"
            bootstrapStatus = "Checking for updates…"
            bootstrapProgress = 0
            bootstrapDownloadedBytes = 0
            bootstrapEstimatedTotalBytes = 0
            await primeLaunchCatalogFromLocalCache()
            let blockingTask = Task { @MainActor [weak self] in
                guard let self else { return }
                await self.runStartupCatalogPipeline(
                    updateBootstrapProgressUI: true,
                    includeDeferredLaunchServices: false
                )
                self.pendingLightBrowseTabEntry = true
            }
            let completedWithinTimeout = await waitForTaskOrTimeout(
                blockingTask,
                timeoutNanoseconds: launchDailyRefreshTimeoutNanoseconds
            )
            if !completedWithinTimeout {
                // Fail open after timeout (offline/slow network). Keep cached values and let the
                // same refresh task continue in the background.
            }
            isLaunchCatalogPipelineComplete = true
        } else {
            await primeLaunchCatalogFromLocalCache()
        }
        Task(priority: .background) { [weak self] in
            await self?.runDeferredLaunchServices()
        }
    }

    private func waitForTaskOrTimeout(
        _ task: Task<Void, Never>,
        timeoutNanoseconds: UInt64
    ) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await task.value
                return true
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }

    /// Fast, local-only readiness pass so Browse/Collect can render without waiting on remote checks.
    private func primeLaunchCatalogFromLocalCache() async {
        await cardData.loadSets(preferSyncedCatalog: true)
        if brandSettings.enabledBrands.contains(.onePiece) {
            await cardData.loadOnePieceBrowseMetadata()
        } else {
            cardData.clearOnePieceBrowseMetadata()
        }
        await sealedProducts.loadFromLocalIfAvailable()
        pendingLightBrowseTabEntry = true
    }

    /// Non-critical launch tasks that should never block first paint.
    private func runDeferredLaunchServices() async {
        await pricing.refreshFXRate()
        await store.loadProducts()
        await store.checkEntitlements()
    }

    private func runStartupCatalogPipeline(
        updateBootstrapProgressUI: Bool,
        includeDeferredLaunchServices: Bool = true
    ) async {
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

        // Give the network sync phase 95% of the bar. The remaining post-sync
        // steps (loadSets, dex, browse lists) are local SQLite reads that take
        // milliseconds — they don't warrant visible bar segments.
        let weightSync: Double = 0.95

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
            bootstrapStatus = "Finishing up…"
        }
        await cardData.loadSets(preferSyncedCatalog: true)

        if brandSettings.enabledBrands.contains(.pokemon) {
            await cardData.loadNationalDexPokemon()
        } else {
            cardData.clearNationalDexForDisabledPokemon()
        }

        if brandSettings.enabledBrands.contains(.onePiece) {
            await cardData.loadOnePieceBrowseMetadata()
        } else {
            cardData.clearOnePieceBrowseMetadata()
        }

        await sealedProducts.loadFromLocalIfAvailable()

        // Kick off essential asset downloads (set logos, symbols, pokémon art, sealed product images)
        // in the background. Fire-and-forget: does not block the bootstrap sequence.
        essentialAssetsDownload.downloadIfNeeded(
            for: brandSettings.enabledBrands,
            nationalDexPokemon: cardData.nationalDexPokemon
        )

        if includeDeferredLaunchServices {
            await pricing.refreshFXRate()
            await store.loadProducts()
            await store.checkEntitlements()
        }
        if updateBootstrapProgressUI {
            bootstrapProgress = 1.0
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

        await sealedProducts.loadFromLocalIfAvailable()

        // Force-recheck after catalog sync so any new sets, pokémon, or sealed products are fetched.
        essentialAssetsDownload.scheduleRecheck(
            for: brandSettings.enabledBrands,
            nationalDexPokemon: cardData.nationalDexPokemon
        )

        catalogDownloadStatus = "Done."
        catalogDownloadProgress = 1

        isCatalogDownloadInProgress = false
        await refreshCatalogCardsLastUpdatedAtFromStore()
    }

    /// Settings action: immediately re-check card JSON deltas (skips 03:00 schedule gate) and report whether any files changed.
    func forceCardDataRefreshFromSettings() async {
        guard !isCatalogDownloadInProgress else { return }
        pricing.clearSetPricingMemoryCache()
        isCatalogDownloadInProgress = true
        catalogDownloadShowsByteProgressUI = false
        catalogDownloadMessage = "Checking card and market data updates…"
        catalogDownloadStatus = "Preparing checks…"
        catalogDownloadProgress = 0
        catalogDownloadDownloadedBytes = 0
        catalogDownloadEstimatedTotalBytes = 0
        await Task.yield()

        let changed = await CatalogSyncCoordinator.shared.forceCardDataRefresh(enabledBrands: brandSettings.enabledBrands) { [weak self] snapshot in
            guard let self else { return }
            if snapshot.downloadedBytes > 0 {
                self.catalogDownloadShowsByteProgressUI = true
            }
            self.catalogDownloadStatus = snapshot.status
            self.catalogDownloadDownloadedBytes = snapshot.downloadedBytes
            self.catalogDownloadEstimatedTotalBytes = max(snapshot.estimatedTotalBytes, snapshot.downloadedBytes)
            self.catalogDownloadProgress = min(max(snapshot.fractionCompleted, 0), 1)
        }

        catalogDownloadProgress = 1
        catalogDownloadStatus = changed ? "Card and market data updated." : "Already up to date."
        await cardData.reloadAfterBrandChange()
        isCatalogDownloadInProgress = false
        await refreshCatalogCardsLastUpdatedAtFromStore()
    }

    /// Settings action: hard reset local catalog SQLite payloads for enabled brands, then fully re-download.
    func forceCatalogRedownloadFromSettings() async {
        guard !isCatalogDownloadInProgress else { return }
        pricing.clearSetPricingMemoryCache()
        isCatalogDownloadInProgress = true
        catalogDownloadShowsByteProgressUI = false
        catalogDownloadMessage = "Re-downloading catalog data…"
        catalogDownloadStatus = "Clearing local catalog cache…"
        catalogDownloadProgress = 0
        catalogDownloadDownloadedBytes = 0
        catalogDownloadEstimatedTotalBytes = 0
        await Task.yield()

        let enabled = brandSettings.enabledBrands
        for brand in enabled {
            try? await BrandCatalogMaintenance.purgeLocalData(for: brand)
        }

        catalogDownloadStatus = "Downloading fresh catalog data…"
        isCatalogDownloadInProgress = false
        await performCatalogSyncAfterEnablingBrands()
        await cardData.reloadAfterBrandChange()
        await refreshCatalogCardsLastUpdatedAtFromStore()
    }

    /// Call this from your root view with the model context
    func setupWishlist(modelContext: ModelContext) {
        socialSyncModelContext = modelContext
        if wishlist == nil {
            wishlist = WishlistService(modelContext: modelContext, store: store)
        }
        Task { await syncSocialLibrariesIfPossible() }
    }

    func setupCollectionLedger(modelContext: ModelContext) {
        socialSyncModelContext = modelContext
        if collectionLedger == nil {
            collectionLedger = CollectionLedgerService(modelContext: modelContext)
        }
        Task { await syncSocialLibrariesIfPossible() }
    }

    func setupCollectionValue(modelContext: ModelContext) {
        guard collectionValue == nil else { return }
        collectionValue = CollectionValueService(
            modelContext: modelContext,
            pricing: pricing,
            cardData: cardData,
            sealedProducts: sealedProducts
        )
    }

    private func refreshCatalogCardsLastUpdatedAtFromStore() async {
        try? await CatalogStore.shared.open()
        guard let raw = await CatalogStore.shared.meta("catalog_cards_last_updated_at"),
              let ts = Double(raw) else {
            catalogCardsLastUpdatedAt = nil
            return
        }
        catalogCardsLastUpdatedAt = Date(timeIntervalSince1970: ts)
    }

    private func syncSocialLibrariesIfPossible() async {
        guard let modelContext = socialSyncModelContext else { return }
        if let wishlist {
            socialCardLibrary.scheduleAutoSyncWishlist(items: wishlist.items)
        }
        if let tradeListItems = try? modelContext.fetch(FetchDescriptor<TradeListItem>()) {
            socialCardLibrary.scheduleAutoSyncTradeList(items: tradeListItems)
        }
        if let collectionItems = try? modelContext.fetch(FetchDescriptor<CollectionItem>()) {
            // Sync summary stats to profile
            let cardCount = collectionItems.reduce(0) { $0 + $1.quantity }
            let binderCount = (try? modelContext.fetchCount(FetchDescriptor<Binder>())) ?? 0
            let deckCount = (try? modelContext.fetchCount(FetchDescriptor<Deck>())) ?? 0
            let totalValue = collectionValue?.snapshots.last?.totalGbp ?? 0

            Task {
                try? await socialProfile.updateCollectionStats(
                    cardCount: cardCount,
                    binderCount: binderCount,
                    deckCount: deckCount,
                    totalValue: totalValue
                )
            }
        }
    }
}
