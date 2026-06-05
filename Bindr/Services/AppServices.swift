import Foundation
import Observation
import SwiftData
import CoreData

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

    private let launchDailyRefreshTimeoutNanoseconds: UInt64 = 5_000_000_000
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
    let tradeSession: TradeSessionService
    let collectionSync: CollectionSyncService
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
    /// Set when the returning-user daily refresh path has deferred work that should run
    /// after the launch overlay fades. RootView calls `runDeferredLaunchServicesIfNeeded()`
    /// from the fade completion block to avoid blocking the fade animation.
    private(set) var shouldRunDeferredLaunchServices = false
    /// True once the initial CloudKit import event has completed (or timed out / not applicable).
    /// Held in the launch gate so the overlay never closes while CloudKit is doing its
    /// initial @MainActor import callbacks, which would stall the fade animation.
    private(set) var isCloudKitImportComplete = false
    private var cloudKitObserver: NSObjectProtocol?
    private var cloudKitIdleMonitor: CloudKitIdleMonitor?
    /// Timestamp used to avoid finalizing CloudKit readiness on the exact frame
    /// the launch catalog pipeline flips complete.
    private var launchCatalogPipelineCompletedAt: Date?
    /// Until `true`, the root UI should not mount the main tab shell (Browse, etc.) so the cold launch catalog pipeline does not race the same SQLite + network work on the main actor.
    private(set) var isLaunchCatalogPipelineComplete = false
    /// Set in `init` when the user already completed the one-time blocking bootstrap; consumed by the first `.task` on the main UI to refresh catalogs in the background.
    private(set) var shouldRunBackgroundCatalogRefreshOnLaunch = false
    private var hasResolvedLaunchCatalogRefreshRequirement = true
    /// Mirrors card-detail root overlay behavior for sealed detail sheets so underlying UI is fully obscured.
    var isSealedDetailPresentationActive = false
    /// Temporary handoff when trade starts from non-social surfaces (e.g. Collect tab),
    /// then the user chooses a friend profile to complete the trade composer.
    var pendingTradeSeed: PendingTradeSeed?
    /// Set by the Trade Wall + button so `FriendsListView` enters "select a friend"
    /// mode for a blank new trade (no pre-seeded card). Cleared by `openSeededTradeBuilder`
    /// when the friend is picked, or by the Cancel button if the user backs out.
    var isCreatingNewTrade: Bool = false
    /// Set when a catalog pipeline run just finished; ``BrowseView`` consumes once to skip duplicate ``CardDataService/reloadAfterBrandChange()`` (same `loadSets` + search index work).
    private var pendingLightBrowseTabEntry = false
    /// When true, ``RootView`` shows the full ``LoadingScreen`` with byte counts; otherwise a simple indeterminate busy state until sync actually transfers data.
    private(set) var bootstrapShowsDownloadProgressUI = false
    private(set) var bootstrapMessage = "Updating card data, please wait."
    private(set) var bootstrapStatus = "Preparing downloads…"
    private(set) var bootstrapProgress: Double = 0
    private(set) var bootstrapDownloadedBytes: Int64 = 0
    private(set) var bootstrapEstimatedTotalBytes: Int64 = 0

    /// Incremented by the settings recalculate button so DashboardView reloads market trend/movers.
    private(set) var dashboardMarketReloadToken: Int = 0

    func requestDashboardMarketReload() {
        dashboardMarketReloadToken += 1
    }

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
        self.tradeSession = TradeSessionService(authService: socialAuth)
        self.collectionSync = CollectionSyncService(authService: socialAuth)
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
        if brandSettings.hasCompletedInitialAppBootstrap {
            isReady = true
            isLaunchCatalogPipelineComplete = false
            hasResolvedLaunchCatalogRefreshRequirement = false
            Task { [weak self] in
                guard let self else { return }
                let requiresBlockingDailyRefresh = await CatalogSyncCoordinator.shared.requiresDailyBlockingRefreshAsync(
                    enabledBrands: brandSettings.enabledBrands
                )
                self.shouldRunBackgroundCatalogRefreshOnLaunch = requiresBlockingDailyRefresh
                self.isLaunchCatalogPipelineComplete = !requiresBlockingDailyRefresh
                self.hasResolvedLaunchCatalogRefreshRequirement = true
                if self.isLaunchCatalogPipelineComplete {
                    self.launchCatalogPipelineCompletedAt = Date()
                }
            }
        }
        Task { await refreshCatalogCardsLastUpdatedAtFromStore() }
        Task {
            // Delay social init until after the launch wordmark animation (~1.8s)
            // so that network callbacks don't hitch the main thread mid-animation.
            // For first-run users, also wait until onboarding completes so the
            // @MainActor work from restoreSession doesn't freeze the onboarding UI.
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            while !brandSettings.hasCompletedBrandOnboarding {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            print("[Launch] init Task: restoreSession start")
            let _t = ContinuousClock().now
            await socialAuth.restoreSession()
            print("[Launch] init Task: restoreSession done \(ContinuousClock().now - _t)")
            // syncSocialLibrariesIfPossible is intentionally omitted here.
            // setupWishlistAndLedger (called from RootView's launch task) already
            // runs a sync pass and is awaited before the overlay closes. Running it
            // again here does a full modelContext.fetch(CollectionItem) on the main
            // thread which blocks the fade animation for several seconds.
        }
    }

    /// Browse calls this once after launch pipeline: if `true`, skip heavy reload (catalog + search index already warmed).
    func consumeLightBrowseTabEntryIfNeeded() -> Bool {
        guard pendingLightBrowseTabEntry else { return false }
        pendingLightBrowseTabEntry = false
        return true
    }

    func bootstrap() async {
        guard !isReady, !isBootstrapping else { return }
        isBootstrapping = true
        LaunchTraceProfiler.begin("bootstrap")
        defer { isBootstrapping = false; LaunchTraceProfiler.end("bootstrap") }

        let bootstrapTask = Task { [weak self] in
            guard let self else { return }
            await self.runStartupCatalogPipeline(updateBootstrapProgressUI: true)
        }
        
        // Enforce a strict launch gate: if timeout is reached, keep showing
        // the launch surface and wait for the blocking bootstrap task to finish.
        let completedWithinTimeout = await waitForTaskOrTimeout(
            bootstrapTask,
            timeoutNanoseconds: 8_000_000_000 // 8 seconds
        )
        
        if !completedWithinTimeout {
            // Prime local cached/bundled catalog datasets while waiting, then
            // hold the gate until bootstrap fully completes.
            await primeLaunchCatalogFromLocalCache()
            bootstrapStatus = "Finishing update…"
            await bootstrapTask.value
        }
        
        brandSettings.markInitialAppBootstrapCompleted()
        pendingLightBrowseTabEntry = true
        isLaunchCatalogPipelineComplete = true
        launchCatalogPipelineCompletedAt = Date()
        isReady = true
        Task(priority: .background) { [weak self] in
            await self?.resumeOfflineDownloadsIfNeeded()
        }
    }

    /// Returning-user launch path: quickly prime local catalog data, then refresh network-backed data in the background.
    func bootstrapCatalogInBackgroundIfNeeded() async {
        LaunchTraceProfiler.begin("bootstrapCatalogInBackgroundIfNeeded")
        defer { LaunchTraceProfiler.end("bootstrapCatalogInBackgroundIfNeeded") }
        while !hasResolvedLaunchCatalogRefreshRequirement {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        guard shouldRunBackgroundCatalogRefreshOnLaunch else {
            await primeLaunchCatalogFromLocalCache()
            isLaunchCatalogPipelineComplete = true
            launchCatalogPipelineCompletedAt = Date()
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
            bootstrapShowsDownloadProgressUI = true
            // Start the network task immediately so the connection handshake overlaps
            // with local SQLite reads in primeLaunchCatalogFromLocalCache.
            let blockingTask = Task { @MainActor [weak self] in
                guard let self else { return }
                await self.runStartupCatalogPipeline(
                    updateBootstrapProgressUI: true,
                    includeDeferredLaunchServices: false
                )
                self.pendingLightBrowseTabEntry = true
            }
            await primeLaunchCatalogFromLocalCache()
            let completedWithinTimeout = await waitForTaskOrTimeout(
                blockingTask,
                timeoutNanoseconds: launchDailyRefreshTimeoutNanoseconds
            )
            if !completedWithinTimeout {
                // Keep the launch gate up until the blocking refresh fully completes.
                // Previously we marked the launch pipeline complete here even after
                // timeout, which let the splash/overlay dismiss while this task was
                // still running.
                bootstrapStatus = "Finishing update…"
                await blockingTask.value
            }
            isLaunchCatalogPipelineComplete = true
            launchCatalogPipelineCompletedAt = Date()
        } else {
            await primeLaunchCatalogFromLocalCache()
        }
        // runDeferredLaunchServices is intentionally NOT called here.
        // RootView calls runDeferredLaunchServicesIfNeeded() from the overlay
        // fade completion block so these @MainActor calls don't block the fade animation.
        shouldRunDeferredLaunchServices = true
        Task(priority: .background) { [weak self] in
            await self?.resumeOfflineDownloadsIfNeeded()
        }
    }

    /// Called by RootView after the launch overlay fade completes so that
    /// these @MainActor service calls don't block the fade animation.
    func runDeferredLaunchServicesIfNeeded() {
        guard shouldRunDeferredLaunchServices else { return }
        shouldRunDeferredLaunchServices = false
        Task(priority: .background) { [weak self] in
            self?.runDeferredLaunchServices()
        }
        // The sealed price-history blob is only needed for charts/detail, and loads on a
        // background context, so a short defer past the launch handoff is enough.
        Task(priority: .utility) { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await self?.sealedProducts.loadSealedPriceHistoryIfNeeded()
        }
    }

    /// Resume any in-progress offline image downloads after app relaunch.
    /// `runFullDownloadIfNeeded` skips images already on disk, so this is safe to call every launch.
    func resumeOfflineDownloadsIfNeeded() async {
        let enabledBrands = TCGBrand.allCases.filter { offlineImageSettings.isOfflinePackEnabled(for: $0) }
        guard !enabledBrands.isEmpty else { return }
        if sealedProducts.products.isEmpty {
            await sealedProducts.loadFromLocalIfAvailable()
        }
        let nationalDexPokemon = cardData.nationalDexPokemon
        let products = sealedProducts.products
        for brand in enabledBrands {
            await offlineImageDownload.runFullDownloadIfNeeded(
                brand: brand,
                nationalDexPokemon: nationalDexPokemon,
                sealedProducts: products
            )
        }
    }

    /// Silently pre-fetches catalog data for the selected brand in the background during onboarding,
    /// so the post-onboarding bootstrap has less network work to do. Fire-and-forget; no UI feedback.
    func prefetchCatalogInBackground(for brands: Set<TCGBrand>) {
        Task(priority: .background) { [weak self] in
            guard let self else { return }
            await CatalogSyncCoordinator.shared.syncAllIfNeeded(
                enabledBrands: brands,
                progressHandler: nil
            )
            await brandsManifest.refresh()
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
        let t = ContinuousClock().now
        print("[Launch] primeLaunchCatalogFromLocalCache: loadSets start")
        await cardData.loadSets(preferSyncedCatalog: true)
        print("[Launch] primeLaunchCatalogFromLocalCache: loadSets done \(ContinuousClock().now - t)")
        if brandSettings.enabledBrands.contains(.onePiece) {
            await cardData.loadOnePieceBrowseMetadata()
        } else {
            cardData.clearOnePieceBrowseMetadata()
        }
        let t2 = ContinuousClock().now
        print("[Launch] primeLaunchCatalogFromLocalCache: sealedProducts start")
        await sealedProducts.loadFromLocalIfAvailable(launchMode: true)
        print("[Launch] primeLaunchCatalogFromLocalCache: sealedProducts done \(ContinuousClock().now - t2)")
        pendingLightBrowseTabEntry = true
    }

    /// Non-critical launch tasks — fired concurrently, none block @MainActor.
    private func runDeferredLaunchServices() {
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            await self.pricing.refreshFXRate()
        }
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            await self.store.loadProducts()
        }
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            await self.store.checkEntitlements()
        }
    }

    private func runStartupCatalogPipeline(
        updateBootstrapProgressUI: Bool,
        includeDeferredLaunchServices: Bool = true
    ) async {
        await brandsManifest.refresh()
        if updateBootstrapProgressUI {
            bootstrapShowsDownloadProgressUI = true
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
                } else if snapshot.fractionCompleted > 0 {
                    // Daily pricing refresh often completes files with 0 bytes (304 / unchanged);
                    // still show the determinate bar from file-fraction progress.
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

        await sealedProducts.reloadFromLocal()

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

        await sealedProducts.reloadFromLocal()

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

    /// Settings action: force re-download of market trend and daily blob data, then reload the dashboard.
    /// Deliberately does NOT touch isCatalogDownloadInProgress — that flag triggers forceRecalculate
    /// on the dashboard which purges collection value snapshot history. Market trend blobs don't
    /// affect per-card prices so no recalculation is needed.
    func forceMarketTrendRefreshFromSettings() async {
        await CatalogSyncCoordinator.shared.forceMarketTrendRefresh(enabledBrands: brandSettings.enabledBrands)
        requestDashboardMarketReload()
    }

    /// Developer Tools: re-download pricing payloads from R2 (per-set prices, daily buckets, sealed prices, trend blobs).
    func forcePricingRefreshFromSettings() async {
        guard !isCatalogDownloadInProgress else { return }
        pricing.clearSetPricingMemoryCache()
        isCatalogDownloadInProgress = true
        catalogDownloadShowsByteProgressUI = false
        catalogDownloadMessage = "Refreshing pricing from R2…"
        catalogDownloadStatus = "Preparing downloads…"
        catalogDownloadProgress = 0
        catalogDownloadDownloadedBytes = 0
        catalogDownloadEstimatedTotalBytes = 0
        await Task.yield()

        let changed = await CatalogSyncCoordinator.shared.forcePricingRefresh(
            enabledBrands: brandSettings.enabledBrands
        ) { [weak self] snapshot in
            guard let self else { return }
            if snapshot.downloadedBytes > 0 {
                self.catalogDownloadShowsByteProgressUI = true
            }
            self.catalogDownloadStatus = snapshot.status
            self.catalogDownloadDownloadedBytes = snapshot.downloadedBytes
            self.catalogDownloadEstimatedTotalBytes = max(snapshot.estimatedTotalBytes, snapshot.downloadedBytes)
            self.catalogDownloadProgress = min(max(snapshot.fractionCompleted, 0), 1)
        }

        await sealedProducts.reloadFromLocal()
        await pricing.refreshFXRate()
        requestDashboardMarketReload()

        catalogDownloadProgress = 1
        catalogDownloadStatus = changed ? "Pricing updated from R2." : "Pricing already up to date."
        isCatalogDownloadInProgress = false
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
        print("[Launch] setupWishlist start")
        let t = ContinuousClock().now
        socialSyncModelContext = modelContext
        if wishlist == nil {
            wishlist = WishlistService(modelContext: modelContext, store: store)
        }
        print("[Launch] setupWishlist done: \(ContinuousClock().now - t)")
        Task { await syncSocialLibrariesIfPossible() }
    }

    func setupCollectionLedger(modelContext: ModelContext) {
        print("[Launch] setupCollectionLedger start")
        let t = ContinuousClock().now
        socialSyncModelContext = modelContext
        if collectionLedger == nil {
            collectionLedger = CollectionLedgerService(modelContext: modelContext, store: store)
        }
        print("[Launch] setupCollectionLedger done: \(ContinuousClock().now - t)")
        Task { await syncSocialLibrariesIfPossible() }
    }

    /// Sets up wishlist + ledger and awaits a single social sync pass.
    /// Called from RootView's launch task so the overlay stays up until this completes.
    func setupWishlistAndLedger(modelContext: ModelContext) async {
        socialSyncModelContext = modelContext
        print("[Launch] setupWishlist start")
        let t = ContinuousClock().now
        if wishlist == nil {
            wishlist = WishlistService(modelContext: modelContext, store: store)
        }
        print("[Launch] setupWishlist done: \(ContinuousClock().now - t)")
        print("[Launch] setupCollectionLedger start")
        let t2 = ContinuousClock().now
        if collectionLedger == nil {
            collectionLedger = CollectionLedgerService(modelContext: modelContext, store: store)
        }
        print("[Launch] setupCollectionLedger done: \(ContinuousClock().now - t2)")
        collectionSync.setup(modelContext: modelContext)
        await syncSocialLibrariesIfPossible()
    }

    /// Keeps the launch overlay visible until SwiftData's CloudKit merge is done.
    ///
    /// CloudKit always syncs on every launch — for existing installs this is a small
    /// catch-up; for fresh installs this is a full restore. Either way, SwiftData posts
    /// mergeChanges work items to @MainActor that freeze the UI. We use CloudKitIdleMonitor
    /// to detect when those merges have finished (main thread idle + no recent notifications),
    /// then close the overlay. The freeze is hidden behind the overlay, not felt on the dashboard.
    ///
    /// - Parameters:
    ///   - quietWindow: seconds of silence after last notification/hitch before declaring idle.
    ///     Use a shorter window for existing installs (small catch-up) vs fresh installs (full restore).
    func beginCloudKitReadinessMonitoring() {
        guard !isCloudKitImportComplete else { return }

        guard FileManager.default.ubiquityIdentityToken != nil else {
            print("[CloudKit] no iCloud account — opening immediately")
            markCloudKitImportComplete()
            return
        }

        let isFreshInstall = !BindrApp.storeExistedAtLaunch
        if !isFreshInstall {
            // Existing installs should not hold the launch overlay for CloudKit catch-up.
            // We keep syncing in the background, but let the user in once local launch gates clear.
            print("[CloudKit] existing install — skipping launch gate and syncing in background")
            markCloudKitImportComplete()
            return
        }
        // SwiftData CloudKit merges can arrive several seconds after the last remote
        // change notification. Keep the overlay up through that quiet period; a
        // longer honest launch is better than revealing a frozen dashboard.
        let quietWindow: TimeInterval = 10.0
        let timeout: TimeInterval = 45.0

        print("[CloudKit] fresh install — idle monitor armed (quietWindow=\(quietWindow)s, timeout=\(timeout)s)")

        let monitor = CloudKitIdleMonitor(quietWindow: quietWindow) { [weak self] in
            guard let self else { return true }
            guard self.isLaunchCatalogPipelineComplete else {
                print("[CloudKit] idle detected before launch catalog pipeline finished — continuing monitor")
                return false
            }
            // Prevent same-tick completion when the catalog gate just flipped; allow a
            // brief post-pipeline settling window for late main-thread merges.
            if let completedAt = self.launchCatalogPipelineCompletedAt,
               Date().timeIntervalSince(completedAt) < 2.0 {
                print("[CloudKit] idle detected immediately after pipeline completion — waiting briefly")
                return false
            }
            self.markCloudKitImportComplete()
            return true
        }
        self.cloudKitIdleMonitor = monitor
        monitor.start()

        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self, !self.isCloudKitImportComplete else { return }
            print("[CloudKit] timeout (\(timeout)s) — opening anyway")
            self.markCloudKitImportComplete()
        }
    }

    private func markCloudKitImportComplete() {
        guard !isCloudKitImportComplete else { return }
        isCloudKitImportComplete = true
        cloudKitIdleMonitor?.stop()
        cloudKitIdleMonitor = nil
        if let observer = cloudKitObserver {
            NotificationCenter.default.removeObserver(observer)
            cloudKitObserver = nil
        }
    }

    func setupCollectionValue(modelContext: ModelContext) {
        guard collectionValue == nil else { return }
        let service = CollectionValueService(
            modelContext: modelContext,
            pricing: pricing,
            cardData: cardData,
            sealedProducts: sealedProducts
        )
        collectionValue = service
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
        let t = ContinuousClock().now
        print("[Launch] syncSocialLibrariesIfPossible starting")
        if let wishlist {
            socialCardLibrary.scheduleAutoSyncWishlist(items: wishlist.items)
        }
        collectionSync.scheduleUpload()
        // Keep launch social sync cheap: do not materialize full SwiftData tables on
        // @MainActor while the launch overlay is coming down.
        let cardCount = (try? modelContext.fetchCount(FetchDescriptor<CollectionItem>())) ?? 0
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
        print("[Launch] syncSocialLibrariesIfPossible done: \(ContinuousClock().now - t)")
    }
}
