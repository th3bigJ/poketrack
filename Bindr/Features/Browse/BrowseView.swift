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

    @State private var shuffledRefs: [CardRef] = []
    @State private var nextRefIndex = 0
    @State private var displayedCards: [Card] = []
    @State private var allBrowseCards: [Card] = []
    @State private var catalogOrderedCards: [Card] = []
    @State private var catalogDisplayedCards: [Card] = []
    @State private var catalogNextIndex = 0
    @State private var isLoadingInitial = true
    @State private var isLoadingMore = false
    @State private var isPreparingFilterCatalog = false

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: gridOptions.columnCount)
    }

    private static let initialBatchSize = 36
    private static let catalogInitialBatchSize = 36
    private static let pageSize = 18
    private static let prefetchBuffer = 8

    private var ownedCardIDs: Set<String> {
        Set(collectionItems.map(\.cardID))
    }

    private var setNameByCode: [String: String] {
        Dictionary(uniqueKeysWithValues: services.cardData.sets.map { ($0.setCode, $0.name) })
    }

    private var usesCatalogFeed: Bool {
        filters.hasActiveFieldFilters || filters.hasActiveSort
    }

    private var visibleCards: [Card] {
        usesCatalogFeed ? catalogDisplayedCards : displayedCards
    }

    private var energyOptions: [String] {
        Array(Set(allBrowseCards.flatMap(resolvedEnergyTypes(for:)))).sorted()
    }

    private var rarityOptions: [String] {
        Array(Set(allBrowseCards.compactMap(\.rarity).map(trimmedValue(_:)))).sorted()
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
            await services.cardData.reloadAfterBrandChange()
            await bootstrapFeed(forceReshuffle: true)
            await ensureAllBrowseCardsLoaded()
        }
        .refreshable {
            await bootstrapFeed(forceReshuffle: true)
            await ensureAllBrowseCardsLoaded()
        }
        .task(id: filters) {
            if usesCatalogFeed {
                await ensureAllBrowseCardsLoaded()
                await rebuildCatalogFeedIfNeeded()
            } else {
                catalogOrderedCards = []
                catalogDisplayedCards = []
                catalogNextIndex = 0
                syncFilterMenuState()
            }
        }
        .onAppear {
            syncFilterMenuState()
        }
        .onChange(of: visibleCards.count) { _, _ in
            syncFilterMenuState()
        }
        .onChange(of: energyOptions) { _, _ in
            syncFilterMenuState()
        }
        .onChange(of: rarityOptions) { _, _ in
            syncFilterMenuState()
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
            .onChange(of: filters) { _, _ in
                proxy.scrollTo("grid-top", anchor: .top)
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
        allBrowseCards = []
        catalogOrderedCards = []
        catalogDisplayedCards = []
        catalogNextIndex = 0
        isLoadingInitial = false
        ImagePrefetcher.shared.prefetchCardWindow(displayedCards, startingAt: 0, count: 24)
        prefetchNextWindow()
    }

    private func loadNextPageIfNeeded() async {
        guard !isLoadingMore else { return }
        if usesCatalogFeed {
            guard catalogNextIndex < catalogOrderedCards.count else { return }
            isLoadingMore = true
            let end = min(catalogNextIndex + Self.pageSize, catalogOrderedCards.count)
            let batch = Array(catalogOrderedCards[catalogNextIndex..<end])
            catalogNextIndex = end
            catalogDisplayedCards.append(contentsOf: batch)
            isLoadingMore = false
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

    private func ensureAllBrowseCardsLoaded() async {
        guard allBrowseCards.isEmpty, !isPreparingFilterCatalog else { return }
        isPreparingFilterCatalog = true
        let loaded = await services.cardData.loadAllCards()
        allBrowseCards = loaded
        isPreparingFilterCatalog = false
    }

    private func rebuildCatalogFeedIfNeeded() async {
        if usesCatalogFeed == false {
            catalogOrderedCards = []
            catalogDisplayedCards = []
            catalogNextIndex = 0
            syncFilterMenuState()
            return
        }
        guard !allBrowseCards.isEmpty else { return }
        let ordered = orderedFilteredCards(from: allBrowseCards)
        catalogOrderedCards = ordered
        let initialEnd = min(Self.catalogInitialBatchSize, ordered.count)
        catalogDisplayedCards = Array(ordered.prefix(initialEnd))
        catalogNextIndex = initialEnd
        syncFilterMenuState()
    }

    private func orderedFilteredCards(from cards: [Card]) -> [Card] {
        let filtered = filterCards(cards)
        switch filters.sortBy {
        case .random:
            // Preserve the same shuffled order used by the unfiltered feed.
            let byID = Dictionary(uniqueKeysWithValues: filtered.map { ($0.masterCardId, $0) })
            let shuffled = shuffledRefs.compactMap { byID[$0.masterCardId] }
            // Fall back for any filtered cards not present in shuffledRefs.
            let covered = Set(shuffled.map(\.masterCardId))
            let remainder = filtered.filter { !covered.contains($0.masterCardId) }
            return shuffled + remainder
        case .newestSet:
            return sortCardsByReleaseDateNewestFirst(filtered, sets: services.cardData.sets)
        case .cardName:
            return filtered.sorted { $0.cardName.localizedCaseInsensitiveCompare($1.cardName) == .orderedAscending }
        case .cardNumber:
            return filtered.sorted {
                if $0.setCode != $1.setCode {
                    return compareReleaseDateNewestFirst(lhsSetCode: $0.setCode, rhsSetCode: $1.setCode)
                }
                return $0.cardNumber.localizedStandardCompare($1.cardNumber) == .orderedAscending
            }
        case .rarity:
            return filtered.sorted {
                let left = $0.rarity?.lowercased() ?? ""
                let right = $1.rarity?.lowercased() ?? ""
                if left != right {
                    return left.localizedStandardCompare(right) == .orderedDescending
                }
                return $0.cardName.localizedCaseInsensitiveCompare($1.cardName) == .orderedAscending
            }
        }
    }

    private func filterCards(_ cards: [Card]) -> [Card] {
        cards.filter { card in
            if filters.cardTypes.isEmpty == false && filters.cardTypes.contains(resolvedCardType(for: card)) == false {
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
            return true
        }
    }

    private func resolvedCardType(for card: Card) -> BrowseCardTypeFilter {
        if services.brandSettings.selectedCatalogBrand == .onePiece {
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
        let dates = Dictionary(uniqueKeysWithValues: services.cardData.sets.map { ($0.setCode, $0.releaseDate ?? "") })
        let lhs = dates[lhsSetCode] ?? ""
        let rhs = dates[rhsSetCode] ?? ""
        if lhs != rhs {
            return lhs > rhs
        }
        return lhsSetCode.localizedStandardCompare(rhsSetCode) == .orderedAscending
    }

    private func syncFilterMenuState() {
        filterResultCount = usesCatalogFeed ? catalogOrderedCards.count : visibleCards.count
        filterEnergyOptions = energyOptions
        filterRarityOptions = rarityOptions
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
    let dates = Dictionary(uniqueKeysWithValues: sets.map { ($0.setCode, $0.releaseDate ?? "") })
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
            filterRarityOptions: .constant([])
        )
    }
        .environment(AppServices())
        .environmentObject(ChromeScrollCoordinator())
}
