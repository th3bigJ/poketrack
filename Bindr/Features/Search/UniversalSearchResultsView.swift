import SwiftData
import SwiftUI

/// In-app results for the universal search field — catalogue cards/sets/Pokémon,
/// sealed products, local decks/binders, and cached social posts.
struct UniversalSearchResultsView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.presentCard) private var presentCard
    @Environment(\.presentSealedProduct) private var presentSealedProduct

    @Query private var collectionItems: [CollectionItem]
    @Query(sort: \Deck.createdAt, order: .reverse) private var decks: [Deck]
    @Query(sort: \Binder.createdAt, order: .reverse) private var binders: [Binder]

    let query: String
    let selectedBrand: TCGBrand
    let scopeCategory: SearchScopeCategory
    let idleContent: AnyView
    let onCommitSearch: () -> Void
    let onOpenPost: (UUID) -> Void

    @State private var matchingSets: [SearchSetMatch] = []
    @State private var cards: [Card] = []
    @State private var collectionCards: [Card] = []
    @State private var matchingSealed: [SealedProduct] = []
    @State private var matchingDecks: [Deck] = []
    @State private var matchingBinders: [Binder] = []
    @State private var matchingPosts: [SocialFeedService.FeedItem] = []
    @State private var isSearching = false
    @State private var isLoadingAllCards = false
    @State private var isLoadingAllCollectionCards = false
    @State private var isLoadingAllSealed = false
    @State private var showAllCards = false
    @State private var showAllCollectionCards = false
    @State private var showAllSealed = false
    @State private var debouncedQuery = ""
    @State private var lastSearchTaskKey = ""
    @State private var lastSearchCards: [Card] = []
    @State private var lastSearchCollectionCards: [Card] = []
    @State private var lastSearchSealed: [SealedProduct] = []
    @State private var lastSearchSets: [SearchSetMatch] = []
    @State private var priceLineByCardID: [String: String] = [:]
    @State private var collectionPriceLineByCardID: [String: String] = [:]

    private let previewCardLimit = 9
    private let previewSealedLimit = 5

    private var usesAllTabPreviewLimits: Bool {
        scopeCategory == .all
    }

    private var hasMoreCardResults: Bool {
        usesAllTabPreviewLimits && cards.count > previewCardLimit && !showAllCards
    }

    private var hasMoreCollectionResults: Bool {
        usesAllTabPreviewLimits && collectionCards.count > previewCardLimit && !showAllCollectionCards
    }

    private var hasMoreSealedResults: Bool {
        usesAllTabPreviewLimits && matchingSealed.count > previewSealedLimit && !showAllSealed
    }

    init(
        query: String,
        selectedBrand: TCGBrand,
        scopeCategory: SearchScopeCategory,
        idleContent: AnyView,
        onCommitSearch: @escaping () -> Void,
        onOpenPost: @escaping (UUID) -> Void
    ) {
        self.query = query
        self.selectedBrand = selectedBrand
        self.scopeCategory = scopeCategory
        self.idleContent = idleContent
        self.onCommitSearch = onCommitSearch
        self.onOpenPost = onOpenPost

        _collectionItems = Query(
            sort: [SortDescriptor(\CollectionItem.dateAcquired, order: .reverse)]
        )
    }

    private struct SearchSetMatch: Identifiable {
        let set: TCGSet
        let brand: TCGBrand

        var id: String { "\(brand.rawValue)|\(set.id)" }
    }

    private var liveTrimmed: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmed: String {
        debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedQuery: String {
        trimmed.lowercased()
    }

    private var showPokemonDexSection: Bool {
        scopeCategory.showsCatalogPokemon && selectedBrand == .pokemon
    }

    private var matchingPokemon: [NationalDexPokemon] {
        guard showPokemonDexSection, !normalizedQuery.isEmpty else { return [] }
        return services.cardData.searchPokemon(matching: trimmed)
    }

    private var hasAnyResults: Bool {
        !matchingSets.isEmpty
            || !matchingPokemon.isEmpty
            || !cards.isEmpty
            || !collectionCards.isEmpty
            || !matchingSealed.isEmpty
            || !matchingDecks.isEmpty
            || !matchingBinders.isEmpty
            || !matchingPosts.isEmpty
    }

    private let cardColumns = [GridItem(.adaptive(minimum: 110), spacing: BindrSpacing.cardGridColumn)]
    private var displayedCards: [Card] {
        guard usesAllTabPreviewLimits, !showAllCards else { return cards }
        return Array(cards.prefix(previewCardLimit))
    }

    private var displayedCollectionCards: [Card] {
        guard usesAllTabPreviewLimits, !showAllCollectionCards else { return collectionCards }
        return Array(collectionCards.prefix(previewCardLimit))
    }

    private var displayedSealed: [SealedProduct] {
        guard usesAllTabPreviewLimits, !showAllSealed else { return matchingSealed }
        return Array(matchingSealed.prefix(previewSealedLimit))
    }
    private var pricedCardsForRefresh: [Card] {
        displayedCards + displayedCollectionCards
    }

    var body: some View {
        Group {
            if trimmed.isEmpty {
                idleContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: RootChromeEnvironment.searchOverlaySectionSpacing, pinnedViews: []) {
                        if scopeCategory.showsOwnedCollectionCards && !collectionCards.isEmpty {
                            collectionSection
                        }

                        if scopeCategory.showsCatalogCards && !scopeCategory.usesCollectionScope {
                            cardsSection
                        }

                        if scopeCategory.showsCatalogSets && !matchingSets.isEmpty {
                            setsSection
                        }

                        if showPokemonDexSection && !matchingPokemon.isEmpty {
                            pokemonSection
                        }

                        if scopeCategory.showsSealedProducts && !matchingSealed.isEmpty {
                            sealedSection
                        }

                        if scopeCategory.showsDecks && !matchingDecks.isEmpty {
                            decksSection
                        }

                        if scopeCategory.showsBinders && !matchingBinders.isEmpty {
                            bindersSection
                        }

                        if scopeCategory.showsPosts && !matchingPosts.isEmpty {
                            postsSection
                        }

                        if scopeCategory.usesCollectionScope {
                            cardsSection
                        }

                        if !isSearching && !hasAnyResults {
                            ContentUnavailableView(
                                "No results",
                                systemImage: "magnifyingglass",
                                description: Text("Try another term or switch filters.")
                            )
                            .padding(.top, 24)
                        }
                    }
                    .padding(.bottom, 12)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .task(id: query) {
            if liveTrimmed.isEmpty {
                debouncedQuery = ""
                return
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            debouncedQuery = query
        }
        .task(id: searchTaskKey) {
            await performSearch()
        }
        .task(id: cardPriceTaskKey) {
            await refreshCardPriceLines()
        }
    }

    private var cardPriceTaskKey: String {
        [
            pricedCardsForRefresh.map(\.masterCardId).joined(separator: "|"),
            services.priceDisplay.currency.rawValue,
            String(services.pricing.usdToGbp),
        ].joined(separator: ";")
    }

    @MainActor
    private func refreshCardPriceLines() async {
        let visible = pricedCardsForRefresh
        guard !visible.isEmpty else {
            priceLineByCardID = [:]
            collectionPriceLineByCardID = [:]
            return
        }

        let currency = services.priceDisplay.currency
        let fx = services.pricing.usdToGbp
        await services.pricing.prefetchPokemonCardPricing(forSetCodes: [])
        await services.pricing.indexPricingForCards(visible)
        guard !Task.isCancelled else { return }

        var catalogPrices: [String: String] = [:]
        var ownedPrices: [String: String] = [:]
        catalogPrices.reserveCapacity(displayedCards.count)
        ownedPrices.reserveCapacity(displayedCollectionCards.count)

        for card in displayedCards {
            if let entry = services.pricing.cachedPricingEntry(for: card),
               let line = browseMarketPriceLine(for: entry, currency: currency, usdToGbp: fx) {
                catalogPrices[card.masterCardId] = line
            } else if services.pricing.isPricingIndexed(for: card) {
                catalogPrices[card.masterCardId] = "—"
            }
        }

        for card in displayedCollectionCards {
            if let entry = services.pricing.cachedPricingEntry(for: card),
               let line = browseMarketPriceLine(for: entry, currency: currency, usdToGbp: fx) {
                ownedPrices[card.masterCardId] = line
            } else if services.pricing.isPricingIndexed(for: card) {
                ownedPrices[card.masterCardId] = "—"
            }
        }

        priceLineByCardID = catalogPrices
        collectionPriceLineByCardID = ownedPrices
    }

    @MainActor
    private func performSearch() async {
        guard !trimmed.isEmpty else {
            clearResults()
            return
        }

        if lastSearchTaskKey == searchTaskKey {
            matchingSets = lastSearchSets
            cards = lastSearchCards
            collectionCards = lastSearchCollectionCards
            matchingSealed = lastSearchSealed
            return
        }

        isLoadingAllCards = false
        isLoadingAllCollectionCards = false
        isLoadingAllSealed = false
        showAllCards = false
        showAllCollectionCards = false
        showAllSealed = false
        try? await Task.sleep(nanoseconds: 225_000_000)
        guard !Task.isCancelled else { return }

        if showPokemonDexSection, services.cardData.nationalDexPokemon.isEmpty {
            await services.cardData.loadNationalDexPokemon()
        }

        if scopeCategory.showsSealedProducts, services.sealedProducts.products.isEmpty {
            await services.sealedProducts.loadFromLocalIfAvailable()
        }

        isSearching = true
        defer { isSearching = false }

        let q = normalizedQuery

        if scopeCategory.showsCatalogSets {
            let brandSets = await services.cardData.catalogSets(for: selectedBrand)
            matchingSets = brandSets
                .filter { set in
                    set.name.lowercased().contains(q)
                        || set.setCode.lowercased().contains(q)
                        || (set.seriesName?.lowercased().contains(q) == true)
                }
                .map { SearchSetMatch(set: $0, brand: selectedBrand) }
        } else {
            matchingSets = []
        }

        if scopeCategory.showsSealedProducts {
            let allSealed = services.sealedProducts.products.filter { $0.searchBlob.contains(q) }
            matchingSealed = allSealed
            lastSearchSealed = allSealed
        } else {
            matchingSealed = []
            lastSearchSealed = []
        }

        if scopeCategory.showsDecks {
            matchingDecks = decks.filter {
                $0.tcgBrand == selectedBrand && $0.title.lowercased().contains(q)
            }
        } else {
            matchingDecks = []
        }

        if scopeCategory.showsBinders {
            matchingBinders = binders.filter {
                $0.tcgBrand == selectedBrand && $0.title.lowercased().contains(q)
            }
        } else {
            matchingBinders = []
        }

        if scopeCategory.showsPosts {
            matchingPosts = services.socialFeed.items.filter { item in
                switch item.type {
                case .sharedContent, .pull, .dailyDigest:
                    break
                default:
                    return false
                }
                let title = item.content?.title.lowercased() ?? ""
                let description = item.content?.description?.lowercased() ?? ""
                let actor = item.actor?.displayName?.lowercased()
                    ?? item.actor?.username.lowercased()
                    ?? ""
                return title.contains(q) || description.contains(q) || actor.contains(q)
            }
        } else {
            matchingPosts = []
        }

        if scopeCategory.showsCatalogCards {
            if scopeCategory.usesCollectionScope {
                let allCollectionCards = await collectionSearchResults(query: trimmed, brand: selectedBrand)
                cards = allCollectionCards
                lastSearchCards = allCollectionCards
                collectionCards = []
                lastSearchCollectionCards = []
            } else {
                let allBrandCards = await services.cardData.search(query: trimmed, catalogBrand: selectedBrand)
                cards = allBrandCards
                lastSearchCards = allBrandCards

                if scopeCategory.showsOwnedCollectionCards {
                    let allOwnedCards = await collectionSearchResults(query: trimmed, brand: selectedBrand)
                    collectionCards = allOwnedCards
                    lastSearchCollectionCards = allOwnedCards
                } else {
                    collectionCards = []
                    lastSearchCollectionCards = []
                }
            }
        } else {
            cards = []
            lastSearchCards = []
            collectionCards = []
            lastSearchCollectionCards = []
        }

        lastSearchTaskKey = searchTaskKey
        lastSearchSets = matchingSets
    }

    @MainActor
    private func clearResults() {
        matchingSets = []
        cards = []
        collectionCards = []
        matchingSealed = []
        matchingDecks = []
        matchingBinders = []
        matchingPosts = []
        isSearching = false
        isLoadingAllCards = false
        isLoadingAllCollectionCards = false
        isLoadingAllSealed = false
        showAllCards = false
        showAllCollectionCards = false
        showAllSealed = false
        lastSearchTaskKey = ""
        lastSearchCards = []
        lastSearchCollectionCards = []
        lastSearchSealed = []
        lastSearchSets = []
        priceLineByCardID = [:]
        collectionPriceLineByCardID = [:]
    }

    @MainActor
    private func loadAllCardResults(for query: String) async {
        guard !query.isEmpty, usesAllTabPreviewLimits else { return }
        guard !isLoadingAllCards else { return }

        isLoadingAllCards = true
        defer { isLoadingAllCards = false }

        showAllCards = true
    }

    @MainActor
    private func loadAllCollectionCardResults(for query: String) async {
        guard !query.isEmpty, usesAllTabPreviewLimits else { return }
        guard !isLoadingAllCollectionCards else { return }

        isLoadingAllCollectionCards = true
        defer { isLoadingAllCollectionCards = false }

        showAllCollectionCards = true
    }

    @MainActor
    private func loadAllSealedResults() async {
        guard usesAllTabPreviewLimits else { return }
        guard !isLoadingAllSealed else { return }
        isLoadingAllSealed = true
        defer { isLoadingAllSealed = false }
        showAllSealed = true
    }

    private var searchTaskKey: String {
        "\(trimmed)|\(selectedBrand.rawValue)|\(scopeCategory.rawValue)"
    }

    private func collectionSearchResults(query: String, brand: TCGBrand) async -> [Card] {
        let ownedIDs = Set(
            collectionItems
                .filter { TCGBrand.inferredFromMasterCardId($0.cardID) == brand }
                .map(\.cardID)
        )
        guard !ownedIDs.isEmpty else { return [] }

        let brandCards = await services.cardData.search(query: query, catalogBrand: brand)
        return brandCards.filter { ownedIDs.contains($0.masterCardId) }
    }

    private var sectionDividerColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.10)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .padding(.top, 4)
    }

    private func sectionHeader(
        _ title: String,
        showsViewMore: Bool,
        isLoadingMore: Bool,
        viewMoreAction: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)

            Spacer()

            if showsViewMore {
                Button(action: viewMoreAction) {
                    if isLoadingMore {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("View more")
                            .font(.subheadline.weight(.medium))
                            .bindrAccentForeground(services.theme.accentColor)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private var setsSection: some View {
        Group {
            sectionHeader("Sets")
            VStack(spacing: 0) {
                ForEach(matchingSets) { set in
                    NavigationLink(value: SearchNavRoot.set(set.set, brand: set.brand)) {
                        HStack(spacing: 12) {
                            SetLogoAsyncImage(logoSrc: set.set.logoSrc, height: 36, brand: set.brand)
                                .frame(width: 72, height: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(set.set.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(set.brand.displayTitle + " · " + set.set.setCode.uppercased())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(TapGesture().onEnded(onCommitSearch))
                    if set.id != matchingSets.last?.id {
                        Divider().overlay(sectionDividerColor)
                    }
                }
            }
            .padding(16)
            .glassCardStyle(cornerRadius: 16, interactive: false)
            .padding(.horizontal, 16)
        }
    }

    private var pokemonSection: some View {
        Group {
            sectionHeader("Pokémon")
            VStack(spacing: 0) {
                ForEach(matchingPokemon) { mon in
                    NavigationLink(
                        value: SearchNavRoot.dex(
                            dexId: mon.nationalDexNumber,
                            displayName: mon.displayName,
                            brand: selectedBrand
                        )
                    ) {
                        HStack(spacing: 12) {
                            CachedAsyncImage(
                                url: AppConfiguration.pokemonArtURL(imageFileName: mon.imageUrl)
                            ) { img in
                                img.resizable().scaledToFit()
                            } placeholder: {
                                Color.primary.opacity(0.06)
                            }
                            .frame(width: 44, height: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mon.displayName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text("#\(mon.nationalDexNumber)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(TapGesture().onEnded(onCommitSearch))
                    if mon.id != matchingPokemon.last?.id {
                        Divider().overlay(sectionDividerColor)
                    }
                }
            }
            .padding(16)
            .glassCardStyle(cornerRadius: 16, interactive: false)
            .padding(.horizontal, 16)
        }
    }

    private var sealedSection: some View {
        Group {
            if usesAllTabPreviewLimits {
                sectionHeader(
                    "Sealed",
                    showsViewMore: hasMoreSealedResults,
                    isLoadingMore: isLoadingAllSealed
                ) {
                    Task { await loadAllSealedResults() }
                }
            } else {
                sectionHeader("Sealed")
            }

            VStack(spacing: 0) {
                ForEach(displayedSealed) { product in
                    Button {
                        onCommitSearch()
                        presentSealedProduct(product, matchingSealed, matchingSealed.firstIndex(where: { $0.id == product.id }) ?? 0)
                    } label: {
                        HStack(spacing: 12) {
                            CachedAsyncImage(url: product.imageURL) { image in
                                image.resizable().scaledToFit()
                            } placeholder: {
                                Color.primary.opacity(0.06)
                            }
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(product.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                Text(product.typeDisplayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if product.id != displayedSealed.last?.id {
                        Divider().overlay(sectionDividerColor)
                    }
                }
            }
            .padding(16)
            .glassCardStyle(cornerRadius: 16, interactive: false)
            .padding(.horizontal, 16)
        }
    }

    private var decksSection: some View {
        Group {
            sectionHeader("Decks")
            VStack(spacing: 0) {
                ForEach(matchingDecks, id: \.id) { deck in
                    NavigationLink(value: SearchNavRoot.deck(id: deck.id)) {
                        HStack(spacing: 12) {
                            Image(systemName: "square.stack.3d.up.fill")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .frame(width: 44, height: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(deck.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text("\(deck.totalCardCount) cards · \(deck.deckFormat.displayName)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(TapGesture().onEnded(onCommitSearch))
                    if deck.id != matchingDecks.last?.id {
                        Divider().overlay(sectionDividerColor)
                    }
                }
            }
            .padding(16)
            .glassCardStyle(cornerRadius: 16, interactive: false)
            .padding(.horizontal, 16)
        }
    }

    private var bindersSection: some View {
        Group {
            sectionHeader("Binders")
            VStack(spacing: 0) {
                ForEach(matchingBinders, id: \.id) { binder in
                    NavigationLink(value: SearchNavRoot.binder(id: binder.id)) {
                        HStack(spacing: 12) {
                            Image(systemName: "book.closed.fill")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .frame(width: 44, height: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(binder.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text("\(binder.slotList.count) slots")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(TapGesture().onEnded(onCommitSearch))
                    if binder.id != matchingBinders.last?.id {
                        Divider().overlay(sectionDividerColor)
                    }
                }
            }
            .padding(16)
            .glassCardStyle(cornerRadius: 16, interactive: false)
            .padding(.horizontal, 16)
        }
    }

    private var postsSection: some View {
        Group {
            sectionHeader("Posts")
            VStack(spacing: 0) {
                ForEach(matchingPosts) { post in
                    Button {
                        onCommitSearch()
                        if let contentID = post.content?.id {
                            onOpenPost(contentID)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "text.bubble.fill")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .frame(width: 44, height: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(post.content?.title ?? "Post")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                if let actor = post.actor?.displayName ?? post.actor?.username {
                                    Text(actor)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if post.id != matchingPosts.last?.id {
                        Divider().overlay(sectionDividerColor)
                    }
                }
            }
            .padding(16)
            .glassCardStyle(cornerRadius: 16, interactive: false)
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private var collectionSection: some View {
        collectionSectionHeader
        if !collectionCards.isEmpty {
            cardResultsGrid(
                cards: displayedCollectionCards,
                priceLines: collectionPriceLineByCardID,
                isOwned: true
            )
        }
    }

    @ViewBuilder
    private var cardsSection: some View {
        cardsSectionHeader
        if isSearching && cards.isEmpty && !hasAnyResults {
            ProgressView("Searching…")
                .frame(maxWidth: .infinity)
                .padding()
        } else if cards.isEmpty && scopeCategory == .cards {
            Text("No matching cards.")
                .foregroundStyle(.secondary)
                .font(.subheadline)
                .padding(.horizontal, 16)
        } else if !cards.isEmpty {
            cardResultsGrid(
                cards: displayedCards,
                priceLines: priceLineByCardID,
                isOwned: scopeCategory == .collection
            )
        }
    }

    private func cardResultsGrid(
        cards: [Card],
        priceLines: [String: String],
        isOwned: Bool
    ) -> some View {
        LazyVGrid(columns: cardColumns, spacing: BindrSpacing.cardGrid) {
            ForEach(cards) { card in
                Button {
                    onCommitSearch()
                    SearchHistoryStore.recordViewedCard(card.masterCardId)
                    presentCard(card, cards)
                } label: {
                    CardGridCell(
                        card: card,
                        services: services,
                        colorScheme: colorScheme,
                        accentColor: services.theme.accentColor,
                        isOwned: isOwned,
                        precomputedPriceLine: priceLines[card.masterCardId] ?? ""
                    )
                }
                .buttonStyle(CardCellButtonStyle())
            }
        }
        .padding(.horizontal, BindrSpacing.cardGridScreenInset)
    }

    private var collectionSectionHeader: some View {
        Group {
            if !collectionCards.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Collection")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)

                    Spacer()

                    if hasMoreCollectionResults {
                        Button {
                            Task { await loadAllCollectionCardResults(for: trimmed) }
                        } label: {
                            if isLoadingAllCollectionCards {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("View all")
                                    .font(.subheadline.weight(.medium))
                                    .bindrAccentForeground(services.theme.accentColor)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
            }
        }
    }

    private var cardsSectionHeader: some View {
        Group {
            if scopeCategory.showsCatalogCards && (!cards.isEmpty || scopeCategory == .all || scopeCategory == .cards) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Cards")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)

                    Spacer()

                    if hasMoreCardResults {
                        Button {
                            Task { await loadAllCardResults(for: trimmed) }
                        } label: {
                            if isLoadingAllCards {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("View all")
                                    .font(.subheadline.weight(.medium))
                                    .bindrAccentForeground(services.theme.accentColor)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
            } else if scopeCategory == .collection && (!cards.isEmpty || !isSearching) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Collection")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)

                    Spacer()

                    if hasMoreCardResults {
                        Button {
                            Task { await loadAllCardResults(for: trimmed) }
                        } label: {
                            if isLoadingAllCards {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("View all")
                                    .font(.subheadline.weight(.medium))
                                    .bindrAccentForeground(services.theme.accentColor)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
            }
        }
    }
}

// MARK: - Search detail wrappers

struct SearchDeckDetailView: View {
    let deckID: UUID
    @Query private var decks: [Deck]

    init(deckID: UUID) {
        self.deckID = deckID
        _decks = Query(filter: #Predicate<Deck> { $0.id == deckID })
    }

    var body: some View {
        if let deck = decks.first {
            DeckDetailView(deck: deck)
        } else {
            ContentUnavailableView("Deck not found", systemImage: "square.stack.3d.up.slash")
        }
    }
}

struct SearchBinderDetailView: View {
    let binderID: UUID
    @Query private var binders: [Binder]

    init(binderID: UUID) {
        self.binderID = binderID
        _binders = Query(filter: #Predicate<Binder> { $0.id == binderID })
    }

    var body: some View {
        if let binder = binders.first {
            BinderDetailView(binder: binder)
        } else {
            ContentUnavailableView("Binder not found", systemImage: "book.closed")
        }
    }
}
