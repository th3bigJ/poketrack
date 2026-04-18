import SwiftUI
import SwiftData
import UIKit

private enum BrowseFullScreen: String, Identifiable, Hashable {
    case allSets
    case allPokemon
    case onePieceCharacters
    case onePieceSubtypes
    var id: String { rawValue }
}

/// Presents Browse Sets / Pokémon as one root `fullScreenCover`, and card detail in a **nested** cover so SwiftUI never stacks two root-level full-screen presentations (which triggers “only presenting a single sheet is supported”).
private struct BrowseFullScreenHost: View {
    let route: BrowseFullScreen
    @Environment(AppServices.self) private var services
    @State private var presentedCardPresentation: CardPresentationContext?

    var body: some View {
        NavigationStack {
            switch route {
            case .allSets:
                BrowseAllSetsView()
            case .allPokemon:
                BrowseAllPokemonView()
            case .onePieceCharacters:
                BrowseAllOnePieceCharactersView()
            case .onePieceSubtypes:
                BrowseAllOnePieceSubtypesView()
            }
        }
        .environment(\.presentCard, { card, list in
            let idx = list.firstIndex(where: { $0.id == card.id }) ?? 0
            presentedCardPresentation = CardPresentationContext(cards: list, startIndex: idx)
        })
        .overlay {
            if presentedCardPresentation != nil {
                Color(uiColor: .systemBackground)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: presentedCardPresentation != nil)
        .sheet(item: $presentedCardPresentation) { ctx in
            CardBrowseDetailView(cards: ctx.cards, startIndex: ctx.startIndex)
                .environment(services)
        }
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
    @State private var collectSelectedBrand: TCGBrand? = nil
    @State private var collectCollectionFilters = BrowseCardGridFilters()
    @State private var collectWishlistFilters = BrowseCardGridFilters()
    @State private var collectFilterEnergyOptions: [String] = []
    @State private var collectFilterRarityOptions: [String] = []
    @State private var collectFilterTrainerTypeOptions: [String] = []
    @State private var collectGridOptions = BrowseGridOptions()
    @State private var isSearchExperiencePresented = false
    /// When non-empty, user has pushed card / set / dex from search — hide root `UniversalSearchBar`; detail uses the same `NavigationStack` bar as Browse (`DexCardsView` / `SetCardsView`).
    @State private var searchNavigationPath = NavigationPath()
    /// Cards tab `NavigationStack` path — hide root chrome when a card detail (or other pushed screen) is showing.
    @State private var browseNavigationPath = NavigationPath()
    @State private var collectionNavigationPath = NavigationPath()
    @State private var bindrsNavigationPath = NavigationPath()
    @State private var moreNavigationPath = NavigationPath()
    @State private var browseFullScreen: BrowseFullScreen?
    @State private var selectedCardPresentation: CardPresentationContext?
    @State private var showBrandOnboarding = false
    @State private var showProfile = false
    @State private var suppressMorePathReset = false
    @State private var showCreateBinder = false
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
        if selectedTab == .bindrs && !bindrsNavigationPath.isEmpty { return false }
        if selectedTab == .more { return false }
        return chromeScroll.barsVisible
    }

    private var isBrowseGridFilterContextActive: Bool {
        selectedTab == .browse
            && browseNavigationPath.isEmpty
            && !isSearchExperiencePresented
            && browseFullScreen == nil
    }

    private var isCollectFilterContextActive: Bool {
        selectedTab == .collect && collectionNavigationPath.isEmpty
    }

    private var activeCollectFilters: BrowseCardGridFilters {
        collectSegment == .collection ? collectCollectionFilters : collectWishlistFilters
    }

    private var activeCollectFiltersBinding: Binding<BrowseCardGridFilters> {
        collectSegment == .collection ? $collectCollectionFilters : $collectWishlistFilters
    }

    private var isCollectFilterActive: Bool {
        activeCollectFilters.isVisiblyCustomized
    }

    private var collectActiveBrand: TCGBrand {
        collectSelectedBrand ?? services.brandSettings.selectedCatalogBrand
    }

    private var isCollectAllBrands: Bool {
        collectSelectedBrand == nil && services.brandSettings.enabledBrands.count > 1
    }

    private var chromeTrailingButton: (symbol: String, accessibilityLabel: String, action: () -> Void)? {
        switch selectedTab {
        case .dashboard: return ("person.crop.circle", "Profile", { showProfile = true })
        case .bindrs: return ("plus", "Create Binder", { showCreateBinder = true })
        default: return nil
        }
    }

    private var rootChromeTitle: String {
        selectedTab.title
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
        }
    }

