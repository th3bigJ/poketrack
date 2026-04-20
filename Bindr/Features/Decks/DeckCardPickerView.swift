import SwiftData
import SwiftUI

// MARK: - Route

private enum DeckPickerBrowseRoute: Hashable {
    case sets
    case set(TCGSet)
    case pokemon
    case dex(dexId: Int, displayName: String)
    case opCharacters
    case opCharacter(name: String)
    case opSubtypes
    case opSubtype(name: String)
}

// MARK: - Source

private enum DeckPickerSource: String, CaseIterable, Identifiable {
    case allCards
    case collection

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allCards:   return "All Cards"
        case .collection: return "Collection"
        }
    }
}

// MARK: - Entry

private struct DeckPickerEntry: Identifiable {
    let id: String
    let card: Card
    let variantKey: String
    let isOwned: Bool
}

// MARK: - Selection

struct DeckPickerSelection {
    let card: Card
    let variantKey: String
    var quantity: Int
}

/// Drives `CardBrowseDetailView`’s `TabView` so the user can page between the current feed, not a single card.
private struct DeckPickerDetailSession: Identifiable {
    let id = UUID()
    let cards: [Card]
    let startIndex: Int
}

private func deckPickerIsBasicEnergy(category: String?, energyType: String?) -> Bool {
    guard category == "Energy" else { return false }
    return energyType?.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare("Basic") == .orderedSame
}

private func deckPickerHasLegalRegulationMark(
    format: DeckFormat,
    category: String?,
    energyType: String?,
    regulationMark: String?
) -> Bool {
    guard let legalMarks = format.legalRegulationMarks else { return true }
    let trimmedMark = regulationMark?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !trimmedMark.isEmpty {
        return legalMarks.contains(trimmedMark)
    }
    return deckPickerIsBasicEnergy(category: category, energyType: energyType)
}

private func deckPickerReleaseDateIsTournamentLegal(_ releaseDate: String?, now: Date = Date()) -> Bool {
    guard let releaseDate, !releaseDate.isEmpty else { return true }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withFullDate]
    guard let release = formatter.date(from: releaseDate) else { return true }
    guard let legalDate = Calendar(identifier: .gregorian).date(byAdding: .day, value: 14, to: release) else {
        return true
    }
    return legalDate <= now
}

// MARK: - Main view

