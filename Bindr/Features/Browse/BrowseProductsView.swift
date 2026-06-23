import Charts
import SwiftData
import SwiftUI
import UIKit

struct BrowseProductsTabContent: View {
    @Environment(AppServices.self) private var services
    @Environment(\.presentSealedProduct) private var presentSealedProduct
    @Query(sort: \CollectionItem.dateAcquired, order: .reverse) private var collectionItems: [CollectionItem]
    @Query(sort: \WishlistItem.dateAdded, order: .reverse) private var wishlistItems: [WishlistItem]

    let query: String
    let filters: BrowseCardGridFilters
    let gridOptions: BrowseGridOptions

    @State private var displayedProducts: [SealedProduct] = []
    @State private var addToCollectionProduct: SealedProduct?
    @State private var showWishlistPaywall = false
    @State private var showWishlistAlert = false
    @State private var wishlistAlertMessage: String?
    /// Selected set is tracked by *name* rather than numeric id because the
    /// sealed-product feed and the catalog `sets.json` come from independent
    /// pipelines (PokeData/TCGCSV vs. the catalog R2 blob), and their numeric
    /// IDs don't reliably line up. Matching by name is robust for Pokémon set
    /// names like "Perfect Order" or "Destined Rivals" since those strings
    /// always appear inside the product name (e.g. "Perfect Order Booster
    /// Box"). The filter falls back to the numeric setID for the (common)
    /// case where the IDs *do* agree, so anything that worked before keeps
    /// working — but products whose setID is unmapped now also resolve.
    @State private var selectedSet: TCGSet? = nil

    /// Cached list of sets that have at least one matching product. Computed
    /// once when the underlying product/set data changes — NEVER inline in the
    /// carousel body. Inline computation here used to walk `products × sets`
    /// (~hundreds × hundreds = tens of thousands of string normalizations) on
    /// every SwiftUI render pass, which was the dominant source of tap lag on
    /// the Products tab.
    @State private var carouselSets: [TCGSet] = []
    /// Lookup of normalized product strings used when resolving the set the
    /// user has tapped (and when populating ``carouselSets``). Built once per
    /// product-list change so the per-tap filter cost stays O(N) instead of
    /// re-normalizing every product on every keystroke or view render.
    @State private var normalizedProductIndex: NormalizedProductIndex = .empty

    private let sealedGridHorizontalPadding: CGFloat = 16
    private let sealedGridSpacing: CGFloat = 12

    private var sealedGridColumnCount: Int {
        min(max(gridOptions.columnCount, 1), 4)
    }

    private var ownedCollectionCardIDs: Set<String> {
        Set(collectionItems.compactMap { item in
            guard item.itemKind == ProductKind.sealedProduct.rawValue else { return nil }
            return item.cardID
        })
    }

    private var ownedQuantityByProductID: [String: Int] {
        collectionItems.reduce(into: [:]) { result, item in
            guard item.quantity > 0 else { return }
            guard item.itemKind == ProductKind.sealedProduct.rawValue else { return }
            result[item.cardID, default: 0] += item.quantity
        }
    }

    private var wishlistedCollectionCardIDs: Set<String> {
        Set(wishlistItems.map(\.cardID).filter { SealedProduct.parseCollectionProductID($0) != nil })
    }

    private var filteredProducts: [SealedProduct] {
        let normalizedQuery = normalizeSealedSearchText(query)
        let selectedSetIDInt: Int? = {
            guard let selectedSet else { return nil }
            return Int(selectedSet.internalId)
        }()
        let normalizedSelectedSetName: String? = {
            guard let selectedSet else { return nil }
            return normalizeSealedSearchText(selectedSet.name)
        }()
        let allProducts = services.sealedProducts.products
        let base = allProducts.enumerated().compactMap { (index, product) -> SealedProduct? in
            if selectedSet != nil {
                if !productMatchesSet(
                    product: product,
                    productIndex: index,
                    setIDInt: selectedSetIDInt,
                    normalizedSetName: normalizedSelectedSetName
                ) {
                    return nil
                }
            }
            if productMatchesSelectedTypes(product.type, selectedOptionIDs: filters.productTypes) == false {
                return nil
            }
            guard normalizedQuery.isEmpty == false else { return product }
            return product.searchBlob.contains(normalizedQuery) ? product : nil
        }
        return sort(products: base)
    }

    /// True when the product belongs to the user's selected set. Tries the
    /// numeric setID first (cheap, exact), falls back to a substring match on
    /// the normalized product name and series (handles the case where the
    /// product feed's `set_id` doesn't line up with the catalog `internalId`).
    /// `productIndex` is the *position* of `product` inside
    /// ``services.sealedProducts.products`` so we can read the precomputed
    /// normalized strings out of ``normalizedProductIndex`` instead of
    /// recomputing them on every check.
    private func productMatchesSet(
        product: SealedProduct,
        productIndex: Int,
        setIDInt: Int?,
        normalizedSetName: String?
    ) -> Bool {
        let setNameNorm = normalizedProductIndex.setName(at: productIndex)
        if let normalizedSetName, !normalizedSetName.isEmpty {
            // Prefer exact set-name matching whenever the product has set-name data.
            // Some feed rows can share or drift set IDs across nearby releases, which
            // causes cross-set leakage (e.g. Ascended Heroes pulling Mega Evolution).
            if !setNameNorm.isEmpty {
                return setNameNorm == normalizedSetName
            }
        }

        // Fallback for rows that do not carry set-name metadata.
        if let setIDInt, let pid = product.setID, pid == setIDInt {
            return true
        }
        return false
    }

