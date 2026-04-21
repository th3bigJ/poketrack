import SwiftData
import SwiftUI

// MARK: - Shared card grid cell

struct CardGridCell: View {
    let card: Card
    var gridOptions = BrowseGridOptions()
    var setName: String? = nil
    /// Optional line under the name (e.g. wishlist variant key).
    var footnote: String? = nil

    var body: some View {
        VStack(spacing: 4) {
            BrowseCardThumbnailView(imageURL: AppConfiguration.imageURL(relativePath: card.imageLowSrc))
            .frame(maxWidth: .infinity)
            .aspectRatio(5/7, contentMode: .fit)
            if gridOptions.showCardName {
                Text(card.cardName)
                    .font(.caption2)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
            }
            if gridOptions.showSetName, let setName, !setName.isEmpty {
                Text(setName)
                    .font(.caption2)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            if gridOptions.showSetID {
                Text(card.setCode)
                    .font(.caption2)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            if gridOptions.showOwned, let footnote, !footnote.isEmpty {
                Text(footnote)
                    .font(.caption2)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            if gridOptions.showPricing {
                BrowseGridPriceText(card: card)
            }
        }
    }
}

private struct BrowseCardThumbnailView: View {
    let imageURL: URL?

    var body: some View {
        AsyncImage(url: imageURL, transaction: Transaction(animation: .easeOut(duration: 0.18))) { phase in
            switch phase {
            case let .success(image):
                image
                    .resizable()
                    .scaledToFit()
            case .failure, .empty:
                Color.gray.opacity(0.12)
                    .aspectRatio(5 / 7, contentMode: .fit)
            @unknown default:
                Color.gray.opacity(0.12)
                    .aspectRatio(5 / 7, contentMode: .fit)
            }
        }
    }
}

/// Subtle spring scale on press for all card grid cells — gives a premium tactile feel.
struct CardCellButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

private struct BrowseCardRow: Identifiable {
    let id: Int
    let card: Card
    let setName: String?
}

private struct BrowseFeedSnapshot {
    var cards: [Card] = []
    var rows: [BrowseCardRow] = []
    var hasMoreCardsToLoad = false
}

enum BrowseHomeTab: String, CaseIterable, Identifiable {
    case cards
    case sets
    case pokemon
    case sealed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cards: return "Cards"
        case .sets: return "Sets"
        case .pokemon: return "Pokemon"
        case .sealed: return "Sealed"
        }
    }
}

enum BrowseInlineDetailRoute: Hashable {
    case set(TCGSet)
    case dex(dexId: Int, displayName: String)
    case onePieceCharacter(String)
    case onePieceSubtype(String)

    var title: String {
        switch self {
        case .set(let set):
            return set.name
        case .dex(_, let displayName):
            return displayName
        case .onePieceCharacter(let name), .onePieceSubtype(let name):
            return name
        }
    }
}

private struct BrowseCardListView: View {
    let cards: [Card]
    let rows: [BrowseCardRow]
    let gridOptions: BrowseGridOptions
    let isLoadingMore: Bool
    let hasMoreCardsToLoad: Bool
    let presentCard: (Card, [Card]) -> Void
    let onLoadMore: () -> Void

    @State private var lastAutoLoadRowCount = 0

    private var safeColumnCount: Int {
        min(max(gridOptions.columnCount, 1), 4)
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: safeColumnCount)
    }

    var body: some View {
        VStack(spacing: 0) {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(rows) { row in
                    Button {
                        presentCard(row.card, cards)
                    } label: {
                        CardGridCell(
                            card: row.card,
                            gridOptions: gridOptions,
                            setName: row.setName
                        )
                    }
                    .buttonStyle(CardCellButtonStyle())
                    .frame(maxWidth: .infinity, alignment: .top)
                    .onAppear {
                        guard hasMoreCardsToLoad else { return }
                        guard row.id >= max(rows.count - safeColumnCount, 0) else { return }
                        guard rows.count != lastAutoLoadRowCount else { return }
                        lastAutoLoadRowCount = rows.count
                        DispatchQueue.main.async {
                            onLoadMore()
                        }
                    }
                }
            }
            if isLoadingMore {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 16)
        .onChange(of: rows.count) { _, newValue in
            if newValue < lastAutoLoadRowCount {
                lastAutoLoadRowCount = 0
            }
        }
    }
}

// MARK: - Browse feed

