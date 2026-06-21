import SwiftData
import SwiftUI

/// Combined Collection + Wishlist view with segmented toggle at top.
struct CollectView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Environment(\.presentCard) private var presentCard
    @Environment(\.presentCardAtIndex) private var presentCardAtIndex
    @Environment(\.rootFloatingChromeInset) private var rootFloatingChromeInset

    // MARK: - Collection State
    @Query(sort: \CollectionItem.dateAcquired, order: .reverse) private var collectionItems: [CollectionItem]
    @State private var cardsByCardID: [String: Card] = [:]
    @State private var collectionPriceByItemKey: [String: Double] = [:]
    @State private var collectionResolvedPriceItemKeys: Set<String> = []
    @State private var selectedSealedProduct: SealedProduct?
    @State private var cachedSetNameByBrandAndCode: [String: String] = [:]
    @State private var sealedProductByIDCache: [Int: SealedProduct] = [:]
    @State private var sealedProductByCollectionCardIDCache: [String: SealedProduct] = [:]
    @State private var collectionFilteredGroupsForSelectedTypeCache: [CollectionGridGroup] = []
    @State private var collectionDisplayedGroups: [CollectionGridGroup] = []
    @State private var collectionDisplayedCards: [Card] = []
    @State private var collectionNextIndex = 0
    @State private var isLoadingMoreCollectionItems = false
    @State private var openSealedSession: CollectionOpenSealedSession?

    // MARK: - Wishlist State
    @Query(sort: \WishlistItem.dateAdded, order: .reverse) private var wishlistItems: [WishlistItem]
    @State private var wishlistCardsByID: [String: Card] = [:]
    @State private var wishlistPriceByItemKey: [String: Double] = [:]

    @State private var pendingCardContextRequest: CardContextActionRequest?

    // MARK: - Shared State (owned by RootView)
    @Binding var selectedSegment: CollectSegment
    @Binding var selectedContentTypeTab: CollectContentTypeTab
    @Binding var selectedBrand: TCGBrand?
    @Binding var collectionFilters: BrowseCardGridFilters
    @Binding var wishlistFilters: BrowseCardGridFilters
    @Binding var collectFilterEnergyOptions: [String]
    @Binding var collectFilterRarityOptions: [String]
    @Binding var collectFilterTrainerTypeOptions: [String]
    @Binding var gridOptions: BrowseGridOptions

    @State private var collectionQuery = ""
    @State private var wishlistQuery = ""
    private static let collectionInitialBatchSize = 36
    private static let collectionPageSize = 18
    private static let sealedReleaseDateSortFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    var showsSegmentedControl = true
    var hidesNavigationBar = true

    private var safeColumnCount: Int {
        min(max(gridOptions.columnCount, 1), 4)
    }

    private var activeBrand: TCGBrand { .pokemon }

    private func setNameKey(brand: TCGBrand, setCode: String) -> String {
        "\(brand.rawValue)|\(setCode)"
    }

    private func setName(for card: Card) -> String? {
        let brand = TCGBrand.inferredFromMasterCardId(card.masterCardId)
        return cachedSetNameByBrandAndCode[setNameKey(brand: brand, setCode: card.setCode)]
    }

    private var setNameCacheKey: String {
        services.brandSettings.enabledBrands.map(\.rawValue).sorted().joined(separator: ",")
    }

    private func buildSetReleaseDateByCode() -> [String: String] {
        var map: [String: String] = [:]
        map.reserveCapacity(services.cardData.sets.count)
        for set in services.cardData.sets where map[set.setCode] == nil {
            map[set.setCode] = set.releaseDate ?? ""
        }
        return map
    }

    private var visibleCollectionItems: [CollectionItem] {
        collectionItems.filter { TCGBrand.inferredFromMasterCardId($0.cardID) == activeBrand }
    }

    private var visibleCollectionCardItems: [CollectionItem] {
        visibleCollectionItems.filter { sealedProduct(for: $0) == nil }
    }

    private var collectionSortNeedsResolvedCards: Bool {
        switch collectionFilters.sortBy {
        case .cardName, .newestSet, .cardNumber, .price:
            return true
        case .acquiredDateNewest, .random:
            return false
        }
    }

    private var collectionHasCardFilterDependencies: Bool {
        let trimmedQuery = collectionQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedQuery.isEmpty || collectionFilters.hasActiveCardFieldFilters
    }

    private var isCollectionWaitingForCurrentSortOrFilters: Bool {
        guard selectedContentTypeTab == .cards else { return false }
        guard !visibleCollectionCardItems.isEmpty else { return false }

        if collectionSortNeedsResolvedCards || collectionHasCardFilterDependencies {
            let missingCardData = visibleCollectionCardItems.contains { cardsByCardID[$0.cardID] == nil }
            if missingCardData { return true }
        }

        if collectionFilters.sortBy == .price {
            let missingPriceResolution = visibleCollectionCardItems.contains {
                !collectionResolvedPriceItemKeys.contains(collectionItemKey($0))
            }
            if missingPriceResolution { return true }
        }

        return false
    }

    private var sealedProductsSignature: Int {
        var h = Hasher()
        for p in services.sealedProducts.products { h.combine(p.id) }
        return h.finalize()
    }

    private var wishlistedSealedCollectionCardIDs: Set<String> {
        Set(wishlistItems.compactMap { item in
            guard SealedProduct.parseCollectionProductID(item.cardID) != nil else { return nil }
            return item.cardID
        })
    }

    private var visibleWishlistItems: [WishlistItem] {
        wishlistItems.filter { TCGBrand.inferredFromMasterCardId($0.cardID) == activeBrand }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Color.clear.frame(height: rootFloatingChromeInset)

                VStack(spacing: 10) {
                    if showsSegmentedControl {
                        segmentedControl.padding(.horizontal, 16)
                    }
                    BrowseInlineSearchField(title: searchPlaceholder, text: activeQueryBinding) {
                        contentTypeChips
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 10)

                contentView
            }
        }
        .refreshable {
            await refreshCollectContent()
        }
        .bindrPageBackground()
        .scrollDismissesKeyboard(.immediately)
        .toolbar(hidesNavigationBar ? .hidden : .visible, for: .navigationBar)
        .onAppear {
            services.setupCollectionLedger(modelContext: modelContext)
            services.setupWishlist(modelContext: modelContext)
            Task { await services.sealedProducts.loadFromLocalIfAvailable() }
        }
        .task {
            if services.sealedProducts.products.isEmpty {
                await services.sealedProducts.refreshFromNetworkAndStoreLocallyIfNeeded()
            }
        }
        .task(id: collectionSignature) {
            await resolveCollectionCards()
        }
        .task(id: wishlistSignature) {
            await resolveWishlistCards()
        }
        .task(id: setNameCacheKey) {
            await refreshSetNameCache()
        }
        .task(id: sealedProductsSignature) {
            refreshSealedProductCaches()
        }
        .onAppear {
            if selectedBrand != services.brandSettings.selectedCatalogBrand {
                selectedBrand = services.brandSettings.selectedCatalogBrand
            }
            refreshSealedProductCaches()
            refreshCollectionFeed()
            Task { @MainActor in
                await Task.yield()
                refreshCollectionFeed()
            }
        }
        .onChange(of: services.brandSettings.selectedCatalogBrand) { _, brand in
            selectedBrand = brand
        }
        .onChange(of: selectedBrand) { _, _ in refreshCollectionFeed() }
        .onChange(of: selectedContentTypeTab) { _, _ in refreshCollectionFeed() }
        .onChange(of: collectionQuery) { _, _ in refreshCollectionFeed() }
        .onChange(of: collectionFilters) { _, _ in refreshCollectionFeed() }
        .onChange(of: collectionPriceByItemKey) { _, _ in refreshCollectionFeed() }
        .onChange(of: cardsByCardID) { _, _ in refreshCollectionFeed() }
        .onChange(of: sealedProductByCollectionCardIDCache) { _, _ in refreshCollectionFeed() }
        .sheet(item: $selectedSealedProduct) { product in
            SealedProductBrowseDetailView(products: [product], startProductID: product.id)
                .environment(services)
        }
        .sheet(item: $openSealedSession) { session in
            OpenSealedCollectionItemSheet(item: session.item, productName: session.productName)
                .environment(services)
        }
        .sheet(item: $pendingCardContextRequest) { req in
            CardContextActionSheet(request: req)
                .environment(services)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: selectedSealedProduct?.id) { _, productID in
            services.isSealedDetailPresentationActive = (productID != nil)
        }
    }

    private func refreshSetNameCache() async {
        var map: [String: String] = cachedSetNameByBrandAndCode
        for brand in services.brandSettings.enabledBrands {
            if brand == services.brandSettings.selectedCatalogBrand,
               !services.cardData.sets.isEmpty {
                for set in services.cardData.sets {
                    let key = setNameKey(brand: brand, setCode: set.setCode)
                    if map[key] == nil {
                        map[key] = set.name
                    }
                }
                continue
            }
            guard let sets = try? await CatalogStore.shared.fetchAllSets(for: brand) else { continue }
            for set in sets {
                let key = setNameKey(brand: brand, setCode: set.setCode)
                if map[key] == nil {
                    map[key] = set.name
                }
            }
        }
        cachedSetNameByBrandAndCode = map
    }

    private func refreshSealedProductCaches() {
        var byID: [Int: SealedProduct] = [:]
        var byCollectionCardID: [String: SealedProduct] = [:]
        byID.reserveCapacity(services.sealedProducts.products.count)
        byCollectionCardID.reserveCapacity(services.sealedProducts.products.count)
        for product in services.sealedProducts.products {
            byID[product.id] = product
            byCollectionCardID[product.collectionCardID] = product
        }
        sealedProductByIDCache = byID
        sealedProductByCollectionCardIDCache = byCollectionCardID
    }

    // MARK: - Segmented Control

    private var segmentedControl: some View {
        SlidingSegmentedPicker(
            selection: $selectedSegment,
            items: CollectSegment.allCases,
            title: { $0.title }
        )
    }

    private var searchPlaceholder: String {
        let itemLabel = selectedContentTypeTab == .cards ? "cards" : "product"
        switch selectedSegment {
        case .collection:
            return "Search \(formattedActiveFilteredCount) \(itemLabel) in collection"
        case .wishlist:
            return "Search \(formattedActiveFilteredCount) \(itemLabel) in wishlist"
        }
    }

    private var activeQueryBinding: Binding<String> {
        switch selectedSegment {
        case .collection: return $collectionQuery
        case .wishlist:   return $wishlistQuery
        }
    }

    private var contentTypeChips: some View {
        HStack(spacing: 6) {
            contentTypeChip(for: .cards, icon: "square.stack.3d.up")
            contentTypeChip(for: .products, icon: "shippingbox")
            if !activeQueryBinding.wrappedValue.isEmpty {
                Button {
                    activeQueryBinding.wrappedValue = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .padding(.leading, 2)
            }
        }
    }

    private func contentTypeChip(for tab: CollectContentTypeTab, icon: String) -> some View {
        let isSelected = selectedContentTypeTab == tab
        return Button {
            guard selectedContentTypeTab != tab else { return }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                selectedContentTypeTab = tab
            }
            Haptics.lightImpact()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(tab.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? .white : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .bindrAccentFill(isSelected ? services.theme.accentColor : Color.clear, usesLogoGradient: isSelected)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(
                        isSelected ? services.theme.accentColor.opacity(0.55) : Color.white.opacity(0.16),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
    }

    private var activeFilteredCount: Int {
        switch selectedSegment {
        case .collection:
            return collectionFilteredGroupsForSelectedTypeCache.count
        case .wishlist:
            if selectedContentTypeTab == .cards {
                return Set(filteredWishlistItemsForSelectedType.map(\.cardID)).count
            }
            return filteredWishlistItemsForSelectedType.count
        }
    }

    private var formattedActiveFilteredCount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: activeFilteredCount)) ?? "\(activeFilteredCount)"
    }

    // MARK: - Content View

    @ViewBuilder
    private var contentView: some View {
        switch selectedSegment {
        case .collection: collectionContent
        case .wishlist:   wishlistContent
        }
    }

    // MARK: - Collection Content

    @ViewBuilder
    private var collectionContent: some View {
        if collectionItems.isEmpty {
            emptyState(title: "No collection yet", image: "square.stack.3d.up.slash",
                       description: "Add cards from card details with the + button.")
        } else if visibleCollectionItems.isEmpty {
            emptyState(
                title: "No collection items",
                image: "line.3.horizontal.decrease.circle",
                description: "No \(activeBrand.displayTitle) cards in your collection yet."
            )
        } else if isCollectionWaitingForCurrentSortOrFilters {
            VStack(spacing: 12) {
                ProgressView()
                Text("Applying your filters and sort...")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        } else if collectionFilteredGroupsForSelectedTypeCache.isEmpty {
            emptyState(
                title: "No matching \(selectedContentTypeTab.title.lowercased())",
                image: "magnifyingglass",
                description: selectedContentTypeTab == .cards
                    ? "Try a different card name, set code, or number."
                    : "Try a different product name, series, or year."
            )
        } else {
            EagerVGrid(items: indexedDisplayedCollectionGroups, columns: safeColumnCount, spacing: 12) { indexed in
                collectionCell(for: indexed.item, at: indexed.index)
                    .onAppear {
                        guard selectedContentTypeTab == .cards else { return }
                        ImagePrefetcher.shared.prefetchCardWindow(collectionDisplayedCards, startingAt: indexed.index + 1)
                        guard indexed.index >= max(collectionDisplayedGroups.count - safeColumnCount, 0) else { return }
                        Task { await loadMoreCollectionItemsIfNeeded() }
                    }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            if isLoadingMoreCollectionItems {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
            }
        }
    }

    @ViewBuilder
    private func collectionCell(for group: CollectionGridGroup, at index: Int) -> some View {
        let item = group.representativeItem
        let variantKeys = group.variantKeys
        let preferredVariantKey = group.preferredVariantKey
        let contextItem = group.item(forVariantKey: preferredVariantKey) ?? item
        let contextOwnedQuantity = group.quantity(forVariantKey: preferredVariantKey)

        if let product = sealedProduct(for: item) {
            Button { selectedSealedProduct = product } label: {
                SealedProductGridCell(
                    product: product,
                    gridOptions: gridOptions,
                    priceUSD: services.sealedProducts.marketPriceUSD(for: product.id),
                    isOwned: false,
                    isWishlisted: wishlistedSealedCollectionCardIDs.contains(product.collectionCardID),
                    ownedCountBadge: group.totalQuantity > 1 ? group.totalQuantity : nil
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(CardCellButtonStyle())
            .contextMenu {
                Button {
                    openSealedSession = CollectionOpenSealedSession(item: item, productName: product.name)
                } label: {
                    Label("Mark as Opened", systemImage: "shippingbox")
                }
            }
            .accessibilityLabel("\(product.name), \(group.totalQuantity) owned")
        } else if let card = cardsByCardID[item.cardID] {
            Button {
                let tapTimeCards = collectionDisplayedGroups.compactMap { cardsByCardID[$0.cardID] }
                let cardIndex = tapTimeCards.firstIndex(where: { $0.masterCardId == card.masterCardId }) ?? 0
                presentCardAtIndex(tapTimeCards, cardIndex)
            } label: {
                CardGridCell(
                    card: card,
                    services: services,
                    colorScheme: colorScheme,
                    gridOptions: gridOptions,
                    setName: setName(for: card),
                    ownedCountBadge: group.totalQuantity,
                    overridePrice: collectionDisplayPrice(for: group),
                    gradeLabel: collectionGradeLabel(for: item)
                )
            }
            .buttonStyle(CardCellButtonStyle())
            .contextMenu {
                Button {
                    pendingCardContextRequest = CardContextActionRequest(
                        card: card,
                        availableVariantKeys: variantKeys,
                        initialVariantKey: preferredVariantKey,
                        ownedQuantity: contextOwnedQuantity,
                        collectionItem: contextItem,
                        initialAction: .collection
                    )
                } label: {
                    Label("Add to Collection", systemImage: "books.vertical")
                }
                Button {
                    pendingCardContextRequest = CardContextActionRequest(
                        card: card,
                        availableVariantKeys: variantKeys,
                        initialVariantKey: preferredVariantKey,
                        ownedQuantity: contextOwnedQuantity,
                        collectionItem: contextItem,
                        initialAction: .wishlist
                    )
                } label: {
                    Label("Add to Wishlist", systemImage: "heart")
                }
                Button {
                    pendingCardContextRequest = CardContextActionRequest(
                        card: card,
                        availableVariantKeys: variantKeys,
                        initialVariantKey: preferredVariantKey,
                        ownedQuantity: contextOwnedQuantity,
                        collectionItem: contextItem,
                        initialAction: .markAs
                    )
                } label: {
                    Label("Mark as", systemImage: "tag")
                }
            }
            .accessibilityLabel(collectionAccessibilityLabel(for: card, group: group))
        } else {
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.15))
                    .aspectRatio(5 / 7, contentMode: .fit)
                    .overlay { ProgressView() }
                Text(item.cardID).font(.caption2).lineLimit(2).multilineTextAlignment(.center).foregroundStyle(.secondary)
            }
        }
    }

    private var collectionOwnedCardIDs: Set<String> {
        Set(visibleCollectionItems.map(\.cardID))
    }

    private var filteredCollectionItems: [CollectionItem] {
        var items = visibleCollectionItems
        if collectionFilters.showDuplicates {
            let rawCardTotals = Dictionary(
                grouping: items.filter { !usesIndividualCollectionGridCell($0) },
                by: \.cardID
            ).mapValues { group in
                group.reduce(0) { $0 + max($1.quantity, 0) }
            }
            items = items.filter { item in
                if usesIndividualCollectionGridCell(item) {
                    return item.quantity >= 2
                }
                return rawCardTotals[item.cardID, default: item.quantity] >= 2
            }
        }
        let trimmedQuery = collectionQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasCardFieldFilters = collectionFilters.hasActiveCardFieldFilters
        let hasSealedFieldFilters = collectionFilters.hasActiveProductFieldFilters
        let needsCardFiltering = hasCardFieldFilters || !trimmedQuery.isEmpty
        let filteredIDs: Set<String> = {
            guard needsCardFiltering else { return [] }
            let filteredCards = filterBrowseCards(
                resolvedCollectionCards, query: collectionQuery, filters: collectionFilters,
                ownedCardIDs: collectionOwnedCardIDs,
                brand: activeBrand, sets: services.cardData.sets
            )
            return Set(filteredCards.map { $0.masterCardId })
        }()
        if needsCardFiltering || hasSealedFieldFilters {
            let normalizedQuery = trimmedQuery.lowercased()
            items = items.filter { item in
                if let product = sealedProduct(for: item) {
                    guard hasCardFieldFilters == false else { return false }
                    guard productMatchesSelectedTypes(product.type, selectedOptionIDs: collectionFilters.productTypes) else {
                        return false
                    }
                    guard !normalizedQuery.isEmpty else { return true }
                    return product.searchBlob.contains(normalizedQuery)
                }
                guard needsCardFiltering else { return true }
                return filteredIDs.contains(item.cardID)
            }
        }
        return applySortToCollectionItems(items, filters: collectionFilters)
    }

    private var filteredCollectionItemsForSelectedType: [CollectionItem] {
        filteredCollectionItems.filter { item in
            let isSealed = sealedProduct(for: item) != nil
            return selectedContentTypeTab == .products ? isSealed : !isSealed
        }
    }

    private var indexedDisplayedCollectionGroups: [IndexedGridItem<CollectionGridGroup>] {
        Array(collectionDisplayedGroups.enumerated()).map { offset, group in
            IndexedGridItem(index: offset, item: group)
        }
    }

    private func groupCollectionItemsForGrid(_ items: [CollectionItem]) -> [CollectionGridGroup] {
        CollectionGridGrouping.groupedItems(items, isSealed: { sealedProduct(for: $0) != nil })
    }

    private func usesIndividualCollectionGridCell(_ item: CollectionItem) -> Bool {
        sealedProduct(for: item) != nil || CollectionGridGrouping.isGradedItem(item)
    }

    private func collectionDisplayPrice(for group: CollectionGridGroup) -> Double? {
        group.items.compactMap { collectionPriceByItemKey[collectionItemKey($0)] }.max()
    }

    private func collectionAccessibilityLabel(for card: Card, group: CollectionGridGroup) -> String {
        if group.variantKeys.count > 1 {
            return "\(card.cardName), \(group.totalQuantity) copies, \(group.variantKeys.count) variants"
        }
        let variant = group.variantKeys.first ?? "normal"
        return "\(card.cardName), \(group.totalQuantity) copies, \(variant)"
    }

    private func applySortToCollectionItems(_ items: [CollectionItem], filters: BrowseCardGridFilters) -> [CollectionItem] {
        switch filters.sortBy {
        case .acquiredDateNewest, .random:
            return items
        case .cardName:
            return items.sorted {
                collectionDisplayName(for: $0).localizedCaseInsensitiveCompare(collectionDisplayName(for: $1)) == .orderedAscending
            }
        case .newestSet, .cardNumber:
            return sortCollectionItemsByNewestSet(items)
        case .price:
            return items.sorted { lhs, rhs in
                let lhsPrice = collectionDisplayPrice(for: lhs)
                let rhsPrice = collectionDisplayPrice(for: rhs)
                switch (lhsPrice, rhsPrice) {
                case let (l?, r?):
                    if l != r { return l > r }
                case (.some, nil):
                    return true
                case (nil, .some):
                    return false
                case (nil, nil):
                    break
                }
                return collectionDisplayName(for: lhs).localizedCaseInsensitiveCompare(collectionDisplayName(for: rhs)) == .orderedAscending
            }
        }
    }

    private var resolvedCollectionCards: [Card] {
        visibleCollectionItems.compactMap { cardsByCardID[$0.cardID] }
    }

    private var collectionSignature: Int {
        var h = Hasher()
        h.combine(activeBrand.rawValue)
        for item in visibleCollectionItems {
            h.combine(item.cardID)
            h.combine(item.variantKey)
            h.combine(item.quantity)
        }
        return h.finalize()
    }

    private func resolveCollectionCards() async {
        let cardItems = visibleCollectionItems.filter { sealedProduct(for: $0) == nil }
        let missingIDs = Array(Set(cardItems.map(\.cardID).filter { cardsByCardID[$0] == nil }))
        var next = cardsByCardID
        if !missingIDs.isEmpty {
            let loaded = await services.cardData.loadCards(
                masterCardIDs: missingIDs,
                catalogBrand: activeBrand
            )
            for card in loaded {
                next[card.masterCardId] = card
            }
        }
        cardsByCardID = next

        let cardsToPrice = cardItems.compactMap { next[$0.cardID] }
        await services.pricing.indexPricingForCards(cardsToPrice)

        var nextPrices: [String: Double] = [:]
        var resolvedPriceKeys: Set<String> = []
        for item in cardItems {
            guard let card = next[item.cardID] else { continue }
            resolvedPriceKeys.insert(collectionItemKey(item))
            let gradeKey = collectionGradeKey(for: item)
            if let usd = services.pricing.cachedUsdPriceForVariantAndGrade(
                for: card,
                variantKey: item.variantKey,
                grade: gradeKey
            ) {
                nextPrices[collectionItemKey(item)] = usd
            }
        }
        collectionPriceByItemKey = nextPrices
        collectionResolvedPriceItemKeys = resolvedPriceKeys

        let cards = collectionDisplayedCards
        ImagePrefetcher.shared.prefetchCardWindow(cards, startingAt: 0, count: 24)
        collectFilterEnergyOptions = cardEnergyOptions(cards)
        collectFilterRarityOptions = cardRarityOptions(cards)
        collectFilterTrainerTypeOptions = cardTrainerTypeOptions(cards)
        refreshCollectionFeed()
    }

    private func refreshCollectContent() async {
        await services.sealedProducts.refreshFromNetworkAndStoreLocallyIfNeeded()
        await refreshSetNameCache()
        refreshSealedProductCaches()
        await resolveCollectionCards()
        await resolveWishlistCards()
        refreshCollectionFeed()
    }

    private func refreshCollectionFeed() {
        let filtered = filteredCollectionItemsForSelectedType
        let groups = groupCollectionItemsForGrid(filtered)
        let filteredIDs = groups.map(\.id)
        let previousIDs = collectionFilteredGroupsForSelectedTypeCache.map(\.id)

        collectionFilteredGroupsForSelectedTypeCache = groups

        if filteredIDs == previousIDs && !collectionDisplayedGroups.isEmpty {
            collectionDisplayedCards = collectionDisplayedGroups.compactMap { cardsByCardID[$0.cardID] }
            return
        }

        let initialEnd = min(Self.collectionInitialBatchSize, groups.count)
        collectionDisplayedGroups = Array(groups.prefix(initialEnd))
        collectionNextIndex = initialEnd
        collectionDisplayedCards = collectionDisplayedGroups.compactMap { cardsByCardID[$0.cardID] }
    }

    @MainActor
    private func loadMoreCollectionItemsIfNeeded() async {
        guard !isLoadingMoreCollectionItems else { return }
        guard collectionNextIndex < collectionFilteredGroupsForSelectedTypeCache.count else { return }
        isLoadingMoreCollectionItems = true
        defer { isLoadingMoreCollectionItems = false }
        let end = min(collectionNextIndex + Self.collectionPageSize, collectionFilteredGroupsForSelectedTypeCache.count)
        let more = collectionFilteredGroupsForSelectedTypeCache[collectionNextIndex..<end]
        collectionDisplayedGroups.append(contentsOf: more)
        collectionNextIndex = end
        collectionDisplayedCards = collectionDisplayedGroups.compactMap { cardsByCardID[$0.cardID] }
    }

    private func sealedProduct(for item: CollectionItem) -> SealedProduct? {
        guard item.itemKind == ProductKind.sealedProduct.rawValue || SealedProduct.parseCollectionProductID(item.cardID) != nil else {
            return nil
        }
        if let product = sealedProductByCollectionCardIDCache[item.cardID] {
            return product
        }
        if let rawID = item.sealedProductId,
           let productID = Int(rawID),
           let product = sealedProductByIDCache[productID] {
            return product
        }
        if let productID = SealedProduct.parseCollectionProductID(item.cardID) {
            return sealedProductByIDCache[productID]
        }
        return nil
    }

    private func collectionDisplayName(for item: CollectionItem) -> String {
        if let product = sealedProduct(for: item) {
            return product.name
        }
        return cardsByCardID[item.cardID]?.cardName ?? item.cardID
    }

    private func collectionDisplayPrice(for item: CollectionItem) -> Double? {
        if let product = sealedProduct(for: item) {
            return services.sealedProducts.marketPriceUSD(for: product.id)
        }
        return collectionPriceByItemKey[collectionItemKey(item)]
    }

    // MARK: - Wishlist Content

    @ViewBuilder
    private var wishlistContent: some View {
        if wishlistItems.isEmpty {
            emptyState(title: "Wishlist is empty", image: "star.slash",
                       description: "Add cards from browse or search to track cards you want.")
        } else if visibleWishlistItems.isEmpty {
            emptyState(
                title: "No wishlist items",
                image: "line.3.horizontal.decrease.circle",
                description: "No \(activeBrand.displayTitle) cards on your wishlist yet."
            )
        } else if filteredWishlistItemsForSelectedType.isEmpty {
            emptyState(
                title: "No matching \(selectedContentTypeTab.title.lowercased())",
                image: "magnifyingglass",
                description: selectedContentTypeTab == .cards
                    ? "Try a different card name, set code, or number."
                    : "Try a different product name, series, or year."
            )
        } else {
            EagerVGrid(items: indexedFilteredWishlistItemsForSelectedType, columns: safeColumnCount, spacing: 12) { indexed in
                wishlistCell(for: indexed.item)
                    .onAppear {
                        guard selectedContentTypeTab == .cards else { return }
                        ImagePrefetcher.shared.prefetchCardWindow(orderedWishlistCards, startingAt: indexed.index + 1)
                    }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private func wishlistCell(for item: WishlistItem) -> some View {
        if let product = sealedProduct(for: item) {
            Button { selectedSealedProduct = product } label: {
                SealedProductGridCell(
                    product: product,
                    gridOptions: gridOptions,
                    priceUSD: services.sealedProducts.marketPriceUSD(for: product.id),
                    isOwned: false,
                    isWishlisted: false
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(CardCellButtonStyle())
            .contextMenu {
                Button(role: .destructive) {
                    removeFromWishlist(item)
                } label: {
                    Label("Remove from Wishlist", systemImage: "heart.slash")
                }
            }
            .accessibilityLabel(product.name)
        } else if let card = wishlistCardsByID[item.cardID] {
            Button { presentCard(card, orderedWishlistCards) } label: {
                CardGridCell(
                    card: card,
                    services: services,
                    colorScheme: colorScheme,
                    gridOptions: gridOptions,
                    setName: setName(for: card),
                    footnote: nil
                )
            }
            .buttonStyle(CardCellButtonStyle())
            .contextMenu {
                Button(role: .destructive) {
                    removeFromWishlist(item)
                } label: {
                    Label("Remove from Wishlist", systemImage: "heart.slash")
                }
            }
            .accessibilityLabel(card.cardName)
        } else {
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.15))
                    .aspectRatio(5 / 7, contentMode: .fit)
                    .overlay { ProgressView() }
                Text(item.cardID).font(.caption2).lineLimit(2).multilineTextAlignment(.center).foregroundStyle(.secondary)
            }
        }
    }

    private var filteredWishlistItems: [WishlistItem] {
        var items = visibleWishlistItems
        let trimmedQuery = wishlistQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasCardFieldFilters = wishlistFilters.hasActiveCardFieldFilters
        let hasSealedFieldFilters = wishlistFilters.hasActiveProductFieldFilters
        let needsCardFiltering = hasCardFieldFilters || !trimmedQuery.isEmpty
        let filteredIDs: Set<String> = {
            guard needsCardFiltering else { return [] }
            let filteredCards = filterBrowseCards(
                resolvedWishlistCards, query: wishlistQuery, filters: wishlistFilters,
                ownedCardIDs: collectionOwnedCardIDs, brand: activeBrand, sets: services.cardData.sets
            )
            return Set(filteredCards.map { $0.masterCardId })
        }()
        if needsCardFiltering || hasSealedFieldFilters {
            let normalizedQuery = trimmedQuery.lowercased()
            items = items.filter { item in
                if let product = sealedProduct(for: item) {
                    guard hasCardFieldFilters == false else { return false }
                    guard productMatchesSelectedTypes(product.type, selectedOptionIDs: wishlistFilters.productTypes) else {
                        return false
                    }
                    guard !normalizedQuery.isEmpty else { return true }
                    return product.searchBlob.contains(normalizedQuery)
                }
                guard needsCardFiltering else { return true }
                return filteredIDs.contains(item.cardID)
            }
        }
        return applySortToWishlistItems(items, filters: wishlistFilters)
    }

    private var filteredWishlistItemsForSelectedType: [WishlistItem] {
        filteredWishlistItems.filter { item in
            let isSealed = sealedProduct(for: item) != nil
            return selectedContentTypeTab == .products ? isSealed : !isSealed
        }
    }

    private var indexedFilteredWishlistItemsForSelectedType: [IndexedGridItem<WishlistItem>] {
        Array(filteredWishlistItemsForSelectedType.enumerated()).map { offset, item in
            IndexedGridItem(index: offset, item: item)
        }
    }

    private func applySortToWishlistItems(_ items: [WishlistItem], filters: BrowseCardGridFilters) -> [WishlistItem] {
        switch filters.sortBy {
        case .acquiredDateNewest, .random:
            return items
        case .cardName:
            return items.sorted {
                wishlistDisplayName(for: $0).localizedCaseInsensitiveCompare(wishlistDisplayName(for: $1)) == .orderedAscending
            }
        case .newestSet, .cardNumber:
            return sortWishlistItemsByNewestSet(items)
        case .price:
            return items.sorted { lhs, rhs in
                let lhsPrice = wishlistDisplayPrice(for: lhs)
                let rhsPrice = wishlistDisplayPrice(for: rhs)
                switch (lhsPrice, rhsPrice) {
                case let (l?, r?):
                    if l != r { return l > r }
                case (.some, nil):
                    return true
                case (nil, .some):
                    return false
                case (nil, nil):
                    break
                }
                return wishlistDisplayName(for: lhs).localizedCaseInsensitiveCompare(wishlistDisplayName(for: rhs)) == .orderedAscending
            }
        }
    }

    private var resolvedWishlistCards: [Card] {
        visibleWishlistItems.compactMap { wishlistCardsByID[$0.cardID] }
    }

    private var orderedWishlistCards: [Card] {
        indexedFilteredWishlistItemsForSelectedType.compactMap { wishlistCardsByID[$0.item.cardID] }
    }

    private var wishlistSignature: Int {
        var h = Hasher()
        h.combine(activeBrand.rawValue)
        for item in visibleWishlistItems { h.combine(item.cardID) }
        return h.finalize()
    }

    private func resolveWishlistCards() async {
        let cardItems = visibleWishlistItems.filter { sealedProduct(for: $0) == nil }
        let missingIDs = Array(Set(cardItems.map(\.cardID).filter { wishlistCardsByID[$0] == nil }))
        var next = wishlistCardsByID
        if !missingIDs.isEmpty {
            let loaded = await services.cardData.loadCards(
                masterCardIDs: missingIDs,
                catalogBrand: activeBrand
            )
            for card in loaded {
                next[card.masterCardId] = card
            }
        }
        wishlistCardsByID = next

        let cardsToPrice = cardItems.compactMap { next[$0.cardID] }
        await services.pricing.indexPricingForCards(cardsToPrice)

        var nextPrices: [String: Double] = [:]
        for item in cardItems {
            guard let card = next[item.cardID] else { continue }
            if let usd = services.pricing.cachedUsdPriceForVariantAndGrade(
                for: card,
                variantKey: item.variantKey,
                grade: "raw"
            ) {
                nextPrices[wishlistItemKey(item)] = usd
            }
        }
        wishlistPriceByItemKey = nextPrices

        ImagePrefetcher.shared.prefetchCardWindow(orderedWishlistCards, startingAt: 0, count: 24)
    }

    private func removeFromWishlist(_ item: WishlistItem) {
        modelContext.delete(item)
        try? modelContext.save()
    }

    private func sealedProduct(for item: WishlistItem) -> SealedProduct? {
        if let product = sealedProductByCollectionCardIDCache[item.cardID] {
            return product
        }
        if let productID = SealedProduct.parseCollectionProductID(item.cardID) {
            return sealedProductByIDCache[productID]
        }
        return nil
    }

    private func wishlistDisplayName(for item: WishlistItem) -> String {
        if let product = sealedProduct(for: item) {
            return product.name
        }
        return wishlistCardsByID[item.cardID]?.cardName ?? item.cardID
    }

    private func wishlistDisplayPrice(for item: WishlistItem) -> Double? {
        if let product = sealedProduct(for: item) {
            return services.sealedProducts.marketPriceUSD(for: product.id)
        }
        return wishlistPriceByItemKey[wishlistItemKey(item)]
    }

    private func collectionItemKey(_ item: CollectionItem) -> String {
        "\(item.cardID)|\(item.variantKey)|\(item.dateAcquired.timeIntervalSinceReferenceDate)"
    }

    private func collectionGradeKey(for item: CollectionItem) -> String {
        guard let company = item.gradingCompany else { return "raw" }
        switch company.uppercased() {
        case "PSA": return "psa10"
        case "ACE": return "ace10"
        default: return "raw"
        }
    }

    private func collectionGradeLabel(for item: CollectionItem) -> String? {
        guard let company = item.gradingCompany, let grade = item.grade else { return nil }
        return "\(company) \(grade)"
    }

    private func wishlistItemKey(_ item: WishlistItem) -> String {
        "\(item.cardID)|\(item.variantKey)|\(item.dateAdded.timeIntervalSinceReferenceDate)"
    }

    private func comparePricedItems(
        lhsPrice: Double?,
        rhsPrice: Double?,
        lhsCard: Card?,
        rhsCard: Card?
    ) -> Bool {
        switch (lhsPrice, rhsPrice) {
        case let (l?, r?):
            if l != r { return l > r }
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        case (nil, nil):
            break
        }

        let lhsName = lhsCard?.cardName ?? ""
        let rhsName = rhsCard?.cardName ?? ""
        if lhsName != rhsName {
            return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
        }

        let lhsSetCode = lhsCard?.setCode ?? ""
        let rhsSetCode = rhsCard?.setCode ?? ""
        if lhsSetCode != rhsSetCode {
            return lhsSetCode.localizedStandardCompare(rhsSetCode) == .orderedAscending
        }

        let lhsNumber = lhsCard?.cardNumber ?? ""
        let rhsNumber = rhsCard?.cardNumber ?? ""
        return lhsNumber.localizedStandardCompare(rhsNumber) == .orderedAscending
    }

    private func releaseDateSortKey(
        for item: CollectionItem,
        card: Card?,
        releaseDateBySetCode: [String: String]
    ) -> String {
        if let product = sealedProduct(for: item) {
            guard let releaseDate = product.releaseDate else { return "" }
            return Self.sealedReleaseDateSortFormatter.string(from: releaseDate)
        }
        guard let card else { return "" }
        return releaseDateBySetCode[card.setCode] ?? ""
    }

    private func releaseDateSortKey(
        for item: WishlistItem,
        card: Card?,
        releaseDateBySetCode: [String: String]
    ) -> String {
        if let product = sealedProduct(for: item) {
            guard let releaseDate = product.releaseDate else { return "" }
            return Self.sealedReleaseDateSortFormatter.string(from: releaseDate)
        }
        guard let card else { return "" }
        return releaseDateBySetCode[card.setCode] ?? ""
    }

    private func sortCollectionItemsByNewestSet(_ items: [CollectionItem]) -> [CollectionItem] {
        guard !items.isEmpty else { return items }
        let releaseDateBySetCode = buildSetReleaseDateByCode()
        let keyed = items.map { item -> (item: CollectionItem, releaseDateKey: String, setCode: String, cardNumber: String, displayName: String) in
            let card = cardsByCardID[item.cardID]
            return (
                item: item,
                releaseDateKey: releaseDateSortKey(for: item, card: card, releaseDateBySetCode: releaseDateBySetCode),
                setCode: card?.setCode ?? "",
                cardNumber: card?.cardNumber ?? "",
                displayName: collectionDisplayName(for: item)
            )
        }
        return keyed.sorted { lhs, rhs in
            compareNewestSetOrdering(
                lhsReleaseDateKey: lhs.releaseDateKey,
                rhsReleaseDateKey: rhs.releaseDateKey,
                lhsSetCode: lhs.setCode,
                rhsSetCode: rhs.setCode,
                lhsCardNumber: lhs.cardNumber,
                rhsCardNumber: rhs.cardNumber,
                lhsDisplayName: lhs.displayName,
                rhsDisplayName: rhs.displayName,
                lhsStableID: lhs.item.cardID,
                rhsStableID: rhs.item.cardID
            )
        }.map(\.item)
    }

    private func sortWishlistItemsByNewestSet(_ items: [WishlistItem]) -> [WishlistItem] {
        guard !items.isEmpty else { return items }
        let releaseDateBySetCode = buildSetReleaseDateByCode()
        let keyed = items.map { item -> (item: WishlistItem, releaseDateKey: String, setCode: String, cardNumber: String, displayName: String) in
            let card = wishlistCardsByID[item.cardID]
            return (
                item: item,
                releaseDateKey: releaseDateSortKey(for: item, card: card, releaseDateBySetCode: releaseDateBySetCode),
                setCode: card?.setCode ?? "",
                cardNumber: card?.cardNumber ?? "",
                displayName: wishlistDisplayName(for: item)
            )
        }
        return keyed.sorted { lhs, rhs in
            compareNewestSetOrdering(
                lhsReleaseDateKey: lhs.releaseDateKey,
                rhsReleaseDateKey: rhs.releaseDateKey,
                lhsSetCode: lhs.setCode,
                rhsSetCode: rhs.setCode,
                lhsCardNumber: lhs.cardNumber,
                rhsCardNumber: rhs.cardNumber,
                lhsDisplayName: lhs.displayName,
                rhsDisplayName: rhs.displayName,
                lhsStableID: lhs.item.cardID,
                rhsStableID: rhs.item.cardID
            )
        }.map(\.item)
    }

    private func compareNewestSetOrdering(
        lhsReleaseDateKey: String,
        rhsReleaseDateKey: String,
        lhsSetCode: String?,
        rhsSetCode: String?,
        lhsCardNumber: String?,
        rhsCardNumber: String?,
        lhsDisplayName: String,
        rhsDisplayName: String,
        lhsStableID: String,
        rhsStableID: String
    ) -> Bool {
        if lhsReleaseDateKey != rhsReleaseDateKey {
            return lhsReleaseDateKey > rhsReleaseDateKey
        }

        let lhsResolvedSetCode = lhsSetCode ?? ""
        let rhsResolvedSetCode = rhsSetCode ?? ""
        if lhsResolvedSetCode != rhsResolvedSetCode {
            return lhsResolvedSetCode.localizedStandardCompare(rhsResolvedSetCode) == .orderedAscending
        }

        let lhsResolvedCardNumber = lhsCardNumber ?? ""
        let rhsResolvedCardNumber = rhsCardNumber ?? ""
        if lhsResolvedCardNumber != rhsResolvedCardNumber {
            return lhsResolvedCardNumber.localizedStandardCompare(rhsResolvedCardNumber) == .orderedAscending
        }

        if lhsDisplayName != rhsDisplayName {
            return lhsDisplayName.localizedCaseInsensitiveCompare(rhsDisplayName) == .orderedAscending
        }

        return lhsStableID.localizedStandardCompare(rhsStableID) == .orderedAscending
    }

    // MARK: - Empty State

    private func emptyState(title: String, image: String, description: String) -> some View {
        ContentUnavailableView(title, systemImage: image, description: Text(description))
            .frame(minHeight: 280)
            .padding(.horizontal)
    }
}

private struct CollectionOpenSealedSession: Identifiable {
    let id = UUID()
    let item: CollectionItem
    let productName: String
}

// MARK: - Segment Enum
enum CollectSegment: String, CaseIterable, Identifiable {
    case collection
    case wishlist

    var id: String { rawValue }

    var title: String {
        switch self {
        case .collection: return "Collection"
        case .wishlist:   return "Wishlist"
        }
    }
}

enum CollectContentTypeTab: String, CaseIterable, Identifiable {
    case cards
    case products

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cards: return "Cards"
        case .products: return "Products"
        }
    }
}

private struct IndexedGridItem<Item: Identifiable>: Identifiable {
    let index: Int
    let item: Item

    var id: Item.ID { item.id }
}
