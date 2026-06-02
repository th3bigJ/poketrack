import SwiftUI
import SwiftData
import UIKit

/// Thin wrapper that gives `BrowseView` its own stable SwiftUI identity,
/// preventing it from being re-initialised whenever `RootView.body` re-evaluates.
private struct BrowseTabView: View {
    @Query private var collectionItems: [CollectionItem]

    @Binding var filters: BrowseCardGridFilters
    @Binding var inlineDetailFilters: BrowseCardGridFilters
    @Binding var gridOptions: BrowseGridOptions
    @Binding var filterResultCount: Int
    @Binding var filterEnergyOptions: [String]
    @Binding var filterRarityOptions: [String]
    @Binding var filterTrainerTypeOptions: [String]
    @Binding var inlineDetailFilterResultCount: Int
    @Binding var inlineDetailFilterEnergyOptions: [String]
    @Binding var inlineDetailFilterRarityOptions: [String]
    @Binding var inlineDetailFilterTrainerTypeOptions: [String]
    @Binding var selectedTab: BrowseHomeTab
    @Binding var inlineDetailRoute: BrowseInlineDetailRoute?
    @Binding var query: String

    var body: some View {
        BrowseView(
            collectionItems: collectionItems,
            filters: $filters,
            inlineDetailFilters: $inlineDetailFilters,
            gridOptions: $gridOptions,
            filterResultCount: $filterResultCount,
            filterEnergyOptions: $filterEnergyOptions,
            filterRarityOptions: $filterRarityOptions,
            filterTrainerTypeOptions: $filterTrainerTypeOptions,
            inlineDetailFilterResultCount: $inlineDetailFilterResultCount,
            inlineDetailFilterEnergyOptions: $inlineDetailFilterEnergyOptions,
            inlineDetailFilterRarityOptions: $inlineDetailFilterRarityOptions,
            inlineDetailFilterTrainerTypeOptions: $inlineDetailFilterTrainerTypeOptions,
            selectedTab: $selectedTab,
            inlineDetailRoute: $inlineDetailRoute,
            isMultiSelectActive: .constant(false),
            multiSelectedCardIDs: .constant([]),
            query: $query
        )
    }
}

/// Lazy wrapper so CollectView's three @Query properties (collectionItems, wishlistItems,
/// tradeListItems) are not instantiated — and their SwiftData fetches not executed — until
/// the Collect tab is first visited. Without this, TabView instantiates CollectView at
/// mainContent build time, blocking the main thread for several seconds.
private struct CollectTabView: View {
    @Binding var selectedSegment: CollectSegment
    @Binding var selectedContentTypeTab: CollectContentTypeTab
    @Binding var selectedBrand: TCGBrand?
    @Binding var collectionFilters: BrowseCardGridFilters
    @Binding var wishlistFilters: BrowseCardGridFilters
    @Binding var tradeListFilters: BrowseCardGridFilters
    @Binding var collectFilterEnergyOptions: [String]
    @Binding var collectFilterRarityOptions: [String]
    @Binding var collectFilterTrainerTypeOptions: [String]
    @Binding var gridOptions: BrowseGridOptions
    @Binding var folderGridOptions: BrowseGridOptions

    var body: some View {
        CollectView(
            selectedSegment: $selectedSegment,
            selectedContentTypeTab: $selectedContentTypeTab,
            selectedBrand: $selectedBrand,
            collectionFilters: $collectionFilters,
            wishlistFilters: $wishlistFilters,
            tradeListFilters: $tradeListFilters,
            collectFilterEnergyOptions: $collectFilterEnergyOptions,
            collectFilterRarityOptions: $collectFilterRarityOptions,
            collectFilterTrainerTypeOptions: $collectFilterTrainerTypeOptions,
            gridOptions: $gridOptions,
            folderGridOptions: $folderGridOptions
        )
    }
}