@MainActor
struct BrowseView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.presentCard) private var presentCard
    @Environment(\.rootFloatingChromeInset) private var rootFloatingChromeInset
    @Query private var collectionItems: [CollectionItem]

    @Binding var filters: BrowseCardGridFilters
    @Binding var inlineDetailFilters: BrowseCardGridFilters
    @Binding var gridOptions: BrowseGridOptions
    @Binding var isFilterMenuPresented: Bool
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

    @State private var shuffledRefs: [CardRef] = []
    @State private var nextRefIndex = 0
    @State private var displayedCards: [Card] = []
    @State private var displayedRows: [BrowseCardRow] = []
    @State private var allBrowseFilterCards: [BrowseFilterCard] = []
    @State private var catalogOrderedRefs: [CardRef] = []
    @State private var catalogDisplayedCards: [Card] = []
    @State private var catalogDisplayedRows: [BrowseCardRow] = []
    @State private var browseFeedSnapshot = BrowseFeedSnapshot()
    @State private var catalogNextIndex = 0
    @State private var isLoadingInitial = true
    @State private var isLoadingMore = false
    @State private var isPreparingFilterCatalog = false
    /// Prevents concurrent full-filter-index loads (background warm vs active filter feed).
    @State private var isLoadingFullCatalog = false
    @State private var loadedBrand: TCGBrand?
    @State private var cachedSetNameByCode: [String: String] = [:]
    @State private var query = ""
    @State private var inlineDetailCards: [Card] = []
    @State private var inlineDetailQuery = ""
    @State private var inlineDetailLoading = false
    @State private var ownedCardIDsCache: Set<String> = []
    @State private var isUsingCatalogFeedSelection = false
    @State private var isInlineDetailPresented = false
    @State private var isViewVisible = false
    @State private var visibleBrowseResultCount = 0
    @State private var isBrowseBodyReady = false
    @State private var currentBrand: TCGBrand = .pokemon

    private var safeColumnCount: Int {
        min(max(gridOptions.columnCount, 1), 4)
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: safeColumnCount)
    }

    private static let initialBatchSize = 36
    private static let catalogInitialBatchSize = 36
    private static let pageSize = 18
    private static let prefetchBuffer = 8

    var body: some View {
        Group {
            if isBrowseBodyReady {
                browseBodyContent
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .onAppear {
            isViewVisible = true
            isInlineDetailPresented = (inlineDetailRoute != nil)
            currentBrand = services.brandSettings.selectedCatalogBrand
            if isBrowseBodyReady == false {
                Task { @MainActor in
                    await Task.yield()
                    guard isViewVisible else { return }
                    isBrowseBodyReady = true
                }
            }
            let brandSnapshot = services.brandSettings.selectedCatalogBrand
            Task { @MainActor in
                await Task.yield()
                guard isViewVisible else { return }
                await scheduleOwnedCardIDsRefresh(for: brandSnapshot)
                await scheduleBrowseInitialization(for: brandSnapshot)
            }
        }
        .onDisappear {
            isViewVisible = false
        }
        .onChange(of: services.brandSettings.selectedCatalogBrand) { _, newBrand in
            currentBrand = newBrand
            Task { @MainActor in
                await Task.yield()
                guard isViewVisible else { return }
                await scheduleOwnedCardIDsRefresh(for: newBrand)
                await scheduleBrowseInitialization(for: newBrand)
            }
        }
        .onChange(of: filters) { _, newFilters in
            guard !isInlineDetailPresented else { return }
            let shouldUseCatalogFeed = selectedTab == .cards
                && (!query.isEmpty || newFilters.hasActiveFieldFilters || newFilters.hasActiveSort)
            Task { @MainActor in
                await Task.yield()
                guard isViewVisible else { return }
                handleBrowseFiltersChanged(usingCatalogFeed: shouldUseCatalogFeed)
            }
        }
        .onChange(of: query) { _, newQuery in
            guard selectedTab == .cards else { return }
            let shouldUseCatalogFeed = !newQuery.isEmpty || filters.hasActiveFieldFilters || filters.hasActiveSort
            Task { @MainActor in
                await Task.yield()
                guard isViewVisible else { return }
                handleBrowseFiltersChanged(usingCatalogFeed: shouldUseCatalogFeed)
            }
        }
        .onChange(of: selectedTab) { _, newValue in
            Task { @MainActor in
                await Task.yield()
                guard isViewVisible else { return }
                query = ""
                if tabSupportsInlineDetail(newValue) == false {
                    inlineDetailRoute = nil
                }
                if newValue != .cards {
                    isUsingCatalogFeedSelection = false
                    syncFilterMenuState(usingCatalogFeed: false)
                } else {
                    let shouldUseCatalogFeed = !query.isEmpty || filters.hasActiveFieldFilters || filters.hasActiveSort
                    handleBrowseFiltersChanged(usingCatalogFeed: shouldUseCatalogFeed)
                }
            }
        }
        .onChange(of: inlineDetailRoute) { _, newValue in
            Task { @MainActor in
                await Task.yield()
                guard isViewVisible else { return }
                isInlineDetailPresented = (newValue != nil)
                inlineDetailQuery = ""
                inlineDetailFilters = BrowseCardGridFilters()
                await loadInlineDetailIfNeeded(route: newValue)
            }
        }
    }

    @MainActor
    private func scheduleBrowseInitialization(for selectedBrand: TCGBrand) async {
        guard isViewVisible else { return }
        let selectedTabSnapshot = selectedTab
        let querySnapshot = query
        // Avoid reading filter bindings during immediate appearance updates.
        // The active filters/query pipeline will reconcile right after startup.
        let filtersSnapshot = BrowseCardGridFilters()
        // Avoid touching the `@Query`-backed collection rows during SwiftUI's
        // appearance update cycle. Ownership-sensitive filters are refreshed
        // later through the normal change handlers once the view is stable.
        let ownedCardIDsSnapshot: Set<String> = []
        let shouldUseCatalogFeedOnStartup = false
        isUsingCatalogFeedSelection = shouldUseCatalogFeedOnStartup
        await initializeBrowseData(
            for: selectedBrand,
            selectedTabSnapshot: selectedTabSnapshot,
            querySnapshot: querySnapshot,
            filtersSnapshot: filtersSnapshot,
            ownedCardIDsSnapshot: ownedCardIDsSnapshot,
            shouldUseCatalogFeedOnStartup: shouldUseCatalogFeedOnStartup
        )
    }

    @MainActor
    private func scheduleOwnedCardIDsRefresh(for brand: TCGBrand) async {
        guard isViewVisible else { return }
        await Task.yield()
        guard isViewVisible else { return }
        ownedCardIDsCache = Set(collectionItems.compactMap { item in
            let itemBrand = TCGBrand.inferredFromMasterCardId(item.cardID)
            return itemBrand == brand ? item.cardID : nil
        })
        if isInlineDetailPresented {
            syncFilterMenuState(usingCatalogFeed: false)
        } else {
            // Avoid re-entering the feed-selection decision path from the
            // ownership refresh task; preserve current feed mode and only
            // rebuild catalog results when that mode is already active.
            if isUsingCatalogFeedSelection {
                guard isViewVisible else { return }
                await ensureAllBrowseFilterCardsLoaded(showsPreparingBanner: false)
                await rebuildCatalogFeedIfNeeded(
                    selectedTab: selectedTab,
                    query: query,
                    filters: filters,
                            brand: currentBrand,
                    ownedCardIDs: ownedCardIDsCache,
                    shouldUseCatalogFeed: true
                )
            } else {
                syncFilterMenuState(usingCatalogFeed: false)
            }
        }
    }

    @ViewBuilder
    private var browseBodyContent: some View {
        if selectedTab == .cards {
            cardsTabScrollView
        } else {
            auxiliaryTabScrollView
        }
    }

    @MainActor
    private func initializeBrowseData(
        for selectedBrand: TCGBrand,
        selectedTabSnapshot: BrowseHomeTab,
        querySnapshot: String,
        filtersSnapshot: BrowseCardGridFilters,
        ownedCardIDsSnapshot: Set<String>,
        shouldUseCatalogFeedOnStartup: Bool
    ) async {
        guard isViewVisible else { return }
        if loadedBrand != selectedBrand {
            shuffledRefs = []
            nextRefIndex = 0
            displayedCards = []
            displayedRows = []
            allBrowseFilterCards = []
            catalogOrderedRefs = []
            catalogDisplayedCards = []
            catalogDisplayedRows = []
            browseFeedSnapshot = BrowseFeedSnapshot()
            catalogNextIndex = 0
            isLoadingInitial = true

            // The root startup pipeline already refreshes catalog data.
            // Browse only needs to ensure the selected brand's sets are present.
            services.cardData.resetBrowseFeedSessionOnly()
            await services.cardData.loadSets(preferSyncedCatalog: true)
            guard isViewVisible else { return }
            cachedSetNameByCode = firstValueMap(services.cardData.sets, key: \.setCode, value: \.name)
            loadedBrand = selectedBrand
        } else if cachedSetNameByCode.isEmpty, services.cardData.sets.isEmpty == false {
            cachedSetNameByCode = firstValueMap(services.cardData.sets, key: \.setCode, value: \.name)
        }

        await Task.yield()
        await Task.yield()
        guard isViewVisible else { return }
        await bootstrapFeed(forceReshuffle: false)
        guard isViewVisible else { return }
        if shouldUseCatalogFeedOnStartup {
            await ensureAllBrowseFilterCardsLoaded(
                showsPreparingBanner: true,
                usingCatalogFeed: true
            )
            guard isViewVisible else { return }
            await rebuildCatalogFeedIfNeeded(
                selectedTab: selectedTabSnapshot,
                query: querySnapshot,
                filters: filtersSnapshot,
                brand: selectedBrand,
                ownedCardIDs: ownedCardIDsSnapshot,
                shouldUseCatalogFeed: shouldUseCatalogFeedOnStartup
            )
        } else {
            await ensureAllBrowseFilterCardsLoaded(
                showsPreparingBanner: false,
                usingCatalogFeed: false
            )
        }
    }

    private var browseCardGrid: some View {
        let usesCatalogFeedSnapshot = isUsingCatalogFeedSelection
        return BrowseCardListView(
            cards: browseFeedSnapshot.cards,
            rows: browseFeedSnapshot.rows,
            gridOptions: gridOptions,
            isLoadingMore: isLoadingMore,
            hasMoreCardsToLoad: browseFeedSnapshot.hasMoreCardsToLoad,
            presentCard: presentCard,
            onLoadMore: {
                Task { await loadNextPageIfNeeded(usingCatalogFeed: usesCatalogFeedSnapshot) }
            }
        )
    }

    private var browseSearchPlaceholder: String {
        if let inlineDetailRoute {
            switch inlineDetailRoute {
            case .set:
                return "Search cards in set"
            case .dex:
                return "Search cards for Pokémon"
            case .onePieceCharacter:
                return "Search cards for character"
            case .onePieceSubtype:
                return "Search cards for subtype"
            }
        }
        switch selectedTab {
        case .cards:
            return "Search cards"
        case .sets:
            return "Search sets"
        case .pokemon:
            return currentBrand == .pokemon ? "Search Pokémon" : "Search characters or subtypes"
        case .sealed:
            return "Search sealed"
        }
    }

    @ViewBuilder
    private var browseTabsRow: some View {
        if isInlineDetailPresented {
            EmptyView()
        } else {
            Picker("Browse section", selection: $selectedTab) {
                ForEach(BrowseHomeTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
    }

    private var browseSearchRow: some View {
        BrowseInlineSearchField(
            title: browseSearchPlaceholder,
            text: isInlineDetailPresented ? $inlineDetailQuery : $query
        )
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
    }

    @ViewBuilder
    private var browseResultCountRow: some View {
        if selectedTab == .cards || isInlineDetailPresented {
            Text("\(visibleBrowseResultCount) cards")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
        }
    }

    private var cardsTabScrollView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // Keeps first row clear of the overlaid search bar; spacer scrolls away so cards can pass under the glass.
                Color.clear
                    .frame(height: rootFloatingChromeInset)
                browseTabsRow
                browseSearchRow
                browseResultCountRow
                activeTabContent
                if selectedTab == .cards && isPreparingFilterCatalog {
                    ProgressView("Preparing filters…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                if selectedTab == .cards && isLoadingMore {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 12)
                }
            }
        }
    }

    private var auxiliaryTabScrollView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                Color.clear
                    .frame(height: rootFloatingChromeInset)
                browseTabsRow
                browseSearchRow
                browseResultCountRow
                activeTabContent
            }
        }
    }

    @ViewBuilder
    private var activeTabContent: some View {
        switch selectedTab {
        case .cards:
            browseCardsContent
        case .sets:
            if let inlineDetailRoute {
                inlineDetailContent(route: inlineDetailRoute)
            } else {
                BrowseSetsTabContent(query: query) { set in
                    inlineDetailRoute = .set(set)
                }
            }
        case .pokemon:
            if let inlineDetailRoute {
                inlineDetailContent(route: inlineDetailRoute)
            } else {
                BrowsePokemonTabContent(query: query) { route in
                    inlineDetailRoute = route
                }
            }
        case .sealed:
            ContentUnavailableView(
                "Sealed coming soon",
                systemImage: "shippingbox",
                description: Text("This tab is a placeholder until sealed products are added.")
            )
            .frame(maxWidth: .infinity, minHeight: 280)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    @ViewBuilder
    private func inlineDetailContent(route: BrowseInlineDetailRoute) -> some View {
        let filteredCards = filteredInlineDetailCards
        if inlineDetailLoading {
            ProgressView("Loading cards…")
                .frame(maxWidth: .infinity, minHeight: 280)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        } else if filteredCards.isEmpty {
            ContentUnavailableView(
                inlineDetailCards.isEmpty ? "No cards found" : "No matching cards",
                systemImage: "magnifyingglass",
                description: Text(inlineDetailCards.isEmpty ? "No cards were found for \(route.title)." : "Try a different card name or number.")
            )
            .frame(maxWidth: .infinity, minHeight: 280)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        } else {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(Array(filteredCards.enumerated()), id: \.element.id) { index, card in
                    Button {
                        presentCard(card, filteredCards)
                    } label: {
                        CardGridCell(
                            card: card,
                            gridOptions: gridOptions,
                            setName: cachedSetNameByCode[card.setCode]
                        )
                    }
                    .buttonStyle(CardCellButtonStyle())
                    .onAppear {
                        ImagePrefetcher.shared.prefetchCardWindow(filteredCards, startingAt: index + 1)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    private var filteredInlineDetailCards: [Card] {
        filterBrowseCards(
            inlineDetailCards,
            query: inlineDetailQuery,
            filters: inlineDetailFilters,
            ownedCardIDs: ownedCardIDsCache,
            brand: currentBrand,
            sets: services.cardData.sets
        )
    }

    @ViewBuilder
    private var browseCardsContent: some View {
        if isLoadingInitial {
            ProgressView("Loading cards…")
                .frame(maxWidth: .infinity, minHeight: 280)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        } else if displayedCards.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("No cards in the catalog yet.")
                    .foregroundStyle(.secondary)
                if let err = services.cardData.lastError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Text("Pull to refresh after your catalog syncs, or check BINDR_R2_BASE_URL in Info.plist.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, minHeight: 280, alignment: .center)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        } else {
            browseCardGrid
        }
    }

    @MainActor
    private func bootstrapFeed(forceReshuffle: Bool) async {
        guard isViewVisible else { return }
        if !forceReshuffle && !displayedCards.isEmpty { return }
        ImagePrefetcher.shared.cancelAll()
        isLoadingInitial = true
        let refs = await services.cardData.browseFeedCardRefs(forceReshuffle: forceReshuffle)
        guard isViewVisible else { return }
        shuffledRefs = refs
        nextRefIndex = 0
        displayedCards = []
        guard !refs.isEmpty else { isLoadingInitial = false; return }
        let firstEnd = min(Self.initialBatchSize, refs.count)
        let batch = Array(refs[..<firstEnd])
        nextRefIndex = firstEnd
        displayedCards = await services.cardData.cardsInOrder(refs: batch)
        guard isViewVisible else { return }
        displayedRows = buildBrowseRows(from: displayedCards)
        allBrowseFilterCards = []
        catalogOrderedRefs = []
        catalogDisplayedCards = []
        catalogDisplayedRows = []
        catalogNextIndex = 0
        refreshBrowseFeedSnapshot(usingCatalogFeed: false)
        isLoadingInitial = false
        ImagePrefetcher.shared.prefetchCardWindow(displayedCards, startingAt: 0, count: 24)
        prefetchNextWindow(usingCatalogFeed: false)
        syncFilterMenuState(usingCatalogFeed: false)
    }

    @MainActor
    private func loadNextPageIfNeeded(usingCatalogFeed: Bool) async {
        guard isViewVisible else { return }
        guard !isLoadingMore else { return }
        if usingCatalogFeed {
            guard catalogNextIndex < catalogOrderedRefs.count else { return }
            isLoadingMore = true
            let end = min(catalogNextIndex + Self.pageSize, catalogOrderedRefs.count)
            let batch = Array(catalogOrderedRefs[catalogNextIndex..<end])
            catalogNextIndex = end
            let more = await services.cardData.cardsInOrder(refs: batch)
            guard isViewVisible else { return }
            catalogDisplayedCards.append(contentsOf: more)
            catalogDisplayedRows = buildBrowseRows(from: catalogDisplayedCards)
            refreshBrowseFeedSnapshot(usingCatalogFeed: true)
            isLoadingMore = false
            syncFilterMenuState(usingCatalogFeed: true)
            return
        }
        guard nextRefIndex < shuffledRefs.count else { return }
        isLoadingMore = true
        let end = min(nextRefIndex + Self.pageSize, shuffledRefs.count)
        let batch = Array(shuffledRefs[nextRefIndex..<end])
        nextRefIndex = end
        let more = await services.cardData.cardsInOrder(refs: batch)
        guard isViewVisible else { return }
        displayedCards.append(contentsOf: more)
        displayedRows = buildBrowseRows(from: displayedCards)
        refreshBrowseFeedSnapshot(usingCatalogFeed: false)
        isLoadingMore = false
        prefetchNextWindow(usingCatalogFeed: false)
        syncFilterMenuState(usingCatalogFeed: false)
    }

    private func prefetchNextWindow(usingCatalogFeed: Bool) {
        guard usingCatalogFeed == false else { return }
        let end = min(nextRefIndex + Self.pageSize, shuffledRefs.count)
        guard nextRefIndex < end else { return }
        let upcoming = Array(shuffledRefs[nextRefIndex..<end])
        Task(priority: .low) {
            let cards = await services.cardData.cardsInOrder(refs: upcoming)
            let urls = cards.map { AppConfiguration.imageURL(relativePath: $0.imageLowSrc) }
            ImagePrefetcher.shared.prefetch(urls)
        }
    }

    @MainActor
    private func ensureAllBrowseFilterCardsLoaded(
        showsPreparingBanner: Bool = true,
        usingCatalogFeed: Bool? = nil
    ) async {
        guard isViewVisible else { return }
        if !allBrowseFilterCards.isEmpty { return }
        while isLoadingFullCatalog {
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        if !allBrowseFilterCards.isEmpty { return }
        isLoadingFullCatalog = true
        if showsPreparingBanner {
            isPreparingFilterCatalog = true
        }
        let loaded = await services.cardData.loadAllBrowseFilterCards()
        guard isViewVisible else { return }
        allBrowseFilterCards = loaded
        isLoadingFullCatalog = false
        if showsPreparingBanner {
            isPreparingFilterCatalog = false
        }
        syncFilterMenuState(usingCatalogFeed: usingCatalogFeed)
    }

    @MainActor
    private func rebuildCatalogFeedIfNeeded(
        selectedTab: BrowseHomeTab,
        query: String,
        filters: BrowseCardGridFilters,
        brand: TCGBrand,
        ownedCardIDs: Set<String>,
        shouldUseCatalogFeed: Bool
    ) async {
        guard isViewVisible else { return }
        if shouldUseCatalogFeed == false {
            isUsingCatalogFeedSelection = false
            catalogOrderedRefs = []
            catalogDisplayedCards = []
            catalogDisplayedRows = []
            catalogNextIndex = 0
            refreshBrowseFeedSnapshot(usingCatalogFeed: false)
            syncFilterMenuState(usingCatalogFeed: false)
            return
        }
        guard !allBrowseFilterCards.isEmpty else { return }
        let ordered = await orderedFilteredRefs(
            from: allBrowseFilterCards,
            query: query,
            filters: filters,
            brand: brand,
            ownedCardIDs: ownedCardIDs
        )
        guard isViewVisible else { return }
        isUsingCatalogFeedSelection = true
        catalogOrderedRefs = ordered
        let initialEnd = min(Self.catalogInitialBatchSize, ordered.count)
        let initialRefs = Array(ordered.prefix(initialEnd))
        catalogDisplayedCards = await services.cardData.cardsInOrder(refs: initialRefs)
        guard isViewVisible else { return }
        catalogDisplayedRows = buildBrowseRows(from: catalogDisplayedCards)
        catalogNextIndex = initialEnd
        refreshBrowseFeedSnapshot(usingCatalogFeed: true)
        syncFilterMenuState(usingCatalogFeed: true)
    }

    @MainActor
    private func handleBrowseFiltersChanged(usingCatalogFeed: Bool) {
        if isInlineDetailPresented {
            syncFilterMenuState(usingCatalogFeed: false)
            return
        }
        let selectedTabSnapshot = selectedTab
        let querySnapshot = query
        let filtersSnapshot = filters
        let brandSnapshot = currentBrand
        let ownedCardIDsSnapshot = ownedCardIDsCache
        let isUsingCatalogFeed = usingCatalogFeed
        isUsingCatalogFeedSelection = isUsingCatalogFeed
        if isUsingCatalogFeed {
            Task {
                await ensureAllBrowseFilterCardsLoaded(showsPreparingBanner: true)
                await rebuildCatalogFeedIfNeeded(
                    selectedTab: selectedTabSnapshot,
                    query: querySnapshot,
                    filters: filtersSnapshot,
                    brand: brandSnapshot,
                    ownedCardIDs: ownedCardIDsSnapshot,
                    shouldUseCatalogFeed: isUsingCatalogFeed
                )
            }
        } else {
            catalogOrderedRefs = []
            catalogDisplayedCards = []
            catalogDisplayedRows = []
            catalogNextIndex = 0
            refreshBrowseFeedSnapshot(usingCatalogFeed: false)
            syncFilterMenuState(usingCatalogFeed: false)
        }
    }

    private func refreshBrowseFeedSnapshot(usingCatalogFeed: Bool) {
        if usingCatalogFeed {
            browseFeedSnapshot = BrowseFeedSnapshot(
                cards: catalogDisplayedCards,
                rows: catalogDisplayedRows,
                hasMoreCardsToLoad: catalogNextIndex < catalogOrderedRefs.count
            )
        } else {
            browseFeedSnapshot = BrowseFeedSnapshot(
                cards: displayedCards,
                rows: displayedRows,
                hasMoreCardsToLoad: nextRefIndex < shuffledRefs.count
            )
        }
    }

    private func buildBrowseRows(from cards: [Card]) -> [BrowseCardRow] {
        let setNames = cachedSetNameByCode
        var rows: [BrowseCardRow] = []
        rows.reserveCapacity(cards.count)
        for (index, card) in cards.enumerated() {
            rows.append(
                BrowseCardRow(
                    id: index,
                    card: card,
                    setName: setNames[card.setCode]
                )
            )
        }
        return rows
    }

    private func orderedFilteredRefs(
        from cards: [BrowseFilterCard],
        query: String,
        filters: BrowseCardGridFilters,
        brand: TCGBrand,
        ownedCardIDs: Set<String>
    ) async -> [CardRef] {
        let filtered = filterCards(
            cards,
            query: query,
            filters: filters,
            brand: brand,
            ownedCardIDs: ownedCardIDs
        )
        switch filters.sortBy {
        case .random, .acquiredDateNewest:
            let filteredIDs = Set(filtered.map(\.masterCardId))
            let shuffled = shuffledRefs.filter { filteredIDs.contains($0.masterCardId) }
            let covered = Set(shuffled.map(\.masterCardId))
            let remainder = Array(filtered.lazy.filter { !covered.contains($0.masterCardId) }.map(\.ref))
            return shuffled + remainder
        case .newestSet:
            return sortBrowseFilterCardsByReleaseDateNewestFirst(filtered, sets: services.cardData.sets).map(\.ref)
        case .cardName:
            return filtered
                .sorted { $0.cardName.localizedCaseInsensitiveCompare($1.cardName) == .orderedAscending }
                .map(\.ref)
        case .cardNumber:
            return filtered.sorted {
                if $0.setCode != $1.setCode {
                    return compareReleaseDateNewestFirst(lhsSetCode: $0.setCode, rhsSetCode: $1.setCode)
                }
                return $0.cardNumber.localizedStandardCompare($1.cardNumber) == .orderedAscending
            }.map(\.ref)
        case .price:
            let refs = filtered.map(\.ref)
            let cards = await services.cardData.cardsInOrder(refs: refs)
            var pricedCards: [(card: Card, price: Double?)] = []
            pricedCards.reserveCapacity(cards.count)
            for card in cards {
                let entry = await services.pricing.pricing(for: card)
                pricedCards.append((card, browseMarketPriceUSD(for: entry)))
            }
            return pricedCards.sorted { lhs, rhs in
                switch (lhs.price, rhs.price) {
                case let (l?, r?):
                    if l != r { return l > r }
                case (.some, nil):
                    return true
                case (nil, .some):
                    return false
                case (nil, nil):
                    break
                }
                if lhs.card.cardName != rhs.card.cardName {
                    return lhs.card.cardName.localizedCaseInsensitiveCompare(rhs.card.cardName) == .orderedAscending
                }
                if lhs.card.setCode != rhs.card.setCode {
                    return compareReleaseDateNewestFirst(lhsSetCode: lhs.card.setCode, rhsSetCode: rhs.card.setCode)
                }
                return lhs.card.cardNumber.localizedStandardCompare(rhs.card.cardNumber) == .orderedAscending
            }.map { CardRef(masterCardId: $0.card.masterCardId, setCode: $0.card.setCode) }
        }
    }

    private func filterCards(
        _ cards: [BrowseFilterCard],
        query: String,
        filters: BrowseCardGridFilters,
        brand: TCGBrand,
        ownedCardIDs: Set<String>
    ) -> [BrowseFilterCard] {
        let loweredQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let setReleaseDateByCode = firstValueMap(services.cardData.sets, key: \.setCode) { $0.releaseDate ?? "" }
        return cards.filter { card in
            let matchesQuery = loweredQuery.isEmpty
                || card.cardName.lowercased().contains(loweredQuery)
                || card.cardNumber.lowercased().contains(loweredQuery)
                || card.setCode.lowercased().contains(loweredQuery)
                || (card.subtype?.lowercased().contains(loweredQuery) == true)
                || (card.subtypes?.contains { $0.lowercased().contains(loweredQuery) } == true)
            guard matchesQuery else { return false }

            if brand == .pokemon,
               filters.cardTypes.isEmpty == false,
               filters.cardTypes.contains(resolvedCardType(for: card, brand: brand)) == false {
                return false
            }
            if filters.rarePlusOnly && isCommonOrUncommon(card.rarity) {
                return false
            }
            if filters.hideOwned && ownedCardIDs.contains(card.masterCardId) {
                return false
            }
            if brand == .pokemon,
               filters.legalities.isEmpty == false,
               pokemonCardMatchesLegalityFilters(
                    selectedLegalityFilters: filters.legalities,
                    setCode: card.setCode,
                    releaseDate: setReleaseDateByCode[card.setCode],
                    category: card.category,
                    energyType: card.energyType,
                    regulationMark: card.regulationMark,
                    cardName: card.cardName
               ) == false {
                return false
            }
            if filters.energyTypes.isEmpty == false {
                let energies = Set(resolvedEnergyTypes(for: card))
                if energies.isDisjoint(with: filters.energyTypes) {
                    return false
                }
            }
            if filters.rarities.isEmpty == false {
                let rarity = trimmedValue(card.rarity)
                if rarity.isEmpty || filters.rarities.contains(rarity) == false {
                    return false
                }
            }
            if filters.trainerTypes.isEmpty == false {
                let trainerType = trimmedValue(card.trainerType)
                if trainerType.isEmpty || filters.trainerTypes.contains(trainerType) == false {
                    return false
                }
            }
            if filters.opCardTypes.isEmpty == false {
                let cardTypes = Set((card.category ?? "").split(separator: ",").map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                })
                if cardTypes.isDisjoint(with: filters.opCardTypes) {
                    return false
                }
            }
            if filters.opAttributes.isEmpty == false {
                let attrs = Set(card.opAttributes ?? [])
                if attrs.isDisjoint(with: filters.opAttributes) { return false }
            }
            if filters.opCosts.isEmpty == false {
                guard let cost = card.opCost, filters.opCosts.contains(cost) else { return false }
            }
            if filters.opCounters.isEmpty == false {
                guard let counter = card.opCounter, filters.opCounters.contains(counter) else { return false }
            }
            if filters.opLives.isEmpty == false {
                guard let life = card.opLife, filters.opLives.contains(life) else { return false }
            }
            if filters.opPowers.isEmpty == false {
                guard let power = card.opPower, filters.opPowers.contains(power) else { return false }
            }
            return true
        }
    }

    private func resolvedCardType(for card: BrowseFilterCard, brand: TCGBrand) -> BrowseCardTypeFilter {
        if brand == .onePiece {
            let category = card.category?.lowercased() ?? ""
            if category.contains("event") {
                return .trainer
            }
            return .pokemon
        }
        let category = card.category?.lowercased() ?? ""
        if category.contains("trainer") || card.trainerType != nil {
            return .trainer
        }
        if category.contains("energy") || card.energyType != nil {
            return .energy
        }
        return .pokemon
    }

    private func resolvedEnergyTypes(for card: BrowseFilterCard) -> [String] {
        var values = Set<String>()
        if let energyType = card.energyType {
            let trimmed = trimmedValue(energyType)
            if !trimmed.isEmpty {
                values.insert(trimmed)
            }
        }
        for type in card.elementTypes ?? [] {
            let trimmed = trimmedValue(type)
            if !trimmed.isEmpty {
                values.insert(trimmed)
            }
        }
        return Array(values)
    }

    private func resolvedEnergyTypes(for card: Card) -> [String] {
        var values = Set<String>()
        if let energyType = card.energyType {
            let trimmed = trimmedValue(energyType)
            if !trimmed.isEmpty {
                values.insert(trimmed)
            }
        }
        for type in card.elementTypes ?? [] {
            let trimmed = trimmedValue(type)
            if !trimmed.isEmpty {
                values.insert(trimmed)
            }
        }
        return Array(values)
    }

    private func isCommonOrUncommon(_ rarity: String?) -> Bool {
        let normalized = rarity?.lowercased() ?? ""
        return normalized.contains("common") || normalized.contains("uncommon")
    }

    private func trimmedValue(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func compareReleaseDateNewestFirst(lhsSetCode: String, rhsSetCode: String) -> Bool {
        let dates = firstValueMap(services.cardData.sets, key: \.setCode) { $0.releaseDate ?? "" }
        let lhs = dates[lhsSetCode] ?? ""
        let rhs = dates[rhsSetCode] ?? ""
        if lhs != rhs {
            return lhs > rhs
        }
        return lhsSetCode.localizedStandardCompare(rhsSetCode) == .orderedAscending
    }

    @MainActor
    private func syncFilterMenuState(usingCatalogFeed: Bool? = nil) {
        if isInlineDetailPresented {
            let inlineCount = filteredInlineDetailCards.count
            visibleBrowseResultCount = inlineCount
            filterResultCount = inlineCount
            filterEnergyOptions = cardEnergyOptions(inlineDetailCards)
            filterRarityOptions = cardRarityOptions(inlineDetailCards)
            filterTrainerTypeOptions = cardTrainerTypeOptions(inlineDetailCards)
            inlineDetailFilterResultCount = inlineCount
            inlineDetailFilterEnergyOptions = cardEnergyOptions(inlineDetailCards)
            inlineDetailFilterRarityOptions = cardRarityOptions(inlineDetailCards)
            inlineDetailFilterTrainerTypeOptions = cardTrainerTypeOptions(inlineDetailCards)
            return
        }
        let isUsingCatalogFeed = usingCatalogFeed ?? isUsingCatalogFeedSelection
        let hasCardFeedFilters = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || filters.hasActiveFieldFilters
            || filters.hasActiveSort
        let count: Int
        if selectedTab != .cards {
            count = 0
        } else if isUsingCatalogFeed {
            count = catalogOrderedRefs.count
        } else if hasCardFeedFilters == false, shuffledRefs.isEmpty == false {
            // No filters/search: show total available browse feed size, not just current page.
            count = shuffledRefs.count
        } else {
            count = browseFeedSnapshot.cards.count
        }
        visibleBrowseResultCount = count
        filterResultCount = count
        if allBrowseFilterCards.isEmpty {
            filterEnergyOptions = cardEnergyOptions(browseFeedSnapshot.cards)
            filterRarityOptions = cardRarityOptions(browseFeedSnapshot.cards)
            filterTrainerTypeOptions = []
        } else {
            filterEnergyOptions = browseFilterEnergyOptions(allBrowseFilterCards)
            filterRarityOptions = browseFilterRarityOptions(allBrowseFilterCards)
            filterTrainerTypeOptions = browseFilterTrainerTypeOptions(allBrowseFilterCards)
        }
    }

    private func tabSupportsInlineDetail(_ tab: BrowseHomeTab) -> Bool {
        switch tab {
        case .sets, .pokemon:
            return true
        case .cards, .sealed:
            return false
        }
    }

    @MainActor
    private func loadInlineDetailIfNeeded(route: BrowseInlineDetailRoute?) async {
        guard let route else {
            inlineDetailCards = []
            inlineDetailLoading = false
            syncFilterMenuState(usingCatalogFeed: false)
            return
        }

        inlineDetailLoading = true
        defer { inlineDetailLoading = false }

        switch route {
        case .set(let set):
            let loaded = await services.cardData.loadCards(forSetCode: set.setCode)
            inlineDetailCards = sortCardsByLocalIdHighestFirst(loaded)
        case .dex(let dexId, _):
            inlineDetailCards = await services.cardData.cards(matchingNationalDex: dexId)
        case .onePieceCharacter(let name):
            inlineDetailCards = await services.cardData.cards(matchingOnePieceCharacterName: name)
        case .onePieceSubtype(let name):
            inlineDetailCards = await services.cardData.cards(matchingOnePieceSubtype: name)
        }

        ImagePrefetcher.shared.prefetchCardWindow(inlineDetailCards, startingAt: 0, count: 24)
        syncFilterMenuState(usingCatalogFeed: false)
    }
}

private struct BrowseSetsTabContent: View {
    @Environment(AppServices.self) private var services

    let query: String
    let onSelectSet: (TCGSet) -> Void

    private var filteredSets: [TCGSet] {
        let sets = services.cardData.allSetsSortedByReleaseDateNewestFirst()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return sets }
        let lowered = trimmed.lowercased()
        return sets.filter { set in
            set.name.lowercased().contains(lowered)
                || set.setCode.lowercased().contains(lowered)
                || (set.seriesName?.lowercased().contains(lowered) == true)
        }
    }

    private var groupedSets: [(title: String, sets: [TCGSet])] {
        let grouped = Dictionary(grouping: filteredSets, by: browseSeriesTitle(for:))
        return grouped
            .map { (title: $0.key, sets: sortSetsNewestFirst($0.value)) }
            .sorted { lhs, rhs in
                let lhsNewest = lhs.sets.map(\.releaseDate).compactMap { $0 }.max() ?? ""
                let rhsNewest = rhs.sets.map(\.releaseDate).compactMap { $0 }.max() ?? ""
                if lhsNewest != rhsNewest { return lhsNewest > rhsNewest }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    var body: some View {
        if filteredSets.isEmpty {
            ContentUnavailableView(
                "No matching sets",
                systemImage: "magnifyingglass",
                description: Text("Try a different set name or code.")
            )
            .frame(maxWidth: .infinity, minHeight: 280)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        } else {
            LazyVStack(alignment: .leading, spacing: 20) {
                ForEach(groupedSets, id: \.title) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.title)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.primary)
                        Rectangle()
                            .fill(Color.primary.opacity(0.08))
                            .frame(height: 1)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                    LazyVStack(spacing: 0) {
                        ForEach(Array(group.sets.enumerated()), id: \.offset) { _, set in
                            Button {
                                onSelectSet(set)
                            } label: {
                                HStack(spacing: 14) {
                                    SetLogoAsyncImage(
                                        logoSrc: set.logoSrc,
                                        height: 44,
                                        brand: services.brandSettings.selectedCatalogBrand
                                    )
                                    .frame(width: 80)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(set.name)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.primary)
                                            .lineLimit(2)
                                        Text(set.setCode.uppercased())
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Divider()
                                .padding(.leading, 124)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.bottom, 16)
        }
    }

    private func browseSeriesTitle(for set: TCGSet) -> String {
        switch services.brandSettings.selectedCatalogBrand {
        case .pokemon:
            let title = set.seriesName?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (title?.isEmpty == false ? title! : "Other")
        case .onePiece:
            return normalizedOnePieceSeriesTitle(set.seriesName)
        }
    }

    private func sortSetsNewestFirst(_ sets: [TCGSet]) -> [TCGSet] {
        sets.sorted { lhs, rhs in
            let ld = lhs.releaseDate ?? ""
            let rd = rhs.releaseDate ?? ""
            if ld != rd { return ld > rd }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func normalizedOnePieceSeriesTitle(_ raw: String?) -> String {
        let title = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let lower = title.lowercased()
        if lower.contains("booster pack") { return "Booster Pack" }
        if lower.contains("extra booster") { return "Extra Boosters" }
        if lower.contains("starter") { return "Starter deck" }
        if lower.contains("premium booster") { return "Premium Booster" }
        if lower.contains("promo") { return "Promo" }
        return title.isEmpty ? "Other" : title
    }
}

private struct BrowsePokemonTabContent: View {
    @Environment(AppServices.self) private var services

    let query: String
    let onSelectRoute: (BrowseInlineDetailRoute) -> Void

    @State private var rows: [NationalDexPokemon] = []
    @State private var isLoading = true
    @State private var characterRows: [String] = []
    @State private var subtypeRows: [String] = []

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    private var filteredPokemonRows: [NationalDexPokemon] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return rows }
        let lowered = trimmed.lowercased()
        return rows.filter { item in
            item.name.lowercased().contains(lowered)
                || item.displayName.lowercased().contains(lowered)
                || String(item.nationalDexNumber).contains(lowered)
        }
    }

    private var filteredCharacterRows: [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return characterRows }
        let lowered = trimmed.lowercased()
        return characterRows.filter { $0.lowercased().contains(lowered) }
    }

    private var filteredSubtypeRows: [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return subtypeRows }
        let lowered = trimmed.lowercased()
        return subtypeRows.filter { $0.lowercased().contains(lowered) }
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView(activeTitle)
                    .frame(maxWidth: .infinity, minHeight: 280)
                    .padding(.horizontal, 16)
            } else if services.brandSettings.selectedCatalogBrand == .pokemon {
                pokemonBody
            } else {
                onePieceBody
            }
        }
        .onAppear {
            scheduleRowLoad(for: services.brandSettings.selectedCatalogBrand)
        }
        .onChange(of: services.brandSettings.selectedCatalogBrand) { _, newBrand in
            scheduleRowLoad(for: newBrand)
        }
    }

    @MainActor
    private func scheduleRowLoad(for _: TCGBrand) {
        Task { @MainActor in
            await loadRows()
        }
    }

    private var activeTitle: String {
        services.brandSettings.selectedCatalogBrand == .pokemon ? "Loading Pokémon…" : "Loading characters…"
    }

    @ViewBuilder
    private var pokemonBody: some View {
        if rows.isEmpty {
            ContentUnavailableView(
                "No Pokédex list",
                systemImage: "hare",
                description: Text("Add pokemon.json next to sets.json on your CDN.")
            )
            .frame(maxWidth: .infinity, minHeight: 280)
            .padding(.horizontal, 16)
        } else if filteredPokemonRows.isEmpty {
            ContentUnavailableView(
                "No matching Pokémon",
                systemImage: "magnifyingglass",
                description: Text("Try a different name or National Dex number.")
            )
            .frame(maxWidth: .infinity, minHeight: 280)
            .padding(.horizontal, 16)
        } else {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(filteredPokemonRows) { item in
                    Button {
                        onSelectRoute(.dex(dexId: item.nationalDexNumber, displayName: item.displayName))
                    } label: {
                        VStack(spacing: 6) {
                            CachedAsyncImage(
                                url: AppConfiguration.pokemonArtURL(imageFileName: item.imageUrl)
                            ) { img in
                                img.resizable().scaledToFit()
                            } placeholder: {
                                Color.gray.opacity(0.12)
                            }
                            .frame(height: 140)

                            Text(item.displayName)
                                .font(.caption2)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)

                            Text("#\(item.nationalDexNumber)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    @ViewBuilder
    private var onePieceBody: some View {
        if characterRows.isEmpty && subtypeRows.isEmpty {
            ContentUnavailableView(
                "No browse lists",
                systemImage: "list.bullet",
                description: Text("Character names and subtypes will appear here after the ONE PIECE catalog sync completes.")
            )
            .frame(maxWidth: .infinity, minHeight: 280)
            .padding(.horizontal, 16)
        } else if filteredCharacterRows.isEmpty && filteredSubtypeRows.isEmpty {
            ContentUnavailableView(
                "No matches",
                systemImage: "magnifyingglass",
                description: Text("Try a different search term.")
            )
            .frame(maxWidth: .infinity, minHeight: 280)
            .padding(.horizontal, 16)
        } else {
            LazyVStack(alignment: .leading, spacing: 20) {
                if !filteredCharacterRows.isEmpty {
                        listSection(title: "Characters", rows: filteredCharacterRows) { row in
                        Button {
                            onSelectRoute(.onePieceCharacter(row))
                        } label: {
                            browseListRow(title: row)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !filteredSubtypeRows.isEmpty {
                    listSection(title: "Subtypes", rows: filteredSubtypeRows) { row in
                        Button {
                            onSelectRoute(.onePieceSubtype(row))
                        } label: {
                            browseListRow(title: row)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.bottom, 16)
        }
    }

    private func loadRows() async {
        isLoading = true
        defer { isLoading = false }

        if services.brandSettings.selectedCatalogBrand == .pokemon {
            characterRows = []
            subtypeRows = []
            if services.cardData.nationalDexPokemon.isEmpty {
                await services.cardData.loadNationalDexPokemon()
            }
            rows = services.cardData.nationalDexPokemonSorted()
        } else {
            rows = []
            if services.cardData.onePieceCharacterNames.isEmpty || services.cardData.onePieceCharacterSubtypes.isEmpty {
                await services.cardData.loadOnePieceBrowseMetadata()
            }
            characterRows = services.cardData.onePieceCharacterNames
            subtypeRows = services.cardData.onePieceCharacterSubtypes
        }
    }

    private func listSection<RowContent: View>(
        title: String,
        rows: [String],
        @ViewBuilder rowBuilder: @escaping (String) -> RowContent
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)

            LazyVStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    rowBuilder(row)
                    Divider()
                        .padding(.leading, 32)
                }
            }
        }
    }

    private func browseListRow(title: String) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

private struct BrowseGridCardCell: View {
    /// Grid display size (~2× retina); Pokémon catalog images are usually lighter than ONE PIECE full-art PNGs on R2.
    private static let thumbnailSize = CGSize(width: 220, height: 308)
    /// Slightly smaller decode for ONE PIECE (`priceKey` cards) to shorten download+decode time while staying sharp on screen.
    private static let onePieceThumbnailDecodeSize = CGSize(width: 200, height: 280)

    let card: Card
    let gridOptions: BrowseGridOptions
    let setName: String?

    private var imageDecodeSize: CGSize {
        if card.masterCardId.contains("::") {
            return Self.onePieceThumbnailDecodeSize
        }
        return Self.thumbnailSize
    }

    var body: some View {
        VStack(spacing: 4) {
            CachedAsyncImage(
                url: AppConfiguration.imageURL(relativePath: card.imageLowSrc),
                targetSize: imageDecodeSize
            ) { img in
                img.resizable().scaledToFit()
            } placeholder: {
                Color.gray.opacity(0.12)
                    .aspectRatio(5/7, contentMode: .fit)
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(5/7, contentMode: .fit)

            if gridOptions.showCardName {
                Text(card.cardName)
                    .font(.caption2)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
            }

            if gridOptions.showSetName, let setName, !setName.isEmpty {
                Text(setName)
                    .font(.caption2)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            if gridOptions.showSetID {
                Text(card.setCode)
                    .font(.caption2)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            if gridOptions.showPricing {
                BrowseGridPriceText(card: card)
            }
        }
    }
}

private struct BrowseGridPriceText: View {
    @Environment(AppServices.self) private var services

    let card: Card

    /// `nil` until the pricing task finishes; then a single price, a `low - high` range, or an em dash when unknown.
    @State private var priceLine: String?

    var body: some View {
        Group {
            if let priceLine {
                Text(priceLine)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            } else {
                Text(" ")
                    .font(.caption2.weight(.semibold))
                    .redacted(reason: .placeholder)
            }
        }
        .task(id: taskID) {
            priceLine = nil
            guard let entry = await services.pricing.pricing(for: card),
                  let range = resolvedMarketPriceRange(entry) else {
                priceLine = "—"
                return
            }
            let currency = services.priceDisplay.currency
            let fx = services.pricing.usdToGbp
            if abs(range.max - range.min) < 0.005 {
                priceLine = currency.format(amountUSD: range.min, usdToGbp: fx)
            } else {
                let low = currency.format(amountUSD: range.min, usdToGbp: fx)
                let high = currency.format(amountUSD: range.max, usdToGbp: fx)
                priceLine = "\(low) - \(high)"
            }
        }
    }

    private var taskID: String {
        "\(card.id)|\(services.priceDisplay.currency.rawValue)|\(services.pricing.usdToGbp)"
    }

    /// Min/max market USD across **all** Scrydex variants on the card (grid headline when multiple printings exist).
    private func resolvedMarketPriceRange(_ entry: CardPricingEntry) -> (min: Double, max: Double)? {
        if let scrydex = entry.scrydex, !scrydex.isEmpty {
            let values = scrydex.values.compactMap { $0.marketEstimateUSD() }
            guard let minV = values.min(), let maxV = values.max() else { return nil }
            return (minV, maxV)
        }
        if let u = entry.tcgplayerMarketEstimateUSD() {
            return (u, u)
        }
        return nil
    }
}

private func sortCardsByReleaseDateNewestFirst(_ cards: [Card], sets: [TCGSet]) -> [Card] {
    guard !cards.isEmpty else { return cards }
    let dates = firstValueMap(sets, key: \.setCode) { $0.releaseDate ?? "" }
    return cards.sorted { a, b in
        let da = dates[a.setCode] ?? ""
        let db = dates[b.setCode] ?? ""
        if da != db {
            return da > db
        }
        if a.setCode != b.setCode {
            return a.setCode.localizedStandardCompare(b.setCode) == .orderedAscending
        }
        return a.cardNumber.localizedStandardCompare(b.cardNumber) == .orderedAscending
    }
}

private func sortBrowseFilterCardsByReleaseDateNewestFirst(_ cards: [BrowseFilterCard], sets: [TCGSet]) -> [BrowseFilterCard] {
    guard !cards.isEmpty else { return cards }
    let dates = firstValueMap(sets, key: \.setCode) { $0.releaseDate ?? "" }
    return cards.sorted { a, b in
        let da = dates[a.setCode] ?? ""
        let db = dates[b.setCode] ?? ""
        if da != db {
            return da > db
        }
        if a.setCode != b.setCode {
            return a.setCode.localizedStandardCompare(b.setCode) == .orderedAscending
        }
        return a.cardNumber.localizedStandardCompare(b.cardNumber) == .orderedAscending
    }
}

private func firstValueMap<Input, Key: Hashable, Value>(
    _ values: [Input],
    key: KeyPath<Input, Key>,
    value: (Input) -> Value
) -> [Key: Value] {
    var out: [Key: Value] = [:]
    out.reserveCapacity(values.count)
    for item in values where out[item[keyPath: key]] == nil {
        out[item[keyPath: key]] = value(item)
    }
    return out
}

private func chunkedBrowseCards(_ cards: [Card], columnCount: Int) -> [[Card]] {
    guard columnCount > 0, cards.isEmpty == false else { return [] }
    var rows: [[Card]] = []
    rows.reserveCapacity((cards.count + columnCount - 1) / columnCount)
    var index = 0
    while index < cards.count {
        let end = min(index + columnCount, cards.count)
        rows.append(Array(cards[index..<end]))
        index = end
    }
    return rows
}

private func safeBrowseGridColumnCount(_ count: Int) -> Int {
    min(max(count, 1), 4)
}

// MARK: - Set cards

struct SetCardsView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.presentCard) private var presentCard
    @Query private var collectionItems: [CollectionItem]
    let set: TCGSet

    @State private var cards: [Card] = []
    @State private var isLoading = true
    @State private var query = ""
    @State private var filters = BrowseCardGridFilters()
    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: 12),
            count: safeBrowseGridColumnCount(services.browseGridOptions.options.columnCount)
        )
    }

    private var ownedCardIDs: Set<String> {
        return Set(collectionItems.compactMap { item in
            let brand = TCGBrand.inferredFromMasterCardId(item.cardID)
            return brand == services.brandSettings.selectedCatalogBrand ? item.cardID : nil
        })
    }

    private var filteredCards: [Card] {
        filterBrowseCards(
            cards,
            query: query,
            filters: filters,
            ownedCardIDs: ownedCardIDs,
            brand: services.brandSettings.selectedCatalogBrand,
            sets: services.cardData.sets
        )
    }

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView().padding()
            } else {
                VStack(spacing: 12) {
                    BrowseInlineSearchField(title: "Search cards in set", text: $query)
                        .padding(.horizontal)
                        .padding(.top, 2)
                    if filteredCards.isEmpty {
                        ContentUnavailableView(
                            "No matching cards",
                            systemImage: "magnifyingglass",
                            description: Text("Try a different card name or number.")
                        )
                        .padding(.horizontal)
                        .padding(.bottom)
                    } else {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(Array(filteredCards.enumerated()), id: \.element.id) { index, card in
                                Button {
                                    presentCard(card, filteredCards)
                                } label: {
                                    CardGridCell(
                                        card: card,
                                        gridOptions: services.browseGridOptions.options,
                                        setName: set.name
                                    )
                                }
                                    .buttonStyle(CardCellButtonStyle())
                                    .onAppear {
                                        ImagePrefetcher.shared.prefetchCardWindow(filteredCards, startingAt: index + 1)
                                    }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom)
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top) {
            BrowseDetailNavBar(
                title: set.name,
                isFilterActive: filters.isVisiblyCustomized,
                isGridOptionsActive: !services.browseGridOptions.options.isDefault
            ) {
                BrowseGridFiltersMenuContent(
                    brand: services.brandSettings.selectedCatalogBrand,
                    filters: $filters,
                    energyOptions: cardEnergyOptions(cards),
                    rarityOptions: cardRarityOptions(cards),
                    trainerTypeOptions: cardTrainerTypeOptions(cards),
                    config: FilterMenuConfig(showGridOptions: false)
                )
            } gridMenuContent: {
                BrowseGridOptionsMenuContent()
            }
        }
        .task {
            isLoading = true
            let loaded = await services.cardData.loadCards(forSetCode: set.setCode)
            cards = sortCardsByLocalIdHighestFirst(loaded)
            ImagePrefetcher.shared.prefetchCardWindow(cards, startingAt: 0, count: 24)
            isLoading = false
        }
    }
}

/// Browse-by-set grid: highest catalog `localId` first (numeric when possible); ties and missing `localId` use `masterCardId`.
private func sortCardsByLocalIdHighestFirst(_ cards: [Card]) -> [Card] {
    cards.sorted { a, b in
        let va = localIdNumericSortValue(a.localId)
        let vb = localIdNumericSortValue(b.localId)
        if va != vb { return va > vb }
        return a.masterCardId > b.masterCardId
    }
}

/// Parses `localId` like `"102"` for ordering; missing or non-numeric sorts last (same as `Int.min`).
private func localIdNumericSortValue(_ raw: String?) -> Int {
    guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
        return Int.min
    }
    if let v = Int(raw) { return v }
    let digits = raw.prefix { $0.isNumber }
    if let v = Int(String(digits)), !digits.isEmpty { return v }
    return Int.min
}

// MARK: - Dex cards

struct DexCardsView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.presentCard) private var presentCard
    @Query private var collectionItems: [CollectionItem]
    let dexId: Int
    let displayName: String

    @State private var cards: [Card] = []
    @State private var isLoading = true
    @State private var query = ""
    @State private var filters = BrowseCardGridFilters()
    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: 12),
            count: safeBrowseGridColumnCount(services.browseGridOptions.options.columnCount)
        )
    }

    private var setNameByCode: [String: String] {
        firstValueMap(services.cardData.sets, key: \.setCode, value: \.name)
    }

    private var ownedCardIDs: Set<String> {
        return Set(collectionItems.compactMap { item in
            let brand = TCGBrand.inferredFromMasterCardId(item.cardID)
            return brand == services.brandSettings.selectedCatalogBrand ? item.cardID : nil
        })
    }

    private var filteredCards: [Card] {
        filterBrowseCards(
            cards,
            query: query,
            filters: filters,
            ownedCardIDs: ownedCardIDs,
            brand: services.brandSettings.selectedCatalogBrand,
            sets: services.cardData.sets
        )
    }

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView().padding()
            } else {
                VStack(spacing: 12) {
                    BrowseInlineSearchField(title: "Search cards for Pokémon", text: $query)
                        .padding(.horizontal)
                        .padding(.top, 2)
                    if filteredCards.isEmpty {
                        ContentUnavailableView(
                            "No matching cards",
                            systemImage: "magnifyingglass",
                            description: Text("Try a different card name or number.")
                        )
                        .padding(.horizontal)
                        .padding(.bottom)
                    } else {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(Array(filteredCards.enumerated()), id: \.element.id) { index, card in
                                Button {
                                    presentCard(card, filteredCards)
                                } label: {
                                    CardGridCell(
                                        card: card,
                                        gridOptions: services.browseGridOptions.options,
                                        setName: setNameByCode[card.setCode]
                                    )
                                }
                                    .buttonStyle(CardCellButtonStyle())
                                    .onAppear {
                                        ImagePrefetcher.shared.prefetchCardWindow(filteredCards, startingAt: index + 1)
                                    }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom)
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top) {
            BrowseDetailNavBar(
                title: displayName,
                isFilterActive: filters.isVisiblyCustomized,
                isGridOptionsActive: !services.browseGridOptions.options.isDefault
            ) {
                BrowseGridFiltersMenuContent(
                    brand: services.brandSettings.selectedCatalogBrand,
                    filters: $filters,
                    energyOptions: cardEnergyOptions(cards),
                    rarityOptions: cardRarityOptions(cards),
                    trainerTypeOptions: cardTrainerTypeOptions(cards),
                    config: FilterMenuConfig(showGridOptions: false)
                )
            } gridMenuContent: {
                BrowseGridOptionsMenuContent()
            }
        }
        .task {
            isLoading = true
            cards = await services.cardData.cards(matchingNationalDex: dexId)
            ImagePrefetcher.shared.prefetchCardWindow(cards, startingAt: 0, count: 24)
            isLoading = false
        }
    }
}

// MARK: - ONE PIECE browse detail

struct OnePieceCharacterCardsView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.presentCard) private var presentCard
    @Query private var collectionItems: [CollectionItem]

    let characterName: String

    @State private var cards: [Card] = []
    @State private var isLoading = true
    @State private var query = ""
    @State private var filters = BrowseCardGridFilters()
    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: 12),
            count: safeBrowseGridColumnCount(services.browseGridOptions.options.columnCount)
        )
    }

    private var setNameByCode: [String: String] {
        firstValueMap(services.cardData.sets, key: \.setCode, value: \.name)
    }

    private var ownedCardIDs: Set<String> {
        return Set(collectionItems.compactMap { item in
            let brand = TCGBrand.inferredFromMasterCardId(item.cardID)
            return brand == services.brandSettings.selectedCatalogBrand ? item.cardID : nil
        })
    }

    private var filteredCards: [Card] {
        filterBrowseCards(
            cards,
            query: query,
            filters: filters,
            ownedCardIDs: ownedCardIDs,
            brand: services.brandSettings.selectedCatalogBrand,
            sets: services.cardData.sets
        )
    }

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView().padding()
            } else {
                VStack(spacing: 12) {
                    BrowseInlineSearchField(title: "Search cards for character", text: $query)
                        .padding(.horizontal)
                        .padding(.top, 2)
                    if filteredCards.isEmpty {
                        ContentUnavailableView(
                            "No matching cards",
                            systemImage: "person.text.rectangle",
                            description: Text(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No ONE PIECE cards matched \(characterName)." : "Try a different card name or number.")
                        )
                        .padding(.horizontal)
                        .padding(.bottom)
                    } else {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(Array(filteredCards.enumerated()), id: \.element.id) { index, card in
                                Button {
                                    presentCard(card, filteredCards)
                                } label: {
                                    CardGridCell(
                                        card: card,
                                        gridOptions: services.browseGridOptions.options,
                                        setName: setNameByCode[card.setCode]
                                    )
                                }
                                    .buttonStyle(CardCellButtonStyle())
                                    .onAppear {
                                        ImagePrefetcher.shared.prefetchCardWindow(filteredCards, startingAt: index + 1)
                                    }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom)
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top) {
            BrowseDetailNavBar(
                title: characterName,
                isFilterActive: filters.isVisiblyCustomized,
                isGridOptionsActive: !services.browseGridOptions.options.isDefault
            ) {
                BrowseGridFiltersMenuContent(
                    brand: services.brandSettings.selectedCatalogBrand,
                    filters: $filters,
                    energyOptions: cardEnergyOptions(cards),
                    rarityOptions: cardRarityOptions(cards),
                    trainerTypeOptions: cardTrainerTypeOptions(cards),
                    config: FilterMenuConfig(showGridOptions: false)
                )
            } gridMenuContent: {
                BrowseGridOptionsMenuContent()
            }
        }
        .task(id: characterName) {
            isLoading = true
            cards = await services.cardData.cards(matchingOnePieceCharacterName: characterName)
            ImagePrefetcher.shared.prefetchCardWindow(cards, startingAt: 0, count: 24)
            isLoading = false
        }
    }
}

struct OnePieceSubtypeCardsView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.presentCard) private var presentCard
    @Query private var collectionItems: [CollectionItem]

    let subtypeName: String

    @State private var cards: [Card] = []
    @State private var isLoading = true
    @State private var query = ""
    @State private var filters = BrowseCardGridFilters()
    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: 12),
            count: safeBrowseGridColumnCount(services.browseGridOptions.options.columnCount)
        )
    }

    private var setNameByCode: [String: String] {
        firstValueMap(services.cardData.sets, key: \.setCode, value: \.name)
    }

    private var ownedCardIDs: Set<String> {
        return Set(collectionItems.compactMap { item in
            let brand = TCGBrand.inferredFromMasterCardId(item.cardID)
            return brand == services.brandSettings.selectedCatalogBrand ? item.cardID : nil
        })
    }

    private var filteredCards: [Card] {
        filterBrowseCards(
            cards,
            query: query,
            filters: filters,
            ownedCardIDs: ownedCardIDs,
            brand: services.brandSettings.selectedCatalogBrand,
            sets: services.cardData.sets
        )
    }

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView().padding()
            } else {
                VStack(spacing: 12) {
                    BrowseInlineSearchField(title: "Search cards for subtype", text: $query)
                        .padding(.horizontal)
                        .padding(.top, 2)
                    if filteredCards.isEmpty {
                        ContentUnavailableView(
                            "No matching cards",
                            systemImage: "line.3.horizontal.decrease.circle",
                            description: Text(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No ONE PIECE cards matched \(subtypeName)." : "Try a different card name or number.")
                        )
                        .padding(.horizontal)
                        .padding(.bottom)
                    } else {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(Array(filteredCards.enumerated()), id: \.element.id) { index, card in
                                Button {
                                    presentCard(card, filteredCards)
                                } label: {
                                    CardGridCell(
                                        card: card,
                                        gridOptions: services.browseGridOptions.options,
                                        setName: setNameByCode[card.setCode]
                                    )
                                }
                                    .buttonStyle(CardCellButtonStyle())
                                    .onAppear {
                                        ImagePrefetcher.shared.prefetchCardWindow(filteredCards, startingAt: index + 1)
                                    }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom)
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top) {
            BrowseDetailNavBar(
                title: subtypeName,
                isFilterActive: filters.isVisiblyCustomized,
                isGridOptionsActive: !services.browseGridOptions.options.isDefault
            ) {
                BrowseGridFiltersMenuContent(
                    brand: services.brandSettings.selectedCatalogBrand,
                    filters: $filters,
                    energyOptions: cardEnergyOptions(cards),
                    rarityOptions: cardRarityOptions(cards),
                    trainerTypeOptions: cardTrainerTypeOptions(cards),
                    config: FilterMenuConfig(showGridOptions: false)
                )
            } gridMenuContent: {
                BrowseGridOptionsMenuContent()
            }
        }
        .task(id: subtypeName) {
            isLoading = true
            cards = await services.cardData.cards(matchingOnePieceSubtype: subtypeName)
            ImagePrefetcher.shared.prefetchCardWindow(cards, startingAt: 0, count: 24)
            isLoading = false
        }
    }
}

private struct BrowseDetailNavBar<FilterMenuContent: View, GridMenuContent: View>: View {
    let title: String
    let isFilterActive: Bool
    let isGridOptionsActive: Bool
    @ViewBuilder let filterMenuContent: () -> FilterMenuContent
    @ViewBuilder let gridMenuContent: () -> GridMenuContent
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Text(title)
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 64)

            HStack {
                ChromeGlassCircleButton(accessibilityLabel: "Back") { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.primary)
                }

                Spacer(minLength: 0)

                HStack(spacing: 10) {
                    Menu {
                        gridMenuContent()
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.primary)
                            .modifier(ChromeGlassCircleGlyphModifier())
                    }
                    .buttonStyle(.plain)
                    .menuActionDismissBehavior(.disabled)
                    .menuOrder(.fixed)
                    .menuIndicator(.hidden)
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Grid options")

                    Menu {
                        filterMenuContent()
                    } label: {
                        Image(systemName: isFilterActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.primary)
                            .modifier(ChromeGlassCircleGlyphModifier())
                    }
                    .buttonStyle(.plain)
                    .menuActionDismissBehavior(.disabled)
                    .menuOrder(.fixed)
                    .menuIndicator(.hidden)
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Filters")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

struct BrowseFilterToolbarButton: View {
    let isActive: Bool

    var body: some View {
        Image(systemName: isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(isActive ? Color.blue : Color.primary)
            .modifier(ChromeGlassCircleGlyphModifier())
            .frame(width: 48, height: 48)
            .contentShape(Rectangle())
    }
}

struct FilterMenuConfig {
    var showSortBy: Bool = true
    var showAcquiredDateSort: Bool = false
    var showBrandFilters: Bool = true
    var showRarity: Bool = true
    var showRarePlusOnly: Bool = true
    var showHideOwned: Bool = true
    var showShowDuplicates: Bool = false
    var showGridOptions: Bool = true
    var defaultSortBy: BrowseCardGridSortOption = .random

    static let browse = FilterMenuConfig()
    static let collect = FilterMenuConfig(showAcquiredDateSort: true, showHideOwned: false, showShowDuplicates: true, defaultSortBy: .price)
}

struct BrowseGridFiltersMenuContent: View {
    @Environment(AppServices.self) private var services

    let brand: TCGBrand
    @Binding var filters: BrowseCardGridFilters
    let energyOptions: [String]
    let rarityOptions: [String]
    let trainerTypeOptions: [String]
    var isAllBrands: Bool = false
    /// When nil, falls back to `services.browseGridOptions` (browse behaviour). Pass a binding to use separate grid options.
    var gridOptions: Binding<BrowseGridOptions>? = nil
    var config: FilterMenuConfig = .browse

    var body: some View {
        if filters.isVisiblyCustomized || filters.sortBy != config.defaultSortBy {
            Section {
                Button("Reset filters", role: .destructive) {
                    filters = BrowseCardGridFilters()
                    filters.sortBy = config.defaultSortBy
                }
            }
        }

        Section("Sort by") {
            Menu(menuTitle("Sort by", summary: filters.sortBy.title)) {
                Picker("Sort by", selection: $filters.sortBy) {
                    ForEach(BrowseCardGridSortOption.allCases.filter {
                        $0 != .acquiredDateNewest || config.showAcquiredDateSort
                    }) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            .menuActionDismissBehavior(.disabled)
            .menuOrder(.fixed)
        }

        if !isAllBrands {
        Section("Filters") {
            if brand == .onePiece {
                filterMenu(title: "Card type", summary: selectionSummary(for: filters.opCardTypes)) {
                    ForEach(opCardTypeAllOptions, id: \.self) { cardType in
                        Toggle(cardType, isOn: stringBinding(for: cardType, keyPath: \.opCardTypes))
                    }
                }

                filterMenu(title: "Attribute", summary: selectionSummary(for: filters.opAttributes)) {
                    ForEach(opAttributeAllOptions, id: \.self) { attr in
                        Toggle(attr, isOn: stringBinding(for: attr, keyPath: \.opAttributes))
                    }
                }

                filterMenu(
                    title: "Stats",
                    summary: combinedSelectionSummary(
                        ("Cost", filters.opCosts.count),
                        ("Counter", filters.opCounters.count),
                        ("Life", filters.opLives.count),
                        ("Power", filters.opPowers.count)
                    )
                ) {
                    filterMenu(title: "Cost", summary: selectionSummary(for: filters.opCosts)) {
                        ForEach(opCostAllOptions, id: \.self) { cost in
                            Toggle("\(cost)", isOn: intBinding(for: cost, keyPath: \.opCosts))
                        }
                    }
                    filterMenu(title: "Counter", summary: selectionSummary(for: filters.opCounters)) {
                        ForEach(opCounterAllOptions, id: \.self) { counter in
                            Toggle("\(counter)", isOn: intBinding(for: counter, keyPath: \.opCounters))
                        }
                    }
                    filterMenu(title: "Life", summary: selectionSummary(for: filters.opLives)) {
                        ForEach(opLifeAllOptions, id: \.self) { life in
                            Toggle("\(life)", isOn: intBinding(for: life, keyPath: \.opLives))
                        }
                    }
                    filterMenu(title: "Power", summary: selectionSummary(for: filters.opPowers)) {
                        ForEach(opPowerAllOptions, id: \.self) { power in
                            Toggle("\(power)", isOn: intBinding(for: power, keyPath: \.opPowers))
                        }
                    }
                }
            } else {
                filterMenu(title: "Card type", summary: selectionSummary(for: filters.cardTypes)) {
                    ForEach(BrowseCardTypeFilter.pokemonOptions) { type in
                        Toggle(type.title, isOn: cardTypeBinding(for: type))
                    }
                }
                filterMenu(title: "Legal", summary: selectionSummary(for: filters.legalities)) {
                    ForEach(BrowseCardLegalityFilter.allCases) { legality in
                        Toggle(legality.title, isOn: legalityBinding(for: legality))
                    }
                }
            }

            filterMenu(title: brand.energyFilterMenuTitle, summary: selectionSummary(for: filters.energyTypes)) {
                if energyOptions.isEmpty {
                    Text("No options available")
                } else {
                    ForEach(energyOptions, id: \.self) { energy in
                        Toggle(energy, isOn: stringBinding(for: energy, keyPath: \.energyTypes))
                    }
                }
            }

            if brand == .pokemon {
                filterMenu(title: "Trainer type", summary: selectionSummary(for: filters.trainerTypes)) {
                    if trainerTypeOptions.isEmpty {
                        Text("No trainer types available")
                    } else {
                        ForEach(trainerTypeOptions, id: \.self) { trainerType in
                            Toggle(trainerType, isOn: stringBinding(for: trainerType, keyPath: \.trainerTypes))
                        }
                    }
                }
            }
        }

        if config.showRarity || config.showRarePlusOnly || config.showHideOwned || config.showShowDuplicates {
            Section("Collection") {
                if config.showRarity {
                    filterMenu(title: "Rarity", summary: selectionSummary(for: filters.rarities)) {
                        if rarityOptions.isEmpty {
                            Text("No rarities available")
                        } else {
                            ForEach(rarityOptions, id: \.self) { rarity in
                                Toggle(rarity, isOn: stringBinding(for: rarity, keyPath: \.rarities))
                            }
                        }
                    }
                }
                if config.showRarePlusOnly {
                    Toggle("Rare + only", isOn: $filters.rarePlusOnly)
                }
                if config.showHideOwned {
                    Toggle("Hide owned", isOn: $filters.hideOwned)
                }
                if config.showShowDuplicates {
                    Toggle("Show duplicates", isOn: $filters.showDuplicates)
                }
            }
        }
        } // end if !isAllBrands

        if config.showGridOptions {
            Section("Grid options") {
                BrowseGridOptionsMenuContent(gridOptions: gridOptions)
            }
        }
    }

    @ViewBuilder
    private func filterMenu<Content: View>(title: String, summary: String?, @ViewBuilder content: () -> Content) -> some View {
        Menu(menuTitle(title, summary: summary)) {
            content()
        }
        .menuActionDismissBehavior(.disabled)
        .menuOrder(.fixed)
    }

    private func cardTypeBinding(for type: BrowseCardTypeFilter) -> Binding<Bool> {
        Binding(
            get: { filters.cardTypes.contains(type) },
            set: { isOn in
                if isOn { filters.cardTypes.insert(type) }
                else { filters.cardTypes.remove(type) }
            }
        )
    }

    private func legalityBinding(for legality: BrowseCardLegalityFilter) -> Binding<Bool> {
        Binding(
            get: { filters.legalities.contains(legality) },
            set: { isOn in
                if isOn { filters.legalities.insert(legality) }
                else { filters.legalities.remove(legality) }
            }
        )
    }

    private func stringBinding(for value: String, keyPath: WritableKeyPath<BrowseCardGridFilters, Set<String>>) -> Binding<Bool> {
        Binding(
            get: { filters[keyPath: keyPath].contains(value) },
            set: { isOn in
                if isOn { filters[keyPath: keyPath].insert(value) }
                else { filters[keyPath: keyPath].remove(value) }
            }
        )
    }

    private func intBinding(for value: Int, keyPath: WritableKeyPath<BrowseCardGridFilters, Set<Int>>) -> Binding<Bool> {
        Binding(
            get: { filters[keyPath: keyPath].contains(value) },
            set: { isOn in
                if isOn { filters[keyPath: keyPath].insert(value) }
                else { filters[keyPath: keyPath].remove(value) }
            }
        )
    }

    private func gridOptionBinding<T>(_ keyPath: WritableKeyPath<BrowseGridOptions, T>) -> Binding<T> {
        if let gridOptions {
            return Binding(
                get: { gridOptions.wrappedValue[keyPath: keyPath] },
                set: { newValue in
                    var updated = gridOptions.wrappedValue
                    updated[keyPath: keyPath] = newValue
                    gridOptions.wrappedValue = updated
                }
            )
        }
        return Binding(
            get: { services.browseGridOptions.options[keyPath: keyPath] },
            set: { newValue in
                var updated = services.browseGridOptions.options
                updated[keyPath: keyPath] = newValue
                services.browseGridOptions.options = updated
            }
        )
    }

    private func menuTitle(_ title: String, summary: String?) -> String {
        guard let summary, !summary.isEmpty else { return title }
        return "\(title) (\(summary))"
    }

    private func selectionSummary<T>(for values: Set<T>) -> String? {
        guard !values.isEmpty else { return nil }
        return values.count == 1 ? "1 selected" : "\(values.count) selected"
    }

    private func combinedSelectionSummary(_ groups: (String, Int)...) -> String? {
        let active = groups.filter { $0.1 > 0 }
        guard !active.isEmpty else { return nil }
        return active.map { "\($0.0) \($0.1)" }.joined(separator: ", ")
    }
}

struct BrowseGridOptionsMenuContent: View {
    @Environment(AppServices.self) private var services

    /// When nil, falls back to `services.browseGridOptions` (browse behaviour). Pass a binding to use separate grid options.
    var gridOptions: Binding<BrowseGridOptions>? = nil

    var body: some View {
        Toggle("Show card name", isOn: gridOptionBinding(\.showCardName))
        Toggle("Show set name", isOn: gridOptionBinding(\.showSetName))
        Toggle("Show set ID", isOn: gridOptionBinding(\.showSetID))
        if gridOptions != nil {
            Toggle("Owned", isOn: gridOptionBinding(\.showOwned))
        }
        Toggle("Show pricing", isOn: gridOptionBinding(\.showPricing))
        Stepper(value: gridOptionBinding(\.columnCount), in: 1...4) {
            let count = gridOptions?.wrappedValue.columnCount ?? services.browseGridOptions.options.columnCount
            Text("Columns: \(count)")
        }
    }

    private func gridOptionBinding<T>(_ keyPath: WritableKeyPath<BrowseGridOptions, T>) -> Binding<T> {
        if let gridOptions {
            return Binding(
                get: { gridOptions.wrappedValue[keyPath: keyPath] },
                set: { newValue in
                    var updated = gridOptions.wrappedValue
                    updated[keyPath: keyPath] = newValue
                    gridOptions.wrappedValue = updated
                }
            )
        }
        return Binding(
            get: { services.browseGridOptions.options[keyPath: keyPath] },
            set: { newValue in
                var updated = services.browseGridOptions.options
                updated[keyPath: keyPath] = newValue
                services.browseGridOptions.options = updated
            }
        )
    }
}

func cardEnergyOptions(_ cards: [Card]) -> [String] {
    var values = Set<String>()
    for card in cards {
        if let energyType = card.energyType?.trimmingCharacters(in: .whitespacesAndNewlines), !energyType.isEmpty {
            values.insert(energyType)
        }
        for type in card.elementTypes ?? [] {
            let trimmed = type.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                values.insert(trimmed)
            }
        }
    }
    return values.sorted()
}

func cardRarityOptions(_ cards: [Card]) -> [String] {
    Set(cards.compactMap { $0.rarity?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }).sorted()
}

func cardTrainerTypeOptions(_ cards: [Card]) -> [String] {
    Set(cards.compactMap { $0.trainerType?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }).sorted()
}

func browseFilterEnergyOptions(_ cards: [BrowseFilterCard]) -> [String] {
    var values = Set<String>()
    for card in cards {
        if let energyType = card.energyType?.trimmingCharacters(in: .whitespacesAndNewlines), !energyType.isEmpty {
            values.insert(energyType)
        }
        for type in card.elementTypes ?? [] {
            let trimmed = type.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                values.insert(trimmed)
            }
        }
    }
    return values.sorted()
}

func browseFilterRarityOptions(_ cards: [BrowseFilterCard]) -> [String] {
    Set(cards.compactMap { $0.rarity?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }).sorted()
}

func browseFilterTrainerTypeOptions(_ cards: [BrowseFilterCard]) -> [String] {
    Set(cards.compactMap { $0.trainerType?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }).sorted()
}

private func browseMarketPriceUSD(for entry: CardPricingEntry?) -> Double? {
    guard let entry else { return nil }
    if let scrydex = entry.scrydex, !scrydex.isEmpty {
        return scrydex.values.compactMap { $0.marketEstimateUSD() }.max()
    }
    return entry.tcgplayerMarketEstimateUSD()
}

private func isCommonOrUncommon(_ rarity: String?) -> Bool {
    let normalized = rarity?.lowercased() ?? ""
    return normalized.contains("common") || normalized.contains("uncommon")
}

func filterBrowseCards(
    _ cards: [Card],
    query: String,
    filters: BrowseCardGridFilters,
    ownedCardIDs: Set<String>,
    brand: TCGBrand,
    sets: [TCGSet] = []
) -> [Card] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let q = trimmed.lowercased()
    let setReleaseDateByCode = firstValueMap(sets, key: \.setCode) { $0.releaseDate ?? "" }
    let filtered = cards.filter { card in
        let matchesQuery = trimmed.isEmpty || card.cardName.lowercased().contains(q)
            || card.cardNumber.lowercased().contains(q)
            || card.setCode.lowercased().contains(q)
            || (card.subtype?.lowercased().contains(q) == true)
            || (card.subtypes?.contains { $0.lowercased().contains(q) } == true)
        guard matchesQuery else { return false }

        if brand == .pokemon,
           filters.cardTypes.isEmpty == false,
           filters.cardTypes.contains(resolvedBrowseCardType(for: card, brand: brand)) == false {
            return false
        }
        if filters.rarePlusOnly && isCommonOrUncommon(card.rarity) {
            return false
        }
        if filters.hideOwned && ownedCardIDs.contains(card.masterCardId) {
            return false
        }
        if brand == .pokemon,
           filters.legalities.isEmpty == false,
           pokemonCardMatchesLegalityFilters(
                selectedLegalityFilters: filters.legalities,
                setCode: card.setCode,
                releaseDate: setReleaseDateByCode[card.setCode],
                category: card.category,
                energyType: card.energyType,
                regulationMark: card.regulationMark,
                cardName: card.cardName
           ) == false {
            return false
        }
        if filters.energyTypes.isEmpty == false {
            let energies = Set(cardEnergyOptions([card]))
            if energies.isDisjoint(with: filters.energyTypes) {
                return false
            }
        }
        if filters.rarities.isEmpty == false {
            let rarity = card.rarity?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if rarity.isEmpty || filters.rarities.contains(rarity) == false {
                return false
            }
        }
        if filters.trainerTypes.isEmpty == false {
            let trainerType = card.trainerType?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if trainerType.isEmpty || filters.trainerTypes.contains(trainerType) == false {
                return false
            }
        }
        if filters.opCardTypes.isEmpty == false {
            let cardTypes = Set((card.category ?? "").split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            })
            if cardTypes.isDisjoint(with: filters.opCardTypes) {
                return false
            }
        }
        if filters.opAttributes.isEmpty == false {
            let attrs = Set(card.opAttributes ?? [])
            if attrs.isDisjoint(with: filters.opAttributes) { return false }
        }
        if filters.opCosts.isEmpty == false {
            guard let cost = card.opCost, filters.opCosts.contains(cost) else { return false }
        }
        if filters.opCounters.isEmpty == false {
            guard let counter = card.opCounter, filters.opCounters.contains(counter) else { return false }
        }
        if filters.opLives.isEmpty == false {
            guard let life = card.opLife, filters.opLives.contains(life) else { return false }
        }
        if filters.opPowers.isEmpty == false {
            let power = card.hp
            guard let power, filters.opPowers.contains(power) else { return false }
        }
        return true
    }

    switch filters.sortBy {
    case .cardName:
        return filtered.sorted { $0.cardName.localizedCaseInsensitiveCompare($1.cardName) == .orderedAscending }
    case .newestSet:
        return sortCardsByReleaseDateNewestFirst(filtered, sets: sets)
    case .cardNumber, .random, .price, .acquiredDateNewest:
        return filtered
    }
}

