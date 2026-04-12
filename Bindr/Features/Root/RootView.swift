import SwiftUI
import SwiftData
import UIKit

private enum BrowseFullScreen: String, Identifiable, Hashable {
    case allSets
    case allPokemon
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
    @State private var sideMenuSheet: SideMenuSheet?
    @State private var universalQuery = ""
    @State private var showCardScanner = false
    @State private var browseFilters = BrowseCardGridFilters()
    @State private var browseFilterResultCount = 0
    @State private var browseFilterEnergyOptions: [String] = []
    @State private var browseFilterRarityOptions: [String] = []
    @State private var isSideMenuOpen = false
    @State private var isSearchExperiencePresented = false
    /// When non-empty, user has pushed card / set / dex from search — hide root `UniversalSearchBar`; detail uses the same `NavigationStack` bar as Browse (`DexCardsView` / `SetCardsView`).
    @State private var searchNavigationPath = NavigationPath()
    /// Cards tab `NavigationStack` path — hide root chrome when a card detail (or other pushed screen) is showing.
    @State private var browseNavigationPath = NavigationPath()
    @State private var browseFullScreen: BrowseFullScreen?
    @State private var selectedCardPresentation: CardPresentationContext?
    @State private var showBrandOnboarding = false
    @FocusState private var searchFieldFocused: Bool

    /// True when search has pushed into a detail view — hide the floating `UniversalSearchBar` (detail uses system nav, same as Browse Pokémon).
    private var isSearchDetailActive: Bool {
        isSearchExperiencePresented && !searchNavigationPath.isEmpty
    }

    /// Search open at root list: show chrome. Search with a pushed detail: hide chrome. Cards tab with a pushed detail: hide chrome. Else scroll-driven chrome on Browse.
    private var showUniversalSearchBar: Bool {
        if isSideMenuOpen { return true }
        if isSearchExperiencePresented { return true }
        return chromeScroll.barsVisible
    }

    /// Screen-edge swipe to open the menu — only when no pushed `NavigationStack` screen and no full-screen browse (so it doesn’t compete with back / pop).
    private var isEdgeSwipeMenuEnabled: Bool {
        !isSideMenuOpen
            && browseNavigationPath.isEmpty
            && searchNavigationPath.isEmpty
            && browseFullScreen == nil
    }

