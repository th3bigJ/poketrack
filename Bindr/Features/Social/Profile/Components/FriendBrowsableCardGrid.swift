import SwiftUI

/// Searchable, filterable card grid for a friend's wishlist or collection.
struct FriendBrowsableCardGrid: View {
    @Environment(AppServices.self) private var services
    @Environment(\.colorScheme) private var colorScheme

    let cardIDs: [String]
    var quantityByCardID: [String: Int] = [:]
    let cardLoader: (String) async -> Card?
    let onCardTap: (String, [String]) -> Void

    @AppStorage("friendProfile.browse.gridOptions") private var gridOptionsData: Data = {
        (try? JSONEncoder().encode(BrowseGridOptions())) ?? Data()
    }()

    @State private var query = ""
    @State private var filters: BrowseCardGridFilters = {
        var f = BrowseCardGridFilters()
        f.sortBy = .cardName
        return f
    }()
    @State private var cardsByID: [String: Card] = [:]
    @State private var priceByCardID: [String: Double] = [:]
    @State private var displayedCards: [Card] = []
    @State private var nextIndex = 0
    @State private var isLoadingMore = false
    @State private var isResolvingCards = false
    @State private var energyOptions: [String] = []
    @State private var rarityOptions: [String] = []
    @State private var trainerTypeOptions: [String] = []

    private static let initialBatch = 36
    private static let pageSize = 18

    private var gridOptions: BrowseGridOptions {
        get { (try? JSONDecoder().decode(BrowseGridOptions.self, from: gridOptionsData)) ?? BrowseGridOptions() }
        nonmutating set { gridOptionsData = (try? JSONEncoder().encode(newValue)) ?? gridOptionsData }
    }

    private var gridOptionsBinding: Binding<BrowseGridOptions> {
        Binding(get: { gridOptions }, set: { gridOptions = $0 })
    }

    private var safeColumnCount: Int {
        min(max(gridOptions.columnCount, 1), 4)
    }

    private var resolvedCards: [Card] {
        cardIDs.compactMap { cardsByID[$0] }
    }

    private var filteredCards: [Card] {
        filterBrowseCards(
            resolvedCards,
            query: query,
            filters: filters,
            ownedCardIDs: [],
            brand: services.brandSettings.selectedCatalogBrand,
            sets: services.cardData.sets,
            priceByCardID: priceByCardID
        )
    }

    private var sortedFilteredCards: [Card] {
        switch filters.sortBy {
        case .cardName:
            return filteredCards.sorted {
                $0.cardName.localizedCaseInsensitiveCompare($1.cardName) == .orderedAscending
            }
        case .price:
            return filteredCards.sorted {
                (priceByCardID[$0.masterCardId] ?? 0) > (priceByCardID[$1.masterCardId] ?? 0)
            }
        default:
            return filteredCards
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            BrowseCardGridControlsBar(
                searchTitle: searchPlaceholder,
                query: $query,
                filters: $filters,
                gridOptions: gridOptionsBinding,
                brand: services.brandSettings.selectedCatalogBrand,
                energyOptions: energyOptions,
                rarityOptions: rarityOptions,
                trainerTypeOptions: trainerTypeOptions
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            if isResolvingCards && resolvedCards.isEmpty {
                ProgressView("Loading cards…")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else if sortedFilteredCards.isEmpty {
                ContentUnavailableView(
                    resolvedCards.isEmpty ? "No cards yet" : "No matching cards",
                    systemImage: resolvedCards.isEmpty ? "rectangle.stack" : "magnifyingglass",
                    description: Text(
                        resolvedCards.isEmpty
                            ? "Cards will appear here once they are shared."
                            : "Try a different search or adjust filters."
                    )
                )
                .padding(.top, 24)
                .padding(.horizontal, 16)
            } else {
                cardGrid
            }
        }
        .task(id: cardIDs) {
            await resolveCards()
        }
        .task(id: priceTaskKey) {
            await refreshPrices()
        }
        .onChange(of: query) { _, _ in refreshFeed() }
        .onChange(of: filters) { _, _ in refreshFeed() }
        .onChange(of: cardsByID.count) { _, _ in refreshFeed() }
    }

    private var searchPlaceholder: String {
        let count = sortedFilteredCards.count
        if isResolvingCards && resolvedCards.isEmpty {
            return "Search cards"
        }
        return count == 1 ? "Search 1 card" : "Search \(count) cards"
    }

    private var priceTaskKey: String {
        let ids = resolvedCards.map(\.masterCardId).sorted().joined(separator: "|")
        return "\(ids)_\(filters.sortBy.rawValue)_\(services.priceDisplay.currency.rawValue)"
    }

    private var cardGrid: some View {
        LazyVStack(spacing: 0) {
            EagerVGrid(
                items: Array(displayedCards.enumerated().map { IndexedFriendCard(index: $0.offset, card: $0.element) }),
                columns: safeColumnCount,
                spacing: 12
            ) { indexed in
                cardCell(for: indexed.card)
                    .onAppear {
                        ImagePrefetcher.shared.prefetchCardWindow(displayedCards, startingAt: indexed.index + 1)
                        guard indexed.index >= max(displayedCards.count - safeColumnCount, 0) else { return }
                        Task { await loadMoreIfNeeded() }
                    }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            if isLoadingMore {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
            }
        }
    }

    @ViewBuilder
    private func cardCell(for card: Card) -> some View {
        Button {
            let orderedIDs = sortedFilteredCards.map(\.masterCardId)
            onCardTap(card.masterCardId, orderedIDs)
        } label: {
            CardGridCell(
                card: card,
                services: services,
                colorScheme: colorScheme,
                gridOptions: gridOptions,
                setName: services.cardData.sets.first { $0.setCode == card.setCode }?.name,
                ownedCountBadge: quantityByCardID[card.masterCardId],
                alwaysShowOwnedCountBadge: quantityByCardID[card.masterCardId] != nil,
                overridePrice: priceByCardID[card.masterCardId]
            )
        }
        .buttonStyle(CardCellButtonStyle())
    }

    @MainActor
    private func resolveCards() async {
        isResolvingCards = true
        defer { isResolvingCards = false }

        var next = cardsByID
        for id in cardIDs where next[id] == nil {
            if let card = await cardLoader(id) {
                next[card.masterCardId] = card
            }
        }
        cardsByID = next
        refreshFeed()
    }

    @MainActor
    private func refreshPrices() async {
        var next: [String: Double] = [:]
        for card in resolvedCards {
            if let usd = await services.pricing.usdPriceForVariant(for: card, variantKey: "normal") {
                next[card.masterCardId] = usd
            }
        }
        priceByCardID = next
        if filters.sortBy == .price {
            refreshFeed()
        }
    }

    @MainActor
    private func refreshFeed() {
        let cards = sortedFilteredCards
        let initial = min(Self.initialBatch, cards.count)
        displayedCards = Array(cards.prefix(initial))
        nextIndex = initial
        energyOptions = cardEnergyOptions(cards)
        rarityOptions = cardRarityOptions(cards)
        trainerTypeOptions = cardTrainerTypeOptions(cards)
    }

    @MainActor
    private func loadMoreIfNeeded() async {
        guard !isLoadingMore, nextIndex < sortedFilteredCards.count else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let end = min(nextIndex + Self.pageSize, sortedFilteredCards.count)
        displayedCards.append(contentsOf: sortedFilteredCards[nextIndex..<end])
        nextIndex = end
    }
}

private struct IndexedFriendCard: Identifiable {
    let index: Int
    let card: Card
    var id: Int { index }
}