struct RootView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @State private var services = AppServices()
    @StateObject private var chromeScroll = ChromeScrollCoordinator()
    @State private var selectedTab: AppTab = .dashboard
    /// Drives the Collection / Wishlist segmented toggle inside `CollectView`. Owned here so the More tab's "Wishlist" quick-access can switch tab + segment together.
    @State private var collectSegment: CollectSegment = .collection
    @State private var collectContentTypeTab: CollectContentTypeTab = .cards
    @State private var universalQuery = ""
    @State private var showCardScanner = false
    @State private var browseFilters = BrowseFiltersSettings()
    @State private var browseFilterResultCount = 0
    @State private var browseFilterEnergyOptions: [String] = []
    @State private var browseFilterRarityOptions: [String] = []
    @State private var browseFilterTrainerTypeOptions: [String] = []
    @State private var browseInlineDetailFilterResultCount = 0
    @State private var browseInlineDetailFilterEnergyOptions: [String] = []
    @State private var browseInlineDetailFilterRarityOptions: [String] = []
    @State private var browseInlineDetailFilterTrainerTypeOptions: [String] = []
    @State private var browseHomeTab: BrowseHomeTab = .cards
    @State private var browseInlineDetailRoute: BrowseInlineDetailRoute?
    @State private var collectSelectedBrand: TCGBrand? = nil
    @State private var collectFilters = CollectionFiltersSettings()
    @State private var collectFilterEnergyOptions: [String] = []
    @State private var collectFilterRarityOptions: [String] = []
    @State private var collectFilterTrainerTypeOptions: [String] = []
    @State private var isSearchExperiencePresented = false
    /// When non-empty, user has pushed card / set / dex from search — hide root `UniversalSearchBar`; detail uses the same `NavigationStack` bar as Browse (`DexCardsView` / `SetCardsView`).
    @State private var searchNavigationPath = NavigationPath()
    /// Cards tab `NavigationStack` path — hide root chrome when a card detail (or other pushed screen) is showing.
    @State private var browseNavigationPath = NavigationPath()
    @State private var collectionNavigationPath = NavigationPath()
    @State private var moreNavigationPath = NavigationPath()
    @State private var selectedCardPresentation: CardPresentationContext?
    @State private var selectedSealedProductPresentation: SealedProductPresentationContext?
    @State private var cachedSetNameByCode: [String: String] = [:]
    @State private var inlineDetailCards: [Card] = []
    @State private var showCreateFolderAlert = false
    @State private var newFolderTitle = ""
    @State private var suppressMorePathReset = false
    @FocusState private var searchFieldFocused: Bool

    // Tabs are built lazily — only render their heavy content after first visit.
    // Dashboard is always built immediately (it's the landing tab).
    @State private var browseTabVisited = false
    @State private var collectTabVisited = false
    @State private var socialTabVisited = false
    @State private var moreTabVisited = false

    // MARK: - Premium upsell auto-popup
    // Weekly cadence (per the product spec). The upsell defers itself until
    // the launch sequence finishes, the splash is dismissed, and the user is
    // not currently mid-brand-onboarding — we don't want to greet a first-run
    // user with a paywall before they've even seen the dashboard.
    @State private var showPremiumAutoSheet = false
    @State private var showSocialFeaturesSheet = false
    @State private var hasEvaluatedPremiumUpsellThisSession = false
    private static let premiumUpsellLastShownKey = "bindr_premium_upsell_last_shown_at"
    private static let premiumUpsellIntervalSeconds: TimeInterval = 7 * 24 * 60 * 60

    // MARK: - One-shot onboarding replay
    // Bump the version suffix to re-trigger this for everyone (e.g. when we
    // ship the next major onboarding redesign). Each version key only fires
    // a single reset, so even if the user mashes "Skip" the flow doesn't
    // come back on subsequent launches.
    private static let onboardingReplayMigrationKey = "bindr_onboarding_replay_v3"

    // MARK: - Launch timing
    private let launchStart = ContinuousClock().now
    @State private var launchElapsedTenths: Int = 0
    @State private var launchTimerTask: Task<Void, Never>? = nil
    @State private var hasScheduledPostLaunchServices = false
    /// Shared handle for imperative CALayer fade — bypasses SwiftUI's updateUIView
    /// scheduling so CloudKit/@MainActor merges can't delay the overlay disappearing.
    @State private var launchFadeHandle = LaunchFadeHandle()

    private var launchElapsedLabel: String {
        String(format: "%.1fs", Double(launchElapsedTenths) / 10.0)
    }

    private func launchLog(_ msg: String) {
        let elapsed = ContinuousClock().now - launchStart
        let secs = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        print(String(format: "[Launch %.2fs] %@", secs, msg))
    }

    private func schedulePostLaunchServicesIfNeeded() {
        guard !hasScheduledPostLaunchServices else { return }
        hasScheduledPostLaunchServices = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)    // 3s: let launch fully settle
            guard !Task.isCancelled else { return }
            LaunchTraceProfiler.flushToFile()
            if services.brandSettings.hasCompletedBrandOnboarding {
                await services.socialPush.updateRegistrationState()
            }
            await services.setupWishlistAndLedger(modelContext: modelContext)
        }
    }

    // MARK: - Splash Flow
    @State private var showSplash: Bool = {
        let currentAppVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let splashLastVersionKey = "bindr_splash_last_shown_version"
        let lastShownVersion = UserDefaults.standard.string(forKey: splashLastVersionKey)
        return lastShownVersion == nil || lastShownVersion != currentAppVersion
    }()
    /// True while a first-run user is in the onboarding flow. The main app
    /// bootstraps in the background during onboarding; once complete we show
    /// the wordmark + progress until the pipeline finishes, then reveal the app.
    @State private var showOnboardingImmediate = false
    /// Flips once the BINDR letter-reveal stagger has played + breathing
    /// pulse has started. Distinct from "ready to dismiss" — the wordmark
    /// stays on screen until the catalog pipeline is also done so we never
    /// flash dashboard between the wordmark and the download UI.
    @State private var hasRevealedLaunchWordmark = false
    /// Flipped to true as soon as isLaunchSequenceComplete fires. mainContent is built immediately
    /// so SwiftUI can do the heavy layout work while the launch overlay is still covering it.
    @State private var hasInsertedMainContent = false
    /// Controls the launch overlay fade-out. Stays true until mainContent has been inserted AND
    /// a couple of frames have passed so the freeze from initial layout is fully hidden.
    @State private var isLaunchOverlayVisible = true
    /// Split from `isLaunchOverlayVisible` so hit testing can be disabled immediately
    /// when the fade starts, without waiting for `DispatchQueue.main.async` in the
    /// CALayer completion block. Without this, the overlay becomes invisible (opacity 0
    /// on the render server) but still intercepts touches for several seconds while the
    /// main thread is busy with post-launch work.
    @State private var isLaunchOverlayHitTestingEnabled = true
    /// Flipped by DashboardView once a value is ready to display (persisted snapshot or fresh compute).
    @State private var isDashboardDataReady = false
    @State private var dashboardLaunchStatus = "Loading your collection..."
    private let splashLastVersionKey = "bindr_splash_last_shown_version"

    /// Single gate for tearing the launch surface down.
    /// Kept minimal — only block on things that directly affect what the user sees
    /// at first paint. Push registration, wishlist, and ledger run after launch.
    private var isLaunchSequenceComplete: Bool {
        hasRevealedLaunchWordmark
            && services.isReady
            && services.isLaunchCatalogPipelineComplete
            && !showSplash
            && !showOnboardingImmediate
            && services.brandSettings.hasCompletedBrandOnboarding
            && isDashboardDataReady
            && services.isCloudKitImportComplete
    }

    private var launchProgressState: LaunchProgressState? {
        guard services.isReady else { return nil }

        if !services.isLaunchCatalogPipelineComplete,
           services.bootstrapShowsDownloadProgressUI {
            return LaunchProgressState(
                message: services.bootstrapMessage,
                status: services.bootstrapStatus,
                fraction: services.bootstrapProgress,
                downloadedBytes: services.bootstrapDownloadedBytes,
                totalBytes: services.bootstrapEstimatedTotalBytes,
                hasByteProgress: services.bootstrapShowsDownloadProgressUI
            )
        }

        if services.isLaunchCatalogPipelineComplete,
           services.isCloudKitImportComplete,
           !isDashboardDataReady,
           !showSplash,
           !showOnboardingImmediate,
           services.brandSettings.hasCompletedBrandOnboarding {
            return LaunchProgressState(
                message: "Preparing dashboard",
                status: dashboardLaunchStatus,
                fraction: 1,
                downloadedBytes: 0,
                totalBytes: 0,
                hasByteProgress: false
            )
        }

        return nil
    }

    /// First-launch (post-brand-onboarding) progress block. Shares the
    /// wordmark + progress visual with the returning-user path so the launch
    /// surface looks consistent across cold starts.
    private var brandOnboardingProgressState: LaunchProgressState? {
        guard services.brandSettings.hasCompletedBrandOnboarding,
              !services.brandSettings.hasCompletedInitialAppBootstrap else { return nil }
        return LaunchProgressState(
            message: services.bootstrapMessage,
            status: services.bootstrapStatus,
            fraction: services.bootstrapProgress,
            downloadedBytes: services.bootstrapDownloadedBytes,
            totalBytes: services.bootstrapEstimatedTotalBytes,
            hasByteProgress: services.bootstrapShowsDownloadProgressUI
        )
    }

    /// True when search has pushed into a detail view — hide the floating `UniversalSearchBar` (detail uses system nav, same as Browse Pokémon).
    private var isSearchDetailActive: Bool {
        isSearchExperiencePresented && !searchNavigationPath.isEmpty
    }

    /// Search open at root list: show chrome. Search with a pushed detail: hide chrome. Cards tab with a pushed detail: hide chrome. Else scroll-driven chrome on Browse.
    private var showUniversalSearchBar: Bool {
        if isSearchExperiencePresented { return true }
        if selectedTab == .social { return false }
        if selectedTab == .more { return false }
        if selectedTab == .collect && !collectionNavigationPath.isEmpty { return false }
        return chromeScroll.barsVisible
    }

    private var isBrowseGridFilterContextActive: Bool {
        selectedTab == .browse
            && browseNavigationPath.isEmpty
            && !isSearchExperiencePresented
            && (browseHomeTab == .cards || browseHomeTab == .products || browseInlineDetailRoute != nil)
    }

    private var isCollectFilterContextActive: Bool {
        selectedTab == .collect && collectionNavigationPath.isEmpty && collectSegment != .folders
    }

    private var activeCollectFilters: BrowseCardGridFilters {
        switch collectSegment {
        case .collection: return collectFilters.collectionFilters
        case .wishlist:   return collectFilters.wishlistFilters
        case .tradeList:  return collectFilters.tradeListFilters
        case .folders:    return BrowseCardGridFilters()
        }
    }

    private var activeCollectFiltersBinding: Binding<BrowseCardGridFilters> {
        switch collectSegment {
        case .collection: return $collectFilters.collectionFilters
        case .wishlist:   return $collectFilters.wishlistFilters
        case .tradeList:  return $collectFilters.tradeListFilters
        case .folders:    return .constant(BrowseCardGridFilters())
        }
    }

    private var isCollectFilterActive: Bool {
        collectSegment == .folders ? false : activeCollectFilters.isVisiblyCustomized
    }

    private var collectActiveBrand: TCGBrand {
        collectSelectedBrand ?? services.brandSettings.selectedCatalogBrand
    }

    private var isCollectAllBrands: Bool {
        false
    }

    private var chromeTrailingButton: (symbol: String, accessibilityLabel: String, action: () -> Void)? {
        if selectedTab == .collect && collectSegment == .folders && collectionNavigationPath.isEmpty {
            return ("folder.badge.plus", "Create folder", { showCreateFolderAlert = true })
        }
        switch selectedTab {
        case .dashboard: return ("gearshape", "Settings", {
            suppressMorePathReset = true
            moreNavigationPath = NavigationPath()
            moreNavigationPath.append(SideMenuPage.account)
            selectedTab = .more
        })
        default: return nil
        }
    }

    private var chromeExtraTrailingButton: (symbol: String, accessibilityLabel: String, action: () -> Void)? { nil }

    private var rootChromeTitle: String {
        if selectedTab == .browse, let browseInlineDetailRoute {
            return browseInlineDetailRoute.title
        }
        return selectedTab.title
    }

    private var activeBrowseFilters: BrowseCardGridFilters {
        browseInlineDetailRoute == nil
            ? activeBrowseTabFiltersBinding.wrappedValue
            : activeBrowseTabInlineFiltersBinding.wrappedValue
    }

    private var activeBrowseFiltersBinding: Binding<BrowseCardGridFilters> {
        browseInlineDetailRoute == nil ? activeBrowseTabFiltersBinding : activeBrowseTabInlineFiltersBinding
    }

    private var sharedBrowseGridOptionsBinding: Binding<BrowseGridOptions> {
        Binding(
            get: { services.browseGridOptions.options },
            set: { services.browseGridOptions.options = $0 }
        )
    }

    private var activeBrowseGridOptionsBinding: Binding<BrowseGridOptions> {
        if browseHomeTab == .products, browseInlineDetailRoute == nil {
            return $browseFilters.productsGridOptions
        }
        return sharedBrowseGridOptionsBinding
    }

    private var activeBrowseTabFiltersBinding: Binding<BrowseCardGridFilters> {
        switch browseHomeTab {
        case .cards:
            return $browseFilters.cardsFilters
        case .sets:
            return $browseFilters.setsFilters
        case .pokemon:
            return $browseFilters.pokemonFilters
        case .products:
            return $browseFilters.productsFilters
        }
    }

    private var activeBrowseTabInlineFiltersBinding: Binding<BrowseCardGridFilters> {
        switch browseHomeTab {
        case .cards:
            return $browseFilters.cardsInlineFilters
        case .sets:
            return $browseFilters.setsInlineFilters
        case .pokemon:
            return $browseFilters.pokemonInlineFilters
        case .products:
            return $browseFilters.productsInlineFilters
        }
    }

    private var activeBrowseFilterEnergyOptions: [String] {
        browseFilterEnergyOptions
    }

    private var activeBrowseFilterRarityOptions: [String] {
        browseFilterRarityOptions
    }

    private var activeBrowseFilterTrainerTypeOptions: [String] {
        browseFilterTrainerTypeOptions
    }

    var body: some View {
        ZStack {
            // Main content — inserted early (on isReady) so the tab tree layout
            // happens while the overlay is fully opaque.
            if hasInsertedMainContent {
                mainContent
            } else {
                Color(uiColor: .systemBackground)
            }

            // Launch overlay — uses a CALayer fade so the animation runs on the
            // render server and cannot be stalled by @MainActor work (CloudKit, SwiftData).
            // launchFadeHandle lets onChange(of: isLaunchSequenceComplete) trigger the
            // fade imperatively, bypassing SwiftUI's updateUIView scheduling delay.
            RenderThreadFadeContainer(
                content: launchOverlayContent,
                isVisible: isLaunchOverlayVisible,
                duration: 0.45,
                onFadeComplete: {
                    // Fallback path (isVisible flipped directly rather than via handle).
                    // Timer is already cancelled before the fade starts (see onChange above).
                    launchLog("overlay fade complete (fallback path) — app is ready")
                    Task { @MainActor in
                        isLaunchOverlayVisible = false
                        services.runDeferredLaunchServicesIfNeeded()
                        evaluatePremiumUpsellIfNeeded()
                        schedulePostLaunchServicesIfNeeded()
                    }
                },
                handle: launchFadeHandle
            )
            .allowsHitTesting(isLaunchOverlayHitTestingEnabled)
            .ignoresSafeArea()
            .zIndex(1)
        }
        .onChange(of: services.isReady) { _, ready in
            launchLog("services.isReady → \(ready)")
            if ready && !hasInsertedMainContent {
                launchLog("inserting mainContent (isReady)")
                hasInsertedMainContent = true
                services.setupCollectionValue(modelContext: modelContext)
            }
        }
        .onChange(of: services.isCloudKitImportComplete) { _, complete in
            launchLog("isCloudKitImportComplete → \(complete)")
        }
        .onChange(of: hasRevealedLaunchWordmark) { _, revealed in
            launchLog("hasRevealedLaunchWordmark → \(revealed)")
        }
        .onChange(of: services.isLaunchCatalogPipelineComplete) { _, complete in
            launchLog("isLaunchCatalogPipelineComplete → \(complete)")
        }
        .onChange(of: hasInsertedMainContent) { _, inserted in
            if inserted { launchLog("mainContent inserted") }
        }
        .onChange(of: isDashboardDataReady) { _, ready in
            if ready { launchLog("isDashboardDataReady → true") }
        }
        .onChange(of: isLaunchSequenceComplete) { _, complete in
            if complete {
                launchLog("isLaunchSequenceComplete — fading overlay")
                LaunchTraceProfiler.mark("isLaunchSequenceComplete — fading overlay")
                // Stop the 100ms elapsed-time timer BEFORE starting the CALayer fade.
                // The timer mutates @State (launchElapsedTenths) every 100ms, causing
                // RootView.body to re-evaluate. During a 450ms fade that means 4–5
                // spurious full body re-renders while SwiftUI is also compositing the
                // fade animation — visibly janky on devices with large collections.
                launchTimerTask?.cancel()
                launchTimerTask = nil

                // Disable hit-testing immediately so the dashboard is interactive
                // even before the fade animation completes. The CALayer fade runs on
                // the render server and its completion is dispatched via
                // DispatchQueue.main.async — if the main thread is blocked by post-load
                // work, the overlay stays invisible but still intercepts touches for
                // several seconds. Flipping hit-testing here avoids that gap entirely.
                isLaunchOverlayHitTestingEnabled = false
                LaunchTraceProfiler.mark("hit-testing disabled")

                // Trigger the CALayer fade imperatively — this starts the animation on
                // the render server immediately without touching any SwiftUI @State.
                // isLaunchOverlayVisible is NOT flipped here: doing so would schedule
                // a full SwiftUI body re-render right as CloudKit's @Query results land,
                // causing a multi-second main-thread freeze proportional to collection size.
                // It is flipped in the completion block instead, after the fade is done
                // and the overlay is being removed from the hit-test tree.
                launchLog("isLaunchSequenceComplete — calling triggerFadeIfNeeded")
                launchFadeHandle.triggerFadeIfNeeded(
                    duration: 0.45,
                    completion: {
                        launchLog("overlay fade complete — app is ready")
                        LaunchTraceProfiler.mark("overlay fade complete")
                        Task { @MainActor in
                            // Flip the fallback flag now that the fade is visually done.
                            // This is the first @State mutation after launch — SwiftUI's
                            // body re-render happens here instead of mid-fade.
                            isLaunchOverlayVisible = false
                            services.runDeferredLaunchServicesIfNeeded()
                            evaluatePremiumUpsellIfNeeded()
                            schedulePostLaunchServicesIfNeeded()
                        }
                    }
                )
            }
        }
        .onChange(of: showSplash) { _, presented in
            if !presented { evaluatePremiumUpsellIfNeeded() }
        }
        .environment(\.offlineImageContext, OfflineImageContext(
            isOfflineEnabled: services.offlineImageSettings.isOfflinePackEnabled(
                for: services.brandSettings.selectedCatalogBrand
            ),
            brand: services.brandSettings.selectedCatalogBrand,
            packDataRevision: services.offlineImageDownload.packDataRevision
        ))
        .environment(services)
        .environmentObject(chromeScroll)
        .environment(\.presentCard, { card, list in
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            let idx = list.firstIndex(where: { $0.id == card.id }) ?? 0
            selectedCardPresentation = CardPresentationContext(cards: list, startIndex: idx)
        })
        .environment(\.presentCardAtIndex, { list, index in
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            let safeIndex = min(max(index, 0), max(list.count - 1, 0))
            selectedCardPresentation = CardPresentationContext(cards: list, startIndex: safeIndex)
        })
        .environment(\.presentSealedProduct, { _, list, index in
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            let safeIndex = min(max(index, 0), max(list.count - 1, 0))
            selectedSealedProductPresentation = SealedProductPresentationContext(products: list, startIndex: safeIndex)
        })
        .task {
            // Start watching for CloudKit's initial import event immediately —
            // before any other launch work so the monitor is registered before
            // the notification fires.
            LaunchTraceProfiler.begin("beginCloudKitReadinessMonitoring")
            services.beginCloudKitReadinessMonitoring()
            LaunchTraceProfiler.end("beginCloudKitReadinessMonitoring")
            if services.isReady && !hasInsertedMainContent {
                launchLog("inserting mainContent immediately (already ready at launch)")
                hasInsertedMainContent = true
                services.setupCollectionValue(modelContext: modelContext)
            }
        }
        .task {
            // ── Cheap, immediate work ─────────────────────────────────────
            // Replay-onboarding migration: run before we read brandSettings
            // anywhere else this launch so the `.onChange` that opens
            // `BindrOnboardingFlow` fires with the freshly-reset flag.
            applyOnboardingReplayMigrationIfNeeded()

            if !services.brandSettings.hasCompletedBrandOnboarding {
                showSplash = true
            } else {
                // Determine splash — just a UserDefaults read, safe to run now.
                let lastShownVersion = UserDefaults.standard.string(forKey: splashLastVersionKey)
                let shouldShowSplash = lastShownVersion == nil || lastShownVersion != currentAppVersion
                if shouldShowSplash {
                    showSplash = true
                }
            }

            // ── Bootstrap strategy depends on launch path ─────────────────
            //
            // First-run: user is shown splash → onboarding → wordmark+progress.
            //   - Wait for splash to dismiss, then kick off bootstrap immediately
            //     so the catalog is being fetched while the user is in onboarding.
            //   - After onboarding finishes (showOnboardingImmediate → false), the
            //     wordmark appears. Wait for its reveal before catalog pipeline work.
            //
            // Returning-user: wordmark shows immediately after splash.
            //   - Wait for the BINDR letter reveal (~1.8 s) to avoid hitching the
            //     animation, then run the catalog pipeline.

            launchLog("root .task started")
            LaunchTraceProfiler.mark("RootView.task launched")
            launchTimerTask = Task { @MainActor in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    launchElapsedTenths += 1
                }
            }

            // Wait for the splash to be dismissed (user tapped GET STARTED).
            while showSplash {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            launchLog("splash dismissed")
            LaunchTraceProfiler.mark("splash dismissed")
            await Task.yield()

            if showOnboardingImmediate {
                // First-run: bootstrap in background while user goes through onboarding.
                if !services.brandSettings.hasCompletedInitialAppBootstrap {
                    launchLog("bootstrap() starting (first-run)")
                    LaunchTraceProfiler.begin("bootstrap (first-run)")
                    await services.bootstrap()
                    LaunchTraceProfiler.end("bootstrap (first-run)")
                    launchLog("bootstrap() done")
                }
                // Wait for onboarding to finish — wordmark appears afterward.
                while showOnboardingImmediate {
                    try? await Task.sleep(nanoseconds: 50_000_000)
                }
                launchLog("onboarding dismissed")
            }

            // Wait for the wordmark reveal before kicking off catalog work.
            while !hasRevealedLaunchWordmark {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            launchLog("wordmark revealed — starting catalog pipeline")
            LaunchTraceProfiler.mark("wordmark revealed")
            await Task.yield()

            if services.isReady {
                launchLog("bootstrapCatalogInBackgroundIfNeeded starting")
                LaunchTraceProfiler.begin("bootstrapCatalogInBackgroundIfNeeded")
                await services.bootstrapCatalogInBackgroundIfNeeded()
                LaunchTraceProfiler.end("bootstrapCatalogInBackgroundIfNeeded")
                launchLog("bootstrapCatalogInBackgroundIfNeeded done")
            }
            // Push registration and wishlist/ledger setup are intentionally scheduled
            // from the overlay fade completion, with a short post-launch delay, so
            // they cannot compete with the first tappable dashboard frame.
            // Cold-launch tap: if the AppDelegate's `didReceive` fired
            // before `AppServices` was constructed, the buffer drain in
            // `SocialPushService.init` already populated
            // `queuedDeepLinkURL`. `.onChange` only observes *changes*
            // after attachment, so it would miss this initial value.
            // Pick it up explicitly here.
            if let queuedURL = services.socialPush.queuedDeepLinkURL,
               queuedURL.scheme?.lowercased() == "bindr" {
                selectedTab = .social
                await services.socialAuth.restoreSession()
            }
        }
        .bindrTheme(accent: services.theme.accentColor)
        .preferredColorScheme(services.theme.colorScheme)
    }

    /// Current app version string (e.g., "1.2.3")
    private var currentAppVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var chromeSearchBarTopInset: CGFloat { RootChromeEnvironment.searchBarTopInset }
    private var chromeSearchBarBottomInset: CGFloat { RootChromeEnvironment.searchBarBottomInset }
    private var chromeFloatingInset: CGFloat { RootChromeEnvironment.floatingContentTopInset }
    private var chromeSearchBarHiddenOffset: CGFloat { -(chromeFloatingInset + 18) }
    private var chromeContentTopInset: CGFloat { isSearchDetailActive ? 0 : chromeFloatingInset }

    @ViewBuilder
    private var launchOverlayContent: some View {
        if showSplash {
            SplashView(onGetStarted: {
                UserDefaults.standard.set(currentAppVersion, forKey: splashLastVersionKey)
                withAnimation(.easeInOut(duration: 0.35)) {
                    showSplash = false
                    if !services.brandSettings.hasCompletedBrandOnboarding {
                        showOnboardingImmediate = true
                    }
                }
            })
        } else if showOnboardingImmediate {
            BindrOnboardingFlow(
                isPresented: .constant(true),
                onWillDismiss: {
                    showOnboardingImmediate = false
                    Task { await services.socialPush.updateRegistrationState() }
                }
            )
            .environment(services)
            .bindrTheme(accent: services.theme.accentColor)
        } else if services.isReady {
            LaunchWordmarkView(
                progress: launchProgressState,
                isSyncingCloudKit: hasRevealedLaunchWordmark && !services.isCloudKitImportComplete && launchProgressState == nil,
                onRevealComplete: { hasRevealedLaunchWordmark = true },
                elapsedLabel: launchElapsedLabel
            )
        } else {
            LaunchWordmarkView(
                progress: brandOnboardingProgressState,
                onRevealComplete: { hasRevealedLaunchWordmark = true },
                elapsedLabel: launchElapsedLabel
            )
            .task {
                guard !services.brandSettings.hasCompletedInitialAppBootstrap else { return }
                await services.bootstrap()
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        ZStack(alignment: .top) {
            ZStack(alignment: .top) {
                    TabView(selection: $selectedTab) {
                        NavigationStack {
                            DashboardView(onViewAllActivity: {
                                suppressMorePathReset = true
                                moreNavigationPath = NavigationPath()
                                moreNavigationPath.append(SideMenuPage.transactions)
                                selectedTab = .more
                            }, onOpenScanner: {
                                showCardScanner = true
                            }, onOpenCollection: {
                                collectionNavigationPath = NavigationPath()
                                collectSegment = .collection
                                collectContentTypeTab = .cards
                                selectedTab = .collect
                            }, onOpenSealedProducts: {
                                collectionNavigationPath = NavigationPath()
                                collectSegment = .collection
                                collectContentTypeTab = .products
                                selectedTab = .collect
                            }, onOpenWishlist: {
                                collectionNavigationPath = NavigationPath()
                                collectSegment = .wishlist
                                collectContentTypeTab = .cards
                                selectedTab = .collect
                            }, onOpenBrowse: {
                                suppressMorePathReset = true
                                moreNavigationPath = NavigationPath()
                                moreNavigationPath.append(SideMenuPage.decks)
                                selectedTab = .more
                            }, onInitialLoadStatusChange: { status in
                                dashboardLaunchStatus = status
                            }, onInitialLoadComplete: {
                                isDashboardDataReady = true
                            })
                        }
                        .toolbarBackground(.hidden, for: .navigationBar)
                        .tabItem { Label(AppTab.dashboard.title, systemImage: AppTab.dashboard.symbolName) }
                        .tag(AppTab.dashboard)

                        NavigationStack(path: $browseNavigationPath) {
                            if browseTabVisited {
                                BrowseTabView(
                                    filters: activeBrowseTabFiltersBinding,
                                    inlineDetailFilters: activeBrowseTabInlineFiltersBinding,
                                    gridOptions: activeBrowseGridOptionsBinding,
                                    filterResultCount: $browseFilterResultCount,
                                    filterEnergyOptions: $browseFilterEnergyOptions,
                                    filterRarityOptions: $browseFilterRarityOptions,
                                    filterTrainerTypeOptions: $browseFilterTrainerTypeOptions,
                                    inlineDetailFilterResultCount: $browseInlineDetailFilterResultCount,
                                    inlineDetailFilterEnergyOptions: $browseInlineDetailFilterEnergyOptions,
                                    inlineDetailFilterRarityOptions: $browseInlineDetailFilterRarityOptions,
                                    inlineDetailFilterTrainerTypeOptions: $browseInlineDetailFilterTrainerTypeOptions,
                                    selectedTab: $browseHomeTab,
                                    inlineDetailRoute: $browseInlineDetailRoute,
                                    query: $universalQuery
                                )
                            } else {
                                Color.clear
                            }
                        }
                        .toolbarBackground(.hidden, for: .navigationBar)
                        .tabItem { Label(AppTab.browse.title, systemImage: AppTab.browse.symbolName) }
                        .tag(AppTab.browse)

                        NavigationStack(path: $collectionNavigationPath) {
                            if collectTabVisited {
                                CollectTabView(
                                    selectedSegment: $collectSegment,
                                    selectedContentTypeTab: $collectContentTypeTab,
                                    selectedBrand: $collectSelectedBrand,
                                    collectionFilters: $collectFilters.collectionFilters,
                                    wishlistFilters: $collectFilters.wishlistFilters,
                                    tradeListFilters: $collectFilters.tradeListFilters,
                                    collectFilterEnergyOptions: $collectFilterEnergyOptions,
                                    collectFilterRarityOptions: $collectFilterRarityOptions,
                                    collectFilterTrainerTypeOptions: $collectFilterTrainerTypeOptions,
                                    gridOptions: $collectFilters.gridOptions,
                                    folderGridOptions: $collectFilters.folderGridOptions
                                )
                            } else {
                                Color.clear
                            }
                        }
                        .toolbarBackground(.hidden, for: .navigationBar)
                        .tabItem { Label(AppTab.collect.title, systemImage: AppTab.collect.symbolName) }
                        .tag(AppTab.collect)

                        NavigationStack {
                            if socialTabVisited {
                                SocialRootView()
                            } else {
                                Color.clear
                            }
                        }
                        .toolbarBackground(.hidden, for: .navigationBar)
                        .tabItem { Label(AppTab.social.title, systemImage: AppTab.social.symbolName) }
                        .tag(AppTab.social)

                        NavigationStack(path: $moreNavigationPath) {
                            if moreTabVisited {
                                MoreView(navigationPath: $moreNavigationPath)
                            } else {
                                Color.clear
                            }
                        }
                        .toolbarBackground(.hidden, for: .navigationBar)
                        .tabItem { Label(AppTab.more.title, systemImage: AppTab.more.symbolName) }
                        .tag(AppTab.more)
                    }
                    .bindrDisableTabBarMinimize()
                    if isSearchExperiencePresented {
                        Color.black.opacity(colorScheme == .light ? 0.28 : 0.45)
                            .ignoresSafeArea(edges: .bottom)
                            .onTapGesture {
                                searchNavigationPath = NavigationPath()
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                                    isSearchExperiencePresented = false
                                }
                                searchFieldFocused = false
                            }

                        NavigationStack(path: $searchNavigationPath) {
                            SearchExperienceView(query: $universalQuery)
                            .navigationDestination(for: SearchNavRoot.self) { root in
                                switch root {
                                case .set(let s, let brand):
                                    SetCardsView(set: s)
                                        .onAppear {
                                            services.brandSettings.selectedCatalogBrand = brand
                                            searchFieldFocused = false
                                        }
                                case .dex(let dexId, let displayName, let brand):
                                    DexCardsView(dexId: dexId, displayName: displayName)
                                        .onAppear {
                                            services.brandSettings.selectedCatalogBrand = brand
                                            searchFieldFocused = false
                                        }
                                case .onePieceCharacter(let name, let brand):
                                    OnePieceCharacterCardsView(characterName: name)
                                        .onAppear {
                                            services.brandSettings.selectedCatalogBrand = brand
                                            searchFieldFocused = false
                                        }
                                case .onePieceSubtype(let name, let brand):
                                    OnePieceSubtypeCardsView(subtypeName: name)
                                        .onAppear {
                                            services.brandSettings.selectedCatalogBrand = brand
                                            searchFieldFocused = false
                                        }
                                }
                            }
                        }
                        .environment(\.presentCard, { card, list in
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            let idx = list.firstIndex(where: { $0.id == card.id }) ?? 0
                            selectedCardPresentation = CardPresentationContext(cards: list, startIndex: idx)
                        })
                        .environment(\.presentCardAtIndex, { list, index in
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            let safeIndex = min(max(index, 0), max(list.count - 1, 0))
                            selectedCardPresentation = CardPresentationContext(cards: list, startIndex: safeIndex)
                        })
                        .environment(\.presentSealedProduct, { _, list, index in
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            let safeIndex = min(max(index, 0), max(list.count - 1, 0))
                            selectedSealedProductPresentation = SealedProductPresentationContext(products: list, startIndex: safeIndex)
                        })
                        .toolbarBackground(.hidden, for: .navigationBar)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .background {
                            if searchNavigationPath.isEmpty {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(.regularMaterial)
                            }
                        }
                        .padding(.horizontal, searchNavigationPath.isEmpty ? 12 : 0)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(2)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.spring(response: 0.38, dampingFraction: 0.88), value: isSearchExperiencePresented)
                .environment(\.rootFloatingChromeInset, chromeContentTopInset)

                // Floating above tab content so `.ultraThinMaterial` / Liquid Glass blur the grid behind the bar.
                floatingSearchBar(hiddenOffset: chromeSearchBarHiddenOffset, topInset: chromeSearchBarTopInset, bottomInset: chromeSearchBarBottomInset)
                    .sheet(isPresented: $showPremiumAutoSheet) {
                        // Same `PaywallSheet` wrapper everywhere else uses,
                        // so the user-initiated path and the auto-popup path
                        // render the exact same `PremiumUpgradeView` body.
                        PaywallSheet()
                            .environment(services)
                            .bindrTheme(accent: services.theme.accentColor)
                            .presentationDetents([.large])
                            .presentationDragIndicator(.visible)
                    }
                    .sheet(isPresented: $showSocialFeaturesSheet) {
                        NavigationStack {
                            SocialLandingView(
                                currentNonce: .constant(nil),
                                errorMessage: nil,
                                headerInset: 0,
                                onSignInResult: { _ in }
                            )
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("Done") { showSocialFeaturesSheet = false }
                                        .glassToolbarButton()
                                }
                            }
                        }
                        .presentationDetents([.large])
                        .presentationDragIndicator(.visible)
                    }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Shared app backdrop shows through translucent chrome/material.
        .bindrPageBackground()
        .overlay {
            if services.isCatalogDownloadInProgress {
                ZStack {
                    Color.black.opacity(0.48)
                        .ignoresSafeArea()
                    if services.catalogDownloadShowsByteProgressUI {
                        LoadingScreen(
                            message: services.catalogDownloadMessage,
                            status: services.catalogDownloadStatus,
                            progress: services.catalogDownloadProgress,
                            downloadedBytes: services.catalogDownloadDownloadedBytes,
                            totalBytes: services.catalogDownloadEstimatedTotalBytes
                        )
                    } else {
                        CatalogEnablingBusyView(
                            message: services.catalogDownloadMessage,
                            status: services.catalogDownloadStatus
                        )
                    }
                }
                .transition(.opacity)
                .zIndex(500)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: services.isCatalogDownloadInProgress)
        .overlay {
            if selectedCardPresentation != nil || selectedSealedProductPresentation != nil || services.isSealedDetailPresentationActive {
                BindrPageBackground()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(
            .easeInOut(duration: 0.25),
            value: selectedCardPresentation != nil || selectedSealedProductPresentation != nil || services.isSealedDetailPresentationActive
        )
        .onChange(of: searchFieldFocused) { _, isFocused in
            if isFocused {
                Haptics.lightImpact()
                if !isSearchExperiencePresented {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) {
                        isSearchExperiencePresented = true
                    }
                }
            }
        }
        .onAppear {
            launchLog("mainContent .onAppear")
            chromeScroll.configureForTab(selectedTab)
            collectSelectedBrand = services.brandSettings.selectedCatalogBrand
            // setupCollectionValue is called from onChange(of: services.isReady) which
            // fires before mainContent is inserted. Call here only as a safety net for
            // any code path where isReady was already true before onAppear.
            if services.collectionValue == nil {
                launchLog("setupCollectionValue (onAppear fallback)")
                services.setupCollectionValue(modelContext: modelContext)
            }
        }
        .onChange(of: selectedTab) { _, tab in
            Haptics.selectionChanged()
            chromeScroll.configureForTab(tab)
            switch tab {
            case .browse:  browseTabVisited = true
            case .collect: collectTabVisited = true
            case .social:  socialTabVisited = true
            case .more:    moreTabVisited = true
            case .dashboard: break
            }
            if tab == .collect {
                collectionNavigationPath = NavigationPath()
            }
            if tab == .social {
                services.socialFeed.clearUnreadState()
                services.socialPush.clearAppBadgeCount()
            }
            if tab == .more {
                if suppressMorePathReset {
                    suppressMorePathReset = false
                } else {
                    moreNavigationPath = NavigationPath()
                }
            }
        }
        .onChange(of: browseNavigationPath.count) { _, newCount in
            if newCount == 0 {
                chromeScroll.forceVisible()
            }
        }
        .onChange(of: isSearchExperiencePresented) { _, open in
            if open {
                chromeScroll.forceVisible()
            } else {
                searchNavigationPath = NavigationPath()
            }
        }
        .onChange(of: services.brandSettings.selectedCatalogBrand) { _, brand in
            browseNavigationPath = NavigationPath()
            collectionNavigationPath = NavigationPath()
            searchNavigationPath = NavigationPath()
            browseHomeTab = .cards
            browseInlineDetailRoute = nil
            selectedCardPresentation = nil
            universalQuery = ""
            searchFieldFocused = false
            collectSelectedBrand = brand
        }
        .onChange(of: services.socialAuth.authState) { _, _ in
            Task {
                await services.socialPush.updateRegistrationState()
            }
        }
        .onOpenURL { url in
            handleSocialDeepLink(url)
        }
        .onChange(of: services.socialPush.queuedDeepLinkURL) { _, queuedURL in
            guard let queuedURL else { return }
            handleSocialDeepLink(queuedURL)
        }
        .sheet(item: $selectedCardPresentation) { ctx in
            let isCollectCards = selectedTab == .collect && collectContentTypeTab == .cards
            let showTradeFlow = isCollectCards && collectSegment == .wishlist
            CardDetailSheet(
                cards: ctx.cards,
                startIndex: ctx.startIndex,
                tradeAction: showTradeFlow ? { card, _ in
                    launchTradeFlowFromCollectionCard(card)
                } : nil,
                tradeActionLabel: "Trade"
            )
            .environment(services)
        }
        .sheet(item: $selectedSealedProductPresentation) { ctx in
            if ctx.products.isEmpty {
                ContentUnavailableView("No product", systemImage: "shippingbox")
            } else {
                SealedProductBrowseDetailView(
                    products: ctx.products,
                    startProductID: ctx.products[min(max(ctx.startIndex, 0), max(ctx.products.count - 1, 0))].id
                )
                .environment(services)
            }
        }
        .alert("New Folder", isPresented: $showCreateFolderAlert) {
            TextField("Folder name", text: $newFolderTitle)
            Button("Create") {
                let title = newFolderTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty {
                    let folder = CardFolder(title: title)
                    modelContext.insert(folder)
                    try? modelContext.save()
                }
                newFolderTitle = ""
            }
            Button("Cancel", role: .cancel) { newFolderTitle = "" }
        }
        .fullScreenCover(isPresented: $showCardScanner) {
            CardScannerView(
                onMatch: { card in
                    showCardScanner = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        selectedCardPresentation = CardPresentationContext(cards: [card], startIndex: 0)
                    }
                },
                onDismiss: {
                    showCardScanner = false
                }
            )
            .environment(services)
        }
        // `.bindrTheme` injects the accent into both `\.bindrAccent` (read by
        // `BindrPalette` consumers and any view using the new env-based
        // approach) and SwiftUI's `\.tint` (read by Buttons, Toggles, etc.).
        // Single source of truth replaces the prior split between
        // `Color.accentColor` (asset, didn't track theme) and
        // `services.theme.accentColor` scattered across 24 files.
        .bindrTheme(accent: services.theme.accentColor)
    }

    @ViewBuilder
    private func floatingSearchBar(hiddenOffset: CGFloat, topInset: CGFloat, bottomInset: CGFloat) -> some View {
        let visible = showUniversalSearchBar && !isSearchDetailActive
        let browseLeadingButton: (symbol: String, accessibilityLabel: String, action: () -> Void)? =
            selectedTab == .browse && browseInlineDetailRoute != nil
            ? ("chevron.left", "Back", {
                browseInlineDetailRoute = nil
            })
            : nil
        let filterEnabled = isBrowseGridFilterContextActive || isCollectFilterContextActive
        let filterActive = isBrowseGridFilterContextActive ? activeBrowseFilters.isVisiblyCustomized
                         : isCollectFilterContextActive ? isCollectFilterActive : false
        let filterContent: AnyView? = isBrowseGridFilterContextActive ? AnyView(browseFilterMenuContent)
                                    : isCollectFilterContextActive ? AnyView(collectFilterMenuContent) : nil
        UniversalSearchBar(
            text: $universalQuery,
            isFocused: $searchFieldFocused,
            title: rootChromeTitle,
            isSearchOpen: isSearchExperiencePresented,
            isFilterEnabled: filterEnabled,
            isFilterActive: filterActive,
            filterMenuContent: filterContent,
            collapsedLeadingButton: browseLeadingButton,
            trailingButton: chromeTrailingButton,
            extraTrailingButton: chromeExtraTrailingButton,
            onActivateSearch: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                    isSearchExperiencePresented = true
                }
                Task { @MainActor in
                    await Task.yield()
                    searchFieldFocused = true
                }
            },
            onBack: {
                searchNavigationPath = NavigationPath()
                universalQuery = ""
                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                    isSearchExperiencePresented = false
                }
                searchFieldFocused = false
            },
            onCamera: {
                searchFieldFocused = false
                showCardScanner = true
            },
            onFilter: {
                searchFieldFocused = false
            }
        )
        .frame(maxWidth: .infinity)
        .offset(y: visible ? 0 : hiddenOffset)
        .opacity(visible ? 1 : 0.001)
        .padding(.horizontal, 16)
        .padding(.top, topInset)
        .padding(.bottom, bottomInset)
        .frame(maxWidth: .infinity, alignment: .top)
        .allowsHitTesting(visible)
        .animation(.easeInOut(duration: 0.22), value: chromeScroll.barsVisible)
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: isSearchExperiencePresented)
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: isSearchDetailActive)
    }

    @ViewBuilder
    private func floatingTabBar() -> some View {
        let visible = chromeScroll.barsVisible && !isSearchExperiencePresented && !isSearchDetailActive
        
        VStack(spacing: 0) {
            Spacer()
            HStack(spacing: 0) {
                ForEach(AppTab.visibleTabs) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: selectedTab == tab ? tab.symbolName : tab.symbolName.replacingOccurrences(of: ".fill", with: ""))
                                .font(.system(size: 20, weight: .medium))
                                .bindrBadge(count: tab == .social ? services.socialFeed.unreadAlertsCount : 0)
                            
                            Text(tab.title)
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(selectedTab == tab ? services.theme.accentColor : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .glassCardStyle(cornerRadius: 32)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .offset(y: visible ? 0 : 150)
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: visible)
    }

    @ViewBuilder
    private var collectFilterMenuContent: some View {
        let showSealedProductTypeFilter = collectContentTypeTab == .products
        let collectConfig = showSealedProductTypeFilter
            ? FilterMenuConfig.products
            : FilterMenuConfig(
                showAcquiredDateSort: true,
                showRandomSort: false,
                showCardNumberSort: false,
                showHideOwned: false,
                showShowDuplicates: true,
                showGridOptions: true,
                defaultSortBy: .price
            )
        BrowseGridFiltersMenuContent(
            brand: collectActiveBrand,
            filters: activeCollectFiltersBinding,
            energyOptions: collectFilterEnergyOptions,
            rarityOptions: collectFilterRarityOptions,
            trainerTypeOptions: collectFilterTrainerTypeOptions,
            isAllBrands: isCollectAllBrands,
            gridOptions: $collectFilters.gridOptions,
            config: collectConfig
        )
    }

    @ViewBuilder
    private var browseFilterMenuContent: some View {
        let isSealedTab = browseHomeTab == .products
        let defaultSortBy: BrowseCardGridSortOption = {
            if let route = browseInlineDetailRoute {
                switch route {
                case .set(_):
                    return .cardNumber
                case .dex(_, _), .onePieceCharacter(_), .onePieceSubtype(_):
                    return .newestSet
                }
            }
            switch browseHomeTab {
            case .sets:
                return .cardNumber
            case .pokemon, .products:
                return .newestSet
            case .cards:
                return .random
            }
        }()

        let browseConfig = FilterMenuConfig(defaultSortBy: defaultSortBy)

        BrowseGridFiltersMenuContent(
            brand: services.brandSettings.selectedCatalogBrand,
            filters: activeBrowseFiltersBinding,
            energyOptions: activeBrowseFilterEnergyOptions,
            rarityOptions: activeBrowseFilterRarityOptions,
            trainerTypeOptions: activeBrowseFilterTrainerTypeOptions,
            isAllBrands: false,
            gridOptions: isSealedTab ? $browseFilters.productsGridOptions : nil,
            config: isSealedTab ? .products : browseConfig
        )
    }

    private func launchTradeFlowFromCollectionCard(_ card: Card) {
        let preferredSide: AppServices.TradePrefillSide = {
            switch collectSegment {
            case .collection:
                return .mySide
            case .wishlist:
                return .theirSide
            case .tradeList:
                return .mySide
            case .folders:
                return .mySide
            }
        }()
        services.pendingTradeSeed = AppServices.PendingTradeSeed(
            cardID: card.masterCardId,
            preferredSide: preferredSide
        )
        selectedCardPresentation = nil
        Haptics.mediumImpact()
        if let url = URL(string: "bindr://social/friends") {
            services.socialPush.queueDeepLink(url: url)
        }
        selectedTab = .social
    }

    private func handleSocialDeepLink(_ url: URL) {
        guard url.scheme?.lowercased() == "bindr" else { return }
        if services.socialPush.queuedDeepLinkURL != url {
            services.socialPush.queueDeepLink(url: url)
        }
        selectedTab = .social
        Task {
            await services.socialAuth.restoreSession()
        }
    }

    // MARK: - Premium upsell gate

    /// Decide whether to surface the weekly Premium upsell sheet this session.
    ///
    /// All gates must pass:
    ///   * Launch sequence has fully finished (so the user has actually
    ///     seen the dashboard before we paywall them).
    ///   * No higher-priority modal is on screen (splash, brand onboarding).
    ///   * The user is not already Premium.
    ///   * At least 7 days have elapsed since the last shown timestamp.
    ///   * We haven't already evaluated *and shown* it earlier this session
    ///     — re-running this with `hasEvaluatedPremiumUpsellThisSession`
    ///     true is a no-op so multiple `.onChange` triggers don't flicker
    ///     the sheet.
    ///
    /// First-launch behaviour: if there's no stored timestamp we treat
    /// "now" as the seed. The user therefore won't see the upsell until
    /// 7 days after their *first* successful launch — they get a full
    /// week to explore before any paywall pressure.
    private func evaluatePremiumUpsellIfNeeded() {
        guard !hasEvaluatedPremiumUpsellThisSession else { return }
        guard !services.store.isPremium else { return }
        // Only mark as evaluated (and potentially show) once the full launch
        // sequence is done — never over the BINDR wordmark or splash screen.
        guard isLaunchSequenceComplete else { return }
        // Ensure onboarding is completed before evaluating automated upsell popups
        guard services.brandSettings.hasCompletedBrandOnboarding else { return }

        hasEvaluatedPremiumUpsellThisSession = true
        let now = Date()
        let defaults = UserDefaults.standard
        let lastShown = defaults.object(forKey: Self.premiumUpsellLastShownKey) as? Date

        // First successful launch seeds the cadence silently. This avoids the
        // dashboard feeling blocked by a paywall while cold-start work is still
        // settling, and prevents the upsell from appearing on every app open.
        guard let lastShown else {
            defaults.set(now, forKey: Self.premiumUpsellLastShownKey)
            return
        }

        guard now.timeIntervalSince(lastShown) >= Self.premiumUpsellIntervalSeconds else { return }

        // 6 s gives the SwiftData queries, pricing tasks, and chart loads time
        // to fully settle before interrupting the user. The previous 2.5 s delay
        // coincided exactly with the end of the cold-start load, making the upsell
        // feel like a "reward" for surviving the freeze rather than a natural pause.
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
            // Re-check at fire time — nothing modal should be on screen.
            guard !showSplash,
                  !showOnboardingImmediate,
                  isLaunchSequenceComplete,
                  selectedCardPresentation == nil,
                  selectedSealedProductPresentation == nil,
                  !services.isSealedDetailPresentationActive else { return }
            defaults.set(Date(), forKey: Self.premiumUpsellLastShownKey)
            showPremiumAutoSheet = true
        }
    }

    // MARK: - One-shot onboarding replay

    /// Resets `hasCompletedBrandOnboarding` exactly once per migration
    /// version so existing users see the new 3-screen onboarding flow on
    /// their next launch. The version key (`onboardingReplayMigrationKey`)
    /// persists forever after firing, so this never repeats — users won't
    /// be re-onboarded every cold launch.
    fileprivate func applyOnboardingReplayMigrationIfNeeded() {
        let migrationKey = Self.onboardingReplayMigrationKey
        if !UserDefaults.standard.bool(forKey: migrationKey) {
            services.brandSettings.hasCompletedBrandOnboarding = false
            showSplash = true
            UserDefaults.standard.set(true, forKey: migrationKey)
        }
    }
}

#Preview {
    RootView()
}

private extension View {
    @ViewBuilder
    func bindrDisableTabBarMinimize() -> some View {
        if #available(iOS 26.0, *) {
            self.tabBarMinimizeBehavior(.never)
        } else {
            self
        }
    }
}
