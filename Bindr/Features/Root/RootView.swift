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

    var body: some View {
        BrowseView(
            collectionItems: collectionItems,
            filters: $filters,
            inlineDetailFilters: $inlineDetailFilters,
            gridOptions: $gridOptions,
            isFilterMenuPresented: .constant(false),
            filterResultCount: $filterResultCount,
            filterEnergyOptions: $filterEnergyOptions,
            filterRarityOptions: $filterRarityOptions,
            filterTrainerTypeOptions: $filterTrainerTypeOptions,
            inlineDetailFilterResultCount: $inlineDetailFilterResultCount,
            inlineDetailFilterEnergyOptions: $inlineDetailFilterEnergyOptions,
            inlineDetailFilterRarityOptions: $inlineDetailFilterRarityOptions,
            inlineDetailFilterTrainerTypeOptions: $inlineDetailFilterTrainerTypeOptions,
            selectedTab: $selectedTab,
            inlineDetailRoute: $inlineDetailRoute
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
    @State private var universalQuery = ""
    @State private var showCardScanner = false
    @State private var browseFilters = BrowseCardGridFilters()
    @State private var browseFilterResultCount = 0
    @State private var browseFilterEnergyOptions: [String] = []
    @State private var browseFilterRarityOptions: [String] = []
    @State private var browseFilterTrainerTypeOptions: [String] = []
    @State private var browseInlineDetailFilters = BrowseCardGridFilters()
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
    @State private var showBrandOnboarding = false
    @State private var showSettings = false
    @State private var suppressMorePathReset = false
    @FocusState private var searchFieldFocused: Bool

    // MARK: - Splash Flow
    @State private var showSplash = false
    private let splashLastVersionKey = "bindr_splash_last_shown_version"

    /// True when search has pushed into a detail view — hide the floating `UniversalSearchBar` (detail uses system nav, same as Browse Pokémon).
    private var isSearchDetailActive: Bool {
        isSearchExperiencePresented && !searchNavigationPath.isEmpty
    }

    /// Search open at root list: show chrome. Search with a pushed detail: hide chrome. Cards tab with a pushed detail: hide chrome. Else scroll-driven chrome on Browse.
    private var showUniversalSearchBar: Bool {
        if isSearchExperiencePresented { return true }
        if selectedTab == .social { return false }
        if selectedTab == .more { return false }
        return chromeScroll.barsVisible
    }

    private var isBrowseGridFilterContextActive: Bool {
        selectedTab == .browse
            && browseNavigationPath.isEmpty
            && !isSearchExperiencePresented
            && (browseHomeTab == .cards || browseInlineDetailRoute != nil)
    }

    private var isCollectFilterContextActive: Bool {
        selectedTab == .collect && collectionNavigationPath.isEmpty
    }

    private var activeCollectFilters: BrowseCardGridFilters {
        collectSegment == .collection ? collectFilters.collectionFilters : collectFilters.wishlistFilters
    }

    private var activeCollectFiltersBinding: Binding<BrowseCardGridFilters> {
        collectSegment == .collection ? $collectFilters.collectionFilters : $collectFilters.wishlistFilters
    }

    private var isCollectFilterActive: Bool {
        activeCollectFilters.isVisiblyCustomized
    }

    private var collectActiveBrand: TCGBrand {
        collectSelectedBrand ?? services.brandSettings.selectedCatalogBrand
    }

    private var isCollectAllBrands: Bool {
        false
    }

    private var chromeTrailingButton: (symbol: String, accessibilityLabel: String, action: () -> Void)? {
        switch selectedTab {
        case .dashboard: return ("gearshape", "Settings", { showSettings = true })
        default: return nil
        }
    }

    private var rootChromeTitle: String {
        if selectedTab == .browse, let browseInlineDetailRoute {
            return browseInlineDetailRoute.title
        }
        return selectedTab.title
    }

    private var activeBrowseFilters: BrowseCardGridFilters {
        browseInlineDetailRoute == nil ? browseFilters : browseInlineDetailFilters
    }

    private var activeBrowseFiltersBinding: Binding<BrowseCardGridFilters> {
        browseInlineDetailRoute == nil ? $browseFilters : $browseInlineDetailFilters
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
            if services.isReady {
                Group {
                    if services.isLaunchCatalogPipelineComplete {
                        mainContent
                    } else {
                        StartupBusyView(
                            message: "Preparing your card data…",
                            status: "Checking catalog updates and prices…"
                        )
                    }
                }
                .task {
                    await Task.yield()
                    await Task.yield()
                    await services.bootstrapCatalogInBackgroundIfNeeded()
                }
            } else {
                Color(uiColor: .systemBackground)
                    .ignoresSafeArea()
                    .overlay {
                        if services.brandSettings.hasCompletedBrandOnboarding,
                           !services.brandSettings.hasCompletedInitialAppBootstrap {
                            if services.bootstrapShowsDownloadProgressUI {
                                LoadingScreen(
                                    message: services.bootstrapMessage,
                                    status: services.bootstrapStatus,
                                    progress: services.bootstrapProgress,
                                    downloadedBytes: services.bootstrapDownloadedBytes,
                                    totalBytes: services.bootstrapEstimatedTotalBytes
                                )
                            } else {
                                StartupBusyView(
                                    message: services.bootstrapMessage,
                                    status: services.bootstrapStatus
                                )
                            }
                        }
                    }
                    .task(id: services.brandSettings.hasCompletedBrandOnboarding) {
                        guard services.brandSettings.hasCompletedBrandOnboarding else { return }
                        guard !services.brandSettings.hasCompletedInitialAppBootstrap else { return }
                        await services.bootstrap()
                    }
            }
        }
        .environment(services)
        .environmentObject(chromeScroll)
        .environment(\.presentCard, { card, list in
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            let idx = list.firstIndex(where: { $0.id == card.id }) ?? 0
            selectedCardPresentation = CardPresentationContext(cards: list, startIndex: idx)
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
            // Determine if splash should show (first launch or update)
            let lastShownVersion = UserDefaults.standard.string(forKey: splashLastVersionKey)
            let shouldShowSplash = lastShownVersion == nil || lastShownVersion != currentAppVersion
            if shouldShowSplash {
                showSplash = true
            }
            await services.socialPush.updateRegistrationState()
        }
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
                                selectedTab = .collect
                            }, onOpenBrowse: {
                                browseNavigationPath = NavigationPath()
                                selectedTab = .browse
                            })
                        }
                        .toolbarBackground(.hidden, for: .navigationBar)
                        .tabItem { Label(AppTab.dashboard.title, systemImage: AppTab.dashboard.symbolName) }
                        .tag(AppTab.dashboard)

                        NavigationStack(path: $browseNavigationPath) {
                            let browseGridOptionsBindable = Bindable(services.browseGridOptions)
                            BrowseTabView(
                                filters: $browseFilters,
                                inlineDetailFilters: $browseInlineDetailFilters,
                                gridOptions: browseGridOptionsBindable.options,
                                filterResultCount: $browseFilterResultCount,
                                filterEnergyOptions: $browseFilterEnergyOptions,
                                filterRarityOptions: $browseFilterRarityOptions,
                                filterTrainerTypeOptions: $browseFilterTrainerTypeOptions,
                                inlineDetailFilterResultCount: $browseInlineDetailFilterResultCount,
                                inlineDetailFilterEnergyOptions: $browseInlineDetailFilterEnergyOptions,
                                inlineDetailFilterRarityOptions: $browseInlineDetailFilterRarityOptions,
                                inlineDetailFilterTrainerTypeOptions: $browseInlineDetailFilterTrainerTypeOptions,
                                selectedTab: $browseHomeTab,
                                inlineDetailRoute: $browseInlineDetailRoute
                            )
                        }
                        .toolbarBackground(.hidden, for: .navigationBar)
                        .tabItem { Label(AppTab.browse.title, systemImage: AppTab.browse.symbolName) }
                        .tag(AppTab.browse)

                        NavigationStack(path: $collectionNavigationPath) {
                            CollectView(
                                selectedSegment: $collectSegment,
                                selectedBrand: $collectSelectedBrand,
                                collectionFilters: $collectFilters.collectionFilters,
                                wishlistFilters: $collectFilters.wishlistFilters,
                                collectFilterEnergyOptions: $collectFilterEnergyOptions,
                                collectFilterRarityOptions: $collectFilterRarityOptions,
                                collectFilterTrainerTypeOptions: $collectFilterTrainerTypeOptions,
                                gridOptions: $collectFilters.gridOptions
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
                        .badge(services.socialFeed.hasUnread ? "●" : nil)
                        .tag(AppTab.social)

                        NavigationStack(path: $moreNavigationPath) {
                            MoreView(navigationPath: $moreNavigationPath)
                        }
                        .toolbarBackground(.hidden, for: .navigationBar)
                        .tabItem { Label(AppTab.more.title, systemImage: AppTab.more.symbolName) }
                        .tag(AppTab.more)
                    }

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
                    .popover(isPresented: $showSettings) {
                        SettingsView()
                            .environment(services)
                    }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // System background shows through the material where the bar is translucent.
        .background(Color(uiColor: .systemBackground))
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
            if selectedCardPresentation != nil {
                Color(uiColor: .systemBackground)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: selectedCardPresentation != nil)
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
            browseFilters = BrowseCardGridFilters()
            browseInlineDetailFilters = BrowseCardGridFilters()
            browseInlineDetailRoute = nil
            selectedCardPresentation = nil
            universalQuery = ""
            searchFieldFocused = false
            collectSelectedBrand = brand

            var defaultCollectionFilters = BrowseCardGridFilters()
            defaultCollectionFilters.sortBy = .price
            collectFilters.collectionFilters = defaultCollectionFilters
            collectFilters.wishlistFilters = BrowseCardGridFilters()
        }
        .onChange(of: services.socialAuth.authState) { _, _ in
            Task {
                await services.socialPush.updateRegistrationState()
            }
        }
        .onOpenURL { url in
            guard services.socialFriend.queueProfileDeepLink(from: url) else { return }
            selectedTab = .social
            Task {
                await services.socialAuth.restoreSession()
            }
        }
        .onChange(of: services.socialPush.queuedDeepLinkURL) { _, queuedURL in
            guard let queuedURL else { return }
            guard services.socialFriend.queueProfileDeepLink(from: queuedURL) else { return }
            _ = services.socialPush.consumeQueuedDeepLinkURL()
            selectedTab = .social
            Task {
                await services.socialAuth.restoreSession()
            }
        }
        .sheet(item: $selectedCardPresentation) { ctx in
            CardBrowseDetailView(cards: ctx.cards, startIndex: ctx.startIndex)
                .environment(services)
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
    }

    @ViewBuilder
    private func floatingSearchBar(hiddenOffset: CGFloat, topInset: CGFloat, bottomInset: CGFloat) -> some View {
        let visible = showUniversalSearchBar && !isSearchDetailActive
        let browseLeadingButton: (symbol: String, accessibilityLabel: String, action: () -> Void)? =
            selectedTab == .browse && browseInlineDetailRoute != nil
            ? ("chevron.left", "Back", {
                browseInlineDetailFilters = BrowseCardGridFilters()
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
    private var collectFilterMenuContent: some View {
        BrowseGridFiltersMenuContent(
            brand: collectActiveBrand,
            filters: activeCollectFiltersBinding,
            energyOptions: collectFilterEnergyOptions,
            rarityOptions: collectFilterRarityOptions,
            trainerTypeOptions: collectFilterTrainerTypeOptions,
            isAllBrands: isCollectAllBrands,
            gridOptions: $collectFilters.gridOptions,
            config: FilterMenuConfig(
                showAcquiredDateSort: true,
                showHideOwned: false,
                showShowDuplicates: true,
                showGridOptions: true,
                defaultSortBy: .price
            )
        )
    }

    @ViewBuilder
    private var browseFilterMenuContent: some View {
        BrowseGridFiltersMenuContent(
            brand: services.brandSettings.selectedCatalogBrand,
            filters: activeBrowseFiltersBinding,
            energyOptions: activeBrowseFilterEnergyOptions,
            rarityOptions: activeBrowseFilterRarityOptions,
            trainerTypeOptions: activeBrowseFilterTrainerTypeOptions,
            isAllBrands: false
        )
    }

}

#Preview {
    RootView()
}
