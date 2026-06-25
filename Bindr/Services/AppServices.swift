import Foundation
import Observation
import SwiftData

struct WishlistRemovalCandidate: Hashable {
    let cardID: String
    let cardName: String
}

struct WishlistRemovalPrompt: Identifiable {
    let id = UUID()
    let candidates: [WishlistRemovalCandidate]

    var message: String {
        if candidates.count == 1, let candidate = candidates.first {
            return "\(candidate.cardName) is on your wishlist. Remove it now?"
        }
        return "\(candidates.count) of the cards you added are on your wishlist. Remove them now?"
    }
}

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

    private let slowLaunchRefreshThreshold: Duration = .seconds(15)
    private var backgroundCatalogRefreshInFlight: Task<CatalogSyncOutcome, Never>?
    private var launchRefreshOutcome: CatalogSyncOutcome?
    private var launchRefreshLastMeaningfulProgressAt: ContinuousClock.Instant?
    private var launchRefreshLastCompletedFiles = 0
    private var launchUsingSavedData = false
    private var hasOfferedSavedDataThisLaunch = false
    let brandsManifest = BrandsManifestService()
    let brandSettings: BrandSettings
    let cardData: CardDataService
    let variantsCatalog = VariantsCatalogService()
    let sealedProducts = SealedProductService()
    let pricing = PricingService()
    let priceDisplay: PriceDisplaySettings
    let browseGridOptions: BrowseGridOptionsSettings
    let store = StoreKitService()
    let socialAuth: SocialAuthService
    let socialProfile: SocialProfileService
    let socialFriend: SocialFriendService
    let socialShare: SocialShareService
    let socialFeed: SocialFeedService
    let socialPush: SocialPushService
    let trade: TradeService
    let tradeSession: TradeSessionService
    let collectionSync: CollectionSyncService
    let cardFriendTradeMatches = CardFriendTradeMatchService()
    let theme: ThemeSettings
    let offlineImageSettings: OfflineImageSettings
    let offlineImageDownload: OfflineImageDownloadService
    let essentialAssetsDownload: EssentialAssetsDownloadService

    // Wishlist service - initialized after model context is available
    private(set) var wishlist: WishlistService?
    private(set) var wishlistRemovalPrompt: WishlistRemovalPrompt?
    private var queuedWishlistRemovalPrompts: [WishlistRemovalPrompt] = []

    /// Collection + ledger (SwiftData) — initialized with `ModelContext`.
    private(set) var collectionLedger: CollectionLedgerService?

    /// Daily value snapshots (SwiftData) — initialized with `ModelContext`.
    private(set) var collectionValue: CollectionValueService?
    /// After a cloud backup restore, today's value must not be recomputed until catalog pricing is fully local.
    private(set) var needsCollectionValueRecalcAfterRestore = false
    private var socialSyncModelContext: ModelContext?

    private(set) var isReady = false
    private(set) var isBootstrapping = false
    /// Joins concurrent callers onto one bootstrap run (prefetch + catalog pipeline).
    private var bootstrapInFlight: Task<Void, Never>?
    /// Set when the returning-user daily refresh path has deferred work that should run
    /// after the launch overlay fades. RootView calls `runDeferredLaunchServicesIfNeeded()`
    /// from the fade completion block to avoid blocking the fade animation.
    private(set) var shouldRunDeferredLaunchServices = false
    /// Fresh installs stay on the launch overlay until Bindr cloud backup restore finishes (or is skipped).
    private(set) var isLaunchCloudBackupRestoreComplete = BindrApp.storeExistedAtLaunch
    private var hasAttemptedAutomaticCloudBackupRestore = false
    private var cloudBackupRestoreInFlight: Task<Void, Never>?
    private var launchCatalogPipelineCompletedAt: Date?
    /// Until `true`, the root UI should not mount the main tab shell (Browse, etc.) so the cold launch catalog pipeline does not race the same SQLite + network work on the main actor.
    private(set) var isLaunchCatalogPipelineComplete = false
    /// Set in `init` when the user already completed the one-time blocking bootstrap; consumed by the first `.task` on the main UI to refresh catalogs in the background.
    private(set) var shouldRunBackgroundCatalogRefreshOnLaunch = false
    private var hasResolvedLaunchCatalogRefreshRequirement = true
    private var launchCatalogRefreshRequirementContinuations: [CheckedContinuation<Void, Never>] = []
    private var launchRefreshOutcomeContinuations: [CheckedContinuation<Void, Never>] = []
    private var launchUsingSavedDataContinuations: [CheckedContinuation<Void, Never>] = []
    /// Mirrors card-detail root overlay behavior for sealed detail sheets so underlying UI is fully obscured.
    var isSealedDetailPresentationActive = false
    /// Mirrors card-detail sheets presented from nested surfaces (e.g. Dashboard).
    var isCardDetailPresentationActive = false
    /// Hides the tab bar while a modal resets its tint so users never see a grey flash.
    var suppressTabBarUntilTintRestored = false
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
    private(set) var shouldOfferSavedDataLaunch = false
    private(set) var savedDataLaunchDate: Date?

    /// Incremented by the settings recalculate button so DashboardView reloads market trend/movers.
    private(set) var dashboardMarketReloadToken: Int = 0

    /// Bumped whenever collection inventory changes (add, remove, gift, sell, etc.) so
    /// DashboardView can recompute live collection value without waiting on SwiftData debounce.
    private(set) var collectionInventoryRevision: Int = 0
    private(set) var wishlistInventoryRevision: Int = 0

    func requestDashboardMarketReload() {
        dashboardMarketReloadToken += 1
    }

    func notifyCollectionInventoryChanged() {
        collectionInventoryRevision += 1
        scheduleLibraryCloudBackup()
    }

    func notifyWishlistInventoryChanged() {
        wishlistInventoryRevision += 1
        scheduleLibraryCloudBackup()
    }

    /// Schedules a debounced R2 upload — account backup + friend trade snapshots.
    func scheduleLibraryCloudBackup() {
        collectionSync.scheduleUpload()
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
        self.priceDisplay = PriceDisplaySettings()
        self.browseGridOptions = BrowseGridOptionsSettings()
        let brandSettings = BrandSettings()
        self.brandSettings = brandSettings
        self.cardData = CardDataService(brandSettings: brandSettings)
        self.trade = TradeService(authService: socialAuth)
        self.tradeSession = TradeSessionService(authService: socialAuth)
        self.collectionSync = CollectionSyncService(authService: socialAuth)
        self.socialShare = SocialShareService(
            authService: socialAuth,
            storeService: store,
            cardDataService: cardData,
            pricingService: pricing
        )
        self.theme = ThemeSettings()
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
                let pending = self.launchCatalogRefreshRequirementContinuations
                self.launchCatalogRefreshRequirementContinuations = []
                for c in pending { c.resume() }
            }
        }
        Task { await refreshCatalogCardsLastUpdatedAtFromStore() }
        Task { await variantsCatalog.reloadFromStore() }
        Task {
            // Delay social init until after the launch wordmark animation (~1.8s)
            // so that network callbacks don't hitch the main thread mid-animation.
            // For first-run users, also wait until onboarding completes so the
            // @MainActor work from restoreSession doesn't freeze the onboarding UI.
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            while !brandSettings.hasCompletedBrandOnboarding {
                await withCheckedContinuation { continuation in
                    withObservationTracking {
                        _ = brandSettings.hasCompletedBrandOnboarding
                    } onChange: {
                        continuation.resume()
                    }
                }
            }
            // First-run catalog bootstrap owns SQLite + R2; defer session restore until it finishes
            // so MainActor work cannot interleave with download progress on the post-onboarding screen.
            while !brandSettings.hasCompletedInitialAppBootstrap && !isReady {
                await withCheckedContinuation { continuation in
                    withObservationTracking {
                        _ = brandSettings.hasCompletedInitialAppBootstrap
                        _ = isReady
                    } onChange: {
                        continuation.resume()
                    }
                }
            }
            await socialAuth.restoreSession()
            // syncSocialLibrariesIfPossible is intentionally omitted here.
            // setupWishlistAndLedger (called from RootView's launch task) already
            // runs a sync pass and is awaited before the overlay closes. Running it
            // again here does a full modelContext.fetch(CollectionItem) on the main
            // thread which blocks the fade animation for several seconds.
        }

        NotificationCenter.default.addObserver(
            forName: .appPreferencesDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleLibraryCloudBackup()
            }
        }
    }

    /// Browse calls this once after launch pipeline: if `true`, skip heavy reload (catalog + search index already warmed).
    func consumeLightBrowseTabEntryIfNeeded() -> Bool {
        guard pendingLightBrowseTabEntry else { return false }
        pendingLightBrowseTabEntry = false
        return true
    }

    func bootstrap() async {
        if isReady { return }
        if let bootstrapInFlight {
            await bootstrapInFlight.value
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }
            await self.performBootstrap()
        }
        bootstrapInFlight = task
        await task.value
        bootstrapInFlight = nil
    }

    private func performBootstrap() async {
        guard !isReady else { return }
        isBootstrapping = true
        defer { isBootstrapping = false }

        bootstrapShowsDownloadProgressUI = true
        bootstrapMessage = "Updating Pokémon card data…"
        bootstrapStatus = "Preparing downloads…"
        bootstrapProgress = 0
        bootstrapDownloadedBytes = 0
        bootstrapEstimatedTotalBytes = 0
        // Paint 0% on the post-onboarding loading screen before sync work begins.
        await Task.yield()
        await Task.yield()

        _ = await runStartupCatalogPipeline(
            updateBootstrapProgressUI: true,
            includeDeferredLaunchServices: false
        )

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
        if !hasResolvedLaunchCatalogRefreshRequirement {
            await withCheckedContinuation { continuation in
                launchCatalogRefreshRequirementContinuations.append(continuation)
            }
        }
        guard shouldRunBackgroundCatalogRefreshOnLaunch else {
            if !isLaunchCatalogPipelineComplete {
                await primeLaunchCatalogFromLocalCache()
                isLaunchCatalogPipelineComplete = true
                launchCatalogPipelineCompletedAt = Date()
            }
            scheduleBackgroundDailyCatalogRefreshIfNeeded()
            return
        }
        shouldRunBackgroundCatalogRefreshOnLaunch = false
        // First launch after the daily boundary: prime cached data immediately, then
        // wait for the refresh unless it stalls/fails and the user chooses saved data.
        if !isLaunchCatalogPipelineComplete {
            bootstrapMessage = "Updating Market data…"
            bootstrapStatus = "Checking for updates…"
            bootstrapProgress = 0
            bootstrapDownloadedBytes = 0
            bootstrapEstimatedTotalBytes = 0
            bootstrapShowsDownloadProgressUI = false
            await primeLaunchCatalogFromLocalCache()
            let hasSavedData = await CatalogStore.shared.hasUsableCachedData(for: brandSettings.enabledBrands)
            savedDataLaunchDate = hasSavedData ? await CatalogStore.shared.savedCardDataDate() : nil
            launchUsingSavedData = false
            hasOfferedSavedDataThisLaunch = false
            shouldOfferSavedDataLaunch = false
            launchRefreshOutcome = nil
            launchRefreshLastCompletedFiles = 0
            launchRefreshLastMeaningfulProgressAt = .now

            scheduleBackgroundDailyCatalogRefreshIfNeeded()
            if hasSavedData {
                launchUsingSavedData = true
                isLaunchCatalogPipelineComplete = true
                launchCatalogPipelineCompletedAt = Date()
                shouldRunDeferredLaunchServices = true
                Task(priority: .background) { [weak self] in
                    await self?.resumeOfflineDownloadsIfNeeded()
                }
                return
            }
            // No saved local data exists, so wait for the refresh. Polling avoids a
            // continuation-registration race when the refresh finishes immediately.
            let slowLaunchTimerTask = Task { [weak self] in
                guard let self, hasSavedData else { return }
                var sleepDuration = slowLaunchRefreshThreshold
                while !Task.isCancelled {
                    try? await Task.sleep(for: sleepDuration)
                    guard !Task.isCancelled, !self.hasOfferedSavedDataThisLaunch else { return }
                    if let lastProgress = self.launchRefreshLastMeaningfulProgressAt {
                        let elapsed = ContinuousClock.now - lastProgress
                        if elapsed >= self.slowLaunchRefreshThreshold {
                            self.hasOfferedSavedDataThisLaunch = true
                            self.shouldOfferSavedDataLaunch = true
                            return
                        }
                        // Progress happened while we slept — wait out the remaining window.
                        sleepDuration = self.slowLaunchRefreshThreshold - elapsed
                    } else {
                        return
                    }
                }
            }
            while launchRefreshOutcome == nil {
                try? await Task.sleep(for: .milliseconds(200))
            }
            slowLaunchTimerTask.cancel()

            if let outcome = launchRefreshOutcome,
               hasSavedData,
               outcome.status == .failed || outcome.status == .partial {
                launchUsingSavedData = true
            }
            isLaunchCatalogPipelineComplete = true
            launchCatalogPipelineCompletedAt = Date()
        } else {
            await primeLaunchCatalogFromLocalCache()
            scheduleBackgroundDailyCatalogRefreshIfNeeded()
        }
        // runDeferredLaunchServices is intentionally NOT called here.
        // RootView calls runDeferredLaunchServicesIfNeeded() from the overlay
        // fade completion block so these @MainActor calls don't block the fade animation.
        shouldRunDeferredLaunchServices = true
        Task(priority: .background) { [weak self] in
            await self?.resumeOfflineDownloadsIfNeeded()
        }
    }

    func keepWaitingForLaunchRefresh() {
        shouldOfferSavedDataLaunch = false
    }

    func loadSavedDataForLaunch() {
        shouldOfferSavedDataLaunch = false
        launchUsingSavedData = true
        let pending = launchUsingSavedDataContinuations
        launchUsingSavedDataContinuations = []
        for c in pending { c.resume() }
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
            try? await Task.sleep(nanoseconds: 200_000_000)
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

    /// After first-run bootstrap completes, download offline image packs if the user enabled them during onboarding.
    func schedulePostBootstrapOfflineImageDownload(for brand: TCGBrand) {
        guard offlineImageSettings.isOfflinePackEnabled(for: brand) else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let bootstrapInFlight {
                await bootstrapInFlight.value
            } else if !isReady {
                await bootstrap()
            }
            guard isReady else { return }
            await offlineImageDownload.runFullDownloadIfNeeded(
                brand: brand,
                nationalDexPokemon: cardData.nationalDexPokemon,
                sealedProducts: sealedProducts.products
            )
        }
    }

    /// Starts (or joins) a background daily catalog refresh when local metadata says
    /// pricing or daily blobs are still stale for the current 03:00 period.
    private func scheduleBackgroundDailyCatalogRefreshIfNeeded() {
        guard backgroundCatalogRefreshInFlight == nil else { return }
        let task = Task { @MainActor [weak self] in
            guard let self else {
                return CatalogSyncOutcome(status: .failed, downloadedBytes: 0)
            }

            let needsRefresh = await CatalogSyncCoordinator.shared.requiresDailyBlockingRefreshAsync(
                enabledBrands: self.brandSettings.enabledBrands
            )
            guard needsRefresh else {
                return CatalogSyncOutcome(status: .unchanged, downloadedBytes: 0)
            }

            let outcome = await self.runStartupCatalogPipeline(
                updateBootstrapProgressUI: true,
                includeDeferredLaunchServices: false
            )
            self.pendingLightBrowseTabEntry = true

            let stillStale = await CatalogSyncCoordinator.shared.requiresDailyBlockingRefreshAsync(
                enabledBrands: self.brandSettings.enabledBrands
            )
            guard !stillStale else { return outcome }

            // Fresh pricing landed — invalidate any pre-03:00 snapshot saved earlier today
            // and nudge the dashboard to recompute with the new data.
            self.collectionValue?.invalidatePersistedSnapshot()
            await self.sealedProducts.reloadFromLocal()
            self.pricing.clearSetPricingMemoryCache()
            await self.pricing.prefetchPokemonCardPricing(forSetCodes: [])
            self.requestDashboardMarketReload()
            return outcome
        }
        backgroundCatalogRefreshInFlight = task
        Task { @MainActor [weak self] in
            let outcome = await task.value
            guard let self else { return }
            self.launchRefreshOutcome = outcome
            self.backgroundCatalogRefreshInFlight = nil
            let pending = self.launchRefreshOutcomeContinuations
            self.launchRefreshOutcomeContinuations = []
            for c in pending { c.resume() }
        }
    }

    /// Fast, local-only readiness pass so Browse/Collect can render without waiting on remote checks.
    private func primeLaunchCatalogFromLocalCache() async {
        await cardData.loadSets(preferSyncedCatalog: true)
        await sealedProducts.loadFromLocalIfAvailable(launchMode: true)
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
    ) async -> CatalogSyncOutcome {
        await brandsManifest.refresh()
        if updateBootstrapProgressUI {
            bootstrapMessage = "Updating Pokémon card data…"
            bootstrapStatus = "Downloading card catalog…"
            await Task.yield()
        }

        // Network sync fills most of the bar; reserve the tail for local SQLite work
        // so the post-onboarding screen keeps moving instead of stalling near the end.
        let syncPhaseWeight = 0.82

        let progressHandler: (@MainActor @Sendable (CatalogSyncProgressSnapshot) -> Void)?
        if updateBootstrapProgressUI {
            progressHandler = { [weak self] snapshot in
                guard let self else { return }
                if snapshot.downloadedBytes > self.bootstrapDownloadedBytes
                    || snapshot.completedFiles > self.launchRefreshLastCompletedFiles {
                    self.launchRefreshLastMeaningfulProgressAt = .now
                    self.launchRefreshLastCompletedFiles = snapshot.completedFiles
                }
                if snapshot.downloadedBytes > 0 {
                    self.bootstrapShowsDownloadProgressUI = true
                }
                self.bootstrapStatus = snapshot.status
                self.bootstrapDownloadedBytes = snapshot.downloadedBytes
                self.bootstrapEstimatedTotalBytes = max(snapshot.estimatedTotalBytes, snapshot.downloadedBytes)
                let raw = min(max(snapshot.fractionCompleted, 0), 1)
                self.bootstrapProgress = raw * syncPhaseWeight
            }
        } else {
            progressHandler = nil
        }
        let outcome = await CatalogSyncCoordinator.shared.syncAllIfNeeded(
            enabledBrands: brandSettings.enabledBrands,
            progressHandler: progressHandler
        )

        if updateBootstrapProgressUI {
            bootstrapStatus = "Refreshing catalog…"
            bootstrapProgress = 0.84
        }
        await cardData.loadSets(preferSyncedCatalog: true)

        if updateBootstrapProgressUI {
            bootstrapStatus = "Preparing browse…"
            bootstrapProgress = 0.88
        }
        await cardData.warmBrowseFeedForLaunch()

        if updateBootstrapProgressUI {
            bootstrapStatus = "Loading Pokémon index…"
            bootstrapProgress = 0.92
        }
        await cardData.loadNationalDexPokemon()
        await variantsCatalog.reloadFromStore()

        if updateBootstrapProgressUI {
            bootstrapProgress = 0.97
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

        // Warm pricing cache after readiness so a slow SQLite pricing pass can never
        // strand the launch overlay at "Card data is ready."
        Task(priority: .utility) { [weak self] in
            await self?.pricing.prefetchPokemonCardPricing(forSetCodes: [])
        }

        return outcome
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

        _ = await CatalogSyncCoordinator.shared.syncAllIfNeeded(
            enabledBrands: brandSettings.enabledBrands,
            progressHandler: { [weak self] snapshot in
            guard let self else { return }
            if snapshot.downloadedBytes > 0 {
                self.catalogDownloadShowsByteProgressUI = true
            }
            self.catalogDownloadStatus = snapshot.status
            self.catalogDownloadDownloadedBytes = snapshot.downloadedBytes
            self.catalogDownloadEstimatedTotalBytes = max(snapshot.estimatedTotalBytes, snapshot.downloadedBytes)
            let raw = min(max(snapshot.fractionCompleted, 0), 1)
            self.catalogDownloadProgress = raw * syncPhaseWeight
            },
            deferDeepHistoryBackfill: false
        )

        catalogDownloadStatus = "Refreshing catalog…"
        catalogDownloadProgress = 0.84
        await cardData.loadSets(preferSyncedCatalog: true)

        catalogDownloadStatus = "Loading Pokémon index…"
        catalogDownloadProgress = 0.92
        await cardData.loadNationalDexPokemon()
        await variantsCatalog.reloadFromStore()

        catalogDownloadProgress = 0.97
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
        await variantsCatalog.reloadFromStore()
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
        await pricing.prefetchPokemonCardPricing(forSetCodes: [])
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
        socialSyncModelContext = modelContext
        if wishlist == nil {
            wishlist = WishlistService(modelContext: modelContext, store: store)
        }
        wishlist?.onWishlistChanged = { [weak self] in self?.notifyWishlistInventoryChanged() }
        Task { await syncSocialLibrariesIfPossible() }
    }

    func requestWishlistRemovalPrompt(for candidates: [WishlistRemovalCandidate]) {
        guard let wishlist else { return }

        var seenCardIDs = Set<String>()
        let wishlisted = candidates.filter { candidate in
            guard seenCardIDs.insert(candidate.cardID).inserted else { return false }
            return wishlist.isInWishlist(cardID: candidate.cardID)
        }
        guard !wishlisted.isEmpty else { return }

        let prompt = WishlistRemovalPrompt(candidates: wishlisted)
        if wishlistRemovalPrompt == nil {
            wishlistRemovalPrompt = prompt
        } else {
            queuedWishlistRemovalPrompts.append(prompt)
        }
    }

    func resolveWishlistRemovalPrompt(remove: Bool) {
        guard let prompt = wishlistRemovalPrompt else { return }

        if remove, let wishlist {
            for candidate in prompt.candidates {
                try? wishlist.removeAllItems(forCardID: candidate.cardID)
            }
        }

        wishlistRemovalPrompt = nil
        guard !queuedWishlistRemovalPrompts.isEmpty else { return }
        let nextPrompt = queuedWishlistRemovalPrompts.removeFirst()
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.wishlistRemovalPrompt = nextPrompt
        }
    }

    func setupCollectionLedger(modelContext: ModelContext) {
        bindCollectionSync(modelContext: modelContext)
        guard collectionLedger == nil else { return }
        let ledger = CollectionLedgerService(modelContext: modelContext, store: store)
        ledger.onCollectionChanged = { [weak self] in self?.notifyCollectionInventoryChanged() }
        collectionLedger = ledger
        _ = try? CollectionCostLotRepair.relinkActiveLots(in: modelContext)
        Task { await syncSocialLibrariesIfPossible() }
    }

    /// Sets up wishlist + ledger and awaits a single social sync pass.
    /// Called from RootView's launch task so the overlay stays up until this completes.
    func setupWishlistAndLedger(modelContext: ModelContext) async {
        bindCollectionSync(modelContext: modelContext)
        if wishlist == nil {
            wishlist = WishlistService(modelContext: modelContext, store: store)
        }
        wishlist?.onWishlistChanged = { [weak self] in self?.notifyWishlistInventoryChanged() }
        if collectionLedger == nil {
            let ledger = CollectionLedgerService(modelContext: modelContext, store: store)
            ledger.onCollectionChanged = { [weak self] in self?.notifyCollectionInventoryChanged() }
            collectionLedger = ledger
        }
        _ = try? CollectionCostLotRepair.relinkActiveLots(in: modelContext)
        bindCollectionSync(modelContext: modelContext)
        await syncSocialLibrariesIfPossible()
    }

    /// Replaces the local library from Bindr cloud backup (R2).
    /// Call when the user signs in during onboarding (or restores an existing session).
    /// Blocks the dashboard until the Bindr cloud backup has been applied.
    func restoreCloudBackupAfterSignIn(modelContext: ModelContext? = nil) async {
        if let cloudBackupRestoreInFlight {
            await cloudBackupRestoreInFlight.value
            return
        }

        let task = Task { @MainActor in
            await self.performCloudBackupRestoreAfterSignIn(modelContext: modelContext)
        }
        cloudBackupRestoreInFlight = task
        await task.value
        cloudBackupRestoreInFlight = nil
    }

    private func performCloudBackupRestoreAfterSignIn(modelContext: ModelContext?) async {
        guard !BindrApp.storeExistedAtLaunch else {
            isLaunchCloudBackupRestoreComplete = true
            return
        }
        guard socialAuth.isSignedIn else { return }

        if let modelContext {
            bindCollectionSync(modelContext: modelContext)
        } else if socialSyncModelContext == nil {
            for _ in 0..<60 {
                try? await Task.sleep(for: .milliseconds(250))
                if socialSyncModelContext != nil { break }
            }
        }

        guard socialSyncModelContext != nil else {
            isLaunchCloudBackupRestoreComplete = true
            return
        }
        guard !hasAttemptedAutomaticCloudBackupRestore else {
            isLaunchCloudBackupRestoreComplete = true
            return
        }

        hasAttemptedAutomaticCloudBackupRestore = true
        _ = await restoreCollectionFromCloudBackup(force: true)
        isLaunchCloudBackupRestoreComplete = true
    }

    /// Call when onboarding finishes without a Bindr sign-in — nothing to restore from R2.
    func markLaunchCloudBackupRestoreSkipped() {
        isLaunchCloudBackupRestoreComplete = true
    }

    func libraryInventoryCounts(modelContext: ModelContext) -> LibraryInventoryCounts {
        LibraryInventoryCounts.load(from: modelContext)
    }

    /// Replaces the local library from Bindr cloud backup (R2).
    func restoreCollectionFromCloudBackup(force: Bool = false) async -> Bool {
        let restored = await collectionSync.restoreFromCloudBackupIfNeeded(force: force)
        if restored {
            await refreshLibraryUIAfterCloudBackupRestore()
        }
        return restored
    }

    /// Uploads the full local library to Bindr cloud backup immediately.
    func backupLibraryToCloud() async -> Bool {
        await collectionSync.backupEverythingNow()
    }

    enum AccountDeletionError: LocalizedError {
        case localLibraryNotReady

        var errorDescription: String? {
            switch self {
            case .localLibraryNotReady:
                return "Your library is still loading. Try again in a moment."
            }
        }
    }

    /// Deletes the Bindr account remotely, clears local library data, and signs out.
    func deleteAccountAndAllData() async throws {
        collectionSync.cancelPendingUpload()
        try await socialAuth.deleteAccount()

        guard let modelContext = socialSyncModelContext else {
            throw AccountDeletionError.localLibraryNotReady
        }

        try UserLibraryBackupCodec.clearLocalLibrary(modelContext: modelContext)
        await refreshLibraryUIAfterLocalClear()
    }

    private func refreshLibraryUIAfterLocalClear() async {
        await collectionValue?.loadAllFromStore()
        collectionInventoryRevision += 1
    }

    private func refreshLibraryUIAfterCloudBackupRestore() async {
        markCollectionValueRecalcAfterRestorePending()
        await collectionValue?.loadAllFromStore()
        collectionInventoryRevision += 1
    }

    /// Clears stale in-memory pricing and defers today's value recompute until catalog data is ready.
    func markCollectionValueRecalcAfterRestorePending() {
        needsCollectionValueRecalcAfterRestore = true
        pricing.clearSetPricingMemoryCache()
        collectionValue?.invalidatePersistedSnapshot()
    }

    func markCollectionValueRecalcAfterRestoreComplete() {
        needsCollectionValueRecalcAfterRestore = false
        scheduleLibraryCloudBackup()
    }

    private func bindCollectionSync(modelContext: ModelContext) {
        socialSyncModelContext = modelContext
        collectionSync.setup(modelContext: modelContext)
    }

    func setupCollectionValue(modelContext: ModelContext) {
        bindCollectionSync(modelContext: modelContext)
        guard collectionValue == nil else { return }
        let service = CollectionValueService(
            modelContext: modelContext,
            pricing: pricing,
            cardData: cardData,
            sealedProducts: sealedProducts
        )
        service.onValueHistoryChanged = { [weak self] in self?.scheduleLibraryCloudBackup() }
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
        // Keep launch social sync cheap: do not materialize full SwiftData tables on
        // @MainActor while the launch overlay is coming down.
        let cardCount = modelContext.collectionTotalCardQuantity()
        let wishlistCount = (try? modelContext.fetchCount(FetchDescriptor<WishlistItem>())) ?? 0
        let binderCount = (try? modelContext.fetchCount(FetchDescriptor<Binder>())) ?? 0
        let deckCount = (try? modelContext.fetchCount(FetchDescriptor<Deck>())) ?? 0
        let valueSnapshotCount = (try? modelContext.fetchCount(FetchDescriptor<CollectionValueSnapshot>())) ?? 0
        let totalValue = collectionValue?.snapshots.last?.totalGbp ?? 0
        // Only upload when we have data — never overwrite cloud backup with an empty snapshot.
        if cardCount > 0 || wishlistCount > 0 || binderCount > 0 || deckCount > 0 || valueSnapshotCount > 0 {
            scheduleLibraryCloudBackup()
        }

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
