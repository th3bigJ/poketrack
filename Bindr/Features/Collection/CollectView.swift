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
    @State private var collectionItems: [CollectionItem] = []
    @State private var isLoadingCollectionItems = true
    @State private var cardsByCardID: [String: Card] = [:]
    @State private var collectionPriceByItemKey: [String: Double] = [:]
    @State private var collectionSortPriceByCardID: [String: Double] = [:]
    @State private var collectionResolvedPriceItemKeys: Set<String> = []
    @State private var isResolvingCollectionPrices = false
    @State private var selectedSealedProduct: SealedProduct?
    @State private var cachedSetNameByBrandAndCode: [String: String] = [:]
    @State private var sealedProductByIDCache: [Int: SealedProduct] = [:]
    @State private var sealedProductByCollectionCardIDCache: [String: SealedProduct] = [:]
    @State private var collectionFilteredItemsForSelectedTypeCache: [CollectionItem] = []
    @State private var collectionDisplayedItems: [CollectionItem] = []
    @State private var collectionDisplayedCards: [Card] = []
    @State private var collectionNextIndex = 0
    @State private var isLoadingMoreCollectionItems = false
    @State private var collectionFeedDebounceTask: Task<Void, Never>? = nil
    @State private var wishlistFeedDebounceTask: Task<Void, Never>? = nil
    @State private var openSealedSession: CollectionOpenSealedSession?
    @State private var cachedVisibleCollectionItems: [CollectionItem] = []
    @State private var cachedVisibleCollectionCardItems: [CollectionItem] = []
    @State private var cachedVisibleWishlistItems: [WishlistItem] = []
    @State private var cachedCollectionOwnedCardIDs: Set<String> = []
    @State private var wishlistFilteredItemsForSelectedTypeCache: [WishlistItem] = []
    @State private var wishlistOrderedCardsCache: [Card] = []

    // MARK: - Wishlist State
    @State private var wishlistItems: [WishlistItem] = []
    @State private var isLoadingWishlistItems = true
    @State private var wishlistCardsByID: [String: Card] = [:]
    @State private var wishlistPriceByItemKey: [String: Double] = [:]
    @State private var wishlistSortPriceByCardID: [String: Double] = [:]
    @State private var wishlistResolvedPriceItemKeys: Set<String> = []
    @State private var isResolvingWishlistPrices = false

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
    @State private var cachedWishlistedSealedCollectionCardIDs: Set<String> = []
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

    private var visibleCollectionItems: [CollectionItem] { cachedVisibleCollectionItems }

    private var visibleCollectionCardItems: [CollectionItem] { cachedVisibleCollectionCardItems }

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

        if collectionFilters.sortBy == .price, isResolvingCollectionPrices {
            return true
        }

        return false
    }

    private var wishlistSortNeedsResolvedCards: Bool {
        switch wishlistFilters.sortBy {
        case .cardName, .newestSet, .cardNumber, .price:
            return true
        case .acquiredDateNewest, .random:
            return false
        }
    }

    private var wishlistHasCardFilterDependencies: Bool {
        let trimmedQuery = wishlistQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedQuery.isEmpty || wishlistFilters.hasActiveCardFieldFilters
    }

    private var isWishlistWaitingForCurrentSortOrFilters: Bool {
        guard selectedContentTypeTab == .cards else { return false }
        guard selectedSegment == .wishlist else { return false }
        let cardItems = visibleWishlistItems.filter { sealedProduct(for: $0) == nil }
        guard !cardItems.isEmpty else { return false }

        if wishlistSortNeedsResolvedCards || wishlistHasCardFilterDependencies {
            let missingCardData = cardItems.contains { wishlistCardsByID[$0.cardID] == nil }
            if missingCardData { return true }
        }

        if wishlistFilters.sortBy == .price, isResolvingWishlistPrices {
            return true
        }

        return false
    }

    private var sealedProductsSignature: Int { services.sealedProducts.products.count }

    private var wishlistedSealedCollectionCardIDs: Set<String> { cachedWishlistedSealedCollectionCardIDs }

    private func refreshWishlistedSealedCollectionCardIDs() {
        cachedWishlistedSealedCollectionCardIDs = Set(wishlistItems.compactMap { item in
            guard SealedProduct.parseCollectionProductID(item.cardID) != nil else { return nil }
            return item.cardID
        })
    }

    private var visibleWishlistItems: [WishlistItem] { cachedVisibleWishlistItems }

    var body: some View {
        composedContent
    }

    private var baseContent: some View {
        scrollContent
            .refreshable {
                await refreshCollectContent()
            }
            .bindrPageBackground()
            .scrollDismissesKeyboard(.immediately)
            .toolbar(hidesNavigationBar ? .hidden : .visible, for: .navigationBar)
            .onAppear {
                handlePrimaryAppear()
            }
    }

    private var composedContent: AnyView {
        let taskWrapped = applyTaskModifiers(to: AnyView(baseContent))
        let observerWrapped = applyObserverModifiers(to: taskWrapped)
        return applySheetModifiers(to: observerWrapped)
    }

    private func applyTaskModifiers(to content: AnyView) -> AnyView {
        AnyView(
            content
                .task {
                    await refreshSealedProductsIfNeeded()
                }
                .task(id: services.collectionInventoryRevision) {
                    await reloadCollectionItems()
                }
                .task(id: services.wishlistInventoryRevision) {
                    await reloadWishlistItems()
                }
                .task(id: collectionResolveTaskKey) {
                    await resolveCollectionCards()
                }
                .task(id: wishlistResolveTaskKey) {
                    await resolveWishlistCards()
                }
                .task(id: setNameCacheKey) {
                    await refreshSetNameCache()
                }
                .task(id: sealedProductsSignature) {
                    handleSealedProductsSignatureChange()
                }
        )
    }

    private func applyObserverModifiers(to content: AnyView) -> AnyView {
        AnyView(
            content
                .onAppear {
                    handleSecondaryAppear()
                }
                .onChange(of: services.brandSettings.selectedCatalogBrand) { _, brand in
                    handleSelectedCatalogBrandChange(brand)
                }
                .onChange(of: selectedBrand) { _, _ in
                    handleSelectedBrandChange()
                }
                .onChange(of: selectedContentTypeTab) { _, _ in
                    handleSelectedContentTypeTabChange()
                }
                .onChange(of: collectionQuery) { _, _ in scheduleCollectionFeedRefresh(requireResolvedPrices: true) }
                .onChange(of: collectionFilters) { _, _ in scheduleCollectionFeedRefresh(requireResolvedPrices: true) }
                .onChange(of: collectionPriceByItemKey) { _, _ in scheduleCollectionFeedRefresh(requireResolvedPrices: true) }
                .onChange(of: collectionSortPriceByCardID) { _, _ in scheduleCollectionFeedRefresh(requireResolvedPrices: true) }
                .onChange(of: cardsByCardID) { _, _ in scheduleCollectionFeedRefresh(requireResolvedPrices: true) }
                .onChange(of: sealedProductByCollectionCardIDCache) { _, _ in
                    handleSealedProductCacheChange()
                }
                .onChange(of: wishlistQuery) { _, _ in scheduleWishlistFeedRefresh(requireResolvedPrices: true) }
                .onChange(of: wishlistFilters) { _, _ in scheduleWishlistFeedRefresh(requireResolvedPrices: true) }
                .onChange(of: wishlistPriceByItemKey) { _, _ in scheduleWishlistFeedRefresh(requireResolvedPrices: true) }
                .onChange(of: wishlistSortPriceByCardID) { _, _ in scheduleWishlistFeedRefresh(requireResolvedPrices: true) }
                .onChange(of: wishlistCardsByID) { _, _ in scheduleWishlistFeedRefresh(requireResolvedPrices: true) }
                .onChange(of: selectedSealedProduct?.id) { _, productID in
                    handleSelectedSealedProductChange(productID)
                }
        )
    }

    private func applySheetModifiers(to content: AnyView) -> AnyView {
        AnyView(
            content
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
        )
    }

    private var scrollContent: some View {
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

    private func loadSealedProductsFromLocal() {
        Task {
            await services.sealedProducts.loadFromLocalIfAvailable()
        }
    }

    private func handlePrimaryAppear() {
        services.setupCollectionLedger(modelContext: modelContext)
        services.setupWishlist(modelContext: modelContext)
        loadSealedProductsFromLocal()
    }

    private func handleSecondaryAppear() {
        if selectedBrand != services.brandSettings.selectedCatalogBrand {
            selectedBrand = services.brandSettings.selectedCatalogBrand
        }
        refreshSealedProductCaches()
        refreshWishlistedSealedCollectionCardIDs()
        refreshVisibilityCaches()
        scheduleCollectionFeedRefresh()
        scheduleWishlistFeedRefresh()
    }

    private func handleSelectedCatalogBrandChange(_ brand: TCGBrand?) {
        selectedBrand = brand
    }

    private func handleSelectedBrandChange() {
        refreshVisibilityCaches()
        scheduleCollectionFeedRefresh()
        scheduleWishlistFeedRefresh()
    }

    private func handleSelectedContentTypeTabChange() {
        scheduleCollectionFeedRefresh()
        scheduleWishlistFeedRefresh()
    }

    private func handleSealedProductCacheChange() {
        scheduleCollectionFeedRefresh(requireResolvedPrices: true)
        scheduleWishlistFeedRefresh(requireResolvedPrices: true)
    }

    private func handleSelectedSealedProductChange(_ productID: Int?) {
        services.isSealedDetailPresentationActive = (productID != nil)
    }

    private func refreshSealedProductsIfNeeded() async {
        if services.sealedProducts.products.isEmpty {
            await services.sealedProducts.refreshFromNetworkAndStoreLocallyIfNeeded()
        }
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

    private func refreshVisibilityCaches() {
        let brand = activeBrand
        let visibleCollection = collectionItems.filter { TCGBrand.inferredFromMasterCardId($0.cardID) == brand }
        cachedVisibleCollectionItems = visibleCollection
        cachedVisibleCollectionCardItems = visibleCollection.filter { sealedProduct(for: $0) == nil }
        cachedCollectionOwnedCardIDs = Set(visibleCollection.map(\.cardID))
        cachedVisibleWishlistItems = wishlistItems.filter { TCGBrand.inferredFromMasterCardId($0.cardID) == brand }
    }

    private func handleSealedProductsSignatureChange() {
        refreshSealedProductCaches()
        refreshVisibilityCaches()
    }

    @MainActor
    private func reloadCollectionItems() async {
        isLoadingCollectionItems = true
        defer { isLoadingCollectionItems = false }

        let descriptor = FetchDescriptor<CollectionItem>(
            sortBy: [SortDescriptor(\.dateAcquired, order: .reverse)]
        )
        collectionItems = (try? modelContext.fetch(descriptor)) ?? []
        refreshVisibilityCaches()
    }

    @MainActor
    private func reloadWishlistItems() async {
        isLoadingWishlistItems = true
        defer { isLoadingWishlistItems = false }

        let descriptor = FetchDescriptor<WishlistItem>(
            sortBy: [SortDescriptor(\.dateAdded, order: .reverse)]
        )
        wishlistItems = (try? modelContext.fetch(descriptor)) ?? []
        services.wishlist?.loadItems()
        refreshWishlistedSealedCollectionCardIDs()
        refreshVisibilityCaches()
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
            .foregroundStyle(isSelected ? .white : .primary.opacity(0.85))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .glassFilterChipStyle(isSelected: isSelected, accentColor: services.theme.accentColor)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
    }

    private var activeFilteredCount: Int {
        switch selectedSegment {
        case .collection:
            if selectedContentTypeTab == .cards {
                return Set(collectionFilteredItemsForSelectedTypeCache.map(\.cardID)).count
            }
            return collectionFilteredItemsForSelectedTypeCache.count
        case .wishlist:
            if selectedContentTypeTab == .cards {
                return Set(wishlistFilteredItemsForSelectedTypeCache.map(\.cardID)).count
            }
            return wishlistFilteredItemsForSelectedTypeCache.count
        }
    }

    private static let activeFilteredCountFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    private var formattedActiveFilteredCount: String {
        Self.activeFilteredCountFormatter.string(from: NSNumber(value: activeFilteredCount)) ?? "\(activeFilteredCount)"
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
        if isLoadingCollectionItems && collectionItems.isEmpty {
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading collection...")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        } else if collectionItems.isEmpty {
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
        } else if collectionFilteredItemsForSelectedTypeCache.isEmpty {
            emptyState(
                title: "No matching \(selectedContentTypeTab.title.lowercased())",
                image: "magnifyingglass",
                description: selectedContentTypeTab == .cards
                    ? "Try a different card name, set code, or number."
                    : "Try a different product name, series, or year."
            )
        } else {
            EagerVGrid(items: indexedDisplayedCollectionItems, columns: safeColumnCount, spacing: BindrSpacing.cardGrid) { indexed in
                collectionCell(for: indexed.item, at: indexed.index)
                    .onAppear {
                        guard selectedContentTypeTab == .cards else { return }
                        ImagePrefetcher.shared.prefetchCardWindow(collectionDisplayedCards, startingAt: indexed.index + 1)
                        guard indexed.index >= max(collectionDisplayedItems.count - safeColumnCount, 0) else { return }
                        guard collectionFilters.sortBy != .price else { return }
                        Task { await loadMoreCollectionItemsIfNeeded() }
                    }
            }
            .padding(.horizontal, BindrSpacing.cardGridScreenInset)
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
                    isOwned: false,
                    isWishlisted: wishlistedSealedCollectionCardIDs.contains(product.collectionCardID),
                    ownedCountBadge: item.quantity > 1 ? item.quantity : nil
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
            .accessibilityLabel("\(product.name), \(item.quantity) owned")
        } else if let card = cardsByCardID[item.cardID] {
            Button {
                let tapTimeCards = collectionDisplayedItems.compactMap { cardsByCardID[$0.cardID] }
                let cardIndex = tapTimeCards.firstIndex(where: { $0.masterCardId == card.masterCardId }) ?? 0
                presentCardAtIndex(tapTimeCards, cardIndex)
            } label: {
                CardGridCell(
                    card: card,
                    services: services,
                    colorScheme: colorScheme,
                    accentColor: services.theme.accentColor,
                    gridOptions: gridOptions,
                    setName: setName(for: card),
                    ownedCountBadge: item.quantity,
                    variantLabel: collectionVariantLabel(for: item),
                    overridePrice: collectionDisplayPrice(for: item),
                    gradeLabel: collectionGradeLabel(for: item)
                )
            }
            .buttonStyle(CardCellButtonStyle())
            .contextMenu {
                Button {
                    pendingCardContextRequest = CardContextActionRequest(
                        card: card,
                        availableVariantKeys: [item.variantKey],
                        initialVariantKey: item.variantKey,
                        ownedQuantity: item.quantity,
                        collectionItem: item,
                        initialAction: .collection
                    )
                } label: {
                    Label("Add to Collection", systemImage: "books.vertical")
                }
                Button {
                    pendingCardContextRequest = CardContextActionRequest(
                        card: card,
                        availableVariantKeys: [item.variantKey],
                        initialVariantKey: item.variantKey,
                        ownedQuantity: item.quantity,
                        collectionItem: item,
                        initialAction: .wishlist
                    )
                } label: {
                    Label("Add to Wishlist", systemImage: "heart")
                }
                Button {
                    pendingCardContextRequest = CardContextActionRequest(
                        card: card,
                        availableVariantKeys: [item.variantKey],
                        initialVariantKey: item.variantKey,
                        ownedQuantity: item.quantity,
                        collectionItem: item,
                        initialAction: .markAs
                    )
                } label: {
                    Label("Mark as", systemImage: "tag")
                }
            }
            .accessibilityLabel("\(card.cardName), \(item.quantity) copies, \(itemVariantLabel(item))")
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

    private func collectionVariantLabel(for item: CollectionItem) -> String? {
        guard sealedProduct(for: item) == nil else { return nil }
        guard gridOptions.showOwned else { return nil }
        if CollectionGridGrouping.isGradedItem(item) {
            return collectionGradeLabel(for: item)
        }
        return itemVariantLabel(item)
    }

    private func itemVariantLabel(_ item: CollectionItem) -> String {
        item.variantKey.replacingOccurrences(of: "_", with: " ")
    }

    private var collectionOwnedCardIDs: Set<String> {
        cachedCollectionOwnedCardIDs
    }

    private var filteredCollectionItems: [CollectionItem] {
        filterCollectionItems(from: visibleCollectionItems)
    }

    private var filteredCollectionItemsForSelectedType: [CollectionItem] {
        filteredCollectionItems.filter { item in
            let isSealed = sealedProduct(for: item) != nil
            return selectedContentTypeTab == .products ? isSealed : !isSealed
        }
    }

    private func filterCollectionItems(from items: [CollectionItem]) -> [CollectionItem] {
        var items = items
        if collectionFilters.showDuplicates {
            items = items.filter { $0.quantity >= 2 }
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
            return sortCollectionItemsByNewestSet(items)
        case .price:
            return items.sorted { lhs, rhs in
                comparePricedItems(
                    lhsPrice: collectionDisplayPrice(for: lhs),
                    rhsPrice: collectionDisplayPrice(for: rhs),
                    lhsCard: cardsByCardID[lhs.cardID],
                    rhsCard: cardsByCardID[rhs.cardID]
                )
            }
        }
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
                lhsStableID: itemStableSortID(lhs.item),
                rhsStableID: itemStableSortID(rhs.item)
            )
        }.map(\.item)
    }

    private func itemStableSortID(_ item: CollectionItem) -> String {
        "\(item.cardID)|\(item.variantKey)|\(item.persistentModelID.hashValue)"
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

    private var collectionResolveTaskKey: String {
        "\(collectionSignature)-\(collectionFilters.sortBy.rawValue)"
    }

    private var wishlistResolveTaskKey: String {
        "\(wishlistSignature)-\(wishlistFilters.sortBy.rawValue)"
    }

    private func scheduleCollectionFeedRefresh(requireResolvedPrices: Bool = false) {
        if requireResolvedPrices, isResolvingCollectionPrices { return }
        collectionFeedDebounceTask?.cancel()
        collectionFeedDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard !Task.isCancelled else { return }
            if requireResolvedPrices, isResolvingCollectionPrices { return }
            refreshCollectionFeed()
        }
    }

    private func scheduleWishlistFeedRefresh(requireResolvedPrices: Bool = false) {
        if requireResolvedPrices, isResolvingWishlistPrices { return }
        wishlistFeedDebounceTask?.cancel()
        wishlistFeedDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard !Task.isCancelled else { return }
            if requireResolvedPrices, isResolvingWishlistPrices { return }
            refreshWishlistFeed()
        }
    }

    private func resolveCollectionCards() async {
        let needsDeepPriceResolve = collectionFilters.sortBy == .price
        if needsDeepPriceResolve {
            isResolvingCollectionPrices = true
        }
        defer {
            if needsDeepPriceResolve {
                isResolvingCollectionPrices = false
            }
        }

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

        var uniqueCardsByID: [String: Card] = [:]
        uniqueCardsByID.reserveCapacity(cardItems.count)
        for item in cardItems {
            if let card = next[item.cardID] {
                uniqueCardsByID[card.masterCardId] = card
            }
        }
        let cardsToPrice = Array(uniqueCardsByID.values)
        await services.pricing.prefetchPokemonCardPricing(forSetCodes: [])
        await services.pricing.indexPricingForCards(cardsToPrice)

        var nextPrices: [String: Double] = [:]
        var nextCardPrices: [String: Double] = [:]
        var resolvedPriceKeys: Set<String> = []
        for item in cardItems {
            guard let card = next[item.cardID] else { continue }
            resolvedPriceKeys.insert(collectionItemKey(item))
            let gradeKey = collectionGradeKey(for: item)
            if let usd = services.pricing.cachedMarketSortUSD(
                for: card,
                variantKey: item.variantKey,
                grade: gradeKey
            ) {
                nextPrices[collectionItemKey(item)] = usd
                nextCardPrices[item.cardID] = max(nextCardPrices[item.cardID] ?? 0, usd)
            }
        }

        if needsDeepPriceResolve {
            await resolveMissingCollectionSortPrices(
                cardItems: cardItems,
                cardsByID: next,
                itemPrices: &nextPrices,
                cardPrices: &nextCardPrices
            )
        }

        cardsByCardID = next
        collectionPriceByItemKey = nextPrices
        collectionSortPriceByCardID = nextCardPrices
        collectionResolvedPriceItemKeys = resolvedPriceKeys

        collectFilterEnergyOptions = cardEnergyOptions(Array(uniqueCardsByID.values))
        collectFilterRarityOptions = cardRarityOptions(Array(uniqueCardsByID.values))
        collectFilterTrainerTypeOptions = cardTrainerTypeOptions(Array(uniqueCardsByID.values))
        refreshCollectionFeed()

        ImagePrefetcher.shared.prefetchCardWindow(collectionDisplayedCards, startingAt: 0, count: 24)
    }

    private func resolveMissingCollectionSortPrices(
        cardItems: [CollectionItem],
        cardsByID: [String: Card],
        itemPrices: inout [String: Double],
        cardPrices: inout [String: Double]
    ) async {
        var cardsNeedingLookup: [String: Card] = [:]
        for item in cardItems {
            guard itemPrices[collectionItemKey(item)] == nil,
                  let card = cardsByID[item.cardID] else { continue }
            cardsNeedingLookup[item.cardID] = card
        }
        guard !cardsNeedingLookup.isEmpty else { return }

        await withTaskGroup(of: (String, Double?).self) { group in
            for (cardID, card) in cardsNeedingLookup {
                let specs = cardItems
                    .filter { $0.cardID == cardID }
                    .map { (variantKey: $0.variantKey, grade: collectionGradeKey(for: $0)) }
                group.addTask {
                    let price = await self.services.pricing.resolveBestMarketSortUSD(for: card, specs: specs)
                    return (cardID, price)
                }
            }
            for await (cardID, price) in group {
                guard let price else { continue }
                cardPrices[cardID] = max(cardPrices[cardID] ?? 0, price)
                for item in cardItems where item.cardID == cardID {
                    let itemKey = collectionItemKey(item)
                    if itemPrices[itemKey] == nil {
                        itemPrices[itemKey] = price
                    }
                }
            }
        }
    }

    private func refreshCollectContent() async {
        await services.sealedProducts.refreshFromNetworkAndStoreLocallyIfNeeded()
        await reloadCollectionItems()
        await reloadWishlistItems()
        await refreshSetNameCache()
        refreshSealedProductCaches()
        await resolveCollectionCards()
        await resolveWishlistCards()
        refreshCollectionFeed()
        refreshWishlistFeed()
    }

    private func refreshCollectionFeed() {
        let filtered = filteredCollectionItemsForSelectedType
        let filteredIDs = filtered.map(\.persistentModelID)
        let previousIDs = collectionFilteredItemsForSelectedTypeCache.map(\.persistentModelID)

        collectionFilteredItemsForSelectedTypeCache = filtered

        if filteredIDs == previousIDs && !collectionDisplayedItems.isEmpty {
            collectionDisplayedCards = collectionDisplayedItems.compactMap { cardsByCardID[$0.cardID] }
            return
        }

        let initialEnd: Int
        if collectionFilters.sortBy == .price {
            initialEnd = filtered.count
        } else {
            initialEnd = min(Self.collectionInitialBatchSize, filtered.count)
        }
        collectionDisplayedItems = Array(filtered.prefix(initialEnd))
        collectionNextIndex = initialEnd
        collectionDisplayedCards = collectionDisplayedItems.compactMap { cardsByCardID[$0.cardID] }
    }

    private func refreshWishlistFeed() {
        wishlistFilteredItemsForSelectedTypeCache = filteredWishlistItemsForSelectedType
        wishlistOrderedCardsCache = wishlistFilteredItemsForSelectedTypeCache.compactMap { wishlistCardsByID[$0.cardID] }
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
        if let cached = collectionPriceByItemKey[collectionItemKey(item)] {
            return cached
        }
        if let cardPrice = collectionSortPriceByCardID[item.cardID] {
            return cardPrice
        }
        guard let card = cardsByCardID[item.cardID] else { return nil }
        let gradeKey = collectionGradeKey(for: item)
        return services.pricing.cachedMarketSortUSD(
            for: card,
            variantKey: item.variantKey,
            grade: gradeKey
        )
    }

    // MARK: - Wishlist Content

    @ViewBuilder
    private var wishlistContent: some View {
        if isLoadingWishlistItems && wishlistItems.isEmpty {
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading wishlist...")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        } else if wishlistItems.isEmpty {
            emptyState(title: "Wishlist is empty", image: "star.slash",
                       description: "Add cards from browse or search to track cards you want.")
        } else if visibleWishlistItems.isEmpty {
            emptyState(
                title: "No wishlist items",
                image: "line.3.horizontal.decrease.circle",
                description: "No \(activeBrand.displayTitle) cards on your wishlist yet."
            )
        } else if isWishlistWaitingForCurrentSortOrFilters {
            VStack(spacing: 12) {
                ProgressView()
                Text("Applying your filters and sort...")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        } else if wishlistFilteredItemsForSelectedTypeCache.isEmpty {
            emptyState(
                title: "No matching \(selectedContentTypeTab.title.lowercased())",
                image: "magnifyingglass",
                description: selectedContentTypeTab == .cards
                    ? "Try a different card name, set code, or number."
                    : "Try a different product name, series, or year."
            )
        } else {
            EagerVGrid(items: indexedFilteredWishlistItemsForSelectedType, columns: safeColumnCount, spacing: BindrSpacing.cardGrid) { indexed in
                wishlistCell(for: indexed.item)
                    .onAppear {
                        guard selectedContentTypeTab == .cards else { return }
                        ImagePrefetcher.shared.prefetchCardWindow(orderedWishlistCards, startingAt: indexed.index + 1)
                    }
            }
            .padding(.horizontal, BindrSpacing.cardGridScreenInset)
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
                    accentColor: services.theme.accentColor,
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
        Array(wishlistFilteredItemsForSelectedTypeCache.enumerated()).map { offset, item in
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
                comparePricedItems(
                    lhsPrice: wishlistDisplayPrice(for: lhs),
                    rhsPrice: wishlistDisplayPrice(for: rhs),
                    lhsCard: wishlistCardsByID[lhs.cardID],
                    rhsCard: wishlistCardsByID[rhs.cardID]
                )
            }
        }
    }

    private var resolvedWishlistCards: [Card] {
        visibleWishlistItems.compactMap { wishlistCardsByID[$0.cardID] }
    }

    private var orderedWishlistCards: [Card] {
        wishlistOrderedCardsCache
    }

    private var wishlistSignature: Int {
        var h = Hasher()
        h.combine(activeBrand.rawValue)
        for item in visibleWishlistItems { h.combine(item.cardID) }
        return h.finalize()
    }

    private func resolveWishlistCards() async {
        let needsDeepPriceResolve = wishlistFilters.sortBy == .price
        if needsDeepPriceResolve {
            isResolvingWishlistPrices = true
        }
        defer {
            if needsDeepPriceResolve {
                isResolvingWishlistPrices = false
            }
        }

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

        var uniqueCardsByID: [String: Card] = [:]
        uniqueCardsByID.reserveCapacity(cardItems.count)
        for item in cardItems {
            if let card = next[item.cardID] {
                uniqueCardsByID[card.masterCardId] = card
            }
        }
        let cardsToPrice = Array(uniqueCardsByID.values)
        await services.pricing.prefetchPokemonCardPricing(forSetCodes: [])
        await services.pricing.indexPricingForCards(cardsToPrice)

        var nextPrices: [String: Double] = [:]
        var nextCardPrices: [String: Double] = [:]
        var resolvedPriceKeys: Set<String> = []
        for item in cardItems {
            guard let card = next[item.cardID] else { continue }
            resolvedPriceKeys.insert(wishlistItemKey(item))
            if let usd = services.pricing.cachedMarketSortUSD(
                for: card,
                variantKey: item.variantKey,
                grade: "raw"
            ) {
                nextPrices[wishlistItemKey(item)] = usd
                nextCardPrices[item.cardID] = max(nextCardPrices[item.cardID] ?? 0, usd)
            }
        }

        if needsDeepPriceResolve {
            await resolveMissingWishlistSortPrices(
                cardItems: cardItems,
                cardsByID: next,
                itemPrices: &nextPrices,
                cardPrices: &nextCardPrices
            )
        }

        wishlistCardsByID = next
        wishlistPriceByItemKey = nextPrices
        wishlistSortPriceByCardID = nextCardPrices
        wishlistResolvedPriceItemKeys = resolvedPriceKeys
        refreshWishlistFeed()

        ImagePrefetcher.shared.prefetchCardWindow(orderedWishlistCards, startingAt: 0, count: 24)
    }

    private func resolveMissingWishlistSortPrices(
        cardItems: [WishlistItem],
        cardsByID: [String: Card],
        itemPrices: inout [String: Double],
        cardPrices: inout [String: Double]
    ) async {
        var cardsNeedingLookup: [String: Card] = [:]
        for item in cardItems {
            guard itemPrices[wishlistItemKey(item)] == nil,
                  let card = cardsByID[item.cardID] else { continue }
            cardsNeedingLookup[item.cardID] = card
        }
        guard !cardsNeedingLookup.isEmpty else { return }

        await withTaskGroup(of: (String, Double?).self) { group in
            for (cardID, card) in cardsNeedingLookup {
                let specs = cardItems
                    .filter { $0.cardID == cardID }
                    .map { (variantKey: $0.variantKey, grade: "raw") }
                group.addTask {
                    let price = await self.services.pricing.resolveBestMarketSortUSD(for: card, specs: specs)
                    return (cardID, price)
                }
            }
            for await (cardID, price) in group {
                guard let price else { continue }
                cardPrices[cardID] = max(cardPrices[cardID] ?? 0, price)
                for item in cardItems where item.cardID == cardID {
                    let itemKey = wishlistItemKey(item)
                    if itemPrices[itemKey] == nil {
                        itemPrices[itemKey] = price
                    }
                }
            }
        }
    }

    private func removeFromWishlist(_ item: WishlistItem) {
        do {
            try services.wishlist?.removeItem(item)
        } catch {
            modelContext.delete(item)
            modelContext.saveLogging()
            services.notifyWishlistInventoryChanged()
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
        if let cached = wishlistPriceByItemKey[wishlistItemKey(item)] {
            return cached
        }
        if let cardPrice = wishlistSortPriceByCardID[item.cardID] {
            return cardPrice
        }
        guard let card = wishlistCardsByID[item.cardID] else { return nil }
        return services.pricing.cachedMarketSortUSD(
            for: card,
            variantKey: item.variantKey,
            grade: "raw"
        )
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