    /// Current app version string (e.g., "1.2.3")
    private var currentAppVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    @ViewBuilder
    private var mainContent: some View {
        GeometryReader { _ in
            let searchBarTopInset = RootChromeEnvironment.searchBarTopInset
            let searchBarBottomInset = RootChromeEnvironment.searchBarBottomInset
            let floatingChromeInset = RootChromeEnvironment.floatingContentTopInset
            let searchBarHiddenOffset = -(floatingChromeInset + 18)
            let contentTopInset: CGFloat = isSearchDetailActive ? 0 : floatingChromeInset

            ZStack(alignment: .top) {
                ZStack(alignment: .top) {
                    TabView(selection: $selectedTab) {
                        ForEach(AppTab.visibleTabs) { tab in
                            Group {
                                switch tab {
                                case .dashboard:
                                    NavigationStack {
                                        DashboardView(onViewAllActivity: {
                                            suppressMorePathReset = true
                                            moreNavigationPath = NavigationPath()
                                            moreNavigationPath.append(SideMenuPage.transactions)
                                            selectedTab = .more
                                        })
                                    }
                                case .browse:
                                    NavigationStack(path: $browseNavigationPath) {
                                        BrowseView(
                                            filters: $browseFilters,
                                            gridOptions: Binding(
                                                get: { services.browseGridOptions.options },
                                                set: { services.browseGridOptions.options = $0 }
                                            ),
                                            isFilterMenuPresented: .constant(false),
                                            filterResultCount: $browseFilterResultCount,
                                            filterEnergyOptions: $browseFilterEnergyOptions,
                                            filterRarityOptions: $browseFilterRarityOptions,
                                            filterTrainerTypeOptions: $browseFilterTrainerTypeOptions,
                                            onBrowseSets: {
                                                browseFullScreen = .allSets
                                            },
                                            onBrowsePokemon: {
                                                browseFullScreen = .allPokemon
                                            },
                                            onBrowseOnePieceCharacters: {
                                                browseFullScreen = .onePieceCharacters
                                            },
                                            onBrowseOnePieceSubtypes: {
                                                browseFullScreen = .onePieceSubtypes
                                            }
                                        )
                                    }
                                case .collect:
                                    NavigationStack(path: $collectionNavigationPath) {
                                        CollectView(
                                            selectedSegment: $collectSegment,
                                            selectedBrand: $collectSelectedBrand,
                                            collectionFilters: $collectCollectionFilters,
                                            wishlistFilters: $collectWishlistFilters,
                                            collectFilterEnergyOptions: $collectFilterEnergyOptions,
                                            collectFilterRarityOptions: $collectFilterRarityOptions,
                                            collectFilterTrainerTypeOptions: $collectFilterTrainerTypeOptions,
                                            gridOptions: $collectGridOptions
                                        )
                                    }
                                case .bindrs:
                                    NavigationStack(path: $bindrsNavigationPath) {
                                        BindersRootView(showCreateSheet: $showCreateBinder)
                                    }
                                case .more:
                                    NavigationStack(path: $moreNavigationPath) {
                                        MoreView(navigationPath: $moreNavigationPath)
                                    }
                                }
                            }
                            .toolbarBackground(.hidden, for: .navigationBar)
                            .tabItem {
                                Label(tab.title, systemImage: tab.symbolName)
                            }
                            .tag(tab)
                        }
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
                                case .set(let s):
                                    SetCardsView(set: s)
                                        .onAppear { searchFieldFocused = false }
                                case .dex(let dexId, let displayName):
                                    DexCardsView(dexId: dexId, displayName: displayName)
                                        .onAppear { searchFieldFocused = false }
                                case .onePieceCharacter(let name):
                                    OnePieceCharacterCardsView(characterName: name)
                                        .onAppear { searchFieldFocused = false }
                                case .onePieceSubtype(let name):
                                    OnePieceSubtypeCardsView(subtypeName: name)
                                        .onAppear { searchFieldFocused = false }
                                }
                            }
                        }
                        .environment(\.presentCard, { card, list in
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
                .environment(\.rootFloatingChromeInset, contentTopInset)

                // Floating above tab content so `.ultraThinMaterial` / Liquid Glass blur the grid behind the bar.
                floatingSearchBar(hiddenOffset: searchBarHiddenOffset, topInset: searchBarTopInset, bottomInset: searchBarBottomInset)
                    .popover(isPresented: $showProfile) {
                        ProfileSheet()
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
        }
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
        .sheet(item: $selectedCardPresentation) { ctx in
            CardBrowseDetailView(cards: ctx.cards, startIndex: ctx.startIndex)
                .environment(services)
        }
        .fullScreenCover(item: $browseFullScreen) { route in
            BrowseFullScreenHost(route: route)
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
        let filterEnabled = isBrowseGridFilterContextActive || isCollectFilterContextActive
        let filterActive = isBrowseGridFilterContextActive ? browseFilters.isVisiblyCustomized
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
            gridOptions: $collectGridOptions,
            config: .collect
        )
    }

    @ViewBuilder
    private var browseFilterMenuContent: some View {
        if browseFilters.isVisiblyCustomized {
            Section {
                Button("Reset filters", role: .destructive) {
                    let currentSort = browseFilters.sortBy
                    browseFilters = BrowseCardGridFilters()
                    browseFilters.sortBy = currentSort
                }
            }
        }

        Section("Sort by") {
            Menu(menuTitle("Sort by", summary: browseFilters.sortBy.title)) {
                Picker("Sort by", selection: $browseFilters.sortBy) {
                    ForEach(BrowseCardGridSortOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            .menuActionDismissBehavior(.disabled)
            .menuOrder(.fixed)
        }

        Section("Filters") {
            if services.brandSettings.selectedCatalogBrand == .onePiece {
                Menu(menuTitle("Card type", summary: selectionSummary(for: browseFilters.opCardTypes))) {
                    ForEach(opCardTypeAllOptions, id: \.self) { cardType in
                        Toggle(cardType, isOn: binding(for: cardType, keyPath: \.opCardTypes))
                    }
                }
                .menuActionDismissBehavior(.disabled)
                .menuOrder(.fixed)

                Menu(menuTitle("Attribute", summary: selectionSummary(for: browseFilters.opAttributes))) {
                    ForEach(opAttributeAllOptions, id: \.self) { attr in
                        Toggle(attr, isOn: binding(for: attr, keyPath: \.opAttributes))
                    }
                }
                .menuActionDismissBehavior(.disabled)
                .menuOrder(.fixed)

                Menu(
                    menuTitle(
                        "Stats",
                        summary: combinedSelectionSummary(
                            ("Cost", browseFilters.opCosts.count),
                            ("Counter", browseFilters.opCounters.count),
                            ("Life", browseFilters.opLives.count),
                            ("Power", browseFilters.opPowers.count)
                        )
                    )
                ) {
                    Menu(menuTitle("Cost", summary: selectionSummary(for: browseFilters.opCosts))) {
                        ForEach(opCostAllOptions, id: \.self) { cost in
                            Toggle("\(cost)", isOn: binding(for: cost, keyPath: \.opCosts))
                        }
                    }
                    .menuActionDismissBehavior(.disabled)
                    .menuOrder(.fixed)

                    Menu(menuTitle("Counter", summary: selectionSummary(for: browseFilters.opCounters))) {
                        ForEach(opCounterAllOptions, id: \.self) { counter in
                            Toggle("\(counter)", isOn: binding(for: counter, keyPath: \.opCounters))
                        }
                    }
                    .menuActionDismissBehavior(.disabled)
                    .menuOrder(.fixed)

                    Menu(menuTitle("Life", summary: selectionSummary(for: browseFilters.opLives))) {
                        ForEach(opLifeAllOptions, id: \.self) { life in
                            Toggle("\(life)", isOn: binding(for: life, keyPath: \.opLives))
                        }
                    }
                    .menuActionDismissBehavior(.disabled)
                    .menuOrder(.fixed)

                    Menu(menuTitle("Power", summary: selectionSummary(for: browseFilters.opPowers))) {
                        ForEach(opPowerAllOptions, id: \.self) { power in
                            Toggle("\(power)", isOn: binding(for: power, keyPath: \.opPowers))
                        }
                    }
                    .menuActionDismissBehavior(.disabled)
                    .menuOrder(.fixed)
                }
                .menuActionDismissBehavior(.disabled)
                .menuOrder(.fixed)
            } else if services.brandSettings.selectedCatalogBrand == .lorcana {
                Menu(menuTitle("Card type", summary: selectionSummary(for: browseFilters.lcCardTypes))) {
                    ForEach(lcCardTypeAllOptions, id: \.self) { cardType in
                        Toggle(cardType, isOn: binding(for: cardType, keyPath: \.lcCardTypes))
                    }
                }
                .menuActionDismissBehavior(.disabled)
                .menuOrder(.fixed)

                Menu(menuTitle("Variant", summary: selectionSummary(for: browseFilters.lcVariants))) {
                    ForEach(lcVariantAllOptions, id: \.self) { variant in
                        Toggle(variant, isOn: binding(for: variant, keyPath: \.lcVariants))
                    }
                }
                .menuActionDismissBehavior(.disabled)
                .menuOrder(.fixed)

                Menu(
                    menuTitle(
                        "Stats",
                        summary: combinedSelectionSummary(
                            ("Cost", browseFilters.lcCosts.count),
                            ("Lore", browseFilters.lcLores.count),
                            ("Strength", browseFilters.lcStrengths.count),
                            ("Willpower", browseFilters.lcWillpowers.count)
                        )
                    )
                ) {
                    Menu(menuTitle("Cost", summary: selectionSummary(for: browseFilters.lcCosts))) {
                        ForEach(lcCostAllOptions, id: \.self) { cost in
                            Toggle("\(cost)", isOn: binding(for: cost, keyPath: \.lcCosts))
                        }
                    }
                    .menuActionDismissBehavior(.disabled)
                    .menuOrder(.fixed)

                    Menu(menuTitle("Lore", summary: selectionSummary(for: browseFilters.lcLores))) {
                        ForEach(lcLoreAllOptions, id: \.self) { lore in
                            Toggle("\(lore)", isOn: binding(for: lore, keyPath: \.lcLores))
                        }
                    }
                    .menuActionDismissBehavior(.disabled)
                    .menuOrder(.fixed)

                    Menu(menuTitle("Strength", summary: selectionSummary(for: browseFilters.lcStrengths))) {
                        ForEach(lcStrengthAllOptions, id: \.self) { strength in
                            Toggle("\(strength)", isOn: binding(for: strength, keyPath: \.lcStrengths))
                        }
                    }
                    .menuActionDismissBehavior(.disabled)
                    .menuOrder(.fixed)

                    Menu(menuTitle("Willpower", summary: selectionSummary(for: browseFilters.lcWillpowers))) {
                        ForEach(lcWillpowerAllOptions, id: \.self) { willpower in
                            Toggle("\(willpower)", isOn: binding(for: willpower, keyPath: \.lcWillpowers))
                        }
                    }
                    .menuActionDismissBehavior(.disabled)
                    .menuOrder(.fixed)
                }
                .menuActionDismissBehavior(.disabled)
                .menuOrder(.fixed)
            } else {
                Menu(menuTitle("Card type", summary: selectionSummary(for: browseFilters.cardTypes))) {
                    ForEach(BrowseCardTypeFilter.allCases) { type in
                        Toggle(type.title, isOn: binding(for: type))
                    }
                }
                .menuActionDismissBehavior(.disabled)
                .menuOrder(.fixed)
            }

            Menu(menuTitle(services.brandSettings.selectedCatalogBrand.energyFilterMenuTitle, summary: selectionSummary(for: browseFilters.energyTypes))) {
                if browseFilterEnergyOptions.isEmpty {
                    Text("No options available")
                } else {
                    ForEach(browseFilterEnergyOptions, id: \.self) { energy in
                        Toggle(energy, isOn: binding(for: energy, keyPath: \.energyTypes))
                    }
                }
            }
            .menuActionDismissBehavior(.disabled)
            .menuOrder(.fixed)

            if services.brandSettings.selectedCatalogBrand == .pokemon {
                Menu(menuTitle("Trainer type", summary: selectionSummary(for: browseFilters.trainerTypes))) {
                    if browseFilterTrainerTypeOptions.isEmpty {
                        Text("No trainer types available")
                    } else {
                        ForEach(browseFilterTrainerTypeOptions, id: \.self) { trainerType in
                            Toggle(trainerType, isOn: binding(for: trainerType, keyPath: \.trainerTypes))
                        }
                    }
                }
                .menuActionDismissBehavior(.disabled)
                .menuOrder(.fixed)
            }
        }

        Section("Collection") {
            Menu(menuTitle("Rarity", summary: selectionSummary(for: browseFilters.rarities))) {
                if browseFilterRarityOptions.isEmpty {
                    Text("No rarities available")
                } else {
                    ForEach(browseFilterRarityOptions, id: \.self) { rarity in
                        Toggle(rarity, isOn: binding(for: rarity, keyPath: \.rarities))
                    }
                }
            }
            .menuActionDismissBehavior(.disabled)
            .menuOrder(.fixed)

            Toggle("Rare + only", isOn: $browseFilters.rarePlusOnly)
            Toggle("Hide owned", isOn: $browseFilters.hideOwned)
        }

        Section("Grid options") {
            Menu("Grid options") {
                Toggle("Show card name", isOn: gridOptionBinding(\.showCardName))
                Toggle("Show set name", isOn: gridOptionBinding(\.showSetName))
                Toggle("Show set ID", isOn: gridOptionBinding(\.showSetID))
                Toggle("Show pricing", isOn: gridOptionBinding(\.showPricing))
                Stepper(value: gridOptionBinding(\.columnCount), in: 1...4) {
                    Text("Columns: \(services.browseGridOptions.options.columnCount)")
                }
            }
            .menuActionDismissBehavior(.disabled)
            .menuOrder(.fixed)
        }
    }

    private func binding(for type: BrowseCardTypeFilter) -> Binding<Bool> {
        Binding(
            get: { browseFilters.cardTypes.contains(type) },
            set: { isOn in
                if isOn { browseFilters.cardTypes.insert(type) }
                else { browseFilters.cardTypes.remove(type) }
            }
        )
    }

    private func binding(for value: String, keyPath: WritableKeyPath<BrowseCardGridFilters, Set<String>>) -> Binding<Bool> {
        Binding(
            get: { browseFilters[keyPath: keyPath].contains(value) },
            set: { isOn in
                if isOn { browseFilters[keyPath: keyPath].insert(value) }
                else { browseFilters[keyPath: keyPath].remove(value) }
            }
        )
    }

    private func binding(for value: Int, keyPath: WritableKeyPath<BrowseCardGridFilters, Set<Int>>) -> Binding<Bool> {
        Binding(
            get: { browseFilters[keyPath: keyPath].contains(value) },
            set: { isOn in
                if isOn { browseFilters[keyPath: keyPath].insert(value) }
                else { browseFilters[keyPath: keyPath].remove(value) }
            }
        )
    }

    private func menuTitle(_ title: String, summary: String?) -> String {
        guard let summary, !summary.isEmpty else { return title }
        return "\(title) (\(summary))"
    }

    private func gridOptionBinding(_ keyPath: WritableKeyPath<BrowseGridOptions, Bool>) -> Binding<Bool> {
        Binding(
            get: { services.browseGridOptions.options[keyPath: keyPath] },
            set: { value in
                var options = services.browseGridOptions.options
                options[keyPath: keyPath] = value
                services.browseGridOptions.options = options
            }
        )
    }

    private func gridOptionBinding(_ keyPath: WritableKeyPath<BrowseGridOptions, Int>) -> Binding<Int> {
        Binding(
            get: { services.browseGridOptions.options[keyPath: keyPath] },
            set: { value in
                var options = services.browseGridOptions.options
                options[keyPath: keyPath] = value
                services.browseGridOptions.options = options
            }
        )
    }

    private func selectionSummary<T>(for values: Set<T>) -> String? {
        guard !values.isEmpty else { return nil }
        if values.count == 1 { return "1 selected" }
        return "\(values.count) selected"
    }

    private func combinedSelectionSummary(_ groups: (String, Int)...) -> String? {
        let active = groups.filter { $0.1 > 0 }
        guard !active.isEmpty else { return nil }
        return active.map { "\($0.0) \($0.1)" }.joined(separator: ", ")
    }

}

#Preview {
    RootView()
}
