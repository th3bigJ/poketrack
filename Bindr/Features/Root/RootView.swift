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
    @Binding var isMultiSelectActive: Bool
    @Binding var multiSelectedCardIDs: Set<String>

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
            inlineDetailRoute: $inlineDetailRoute,
            isMultiSelectActive: $isMultiSelectActive,
            multiSelectedCardIDs: $multiSelectedCardIDs
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
    @State private var browseMultiSelectActive = false
    @State private var browseMultiSelectedCardIDs: Set<String> = []
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
    @State private var showCreateFolderAlert = false
    @State private var newFolderTitle = ""
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
        if selectedTab == .collect && !collectionNavigationPath.isEmpty { return false }
        return chromeScroll.barsVisible
    }

    private var isBrowseGridFilterContextActive: Bool {
        selectedTab == .browse
            && browseNavigationPath.isEmpty
            && !isSearchExperiencePresented
            && (browseHomeTab == .cards || browseHomeTab == .sealed || browseInlineDetailRoute != nil)
    }

    private var isCollectFilterContextActive: Bool {
        selectedTab == .collect && collectionNavigationPath.isEmpty && collectSegment != .folders
    }

    private var activeCollectFilters: BrowseCardGridFilters {
        switch collectSegment {
        case .collection: return collectFilters.collectionFilters
        case .wishlist:   return collectFilters.wishlistFilters
        case .folders:    return BrowseCardGridFilters()
        }
    }

    private var activeCollectFiltersBinding: Binding<BrowseCardGridFilters> {
        switch collectSegment {
        case .collection: return $collectFilters.collectionFilters
        case .wishlist:   return $collectFilters.wishlistFilters
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

    private var chromeExtraTrailingButton: (symbol: String, accessibilityLabel: String, action: () -> Void)? {
        guard isBrowseGridFilterContextActive else { return nil }
        return (
            browseMultiSelectActive ? "checkmark.circle.fill" : "checkmark.circle",
            browseMultiSelectActive ? "Exit multi-select" : "Multi-select",
            {
                browseMultiSelectActive.toggle()
                if !browseMultiSelectActive {
                    browseMultiSelectedCardIDs.removeAll()
                }
            }
        )
    }

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
        if browseHomeTab == .sealed, browseInlineDetailRoute == nil {
            return $browseFilters.sealedGridOptions
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
        case .sealed:
            return $browseFilters.sealedFilters
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
        case .sealed:
            return $browseFilters.sealedInlineFilters
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
                                selectedTab = .collect
                            }, onOpenWishlist: {
                                collectionNavigationPath = NavigationPath()
                                collectSegment = .wishlist
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
                                isMultiSelectActive: $browseMultiSelectActive,
                                multiSelectedCardIDs: $browseMultiSelectedCardIDs
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
            if selectedCardPresentation != nil || services.isSealedDetailPresentationActive {
                Color(uiColor: .systemBackground)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(
            .easeInOut(duration: 0.25),
            value: selectedCardPresentation != nil || services.isSealedDetailPresentationActive
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
            if tab != .browse {
                resetBrowseMultiSelectState()
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
            if newCount > 0 {
                resetBrowseMultiSelectState()
            }
            if newCount == 0 {
                chromeScroll.forceVisible()
            }
        }
        .onChange(of: browseHomeTab) { _, newValue in
            let supportsMultiSelect = newValue == .cards || newValue == .sealed || browseInlineDetailRoute != nil
            if !supportsMultiSelect {
                resetBrowseMultiSelectState()
            }
        }
        .onChange(of: browseInlineDetailRoute) { _, newValue in
            if newValue == nil && browseHomeTab != .cards && browseHomeTab != .sealed {
                resetBrowseMultiSelectState()
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
            resetBrowseMultiSelectState()
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
            guard url.scheme?.lowercased() == "bindr" else { return }
            services.socialPush.queueDeepLink(url: url)
            selectedTab = .social
            Task {
                await services.socialAuth.restoreSession()
            }
        }
        .onChange(of: services.socialPush.queuedDeepLinkURL) { _, queuedURL in
            guard let queuedURL else { return }
            guard queuedURL.scheme?.lowercased() == "bindr" else { return }
            selectedTab = .social
            Task {
                await services.socialAuth.restoreSession()
            }
        }
        .sheet(item: $selectedCardPresentation) { ctx in
            CardBrowseDetailView(cards: ctx.cards, startIndex: ctx.startIndex)
                .environment(services)
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
        .tint(services.theme.accentColor)
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
                showRandomSort: false,
                showCardNumberSort: false,
                showHideOwned: false,
                showShowDuplicates: true,
                showGridOptions: true,
                defaultSortBy: .price,
                showSealedProductTypeFilter: true
            )
        )
    }

    @ViewBuilder
    private var browseFilterMenuContent: some View {
        let isSealedTab = browseHomeTab == .sealed
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
            case .pokemon, .sealed:
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
            gridOptions: isSealedTab ? $browseFilters.sealedGridOptions : nil,
            config: isSealedTab
                ? FilterMenuConfig(
                    showAcquiredDateSort: false,
                    showCardNumberSort: false,
                    showBrandFilters: false,
                    showRarity: false,
                    showRarePlusOnly: false,
                    showHideOwned: false,
                    showShowDuplicates: false,
                    showGridOptions: true,
                    defaultSortBy: .newestSet,
                    gridNameToggleTitle: "Show product name",
                    showGridCardIDToggle: false,
                    showGridColumns: true,
                    showGridOwnedToggle: false,
                    showSealedProductTypeFilter: true
                )
                : browseConfig
        )
    }

    private func resetBrowseMultiSelectState() {
        browseMultiSelectActive = false
        browseMultiSelectedCardIDs.removeAll()
    }

}

#Preview {
    RootView()
}