    /// Rebuilds ``carouselSets`` and ``normalizedProductIndex`` from the
    /// current product feed. Heavy string folding and the O(products × sets)
    /// matching pass are dispatched to a background priority Task so the
    /// Products tab can render its first frame immediately when the user
    /// taps the segmented control. The cached results are then published
    /// back on the main actor and SwiftUI animates the carousel in.
    private func recomputeCarouselSets() async {
        let allProducts = services.sealedProducts.products
        let allSets = services.cardData.sets

        let computed: (NormalizedProductIndex, [TCGSet]) = await Task.detached(priority: .utility) {
            let index = NormalizedProductIndex(products: allProducts)
            let activeSetIDs = Set(allProducts.compactMap { $0.setID })
            let normalized: (String?) -> String = { value in
                normalizeSealedSearchText(value)
            }

            let matchedCatalogSets = allSets.filter { set in
                let setIDInt = Int(set.internalId)
                if let setIDInt, activeSetIDs.contains(setIDInt) {
                    return true
                }
                let normalizedSetName = normalized(set.name)
                guard !normalizedSetName.isEmpty else { return false }
                for i in allProducts.indices {
                    let setNameNorm = index.setName(at: i)
                    if !setNameNorm.isEmpty, setNameNorm == normalizedSetName { return true }
                }
                return false
            }
            var seenSetNames = Set(matchedCatalogSets.map { normalized($0.name) })

            // Include any set names that exist in sealed products but not in catalog sets.
            // This keeps the set-tag carousel complete when sealed feed data lands before
            // catalog set metadata (e.g. newly released products).
            var virtualSets: [TCGSet] = []
            for product in allProducts {
                let setName = (product.setName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !setName.isEmpty else { continue }
                let setNameNorm = normalized(setName)
                guard !setNameNorm.isEmpty, !seenSetNames.contains(setNameNorm) else { continue }
                seenSetNames.insert(setNameNorm)

                virtualSets.append(
                    TCGSet(
                        internalId: "virtual:\(setNameNorm)",
                        name: setName,
                        setKey: nil,
                        code: nil,
                        tcgdexId: nil,
                        releaseDate: product.releaseDate?.formatted(.iso8601.year().month().day()),
                        cardCountTotal: nil,
                        cardCountOfficial: nil,
                        seriesName: product.series,
                        logoSrc: "",
                        symbolSrc: nil
                    )
                )
            }

            let sets = (matchedCatalogSets + virtualSets)
                .sorted { ($0.releaseDate ?? "") > ($1.releaseDate ?? "") }

            return (index, sets)
        }.value

        normalizedProductIndex = computed.0
        carouselSets = computed.1
    }

    var body: some View {
        Group {
            if services.sealedProducts.isLoading && services.sealedProducts.products.isEmpty {
                ProgressView("Loading products…")
                    .frame(maxWidth: .infinity, minHeight: 280)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            } else {
                VStack(spacing: 0) {
                    productSetCarousel
                        .padding(.bottom, 14)
                    
                    if displayedProducts.isEmpty {
                        ContentUnavailableView(
                            services.sealedProducts.products.isEmpty ? "No products yet" : "No matching products",
                            systemImage: "shippingbox",
                            description: Text(services.sealedProducts.products.isEmpty
                                ? "Products will appear after the next market sync."
                                : "Try a different product name, series, or year.")
                        )
                        .frame(maxWidth: .infinity, minHeight: 280)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    } else {
                        EagerVGrid(items: displayedProducts, columns: sealedGridColumnCount, spacing: sealedGridSpacing) { product in
                            Button {
                                let index = displayedProducts.firstIndex(where: { $0.id == product.id }) ?? 0
                                presentSealedProduct(product, displayedProducts, index)
                            } label: {
                                SealedProductGridCell(
                                    product: product,
                                    gridOptions: gridOptions,
                                    priceUSD: services.sealedProducts.marketPriceUSD(for: product.id),
                                    isOwned: ownedCollectionCardIDs.contains(product.collectionCardID),
                                    isWishlisted: wishlistedCollectionCardIDs.contains(product.collectionCardID),
                                    ownedCountBadge: ownedQuantityByProductID[product.collectionCardID]
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(CardCellButtonStyle())
                            .contextMenu {
                                Button {
                                    addToCollectionProduct = product
                                } label: {
                                    Label("Add to Collection", systemImage: "books.vertical")
                                }
                                Button {
                                    toggleWishlist(for: product)
                                } label: {
                                    Label(
                                        isWishlisted(product) ? "Remove from Wishlist" : "Add to Wishlist",
                                        systemImage: isWishlisted(product) ? "heart.slash" : "heart"
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, sealedGridHorizontalPadding)
                        .padding(.bottom, 16)
                    }
                }
            }
        }
        .task {
            await services.sealedProducts.loadFromLocalIfAvailable()
            if services.sealedProducts.products.isEmpty {
                await services.sealedProducts.refreshFromNetworkAndStoreLocallyIfNeeded()
            }
            // Build the carousel + normalized index once before the first
            // grid render. The heavy lifting is dispatched off the main
            // actor inside `recomputeCarouselSets`, so the tab is interactive
            // immediately and the carousel populates a frame or two later.
            await recomputeCarouselSets()
            recomputeDisplayedProducts()
        }
        .onChange(of: query) { _, _ in recomputeDisplayedProducts() }
        .onChange(of: filters) { _, _ in recomputeDisplayedProducts() }
        .onChange(of: selectedSet) { _, _ in recomputeDisplayedProducts() }
        .onChange(of: services.sealedProducts.products) { _, _ in
            // Product feed changed → carousel set list and the normalized
            // product index both need to be rebuilt before
            // `recomputeDisplayedProducts` runs (the filter relies on the
            // index for the selected-set match).
            Task {
                await recomputeCarouselSets()
                recomputeDisplayedProducts()
            }
        }
        .sheet(item: $addToCollectionProduct) { product in
            AddSealedToCollectionSheet(product: product)
                .environment(services)
        }
        .sheet(isPresented: $showWishlistPaywall) {
            PaywallSheet()
                .environment(services)
        }
        .alert("Wishlist", isPresented: $showWishlistAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(wishlistAlertMessage ?? "")
        }
    }

    private var productSetCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // "All Sets" button
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        selectedSet = nil
                    }
                    Haptics.lightImpact()
                } label: {
                    Text("All Sets")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background {
                            Capsule()
                                .fill(selectedSet == nil ? services.theme.accentColor : Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.06))
                        }
                        .foregroundStyle(selectedSet == nil ? .white : .primary.opacity(0.8))
                }
                .buttonStyle(.plain)

                // ``carouselSets`` is precomputed in `recomputeCarouselSets`
                // and only refreshed when the underlying data changes — it
                // used to be calculated inline here, doing O(products × sets)
                // string normalization on every render of the tab, which was
                // the dominant source of lag when switching to the Products
                // tab on devices with a large product feed.
                ForEach(carouselSets) { set in
                    let isSelected = selectedSet?.id == set.id

                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            selectedSet = isSelected ? nil : set
                        }
                        Haptics.lightImpact()
                    } label: {
                        HStack(spacing: 6) {
                            SetLogoAsyncImage(logoSrc: set.logoSrc, height: 18, brand: services.brandSettings.selectedCatalogBrand)
                                .grayscale(isSelected ? 0 : 1)
                                .opacity(isSelected ? 1 : 0.5)

                            if isSelected {
                                Text(set.name)
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .fixedSize()
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background {
                            Capsule()
                                .fill(isSelected ? services.theme.accentColor : Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.06))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    @Environment(\.colorScheme) private var colorScheme

    private func recomputeDisplayedProducts() {
        displayedProducts = filteredProducts
    }

    private func sort(products: [SealedProduct]) -> [SealedProduct] {
        switch filters.sortBy {
        case .random:
            return products.sorted { lhs, rhs in
                stableRandomRank(for: lhs.id) < stableRandomRank(for: rhs.id)
            }
        case .newestSet:
            return products.sorted { lhs, rhs in
                let lDate = lhs.releaseDate ?? .distantPast
                let rDate = rhs.releaseDate ?? .distantPast
                if lDate != rDate { return lDate > rDate }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        case .cardName:
            return products.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .price:
            return products.sorted { lhs, rhs in
                let l = services.sealedProducts.marketPriceUSD(for: lhs.id)
                let r = services.sealedProducts.marketPriceUSD(for: rhs.id)
                switch (l, r) {
                case let (lv?, rv?):
                    if lv != rv { return lv > rv }
                case (.some, nil):
                    return true
                case (nil, .some):
                    return false
                case (nil, nil):
                    break
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        case .cardNumber:
            return products.sorted { $0.id < $1.id }
        case .acquiredDateNewest:
            return products
        }
    }

    private func stableRandomRank(for id: Int) -> UInt64 {
        var x = UInt64(bitPattern: Int64(id))
        x &+= 0x9E3779B97F4A7C15
        x = (x ^ (x >> 30)) &* 0xBF58476D1CE4E5B9
        x = (x ^ (x >> 27)) &* 0x94D049BB133111EB
        return x ^ (x >> 31)
    }

    private func isWishlisted(_ product: SealedProduct) -> Bool {
        wishlistedCollectionCardIDs.contains(product.collectionCardID)
    }

    private func toggleWishlist(for product: SealedProduct) {
        guard let wishlist = services.wishlist else {
            wishlistAlertMessage = "Wishlist isn't available yet. Try again in a moment."
            showWishlistAlert = true
            return
        }

        let cardID = product.collectionCardID
        if isWishlisted(product) {
            do {
                try wishlist.removeCardVariant(cardID: cardID, variantKey: "sealed")
            } catch {
                wishlistAlertMessage = error.localizedDescription
                showWishlistAlert = true
            }
            return
        }

        guard wishlist.canAddItem else {
            showWishlistPaywall = true
            return
        }

        do {
            try wishlist.addItem(cardID: cardID, variantKey: "sealed")
        } catch WishlistError.limitReached {
            showWishlistPaywall = true
        } catch {
            wishlistAlertMessage = error.localizedDescription
            showWishlistAlert = true
        }
    }

}

struct SealedProductGridCell: View {
    @Environment(AppServices.self) private var services
    @Environment(\.colorScheme) private var colorScheme

    let product: SealedProduct
    let gridOptions: BrowseGridOptions
    let priceUSD: Double?
    let isOwned: Bool
    let isWishlisted: Bool
    var ownedCountBadge: Int? = nil

    private var showsFooter: Bool {
        (gridOptions.showSetName && !(product.setName ?? "").isEmpty)
            || gridOptions.showSetID
            || gridOptions.showPricing
    }

    private var imageCornerRadius: CGFloat { 8 }

    private var imageHeight: CGFloat {
        let columns = min(max(gridOptions.columnCount, 1), 4)
        switch columns {
        case 1: return 180
        case 2: return 110
        case 3: return 80
        default: return 65
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if gridOptions.showCardName {
                Text(product.name)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .padding(.horizontal, 8)
            }

            SealedThumbnailView(
                imageURL: product.imageURL,
                isOwned: isOwned,
                isWishlisted: isWishlisted,
                ownedCountBadge: ownedCountBadge
            )
            .frame(maxWidth: .infinity)
            .frame(height: imageHeight)
            .clipShape(RoundedRectangle(cornerRadius: imageCornerRadius, style: .continuous))
            .overlay {
                if isOwned || isWishlisted {
                    RoundedRectangle(cornerRadius: imageCornerRadius, style: .continuous)
                        .stroke(
                            isOwned ? services.theme.accentColor : Color.yellow,
                            lineWidth: 1.8
                        )
                }
            }

            if showsFooter {
                VStack(spacing: 3) {
                    if gridOptions.showSetName, let setName = product.setName, !setName.isEmpty {
                        Text(setName)
                            .font(.caption2)
                            .lineLimit(1)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }

                    if gridOptions.showSetID {
                        Text("#\(product.id)")
                            .font(.caption2)
                            .lineLimit(1)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                    }

                    if gridOptions.showPricing {
                        if let priceUSD {
                            Text(services.priceDisplay.currency.format(amountUSD: priceUSD, usdToGbp: services.pricing.usdToGbp))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(services.theme.accentColor)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("—")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

private struct SealedThumbnailView: View {
    @Environment(AppServices.self) private var services

    let imageURL: URL?
    var isOwned: Bool
    var isWishlisted: Bool
    var ownedCountBadge: Int? = nil

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            CachedAsyncImage(url: imageURL, targetSize: CGSize(width: 260, height: 364)) { image in
                image
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } placeholder: {
                Color.secondary.opacity(0.12)
                    .overlay { ProgressView() }
            }
            .clipped()

            if let ownedCountBadge, ownedCountBadge >= 1 {
                ZStack {
                    Circle()
                        .fill(services.theme.accentColor)
                        .frame(width: 24, height: 24)
                    Text("x\(ownedCountBadge)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                }
                .shadow(color: .black.opacity(0.18), radius: 3, x: 0, y: 1)
                .padding(6)
                .accessibilityLabel("Owned \(ownedCountBadge)")
            } else if isWishlisted {
                Image(systemName: "star.circle.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white, .yellow)
                    .shadow(color: .black.opacity(0.18), radius: 3, x: 0, y: 1)
                    .padding(6)
            }
        }
    }
}

struct SealedProductBrowseDetailView: View {
    let products: [SealedProduct]

    @Environment(AppServices.self) private var services
    @Environment(\.suppressTabBarForModalChrome) private var suppressTabBarForModalChrome
    @Environment(\.restoreTabBarChrome) private var restoreTabBarChrome
    @State private var scrollIndex: Int?

    init(products: [SealedProduct], startProductID: Int) {
        self.products = products
        let start = products.firstIndex(where: { $0.id == startProductID }) ?? 0
        _scrollIndex = State(initialValue: start)
    }

    var body: some View {
        GeometryReader { geo in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(Array(products.indices), id: \.self) { i in
                        SealedProductDetailPage(
                            product: products[i]
                        )
                        .frame(width: geo.size.width, height: geo.size.height)
                        .id(i)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $scrollIndex)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
            .onChange(of: scrollIndex) { _, i in
                guard i != nil else { return }
                HapticManager.selection()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            CardDetailTypeBackground(accent: services.theme.accentColor)
                .ignoresSafeArea()
        }
        .onAppear {
            suppressTabBarForModalChrome?()
        }
        .onDisappear {
            restoreTabBarAfterPresentation()
        }
        .presentationBackground {
            CardDetailTypeBackground(accent: services.theme.accentColor)
                .ignoresSafeArea()
        }
        .presentationDragIndicator(.hidden)
        .presentationDetents([.large])
        .presentationCornerRadius(20)
    }

    private func restoreTabBarAfterPresentation() {
        if let restoreTabBarChrome {
            restoreTabBarChrome()
        } else {
            services.suppressTabBarUntilTintRestored = false
            services.isCardDetailPresentationActive = false
            services.isSealedDetailPresentationActive = false
            BindrApp.reapplyTabBarAppearanceAfterPresentation(accent: services.theme.accentColor)
        }
    }
}

private struct SealedProductDetailPage: View {
    @Environment(AppServices.self) private var services
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @Query private var collectionItems: [CollectionItem]

    let product: SealedProduct

    @State private var showAddSheet = false
    @State private var showWishlistPaywall = false
    @State private var wishlistAlertMessage: String?
    @State private var showWishlistAlert = false
    @State private var isWishlisted = false
    @State private var shareProduct: SealedProduct? = nil
    @State private var editingItem: CollectionItem?
    @State private var markAsSession: SealedCollectionMarkAsSession?

    init(product: SealedProduct) {
        self.product = product
        let cardID = SealedProduct.collectionCardID(productID: product.id)
        _collectionItems = Query(filter: #Predicate<CollectionItem> { $0.cardID == cardID })
    }

    private var collectionCardID: String { SealedProduct.collectionCardID(productID: product.id) }

    private var sectionDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.07))
            .frame(height: 1)
    }

    private var dragPill: some View {
        Capsule(style: .continuous)
            .fill(Color.primary.opacity(colorScheme == .dark ? 0.35 : 0.22))
            .frame(width: 38, height: 5)
            .padding(.top, 8)
            .allowsHitTesting(false)
    }

    private func heroImageHeight(viewportHeight: CGFloat) -> CGFloat {
        guard viewportHeight > 0 else { return 240 }
        return min(280, max(180, viewportHeight * 0.3))
    }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    navigationChrome

                    productHeroSection(viewportHeight: geo.size.height)
                        .padding(.top, 4)

                    titleBlock
                        .padding(.top, 6)

                    actionButtons
                        .padding(.vertical, 4)

                    SealedProductPricingPanel(productID: product.id)
                        .padding(.vertical, 4)

                    if !visibleCollectionItems.isEmpty {
                        sectionDivider
                        collectionSection
                            .padding(.vertical, 4)
                    }

                    sectionDivider
                    recentSoldOnEbayRow
                        .padding(.vertical, 4)

                    sectionDivider
                    detailsSection
                        .padding(.vertical, 4)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)
            }
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
            .overlay(alignment: .top) { dragPill }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.clear)
        .onAppear {
            refreshWishlistState()
        }
        .sheet(isPresented: $showAddSheet) {
            AddSealedToCollectionSheet(product: product).environment(services)
        }
        .sheet(isPresented: $showWishlistPaywall) {
            PaywallSheet().environment(services)
        }
        .sheet(item: $shareProduct) { product in
            SocialShareSheet(item: .sealedProductDetail(product))
                .environment(services)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
        }
        .sheet(isPresented: Binding(get: { editingItem != nil }, set: { if !$0 { editingItem = nil } })) {
            if let editingItem {
                EditSealedCollectionItemSheet(item: editingItem, productName: product.name).environment(services)
            }
        }
        .sheet(item: $markAsSession) { session in
            SealedCollectionMarkAsSheet(item: session.item, productName: product.name, initialAction: session.initialAction).environment(services)
        }
        .alert("Wishlist", isPresented: $showWishlistAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(wishlistAlertMessage ?? "")
        }
    }

    private var navigationChrome: some View {
        HStack {
            ChromeGlassCircleButton(accessibilityLabel: "Close details") {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
            }

            Spacer()

            ChromeGlassCircleButton(accessibilityLabel: isWishlisted ? "Remove from Wish List" : "Add to Wish List") {
                toggleWishlist()
            } label: {
                Image(systemName: isWishlisted ? "star.fill" : "star")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isWishlisted ? Color(red: 0.98, green: 0.78, blue: 0.18) : .primary)
            }

            ChromeGlassCircleButton(accessibilityLabel: "Share") {
                shareProduct = product
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
            }
        }
        .frame(height: 42)
    }

    private func productHeroSection(viewportHeight: CGFloat) -> some View {
        CachedAsyncImage(url: product.imageURL, targetSize: CGSize(width: 800, height: 800)) { image in
            image
                .resizable()
                .scaledToFit()
        } placeholder: {
            Color(uiColor: .tertiarySystemFill)
                .aspectRatio(1, contentMode: .fit)
        }
        .frame(height: heroImageHeight(viewportHeight: viewportHeight))
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.15 : 0.40), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 10, y: 6)
    }

    private var titleBlock: some View {
        VStack(spacing: 4) {
            Text(product.name)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
            centeredSetBlock
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var centeredSetBlock: some View {
        if let set = matchedSet, !set.logoSrc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            SetLogoAsyncImage(
                logoSrc: set.logoSrc,
                height: 22,
                brand: services.brandSettings.selectedCatalogBrand
            )
            .frame(maxWidth: 140, minHeight: 26)
        } else if let series = displaySeries {
            Text(series)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .center)
        } else {
            Color.clear
                .frame(width: 140, height: 26)
        }
    }

    private var collectionButton: some View {
        Button {
            Haptics.lightImpact()
            showAddSheet = true
        } label: {
            Label(isOwned ? "Add Copy" : "Add to Collection", systemImage: "plus.circle.fill")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Color(red: 0.12, green: 0.67, blue: 0.28), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            collectionButton

            if isOwned {
                Button {
                    openRemoveFromCollectionFlow()
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color(red: 0.88, green: 0.22, blue: 0.24))
                        .frame(width: 44, height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(red: 0.95, green: 0.27, blue: 0.27).opacity(0.12))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color(red: 0.95, green: 0.27, blue: 0.27).opacity(0.30), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove from Collection")
            }
        }
    }

    private var visibleCollectionItems: [CollectionItem] {
        collectionItems
            .filter { $0.itemKind == ProductKind.sealedProduct.rawValue && $0.quantity > 0 }
            .sorted { $0.dateAcquired > $1.dateAcquired }
    }

    private var collectionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your Collection")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(visibleCollectionItems, id: \.persistentModelID) { item in
                Button {
                    editingItem = item
                } label: {
                    HStack(spacing: 12) {
                        Text("Sealed")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(services.theme.accentColor)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(services.theme.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))

                        collectionValue(label: "Qty", value: "\(item.quantity)")
                        collectionValue(
                            label: "Paid",
                            value: item.purchasePrice.map { formatCurrency(amount: $0, code: services.priceDisplay.currency == .gbp ? "GBP" : "USD") } ?? "—"
                        )
                        collectionValue(
                            label: "Added",
                            value: item.dateAcquired.formatted(date: .abbreviated, time: .omitted)
                        )

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func collectionValue(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Details")
                .font(.caption)
                .foregroundStyle(.secondary)

            let facts: [(String, String)] = [
                ("Release", releaseDateDisplay),
                ("Type", product.typeDisplayName),
                product.series.flatMap { $0.isEmpty ? nil : ("Series", $0) },
                product.language.flatMap { $0.isEmpty ? nil : ("Language", $0) },
                product.year.map { ("Year", String($0)) },
            ].compactMap { $0 }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                spacing: 10
            ) {
                ForEach(facts, id: \.0) { fact in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(fact.0)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(fact.1)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .topLeading)
                }
            }
        }
    }

    private var releaseDateDisplay: String {
        if let date = product.releaseDate {
            return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none)
        }
        return product.releaseDateRaw.flatMap { $0.isEmpty ? nil : $0 } ?? "Unknown"
    }

    private var recentSoldOnEbayRow: some View {
        Button {
            guard let url = ebayRecentSoldURL else { return }
            openURL(url)
        } label: {
            HStack(spacing: 10) {
                ebayWordmark
                VStack(alignment: .leading, spacing: 1) {
                    Text("View on eBay")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("See latest listings and sold items")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }


    private var ebayWordmark: some View {
        HStack(spacing: 0) {
            Text("e").foregroundStyle(Color(red: 0.89, green: 0.15, blue: 0.13))
            Text("B").foregroundStyle(Color(red: 0.00, green: 0.38, blue: 0.75))
            Text("a").foregroundStyle(Color(red: 0.97, green: 0.74, blue: 0.06))
            Text("y").foregroundStyle(Color(red: 0.44, green: 0.68, blue: 0.11))
        }
        .font(.system(size: 20, weight: .bold, design: .rounded))
        .frame(width: 74, alignment: .leading)
    }

    private var ebayRecentSoldURL: URL? {
        let searchText = [
            product.name.trimmingCharacters(in: .whitespacesAndNewlines),
            (product.setName ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            product.year.map(String.init) ?? ""
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !searchText.isEmpty else { return nil }

        var components = URLComponents(string: "https://www.ebay.com/sch/i.html")
        components?.queryItems = [
            URLQueryItem(name: "_nkw", value: searchText),
            URLQueryItem(name: "LH_Sold", value: "1"),
            URLQueryItem(name: "LH_Complete", value: "1")
        ]
        return components?.url
    }

    private func formatCurrency(amount: Double, code: String) -> String {
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.currencyCode = code
        fmt.maximumFractionDigits = 2
        return fmt.string(from: NSNumber(value: amount)) ?? String(format: "%.2f", amount)
    }

    private var isOwned: Bool {
        collectionItems.contains { $0.itemKind == ProductKind.sealedProduct.rawValue && $0.quantity > 0 }
    }

    private func openRemoveFromCollectionFlow() {
        guard let item = visibleCollectionItems.first else { return }
        markAsSession = SealedCollectionMarkAsSession(item: item, initialAction: .sold)
    }

    private func toggleWishlist() {
        guard let wishlist = services.wishlist else {
            wishlistAlertMessage = "Wishlist isn't available yet. Try again in a moment."
            showWishlistAlert = true
            return
        }
        if isWishlisted {
            do {
                try wishlist.removeCardVariant(cardID: collectionCardID, variantKey: "sealed")
                isWishlisted = false
            } catch {
                wishlistAlertMessage = error.localizedDescription
                showWishlistAlert = true
            }
            return
        }
        guard wishlist.canAddItem else { showWishlistPaywall = true; return }
        do {
            try wishlist.addItem(cardID: collectionCardID, variantKey: "sealed")
            isWishlisted = true
        } catch WishlistError.limitReached {
            showWishlistPaywall = true
        } catch {
            wishlistAlertMessage = error.localizedDescription
            showWishlistAlert = true
        }
    }

    private func refreshWishlistState() {
        guard let wishlist = services.wishlist else { isWishlisted = false; return }
        isWishlisted = wishlist.items.contains { $0.cardID == collectionCardID && $0.variantKey == "sealed" }
    }

    private var matchedSet: TCGSet? {
        let sets = services.cardData.sets
        if let setName = normalized(product.setName) {
            if let match = sets.first(where: { normalized($0.name) == setName }) { return match }
        }
        if let series = normalized(product.series) {
            if let match = sets.first(where: { normalized($0.name) == series }) { return match }
            if let match = sets.first(where: { normalized($0.seriesName) == series }) { return match }
        }
        return nil
    }

    private var displaySeries: String? { trimmed(product.series) }

    private func trimmed(_ value: String?) -> String? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        return raw
    }

    private func normalized(_ value: String?) -> String? { trimmed(value)?.lowercased() }
}

private enum SealedChartRange: String, CaseIterable {
    case oneMonth = "1M"
    case oneYear = "1Y"
    case all = "ALL"
}

private enum SealedChartDataResolution {
    case daily
    case weekly
    case monthly
}

private struct SealedProductPricingPanel: View {
    @Environment(AppServices.self) private var services
    @Environment(\.colorScheme) private var colorScheme

    let productID: Int

    @State private var history: SealedProductHistorySeries?
    @State private var currentPrice = "—"
    @State private var livePriceUSD: Double?
    @State private var chartRange: SealedChartRange = .oneMonth
    @State private var scrubPoint: PriceDataPoint? = nil
    @State private var isLoading = false

    private var chartDailyPoints: [PriceDataPoint] {
        (history?.daily ?? []).pinningTodayPrice(livePriceUSD)
    }

    private var resolvedChart: (points: [PriceDataPoint], resolution: SealedChartDataResolution) {
        let dailyWithToday = chartDailyPoints
        let daily31 = Array(dailyWithToday.suffix(31))
        let weeklySource = history.flatMap { $0.weekly.isEmpty ? nil : $0.weekly } ?? weeklyFromDaily(dailyWithToday)
        let weekly13 = Array(weeklySource.suffix(13))
        let monthlySource = history.flatMap { $0.monthly.isEmpty ? nil : $0.monthly } ?? monthlyFromDaily(dailyWithToday)
        let monthly12 = Array(monthlySource.suffix(12))

        switch chartRange {
        case .oneMonth:
            if !daily31.isEmpty { return (daily31, .daily) }
            if !weekly13.isEmpty { return (weekly13, .weekly) }
            if !monthly12.isEmpty { return (monthly12, .monthly) }
        case .oneYear:
            if !monthly12.isEmpty { return (monthly12, .monthly) }
            if !weekly13.isEmpty { return (weekly13, .weekly) }
            if !daily31.isEmpty { return (daily31, .daily) }
        case .all:
            if !dailyWithToday.isEmpty { return (dailyWithToday, .daily) }
            if !weeklySource.isEmpty { return (weeklySource, .weekly) }
            if !monthlySource.isEmpty { return (monthlySource, .monthly) }
        }
        return ([], .daily)
    }

    private func weeklyFromDaily(_ daily: [PriceDataPoint]) -> [PriceDataPoint] {
        let tuples = daily.map { [$0.label, String($0.price)] }
        return BucketDateMath.weeklyAverages(from: tuples, limit: 13).compactMap { pair in
            guard pair.count >= 2, let price = Double(pair[1]) else { return nil }
            return PriceDataPoint(id: pair[0], label: pair[0], price: price)
        }
    }

    private func monthlyFromDaily(_ daily: [PriceDataPoint]) -> [PriceDataPoint] {
        let tuples = daily.map { [$0.label, String($0.price)] }
        return BucketDateMath.monthlyAverages(from: tuples, limit: 12).compactMap { pair in
            guard pair.count >= 2, let price = Double(pair[1]) else { return nil }
            return PriceDataPoint(id: pair[0], label: pair[0], price: price)
        }
    }

    private var change1d: Double? { pctChange(Array(chartDailyPoints.suffix(2))) }
    private var change7d: Double? { pctChange(Array(chartDailyPoints.suffix(8))) }
    private var change30d: Double? { pctChange(Array(chartDailyPoints.suffix(31))) }

    private func pctChange(_ pts: [PriceDataPoint]) -> Double? {
        guard pts.count >= 2, pts.first!.price > 0 else { return nil }
        return ((pts.last!.price - pts.first!.price) / pts.first!.price) * 100
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(scrubPoint != nil ? scrubLabel(scrubPoint!.label) : "Market Price")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .animation(.none, value: scrubPoint?.label)

                    Text(scrubPoint != nil
                         ? services.priceDisplay.currency.format(amountUSD: scrubPoint!.price, usdToGbp: services.pricing.usdToGbp)
                         : currentPrice)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .animation(.none, value: scrubPoint?.price)

                    if let dailyChange = change1d {
                        HStack(spacing: 5) {
                            Image(systemName: dailyChange >= 0 ? "arrow.up" : "arrow.down")
                            Text("\(String(format: "%.1f%%", abs(dailyChange))) today")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(dailyChange >= 0 ? SealedPricingPalette.success : SealedPricingPalette.danger)
                    }
                }
                Spacer(minLength: 0)
            }

            if !resolvedChart.points.isEmpty {
                chartRangePicker
                chartView
            } else if isLoading {
                ProgressView()
                    .tint(.primary)
                    .padding(.vertical, 24)
            } else {
                Spacer().frame(height: 16)
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: "\(productID)|\(services.priceDisplay.currency.rawValue)|\(services.pricing.usdToGbp)") {
            isLoading = true
            history = services.sealedProducts.history(for: productID)
            refreshPrice()
            isLoading = false
        }
        .onChange(of: services.priceDisplay.currency) { _, _ in refreshPrice() }
        .onChange(of: services.pricing.usdToGbp) { _, _ in refreshPrice() }
    }

    private var chartRangePicker: some View {
        HStack(spacing: 0) {
            ForEach(SealedChartRange.allCases, id: \.self) { range in
                let isSelected = chartRange == range
                Button {
                    guard chartRange != range else { return }
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        chartRange = range
                    }
                    Haptics.lightImpact()
                } label: {
                    Text(range.rawValue)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : .primary.opacity(0.82))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background {
                            if isSelected {
                                Capsule(style: .continuous)
                                    .fill(services.theme.accentColor)
                                    .shadow(
                                        color: services.theme.accentColor.opacity(0.20),
                                        radius: 4,
                                        y: 2
                                    )
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var panelDivider: Color {
        BindrGlassStyle.insetBorder(colorScheme)
    }

    private var chartView: some View {
        let points = resolvedChart.points
        let prices = points.map(\.price)
        let minP = (prices.min() ?? 0) * 0.97
        let maxP = (prices.max() ?? 1) * 1.03

        return Chart(points) { point in
            AreaMark(
                x: .value("Date", point.label),
                yStart: .value("Min", minP),
                yEnd: .value("Price", point.price)
            )
            .interpolationMethod(.linear)
            .foregroundStyle(
                LinearGradient(
                    colors: [
                        services.theme.accentColor.opacity(0.70),
                        services.theme.accentColor.opacity(0.28),
                        .clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            LineMark(
                x: .value("Date", point.label),
                y: .value("Price", point.price)
            )
            .interpolationMethod(.linear)
            .foregroundStyle(services.theme.accentColor)
            .lineStyle(StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        }
        .chartYScale(domain: minP...maxP)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geo in
                if let plotAnchor = proxy.plotFrame {
                    let plotFrame = geo[plotAnchor]
                    if let scrub = scrubPoint, let xPos = proxy.position(forX: scrub.label) {
                        let x = xPos + plotFrame.origin.x
                        Rectangle()
                            .fill(panelDivider)
                            .frame(width: 1.5).frame(maxHeight: .infinity)
                            .offset(x: x - 0.75).allowsHitTesting(false)
                        if let yPos = proxy.position(forY: scrub.price) {
                            Circle().fill(services.theme.accentColor)
                                .frame(width: 8, height: 8)
                                .offset(x: x - 4, y: plotFrame.origin.y + yPos - 4)
                                .allowsHitTesting(false)
                        }
                    }
                    Rectangle().fill(Color.clear).contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let x = value.location.x - plotFrame.origin.x
                                guard x >= 0, x <= plotFrame.width else { return }
                                if let label: String = proxy.value(atX: x) {
                                    scrubPoint = nearestPoint(to: label, in: points)
                                }
                            }
                            .onEnded { _ in scrubPoint = nil }
                        )
                }
            }
        }
        .frame(height: 130)
        .padding(.horizontal, -16)
    }

    private func refreshPrice() {
        guard let usd = services.sealedProducts.marketPriceUSD(for: productID) else {
            currentPrice = "—"
            livePriceUSD = nil
            return
        }
        livePriceUSD = usd
        currentPrice = services.priceDisplay.currency.format(amountUSD: usd, usdToGbp: services.pricing.usdToGbp)
    }

    @ViewBuilder
    private func changeBadge(label: String, value: Double?) -> some View {
        if let value {
            HStack(spacing: 3) {
                Text(label).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Image(systemName: value >= 0 ? "arrow.up" : "arrow.down").font(.system(size: 9, weight: .bold))
                Text(String(format: "%.1f%%", abs(value))).font(.caption.weight(.semibold))
            }
            .foregroundStyle(value >= 0 ? SealedPricingPalette.success : SealedPricingPalette.danger)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill((value >= 0 ? SealedPricingPalette.success : SealedPricingPalette.danger).opacity(0.15)))
        }
    }

    private func truncatedLabel(_ label: String) -> String {
        switch resolvedChart.resolution {
        case .daily: return dailyToShortUK(label)
        case .weekly: return weekLabelToShortUK(label)
        case .monthly: return monthLabelToShort(label)
        }
    }

    private static let weekShortFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "dd/MM"; f.timeZone = TimeZone(identifier: "UTC"); return f
    }()
    private static let weekFullFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "dd/MM/yy"; f.timeZone = TimeZone(identifier: "UTC"); return f
    }()
    private static let iso8601Cal: Calendar = {
        var c = Calendar(identifier: .iso8601); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }()
    private static let shortMonthSymbols: [String] = DateFormatter().shortMonthSymbols

    private func scrubLabel(_ label: String) -> String {
        switch resolvedChart.resolution {
        case .daily: return dailyToFullUK(label)
        case .weekly: return weekLabelToFullUK(label)
        case .monthly:
            let parts = label.components(separatedBy: "-")
            guard parts.count == 2, let month = Int(parts[1]) else { return label }
            return "\(Self.shortMonthSymbols[month - 1]) \(parts[0])"
        }
    }

    private func dailyToShortUK(_ label: String) -> String {
        let p = label.components(separatedBy: "-")
        guard p.count == 3 else { return label }
        return "\(p[2])/\(p[1])"
    }

    private func dailyToFullUK(_ label: String) -> String {
        let p = label.components(separatedBy: "-")
        guard p.count == 3, p[0].count == 4 else { return label }
        return "\(p[2])/\(p[1])/\(String(p[0].suffix(2)))"
    }

    private func weekLabelToShortUK(_ label: String) -> String {
        guard let date = weekLabelToDate(label) else { return label }
        return Self.weekShortFormatter.string(from: date)
    }

    private func weekLabelToFullUK(_ label: String) -> String {
        guard let date = weekLabelToDate(label) else { return label }
        return Self.weekFullFormatter.string(from: date)
    }

    private func weekLabelToDate(_ label: String) -> Date? {
        let parts = label.components(separatedBy: "-W")
        guard parts.count == 2, let year = Int(parts[0]), let week = Int(parts[1]) else { return nil }
        return Self.iso8601Cal.date(from: DateComponents(weekOfYear: week, yearForWeekOfYear: year))
    }

    private func monthLabelToShort(_ label: String) -> String {
        let p = label.components(separatedBy: "-")
        guard p.count == 2, let month = Int(p[1]) else { return label }
        return Self.shortMonthSymbols[month - 1]
    }

    private func nearestPoint(to label: String, in points: [PriceDataPoint]) -> PriceDataPoint? {
        guard !points.isEmpty else { return nil }
        if let exact = points.first(where: { $0.label == label }) { return exact }
        let sorted = points.sorted { $0.label < $1.label }
        for (i, p) in sorted.enumerated() {
            if p.label > label { return i == 0 ? p : sorted[i - 1] }
        }
        return sorted.last
    }
}

private enum SealedActionPalette {
    static let success = Color(red: 0.22, green: 0.81, blue: 0.44)
    static let danger = Color(red: 1.0, green: 0.36, blue: 0.34)
    static let gold = Color(red: 0.98, green: 0.78, blue: 0.18)
    static let share = Color(red: 0.36, green: 0.61, blue: 0.97)
}

private enum SealedPricingPalette {
    static let success = Color(red: 0.28, green: 0.84, blue: 0.39)
    static let danger = Color(red: 1.0, green: 0.36, blue: 0.34)
    static let gold = Color(red: 0.97, green: 0.74, blue: 0.06)
    static let actionBlue = Color(red: 0.12, green: 0.52, blue: 1.0)
}

private struct SealedCollectionMarkAsSession: Identifiable {
    let id = UUID()
    let item: CollectionItem
    let initialAction: SealedCollectionMarkAsAction
}

private enum SealedCollectionMarkAsAction: String, CaseIterable, Identifiable {
    case opened
    case sold
    case traded
    case gifted
    case lost
    case damaged

    var id: String { rawValue }

    var title: String {
        switch self {
        case .opened: return "Opened"
        case .sold: return "Sold"
        case .traded: return "Traded"
        case .gifted: return "Gifted"
        case .lost: return "Lost"
        case .damaged: return "Damaged"
        }
    }

    var dispositionKind: CollectionDispositionKind? {
        switch self {
        case .opened:
            return nil
        case .sold:
            return .sold
        case .traded:
            return .traded
        case .gifted:
            return .gifted
        case .lost:
            return .lost
        case .damaged:
            return .damaged
        }
    }
}

private struct SealedCollectionMarkAsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppServices.self) private var services
    @Environment(\.colorScheme) private var colorScheme

    let item: CollectionItem
    let productName: String
    let initialAction: SealedCollectionMarkAsAction

    @State private var action: SealedCollectionMarkAsAction
    @State private var quantity: Int = 1
    @State private var priceText: String = ""
    @State private var counterparty: String = ""
    @State private var notes: String = ""
    @State private var errorMessage: String?

    init(item: CollectionItem, productName: String, initialAction: SealedCollectionMarkAsAction) {
        self.item = item
        self.productName = productName
        self.initialAction = initialAction
        _action = State(initialValue: initialAction)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(productName)
                        .font(.headline)
                    Text("In collection: \(item.quantity)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Picker("Status", selection: $action) {
                        ForEach(SealedCollectionMarkAsAction.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                }

                Section {
                    Stepper("Quantity: \(quantity)", value: $quantity, in: 1...max(item.quantity, 1))
                }

                if action == .sold {
                    Section {
                        TextField("Sold price per item", text: $priceText)
                            .keyboardType(.decimalPad)
                    }
                }

                if action != .opened {
                    Section {
                        TextField(counterpartyLabel, text: $counterparty)
                        TextField("Notes", text: $notes, axis: .vertical)
                            .lineLimit(2...6)
                    }
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
            .navigationTitle("Mark As")
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
            }
        }
    }

    private var counterpartyLabel: String {
        switch action {
        case .opened: return ""
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
            errorMessage = "Collection isn't ready. Try again."
            return
        }

        do {
            if action == .opened {
                try ledger.recordSealedProductOpened(
                    item: item,
                    quantity: quantity,
                    productName: productName
                )
                dismiss()
                return
            }

            guard let dispositionKind = action.dispositionKind else { return }
            try ledger.recordSealedProductDisposition(
                item: item,
                kind: dispositionKind,
                quantity: quantity,
                currencyCode: services.priceDisplay.currency == .gbp ? "GBP" : "USD",
                productName: productName,
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
            throw SealedCollectionMarkAsSheetError.invalidPrice
        }
        return value
    }
}

private enum SealedCollectionMarkAsSheetError: LocalizedError {
    case invalidPrice

    var errorDescription: String? {
        switch self {
        case .invalidPrice:
            return "Enter a valid price."
        }
    }
}

struct OpenSealedCollectionItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppServices.self) private var services

    let item: CollectionItem
    let productName: String

    @State private var quantity: Int
    @State private var errorMessage: String?

    init(item: CollectionItem, productName: String) {
        self.item = item
        self.productName = productName
        _quantity = State(initialValue: min(max(item.quantity, 1), 999))
    }

    private var headerButtonColor: Color {
        colorScheme == .dark ? .white : .black
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(productName)
                        .font(.headline)
                    Text("In collection: \(item.quantity)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Stepper("Open quantity: \(quantity)", value: $quantity, in: 1...max(item.quantity, 1))
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Mark Opened")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(headerButtonColor)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .foregroundStyle(headerButtonColor)
                }
            }
        }
        .tint(headerButtonColor)
    }

    private func save() {
        errorMessage = nil
        guard let ledger = services.collectionLedger else {
            errorMessage = "Collection isn't ready. Try again."
            return
        }
        do {
            try ledger.recordSealedProductOpened(
                item: item,
                quantity: quantity,
                productName: productName
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct EditSealedCollectionItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext

    let item: CollectionItem
    let productName: String

    @State private var quantity: Int
    @State private var occurredAt: Date
    @State private var unitPriceText: String
    @State private var counterparty: String
    @State private var sourceDescription: String
    @State private var notes: String
    @State private var errorMessage: String?

    init(item: CollectionItem, productName: String) {
        self.item = item
        self.productName = productName
        _quantity = State(initialValue: max(item.quantity, 1))
        _occurredAt = State(initialValue: item.dateAcquired)
        _unitPriceText = State(initialValue: item.purchasePrice.map { String($0) } ?? "")
        let primaryLine = (item.costLots ?? [])
            .sorted { $0.createdAt > $1.createdAt }
            .compactMap(\.sourceLedgerLine)
            .first
        _counterparty = State(initialValue: primaryLine?.counterparty ?? "")
        _sourceDescription = State(initialValue: primaryLine?.lineDescription ?? productName)
        _notes = State(initialValue: item.notes)
    }

    private var headerButtonColor: Color {
        colorScheme == .dark ? .white : .black
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(productName)
                        .font(.headline)
                    Text("In collection: \(item.quantity)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Stepper("Quantity: \(quantity)", value: $quantity, in: 1...999)
                }

                Section {
                    DatePicker("Date", selection: $occurredAt, displayedComponents: .date)
                    TextField("Bought value / unit price", text: $unitPriceText)
                        .keyboardType(.decimalPad)
                    TextField("Source", text: $counterparty)
                    TextField("Details", text: $sourceDescription, axis: .vertical)
                        .lineLimit(2...5)
                }

                Section {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Edit in collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(headerButtonColor)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .foregroundStyle(headerButtonColor)
                }
            }
        }
        .tint(headerButtonColor)
    }

    private func save() {
        errorMessage = nil
        do {
            let trimmedCounterparty = counterparty.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedDescription = sourceDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            let parsedUnitPrice = try parsedOptionalPrice(unitPriceText)
            let lots = (item.costLots ?? []).filter { $0.quantityRemaining > 0 }

            if !lots.isEmpty {
                var remaining = quantity
                let sorted = lots.sorted { $0.createdAt > $1.createdAt }
                for lot in sorted {
                    let assigned = min(remaining, lot.quantityRemaining)
                    lot.quantityRemaining = assigned
                    remaining -= assigned
                }
                if remaining > 0, let first = sorted.first {
                    first.quantityRemaining += remaining
                }
            }

            item.quantity = quantity
            item.dateAcquired = occurredAt
            item.purchasePrice = parsedUnitPrice
            item.notes = notes

            for lot in lots {
                if let ledgerLine = lot.sourceLedgerLine {
                    ledgerLine.occurredAt = occurredAt
                    ledgerLine.unitPrice = parsedUnitPrice
                    ledgerLine.counterparty = trimmedCounterparty.isEmpty ? nil : trimmedCounterparty
                    ledgerLine.lineDescription = trimmedDescription.isEmpty ? productName : trimmedDescription
                    ledgerLine.quantity = lots
                        .filter { $0.sourceLedgerLine?.id == ledgerLine.id }
                        .reduce(0) { $0 + $1.quantityRemaining }
                }
            }

            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func parsedOptionalPrice(_ text: String) throws -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let value = Double(trimmed.replacingOccurrences(of: ",", with: ".")) else {
            throw EditSealedValidationError.invalidPrice
        }
        return value
    }
}

private enum EditSealedValidationError: LocalizedError {
    case invalidPrice

    var errorDescription: String? {
        switch self {
        case .invalidPrice:
            return "Enter a valid price."
        }
    }
}

struct AddSealedToCollectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppServices.self) private var services

    let product: SealedProduct

    @State private var acquisitionKind: CollectionAcquisitionKind = .bought
    @State private var quantity: Int = 1
    @State private var occurredAt: Date = Date()
    @State private var priceText: String = ""
    @State private var errorMessage: String?
    @State private var showPaywall = false

    private var currencyCode: String {
        switch services.priceDisplay.currency {
        case .usd: return "USD"
        case .gbp: return "GBP"
        }
    }

    private var currencySymbol: String {
        services.priceDisplay.currency.symbol
    }

    private var headerButtonColor: Color {
        colorScheme == .dark ? .white : .black
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(product.name)
                        .font(.headline)
                    Text(product.typeDisplayName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Picker("Acquired by", selection: $acquisitionKind) {
                        Text(CollectionAcquisitionKind.bought.title).tag(CollectionAcquisitionKind.bought)
                        Text("Traded").tag(CollectionAcquisitionKind.trade)
                        Text(CollectionAcquisitionKind.gifted.title).tag(CollectionAcquisitionKind.gifted)
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Stepper("Quantity: \(quantity)", value: $quantity, in: 1...999)
                }

                Section {
                    DatePicker("Date", selection: $occurredAt, displayedComponents: .date)
                }

                if acquisitionKind == .bought {
                    Section {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Price per unit")
                            Spacer()
                            HStack(spacing: 6) {
                                Text(currencySymbol)
                                    .foregroundStyle(.secondary)
                                TextField("0.00", text: $priceText)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(minWidth: 72)
                            }
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Add to collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(headerButtonColor)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .foregroundStyle(headerButtonColor)
                }
            }
        }
        .tint(headerButtonColor)
        .sheet(isPresented: $showPaywall) {
            PaywallSheet().environment(services)
        }
    }

    private func parseRequiredPrice(_ text: String) throws -> Double {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AddSealedToCollectionValidation.missingPrice }
        guard let value = Double(trimmed.replacingOccurrences(of: ",", with: ".")) else {
            throw AddSealedToCollectionValidation.invalidPrice
        }
        return value
    }

    private func save() {
        errorMessage = nil
        guard let ledger = services.collectionLedger else {
            errorMessage = "Collection isn't ready. Try again."
            return
        }

        do {
            let unitPrice: Double?
            if acquisitionKind == .bought {
                unitPrice = try parseRequiredPrice(priceText)
            } else {
                unitPrice = nil
            }

            try ledger.recordSealedProductAcquisition(
                sealedProductId: String(product.id),
                productName: product.name,
                quantity: quantity,
                kind: acquisitionKind,
                currencyCode: currencyCode,
                unitPrice: unitPrice,
                cardID: product.collectionCardID,
                occurredAt: occurredAt
            )
            dismiss()
        } catch AddSealedToCollectionValidation.missingPrice {
            errorMessage = "Enter a unit price."
        } catch AddSealedToCollectionValidation.invalidPrice {
            errorMessage = "Enter a valid unit price."
        } catch CollectionLedgerError.freeTierLimitReached {
            errorMessage = CollectionLedgerError.freeTierLimitReached.errorDescription
            showPaywall = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum AddSealedToCollectionValidation: Error {
    case missingPrice
    case invalidPrice
}

func normalizeSealedSearchText(_ value: String?) -> String {
    (value ?? "")
        .folding(options: [.diacriticInsensitive, .widthInsensitive, .caseInsensitive], locale: .current)
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
}

/// Precomputed normalized strings for every product in the feed, indexed by
/// the same position the product occupies in
/// ``SealedProductService.products``. Built once per product-list change and
/// read on the hot path (carousel build + per-tap set filtering) so name
/// matching never re-normalizes on every render.
struct NormalizedProductIndex: Equatable {
    private let names: [String]
    private let series: [String]
    private let setNames: [String]

    static let empty = NormalizedProductIndex(names: [], series: [], setNames: [])

    private init(names: [String], series: [String], setNames: [String]) {
        self.names = names
        self.series = series
        self.setNames = setNames
    }

    init(products: [SealedProduct]) {
        var n: [String] = []
        var s: [String] = []
        var sn: [String] = []
        n.reserveCapacity(products.count)
        s.reserveCapacity(products.count)
        sn.reserveCapacity(products.count)
        for product in products {
            n.append(normalizeSealedSearchText(product.name))
            s.append(normalizeSealedSearchText(product.series))
            sn.append(normalizeSealedSearchText(product.setName))
        }
        self.names = n
        self.series = s
        self.setNames = sn
    }

    func name(at index: Int) -> String {
        guard index >= 0, index < names.count else { return "" }
        return names[index]
    }

    func series(at index: Int) -> String {
        guard index >= 0, index < series.count else { return "" }
        return series[index]
    }

    func setName(at index: Int) -> String {
        guard index >= 0, index < setNames.count else { return "" }
        return setNames[index]
    }
}