struct DeckCardPickerView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CollectionItem.dateAcquired, order: .reverse) private var collectionItems: [CollectionItem]

    let deck: Deck
    /// When set, picker opens with this card type pre-filtered
    var initialCategoryFilter: BrowseCardTypeFilter? = nil

    @State private var source: DeckPickerSource = .allCards
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
    @State private var basket: [DeckPickerSelection] = []
    @State private var resolvedCardsByID: [String: Card] = [:]
    @State private var browsePath: [DeckPickerBrowseRoute] = []
    @State private var detailSheetSession: DeckPickerDetailSession? = nil

    private static let initialBatchSize = 36
    private static let pageSize = 24

    // MARK: - Derived

    private var ownedCardIDs: Set<String> {
        Set(collectionItems.map(\.cardID))
    }

    /// Colors of the One Piece Leader in this deck (from `elementTypes`). Empty = no leader yet.
    private var opLeaderColors: Set<String> {
        guard deck.tcgBrand == .onePiece else { return [] }
        let leader = deck.cardList.first { ($0.catalogCategory ?? "").lowercased().contains("leader") }
        let colors = leader?.elementTypes?.filter { !$0.isEmpty && $0 != "-" } ?? []
        return Set(colors)
    }

    private var basketCardIDs: Set<String> {
        Set(basket.map { $0.card.masterCardId })
    }

    /// Total copies staged in the basket (sum of line quantities).
    private var basketTotalQuantity: Int {
        basket.reduce(0) { $0 + $1.quantity }
    }

    private var deckCardIDs: Set<String> {
        Set(deck.cardList.map(\.cardID))
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

    private var liveTrimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var debouncedTrimmedQuery: String {
        debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var debouncedQueryIsActive: Bool {
        !debouncedTrimmedQuery.isEmpty
    }

    private var allCardsBase: [Card] {
        debouncedQueryIsActive ? allCardSearchResults : displayedAllCards
    }

    private var collectionEntries: [DeckPickerEntry] {
        let q = debouncedTrimmedQuery.lowercased()
        return collectionItems.compactMap { item in
            guard TCGBrand.inferredFromMasterCardId(item.cardID) == deck.tcgBrand else { return nil }
            guard let card = resolvedCardsByID[item.cardID] else { return nil }
            guard isEligible(card) else { return nil }
            guard passesPickerFilters(card) else { return nil }
            if !q.isEmpty {
                let name = card.cardName.lowercased()
                let num = card.cardNumber.lowercased()
                let setCode = card.setCode.lowercased()
                guard name.contains(q) || num.contains(q) || setCode.contains(q) else { return nil }
            }
            return DeckPickerEntry(
                id: "collection|\(String(describing: item.persistentModelID))",
                card: card,
                variantKey: item.variantKey,
                isOwned: true
            )
        }
    }

    private var visibleEntries: [DeckPickerEntry] {
        switch source {
        case .allCards:
            return allCardsBase.map { card in
                DeckPickerEntry(
                    id: "all|\(card.masterCardId)",
                    card: card,
                    variantKey: card.pricingVariants?.first ?? "normal",
                    isOwned: ownedCardIDs.contains(card.masterCardId)
                )
            }
        case .collection:
            return sortedCollectionEntries(collectionEntries)
        }
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: min(max(gridOptions.columnCount, 1), 4))
    }

    private var preloadTriggerEntryID: String? {
        visibleEntries.suffix(4).first?.id
    }

    private var energyOptions: [String] {
        allBrowseFilterCards.isEmpty ? [] : browseFilterEnergyOptions(allBrowseFilterCards)
    }

    private var rarityOptions: [String] {
        allBrowseFilterCards.isEmpty ? [] : browseFilterRarityOptions(allBrowseFilterCards)
    }

    private var trainerTypeOptions: [String] {
        allBrowseFilterCards.isEmpty ? [] : browseFilterTrainerTypeOptions(allBrowseFilterCards)
    }

    private var searchTaskKey: String {
        "\(source.rawValue)|\(deck.format)|\(debouncedTrimmedQuery)"
    }

    private var visibleItemSignature: String {
        collectionItems
            .filter { TCGBrand.inferredFromMasterCardId($0.cardID) == deck.tcgBrand }
            .map(\.cardID).sorted().joined(separator: "|")
    }

    /// Cards matching the current source, search query, and browse filters — not limited by grid pagination.
    private var totalCardsMatchingFilters: Int {
        switch source {
        case .allCards:
            if debouncedQueryIsActive {
                return allCardSearchResults.count
            }
            return filteredAllCardRefs.count
        case .collection:
            return collectionEntries.count
        }
    }

    // MARK: - Eligibility

    private func isEligible(_ card: Card) -> Bool {
        let fmt = deck.deckFormat

        // Set whitelist (Expanded / GLC)
        if let legalSets = fmt.legalSetKeys {
            guard legalSets.contains(card.setCode) else { return false }
        }

        // Standard only: newly released sets wait until tournament-legal.
        let releaseDate = releaseDateBySetCode[card.setCode]
        if fmt == .pokemonStandard,
           !deckPickerReleaseDateIsTournamentLegal(releaseDate) {
            return false
        }

        // Standard: Basic Energy may omit regulation marks; other cards must carry a legal mark.
        if fmt.legalRegulationMarks != nil {
            guard deckPickerHasLegalRegulationMark(
                format: fmt,
                category: card.category,
                energyType: card.energyType,
                regulationMark: card.regulationMark
            ) else { return false }
        }

        // Ban list
        if fmt.isBanned(cardName: card.cardName) { return false }

        // GLC: no rule-box Pokémon
        if fmt == .pokemonGLC {
            let sub = card.subtype ?? ""
            let ruleBox = ["ex", "V", "GX", "VMAX", "VSTAR"]
            if card.category == "Pokémon" && ruleBox.contains(where: { sub.contains($0) }) {
                return false
            }
        }

        return true
    }

    // MARK: - Body

    var body: some View {
        NavigationStack(path: $browsePath) {
            Group {
                if isLoading && visibleEntries.isEmpty && !isSearching {
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
                                            openDetail(for: entry)
                                        } label: {
                                            DeckPickerCardCell(
                                                entry: entry,
                                                setName: setNameByCode[entry.card.setCode],
                                                gridOptions: gridOptions,
                                                isSelected: basketCardIDs.contains(entry.card.masterCardId),
                                                alreadyInDeck: deckCardIDs.contains(entry.card.masterCardId)
                                            )
                                        }
                                        .buttonStyle(CardCellButtonStyle())
                                        .onAppear {
                                            guard source == .allCards, !debouncedQueryIsActive else { return }
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
                            Spacer(minLength: 0).frame(height: 110)
                        }
                    }
                }
            }
            .navigationTitle("Add Cards")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: DeckPickerBrowseRoute.self) { route in
                switch route {
                case .sets:
                    DeckPickerSetsView(
                        deck: deck,
                        isEligible: isEligible,
                        basketCardIDs: basketCardIDs,
                        onToggle: { card in toggleBasketCard(card) }
                    )
                case .set(let set):
                    DeckPickerCatalogCardsView(
                        path: $browsePath,
                        title: set.name,
                        searchPlaceholder: "Search cards in set",
                        deck: deck,
                        isEligible: isEligible,
                        basketCardIDs: basketCardIDs,
                        loadCards: {
                            let loaded = await services.cardData.loadCards(forSetCode: set.setCode, catalogBrand: deck.tcgBrand)
                            return sortCardsByLocalIdHighestFirst(loaded)
                        },
                        onCardSelected: { card, swipeCards in
                            openDetailForCard(card, swipeContext: swipeCards)
                        }
                    )
                case .pokemon:
                    DeckPickerPokemonBrowseView()
                case .dex(let dexId, let displayName):
                    DeckPickerCatalogCardsView(
                        path: $browsePath,
                        title: displayName,
                        searchPlaceholder: "Search cards for Pokémon",
                        deck: deck,
                        isEligible: isEligible,
                        basketCardIDs: basketCardIDs,
                        loadCards: { await loadPokemonDexCards(dexId: dexId) },
                        onCardSelected: { card, swipeCards in
                            openDetailForCard(card, swipeContext: swipeCards)
                        }
                    )
                case .opCharacters:
                    DeckPickerOPBrowseListView(title: "Characters", searchPlaceholder: "Search characters", routeBuilder: { .opCharacter(name: $0) })
                case .opCharacter(let name):
                    DeckPickerCatalogCardsView(
                        path: $browsePath,
                        title: name,
                        searchPlaceholder: "Search cards",
                        deck: deck,
                        isEligible: isEligible,
                        basketCardIDs: basketCardIDs,
                        loadCards: { await services.cardData.cards(matchingOnePieceCharacterName: name) },
                        onCardSelected: { card, swipeCards in
                            openDetailForCard(card, swipeContext: swipeCards)
                        }
                    )
                case .opSubtypes:
                    DeckPickerOPBrowseListView(title: "Subtypes", searchPlaceholder: "Search subtypes", routeBuilder: { .opSubtype(name: $0) })
                case .opSubtype(let name):
                    DeckPickerCatalogCardsView(
                        path: $browsePath,
                        title: name,
                        searchPlaceholder: "Search cards",
                        deck: deck,
                        isEligible: isEligible,
                        basketCardIDs: basketCardIDs,
                        loadCards: { await services.cardData.cards(matchingOnePieceSubtype: name) },
                        onCardSelected: { card, swipeCards in
                            openDetailForCard(card, swipeContext: swipeCards)
                        }
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
                            brand: deck.tcgBrand,
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
                        Image(systemName: filters.isVisiblyCustomized
                              ? "line.3.horizontal.decrease.circle.fill"
                              : "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .task(id: deck.format) {
                await reloadAllCards(force: true)
            }
            .task(id: visibleItemSignature) {
                await resolveVisibleCards()
            }
            .onChange(of: source) { _, _ in
                if source == .allCards {
                    Task { await restoreAllCardsFeedIfNeeded() }
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
                guard source == .allCards, !debouncedQueryIsActive else { return }
                Task { await rebuildFilteredRefFeed(reset: true) }
            }
            .onAppear {
                filters.sortBy = .newestSet
                if let initial = initialCategoryFilter {
                    if let opCat = initial.opCategoryString {
                        filters.opCardTypes = [opCat]
                    } else {
                        filters.cardTypes = [initial]
                    }
                }
                Task { await restoreAllCardsFeedIfNeeded() }
            }
            .safeAreaInset(edge: .bottom) {
                basketBar
            }
            .sheet(item: $detailSheetSession) { session in
                DeckPickerDetailSheet(
                    cards: session.cards,
                    startIndex: session.startIndex
                ) { card, variantKey, quantity in
                    addToBasket(card: card, variantKey: variantKey, quantity: quantity)
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            Picker("Source", selection: $source) {
                ForEach(DeckPickerSource.allCases) { s in
                    Text(s.title).tag(s)
                }
            }
            .pickerStyle(.segmented)

            browseShortcutRow

            BrowseInlineSearchField(title: searchPlaceholder, text: $query)

            HStack {
                Text("\(deck.deckFormat.displayName) · Ineligible cards filtered out")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(totalCardsMatchingFilters == 1 ? "1 card" : "\(totalCardsMatchingFilters) cards")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(
                        totalCardsMatchingFilters == 1
                            ? "1 card matches the current filters"
                            : "\(totalCardsMatchingFilters) cards match the current filters"
                    )
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
                NavigationLink(value: DeckPickerBrowseRoute.sets) {
                    shortcutChip(title: "Sets")
                }
                if deck.tcgBrand == .pokemon {
                    NavigationLink(value: DeckPickerBrowseRoute.pokemon) {
                        shortcutChip(title: "Pokémon")
                    }
                }
                if deck.tcgBrand == .onePiece {
                    NavigationLink(value: DeckPickerBrowseRoute.opCharacters) {
                        shortcutChip(title: "Characters")
                    }
                    NavigationLink(value: DeckPickerBrowseRoute.opSubtypes) {
                        shortcutChip(title: "Subtypes")
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.horizontal, -16)
    }

    private func shortcutChip(title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color(uiColor: .secondarySystemFill)))
    }

    private var searchPlaceholder: String {
        switch source {
        case .allCards:   return "Browse all \(deck.tcgBrand.displayTitle) cards"
        case .collection: return "Search your collection"
        }
    }

    private var emptyState: some View {
        let trimmed = debouncedTrimmedQuery
        return ContentUnavailableView(
            trimmed.isEmpty ? "No cards found" : "No matching cards",
            systemImage: trimmed.isEmpty ? "rectangle.stack" : "magnifyingglass",
            description: Text(trimmed.isEmpty
                              ? "Download a catalog to browse cards here."
                              : "Try a different search or loosen your filters.")
        )
    }

    // MARK: - Basket bar

    @ViewBuilder
    private var basketBar: some View {
        if !basket.isEmpty {
            HStack(spacing: 16) {
                ZStack {
                    Circle().fill(Color.accentColor).frame(width: 32, height: 32)
                    Text("\(basketTotalQuantity)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("\(basketTotalQuantity) card\(basketTotalQuantity == 1 ? "" : "s") in basket")
                        .font(.subheadline.weight(.semibold))
                    Text("Tap the grid to remove · Confirm to add to deck")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    commitBasket()
                    dismiss()
                } label: {
                    Text("Add to Deck")
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

    // MARK: - Detail sheet

    private func openDetail(for entry: DeckPickerEntry) {
        let cards = visibleEntries.map(\.card)
        guard let idx = cards.firstIndex(where: { $0.masterCardId == entry.card.masterCardId }) else {
            detailSheetSession = DeckPickerDetailSession(cards: [entry.card], startIndex: 0)
            return
        }
        detailSheetSession = DeckPickerDetailSession(cards: cards, startIndex: idx)
    }

    /// `swipeContext` is the ordered list used for horizontal paging (e.g. filtered grid cards).
    private func openDetailForCard(_ card: Card, swipeContext: [Card]) {
        guard let idx = swipeContext.firstIndex(where: { $0.masterCardId == card.masterCardId }) else {
            detailSheetSession = DeckPickerDetailSession(cards: [card], startIndex: 0)
            return
        }
        detailSheetSession = DeckPickerDetailSession(cards: swipeContext, startIndex: idx)
    }

    /// Subtype text for deck summaries (stages, V, etc.). Prefer CSV `subtype`; fall back to `subtypes`; then `stage` when the catalog omits subtype text.
    private static func catalogSubtypeString(from card: Card) -> String? {
        if let s = card.subtype?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            return s
        }
        let cleaned = card.subtypes?.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } ?? []
        if !cleaned.isEmpty {
            return cleaned.joined(separator: ", ")
        }
        if card.category == "Pokémon",
           let st = card.stage?.trimmingCharacters(in: .whitespacesAndNewlines), !st.isEmpty {
            return st
        }
        return nil
    }

    private static func catalogStageString(from card: Card) -> String? {
        guard card.category == "Pokémon",
              let stage = card.stage?.trimmingCharacters(in: .whitespacesAndNewlines),
              !stage.isEmpty else {
            return nil
        }
        return stage
    }

    private func addCardToDeck(card: Card, variantKey: String, quantity: Int) {
        let fmt = deck.deckFormat
        let existingMap = Dictionary(uniqueKeysWithValues: deck.cardList.map { ($0.cardID, $0) })
        let aceSpecInDeck = deck.cardList.filter { $0.isAceSpec }.reduce(0) { $0 + $1.quantity }

        let cardIsBasicEnergy  = deck.tcgBrand == .pokemon && card.category == "Energy" && card.energyType == "Basic"
        let cardIsAceSpec      = card.rarity?.lowercased().contains("ace spec") == true
        let cardIsRadiant      = card.cardName.hasPrefix("Radiant ") || card.subtype?.contains("Radiant") == true
        let cardIsBasicPokemon = card.category == "Pokémon" && (card.subtype?.contains("Basic") == true || card.stage == "Basic")
        let cardIsRuleBox: Bool = {
            guard card.category == "Pokémon" else { return false }
            let sub = card.subtype ?? ""
            return ["ex", "V", "GX", "VMAX", "VSTAR"].contains { sub.contains($0) }
        }()

        let effectiveMax: Int = {
            if cardIsBasicEnergy { return 99 }
            if cardIsAceSpec     { return max(0, 1 - aceSpecInDeck) }
            if cardIsRadiant     { return 1 }
            return fmt.maxCopiesPerCard
        }()

        if let existing = existingMap[card.masterCardId] {
            existing.quantity = min(existing.quantity + quantity, effectiveMax)
            if existing.catalogCategory == nil, let cat = card.category?.trimmingCharacters(in: .whitespacesAndNewlines), !cat.isEmpty {
                existing.catalogCategory = cat
            }
            if existing.catalogSubtype == nil, let sub = DeckCardPickerView.catalogSubtypeString(from: card) {
                existing.catalogSubtype = sub
            }
            if existing.catalogStage == nil, let stage = DeckCardPickerView.catalogStageString(from: card) {
                existing.catalogStage = stage
            }
            if existing.opCost == nil { existing.opCost = card.opCost }
            if existing.opPower == nil { existing.opPower = card.hp }
            if existing.opCounter == nil { existing.opCounter = card.opCounter }
            if existing.imageLowSrc.isEmpty, !card.imageLowSrc.isEmpty { existing.imageLowSrc = card.imageLowSrc }
        } else if effectiveMax > 0 {
            let deckCard = DeckCard(
                cardID: card.masterCardId,
                variantKey: variantKey,
                cardName: card.cardName,
                quantity: min(quantity, effectiveMax),
                isBasicEnergy: cardIsBasicEnergy,
                isAceSpec: cardIsAceSpec,
                isRadiant: cardIsRadiant,
                isBasicPokemon: cardIsBasicPokemon,
                isRuleBox: cardIsRuleBox,
                setKey: card.setCode,
                regulationMark: card.regulationMark,
                elementTypes: card.elementTypes,
                trainerType: card.trainerType,
                isEnergy: card.category == "Energy",
                imageLowSrc: card.imageLowSrc,
                catalogCategory: card.category,
                catalogSubtype: Self.catalogSubtypeString(from: card),
                catalogStage: Self.catalogStageString(from: card),
                opCost: card.opCost,
                opPower: card.hp,
                opCounter: card.opCounter
            )
            deckCard.deck = deck
            modelContext.insert(deckCard)
        }
    }

    // MARK: - Basket operations

    /// Stages copies from the card detail sheet; deck is updated only when the user taps **Add to Deck** on the bar.
    private func addToBasket(card: Card, variantKey: String, quantity: Int) {
        if let idx = basket.firstIndex(where: { $0.card.masterCardId == card.masterCardId }) {
            let mergedQty = basket[idx].quantity + quantity
            basket[idx] = DeckPickerSelection(card: card, variantKey: variantKey, quantity: mergedQty)
        } else {
            basket.append(DeckPickerSelection(card: card, variantKey: variantKey, quantity: quantity))
        }
        HapticManager.impact(.light)
        detailSheetSession = nil
    }

    private func toggleBasket(entry: DeckPickerEntry) {
        toggleBasketCard(entry.card, variantKey: entry.variantKey)
    }

    private func toggleBasketCard(_ card: Card, variantKey: String? = nil) {
        if let idx = basket.firstIndex(where: { $0.card.masterCardId == card.masterCardId }) {
            basket.remove(at: idx)
        } else {
            basket.append(DeckPickerSelection(
                card: card,
                variantKey: variantKey ?? card.pricingVariants?.first ?? "normal",
                quantity: 1
            ))
        }
    }

    private func commitBasket() {
        for selection in basket {
            addCardToDeck(card: selection.card, variantKey: selection.variantKey, quantity: selection.quantity)
        }
        HapticManager.impact(.light)
    }

    // MARK: - Data loading

    private func reloadAllCards(force: Bool = false) async {
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
            let sets = try CatalogStore.shared.fetchAllSets(for: deck.tcgBrand)
            let refs = try CatalogStore.shared.fetchAllCardRefs(for: deck.tcgBrand)
            var filterCards = try CatalogStore.shared.fetchAllBrowseFilterCards(for: deck.tcgBrand)

            // Pre-filter ineligible cards at the BrowseFilterCard level using setKey + regulationMark
            let fmt = deck.deckFormat
            filterCards = filterCards.filter { card in
                if let legalSets = fmt.legalSetKeys, !legalSets.contains(card.setCode) { return false }
                let releaseDate = sets.first(where: { $0.setCode == card.setCode })?.releaseDate
                if fmt == .pokemonStandard,
                   !deckPickerReleaseDateIsTournamentLegal(releaseDate) {
                    return false
                }
                if fmt.legalRegulationMarks != nil,
                   !deckPickerHasLegalRegulationMark(
                    format: fmt,
                    category: card.category,
                    energyType: card.energyType,
                    regulationMark: card.regulationMark
                   ) {
                    return false
                }
                if fmt.isBanned(cardName: card.cardName) { return false }
                if fmt == .pokemonGLC {
                    let sub = card.subtype ?? ""
                    let ruleBox = ["ex", "V", "GX", "VMAX", "VSTAR"]
                    if (card.category ?? "").contains("Pokémon") && ruleBox.contains(where: { sub.contains($0) }) { return false }
                }
                return true
            }

            let eligibleIDs = Set(filterCards.map(\.masterCardId))
            let filteredRefs = refs.filter { eligibleIDs.contains($0.masterCardId) }

            await MainActor.run {
                catalogSets = sets
                allCardRefs = filteredRefs
                allBrowseFilterCards = filterCards
                filteredAllCardRefs = filteredRefs
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
        let results = await services.cardData.search(query: trimmed, catalogBrand: deck.tcgBrand)
        let eligible = results.filter { isEligible($0) }
        await MainActor.run {
            allCardSearchResults = eligible
            isSearching = false
            isLoading = false
        }
    }

    private func loadNextAllCardsPage(reset: Bool = false) async {
        guard !debouncedQueryIsActive else { return }
        guard !isLoadingMore else { return }
        guard reset || nextRefIndex < filteredAllCardRefs.count else {
            isLoading = false
            return
        }
        isLoadingMore = true
        let start = reset ? 0 : nextRefIndex
        let end = min(start + (reset ? Self.initialBatchSize : Self.pageSize), filteredAllCardRefs.count)
        let batch = Array(filteredAllCardRefs[start..<end])
        let cards = await loadCardsInOrder(batch)
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
        guard !debouncedQueryIsActive else { return }
        guard displayedAllCards.isEmpty else { isLoading = false; return }
        guard !filteredAllCardRefs.isEmpty else {
            await reloadAllCards()
            return
        }
        await loadNextAllCardsPage(reset: true)
    }

    private func resolveVisibleCards() async {
        var next = resolvedCardsByID
        let ids = Set(collectionItems
            .filter { TCGBrand.inferredFromMasterCardId($0.cardID) == deck.tcgBrand }
            .map(\.cardID))
        for id in ids where next[id] == nil {
            if let card = await services.cardData.loadCard(masterCardId: id) {
                next[id] = card
            }
        }
        await MainActor.run { resolvedCardsByID = next }
    }

    private func loadCardsInOrder(_ refs: [CardRef]) async -> [Card] {
        guard !refs.isEmpty else { return [] }
        var bySet: [String: Set<String>] = [:]
        for ref in refs { bySet[ref.setCode, default: []].insert(ref.masterCardId) }
        var cardByKey: [String: Card] = [:]
        for (setCode, ids) in bySet {
            let loaded = await services.cardData.loadCards(forSetCode: setCode, catalogBrand: deck.tcgBrand)
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
            let remainder = filtered.lazy.filter { !covered.contains($0.masterCardId) }.map(\.ref)
            return ordered + remainder
        case .newestSet:
            return sortBrowseFilterCardsByDate(filtered).map(\.ref)
        case .cardName:
            return filtered.sorted { $0.cardName.localizedCaseInsensitiveCompare($1.cardName) == .orderedAscending }.map(\.ref)
        case .cardNumber:
            return filtered.sorted {
                if $0.setCode != $1.setCode { return compareByDate(lhs: $0.setCode, rhs: $1.setCode) }
                return $0.cardNumber.localizedStandardCompare($1.cardNumber) == .orderedAscending
            }.map(\.ref)
        case .price:
            let refs = filtered.map(\.ref)
            let loaded = await loadCardsInOrder(refs)
            var priced: [(Card, Double?)] = []
            for card in loaded {
                let entry = await services.pricing.pricing(for: card)
                priced.append((card, pickerMarketPriceUSD(for: entry)))
            }
            return priced.sorted { l, r in
                switch (l.1, r.1) {
                case let (lp?, rp?): if lp != rp { return lp > rp }
                case (.some, nil): return true
                case (nil, .some): return false
                case (nil, nil): break
                }
                return l.0.cardName.localizedCaseInsensitiveCompare(r.0.cardName) == .orderedAscending
            }.map { CardRef(masterCardId: $0.0.masterCardId, setCode: $0.0.setCode) }
        }
    }

    private func filterBrowseFilterCards(_ cards: [BrowseFilterCard]) -> [BrowseFilterCard] {
        let leaderColors = opLeaderColors
        return cards.filter { card in
            if deck.tcgBrand == .pokemon,
               !filters.cardTypes.isEmpty,
               !filters.cardTypes.contains(resolvedCardType(for: card)) { return false }
            if deck.tcgBrand == .onePiece, !filters.opCardTypes.isEmpty {
                let cardTypes = Set((card.category ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
                if cardTypes.isDisjoint(with: filters.opCardTypes) { return false }
            }
            if deck.tcgBrand == .onePiece, !leaderColors.isEmpty {
                let isLeader = (card.category ?? "").lowercased().contains("leader")
                if !isLeader {
                    let cardColors = Set(card.elementTypes?.filter { !$0.isEmpty && $0 != "-" } ?? [])
                    if cardColors.isDisjoint(with: leaderColors) { return false }
                }
            }
            if filters.rarePlusOnly && isCommonOrUncommon(card.rarity) { return false }
            if filters.hideOwned && ownedCardIDs.contains(card.masterCardId) { return false }
            if !filters.energyTypes.isEmpty {
                if Set(resolvedEnergyTypes(for: card)).isDisjoint(with: filters.energyTypes) { return false }
            }
            if !filters.rarities.isEmpty {
                let r = card.rarity?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if r.isEmpty || !filters.rarities.contains(r) { return false }
            }
            if !filters.trainerTypes.isEmpty {
                let t = card.trainerType?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if t.isEmpty || !filters.trainerTypes.contains(t) { return false }
            }
            return true
        }
    }

    /// Same rules as ``filterBrowseFilterCards`` but for resolved ``Card`` models (collection tab).
    private func passesPickerFilters(_ card: Card) -> Bool {
        if deck.tcgBrand == .pokemon,
           !filters.cardTypes.isEmpty,
           !filters.cardTypes.contains(resolvedBrowseCardTypeForPicker(card)) {
            return false
        }
        if deck.tcgBrand == .onePiece, !filters.opCardTypes.isEmpty {
            let cardTypes = Set((card.category ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
            if cardTypes.isDisjoint(with: filters.opCardTypes) { return false }
        }
        let leaderColors = opLeaderColors
        if deck.tcgBrand == .onePiece, !leaderColors.isEmpty {
            let isLeader = (card.category ?? "").lowercased().contains("leader")
            if !isLeader {
                let cardColors = Set(card.elementTypes?.filter { !$0.isEmpty && $0 != "-" } ?? [])
                if cardColors.isDisjoint(with: leaderColors) { return false }
            }
        }
        if filters.rarePlusOnly && isCommonOrUncommon(card.rarity) { return false }
        if filters.hideOwned && ownedCardIDs.contains(card.masterCardId) { return false }
        if !filters.energyTypes.isEmpty {
            if Set(resolvedEnergyTypesForPickerCard(card)).isDisjoint(with: filters.energyTypes) { return false }
        }
        if !filters.rarities.isEmpty {
            let r = card.rarity?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if r.isEmpty || !filters.rarities.contains(r) { return false }
        }
        if !filters.trainerTypes.isEmpty {
            let t = card.trainerType?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if t.isEmpty || !filters.trainerTypes.contains(t) { return false }
        }
        return true
    }

    private func resolvedBrowseCardTypeForPicker(_ card: Card) -> BrowseCardTypeFilter {
        let category = card.category?.lowercased() ?? ""
        if category.contains("trainer") || card.trainerType != nil {
            return .trainer
        }
        if category.contains("energy") || card.energyType != nil {
            return .energy
        }
        if deck.tcgBrand == .onePiece, category.contains("event") {
            return .trainer
        }
        return .pokemon
    }

    private func resolvedEnergyTypesForPickerCard(_ card: Card) -> [String] {
        var values = Set<String>()
        if let e = card.energyType?.trimmingCharacters(in: .whitespacesAndNewlines), !e.isEmpty {
            values.insert(e)
        }
        for t in card.elementTypes ?? [] {
            let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { values.insert(trimmed) }
        }
        return Array(values)
    }

    private func resolvedCardType(for card: BrowseFilterCard) -> BrowseCardTypeFilter {
        let category = card.category?.lowercased() ?? ""
        if category.contains("trainer") || card.trainerType != nil { return .trainer }
        if category.contains("energy") || card.energyType != nil { return .energy }
        return .pokemon
    }

    private func resolvedEnergyTypes(for card: BrowseFilterCard) -> [String] {
        var values = Set<String>()
        if let e = card.energyType?.trimmingCharacters(in: .whitespacesAndNewlines), !e.isEmpty { values.insert(e) }
        for t in card.elementTypes ?? [] {
            let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { values.insert(trimmed) }
        }
        return Array(values)
    }

    private func sortBrowseFilterCardsByDate(_ cards: [BrowseFilterCard]) -> [BrowseFilterCard] {
        cards.sorted { lhs, rhs in
            let l = releaseDateBySetCode[lhs.setCode] ?? ""
            let r = releaseDateBySetCode[rhs.setCode] ?? ""
            if l != r { return l > r }
            if lhs.setCode != rhs.setCode { return lhs.setCode.localizedStandardCompare(rhs.setCode) == .orderedAscending }
            return lhs.cardNumber.localizedStandardCompare(rhs.cardNumber) == .orderedAscending
        }
    }

    private func compareByDate(lhs: String, rhs: String) -> Bool {
        let l = releaseDateBySetCode[lhs] ?? ""
        let r = releaseDateBySetCode[rhs] ?? ""
        if l != r { return l > r }
        return lhs.localizedStandardCompare(rhs) == .orderedAscending
    }

    private func isCommonOrUncommon(_ rarity: String?) -> Bool {
        let n = rarity?.lowercased() ?? ""
        return n.contains("common") || n.contains("uncommon")
    }

    private func pickerMarketPriceUSD(for entry: CardPricingEntry?) -> Double? {
        guard let entry else { return nil }
        if let scrydex = entry.scrydex, !scrydex.isEmpty {
            return scrydex.values.compactMap { $0.marketEstimateUSD() }.max()
        }
        return entry.tcgplayerMarketEstimateUSD()
    }

    private func sortedCollectionEntries(_ entries: [DeckPickerEntry]) -> [DeckPickerEntry] {
        switch filters.sortBy {
        case .cardName:
            return entries.sorted { $0.card.cardName.localizedCaseInsensitiveCompare($1.card.cardName) == .orderedAscending }
        case .newestSet:
            return entries.sorted {
                let l = releaseDateBySetCode[$0.card.setCode] ?? ""
                let r = releaseDateBySetCode[$1.card.setCode] ?? ""
                return l > r
            }
        case .cardNumber:
            return entries.sorted {
                if $0.card.setCode != $1.card.setCode {
                    return compareByDate(lhs: $0.card.setCode, rhs: $1.card.setCode)
                }
                return $0.card.cardNumber.localizedStandardCompare($1.card.cardNumber) == .orderedAscending
            }
        case .random, .price, .acquiredDateNewest:
            return entries
        }
    }

    private func loadPokemonDexCards(dexId: Int) async -> [Card] {
        do {
            try CatalogStore.shared.open()
            let cards = try CatalogStore.shared.fetchAllCards(for: .pokemon)
            let matches = cards.filter { $0.dexIds?.contains(dexId) == true && isEligible($0) }
            return matches.sorted {
                let l = releaseDateBySetCode[$0.setCode] ?? ""
                let r = releaseDateBySetCode[$1.setCode] ?? ""
                return l > r
            }
        } catch { return [] }
    }

    private func sortCardsByLocalIdHighestFirst(_ cards: [Card]) -> [Card] {
        cards.filter { isEligible($0) }.sorted {
            let lv = localIdNumericSortValue($0.localId)
            let rv = localIdNumericSortValue($1.localId)
            if lv != rv { return lv > rv }
            return $0.masterCardId > $1.masterCardId
        }
    }

    private func localIdNumericSortValue(_ raw: String?) -> Int {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return Int.min }
        if let v = Int(raw) { return v }
        let digits = raw.prefix { $0.isNumber }
        if let v = Int(String(digits)), !digits.isEmpty { return v }
        return Int.min
    }
}

// MARK: - Card cell

private struct DeckPickerCardCell: View {
    let entry: DeckPickerEntry
    let setName: String?
    let gridOptions: BrowseGridOptions
    let isSelected: Bool
    let alreadyInDeck: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            CardGridCell(
                card: entry.card,
                gridOptions: gridOptions,
                setName: setName,
                footnote: nil
            )

            Image(systemName: isSelected
                  ? "checkmark.circle.fill"
                  : (entry.isOwned ? "checkmark.circle.fill" : "circle"))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isSelected ? Color.accentColor : (entry.isOwned ? .green : .white))
                .background(Circle().fill(isSelected || entry.isOwned ? .white : Color.black.opacity(0.18)))
                .padding(6)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color(uiColor: .secondarySystemBackground)))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    isSelected ? Color.accentColor : (alreadyInDeck ? Color.orange.opacity(0.5) : Color.primary.opacity(0.06)),
                    lineWidth: isSelected ? 2 : (alreadyInDeck ? 1.5 : 1)
                )
        }
    }
}

// MARK: - Sets browse

private struct DeckPickerSetsView: View {
    let deck: Deck
    let isEligible: (Card) -> Bool
    let basketCardIDs: Set<String>
    let onToggle: (Card) -> Void

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
        let grouped = Dictionary(grouping: filteredSets, by: seriesTitle(for:))
        let sorted = grouped.map { (title: $0.key, sets: sortNewestFirst($0.value)) }
        switch deck.tcgBrand {
        case .onePiece:
            return sorted.sorted { lhs, rhs in
                let li = opSeriesOrder(lhs.title), ri = opSeriesOrder(rhs.title)
                if li != ri { return li < ri }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        default:
            return sorted.sorted { lhs, rhs in
                let l = lhs.sets.compactMap(\.releaseDate).min() ?? ""
                let r = rhs.sets.compactMap(\.releaseDate).min() ?? ""
                if l != r { return l > r }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        }
    }

    private func seriesTitle(for set: TCGSet) -> String {
        switch deck.tcgBrand {
        case .onePiece:
            let lower = (set.seriesName ?? "").lowercased()
            if lower.contains("booster pack")    { return "Booster Pack" }
            if lower.contains("extra booster")   { return "Extra Boosters" }
            if lower.contains("starter")         { return "Starter deck" }
            if lower.contains("premium booster") { return "Premium Booster" }
            if lower.contains("promo")           { return "Promo" }
            let raw = set.seriesName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return raw.isEmpty ? "Other" : raw
        default:
            let raw = set.seriesName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return raw.isEmpty ? "Other" : raw
        }
    }

    private func sortNewestFirst(_ sets: [TCGSet]) -> [TCGSet] {
        sets.sorted {
            let l = $0.releaseDate ?? "", r = $1.releaseDate ?? ""
            if l != r { return l > r }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func opSeriesOrder(_ title: String) -> Int {
        switch title {
        case "Booster Pack": return 0
        case "Extra Boosters": return 1
        case "Starter deck": return 2
        case "Premium Booster": return 3
        case "Promo": return 4
        default: return 5
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                BrowseInlineSearchField(title: "Search sets", text: $query)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                if filteredSets.isEmpty {
                    ContentUnavailableView("No matching sets", systemImage: "rectangle.stack")
                        .padding(.top, 24)
                } else {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(groupedSets, id: \.title) { group in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(group.title)
                                    .font(.title2.weight(.bold))
                                    .foregroundStyle(.primary)
                                Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 10)

                            LazyVStack(spacing: 0) {
                                ForEach(group.sets) { set in
                                    NavigationLink(value: DeckPickerBrowseRoute.set(set)) {
                                        HStack(spacing: 14) {
                                            SetLogoAsyncImage(logoSrc: set.logoSrc, height: 44, brand: deck.tcgBrand)
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
        .navigationTitle("Browse Sets")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: deck.format) {
            do {
                try CatalogStore.shared.open()
                var allSets = try CatalogStore.shared.fetchAllSets(for: deck.tcgBrand)
                // Filter sets to only those with at least one eligible card per the format
                if let legalSets = deck.deckFormat.legalSetKeys {
                    allSets = allSets.filter { legalSets.contains($0.setCode) }
                }
                if deck.deckFormat == .pokemonStandard {
                    allSets = allSets.filter { deckPickerReleaseDateIsTournamentLegal($0.releaseDate) }
                }
                sets = allSets
            } catch {
                sets = []
            }
        }
    }
}

// MARK: - One Piece character / subtype browse

private struct DeckPickerOPBrowseListView: View {
    @Environment(AppServices.self) private var services

    let title: String
    let searchPlaceholder: String
    let routeBuilder: (String) -> DeckPickerBrowseRoute

    @State private var rows: [String] = []
    @State private var isLoading = true
    @State private var query = ""

    private var filteredRows: [String] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return rows }
        return rows.filter { $0.lowercased().contains(q) }
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if rows.isEmpty {
                ContentUnavailableView(title, systemImage: "list.bullet",
                    description: Text("Sync the ONE PIECE catalog to see results."))
            } else {
                List {
                    Section {
                        BrowseInlineSearchField(title: searchPlaceholder, text: $query)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(Color.clear)
                    }
                    if filteredRows.isEmpty {
                        ContentUnavailableView("No matches", systemImage: "magnifyingglass")
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(filteredRows, id: \.self) { row in
                            NavigationLink(value: routeBuilder(row)) {
                                Text(row).padding(.vertical, 4)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            isLoading = true
            defer { isLoading = false }
            if services.cardData.onePieceCharacterNames.isEmpty {
                await services.cardData.loadOnePieceBrowseMetadata()
            }
            rows = title == "Characters"
                ? services.cardData.onePieceCharacterNames
                : services.cardData.onePieceCharacterSubtypes
        }
    }
}

// MARK: - Pokémon browse

private struct DeckPickerPokemonBrowseView: View {
    @Environment(AppServices.self) private var services
    @State private var query = ""

    private var rows: [NationalDexPokemon] { services.cardData.nationalDexPokemonSorted() }

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
                        NavigationLink(value: DeckPickerBrowseRoute.dex(dexId: item.nationalDexNumber, displayName: item.displayName)) {
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

// MARK: - Catalog cards view (set / dex)

private struct DeckPickerCatalogCardsView: View {
    @Environment(AppServices.self) private var services
    @Query private var collectionItems: [CollectionItem]
    @Binding var path: [DeckPickerBrowseRoute]

    let title: String
    let searchPlaceholder: String
    let deck: Deck
    let isEligible: (Card) -> Bool
    let basketCardIDs: Set<String>
    let loadCards: () async -> [Card]
    /// Opens the deck detail sheet; second argument is the list to swipe through (typically the filtered grid).
    let onCardSelected: (Card, [Card]) -> Void

    @State private var cards: [Card] = []
    @State private var isLoading = true
    @State private var query = ""

    private var ownedCardIDs: Set<String> { Set(collectionItems.map(\.cardID)) }
    private var deckCardIDs: Set<String> { Set(deck.cardList.map(\.cardID)) }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: min(max(services.browseGridOptions.options.columnCount, 1), 4))
    }

    private var setNameByCode: [String: String] {
        var result: [String: String] = [:]
        for set in services.cardData.sets where result[set.setCode] == nil {
            result[set.setCode] = set.name
        }
        return result
    }

    private var filteredCards: [Card] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return cards }
        return cards.filter {
            $0.cardName.lowercased().contains(trimmed)
            || $0.cardNumber.lowercased().contains(trimmed)
        }
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
                                Button { onCardSelected(card, filteredCards) } label: {
                                    DeckPickerCardCell(
                                        entry: DeckPickerEntry(
                                            id: "cat|\(card.masterCardId)",
                                            card: card,
                                            variantKey: card.pricingVariants?.first ?? "normal",
                                            isOwned: ownedCardIDs.contains(card.masterCardId)
                                        ),
                                        setName: setNameByCode[card.setCode],
                                        gridOptions: services.browseGridOptions.options,
                                        isSelected: basketCardIDs.contains(card.masterCardId),
                                        alreadyInDeck: deckCardIDs.contains(card.masterCardId)
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
                Button { path.removeAll() } label: {
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

// MARK: - Card detail sheet with add-to-deck button

private struct DeckPickerDetailSheet: View {
    let cards: [Card]
    let startIndex: Int
    let onAdd: (Card, String, Int) -> Void

    var body: some View {
        CardBrowseDetailView(cards: cards, startIndex: startIndex, addToDeckAction: onAdd)
    }
}
