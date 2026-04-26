import SwiftData
import SwiftUI

/// Combined Collection + Wishlist view with segmented toggle at top.
struct CollectView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(\.presentCard) private var presentCard
    @Environment(\.rootFloatingChromeInset) private var rootFloatingChromeInset

    // MARK: - Collection State
    @Query(sort: \CollectionItem.dateAcquired, order: .reverse) private var collectionItems: [CollectionItem]
    @State private var cardsByCardID: [String: Card] = [:]
    @State private var collectionPriceByItemKey: [String: Double] = [:]
    @State private var selectedSealedProduct: SealedProduct?
    @State private var cachedSetNameByBrandAndCode: [String: String] = [:]

    // MARK: - Wishlist State
    @Query(sort: \WishlistItem.dateAdded, order: .reverse) private var wishlistItems: [WishlistItem]
    @State private var wishlistCardsByID: [String: Card] = [:]
    @State private var wishlistPriceByItemKey: [String: Double] = [:]

    // MARK: - Shared State (owned by RootView)
    @Binding var selectedSegment: CollectSegment
    @Binding var selectedBrand: TCGBrand?
    @Binding var collectionFilters: BrowseCardGridFilters
    @Binding var wishlistFilters: BrowseCardGridFilters
    @Binding var collectFilterEnergyOptions: [String]
    @Binding var collectFilterRarityOptions: [String]
    @Binding var collectFilterTrainerTypeOptions: [String]
    @Binding var gridOptions: BrowseGridOptions

    @State private var collectionQuery = ""
    @State private var wishlistQuery = ""

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

    private var visibleCollectionItems: [CollectionItem] {
        collectionItems.filter { TCGBrand.inferredFromMasterCardId($0.cardID) == activeBrand }
    }

    private var sealedProductByID: [Int: SealedProduct] {
        Dictionary(uniqueKeysWithValues: services.sealedProducts.products.map { ($0.id, $0) })
    }

    private var sealedProductByCollectionCardID: [String: SealedProduct] {
        Dictionary(uniqueKeysWithValues: services.sealedProducts.products.map { ($0.collectionCardID, $0) })
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
                    BrowseInlineSearchField(title: searchPlaceholder, text: activeQueryBinding)
                        .padding(.horizontal, 16)
                }
                .padding(.bottom, 10)

                contentView
            }
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
        .onAppear {
            if selectedBrand != services.brandSettings.selectedCatalogBrand {
                selectedBrand = services.brandSettings.selectedCatalogBrand
            }
        }
        .onChange(of: services.brandSettings.selectedCatalogBrand) { _, brand in
            selectedBrand = brand
        }
        .onChange(of: selectedBrand) { _, _ in
            // Keep persisted filters when switching brands.
        }
        .onChange(of: collectionShareSyncSignature) { _, _ in
            services.socialShare.scheduleAutoSyncCollection(items: collectionItems)
        }
        .sheet(item: $selectedSealedProduct) { product in
            SealedProductBrowseDetailView(products: [product], startProductID: product.id)
                .environment(services)
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

    // MARK: - Segmented Control

    private var segmentedControl: some View {
        SlidingSegmentedPicker(
            selection: $selectedSegment,
            items: CollectSegment.allCases,
            title: { $0.title }
        )
    }

    private var searchPlaceholder: String {
        switch selectedSegment {
        case .collection:
            return "Search \(formattedActiveFilteredCount) cards in collection"
        case .wishlist:
            return "Search \(formattedActiveFilteredCount) cards in wishlist"
        }
    }

    private var activeQueryBinding: Binding<String> {
        selectedSegment == .collection ? $collectionQuery : $wishlistQuery
    }

    private var activeFilteredCount: Int {
        selectedSegment == .collection ? filteredCollectionItems.count : filteredWishlistItems.count
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
        } else if filteredCollectionItems.isEmpty {
            emptyState(
                title: "No matching cards",
                image: "magnifyingglass",
                description: "Try a different card name, set code, or number."
            )
        } else {
            EagerVGrid(items: filteredCollectionItems, columns: safeColumnCount, spacing: 12) { item in
                let index = filteredCollectionItems.firstIndex(where: { $0.id == item.id }) ?? 0
                collectionCell(for: item)
                    .onAppear {
                        ImagePrefetcher.shared.prefetchCardWindow(orderedCollectionCards, startingAt: index + 1)
                    }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private func collectionCell(for item: CollectionItem) -> some View {
        if let product = sealedProduct(for: item) {
            Button { selectedSealedProduct = product } label: {
                SealedProductGridCell(
                    product: product,
                    gridOptions: gridOptions,
                    priceUSD: services.sealedProducts.marketPriceUSD(for: product.id),
                    isOwned: item.quantity > 0,
                    isWishlisted: wishlistedSealedCollectionCardIDs.contains(product.collectionCardID)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(CardCellButtonStyle())
            .accessibilityLabel("\(product.name), \(item.quantity) owned")
        } else if let card = cardsByCardID[item.cardID] {
            Button { presentCard(card, orderedCollectionCards) } label: {
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
        if collectionFilters.hasActiveFieldFilters || !trimmedQuery.isEmpty {
            let filteredCards = filterBrowseCards(
                resolvedCollectionCards, query: collectionQuery, filters: collectionFilters,
                ownedCardIDs: Set(items.map { $0.cardID }),
                brand: activeBrand, sets: services.cardData.sets
            )
            let filteredIDs = Set(filteredCards.map { $0.masterCardId })
            let hasFieldFilters = collectionFilters.hasActiveFieldFilters
            let normalizedQuery = trimmedQuery.lowercased()
            items = items.filter { item in
                if let product = sealedProduct(for: item) {
                    guard hasFieldFilters == false else { return false }
                    guard !normalizedQuery.isEmpty else { return true }
                    return product.searchBlob.contains(normalizedQuery)
                }
                return filteredIDs.contains(item.cardID)
            }
        }
        return applySortToCollectionItems(items, filters: collectionFilters)
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
            return items
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

    private var orderedCollectionCards: [Card] {
        filteredCollectionItems.compactMap { cardsByCardID[$0.cardID] }
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

        let cards = orderedCollectionCards
        ImagePrefetcher.shared.prefetchCardWindow(cards, startingAt: 0, count: 24)
        collectFilterEnergyOptions = cardEnergyOptions(cards)
        collectFilterRarityOptions = cardRarityOptions(cards)
        collectFilterTrainerTypeOptions = cardTrainerTypeOptions(cards)
    }

    private func sealedProduct(for item: CollectionItem) -> SealedProduct? {
        guard item.itemKind == ProductKind.sealedProduct.rawValue || SealedProduct.parseCollectionProductID(item.cardID) != nil else {
            return nil
        }
        if let product = sealedProductByCollectionCardID[item.cardID] {
            return product
        }
        if let rawID = item.sealedProductId,
           let productID = Int(rawID),
           let product = sealedProductByID[productID] {
            return product
        }
        if let productID = SealedProduct.parseCollectionProductID(item.cardID) {
            return sealedProductByID[productID]
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
        } else if filteredWishlistItems.isEmpty {
            emptyState(
                title: "No matching cards",
                image: "magnifyingglass",
                description: "Try a different card name, set code, or number."
            )
        } else {
            EagerVGrid(items: filteredWishlistItems, columns: safeColumnCount, spacing: 12) { item in
                let index = filteredWishlistItems.firstIndex(where: { $0.id == item.id }) ?? 0
                wishlistCell(for: item)
                    .onAppear {
                        ImagePrefetcher.shared.prefetchCardWindow(orderedWishlistCards, startingAt: index + 1)
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
        if wishlistFilters.hasActiveFieldFilters || !trimmedQuery.isEmpty {
            let filteredCards = filterBrowseCards(
                resolvedWishlistCards, query: wishlistQuery, filters: wishlistFilters,
                ownedCardIDs: [], brand: activeBrand, sets: services.cardData.sets
            )
            let filteredIDs = Set(filteredCards.map { $0.masterCardId })
            let hasFieldFilters = wishlistFilters.hasActiveFieldFilters
            let normalizedQuery = trimmedQuery.lowercased()
            items = items.filter { item in
                if let product = sealedProduct(for: item) {
                    guard hasFieldFilters == false else { return false }
                    guard !normalizedQuery.isEmpty else { return true }
                    return product.searchBlob.contains(normalizedQuery)
                }
                return filteredIDs.contains(item.cardID)
            }
        }
        return applySortToWishlistItems(items, filters: wishlistFilters)
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
            return items
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
        filteredWishlistItems.compactMap { wishlistCardsByID[$0.cardID] }
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

    private func sealedProduct(for item: WishlistItem) -> SealedProduct? {
        if let product = sealedProductByCollectionCardID[item.cardID] {
            return product
        }
        if let productID = SealedProduct.parseCollectionProductID(item.cardID) {
            return sealedProductByID[productID]
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

    // MARK: - Empty State

    private func emptyState(title: String, image: String, description: String) -> some View {
        ContentUnavailableView(title, systemImage: image, description: Text(description))
            .frame(minHeight: 280)
            .padding(.horizontal)
    }
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