private func resolvedBrowseCardType(for card: Card, brand: TCGBrand) -> BrowseCardTypeFilter {
    let category = card.category?.lowercased() ?? ""
    if category.contains("trainer") || card.trainerType != nil {
        return .trainer
    }
    if category.contains("energy") || card.energyType != nil {
        return .energy
    }
    if brand == .onePiece, category.contains("event") {
        return .trainer
    }
    return .pokemon
}

private func pokemonCardMatchesLegalityFilters(
    selectedLegalityFilters: Set<BrowseCardLegalityFilter>,
    setCode: String,
    releaseDate: String?,
    category: String?,
    energyType: String?,
    regulationMark: String?,
    cardName: String
) -> Bool {
    selectedLegalityFilters.contains { legality in
        pokemonCardIsLegalInDeckFormat(
            legality.deckFormat,
            setCode: setCode,
            releaseDate: releaseDate,
            category: category,
            energyType: energyType,
            regulationMark: regulationMark,
            cardName: cardName
        )
    }
}

private func pokemonCardIsLegalInDeckFormat(
    _ format: DeckFormat,
    setCode: String,
    releaseDate: String?,
    category: String?,
    energyType: String?,
    regulationMark: String?,
    cardName: String
) -> Bool {
    if let legalSets = format.legalSetKeys, legalSets.contains(setCode) == false {
        return false
    }
    if format == .pokemonStandard,
       pokemonSetIsTournamentLegal(releaseDate: releaseDate) == false {
        return false
    }
    if let legalMarks = format.legalRegulationMarks {
        let trimmedMark = regulationMark?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmedMark.isEmpty {
            if pokemonCardIsBasicEnergy(category: category, energyType: energyType) == false {
                return false
            }
        } else if legalMarks.contains(trimmedMark) == false {
            return false
        }
    }
    if format.isBanned(cardName: cardName) {
        return false
    }
    return true
}

