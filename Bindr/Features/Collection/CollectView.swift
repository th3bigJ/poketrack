import SwiftData
import SwiftUI

/// Combined Collection + Wishlist view with segmented toggle at top.
struct CollectView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(\.presentCard) private var presentCard
    @Environment(\.presentCardAtIndex) private var presentCardAtIndex
    @Environment(\.rootFloatingChromeInset) private var rootFloatingChromeInset

    // MARK: - Collection State
    @Query(sort: \CollectionItem.dateAcquired, order: .reverse) private var collectionItems: [CollectionItem]
    @State private var cardsByCardID: [String: Card] = [:]
    @State private var collectionPriceByItemKey: [String: Double] = [:]
    @State private var selectedSealedProduct: SealedProduct?
    @State private var cachedSetNameByBrandAndCode: [String: String] = [:]
    @State private var sealedProductByIDCache: [Int: SealedProduct] = [:]
    @State private var sealedProductByCollectionCardIDCache: [String: SealedProduct] = [:]
    @State private var collectionFilteredItemsForSelectedTypeCache: [CollectionItem] = []
    @State private var collectionDisplayedItems: [CollectionItem] = []
    @State private var collectionDisplayedCards: [Card] = []
    @State private var collectionNextIndex = 0
    @State private var isLoadingMoreCollectionItems = false
    @State private var markAsSession: CollectionMarkAsSession?
    @State private var openSealedSession: CollectionOpenSealedSession?

    // MARK: - Wishlist State
    @Query(sort: \WishlistItem.dateAdded, order: .reverse) private var wishlistItems: [WishlistItem]
    @State private var wishlistCardsByID: [String: Card] = [:]
    @State private var wishlistPriceByItemKey: [String: Double] = [:]

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

    private var activeBrand: TCGBrand {
        selectedBrand ?? services.brandSettings.selectedCatalogBrand
    }

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

    private var setReleaseDateByCode: [String: String] {
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

    private var sealedProductsSignature: String {
        services.sealedProducts.products.map { "\($0.id)" }.joined(separator: ",")
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
        Group {
            if selectedSegment == .folders {
                VStack(spacing: 0) {
                    Color.clear.frame(height: rootFloatingChromeInset)

                    VStack(spacing: 10) {
                        if showsSegmentedControl {
                            segmentedControl.padding(.horizontal, 16)
                        }
                    }
                    .padding(.bottom, 10)

                    contentView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
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
            }
        }
        .navigationDestination(for: CardFolder.self) { folder in
            FolderContentsView(folder: folder)
        }
        .scrollDismissesKeyboard(.immediately)
        .toolbar(hidesNavigationBar ? .hidden : .visible, for: .navigationBar)
        .onAppear {
            services.setupCollectionLedger(modelContext: modelContext)
            services.setupWishlist(modelContext: modelContext)
            services.sealedProducts.loadFromLocalIfAvailable()
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
            refreshSetNameCache()
        }
        .task(id: sealedProductsSignature) {
            refreshSealedProductCaches()
        }
        .task(id: collectionShareSyncSignature) {
            services.socialShare.scheduleAutoSyncCollection(items: collectionItems)
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
        .sheet(item: $markAsSession) { session in
            CollectionMarkAsSheet(
                item: session.item,
                cardDisplayName: session.cardDisplayName,
                initialKind: session.initialKind
            )
            .environment(services)
        }
        .sheet(item: $openSealedSession) { session in
            OpenSealedCollectionItemSheet(item: session.item, productName: session.productName)
                .environment(services)
        }
        .onChange(of: selectedSealedProduct?.id) { _, productID in
            services.isSealedDetailPresentationActive = (productID != nil)
        }
    }

    private func refreshSetNameCache() {
        var map: [String: String] = [:]
        for brand in services.brandSettings.enabledBrands {
            guard let sets = try? CatalogStore.shared.fetchAllSets(for: brand) else { continue }
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
        let itemLabel = selectedContentTypeTab == .cards ? "cards" : "sealed"
        switch selectedSegment {
        case .collection:
            return "Search \(formattedActiveFilteredCount) \(itemLabel) in collection"
        case .wishlist:
            return "Search \(formattedActiveFilteredCount) \(itemLabel) in wishlist"
        case .folders:
            return ""
        }
    }

    private var activeQueryBinding: Binding<String> {
        switch selectedSegment {
        case .collection: return $collectionQuery
        case .wishlist:   return $wishlistQuery
        case .folders:    return $collectionQuery
        }
    }

    private var contentTypeChips: some View {
        HStack(spacing: 6) {
            contentTypeChip(for: .cards, icon: "square.stack.3d.up")
            contentTypeChip(for: .sealed, icon: "shippingbox")
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
                    .fill(isSelected ? services.theme.accentColor : Color.clear)
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
        case .collection: return collectionFilteredItemsForSelectedTypeCache.count
        case .wishlist:   return filteredWishlistItemsForSelectedType.count
        case .folders:    return 0
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
        case .folders:    foldersContent
        }
    }

    @ViewBuilder
    private var foldersContent: some View {
        FoldersListView()
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
        } else if collectionFilteredItemsForSelectedTypeCache.isEmpty {
            emptyState(
                title: "No matching \(selectedContentTypeTab.title.lowercased())",
                image: "magnifyingglass",
                description: selectedContentTypeTab == .cards
                    ? "Try a different card name, set code, or number."
                    : "Try a different product name, series, or year."
            )
        } else {
            EagerVGrid(items: indexedDisplayedCollectionItems, columns: safeColumnCount, spacing: 12) { indexed in
                collectionCell(for: indexed.item, at: indexed.index)
                    .onAppear {
                        guard selectedContentTypeTab == .cards else { return }
                        ImagePrefetcher.shared.prefetchCardWindow(collectionDisplayedCards, startingAt: indexed.index + 1)
                        guard indexed.index >= max(collectionDisplayedItems.count - safeColumnCount, 0) else { return }
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
    private func collectionCell(for item: CollectionItem, at index: Int) -> some View {
        if let product = sealedProduct(for: item) {
            Button { selectedSealedProduct = product } label: {
                SealedProductGridCell(
                    product: product,
                    gridOptions: gridOptions,
                    priceUSD: services.sealedProducts.marketPriceUSD(for: product.id),
                    isOwned: item.quantity > 0,
                    isWishlisted: wishlistedSealedCollectionCardIDs.contains(product.collectionCardID),
                    ownedCountBadge: item.quantity
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(CardCellButtonStyle())
            .contextMenu {
                Menu {
                    Button {
                        openSealedSession = CollectionOpenSealedSession(item: item, productName: product.name)
                    } label: {
                        Label("Opened", systemImage: "shippingbox")
                    }
                    Divider()
                    markAsButton(kind: .sold, item: item, displayName: product.name)
                    markAsButton(kind: .traded, item: item, displayName: product.name)
                    markAsButton(kind: .gifted, item: item, displayName: product.name)
                    markAsButton(kind: .lost, item: item, displayName: product.name)
                    markAsButton(kind: .damaged, item: item, displayName: product.name)
                } label: {
                    Label("Mark as", systemImage: "tag")
                }
            }
            .accessibilityLabel("\(product.name), \(item.quantity) owned")
        } else if let card = cardsByCardID[item.cardID] {
            Button { presentCardAtIndex(collectionDisplayedCards, index) } label: {
                CardGridCell(
                    card: card,
                    gridOptions: gridOptions,
                    setName: setName(for: card),
                    ownedCountBadge: item.quantity,
                    overridePrice: collectionPriceByItemKey[collectionItemKey(item)],
                    gradeLabel: collectionGradeLabel(for: item)
                )
            }
            .buttonStyle(CardCellButtonStyle())
            .contextMenu {
                Menu {
                    markAsButton(kind: .sold, item: item, card: card)
                    markAsButton(kind: .traded, item: item, card: card)
                    markAsButton(kind: .gifted, item: item, card: card)
                    markAsButton(kind: .lost, item: item, card: card)
                    markAsButton(kind: .damaged, item: item, card: card)
                } label: {
                    Label("Mark as", systemImage: "tag")
                }
            }
            .accessibilityLabel("\(card.cardName), \(item.quantity) copies, \(item.variantKey)")
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

    private var filteredCollectionItems: [CollectionItem] {
        var items = visibleCollectionItems
        if collectionFilters.showDuplicates {
            items = items.filter { $0.quantity >= 2 }
        }
        let trimmedQuery = collectionQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasCardFieldFilters = collectionFilters.hasActiveCardFieldFilters
        let hasSealedFieldFilters = collectionFilters.hasActiveSealedFieldFilters
        let needsCardFiltering = hasCardFieldFilters || !trimmedQuery.isEmpty
        let filteredIDs: Set<String> = {
            guard needsCardFiltering else { return [] }
            let filteredCards = filterBrowseCards(
                resolvedCollectionCards, query: collectionQuery, filters: collectionFilters,
                ownedCardIDs: Set(items.map { $0.cardID }),
                brand: activeBrand, sets: services.cardData.sets
            )
            return Set(filteredCards.map { $0.masterCardId })
        }()
        if needsCardFiltering || hasSealedFieldFilters {
            let normalizedQuery = trimmedQuery.lowercased()
            items = items.filter { item in
                if let product = sealedProduct(for: item) {
                    guard hasCardFieldFilters == false else { return false }
                    guard sealedProductMatchesSelectedTypes(product.type, selectedOptionIDs: collectionFilters.sealedProductTypes) else {
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
            return selectedContentTypeTab == .sealed ? isSealed : !isSealed
        }
    }

    private var indexedDisplayedCollectionItems: [IndexedGridItem<CollectionItem>] {
        Array(collectionDisplayedItems.enumerated()).map { offset, item in
            IndexedGridItem(index: offset, item: item)
        }
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
            return items.sorted { lhs, rhs in
                compareNewestSetOrdering(
                    lhsReleaseDateKey: releaseDateSortKey(for: lhs, cardLookup: cardsByCardID),
                    rhsReleaseDateKey: releaseDateSortKey(for: rhs, cardLookup: cardsByCardID),
                    lhsSetCode: cardsByCardID[lhs.cardID]?.setCode,
                    rhsSetCode: cardsByCardID[rhs.cardID]?.setCode,
                    lhsCardNumber: cardsByCardID[lhs.cardID]?.cardNumber,
                    rhsCardNumber: cardsByCardID[rhs.cardID]?.cardNumber,
                    lhsDisplayName: collectionDisplayName(for: lhs),
                    rhsDisplayName: collectionDisplayName(for: rhs),
                    lhsStableID: lhs.cardID,
                    rhsStableID: rhs.cardID
                )
            }
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

    private var collectionSignature: String {
        let brandKey = activeBrand.rawValue
        return visibleCollectionItems.map { "\($0.cardID)|\($0.variantKey)|\($0.quantity)" }.joined(separator: "§") + "|" + brandKey
    }

    private var collectionShareSyncSignature: String {
        collectionItems
            .map { "\($0.cardID)|\($0.variantKey)|\($0.quantity)|\($0.notes)" }
            .sorted()
            .joined(separator: ";")
    }

    private func resolveCollectionCards() async {
        var next = cardsByCardID
        for item in visibleCollectionItems {
            if sealedProduct(for: item) != nil { continue }
            if next[item.cardID] != nil { continue }
            if let c = await services.cardData.loadCard(masterCardId: item.cardID) { next[item.cardID] = c }
        }
        cardsByCardID = next

        var nextPrices: [String: Double] = [:]
        for item in visibleCollectionItems {
            guard let card = next[item.cardID] else { continue }
            let gradeKey = collectionGradeKey(for: item)
            if let usd = await services.pricing.usdPriceForVariantAndGrade(for: card, variantKey: item.variantKey, grade: gradeKey) {
                nextPrices[collectionItemKey(item)] = usd
            }
        }
        collectionPriceByItemKey = nextPrices

        let cards = collectionDisplayedCards
        ImagePrefetcher.shared.prefetchCardWindow(cards, startingAt: 0, count: 24)
        collectFilterEnergyOptions = cardEnergyOptions(cards)
        collectFilterRarityOptions = cardRarityOptions(cards)
        collectFilterTrainerTypeOptions = cardTrainerTypeOptions(cards)
        refreshCollectionFeed()
    }

    private func refreshCollectionFeed() {
        let filtered = filteredCollectionItemsForSelectedType
        collectionFilteredItemsForSelectedTypeCache = filtered
        let initialEnd = min(Self.collectionInitialBatchSize, filtered.count)
        collectionDisplayedItems = Array(filtered.prefix(initialEnd))
        collectionNextIndex = initialEnd
        collectionDisplayedCards = collectionDisplayedItems.compactMap { cardsByCardID[$0.cardID] }
    }

    @MainActor
    private func loadMoreCollectionItemsIfNeeded() async {
        guard !isLoadingMoreCollectionItems else { return }
        guard collectionNextIndex < collectionFilteredItemsForSelectedTypeCache.count else { return }
        isLoadingMoreCollectionItems = true
        defer { isLoadingMoreCollectionItems = false }
        let end = min(collectionNextIndex + Self.collectionPageSize, collectionFilteredItemsForSelectedTypeCache.count)
        let more = collectionFilteredItemsForSelectedTypeCache[collectionNextIndex..<end]
        collectionDisplayedItems.append(contentsOf: more)
        collectionNextIndex = end
        collectionDisplayedCards = collectionDisplayedItems.compactMap { cardsByCardID[$0.cardID] }
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
                    isWishlisted: true
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
        let hasSealedFieldFilters = wishlistFilters.hasActiveSealedFieldFilters
        let needsCardFiltering = hasCardFieldFilters || !trimmedQuery.isEmpty
        let filteredIDs: Set<String> = {
            guard needsCardFiltering else { return [] }
            let filteredCards = filterBrowseCards(
                resolvedWishlistCards, query: wishlistQuery, filters: wishlistFilters,
                ownedCardIDs: [], brand: activeBrand, sets: services.cardData.sets
            )
            return Set(filteredCards.map { $0.masterCardId })
        }()
        if needsCardFiltering || hasSealedFieldFilters {
            let normalizedQuery = trimmedQuery.lowercased()
            items = items.filter { item in
                if let product = sealedProduct(for: item) {
                    guard hasCardFieldFilters == false else { return false }
                    guard sealedProductMatchesSelectedTypes(product.type, selectedOptionIDs: wishlistFilters.sealedProductTypes) else {
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
            return selectedContentTypeTab == .sealed ? isSealed : !isSealed
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
            return items.sorted { lhs, rhs in
                compareNewestSetOrdering(
                    lhsReleaseDateKey: releaseDateSortKey(for: lhs, cardLookup: wishlistCardsByID),
                    rhsReleaseDateKey: releaseDateSortKey(for: rhs, cardLookup: wishlistCardsByID),
                    lhsSetCode: wishlistCardsByID[lhs.cardID]?.setCode,
                    rhsSetCode: wishlistCardsByID[rhs.cardID]?.setCode,
                    lhsCardNumber: wishlistCardsByID[lhs.cardID]?.cardNumber,
                    rhsCardNumber: wishlistCardsByID[rhs.cardID]?.cardNumber,
                    lhsDisplayName: wishlistDisplayName(for: lhs),
                    rhsDisplayName: wishlistDisplayName(for: rhs),
                    lhsStableID: lhs.cardID,
                    rhsStableID: rhs.cardID
                )
            }
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

    private var wishlistSignature: String {
        let brandKey = activeBrand.rawValue
        return visibleWishlistItems.map { $0.cardID }.joined(separator: "§") + "|" + brandKey
    }

    private func resolveWishlistCards() async {
        var next = wishlistCardsByID
        for item in visibleWishlistItems {
            if sealedProduct(for: item) != nil { continue }
            if next[item.cardID] != nil { continue }
            if let c = await services.cardData.loadCard(masterCardId: item.cardID) { next[item.cardID] = c }
        }
        wishlistCardsByID = next

        var nextPrices: [String: Double] = [:]
        for item in visibleWishlistItems {
            guard let card = next[item.cardID] else { continue }
            if let usd = await services.pricing.usdPriceForVariant(for: card, variantKey: item.variantKey) {
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

    @ViewBuilder
    private func markAsButton(kind: CollectionDispositionKind, item: CollectionItem, card: Card) -> some View {
        markAsButton(kind: kind, item: item, displayName: card.cardName)
    }

    @ViewBuilder
    private func markAsButton(kind: CollectionDispositionKind, item: CollectionItem, displayName: String) -> some View {
        Button {
            markAsSession = CollectionMarkAsSession(
                item: item,
                cardDisplayName: displayName,
                initialKind: kind
            )
        } label: {
            Label(kind.title, systemImage: markAsSymbol(for: kind))
        }
    }

    private func markAsSymbol(for kind: CollectionDispositionKind) -> String {
        switch kind {
        case .sold:
            return "dollarsign.circle"
        case .traded:
            return "arrow.left.arrow.right.circle"
        case .gifted:
            return "gift"
        case .lost:
            return "questionmark.circle"
        case .damaged:
            return "exclamationmark.triangle"
        }
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

    private func releaseDateSortKey(for item: CollectionItem, cardLookup: [String: Card]) -> String {
        if let product = sealedProduct(for: item) {
            guard let releaseDate = product.releaseDate else { return "" }
            return Self.sealedReleaseDateSortFormatter.string(from: releaseDate)
        }
        guard let card = cardLookup[item.cardID] else { return "" }
        return setReleaseDateByCode[card.setCode] ?? ""
    }

    private func releaseDateSortKey(for item: WishlistItem, cardLookup: [String: Card]) -> String {
        if let product = sealedProduct(for: item) {
            guard let releaseDate = product.releaseDate else { return "" }
            return Self.sealedReleaseDateSortFormatter.string(from: releaseDate)
        }
        guard let card = cardLookup[item.cardID] else { return "" }
        return setReleaseDateByCode[card.setCode] ?? ""
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

private struct CollectionMarkAsSession: Identifiable {
    let id = UUID()
    let item: CollectionItem
    let cardDisplayName: String
    let initialKind: CollectionDispositionKind
}

private struct CollectionOpenSealedSession: Identifiable {
    let id = UUID()
    let item: CollectionItem
    let productName: String
}

private struct CollectionMarkAsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services
    @Environment(\.colorScheme) private var colorScheme

    let item: CollectionItem
    let cardDisplayName: String
    let initialKind: CollectionDispositionKind

    @State private var dispositionKind: CollectionDispositionKind
    @State private var quantity: Int = 1
    @State private var priceText: String = ""
    @State private var counterparty: String = ""
    @State private var notes: String = ""
    @State private var errorMessage: String?

    init(item: CollectionItem, cardDisplayName: String, initialKind: CollectionDispositionKind) {
        self.item = item
        self.cardDisplayName = cardDisplayName
        self.initialKind = initialKind
        _dispositionKind = State(initialValue: initialKind)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(displayVariant(item.variantKey))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Picker("Status", selection: $dispositionKind) {
                        ForEach(CollectionDispositionKind.allCases, id: \.self) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Stepper("Quantity: \(quantity)", value: $quantity, in: 1...max(item.quantity, 1))
                }

                if dispositionKind == .sold {
                    Section {
                        TextField("Sold price per card", text: $priceText)
                            .keyboardType(.decimalPad)
                    }
                }

                Section {
                    TextField(counterpartyLabel, text: $counterparty)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .tint(colorScheme == .dark ? .white : .black)
            .navigationTitle("Mark Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
                }
            }
            .onAppear {
                quantity = min(max(item.quantity, 1), quantity)
                services.setupCollectionLedger(modelContext: modelContext)
            }
        }
    }

    private var counterpartyLabel: String {
        switch dispositionKind {
        case .sold: return "Sold to"
        case .traded: return "Traded with"
        case .gifted: return "Gifted to"
        case .lost: return "Lost details"
        case .damaged: return "Damage details"
        }
    }

    private func save() {
        errorMessage = nil
        guard let ledger = services.collectionLedger else {
            errorMessage = "Collection isn’t ready. Try again."
            return
        }

        do {
            try ledger.recordSingleCardDisposition(
                item: item,
                kind: dispositionKind,
                quantity: quantity,
                currencyCode: services.priceDisplay.currency == .gbp ? "GBP" : "USD",
                cardDisplayName: cardDisplayName,
                unitPrice: try parsedOptionalPrice(priceText),
                counterparty: counterparty,
                notes: notes
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func parsedOptionalPrice(_ text: String) throws -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let value = Double(trimmed.replacingOccurrences(of: ",", with: ".")) else {
            throw CollectionMarkAsSheetError.invalidPrice
        }
        return value
    }

    private func displayVariant(_ variantKey: String) -> String {
        let normalized = variantKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "Normal" }
        let spaced = normalized
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
        return spaced
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }
}

private enum CollectionMarkAsSheetError: LocalizedError {
    case invalidPrice

    var errorDescription: String? {
        switch self {
        case .invalidPrice:
            return "Enter a valid price."
        }
    }
}

// MARK: - Segment Enum
enum CollectSegment: String, CaseIterable, Identifiable {
    case collection
    case wishlist
    case folders

    var id: String { rawValue }

    var title: String {
        switch self {
        case .collection: return "Collection"
        case .wishlist:   return "Wishlist"
        case .folders:    return "Folders"
        }
    }
}

enum CollectContentTypeTab: String, CaseIterable, Identifiable {
    case cards
    case sealed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cards: return "Cards"
        case .sealed: return "Sealed"
        }
    }
}

private struct IndexedGridItem<Item: Identifiable>: Identifiable {
    let index: Int
    let item: Item

    var id: Item.ID { item.id }
}
