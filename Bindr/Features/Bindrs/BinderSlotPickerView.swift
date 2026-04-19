 import SwiftData
import SwiftUI

struct BinderSlotPickerSelection {
    let cardID: String
    let variantKey: String
    let cardName: String
}

private enum BinderPickerSource: String, CaseIterable, Identifiable {
    case allCards
    case collection
    case wishlist

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allCards: return "All Cards"
        case .collection: return "Collection"
        case .wishlist: return "Wishlist"
        }
    }
}

private struct BinderPickerEntry: Identifiable {
    let id: String
    let card: Card
    let variantKey: String
    let footnote: String?
    let isOwned: Bool
}

private enum BinderPickerBrowseRoute: Hashable {
    case sets
    case set(TCGSet)
    case pokemon
    case dex(dexId: Int, displayName: String)
    case onePieceCharacters
    case onePieceCharacter(String)
    case onePieceSubtypes
    case onePieceSubtype(String)
}

struct BinderSlotPickerView: View {
    @Environment(AppServices.self) private var services
    @Query(sort: \CollectionItem.dateAcquired, order: .reverse) private var collectionItems: [CollectionItem]
    @Query(sort: \WishlistItem.dateAdded, order: .reverse) private var wishlistItems: [WishlistItem]
    @Environment(\.dismiss) private var dismiss

    let startPosition: Int
    let occupiedPositions: Set<Int>
    var onAdd: ([BinderSlotPickerSelection]) -> Void

    @State private var source: BinderPickerSource = .allCards
    @State private var selectedBrand: TCGBrand = .pokemon
    @State private var query = ""
    @State private var debouncedQuery = ""
    @State private var filters = BrowseCardGridFilters()
    @State private var gridOptions = BrowseGridOptions(showCardName: true, showSetName: true, showSetID: false, showPricing: false, showOwned: true, columnCount: 3)
    @State private var allCardRefs: [CardRef] = []
    @State private var filteredAllCardRefs: [CardRef] = []
    @State private var displayedAllCards: [Card] = []
    @State private var allCardSearchResults: [Card] = []
    @State private var allBrowseFilterCards: [BrowseFilterCard] = []
    @State private var catalogSets: [TCGSet] = []
    @State private var nextRefIndex = 0
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var isSearching = false
    @State private var loadError: String?
    @State private var basket: [BinderSlotPickerSelection] = []
    @State private var resolvedCardsByID: [String: Card] = [:]
    @State private var browsePath: [BinderPickerBrowseRoute] = []

    private static let initialBatchSize = 36
    private static let pageSize = 24

    private var enabledBrands: [TCGBrand] {
        services.brandsManifest.sortBrands(services.brandSettings.enabledBrands)
    }

    private var ownedCardIDs: Set<String> {
        Set(collectionItems.map(\.cardID))
    }

    private var basketCardIDs: Set<String> {
        Set(basket.map(\.cardID))
    }

    private var setNameByCode: [String: String] {
        var result: [String: String] = [:]
        for set in catalogSets where result[set.setCode] == nil {
            result[set.setCode] = set.name
        }
        return result
    }

    private var releaseDateBySetCode: [String: String] {
        var result: [String: String] = [:]
        for set in catalogSets where result[set.setCode] == nil {
            result[set.setCode] = set.releaseDate ?? ""
        }
        return result
    }

    private var sourceCards: [Card] {
        switch source {
        case .allCards:
            return debouncedQueryIsActive ? allCardsBase : []
        case .collection:
            return collectionEntries.map(\.card)
        case .wishlist:
            return wishlistEntries.map(\.card)
        }
    }

    private var energyOptions: [String] {
        switch source {
        case .allCards:
            return allBrowseFilterCards.isEmpty ? cardEnergyOptions(allCardsBase) : browseFilterEnergyOptions(allBrowseFilterCards)
        case .collection, .wishlist:
            return cardEnergyOptions(sourceCards)
        }
    }

    private var rarityOptions: [String] {
        switch source {
        case .allCards:
            return allBrowseFilterCards.isEmpty ? cardRarityOptions(allCardsBase) : browseFilterRarityOptions(allBrowseFilterCards)
        case .collection, .wishlist:
            return cardRarityOptions(sourceCards)
        }
    }

    private var trainerTypeOptions: [String] {
        switch source {
        case .allCards:
            return allBrowseFilterCards.isEmpty ? cardTrainerTypeOptions(allCardsBase) : browseFilterTrainerTypeOptions(allBrowseFilterCards)
        case .collection, .wishlist:
            return cardTrainerTypeOptions(sourceCards)
        }
    }

    private var allCardsBase: [Card] {
        debouncedQueryIsActive ? allCardSearchResults : displayedAllCards
    }