private func pokemonCardIsBasicEnergy(category: String?, energyType: String?) -> Bool {
    guard category == "Energy" else { return false }
    return energyType?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .caseInsensitiveCompare("Basic") == .orderedSame
}

private func pokemonSetIsTournamentLegal(releaseDate: String?, now: Date = Date()) -> Bool {
    guard let releaseDate, releaseDate.isEmpty == false else { return true }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withFullDate]
    guard let release = formatter.date(from: releaseDate) else { return true }
    guard let legalDate = Calendar(identifier: .gregorian).date(byAdding: .day, value: 14, to: release) else {
        return true
    }
    return legalDate <= now
}

#Preview {
    NavigationStack {
        BrowseView(
            filters: .constant(BrowseCardGridFilters()),
            inlineDetailFilters: .constant(BrowseCardGridFilters()),
            gridOptions: .constant(BrowseGridOptions()),
            isFilterMenuPresented: .constant(false),
            filterResultCount: .constant(0),
            filterEnergyOptions: .constant([]),
            filterRarityOptions: .constant([]),
            filterTrainerTypeOptions: .constant([]),
            inlineDetailFilterResultCount: .constant(0),
            inlineDetailFilterEnergyOptions: .constant([]),
            inlineDetailFilterRarityOptions: .constant([]),
            inlineDetailFilterTrainerTypeOptions: .constant([]),
            selectedTab: .constant(.cards),
            inlineDetailRoute: .constant(nil)
        )
    }
        .environment(AppServices())
        .environmentObject(ChromeScrollCoordinator())
}
