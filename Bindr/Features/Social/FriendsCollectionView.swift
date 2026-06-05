import SwiftUI

/// Merged view of all friends' collections, loaded from R2 snapshots.
/// Supports the same search, sort, filters, and grid options as My Collection.
struct FriendsCollectionView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.presentCardAtIndex) private var presentCardAtIndex

    // MARK: - State

    @State private var allEntries: [FriendCardEntry] = []
    @State private var cardsByID: [String: Card] = [:]
    @State private var priceByCardID: [String: Double] = [:]
    @State private var isLoading = false
    @State private var loadError: String?

    @State private var query = ""
    @State private var filters: BrowseCardGridFilters = {
        var f = BrowseCardGridFilters()
        f.sortBy = .cardName
        return f
    }()
    @State private var gridOptions: BrowseGridOptions = {
        var o = BrowseGridOptions()
        o.showOwned = true  // repurposed: show owner name footnote
        return o
    }()
    @State private var energyOptions: [String] = []
    @State private var rarityOptions: [String] = []
    @State private var trainerTypeOptions: [String] = []

    // Pagination
    @State private var displayedCards: [Card] = []
    @State private var nextIndex = 0
    @State private var isLoadingMore = false
    private static let initialBatch = 36
    private static let pageSize = 18

    // MARK: - Types

    struct FriendCardEntry: Identifiable {
        let id: String // cardID
        let cardID: String
        let variantKey: String
        let owners: [SocialProfile]
        var ownerCount: Int { owners.count }
    }

    // MARK: - Computed

    private var safeColumnCount: Int { min(max(gridOptions.columnCount, 1), 4) }

    private var filteredCards: [Card] {
        filterBrowseCards(
            Array(cardsByID.values),
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
            return filteredCards.sorted { $0.cardName.localizedCaseInsensitiveCompare($1.cardName) == .orderedAscending }
        case .price:
            return filteredCards.sorted { (priceByCardID[$0.masterCardId] ?? 0) > (priceByCardID[$1.masterCardId] ?? 0) }
        default:
            return filteredCards
        }
    }

    private var filterConfig: FilterMenuConfig {
        FilterMenuConfig(
            showAcquiredDateSort: false,
            showRandomSort: false,
            showHideOwned: false,
            showShowDuplicates: false,
            showGridOptions: true,
            defaultSortBy: .cardName,
            showGridOwnedToggle: false
        )
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                BrowseInlineSearchField(
                    title: isLoading ? "Loading…" : "Search \(sortedFilteredCards.count) cards",
                    text: $query
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 10)

                if isLoading && allEntries.isEmpty {
                    ProgressView("Loading friends' collections…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                } else if let error = loadError {
                    ContentUnavailableView(
                        "Couldn't load collections",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error)
                    )
                    .padding(.top, 40)
                } else if sortedFilteredCards.isEmpty && !isLoading {
                    ContentUnavailableView(
                        allEntries.isEmpty ? "No friends' collections yet" : "No matching cards",
                        systemImage: allEntries.isEmpty ? "person.2.slash" : "magnifyingglass",
                        description: Text(allEntries.isEmpty
                            ? "Friends need to sign into social and sync their collections."
                            : "Try a different search or adjust filters.")
                    )
                    .padding(.top, 40)
                } else {
                    cardGrid
                }
            }
        }
        .refreshable { await load() }
        .bindrPageBackground()
        .scrollDismissesKeyboard(.immediately)
        .navigationTitle("Friends' Collections")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Toggle(isOn: $gridOptions.showOwned) {
                        Label("Show owner", systemImage: "person.circle")
                    }
                    Divider()
                    BrowseGridFiltersMenuContent(
                        brand: services.brandSettings.selectedCatalogBrand,
                        filters: $filters,
                        energyOptions: energyOptions,
                        rarityOptions: rarityOptions,
                        trainerTypeOptions: trainerTypeOptions,
                        isAllBrands: false,
                        gridOptions: $gridOptions,
                        config: filterConfig
                    )
                } label: {
                    Image(systemName: filters.isVisiblyCustomized ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(filters.isVisiblyCustomized ? services.theme.accentColor : .primary)
                }
            }
        }
        .task { await load() }
        .onChange(of: query) { _, _ in refreshFeed() }
        .onChange(of: filters) { _, _ in refreshFeed() }
        .onChange(of: cardsByID) { _, _ in refreshFeed() }
    }

    // MARK: - Grid

    private var cardGrid: some View {
        LazyVStack(spacing: 0) {
            EagerVGrid(items: Array(displayedCards.enumerated().map { IndexedCard(index: $0, card: $1) }),
                       columns: safeColumnCount, spacing: 12) { indexed in
                cardCell(for: indexed.card, at: indexed.index)
                    .onAppear {
                        ImagePrefetcher.shared.prefetchCardWindow(displayedCards, startingAt: indexed.index + 1)
                        guard indexed.index >= max(displayedCards.count - safeColumnCount, 0) else { return }
                        Task { await loadMoreIfNeeded() }
                    }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            if isLoadingMore {
                ProgressView().frame(maxWidth: .infinity).padding(.top, 12)
            }
        }
    }

    @ViewBuilder
    private func cardCell(for card: Card, at index: Int) -> some View {
        let owners = allEntries.first(where: { $0.cardID == card.masterCardId })?.owners ?? []
        let footnote: String? = gridOptions.showOwned ? ownerLabel(owners) : nil
        let avatarURL: URL? = gridOptions.showOwned && owners.count == 1
            ? owners[0].avatarURL.flatMap { URL(string: $0) }
                ?? owners[0].favoritePokemonImageURL.flatMap { URL(string: $0) }
            : nil
        Button {
            presentCardAtIndex(displayedCards, index)
        } label: {
            CardGridCell(
                card: card,
                services: services,
                colorScheme: colorScheme,
                gridOptions: gridOptions,
                setName: services.cardData.sets.first { $0.setCode == card.setCode }?.name,
                footnote: footnote,
                footnoteLeadingAvatarURL: avatarURL,
                overridePrice: priceByCardID[card.masterCardId]
            )
        }
        .buttonStyle(CardCellButtonStyle())
    }

    private func ownerLabel(_ owners: [SocialProfile]) -> String {
        switch owners.count {
        case 0: return ""
        case 1: return owners[0].displayName ?? owners[0].username
        case 2: return "\(owners[0].displayName ?? owners[0].username) & \(owners[1].displayName ?? owners[1].username)"
        default: return "\(owners[0].displayName ?? owners[0].username) +\(owners.count - 1)"
        }
    }

    // MARK: - Pagination

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

    // MARK: - Data

    private func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        do {
            let friends = try await services.socialFriend.fetchFriends()
            guard !friends.isEmpty else {
                allEntries = []
                cardsByID = [:]
                refreshFeed()
                return
            }

            // Fetch all snapshots concurrently
            var cardToOwners: [String: [SocialProfile]] = [:]
            await withTaskGroup(of: (SocialProfile, FriendCollectionSnapshot?).self) { group in
                for friend in friends {
                    group.addTask {
                        let snapshot = try? await services.collectionSync.fetchFriendCollection(userID: friend.id)
                        return (friend, snapshot)
                    }
                }
                for await (friend, snapshot) in group {
                    guard let snapshot else { continue }
                    for entry in snapshot.collection where !entry.cardID.isEmpty {
                        cardToOwners[entry.cardID, default: []].append(friend)
                    }
                }
            }

            allEntries = cardToOwners.map { cardID, owners in
                FriendCardEntry(id: cardID, cardID: cardID, variantKey: "normal", owners: owners)
            }

            // Load card data
            var nextCards = cardsByID
            for entry in allEntries where nextCards[entry.cardID] == nil {
                if let card = await services.cardData.loadCard(masterCardId: entry.cardID) {
                    nextCards[card.masterCardId] = card
                }
            }
            cardsByID = nextCards

            // Load prices
            var nextPrices: [String: Double] = [:]
            for card in nextCards.values {
                if let usd = await services.pricing.usdPriceForVariant(for: card, variantKey: "normal") {
                    nextPrices[card.masterCardId] = usd
                }
            }
            priceByCardID = nextPrices

            refreshFeed()
        } catch {
            loadError = error.localizedDescription
        }
    }
}

private struct IndexedCard: Identifiable {
    let index: Int
    let card: Card
    var id: String { card.masterCardId }
}
