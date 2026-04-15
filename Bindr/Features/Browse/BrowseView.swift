import SwiftData
import SwiftUI

// MARK: - Shared card grid cell

struct CardGridCell: View {
    @Environment(AppServices.self) private var services

    let card: Card
    var gridOptions = BrowseGridOptions()
    var setName: String? = nil
    /// Optional line under the name (e.g. wishlist variant key).
    var footnote: String? = nil

    /// Target size for memory-efficient downsampling (~2x display size for retina)
    private static let thumbnailSize = CGSize(width: 220, height: 308)

    var body: some View {
        VStack(spacing: 4) {
            CachedAsyncImage(
                url: AppConfiguration.imageURL(relativePath: card.imageLowSrc),
                targetSize: Self.thumbnailSize
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
            if let footnote, !footnote.isEmpty {
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

/// Subtle spring scale on press for all card grid cells — gives a premium tactile feel.
struct CardCellButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

// MARK: - Browse feed

struct BrowseView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.presentCard) private var presentCard
    @Environment(\.rootFloatingChromeInset) private var rootFloatingChromeInset
    @EnvironmentObject private var chromeScroll: ChromeScrollCoordinator
    @Query private var collectionItems: [CollectionItem]

    @Binding var filters: BrowseCardGridFilters
    @Binding var gridOptions: BrowseGridOptions
    @Binding var isFilterMenuPresented: Bool
    @Binding var filterResultCount: Int
    @Binding var filterEnergyOptions: [String]
    @Binding var filterRarityOptions: [String]
    @Binding var filterTrainerTypeOptions: [String]
    var onBrowseSets: () -> Void
    var onBrowsePokemon: () -> Void
    var onBrowseOnePieceCharacters: () -> Void
    var onBrowseOnePieceSubtypes: () -> Void

    @State private var shuffledRefs: [CardRef] = []
    @State private var nextRefIndex = 0
    @State private var displayedCards: [Card] = []
    @State private var allBrowseFilterCards: [BrowseFilterCard] = []
    @State private var catalogOrderedRefs: [CardRef] = []
    @State private var catalogDisplayedCards: [Card] = []
    @State private var catalogNextIndex = 0
    @State private var isLoadingInitial = true
    @State private var isLoadingMore = false
    @State private var isPreparingFilterCatalog = false
    /// Prevents concurrent full-filter-index loads (background warm vs active filter feed).
    @State private var isLoadingFullCatalog = false
    @State private var gridResetToken = UUID()

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

    private var ownedCardIDs: Set<String> {
        let enabled = services.brandSettings.enabledBrands
        return Set(collectionItems.compactMap { item in
            let brand = TCGBrand.inferredFromMasterCardId(item.cardID)
            return enabled.contains(brand) ? item.cardID : nil
        })
    }

    private var setNameByCode: [String: String] {
        firstValueMap(services.cardData.sets, key: \.setCode, value: \.name)
    }

    private var usesCatalogFeed: Bool {
        filters.hasActiveFieldFilters || filters.hasActiveSort
    }

    private var visibleCards: [Card] {
        usesCatalogFeed ? catalogDisplayedCards : displayedCards
    }

    /// Until `loadAllCards()` runs (filtered / sorted catalog feed), derive options from what is already loaded
    /// so we never block launch on a full-catalog query; options grow as the user scrolls the shuffle feed.
    private var energyOptions: [String] {
        if allBrowseFilterCards.isEmpty {
            return Array(Set(displayedCards.flatMap(resolvedEnergyTypes(for:)))).sorted()
        }
        return Array(Set(allBrowseFilterCards.flatMap(resolvedEnergyTypes(for:)))).sorted()
    }

    private var rarityOptions: [String] {
        if allBrowseFilterCards.isEmpty {
            return Array(Set(displayedCards.compactMap(\.rarity).map(trimmedValue(_:)))).sorted()
        }
        return Array(Set(allBrowseFilterCards.compactMap(\.rarity).map(trimmedValue(_:)))).sorted()
    }

    private var trainerTypeOptions: [String] {
        Array(Set(allBrowseFilterCards.compactMap(\.trainerType).map(trimmedValue(_:)).filter { !$0.isEmpty })).sorted()
    }

    var body: some View {
        Group {
            if isLoadingInitial {
                ProgressView("Loading cards…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if displayedCards.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No cards in the catalog yet.")
                        .foregroundStyle(.secondary)
                    if let err = services.cardData.lastError {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }
                    Text("Pull to refresh after your catalog syncs, or check BINDR_R2_BASE_URL in Info.plist.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding()
            } else {
                scrollTrackedCardGrid
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task(id: services.brandSettings.selectedCatalogBrand) {
            // Launch pipeline already ran `loadSets` + warmed search; full `reloadAfterBrandChange()` would repeat that and freeze the UI.
            if services.consumeLightBrowseTabEntryIfNeeded() {
                services.cardData.resetBrowseFeedSessionOnly()
            } else {
                await services.cardData.reloadAfterBrandChange()
            }
            await Task.yield()
            await Task.yield()
            await bootstrapFeed(forceReshuffle: true)
            if usesCatalogFeed {
                await ensureAllBrowseFilterCardsLoaded(showsPreparingBanner: true)
                await rebuildCatalogFeedIfNeeded()
            } else {
                Task {
                    await ensureAllBrowseFilterCardsLoaded(showsPreparingBanner: false)
                }
            }
        }
        .refreshable {
            await bootstrapFeed(forceReshuffle: true)
            if usesCatalogFeed {
                await ensureAllBrowseFilterCardsLoaded(showsPreparingBanner: true)
                await rebuildCatalogFeedIfNeeded()
            } else {
                Task {
                    await ensureAllBrowseFilterCardsLoaded(showsPreparingBanner: false)
                }
            }
        }
        .task(id: filters) {
            if usesCatalogFeed {
                await ensureAllBrowseFilterCardsLoaded(showsPreparingBanner: true)
                await rebuildCatalogFeedIfNeeded()
            } else {
                catalogOrderedRefs = []
                catalogDisplayedCards = []
                catalogNextIndex = 0
                syncFilterMenuState()
            }
        }
    }

    private var browseCardGrid: some View {
        let cards = visibleCards
        let rows = chunkedBrowseCards(cards, columnCount: safeColumnCount)
        return VStack(spacing: 0) {
            LazyVStack(spacing: 12) {
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, rowCards in
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(rowCards, id: \.id) { card in
                            Button { presentCard(card, cards) } label: {
                                BrowseGridCardCell(
                                    card: card,
                                    gridOptions: gridOptions,
                                    setName: setNameByCode[card.setCode]
                                )
                            }
                            .buttonStyle(CardCellButtonStyle())
                            .frame(maxWidth: .infinity, alignment: .top)
                        }
                        ForEach(0..<max(0, safeColumnCount - rowCards.count), id: \.self) { _ in
                            Color.clear
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .onAppear {
                        guard rowIndex >= max(0, rows.count - 2) else { return }
                        Task { await loadNextPageIfNeeded() }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 16)
    }

    private var browseShortcutRow: some View {
        BrowseShortcutButtonsRow(
            onBrowseSets: onBrowseSets,
            onBrowsePokemon: onBrowsePokemon,
            onBrowseOnePieceCharacters: onBrowseOnePieceCharacters,
            onBrowseOnePieceSubtypes: onBrowseOnePieceSubtypes
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private var scrollTrackedCardGrid: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Keeps first row clear of the overlaid search bar; spacer scrolls away so cards can pass under the glass.
                    Color.clear
                        .frame(height: rootFloatingChromeInset)
                        .id("grid-top")
                    ScrollOffsetAnchor { y in chromeScroll.reportScrollOffsetY(y) }
                    if services.brandSettings.enabledBrands.count > 1 {
                        BrandCatalogCarousel()
                            .padding(.horizontal, 16)
                            .padding(.bottom, 10)
                    }
                    browseShortcutRow
                    browseCardGrid
                    if isPreparingFilterCatalog {
                        ProgressView("Preparing filters…")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    if isLoadingMore {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 12)
                    }
                }
                // Match chrome animation so safe-area changes (tab bar) interpolate with the grid instead of snapping.
                .animation(.easeInOut(duration: 0.22), value: chromeScroll.barsVisible)
            }
            .tabBarChromeFromScroll()
            .coordinateSpace(name: "scroll")
            .onChange(of: gridResetToken) { _, _ in
                Task { @MainActor in
                    await Task.yield()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo("grid-top", anchor: .top)
                    }
                }
            }
        }
    }

    private func bootstrapFeed(forceReshuffle: Bool) async {
        if !forceReshuffle && !displayedCards.isEmpty { return }
        ImagePrefetcher.shared.cancelAll()
        isLoadingInitial = true
        let refs = await services.cardData.browseFeedCardRefs(forceReshuffle: forceReshuffle)
        shuffledRefs = refs
        nextRefIndex = 0
        displayedCards = []
        guard !refs.isEmpty else { isLoadingInitial = false; return }
        let firstEnd = min(Self.initialBatchSize, refs.count)
        let batch = Array(refs[..<firstEnd])
        nextRefIndex = firstEnd
        displayedCards = await services.cardData.cardsInOrder(refs: batch)
        allBrowseFilterCards = []
        catalogOrderedRefs = []
        catalogDisplayedCards = []
        catalogNextIndex = 0
        isLoadingInitial = false
        ImagePrefetcher.shared.prefetchCardWindow(displayedCards, startingAt: 0, count: 24)
        prefetchNextWindow()
        syncFilterMenuState()
    }

    private func loadNextPageIfNeeded() async {
        guard !isLoadingMore else { return }
        if usesCatalogFeed {
            guard catalogNextIndex < catalogOrderedRefs.count else { return }
            isLoadingMore = true
            let end = min(catalogNextIndex + Self.pageSize, catalogOrderedRefs.count)
            let batch = Array(catalogOrderedRefs[catalogNextIndex..<end])
            catalogNextIndex = end
            let more = await services.cardData.cardsInOrder(refs: batch)
            catalogDisplayedCards.append(contentsOf: more)
            isLoadingMore = false
            syncFilterMenuState()
            return
        }
        guard nextRefIndex < shuffledRefs.count else { return }
        isLoadingMore = true
        let end = min(nextRefIndex + Self.pageSize, shuffledRefs.count)
        let batch = Array(shuffledRefs[nextRefIndex..<end])
        nextRefIndex = end
        let more = await services.cardData.cardsInOrder(refs: batch)
        displayedCards.append(contentsOf: more)
        isLoadingMore = false
        prefetchNextWindow()
        syncFilterMenuState()
    }

    private func prefetchNextWindow() {
        guard usesCatalogFeed == false else { return }
        let end = min(nextRefIndex + Self.pageSize, shuffledRefs.count)
        guard nextRefIndex < end else { return }
        let upcoming = Array(shuffledRefs[nextRefIndex..<end])
        Task.detached(priority: .low) {
            let cards = await services.cardData.cardsInOrder(refs: upcoming)
            let urls = cards.map { AppConfiguration.imageURL(relativePath: $0.imageLowSrc) }
            ImagePrefetcher.shared.prefetch(urls)
        }
    }

    private func ensureAllBrowseFilterCardsLoaded(showsPreparingBanner: Bool = true) async {
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
        allBrowseFilterCards = loaded
        isLoadingFullCatalog = false
        if showsPreparingBanner {
            isPreparingFilterCatalog = false
        }
        syncFilterMenuState()
    }

    private func rebuildCatalogFeedIfNeeded() async {
        if usesCatalogFeed == false {
            catalogOrderedRefs = []
            catalogDisplayedCards = []
            catalogNextIndex = 0
            syncFilterMenuState()
            return
        }
        guard !allBrowseFilterCards.isEmpty else { return }
        let ordered = await orderedFilteredRefs(from: allBrowseFilterCards)
        catalogOrderedRefs = ordered
        let initialEnd = min(Self.catalogInitialBatchSize, ordered.count)
        let initialRefs = Array(ordered.prefix(initialEnd))
        catalogDisplayedCards = await services.cardData.cardsInOrder(refs: initialRefs)
        catalogNextIndex = initialEnd
        gridResetToken = UUID()
        syncFilterMenuState()
    }

    private func orderedFilteredRefs(from cards: [BrowseFilterCard]) async -> [CardRef] {
        let filtered = filterCards(cards)
        switch filters.sortBy {
        case .random:
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

    private func filterCards(_ cards: [BrowseFilterCard]) -> [BrowseFilterCard] {
        cards.filter { card in
            if services.brandSettings.selectedCatalogBrand == .pokemon,
               filters.cardTypes.isEmpty == false,
               filters.cardTypes.contains(resolvedCardType(for: card)) == false {
                return false
            }
            if filters.rarePlusOnly && isCommonOrUncommon(card.rarity) {
                return false
            }
            if filters.hideOwned && ownedCardIDs.contains(card.masterCardId) {
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
            if filters.lcCardTypes.isEmpty == false {
                let supertype = trimmedValue(card.category)
                if supertype.isEmpty || filters.lcCardTypes.contains(supertype) == false {
                    return false
                }
            }
            if filters.lcVariants.isEmpty == false {
                let v = trimmedValue(card.lcVariant)
                if v.isEmpty || filters.lcVariants.contains(v) == false {
                    return false
                }
            }
            if filters.lcCosts.isEmpty == false {
                guard let cost = card.lcCost, filters.lcCosts.contains(cost) else { return false }
            }
            if filters.lcStrengths.isEmpty == false {
                guard let s = card.lcStrength, filters.lcStrengths.contains(s) else { return false }
            }
            if filters.lcWillpowers.isEmpty == false {
                guard let w = card.lcWillpower, filters.lcWillpowers.contains(w) else { return false }
            }
            if filters.lcLores.isEmpty == false {
                guard let lore = card.lcLore, filters.lcLores.contains(lore) else { return false }
            }
            return true
        }
    }

    private func resolvedCardType(for card: BrowseFilterCard) -> BrowseCardTypeFilter {
        if services.brandSettings.selectedCatalogBrand == .onePiece {
            let category = card.category?.lowercased() ?? ""
            if category.contains("event") {
                return .trainer
            }
            return .pokemon
        }
        if services.brandSettings.selectedCatalogBrand == .lorcana {
            // Browse uses `lcCardTypes` for supertype; this path is only relevant if Pokémon-style filters run.
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

    private func syncFilterMenuState() {
        filterResultCount = usesCatalogFeed ? catalogOrderedRefs.count : visibleCards.count
        filterEnergyOptions = energyOptions
        filterRarityOptions = rarityOptions
        filterTrainerTypeOptions = trainerTypeOptions
    }
}

private struct BrowseShortcutButtonsRow: View {
    @Environment(AppServices.self) private var services

    let onBrowseSets: () -> Void
    let onBrowsePokemon: () -> Void
    let onBrowseOnePieceCharacters: () -> Void
    let onBrowseOnePieceSubtypes: () -> Void

    private var pokemonCatalogEnabled: Bool {
        services.brandSettings.enabledBrands.contains(.pokemon)
    }

    private var showBrowsePokemonShortcut: Bool {
        pokemonCatalogEnabled && services.brandSettings.selectedCatalogBrand == .pokemon
    }

    private var showBrowseOnePieceShortcuts: Bool {
        services.brandSettings.selectedCatalogBrand == .onePiece
    }

    private var currentBrand: TCGBrand {
        services.brandSettings.selectedCatalogBrand
    }

    var body: some View {
        Group {
            if showBrowsePokemonShortcut {
                HStack(spacing: 10) {
                    shortcutButton(title: "Browse sets", action: onBrowseSets)
                    shortcutButton(title: "Browse Pokémon", action: onBrowsePokemon)
                }
            } else if showBrowseOnePieceShortcuts {
                HStack(spacing: 10) {
                    shortcutButton(title: "Browse sets", action: onBrowseSets)
                    shortcutButton(title: "Browse characters", action: onBrowseOnePieceCharacters)
                    shortcutButton(title: "Browse subtypes", action: onBrowseOnePieceSubtypes)
                }
            } else {
                shortcutButton(title: "Browse sets", action: onBrowseSets)
            }
        }
        .id(currentBrand)
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private func shortcutButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(uiColor: .tertiarySystemFill))
                )
        }
        .buttonStyle(.plain)
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
        let enabled = services.brandSettings.enabledBrands
        return Set(collectionItems.compactMap { item in
            let brand = TCGBrand.inferredFromMasterCardId(item.cardID)
            return enabled.contains(brand) ? item.cardID : nil
        })
    }

    private var filteredCards: [Card] {
        filterBrowseCards(
            cards,
            query: query,
            filters: filters,
            ownedCardIDs: ownedCardIDs,
            brand: services.brandSettings.selectedCatalogBrand
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
                        .padding(.top)
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
        .navigationTitle(set.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    BrowseGridFiltersMenuContent(
                        brand: services.brandSettings.selectedCatalogBrand,
                        filters: $filters,
                        energyOptions: cardEnergyOptions(cards),
                        rarityOptions: cardRarityOptions(cards),
                        trainerTypeOptions: cardTrainerTypeOptions(cards)
                    )
                } label: {
                    BrowseFilterToolbarButton(isActive: filters.isVisiblyCustomized)
                }
                .menuStyle(.button)
                .menuActionDismissBehavior(.disabled)
                .menuOrder(.fixed)
                .menuIndicator(.hidden)
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
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
        let enabled = services.brandSettings.enabledBrands
        return Set(collectionItems.compactMap { item in
            let brand = TCGBrand.inferredFromMasterCardId(item.cardID)
            return enabled.contains(brand) ? item.cardID : nil
        })
    }

    private var filteredCards: [Card] {
        filterBrowseCards(
            cards,
            query: query,
            filters: filters,
            ownedCardIDs: ownedCardIDs,
            brand: services.brandSettings.selectedCatalogBrand
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
                        .padding(.top)
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
        .navigationTitle(displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    BrowseGridFiltersMenuContent(
                        brand: services.brandSettings.selectedCatalogBrand,
                        filters: $filters,
                        energyOptions: cardEnergyOptions(cards),
                        rarityOptions: cardRarityOptions(cards),
                        trainerTypeOptions: cardTrainerTypeOptions(cards)
                    )
                } label: {
                    BrowseFilterToolbarButton(isActive: filters.isVisiblyCustomized)
                }
                .menuStyle(.button)
                .menuActionDismissBehavior(.disabled)
                .menuOrder(.fixed)
                .menuIndicator(.hidden)
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
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
        let enabled = services.brandSettings.enabledBrands
        return Set(collectionItems.compactMap { item in
            let brand = TCGBrand.inferredFromMasterCardId(item.cardID)
            return enabled.contains(brand) ? item.cardID : nil
        })
    }

    private var filteredCards: [Card] {
        filterBrowseCards(
            cards,
            query: query,
            filters: filters,
            ownedCardIDs: ownedCardIDs,
            brand: services.brandSettings.selectedCatalogBrand
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
                        .padding(.top)
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
        .navigationTitle(characterName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    BrowseGridFiltersMenuContent(
                        brand: services.brandSettings.selectedCatalogBrand,
                        filters: $filters,
                        energyOptions: cardEnergyOptions(cards),
                        rarityOptions: cardRarityOptions(cards),
                        trainerTypeOptions: cardTrainerTypeOptions(cards)
                    )
                } label: {
                    BrowseFilterToolbarButton(isActive: filters.isVisiblyCustomized)
                }
                .menuStyle(.button)
                .menuActionDismissBehavior(.disabled)
                .menuOrder(.fixed)
                .menuIndicator(.hidden)
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
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
        let enabled = services.brandSettings.enabledBrands
        return Set(collectionItems.compactMap { item in
            let brand = TCGBrand.inferredFromMasterCardId(item.cardID)
            return enabled.contains(brand) ? item.cardID : nil
        })
    }

    private var filteredCards: [Card] {
        filterBrowseCards(
            cards,
            query: query,
            filters: filters,
            ownedCardIDs: ownedCardIDs,
            brand: services.brandSettings.selectedCatalogBrand
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
                        .padding(.top)
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
        .navigationTitle(subtypeName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    BrowseGridFiltersMenuContent(
                        brand: services.brandSettings.selectedCatalogBrand,
                        filters: $filters,
                        energyOptions: cardEnergyOptions(cards),
                        rarityOptions: cardRarityOptions(cards),
                        trainerTypeOptions: cardTrainerTypeOptions(cards)
                    )
                } label: {
                    BrowseFilterToolbarButton(isActive: filters.isVisiblyCustomized)
                }
                .menuStyle(.button)
                .menuActionDismissBehavior(.disabled)
                .menuOrder(.fixed)
                .menuIndicator(.hidden)
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .task(id: subtypeName) {
            isLoading = true
            cards = await services.cardData.cards(matchingOnePieceSubtype: subtypeName)
            ImagePrefetcher.shared.prefetchCardWindow(cards, startingAt: 0, count: 24)
            isLoading = false
        }
    }
}

private struct BrowseFilterToolbarButton: View {
    let isActive: Bool

    var body: some View {
        Image(systemName: isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(isActive ? Color.blue : Color.primary)
            .modifier(ChromeGlassCircleGlyphModifier())
    }
}

private struct BrowseGridFiltersMenuContent: View {
    @Environment(AppServices.self) private var services

    let brand: TCGBrand
    @Binding var filters: BrowseCardGridFilters
    let energyOptions: [String]
    let rarityOptions: [String]
    let trainerTypeOptions: [String]

    var body: some View {
        if filters.isVisiblyCustomized {
            Section {
                Button("Reset filters", role: .destructive) {
                    let currentSort = filters.sortBy
                    filters = BrowseCardGridFilters()
                    filters.sortBy = currentSort
                }
            }
        }

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
            } else if brand == .lorcana {
                filterMenu(title: "Card type", summary: selectionSummary(for: filters.lcCardTypes)) {
                    ForEach(lcCardTypeAllOptions, id: \.self) { cardType in
                        Toggle(cardType, isOn: stringBinding(for: cardType, keyPath: \.lcCardTypes))
                    }
                }

                filterMenu(title: "Variant", summary: selectionSummary(for: filters.lcVariants)) {
                    ForEach(lcVariantAllOptions, id: \.self) { variant in
                        Toggle(variant, isOn: stringBinding(for: variant, keyPath: \.lcVariants))
                    }
                }

                filterMenu(
                    title: "Stats",
                    summary: combinedSelectionSummary(
                        ("Cost", filters.lcCosts.count),
                        ("Lore", filters.lcLores.count),
                        ("Strength", filters.lcStrengths.count),
                        ("Willpower", filters.lcWillpowers.count)
                    )
                ) {
                    filterMenu(title: "Cost", summary: selectionSummary(for: filters.lcCosts)) {
                        ForEach(lcCostAllOptions, id: \.self) { cost in
                            Toggle("\(cost)", isOn: intBinding(for: cost, keyPath: \.lcCosts))
                        }
                    }
                    filterMenu(title: "Lore", summary: selectionSummary(for: filters.lcLores)) {
                        ForEach(lcLoreAllOptions, id: \.self) { lore in
                            Toggle("\(lore)", isOn: intBinding(for: lore, keyPath: \.lcLores))
                        }
                    }
                    filterMenu(title: "Strength", summary: selectionSummary(for: filters.lcStrengths)) {
                        ForEach(lcStrengthAllOptions, id: \.self) { strength in
                            Toggle("\(strength)", isOn: intBinding(for: strength, keyPath: \.lcStrengths))
                        }
                    }
                    filterMenu(title: "Willpower", summary: selectionSummary(for: filters.lcWillpowers)) {
                        ForEach(lcWillpowerAllOptions, id: \.self) { willpower in
                            Toggle("\(willpower)", isOn: intBinding(for: willpower, keyPath: \.lcWillpowers))
                        }
                    }
                }
            } else {
                filterMenu(title: "Card type", summary: selectionSummary(for: filters.cardTypes)) {
                    ForEach(BrowseCardTypeFilter.allCases) { type in
                        Toggle(type.title, isOn: cardTypeBinding(for: type))
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

        Section("Collection") {
            filterMenu(title: "Rarity", summary: selectionSummary(for: filters.rarities)) {
                if rarityOptions.isEmpty {
                    Text("No rarities available")
                } else {
                    ForEach(rarityOptions, id: \.self) { rarity in
                        Toggle(rarity, isOn: stringBinding(for: rarity, keyPath: \.rarities))
                    }
                }
            }

            Toggle("Rare + only", isOn: $filters.rarePlusOnly)
            Toggle("Hide owned", isOn: $filters.hideOwned)
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
        Binding(
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

private func cardEnergyOptions(_ cards: [Card]) -> [String] {
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

private func cardRarityOptions(_ cards: [Card]) -> [String] {
    Set(cards.compactMap { $0.rarity?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }).sorted()
}

private func cardTrainerTypeOptions(_ cards: [Card]) -> [String] {
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

private func filterBrowseCards(
    _ cards: [Card],
    query: String,
    filters: BrowseCardGridFilters,
    ownedCardIDs: Set<String>,
    brand: TCGBrand
) -> [Card] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let q = trimmed.lowercased()
    return cards.filter { card in
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
        if filters.lcCardTypes.isEmpty == false {
            let supertype = card.category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if supertype.isEmpty || filters.lcCardTypes.contains(supertype) == false {
                return false
            }
        }
        if filters.lcVariants.isEmpty == false {
            let variant = card.lcVariant?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if variant.isEmpty || filters.lcVariants.contains(variant) == false {
                return false
            }
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

private func resolvedBrowseCardType(for card: Card, brand: TCGBrand) -> BrowseCardTypeFilter {
    if brand == .lorcana { return .pokemon }
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

#Preview {
    NavigationStack {
        BrowseView(
            filters: .constant(BrowseCardGridFilters()),
            gridOptions: .constant(BrowseGridOptions()),
            isFilterMenuPresented: .constant(false),
            filterResultCount: .constant(0),
            filterEnergyOptions: .constant([]),
            filterRarityOptions: .constant([]),
            filterTrainerTypeOptions: .constant([]),
            onBrowseSets: {},
            onBrowsePokemon: {},
            onBrowseOnePieceCharacters: {},
            onBrowseOnePieceSubtypes: {}
        )
    }
        .environment(AppServices())
        .environmentObject(ChromeScrollCoordinator())
}