    private var isBrowseGridFilterContextActive: Bool {
        selectedTab == .browse
            && browseNavigationPath.isEmpty
            && !isSearchExperiencePresented
            && browseFullScreen == nil
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
            showBrandOnboarding = !completed
        }
        .task(id: services.brandSettings.hasCompletedBrandOnboarding) {
            guard !services.brandSettings.hasCompletedBrandOnboarding else { return }
            await Task.yield()
            showBrandOnboarding = true
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let menuWidth = min(width * 0.65, 300)
            // `GeometryReader` is already laid out inside the safe area, so only a small margin below the
            // status bar — do not add `safeAreaInsets.top` here or the bar sits one notch-height too low.
            let searchBarTopInset: CGFloat = 8
            let searchBarHiddenOffset = -(RootChromeEnvironment.searchBarStackHeight + searchBarTopInset + 18)
            // `SideMenuView` uses `.ignoresSafeArea(edges: .top)`, so it still needs the full safe inset.
            let sideMenuHeaderTopPadding = geo.safeAreaInsets.top + 8
            let edgeSwipeBelowSearchBar = searchBarTopInset + RootChromeEnvironment.searchBarStackHeight + 8
            ZStack(alignment: .leading) {
            SideMenuView(
                isPresented: $isSideMenuOpen,
                selectedTab: $selectedTab,
                presentedSheet: $sideMenuSheet,
                headerTopPadding: sideMenuHeaderTopPadding,
                onPickSearch: {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        searchFieldFocused = true
                    }
                }
            )
            .frame(width: menuWidth)
            .frame(maxHeight: .infinity)
            .zIndex(0)

            let floatingChromeInset: CGFloat = {
                if isSearchDetailActive { return 0 }
                return RootChromeEnvironment.searchBarStackHeight
            }()

            ZStack(alignment: .top) {
                ZStack(alignment: .top) {
                    TabView(selection: $selectedTab) {
                        ForEach(AppTab.allCases) { tab in
                            Group {
                                switch tab {
                                case .dashboard:
                                    DashboardPlaceholderView()
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
                                            filterRarityOptions: $browseFilterRarityOptions
                                        )
                                    }
                                case .wishlist:
                                    NavigationStack {
                                        WishlistView()
                                    }
                                case .collection:
                                    NavigationStack {
                                        CollectionListView()
                                    }
                                case .bindrs:
                                    BindrsPlaceholderView()
                                }
                            }
                            .toolbarBackground(.hidden, for: .navigationBar)
                            .tabItem {
                                Label(tab.title, systemImage: tab.symbolName)
                            }
                            .tag(tab)
                        }
                    }
                    .allowsHitTesting(!isSideMenuOpen)

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
                            SearchExperienceView(
                                query: $universalQuery,
                                onBrowseSets: {
                                    searchNavigationPath = NavigationPath()
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                                        isSearchExperiencePresented = false
                                    }
                                    searchFieldFocused = false
                                    browseFullScreen = .allSets
                                },
                                onBrowsePokemon: {
                                    searchNavigationPath = NavigationPath()
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                                        isSearchExperiencePresented = false
                                    }
                                    searchFieldFocused = false
                                    browseFullScreen = .allPokemon
                                }
                            )
                            .navigationDestination(for: SearchNavRoot.self) { root in
                                switch root {
                                case .set(let s):
                                    SetCardsView(set: s)
                                        .onAppear { searchFieldFocused = false }
                                case .dex(let dexId, let displayName):
                                    DexCardsView(dexId: dexId, displayName: displayName)
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
                        .allowsHitTesting(!isSideMenuOpen)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.spring(response: 0.38, dampingFraction: 0.88), value: isSearchExperiencePresented)
                .environment(\.rootFloatingChromeInset, floatingChromeInset)

                // Floating above tab content so `.ultraThinMaterial` / Liquid Glass blur the grid behind the bar.
                UniversalSearchBar(
                    text: $universalQuery,
                    isFocused: $searchFieldFocused,
                    isMenuOpen: isSideMenuOpen,
                    isSearchOpen: isSearchExperiencePresented,
                    isFilterEnabled: isBrowseGridFilterContextActive,
                    isFilterActive: browseFilters.isVisiblyCustomized,
                    filterMenuContent: isBrowseGridFilterContextActive ? AnyView(browseFilterMenuContent) : nil,
                    onBurgerTap: {
                        if isSearchExperiencePresented {
                            searchNavigationPath = NavigationPath()
                            universalQuery = ""
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                                isSearchExperiencePresented = false
                            }
                            searchFieldFocused = false
                            return
                        }
                        searchFieldFocused = false
                        isSearchExperiencePresented = false
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                            isSideMenuOpen.toggle()
                        }
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
                .offset(y: showUniversalSearchBar && !isSearchDetailActive ? 0 : searchBarHiddenOffset)
                .opacity(showUniversalSearchBar && !isSearchDetailActive ? 1 : 0.001)
                .padding(.horizontal, 16)
                .padding(.top, searchBarTopInset)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity, alignment: .top)
                .allowsHitTesting(showUniversalSearchBar && !isSearchDetailActive)
                .animation(.easeInOut(duration: 0.22), value: chromeScroll.barsVisible)
                .animation(.spring(response: 0.35, dampingFraction: 0.86), value: isSideMenuOpen)
                .animation(.spring(response: 0.35, dampingFraction: 0.86), value: isSearchExperiencePresented)
                .animation(.spring(response: 0.35, dampingFraction: 0.86), value: isSearchDetailActive)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // System background shows through the material where the bar is translucent.
            .background(Color(uiColor: .systemBackground))
            .offset(x: isSideMenuOpen ? menuWidth : 0)
            .shadow(
                color: .black.opacity(isSideMenuOpen ? 0.45 : 0),
                radius: 18,
                x: -10,
                y: 0
            )
            .overlay(alignment: .topLeading) {
                if isEdgeSwipeMenuEnabled {
                    LeftEdgeOpenMenuGesture(isEnabled: true) {
                        searchFieldFocused = false
                        searchNavigationPath = NavigationPath()
                        isSearchExperiencePresented = false
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                            isSideMenuOpen = true
                        }
                    }
                    .frame(width: 28)
                    .padding(.top, edgeSwipeBelowSearchBar)
                    .padding(.bottom, max(geo.safeAreaInsets.bottom, 12) + 52)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .zIndex(400)
                }
            }
            .overlay(alignment: .trailing) {
                if isSideMenuOpen {
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: max(0, width - menuWidth))
                        .frame(maxHeight: .infinity)
                        .ignoresSafeArea(edges: .vertical)
                        .onTapGesture {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                                isSideMenuOpen = false
                            }
                        }
                }
            }
            .zIndex(1)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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
                withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) {
                    isSearchExperiencePresented = true
                }
            }
        }
        .onAppear {
            chromeScroll.configureForTab(selectedTab)
            if services.isReady {
                services.setupWishlist(modelContext: modelContext)
                services.setupCollectionLedger(modelContext: modelContext)
            }
        }
        .onChange(of: services.isReady) { _, ready in
            if ready {
                services.setupWishlist(modelContext: modelContext)
                services.setupCollectionLedger(modelContext: modelContext)
            }
        }
        .onChange(of: selectedTab) { _, tab in
            Haptics.selectionChanged()
            chromeScroll.configureForTab(tab)
        }
        .onChange(of: browseNavigationPath.count) { _, newCount in
            if newCount == 0 {
                chromeScroll.forceVisible()
            }
        }
        .onChange(of: isSideMenuOpen) { _, open in
            if open { chromeScroll.forceVisible() }
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
        .fullScreenCover(item: $sideMenuSheet) { destination in
            Group {
                switch destination {
                case .account:
                    AccountView()
                case .transactions:
                    TransactionsView()
                }
            }
            .environment(services)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack {
                    Text(destination == .account ? "Account" : "Transactions")
                        .font(.headline.weight(.semibold))
                    Spacer()
                    Button("Done") {
                        sideMenuSheet = nil
                    }
                    .fontWeight(.semibold)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(.bar)
            }
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
                }
            }
            .animation(.easeInOut(duration: 0.22), value: services.isCatalogDownloadInProgress)
        }
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
            Menu(menuTitle("Card type", summary: selectionSummary(for: browseFilters.cardTypes))) {
                ForEach(BrowseCardTypeFilter.allCases) { type in
                    Toggle(type.title, isOn: binding(for: type))
                }
            }
            .menuActionDismissBehavior(.disabled)
            .menuOrder(.fixed)

            Toggle("Rare + only", isOn: $browseFilters.rarePlusOnly)
            Toggle("Hide owned", isOn: $browseFilters.hideOwned)

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
        }

        Section("Grid options") {
            Menu("Grid options") {
                Toggle("Show card name", isOn: gridOptionBinding(\.showCardName))
                Toggle("Show set name", isOn: gridOptionBinding(\.showSetName))
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
}

#Preview {
    RootView()
}