    private var liveTrimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var debouncedTrimmedQuery: String {
        debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var debouncedQueryIsActive: Bool {
        !debouncedTrimmedQuery.isEmpty
    }

    private var collectionEntries: [BinderPickerEntry] {
        collectionItems.compactMap { item in
            guard TCGBrand.inferredFromMasterCardId(item.cardID) == selectedBrand else { return nil }
            guard let card = resolvedCardsByID[item.cardID] else { return nil }
            return BinderPickerEntry(
                id: "collection|\(String(describing: item.persistentModelID))",
                card: card,
                variantKey: item.variantKey,
                footnote: "×\(item.quantity) · \(displayVariant(item.variantKey))",
                isOwned: true
            )
        }
    }

    private var wishlistEntries: [BinderPickerEntry] {
        wishlistItems.compactMap { item in
            guard TCGBrand.inferredFromMasterCardId(item.cardID) == selectedBrand else { return nil }
            guard let card = resolvedCardsByID[item.cardID] else { return nil }
            return BinderPickerEntry(
                id: "wishlist|\(String(describing: item.persistentModelID))",
                card: card,
                variantKey: item.variantKey,
                footnote: displayVariant(item.variantKey),
                isOwned: ownedCardIDs.contains(item.cardID)
            )
        }
    }

    private var visibleEntries: [BinderPickerEntry] {
        switch source {
        case .allCards:
            return allCardsBase.map { card in
                BinderPickerEntry(
                    id: "all|\(card.masterCardId)",
                    card: card,
                    variantKey: card.pricingVariants?.first ?? "normal",
                    footnote: nil,
                    isOwned: ownedCardIDs.contains(card.masterCardId)
                )
            }
        case .collection:
            return sortedEntries(collectionEntries)
        case .wishlist:
            return sortedEntries(wishlistEntries)
        }
    }

    private var overwriteCount: Int {
        let end = startPosition + basket.count
        guard end > startPosition else { return 0 }
        return occupiedPositions.intersection(Set(startPosition..<end)).count
    }

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: 12),
            count: min(max(gridOptions.columnCount, 1), 4)
        )
    }

    private var preloadTriggerEntryID: String? {
        visibleEntries.suffix(4).first?.id
    }

    var body: some View {
        NavigationStack(path: $browsePath) {
            Group {
                if isLoading && !isSearching && visibleEntries.isEmpty {
                    ProgressView("Loading cards…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let loadError {
                    ContentUnavailableView(
                        "Couldn't load cards",
                        systemImage: "exclamationmark.triangle",
                        description: Text(loadError)
                    )
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            header

                            if isSearching && visibleEntries.isEmpty {
                                ProgressView("Searching…")
                                    .frame(maxWidth: .infinity, minHeight: 220)
                                    .padding(.top, 24)
                            } else if visibleEntries.isEmpty {
                                emptyState
                                    .frame(maxWidth: .infinity, minHeight: 280)
                                    .padding(.top, 24)
                            } else {
                                LazyVGrid(columns: columns, spacing: 12) {
                                    ForEach(visibleEntries) { entry in
                                        Button {
                                            toggleBasket(entry: entry)
                                        } label: {
                                            BinderPickerCardCell(
                                                entry: entry,
                                                setName: setNameByCode[entry.card.setCode],
                                                gridOptions: gridOptions,
                                                isSelected: basketCardIDs.contains(entry.card.masterCardId)
                                            )
                                        }
                                        .buttonStyle(CardCellButtonStyle())
                                        .onAppear {
                                            guard source == .allCards, debouncedQueryIsActive == false else { return }
                                            guard entry.id == preloadTriggerEntryID else { return }
                                            Task { await loadNextAllCardsPage() }
                                        }
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.top, 12)
                            }

                            if isLoadingMore {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                            }
                            Spacer(minLength: 0)
                                .frame(height: 110)
                        }
                    }
                }
            }
            .navigationTitle("Add Cards")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: BinderPickerBrowseRoute.self) { route in
                switch route {
                case .sets:
                    BinderPickerSetsView(brand: selectedBrand)
                case .set(let set):
                    BinderPickerCatalogCardsView(
                        path: $browsePath,
                        title: set.name,
                        searchPlaceholder: "Search cards in set",
                        selectedBrand: selectedBrand,
                        basketCardIDs: basketCardIDs,
                        loadCards: {
                            let loaded = await services.cardData.loadCards(forSetCode: set.setCode, catalogBrand: selectedBrand)
                            return sortCardsByLocalIdHighestFirst(loaded)
                        },
                        onToggle: { card in toggleBasketCard(card) }
                    )
                case .pokemon:
                    BinderPickerPokemonBrowseView()
                case .dex(let dexId, let displayName):
                    BinderPickerCatalogCardsView(
                        path: $browsePath,
                        title: displayName,
                        searchPlaceholder: "Search cards for Pokémon",
                        selectedBrand: .pokemon,
                        basketCardIDs: basketCardIDs,
                        loadCards: { await loadPokemonDexCards(dexId: dexId) },
                        onToggle: { card in toggleBasketCard(card) }
                    )
                case .onePieceCharacters:
                    BinderPickerOnePieceBrowseListView(mode: .characters)
                case .onePieceCharacter(let name):
                    BinderPickerCatalogCardsView(
                        path: $browsePath,
                        title: name,
                        searchPlaceholder: "Search cards for character",
                        selectedBrand: .onePiece,
                        basketCardIDs: basketCardIDs,
                        loadCards: { await loadOnePieceCharacterCards(name: name) },
                        onToggle: { card in toggleBasketCard(card) }
                    )
                case .onePieceSubtypes:
                    BinderPickerOnePieceBrowseListView(mode: .subtypes)
                case .onePieceSubtype(let name):
                    BinderPickerCatalogCardsView(
                        path: $browsePath,
                        title: name,
                        searchPlaceholder: "Search cards for subtype",
                        selectedBrand: .onePiece,
                        basketCardIDs: basketCardIDs,
                        loadCards: { await loadOnePieceSubtypeCards(name: name) },
                        onToggle: { card in toggleBasketCard(card) }
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        BrowseGridFiltersMenuContent(
                            brand: selectedBrand,
                            filters: $filters,
                            energyOptions: energyOptions,
                            rarityOptions: rarityOptions,
                            trainerTypeOptions: trainerTypeOptions,
                            gridOptions: $gridOptions,
                            config: FilterMenuConfig(
                                showSortBy: true,
                                showAcquiredDateSort: false,
                                showBrandFilters: false,
                                showRarity: true,
                                showRarePlusOnly: true,
                                showHideOwned: source == .allCards,
                                showShowDuplicates: false,
                                showGridOptions: true,
                                defaultSortBy: .newestSet
                            )
                        )
                    } label: {
                        Image(systemName: filters.isVisiblyCustomized ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .task(id: selectedBrand) {
                await reloadForBrand()
            }
            .task(id: visibleItemSignature) {
                await resolveVisibleCards()
            }
            .onChange(of: source) { _, _ in
                if source == .allCards {
                    Task { await reloadAllCardsIfNeeded() }
                }
            }
            .task(id: query) {
                if liveTrimmedQuery.isEmpty {
                    debouncedQuery = ""
                    return
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled else { return }
                debouncedQuery = query
            }
            .task(id: searchTaskKey) {
                await handleQueryChanged()
            }
            .onChange(of: browsePath) { _, newPath in
                guard newPath.isEmpty, source == .allCards else { return }
                displayedAllCards = []
                isLoading = true
                Task { await restoreAllCardsFeedIfNeeded() }
            }
            .onChange(of: filters) { _, _ in
                guard source == .allCards, debouncedQueryIsActive == false else { return }
                Task { await rebuildFilteredRefFeed(reset: true) }
            }
            .onAppear {
                selectedBrand = services.brandSettings.selectedCatalogBrand
                filters.sortBy = .newestSet
                Task { await restoreAllCardsFeedIfNeeded() }
            }
            .safeAreaInset(edge: .bottom) {
                basketBar
            }
        }
    }

    @ViewBuilder
    private var basketBar: some View {
        if !basket.isEmpty {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 32, height: 32)
                    Text("\(basket.count)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("\(basket.count) card\(basket.count == 1 ? "" : "s") in basket")
                        .font(.subheadline.weight(.semibold))
                    Text(overwriteCount > 0
                         ? "Replaces \(overwriteCount) slot\(overwriteCount == 1 ? "" : "s")"
                         : "Fills slots \(startPosition + 1)–\(startPosition + basket.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    onAdd(basket)
                    dismiss()
                } label: {
                    Text("Add to Binder")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.accentColor, in: Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.regularMaterial)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            if enabledBrands.count > 1 {
                Picker("Brand", selection: $selectedBrand) {
                    ForEach(enabledBrands) { brand in
                        Text(brand.displayTitle).tag(brand)
                    }
                }
                .pickerStyle(.segmented)
            }

            Picker("Source", selection: $source) {
                ForEach(BinderPickerSource.allCases) { source in
                    Text(source.title).tag(source)
                }
            }
            .pickerStyle(.segmented)

            browseShortcutRow

            BrowseInlineSearchField(title: searchPlaceholder, text: $query)

            HStack {
                Text("Tap cards to fill from slot \(startPosition + 1).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(visibleEntries.count) shown")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var browseShortcutRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                NavigationLink(value: BinderPickerBrowseRoute.sets) {
                    shortcutChip(title: "Sets")
                }

                switch selectedBrand {
                case .pokemon:
                    NavigationLink(value: BinderPickerBrowseRoute.pokemon) {
                        shortcutChip(title: "Pokémon")
                    }
                case .onePiece:
                    NavigationLink(value: BinderPickerBrowseRoute.onePieceCharacters) {
                        shortcutChip(title: "Characters")
                    }
                    NavigationLink(value: BinderPickerBrowseRoute.onePieceSubtypes) {
                        shortcutChip(title: "Subtypes")
                    }
                case .lorcana:
                    EmptyView()
                }
            }
        }
    }

    private func shortcutChip(title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color(uiColor: .secondarySystemFill))
            )
    }

    private var searchPlaceholder: String {
        switch source {
        case .allCards:
            return "Browse all \(selectedBrand.displayTitle) cards"
        case .collection:
            return "Search your collection"
        case .wishlist:
            return "Search your wishlist"
        }
    }

    private var emptyState: some View {
        let trimmed = debouncedTrimmedQuery
        return ContentUnavailableView(
            trimmed.isEmpty ? emptyTitle : "No matching cards",
            systemImage: trimmed.isEmpty ? emptyStateIcon : "magnifyingglass",
            description: Text(trimmed.isEmpty ? emptyDescription : "Try a different search or loosen your filters.")
        )
    }

    private var emptyTitle: String {
        switch source {
        case .allCards: return "No cards found"
        case .collection: return "No collection cards"
        case .wishlist: return "No wishlist cards"
        }
    }

    private var emptyDescription: String {
        switch source {
        case .allCards: return "Download a catalog to browse cards here."
        case .collection: return "Cards you own will show up here for quick binder building."
        case .wishlist: return "Cards on your wishlist will show up here for quick binder planning."
        }
    }

    private var emptyStateIcon: String {
        switch source {
        case .allCards: return "rectangle.stack"
        case .collection: return "square.stack.3d.up"
        case .wishlist: return "star"
        }
    }

    // MARK: - Basket operations

    private func toggleBasket(entry: BinderPickerEntry) {
        toggleBasketCard(entry.card, variantKey: entry.variantKey)
    }

    private func toggleBasketCard(_ card: Card, variantKey: String? = nil) {
        if let idx = basket.firstIndex(where: { $0.cardID == card.masterCardId }) {
            basket.remove(at: idx)
        } else {
            basket.append(BinderSlotPickerSelection(
                cardID: card.masterCardId,
                variantKey: variantKey ?? card.pricingVariants?.first ?? "normal",
                cardName: card.cardName
            ))
        }
    }

    // MARK: - Data loading

    private func reloadForBrand() async {
        allCardSearchResults = []
        query = ""
        debouncedQuery = ""
        await reloadAllCardsIfNeeded(force: true)
        await resolveVisibleCards()
    }

    private func reloadAllCardsIfNeeded(force: Bool = false) async {
        guard source == .allCards || force else { return }
        isLoading = true
        loadError = nil
        if force {
            allCardRefs = []
            filteredAllCardRefs = []
            displayedAllCards = []
            allBrowseFilterCards = []
            nextRefIndex = 0
        }

        do {
            try CatalogStore.shared.open()
            let sets = try CatalogStore.shared.fetchAllSets(for: selectedBrand)
            let refs = try CatalogStore.shared.fetchAllCardRefs(for: selectedBrand)
            let filterCards = try CatalogStore.shared.fetchAllBrowseFilterCards(for: selectedBrand)
            await MainActor.run {
                catalogSets = sets
                allCardRefs = refs
                allBrowseFilterCards = filterCards
                filteredAllCardRefs = refs
                displayedAllCards = []
                nextRefIndex = 0
            }
            await rebuildFilteredRefFeed(reset: true)
        } catch {
            await MainActor.run {
                loadError = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func handleQueryChanged() async {
        guard source == .allCards else { return }
        let trimmed = debouncedTrimmedQuery
        if trimmed.isEmpty {
            allCardSearchResults = []
            isSearching = false
            isLoading = false
            await rebuildFilteredRefFeed(reset: true)
            return
        }

        isSearching = true
        var results = await services.cardData.search(query: trimmed, catalogBrand: selectedBrand)
        if filters.sortBy == .price {
            var pricedCards: [(card: Card, price: Double?)] = []
            pricedCards.reserveCapacity(results.count)
            for card in results {
                let entry = await services.pricing.pricing(for: card)
                pricedCards.append((card, pickerMarketPriceUSD(for: entry)))
            }
            results = pricedCards.sorted { lhs, rhs in
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
            }.map(\.card)
        }
        await MainActor.run {
            allCardSearchResults = results
            isSearching = false
            isLoading = false
        }
    }

    private func loadNextAllCardsPage(reset: Bool = false) async {
        guard debouncedQueryIsActive == false else { return }
        guard isLoadingMore == false else { return }
        guard reset || nextRefIndex < filteredAllCardRefs.count else {
            isLoading = false
            return
        }

        isLoadingMore = true
        let start = reset ? 0 : nextRefIndex
        let end = min(start + (reset ? Self.initialBatchSize : Self.pageSize), filteredAllCardRefs.count)
        let batch = Array(filteredAllCardRefs[start..<end])
        let cards = await loadCardsInOrder(batch, brand: selectedBrand)

        await MainActor.run {
            if reset {
                displayedAllCards = cards
            } else {
                displayedAllCards.append(contentsOf: cards)
            }
            for card in cards {
                resolvedCardsByID[card.masterCardId] = card
            }
            nextRefIndex = end
            isLoading = false
            isLoadingMore = false
        }
    }

    private func rebuildFilteredRefFeed(reset: Bool) async {
        let refs = await orderedFilteredRefs(from: allBrowseFilterCards)
        await MainActor.run {
            filteredAllCardRefs = refs
            if reset {
                displayedAllCards = []
                nextRefIndex = 0
            }
        }
        await loadNextAllCardsPage(reset: true)
    }

    private func restoreAllCardsFeedIfNeeded() async {
        guard source == .allCards else { return }
        guard debouncedQueryIsActive == false else { return }
        guard displayedAllCards.isEmpty else {
            isLoading = false
            return
        }
        guard filteredAllCardRefs.isEmpty == false else {
            await reloadAllCardsIfNeeded()
            return
        }
        await loadNextAllCardsPage(reset: true)
    }

    private func resolveVisibleCards() async {
        var next = resolvedCardsByID
        let ids = Set(
            collectionItems
                .filter { TCGBrand.inferredFromMasterCardId($0.cardID) == selectedBrand }
                .map(\.cardID)
                + wishlistItems
                .filter { TCGBrand.inferredFromMasterCardId($0.cardID) == selectedBrand }
                .map(\.cardID)
        )

        for id in ids where next[id] == nil {
            if let card = await services.cardData.loadCard(masterCardId: id) {
                next[id] = card
            }
        }

        await MainActor.run {
            resolvedCardsByID = next
        }
    }

    private func loadCardsInOrder(_ refs: [CardRef], brand: TCGBrand) async -> [Card] {
        guard !refs.isEmpty else { return [] }
        var bySet: [String: Set<String>] = [:]
        for ref in refs {
            bySet[ref.setCode, default: []].insert(ref.masterCardId)
        }

        var cardByKey: [String: Card] = [:]
        for (setCode, ids) in bySet {
            let loaded = await services.cardData.loadCards(forSetCode: setCode, catalogBrand: brand)
            for card in loaded where ids.contains(card.masterCardId) {
                cardByKey["\(card.setCode)|\(card.masterCardId)"] = card
            }
        }

        return refs.compactMap { cardByKey["\($0.setCode)|\($0.masterCardId)"] }
    }

    private func orderedFilteredRefs(from cards: [BrowseFilterCard]) async -> [CardRef] {
        let filtered = filterBrowseFilterCards(cards)
        switch filters.sortBy {
        case .random, .acquiredDateNewest:
            let filteredIDs = Set(filtered.map(\.masterCardId))
            let ordered = allCardRefs.filter { filteredIDs.contains($0.masterCardId) }
            let covered = Set(ordered.map(\.masterCardId))
            let remainder = filtered.lazy
                .filter { !covered.contains($0.masterCardId) }
                .map(\.ref)
            return ordered + remainder
        case .newestSet:
            return sortBrowseFilterCardsByReleaseDateNewestFirst(filtered, sets: catalogSets).map(\.ref)
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
            let cards = await loadCardsInOrder(refs, brand: selectedBrand)
            var pricedCards: [(card: Card, price: Double?)] = []
            pricedCards.reserveCapacity(cards.count)
            for card in cards {
                let entry = await services.pricing.pricing(for: card)
                pricedCards.append((card, pickerMarketPriceUSD(for: entry)))
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

    private func filterBrowseFilterCards(_ cards: [BrowseFilterCard]) -> [BrowseFilterCard] {
        cards.filter { card in
            if selectedBrand == .pokemon,
               filters.cardTypes.isEmpty == false,
               filters.cardTypes.contains(resolvedCardType(for: card)) == false {
                return false
            }
            if filters.rarePlusOnly && isCommonOrUncommon(card.rarity) { return false }
            if filters.hideOwned && ownedCardIDs.contains(card.masterCardId) { return false }
            if filters.energyTypes.isEmpty == false {
                let energies = Set(resolvedEnergyTypes(for: card))
                if energies.isDisjoint(with: filters.energyTypes) { return false }
            }
            if filters.rarities.isEmpty == false {
                let rarity = trimmedValue(card.rarity)
                if rarity.isEmpty || filters.rarities.contains(rarity) == false { return false }
            }
            if filters.trainerTypes.isEmpty == false {
                let trainerType = trimmedValue(card.trainerType)
                if trainerType.isEmpty || filters.trainerTypes.contains(trainerType) == false { return false }
            }
            if filters.opCardTypes.isEmpty == false {
                let cardTypes = Set((card.category ?? "").split(separator: ",").map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                })
                if cardTypes.isDisjoint(with: filters.opCardTypes) { return false }
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
            if filters.lcCardTypes.isEmpty == false {
                let supertype = trimmedValue(card.category)
                if supertype.isEmpty || filters.lcCardTypes.contains(supertype) == false { return false }
            }
            if filters.lcVariants.isEmpty == false {
                let variant = trimmedValue(card.lcVariant)
                if variant.isEmpty || filters.lcVariants.contains(variant) == false { return false }
            }
            if filters.lcCosts.isEmpty == false {
                guard let cost = card.lcCost, filters.lcCosts.contains(cost) else { return false }
            }
            if filters.lcStrengths.isEmpty == false {
                guard let strength = card.lcStrength, filters.lcStrengths.contains(strength) else { return false }
            }
            if filters.lcWillpowers.isEmpty == false {
                guard let willpower = card.lcWillpower, filters.lcWillpowers.contains(willpower) else { return false }
            }
            if filters.lcLores.isEmpty == false {
                guard let lore = card.lcLore, filters.lcLores.contains(lore) else { return false }
            }
            return true
        }
    }

    private func resolvedCardType(for card: BrowseFilterCard) -> BrowseCardTypeFilter {
        if selectedBrand == .onePiece {
            let category = card.category?.lowercased() ?? ""
            if category.contains("event") { return .trainer }
            return .pokemon
        }
        if selectedBrand == .lorcana { return .pokemon }
        let category = card.category?.lowercased() ?? ""
        if category.contains("trainer") || card.trainerType != nil { return .trainer }
        if category.contains("energy") || card.energyType != nil { return .energy }
        return .pokemon
    }

    private func resolvedEnergyTypes(for card: BrowseFilterCard) -> [String] {
        var values = Set<String>()
        if let energyType = card.energyType {
            let trimmed = trimmedValue(energyType)
            if !trimmed.isEmpty { values.insert(trimmed) }
        }
        for type in card.elementTypes ?? [] {
            let trimmed = trimmedValue(type)
            if !trimmed.isEmpty { values.insert(trimmed) }
        }
        return Array(values)
    }

    private func compareReleaseDateNewestFirst(lhsSetCode: String, rhsSetCode: String) -> Bool {
        let lhs = releaseDateBySetCode[lhsSetCode] ?? ""
        let rhs = releaseDateBySetCode[rhsSetCode] ?? ""
        if lhs != rhs { return lhs > rhs }
        return lhsSetCode.localizedStandardCompare(rhsSetCode) == .orderedAscending
    }

    private func trimmedValue(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func pickerMarketPriceUSD(for entry: CardPricingEntry?) -> Double? {
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

    private func sortBrowseFilterCardsByReleaseDateNewestFirst(_ cards: [BrowseFilterCard], sets: [TCGSet]) -> [BrowseFilterCard] {
        guard !cards.isEmpty else { return cards }
        let dates = firstSetValueMap(sets, key: \.setCode) { $0.releaseDate ?? "" }
        return cards.sorted { lhs, rhs in
            let lhsDate = dates[lhs.setCode] ?? ""
            let rhsDate = dates[rhs.setCode] ?? ""
            if lhsDate != rhsDate { return lhsDate > rhsDate }
            if lhs.setCode != rhs.setCode {
                return lhs.setCode.localizedStandardCompare(rhs.setCode) == .orderedAscending
            }
            return lhs.cardNumber.localizedStandardCompare(rhs.cardNumber) == .orderedAscending
        }
    }

    private func firstSetValueMap<Input, Key: Hashable, Value>(
        _ values: [Input],
        key: KeyPath<Input, Key>,
        value: (Input) -> Value
    ) -> [Key: Value] {
        var result: [Key: Value] = [:]
        result.reserveCapacity(values.count)
        for item in values where result[item[keyPath: key]] == nil {
            result[item[keyPath: key]] = value(item)
        }
        return result
    }

    private func loadPokemonDexCards(dexId: Int) async -> [Card] {
        do {
            try CatalogStore.shared.open()
            let cards = try CatalogStore.shared.fetchAllCards(for: .pokemon)
            return sortCardsByReleaseDateNewestFirst(cards.filter { $0.dexIds?.contains(dexId) == true })
        } catch {
            return []
        }
    }

    private func loadOnePieceCharacterCards(name: String) async -> [Card] {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        do {
            try CatalogStore.shared.open()
            let cards = try CatalogStore.shared.fetchAllCards(for: .onePiece)
            let matches = cards.filter {
                $0.cardName.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current) == normalized
            }
            return sortCardsByReleaseDateNewestFirst(matches)
        } catch {
            return []
        }
    }

    private func loadOnePieceSubtypeCards(name: String) async -> [Card] {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        do {
            try CatalogStore.shared.open()
            let cards = try CatalogStore.shared.fetchAllCards(for: .onePiece)
            let matches = cards.filter { card in
                let values = (card.subtypes ?? []) + [card.subtype].compactMap { $0 }
                return values.contains {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current) == normalized
                }
            }
            return sortCardsByReleaseDateNewestFirst(matches)
        } catch {
            return []
        }
    }

    private func sortCardsByReleaseDateNewestFirst(_ cards: [Card]) -> [Card] {
        cards.sorted { lhs, rhs in
            let lhsDate = releaseDateBySetCode[lhs.setCode] ?? ""
            let rhsDate = releaseDateBySetCode[rhs.setCode] ?? ""
            if lhsDate != rhsDate { return lhsDate > rhsDate }
            if lhs.setCode != rhs.setCode {
                return lhs.setCode.localizedStandardCompare(rhs.setCode) == .orderedAscending
            }
            return lhs.cardNumber.localizedStandardCompare(rhs.cardNumber) == .orderedAscending
        }
    }

    private func sortCardsByLocalIdHighestFirst(_ cards: [Card]) -> [Card] {
        cards.sorted { lhs, rhs in
            let lhsValue = localIdNumericSortValue(lhs.localId)
            let rhsValue = localIdNumericSortValue(rhs.localId)
            if lhsValue != rhsValue { return lhsValue > rhsValue }
            return lhs.masterCardId > rhs.masterCardId
        }
    }

    private func localIdNumericSortValue(_ raw: String?) -> Int {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return Int.min
        }
        if let value = Int(raw) { return value }
        let digits = raw.prefix { $0.isNumber }
        if let value = Int(String(digits)), !digits.isEmpty { return value }
        return Int.min
    }

    private func sortedEntries(_ entries: [BinderPickerEntry]) -> [BinderPickerEntry] {
        let allowedIDs = Set(filteredCards(from: entries.map(\.card)).map(\.masterCardId))
        let filteredEntries = entries.filter { allowedIDs.contains($0.card.masterCardId) }

        switch filters.sortBy {
        case .cardName:
            return filteredEntries.sorted {
                $0.card.cardName.localizedCaseInsensitiveCompare($1.card.cardName) == .orderedAscending
            }
        case .newestSet:
            return filteredEntries.sorted { compareCardsNewestSetFirst($0.card, $1.card) }
        case .cardNumber:
            return filteredEntries.sorted { compareCardsByNumber($0.card, $1.card) }
        case .price, .random, .acquiredDateNewest:
            return filteredEntries
        }
    }

    private func filteredCards(from cards: [Card]) -> [Card] {
        var filterOnly = filters
        filterOnly.sortBy = .random
        return filterBrowseCards(
            cards,
            query: debouncedQuery,
            filters: filterOnly,
            ownedCardIDs: ownedCardIDs,
            brand: selectedBrand,
            sets: catalogSets
        )
    }

    private func compareCardsNewestSetFirst(_ lhs: Card, _ rhs: Card) -> Bool {
        let lhsDate = releaseDateBySetCode[lhs.setCode] ?? ""
        let rhsDate = releaseDateBySetCode[rhs.setCode] ?? ""
        if lhsDate != rhsDate { return lhsDate > rhsDate }
        return compareCardsByNumber(lhs, rhs)
    }

    private func compareCardsByNumber(_ lhs: Card, _ rhs: Card) -> Bool {
        if lhs.setCode != rhs.setCode {
            return lhs.setCode.localizedStandardCompare(rhs.setCode) == .orderedAscending
        }
        let numberComparison = lhs.cardNumber.localizedStandardCompare(rhs.cardNumber)
        if numberComparison != .orderedSame { return numberComparison == .orderedAscending }
        return lhs.cardName.localizedCaseInsensitiveCompare(rhs.cardName) == .orderedAscending
    }

    private func displayVariant(_ variantKey: String) -> String {
        variantKey.replacingOccurrences(of: "_", with: " ")
    }

    private var visibleItemSignature: String {
        let collectionKey = collectionItems
            .filter { TCGBrand.inferredFromMasterCardId($0.cardID) == selectedBrand }
            .map(\.cardID).sorted().joined(separator: "|")
        let wishlistKey = wishlistItems
            .filter { TCGBrand.inferredFromMasterCardId($0.cardID) == selectedBrand }
            .map(\.cardID).sorted().joined(separator: "|")
        return "\(selectedBrand.rawValue)#\(collectionKey)#\(wishlistKey)"
    }

    private var searchTaskKey: String {
        "\(source.rawValue)|\(selectedBrand.rawValue)|\(debouncedTrimmedQuery)"
    }
}

// MARK: - Card cell

private struct BinderPickerCardCell: View {
    let entry: BinderPickerEntry
    let setName: String?
    let gridOptions: BrowseGridOptions
    let isSelected: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            CardGridCell(
                card: entry.card,
                gridOptions: gridOptions,
                setName: setName,
                footnote: entry.footnote
            )

            Image(systemName: isSelected ? "checkmark.circle.fill" : (entry.isOwned ? "checkmark.circle.fill" : "circle"))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isSelected ? Color.accentColor : (entry.isOwned ? .green : .white))
                .background(Circle().fill(isSelected || entry.isOwned ? .white : Color.black.opacity(0.18)))
                .padding(6)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    isSelected ? Color.accentColor : Color.primary.opacity(0.06),
                    lineWidth: isSelected ? 2 : 1
                )
        }
    }
}

// MARK: - Sets browse

private struct BinderPickerSetsView: View {
    let brand: TCGBrand
    @State private var query = ""
    @State private var sets: [TCGSet] = []

    private var filteredSets: [TCGSet] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return sets }
        return sets.filter {
            $0.name.lowercased().contains(trimmed)
                || $0.setCode.lowercased().contains(trimmed)
                || ($0.seriesName?.lowercased().contains(trimmed) == true)
        }
    }

    private var groupedSets: [(title: String, sets: [TCGSet])] {
        let grouped = Dictionary(grouping: filteredSets, by: seriesTitle)
        switch brand {
        case .pokemon:
            return grouped
                .map { (title: $0.key, sets: sortSetsNewestFirst($0.value)) }
                .sorted { lhs, rhs in
                    let lhsOldest = lhs.sets.map(\.releaseDate).compactMap { $0 }.min() ?? ""
                    let rhsOldest = rhs.sets.map(\.releaseDate).compactMap { $0 }.min() ?? ""
                    if lhsOldest != rhsOldest { return lhsOldest > rhsOldest }
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
        case .onePiece:
            return grouped
                .map { (title: $0.key, sets: sortSetsNewestFirst($0.value)) }
                .sorted { lhs, rhs in
                    let lhsIndex = onePieceSeriesOrderIndex(lhs.title)
                    let rhsIndex = onePieceSeriesOrderIndex(rhs.title)
                    if lhsIndex != rhsIndex { return lhsIndex < rhsIndex }
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
        case .lorcana:
            return grouped
                .map { (title: $0.key, sets: sortSetsNewestFirst($0.value)) }
                .sorted { lhs, rhs in
                    let lhsIndex = lorcanaSeriesOrderIndex(lhs.title)
                    let rhsIndex = lorcanaSeriesOrderIndex(rhs.title)
                    if lhsIndex != rhsIndex { return lhsIndex < rhsIndex }
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                BrowseInlineSearchField(title: "Search sets", text: $query)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                if filteredSets.isEmpty {
                    ContentUnavailableView(
                        "No matching sets",
                        systemImage: "rectangle.stack",
                        description: Text("Try a different set name or code.")
                    )
                    .padding(.top, 24)
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
                                ForEach(group.sets) { set in
                                    NavigationLink(value: BinderPickerBrowseRoute.set(set)) {
                                        HStack(spacing: 14) {
                                            SetLogoAsyncImage(logoSrc: set.logoSrc, height: 44, brand: brand)
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
                                    }
                                    .buttonStyle(.plain)
                                    Divider().padding(.leading, 108)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Browse sets")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: brand) {
            do {
                try CatalogStore.shared.open()
                sets = try CatalogStore.shared.fetchAllSets(for: brand)
            } catch {
                sets = []
            }
        }
    }

    private func seriesTitle(for set: TCGSet) -> String {
        switch brand {
        case .pokemon:
            let title = set.seriesName?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (title?.isEmpty == false ? title! : "Other")
        case .onePiece:
            let title = set.seriesName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let lower = title.lowercased()
            if lower.contains("booster pack") { return "Booster Pack" }
            if lower.contains("extra booster") { return "Extra Boosters" }
            if lower.contains("starter") { return "Starter deck" }
            if lower.contains("premium booster") { return "Premium Booster" }
            if lower.contains("promo") { return "Promo" }
            return title.isEmpty ? "Other" : title
        case .lorcana:
            let joined = "\(set.name) \(set.setCode)".lowercased()
            if joined.contains("illumineer") { return "ILLUMINEER'S QUEST" }
            if joined.contains("promo") || set.setCode.lowercased().contains("promo") { return "PROMO" }
            return "MAIN"
        }
    }

    private func sortSetsNewestFirst(_ sets: [TCGSet]) -> [TCGSet] {
        sets.sorted { lhs, rhs in
            let lhsDate = lhs.releaseDate ?? ""
            let rhsDate = rhs.releaseDate ?? ""
            if lhsDate != rhsDate { return lhsDate > rhsDate }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func onePieceSeriesOrderIndex(_ title: String) -> Int {
        switch title {
        case "Booster Pack": return 0
        case "Extra Boosters": return 1
        case "Starter deck": return 2
        case "Premium Booster": return 3
        case "Promo": return 4
        default: return 5
        }
    }

    private func lorcanaSeriesOrderIndex(_ title: String) -> Int {
        switch title {
        case "MAIN": return 0
        case "ILLUMINEER'S QUEST": return 1
        case "PROMO": return 2
        default: return 3
        }
    }
}

// MARK: - Pokémon browse

private struct BinderPickerPokemonBrowseView: View {
    @Environment(AppServices.self) private var services
    @State private var query = ""

    private var rows: [NationalDexPokemon] {
        services.cardData.nationalDexPokemonSorted()
    }

    private var filteredRows: [NationalDexPokemon] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return rows }
        return rows.filter {
            $0.name.lowercased().contains(trimmed)
                || $0.displayName.lowercased().contains(trimmed)
                || String($0.nationalDexNumber).contains(trimmed)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                BrowseInlineSearchField(title: "Search Pokémon", text: $query)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 12)], spacing: 12) {
                    ForEach(filteredRows) { item in
                        NavigationLink(value: BinderPickerBrowseRoute.dex(dexId: item.nationalDexNumber, displayName: item.displayName)) {
                            VStack(spacing: 6) {
                                CachedAsyncImage(url: AppConfiguration.pokemonArtURL(imageFileName: item.imageUrl)) { img in
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
        .navigationTitle("Browse Pokémon")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if services.cardData.nationalDexPokemon.isEmpty {
                await services.cardData.loadNationalDexPokemon()
            }
        }
    }
}

// MARK: - One Piece browse

private struct BinderPickerOnePieceBrowseListView: View {
    @Environment(AppServices.self) private var services
    let mode: Mode
    @State private var query = ""

    enum Mode {
        case characters
        case subtypes
    }

    private var rows: [String] {
        switch mode {
        case .characters: return services.cardData.onePieceCharacterNames
        case .subtypes: return services.cardData.onePieceCharacterSubtypes
        }
    }

    private var filteredRows: [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return rows }
        return rows.filter { $0.lowercased().contains(trimmed) }
    }

    var body: some View {
        List {
            Section {
                BrowseInlineSearchField(title: mode == .characters ? "Search characters" : "Search subtypes", text: $query)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
            }
            ForEach(filteredRows, id: \.self) { row in
                NavigationLink(value: mode == .characters ? BinderPickerBrowseRoute.onePieceCharacter(row) : BinderPickerBrowseRoute.onePieceSubtype(row)) {
                    Text(row)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(mode == .characters ? "Browse characters" : "Browse subtypes")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if services.cardData.onePieceCharacterNames.isEmpty || services.cardData.onePieceCharacterSubtypes.isEmpty {
                await services.cardData.loadOnePieceBrowseMetadata()
            }
        }
    }
}

// MARK: - Catalog cards view (set / dex / character)

private struct BinderPickerCatalogCardsView: View {
    @Environment(AppServices.self) private var services
    @Query private var collectionItems: [CollectionItem]
    @Binding var path: [BinderPickerBrowseRoute]
    let title: String
    let searchPlaceholder: String
    let selectedBrand: TCGBrand
    let basketCardIDs: Set<String>
    let loadCards: () async -> [Card]
    let onToggle: (Card) -> Void

    @State private var cards: [Card] = []
    @State private var isLoading = true
    @State private var query = ""
    @State private var filters = BrowseCardGridFilters()

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: safeColumnCount(services.browseGridOptions.options.columnCount))
    }

    private var setNameByCode: [String: String] {
        var result: [String: String] = [:]
        for set in services.cardData.sets where result[set.setCode] == nil {
            result[set.setCode] = set.name
        }
        return result
    }

    private var ownedCardIDs: Set<String> {
        Set(collectionItems.map(\.cardID))
    }

    private var filteredCards: [Card] {
        filterBrowseCards(cards, query: query, filters: filters, ownedCardIDs: ownedCardIDs, brand: selectedBrand, sets: services.cardData.sets)
    }

    private func safeColumnCount(_ count: Int) -> Int {
        min(max(count, 1), 4)
    }

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView().padding()
            } else {
                VStack(spacing: 12) {
                    BrowseInlineSearchField(title: searchPlaceholder, text: $query)
                        .padding(.horizontal, 16)
                        .padding(.top, 2)
                    if filteredCards.isEmpty {
                        ContentUnavailableView(
                            "No matching cards",
                            systemImage: "magnifyingglass",
                            description: Text("Try a different card name or number.")
                        )
                        .padding(.top, 24)
                    } else {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(filteredCards) { card in
                                Button {
                                    onToggle(card)
                                } label: {
                                    BinderPickerCardCell(
                                        entry: BinderPickerEntry(
                                            id: "all|\(card.masterCardId)",
                                            card: card,
                                            variantKey: card.pricingVariants?.first ?? "normal",
                                            footnote: nil,
                                            isOwned: ownedCardIDs.contains(card.masterCardId)
                                        ),
                                        setName: setNameByCode[card.setCode],
                                        gridOptions: services.browseGridOptions.options,
                                        isSelected: basketCardIDs.contains(card.masterCardId)
                                    )
                                }
                                .buttonStyle(CardCellButtonStyle())
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 100)
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    path.removeAll()
                } label: {
                    Image(systemName: "checkmark")
                }
            }
        }
        .task {
            isLoading = true
            cards = await loadCards()
            isLoading = false
        }
    }
}
