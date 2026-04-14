import SwiftData
import SwiftUI

// MARK: - Shared card grid cell

struct CardGridCell: View {
    let card: Card
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
            Text(card.cardName)
                .font(.caption2)
                .lineLimit(1)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
            if let footnote, !footnote.isEmpty {
                Text(footnote)
                    .font(.caption2)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
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

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: gridOptions.columnCount)
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
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(Array(visibleCards.enumerated()), id: \.element.id) { index, card in
                Button { presentCard(card, visibleCards) } label: {
                    BrowseGridCardCell(
                        card: card,
                        gridOptions: gridOptions,
                        setName: setNameByCode[card.setCode]
                    )
                }
                .buttonStyle(CardCellButtonStyle())
                .onAppear {
                    // Prefetch ahead every row so images are warm before cells reach the viewport.
                    let ahead = gridOptions.columnCount * 5
                    if index % gridOptions.columnCount == 0 {
                        ImagePrefetcher.shared.prefetchCardWindow(
                            visibleCards,
                            startingAt: index + ahead,
                            count: ahead * 2
                        )
                    }
                }
            }

            // Sentinel: triggers next page load when the bottom of the grid scrolls into view.
            Color.clear
                .frame(height: 1)
                .onAppear { Task { await loadNextPageIfNeeded() } }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 16)
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
        let ordered = orderedFilteredRefs(from: allBrowseFilterCards)
        catalogOrderedRefs = ordered
        let initialEnd = min(Self.catalogInitialBatchSize, ordered.count)
        let initialRefs = Array(ordered.prefix(initialEnd))
        catalogDisplayedCards = await services.cardData.cardsInOrder(refs: initialRefs)
        catalogNextIndex = initialEnd
        gridResetToken = UUID()
        syncFilterMenuState()
    }

    private func orderedFilteredRefs(from cards: [BrowseFilterCard]) -> [CardRef] {
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
        case .rarity:
            return filtered.sorted {
                let left = $0.rarity?.lowercased() ?? ""
                let right = $1.rarity?.lowercased() ?? ""
                if left != right {
                    return left.localizedStandardCompare(right) == .orderedDescending
                }
                return $0.cardName.localizedCaseInsensitiveCompare($1.cardName) == .orderedAscending
            }.map(\.ref)
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

// MARK: - Set cards

struct SetCardsView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.presentCard) private var presentCard
    let set: TCGSet

    @State private var cards: [Card] = []
    @State private var isLoading = true
    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView().padding()
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                        Button { presentCard(card, cards) } label: { CardGridCell(card: card) }
                            .buttonStyle(CardCellButtonStyle())
                            .onAppear {
                                ImagePrefetcher.shared.prefetchCardWindow(cards, startingAt: index + 1)
                            }
                    }
                }
                .padding()
            }
        }
        .navigationTitle(set.name)
        .navigationBarTitleDisplayMode(.inline)
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
    let dexId: Int
    let displayName: String

    @State private var cards: [Card] = []
    @State private var isLoading = true
    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView().padding()
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                        Button { presentCard(card, cards) } label: { CardGridCell(card: card) }
                            .buttonStyle(CardCellButtonStyle())
                            .onAppear {
                                ImagePrefetcher.shared.prefetchCardWindow(cards, startingAt: index + 1)
                            }
                    }
                }
                .padding()
            }
        }
        .navigationTitle(displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task {
            isLoading = true
            cards = await services.cardData.cards(matchingNationalDex: dexId)
            ImagePrefetcher.shared.prefetchCardWindow(cards, startingAt: 0, count: 24)
            isLoading = false
        }
    }
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
            filterTrainerTypeOptions: .constant([])
        )
    }
        .environment(AppServices())
        .environmentObject(ChromeScrollCoordinator())
}
