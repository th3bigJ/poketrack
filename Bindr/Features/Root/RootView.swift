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
    @State private var showBrandOnboarding = false
    @State private var cachedSetNameByCode: [String: String] = [:]
    @State private var inlineDetailCards: [Card] = []
    @State private var showCreateFolderAlert = false
    @State private var newFolderTitle = ""
    @State private var showSettings = false
    @State private var suppressMorePathReset = false
    @FocusState private var searchFieldFocused: Bool

    // MARK: - Splash Flow
    @State private var showSplash = false
    /// Flips once the BINDR letter-reveal stagger has played + breathing
    /// pulse has started. Distinct from "ready to dismiss" — the wordmark
    /// stays on screen until the catalog pipeline is also done so we never
    /// flash dashboard between the wordmark and the download UI.
    @State private var hasRevealedLaunchWordmark = false
    private let splashLastVersionKey = "bindr_splash_last_shown_version"

    /// Single gate for tearing the launch surface down. We require:
    ///  - the BINDR reveal animation has played,
    ///  - the services layer is initialized,
    ///  - the launch catalog pipeline (returning-user daily refresh, if any)
    ///    has completed.
    /// This collapses the previous two-phase "wordmark → maybe LoadingScreen"
    /// flow into a single fade so the dashboard never appears mid-launch.
    private var isLaunchSequenceComplete: Bool {
        hasRevealedLaunchWordmark
            && services.isReady
            && services.isLaunchCatalogPipelineComplete
    }

    private var launchProgressState: LaunchProgressState? {
        // Don't render progress under the wordmark for brand-new users — that
        // path goes through the brand-onboarding sheet, not the launch
        // refresh pipeline.
        guard services.isReady, !services.isLaunchCatalogPipelineComplete else { return nil }
        return LaunchProgressState(
            message: services.bootstrapMessage,
            status: services.bootstrapStatus,
            fraction: services.bootstrapProgress,
            downloadedBytes: services.bootstrapDownloadedBytes,
            totalBytes: services.bootstrapEstimatedTotalBytes,
            hasByteProgress: services.bootstrapShowsDownloadProgressUI
        )
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
        case .dashboard: return ("gearshape", "Settings", { showSettings = true })
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
        Group {
            if isLaunchSequenceComplete {
                // Dashboard slides up under a fade so the eye reads it as one
                // continuous launch transition rather than a hard cut.
                mainContent
                    .transition(.opacity)
            } else if services.isReady {
                // Returning-user path: wordmark stays put, progress block fades
                // in beneath it the moment the daily refresh starts work.
                LaunchWordmarkView(
                    progress: launchProgressState,
                    onRevealComplete: {
                        hasRevealedLaunchWordmark = true
                    }
                )
                .transition(.opacity)
            } else {
                // First-launch / brand-onboarding path is unchanged: keep
                // showing the wordmark until services come online (the
                // bootstrap progress UI takes over once onboarding is done).
                ZStack {
                    LaunchWordmarkView(
                        progress: brandOnboardingProgressState,
                        onRevealComplete: {
                            hasRevealedLaunchWordmark = true
                        }
                    )
                }
                .task(id: services.brandSettings.hasCompletedBrandOnboarding) {
                    guard services.brandSettings.hasCompletedBrandOnboarding else { return }
                    guard !services.brandSettings.hasCompletedInitialAppBootstrap else { return }
                    await services.bootstrap()
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: isLaunchSequenceComplete)
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
        .sheet(isPresented: $showBrandOnboarding) {
            BrandOnboardingView(isPresented: $showBrandOnboarding)
                .environment(services)
        }
        .onChange(of: services.brandSettings.hasCompletedBrandOnboarding) { _, completed in
            // Only show brand onboarding if splash has been dismissed
            if !showSplash {
                showBrandOnboarding = !completed
            }
        }
        .task(id: services.brandSettings.hasCompletedBrandOnboarding) {
            guard !services.brandSettings.hasCompletedBrandOnboarding else { return }
            // Wait for splash to be dismissed before showing onboarding
            if !showSplash {
                await Task.yield()
                showBrandOnboarding = true
            }
        }
        // MARK: - Splash Overlay
        .overlay {
            if showSplash {
                SplashView(onGetStarted: {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        showSplash = false
                        // Mark this version as shown
                        UserDefaults.standard.set(currentAppVersion, forKey: splashLastVersionKey)
                        // Show existing brand onboarding if not completed
                        if !services.brandSettings.hasCompletedBrandOnboarding {
                            showBrandOnboarding = true
                        }
                    }
                })
                .transition(.opacity)
                .zIndex(100)
            }
        }
        .task {
            // ── Cheap, immediate work ─────────────────────────────────────
            // Determine splash — just a UserDefaults read, safe to run now.
            let lastShownVersion = UserDefaults.standard.string(forKey: splashLastVersionKey)
            let shouldShowSplash = lastShownVersion == nil || lastShownVersion != currentAppVersion
            if shouldShowSplash {
                showSplash = true
            }

            // ── Defer all heavy work until the launch animation finishes ──
            // bootstrapCatalogInBackgroundIfNeeded does SQLite + search index
            // work that can hitch the main thread right when 'R' appears.
            // We poll hasRevealedLaunchWordmark (flips ~1.8s after launch) so
            // the BINDR letters can settle before we kick off the catalog
            // pipeline. The wordmark itself stays mounted *after* this — the
            // dismiss is gated on `isLaunchSequenceComplete` in the body.
            while !hasRevealedLaunchWordmark {
                try? await Task.sleep(nanoseconds: 50_000_000) // poll every 50ms
            }
            await Task.yield()

            if services.isReady {
                await services.bootstrapCatalogInBackgroundIfNeeded()
            }
            await services.socialPush.updateRegistrationState()
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
                            })
                        }
                        .toolbarBackground(.hidden, for: .navigationBar)
                        .tabItem { Label(AppTab.dashboard.title, systemImage: AppTab.dashboard.symbolName) }
                        .tag(AppTab.dashboard)

                        NavigationStack(path: $browseNavigationPath) {
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
                        }
                        .toolbarBackground(.hidden, for: .navigationBar)
                        .tabItem { Label(AppTab.browse.title, systemImage: AppTab.browse.symbolName) }
                        .tag(AppTab.browse)

                        NavigationStack(path: $collectionNavigationPath) {
                            CollectView(
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
                        }
                        .toolbarBackground(.hidden, for: .navigationBar)
                        .tabItem { Label(AppTab.collect.title, systemImage: AppTab.collect.symbolName) }
                        .tag(AppTab.collect)

                        NavigationStack {
                            SocialRootView()
                        }
                        .toolbarBackground(.hidden, for: .navigationBar)
                        .tabItem { Label(AppTab.social.title, systemImage: AppTab.social.symbolName) }
                        .tag(AppTab.social)

                        NavigationStack(path: $moreNavigationPath) {
                            MoreView(navigationPath: $moreNavigationPath)
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
                    .sheet(isPresented: $showSettings) {
                        NavigationStack {
                            SettingsView()
                                .environment(services)
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
            chromeScroll.configureForTab(selectedTab)
            collectSelectedBrand = services.brandSettings.selectedCatalogBrand
            if services.isReady {
                services.setupWishlist(modelContext: modelContext)
                services.setupCollectionLedger(modelContext: modelContext)
                services.setupCollectionValue(modelContext: modelContext)
            }
        }
        .onChange(of: services.isReady) { _, ready in
            if ready {
                services.setupWishlist(modelContext: modelContext)
                services.setupCollectionLedger(modelContext: modelContext)
                services.setupCollectionValue(modelContext: modelContext)
            }
        }
        .onChange(of: selectedTab) { _, tab in
            Haptics.selectionChanged()
            chromeScroll.configureForTab(tab)
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
            let showAddToTradeList = isCollectCards && collectSegment == .collection
            let showTradeFlow = isCollectCards && collectSegment == .wishlist
            CardDetailSheet(
                cards: ctx.cards,
                startIndex: ctx.startIndex,
                tradeAction: showAddToTradeList ? { card, qty in
                    addCardToTradeList(card, quantity: qty)
                } : showTradeFlow ? { card, _ in
                    launchTradeFlowFromCollectionCard(card)
                } : nil,
                tradeActionLabel: showAddToTradeList ? "Trade List" : "Trade"
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

    private func addCardToTradeList(_ card: Card, quantity: Int) {
        let cardID = card.masterCardId
        let existing = (try? modelContext.fetch(
            FetchDescriptor<TradeListItem>(predicate: #Predicate { $0.cardID == cardID })
        )) ?? []
        if let first = existing.first {
            first.quantity = quantity
        } else {
            modelContext.insert(TradeListItem(cardID: cardID, quantity: quantity))
        }
        try? modelContext.save()
        Haptics.success()
        selectedCardPresentation = nil
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
