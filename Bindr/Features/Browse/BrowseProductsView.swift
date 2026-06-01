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
    @State private var addToFolderProduct: SealedProduct?
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
                                Button {
                                    addToFolderProduct = product
                                } label: {
                                    Label("Add to Folder", systemImage: "folder.badge.plus")
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
        .sheet(item: $addToFolderProduct) { product in
            AddSealedToFolderSheet(cardID: product.collectionCardID, variantKey: "sealed")
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

    private var tileBackground: Color {
        colorScheme == .dark ? .black : .white
    }

    private var tileBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.20) : Color.black.opacity(0.16)
    }

    private var insetBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.03) : Color.black.opacity(0.02)
    }

    private var dividerColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.06)
    }

    private var showsFooter: Bool {
        (gridOptions.showSetName && !(product.setName ?? "").isEmpty)
            || gridOptions.showSetID
            || gridOptions.showPricing
    }

    private var cardCornerRadius: CGFloat {
        showsFooter ? 18 : 0
    }

    private var imageHeight: CGFloat {
        let columns = min(max(gridOptions.columnCount, 1), 4)
        switch columns {
        case 1: return 180
        case 2: return 110
        case 3: return 80
        default: return 65
        }
    }

    /// Sealed products don't carry an element type, but we still want the
    /// chrome to feel "alive" — using the app's theme accent at low opacity
    /// gives the strip and footer the same colour-extending-from-the-card
    /// feel that ``CardGridCell`` gets from the Pokémon type, without picking
    /// a colour out of thin air.
    private var stripBackground: LinearGradient {
        let accent = services.theme.accentColor
        let strong = colorScheme == .dark ? 0.18 : 0.12
        let weak = colorScheme == .dark ? 0.04 : 0.02
        return LinearGradient(
            stops: [
                .init(color: accent.opacity(weak), location: 0.0),
                .init(color: accent.opacity(weak * 1.6), location: 0.5),
                .init(color: accent.opacity(strong), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var footerAccentBackground: LinearGradient {
        let accent = services.theme.accentColor
        let strong = colorScheme == .dark ? 0.16 : 0.10
        let weak = colorScheme == .dark ? 0.04 : 0.02
        return LinearGradient(
            stops: [
                .init(color: accent.opacity(strong), location: 0.0),
                .init(color: accent.opacity(weak * 1.5), location: 0.6),
                .init(color: accent.opacity(weak), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
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
                    .background(tileBackground)
                    .background(stripBackground)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(dividerColor).frame(height: 1)
                    }
            }

            SealedThumbnailView(
                imageURL: product.imageURL,
                isOwned: isOwned,
                isWishlisted: isWishlisted,
                ownedCountBadge: ownedCountBadge
            )
            .frame(maxWidth: .infinity)
            .frame(height: imageHeight)
            .clipped()

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
                .background(tileBackground)
                .background(footerAccentBackground)
                .overlay(alignment: .top) {
                    Rectangle().fill(dividerColor).frame(height: 1)
                }
            }
        }
        .background(tileBackground)
        .contentShape(Rectangle())
        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .stroke(isOwned ? services.theme.accentColor : isWishlisted ? Color.yellow : tileBorder, lineWidth: isOwned || isWishlisted ? 1.8 : 1.2)
        }
        .overlay {
            // Inner top highlight — matches CardGridCell + dashboard glass
            // styling. Skipped on owned state so the accent border isn't
            // muted by the white inner stroke.
            if !isOwned && !isWishlisted && cardCornerRadius > 0 {
                RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.10 : 0.32),
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                    .padding(0.5)
                    .allowsHitTesting(false)
            }
        }
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

    @Environment(\.colorScheme) private var colorScheme
    @State private var scrollIndex: Int?
    @State private var auraColorsByProductID: [Int: [Color]] = [:]

    init(products: [SealedProduct], startProductID: Int) {
        self.products = products
        let start = products.firstIndex(where: { $0.id == startProductID }) ?? 0
        _scrollIndex = State(initialValue: start)
    }

    private var currentProductID: Int? {
        guard let i = scrollIndex, products.indices.contains(i) else { return nil }
        return products[i].id
    }

    private var currentAuraColors: [Color] {
        let extracted = currentProductID.flatMap { auraColorsByProductID[$0] } ?? []
        if extracted.count >= 3 { return Array(extracted.prefix(3)) }
        if let first = extracted.first { return [first, first.opacity(0.74), first.opacity(0.52)] }
        return [Color(red: 0.50, green: 0.60, blue: 0.74),
                Color(red: 0.63, green: 0.52, blue: 0.76),
                Color(red: 0.72, green: 0.60, blue: 0.68)]
    }

    var body: some View {
        GeometryReader { geo in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(Array(products.indices), id: \.self) { i in
                        SealedProductDetailPage(
                            product: products[i],
                            onAuraColors: { colors in
                                auraColorsByProductID[products[i].id] = colors
                            }
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
        .background(sheetBackground)
        .presentationDragIndicator(.visible)
        .presentationDetents([.large])
        .presentationCornerRadius(20)
    }

    private var sheetBackground: some View {
        ZStack {
            colorScheme == .dark ? Color.black : Color.white
            currentAuraColors[0].opacity(colorScheme == .dark ? 0.30 : 0.16)
            LinearGradient(
                colors: [
                    currentAuraColors[1].opacity(colorScheme == .dark ? 0.24 : 0.14),
                    .clear,
                    currentAuraColors[2].opacity(colorScheme == .dark ? 0.24 : 0.14),
                ],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
        }
        .ignoresSafeArea()
    }
}

private struct SealedProductDetailPage: View {
    @Environment(AppServices.self) private var services
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Query private var collectionItems: [CollectionItem]

    let product: SealedProduct
    var onAuraColors: (([Color]) -> Void)? = nil

    @State private var auraColors: [Color] = []
    @State private var showAddSheet = false
    @State private var showWishlistPaywall = false
    @State private var wishlistAlertMessage: String?
    @State private var showWishlistAlert = false
    @State private var isWishlisted = false
    @State private var showAddToFolderSheet = false
    @State private var showShareSheet = false
    @State private var isMenuExpanded = false
    @State private var editingItem: CollectionItem?
    @State private var markAsSession: SealedCollectionMarkAsSession?

    init(product: SealedProduct, onAuraColors: (([Color]) -> Void)? = nil) {
        self.product = product
        self.onAuraColors = onAuraColors
        let cardID = SealedProduct.collectionCardID(productID: product.id)
        _collectionItems = Query(filter: #Predicate<CollectionItem> { $0.cardID == cardID })
    }

    private var collectionCardID: String { SealedProduct.collectionCardID(productID: product.id) }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    heroAndMeta

                    SealedProductPricingPanel(productID: product.id)
                        .glassCardStyle(cornerRadius: 26, interactive: false)
                        .padding(.horizontal, 12)

                    recentSoldOnEbayButton
                        .glassCardStyle(cornerRadius: 26, interactive: false)
                        .padding(.horizontal, 12)

                    if !visibleCollectionItems.isEmpty {
                        collectionSection
                            .padding(.horizontal, 12)
                    }

                    detailsSection
                        .padding(.horizontal, 12)
                }
                .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .topLeading)
                .padding(.bottom, 24)
            }
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            auraBackground
                .ignoresSafeArea()
        )
        .onAppear { refreshWishlistState() }
        .sheet(isPresented: $showAddSheet) {
            AddSealedToCollectionSheet(product: product).environment(services)
        }
        .sheet(isPresented: $showWishlistPaywall) {
            PaywallSheet().environment(services)
        }
        .sheet(isPresented: $showAddToFolderSheet) {
            AddSealedToFolderSheet(cardID: collectionCardID, variantKey: "sealed")
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: shareItems)
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

    private var heroAndMeta: some View {
        VStack(spacing: 12) {
            productHeroSection
                .padding(.top, 20)
                .padding(.horizontal, 24)

            VStack(spacing: 4) {
                Text(product.name)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
                centeredSetBlock
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 16)

            actionButtons
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
    }

    private var auraBackground: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(LinearGradient(
                    colors: resolvedAuraColors.map { $0.opacity(colorScheme == .dark ? 0.62 : 0.42) },
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(maxWidth: .infinity)
                .aspectRatio(4 / 3, contentMode: .fit)
                .blur(radius: colorScheme == .dark ? 32 : 26)
                .scaleEffect(1.16)

            LinearGradient(
                colors: [
                    resolvedAuraColors[0].opacity(colorScheme == .dark ? 0.34 : 0.20),
                    resolvedAuraColors[1].opacity(colorScheme == .dark ? 0.24 : 0.14),
                    resolvedAuraColors[2].opacity(colorScheme == .dark ? 0.14 : 0.09),
                    resolvedAuraColors[2].opacity(colorScheme == .dark ? 0.08 : 0.05),
                    resolvedAuraColors[2].opacity(colorScheme == .dark ? 0.04 : 0.02),
                    .clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 330)
            .blur(radius: colorScheme == .dark ? 20 : 15)
            .offset(y: -8)
        }
        .allowsHitTesting(false)
    }

    private var visibleCollectionItems: [CollectionItem] {
        collectionItems
            .filter { $0.itemKind == ProductKind.sealedProduct.rawValue && $0.quantity > 0 }
            .sorted { $0.dateAcquired > $1.dateAcquired }
    }

    private var collectionSection: some View {
        SealedDetailSurface(title: "My Collection") {
            VStack(spacing: 10) {
                ForEach(visibleCollectionItems, id: \.persistentModelID) { item in
                    collectionItemCard(item)
                }
            }
        }
    }

    private func collectionItemCard(_ item: CollectionItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(item.quantity) × Sealed")
                .font(.headline)
                .foregroundStyle(.primary)

            let sources = activeHoldingSources(for: item)
            if sources.isEmpty {
                Text("No source details recorded yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(sources) { source in
                        sourceRow(source, item: item)
                    }
                }
            }

            if let notes = cleaned(item.notes) {
                Text(notes).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    private func sourceRow(_ source: SealedHoldingSource, item: CollectionItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                infoBadge(label: source.directionTitle, tint: source.tint)
                Text("Qty \(source.quantity)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                if let priceText = source.priceText {
                    labelValueRow(label: "Price", value: priceText)
                }
                Spacer(minLength: 8)
                Text(source.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Spacer(minLength: 8)
                Button("Edit") { editingItem = item }
                    .buttonStyle(.bordered)
                    .tint(colorScheme == .dark ? .white : .black)
                Button("Mark As") { markAsSession = SealedCollectionMarkAsSession(item: item, initialAction: .opened) }
                    .buttonStyle(.borderedProminent)
                    .tint(SealedPricingPalette.actionBlue)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(sectionInsetBackground.opacity(0.55)))
    }

    private var detailsSection: some View {
        SealedDetailSurface(title: "Details") {
            let facts: [(String, String)] = [
                ("Release", releaseDateDisplay),
                ("Type", product.typeDisplayName),
                product.series.flatMap { $0.isEmpty ? nil : ("Series", $0) },
                product.language.flatMap { $0.isEmpty ? nil : ("Language", $0) },
                product.year.map { ("Year", String($0)) },
            ].compactMap { $0 }

            let rows = stride(from: 0, to: facts.count, by: 2).map {
                Array(facts[$0..<min($0 + 2, facts.count)])
            }
            VStack(spacing: 10) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 12) {
                        ForEach(row, id: \.0) { fact in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(fact.0)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(fact.1)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(sectionInsetBackground))
                        }
                        if row.count < 2 { Color.clear.frame(maxWidth: .infinity) }
                    }
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

    private var sectionInsetBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.03)
    }

    private var recentSoldOnEbayButton: some View {
        Button {
            guard let url = ebayRecentSoldURL else { return }
            openURL(url)
        } label: {
            HStack(spacing: 14) {
                ebayWordmarkBadge
                VStack(alignment: .leading, spacing: 3) {
                    Text("Recent Sold on eBay")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("Open sold listings for this product")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05), in: Circle())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(minHeight: 76)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .accessibilityLabel("Open recent sold listings on eBay")
    }

    private var ebayWordmarkBadge: some View {
        ebayWordmark
            .frame(width: 74, height: 42)
            .background(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.70), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.05), lineWidth: 1)
            }
    }

    private var ebayWordmark: some View {
        HStack(spacing: 0) {
            Text("e").foregroundStyle(Color(red: 0.89, green: 0.15, blue: 0.13))
            Text("B").foregroundStyle(Color(red: 0.00, green: 0.38, blue: 0.75))
            Text("a").foregroundStyle(Color(red: 0.97, green: 0.74, blue: 0.06))
            Text("y").foregroundStyle(Color(red: 0.44, green: 0.68, blue: 0.11))
        }
        .font(.system(size: 24, weight: .bold, design: .rounded))
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

    private func labelValueRow(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label + ":").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.caption.weight(.medium)).foregroundStyle(.primary)
        }
    }

    private func infoBadge(label: String, tint: Color) -> some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule(style: .continuous).fill(tint.opacity(0.14)))
    }

    private func activeHoldingSources(for item: CollectionItem) -> [SealedHoldingSource] {
        (item.costLots ?? [])
            .filter { $0.quantityRemaining > 0 }
            .sorted { $0.createdAt > $1.createdAt }
            .map { lot in
                let line = lot.sourceLedgerLine
                let direction = line.flatMap { LedgerDirection(rawValue: $0.direction) } ?? .bought
                let tint: Color
                switch direction {
                case .sold, .tradedOut, .giftedOut, .adjustmentOut: tint = SealedPricingPalette.danger
                default: tint = SealedPricingPalette.success
                }
                return SealedHoldingSource(
                    id: line?.id ?? UUID(),
                    quantity: lot.quantityRemaining,
                    date: line?.occurredAt ?? item.dateAcquired,
                    directionTitle: directionTitle(for: direction),
                    tint: tint,
                    priceText: line.flatMap { l in
                        guard let p = l.unitPrice, p > 0 else { return nil }
                        return formatCurrency(amount: p, code: l.currencyCode)
                    },
                    description: cleaned(line?.lineDescription)
                )
            }
    }

    private func directionTitle(for direction: LedgerDirection) -> String {
        switch direction {
        case .bought: return "Bought"
        case .packed: return "Packed"
        case .tradedIn: return "Traded In"
        case .giftedIn: return "Gifted"
        case .adjustmentIn: return "Adjusted In"
        case .sold: return "Sold"
        case .tradedOut: return "Traded Out"
        case .giftedOut: return "Gifted Out"
        case .adjustmentOut: return "Adjusted Out"
        }
    }

    private func formatCurrency(amount: Double, code: String) -> String {
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.currencyCode = code
        fmt.maximumFractionDigits = 2
        return fmt.string(from: NSNumber(value: amount)) ?? String(format: "%.2f", amount)
    }

    private func cleaned(_ text: String?) -> String? {
        guard let t = text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                toggleWishlist()
            } label: {
                Image(systemName: isWishlisted ? "star.fill" : "star")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color(red: 0.98, green: 0.78, blue: 0.18))
                    .frame(width: 56, height: 56)
                    .glassCardStyle(cornerRadius: 18, interactive: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isWishlisted ? "Remove from wishlist" : "Add to wishlist")

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isMenuExpanded.toggle()
                }
                Haptics.lightImpact()
            } label: {
                HStack(spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: isOwned ? "folder.fill" : "plus.circle.fill")
                            .font(.system(size: 18, weight: .bold))
                        Text(isOwned ? "Manage..." : "Add to...")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .fixedSize()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .bold))
                        .opacity(0.4)
                        .rotationEffect(.degrees(isMenuExpanded ? 180 : 0))
                }
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .foregroundStyle(isOwned ? Color(red: 0.36, green: 0.61, blue: 0.97) : SealedPricingPalette.success)
                .glassCardStyle(cornerRadius: 18, interactive: true)
            }
            .buttonStyle(.plain)

            Button { showShareSheet = true } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color(red: 0.36, green: 0.61, blue: 0.97))
                    .frame(width: 56, height: 56)
                    .glassCardStyle(cornerRadius: 18, interactive: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Share")
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .bottom) {
            if isMenuExpanded {
                sealedActionMenu
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.9, anchor: .bottom).combined(with: .opacity).combined(with: .move(edge: .bottom)),
                        removal: .scale(scale: 0.9, anchor: .bottom).combined(with: .opacity).combined(with: .move(edge: .bottom))
                    ))
                    .offset(y: -74)
                    .zIndex(100)
            }
        }
    }

    private var isOwned: Bool {
        collectionItems.contains { $0.itemKind == ProductKind.sealedProduct.rawValue && $0.quantity > 0 }
    }

    private var sealedActionMenu: some View {
        VStack(spacing: 0) {
            menuRow(label: "Add to Collection", subLabel: isOwned ? "Add more copies" : "Add to your collection", icon: "plus.circle.fill", color: SealedPricingPalette.success) {
                showAddSheet = true
            }
            Divider().padding(.horizontal, 20).opacity(0.06)
            menuRow(label: "Add to Folder", subLabel: "Save to a specific folder", icon: "folder.badge.plus", color: Color(red: 0.18, green: 0.72, blue: 0.88)) {
                showAddToFolderSheet = true
            }
        }
        .frame(width: 280)
        .glassCardStyle(cornerRadius: 26, interactive: true)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.15), radius: 25, y: 15)
    }

    private func menuRow(label: String, subLabel: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selectionChanged()
            action()
            withAnimation(.spring(response: 0.25)) { isMenuExpanded = false }
        } label: {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(color)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text(subLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var shareItems: [Any] {
        var items: [Any] = [product.name]
        if let url = product.imageURL { items.append(url) }
        return items
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

    private var resolvedAuraColors: [Color] {
        if auraColors.count >= 3 { return Array(auraColors.prefix(3)) }
        if let first = auraColors.first { return [first, first.opacity(0.74), first.opacity(0.52)] }
        return [
            Color(red: 0.50, green: 0.60, blue: 0.74),
            Color(red: 0.63, green: 0.52, blue: 0.76),
            Color(red: 0.72, green: 0.60, blue: 0.68)
        ]
    }

    private var productHeroSection: some View {
        CachedAsyncImage(url: product.imageURL, targetSize: CGSize(width: 800, height: 800)) { image in
            image
                .resizable()
                .scaledToFit()
                .onAppear { extractAuraColors(from: image) }
        } placeholder: {
            Color(uiColor: .tertiarySystemFill)
                .aspectRatio(3 / 4, contentMode: .fit)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.16 : 0.22), lineWidth: 1)
        )
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(LinearGradient(
                    colors: resolvedAuraColors.map { $0.opacity(colorScheme == .dark ? 0.78 : 0.56) },
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .blur(radius: colorScheme == .dark ? 30 : 24)
                .scaleEffect(1.12)
        )
        .frame(maxWidth: .infinity)
    }

    @MainActor
    private func extractAuraColors(from image: Image) {
        guard auraColors.isEmpty else { return }
        let renderer = ImageRenderer(content: image.resizable().frame(width: 44, height: 62))
        renderer.scale = 1
        guard let uiImage = renderer.uiImage else { return }
        Task.detached(priority: .utility) {
            let colors = uiImage.sealedAuraColors(maxColors: 3)
            guard !colors.isEmpty else { return }
            await MainActor.run {
                self.auraColors = colors
                self.onAuraColors?(colors)
            }
        }
    }

    @ViewBuilder
    private var centeredSetBlock: some View {
        if let set = matchedSet, !set.logoSrc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            SetLogoAsyncImage(
                logoSrc: set.logoSrc,
                height: 34,
                brand: services.brandSettings.selectedCatalogBrand
            )
            .frame(maxWidth: 140, minHeight: 40)
        } else if let series = displaySeries {
            Text(series)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .center)
        } else {
            Color.clear
                .frame(width: 140, height: 40)
        }
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

private struct SealedDetailSurface<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.primary)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCardStyle(cornerRadius: 26, interactive: false)
    }

}

struct AddSealedToFolderSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let cardID: String
    let variantKey: String

    @Query(sort: \CardFolder.createdAt, order: .reverse) private var folders: [CardFolder]

    @State private var showCreateAlert = false
    @State private var newFolderTitle = ""
    @State private var addedFolderIDs: Set<UUID> = []

    private var headerButtonColor: Color {
        colorScheme == .dark ? .white : .black
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        newFolderTitle = ""
                        showCreateAlert = true
                    } label: {
                        Label("New Folder…", systemImage: "folder.badge.plus")
                            .foregroundStyle(.primary)
                    }
                }

                if !folders.isEmpty {
                    Section("MY FOLDERS") {
                        ForEach(folders) { folder in
                            let alreadyAdded = addedFolderIDs.contains(folder.id) || folderContainsItem(folder)
                            Button {
                                guard !alreadyAdded else { return }
                                addToFolder(folder)
                            } label: {
                                HStack {
                                    Label(folder.title, systemImage: "folder")
                                        .foregroundStyle(alreadyAdded ? .secondary : .primary)
                                    Spacer()
                                    if alreadyAdded {
                                        Image(systemName: "checkmark")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text("\((folder.items ?? []).count) cards")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add to Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(headerButtonColor)
                }
            }
            .alert("New Folder", isPresented: $showCreateAlert) {
                TextField("Folder name", text: $newFolderTitle)
                Button("Create") { createAndAdd() }
                Button("Cancel", role: .cancel) { newFolderTitle = "" }
            }
        }
        .tint(headerButtonColor)
    }

    private func folderContainsItem(_ folder: CardFolder) -> Bool {
        (folder.items ?? []).contains { $0.cardID == cardID && $0.variantKey == variantKey }
    }

    private func addToFolder(_ folder: CardFolder) {
        let item = CardFolderItem(cardID: cardID, variantKey: variantKey)
        item.folder = folder
        modelContext.insert(item)
        try? modelContext.save()
        addedFolderIDs.insert(folder.id)
    }

    private func createAndAdd() {
        let title = newFolderTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let folder = CardFolder(title: title)
        modelContext.insert(folder)
        let item = CardFolderItem(cardID: cardID, variantKey: variantKey)
        item.folder = folder
        modelContext.insert(item)
        try? modelContext.save()
        addedFolderIDs.insert(folder.id)
        newFolderTitle = ""
    }
}

private struct SealedHoldingSource: Identifiable {
    let id: UUID
    let quantity: Int
    let date: Date
    let directionTitle: String
    let tint: Color
    let priceText: String?
    let description: String?
}

private enum SealedChartRange: String, CaseIterable {
    case oneMonth = "1M"
    case threeMonths = "3M"
    case oneYear = "1Y"
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
    @State private var chartRange: SealedChartRange = .oneMonth
    @State private var scrubPoint: PriceDataPoint? = nil
    @State private var isLoading = false

    private var resolvedChart: (points: [PriceDataPoint], resolution: SealedChartDataResolution) {
        guard let history else { return ([], .daily) }

        let daily31 = Array(history.daily.suffix(31))
        let weekly13 = Array((history.weekly.isEmpty ? weeklyFromDaily(history.daily) : history.weekly).suffix(13))
        let monthly12 = Array((history.monthly.isEmpty ? monthlyFromDaily(history.daily) : history.monthly).suffix(12))

        switch chartRange {
        case .oneMonth:
            if !daily31.isEmpty { return (daily31, .daily) }
            if !weekly13.isEmpty { return (weekly13, .weekly) }
            if !monthly12.isEmpty { return (monthly12, .monthly) }
        case .threeMonths:
            if !weekly13.isEmpty { return (weekly13, .weekly) }
            if !daily31.isEmpty { return (daily31, .daily) }
            if !monthly12.isEmpty { return (monthly12, .monthly) }
        case .oneYear:
            if !monthly12.isEmpty { return (monthly12, .monthly) }
            if !weekly13.isEmpty { return (weekly13, .weekly) }
            if !daily31.isEmpty { return (daily31, .daily) }
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

    private var change1d: Double? { pctChange(Array(history?.daily.suffix(2) ?? [])) }
    private var change7d: Double? { pctChange(Array(history?.daily.suffix(8) ?? [])) }
    private var change30d: Double? { pctChange(Array(history?.daily.suffix(31) ?? [])) }

    private func pctChange(_ pts: [PriceDataPoint]) -> Double? {
        guard pts.count >= 2, pts.first!.price > 0 else { return nil }
        return ((pts.last!.price - pts.first!.price) / pts.first!.price) * 100
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(scrubPoint != nil ? scrubLabel(scrubPoint!.label) : "Market Price")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 12)
                .animation(.none, value: scrubPoint?.label)

            Text(scrubPoint != nil
                 ? services.priceDisplay.currency.format(amountUSD: scrubPoint!.price, usdToGbp: services.pricing.usdToGbp)
                 : currentPrice)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.primary)
                .padding(.top, 2)
                .animation(.none, value: scrubPoint?.price)

            if change1d != nil || change7d != nil || change30d != nil {
                HStack(spacing: 12) {
                    changeBadge(label: "1D", value: change1d)
                    changeBadge(label: "7D", value: change7d)
                    changeBadge(label: "1M", value: change30d)
                }
                .padding(.top, 8)
                .padding(.bottom, 4)
            }

            if !resolvedChart.points.isEmpty {
                chartView
                    .padding(.top, 4)

                Picker("Range", selection: $chartRange) {
                    ForEach(SealedChartRange.allCases, id: \.self) { r in
                        Text(r.rawValue).tag(r)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 4)
            } else if isLoading {
                ProgressView()
                    .tint(.primary)
                    .padding(.vertical, 24)
            } else {
                Spacer().frame(height: 16)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
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

    private var panelDivider: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.10)
    }

    private var chartView: some View {
        let points = resolvedChart.points
        let prices = points.map(\.price)
        let minP = (prices.min() ?? 0) * 0.97
        let maxP = (prices.max() ?? 1) * 1.03

        return Chart(points) { point in
            LineMark(
                x: .value("Date", point.label),
                y: .value("Price", point.price)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(services.theme.accentColor)
            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

            AreaMark(
                x: .value("Date", point.label),
                yStart: .value("Min", minP),
                yEnd: .value("Price", point.price)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(LinearGradient(
                colors: [services.theme.accentColor.opacity(0.28), services.theme.accentColor.opacity(0.03)],
                startPoint: .top, endPoint: .bottom
            ))
        }
        .chartYScale(domain: minP...maxP)
        .chartXAxis {
            let stride = max(1, points.count / 4)
            let lastIndex = points.count - 1
            let visibleLabels = Set(points.enumerated().compactMap { i, p -> String? in
                (i == 0 || i == lastIndex || i % stride == 0) ? p.label : nil
            })
            AxisMarks(values: points.map(\.label)) { value in
                if let label = value.as(String.self), visibleLabels.contains(label) {
                    let isFirst = label == points.first?.label
                    let isLast  = label == points.last?.label
                    AxisValueLabel(truncatedLabel(label), anchor: isFirst ? .topLeading : isLast ? .topTrailing : .top)
                        .foregroundStyle(Color(uiColor: .label))
                        .font(.system(size: 9))
                }
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [4])).foregroundStyle(panelDivider)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing) { value in
                if let price = value.as(Double.self) {
                    AxisValueLabel(services.priceDisplay.currency.formatAxisTick(usd: price, usdToGbp: services.pricing.usdToGbp))
                        .foregroundStyle(Color(uiColor: .label))
                        .font(.system(size: 9))
                }
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [4])).foregroundStyle(panelDivider)
            }
        }
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
        .frame(height: 160)
        .padding(.horizontal, 16)
    }

    private func refreshPrice() {
        guard let usd = services.sealedProducts.marketPriceUSD(for: productID) else { currentPrice = "—"; return }
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

    private func scrubLabel(_ label: String) -> String {
        switch resolvedChart.resolution {
        case .daily: return dailyToFullUK(label)
        case .weekly: return weekLabelToFullUK(label)
        case .monthly:
            let parts = label.components(separatedBy: "-")
            guard parts.count == 2, let month = Int(parts[1]) else { return label }
            return "\(DateFormatter().shortMonthSymbols[month - 1]) \(parts[0])"
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
        let fmt = DateFormatter(); fmt.dateFormat = "dd/MM"; fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt.string(from: date)
    }

    private func weekLabelToFullUK(_ label: String) -> String {
        guard let date = weekLabelToDate(label) else { return label }
        let fmt = DateFormatter(); fmt.dateFormat = "dd/MM/yy"; fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt.string(from: date)
    }

    private func weekLabelToDate(_ label: String) -> Date? {
        let parts = label.components(separatedBy: "-W")
        guard parts.count == 2, let year = Int(parts[0]), let week = Int(parts[1]) else { return nil }
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: DateComponents(weekOfYear: week, yearForWeekOfYear: year))
    }

    private func monthLabelToShort(_ label: String) -> String {
        let p = label.components(separatedBy: "-")
        guard p.count == 2, let month = Int(p[1]) else { return label }
        return DateFormatter().shortMonthSymbols[month - 1]
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
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
        }
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

private extension UIImage {
    func sealedAuraColors(maxColors: Int) -> [Color] {
        guard maxColors > 0, let cgImage else { return [] }
        let sampleWidth = 44, sampleHeight = 62, bytesPerPixel = 4
        let bytesPerRow = sampleWidth * bytesPerPixel
        var raw = [UInt8](repeating: 0, count: sampleHeight * bytesPerRow)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: &raw, width: sampleWidth, height: sampleHeight,
                                     bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace,
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return [] }
        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight))
        struct AuraBin: Hashable { let r, g, b: Int }
        var histogram: [AuraBin: Double] = [:]
        let step = 32.0
        for y in 0..<sampleHeight {
            for x in 0..<sampleWidth {
                let i = y * bytesPerRow + x * bytesPerPixel
                let r = Double(raw[i]), g = Double(raw[i+1]), b = Double(raw[i+2]), a = Double(raw[i+3]) / 255.0
                guard a > 0.6 else { continue }
                let maxC = max(r, g, b) / 255.0, minC = min(r, g, b) / 255.0
                let saturation = maxC == 0 ? 0.0 : (maxC - minC) / maxC
                let brightness = maxC
                guard saturation >= 0.22, brightness >= 0.18, brightness <= 0.94 else { continue }
                let bin = AuraBin(r: Int(floor(r/step)), g: Int(floor(g/step)), b: Int(floor(b/step)))
                histogram[bin, default: 0] += 0.3 + saturation * 1.6 + brightness * 0.2
            }
        }
        let sortedBins = histogram.sorted { $0.value > $1.value }.map(\.key)
        guard !sortedBins.isEmpty else { return [] }
        var selected: [SIMD3<Double>] = []
        for bin in sortedBins {
            let c = SIMD3<Double>((Double(bin.r)+0.5)*step/255, (Double(bin.g)+0.5)*step/255, (Double(bin.b)+0.5)*step/255)
            if selected.allSatisfy({ existing in let d = c - existing; return sqrt(d.x*d.x+d.y*d.y+d.z*d.z) > 0.22 }) {
                selected.append(c)
            }
            if selected.count == maxColors { break }
        }
        if selected.isEmpty, let f = sortedBins.first {
            selected = [SIMD3<Double>((Double(f.r)+0.5)*step/255, (Double(f.g)+0.5)*step/255, (Double(f.b)+0.5)*step/255)]
        }
        if selected.count == 1, let f = selected.first { selected += [f*0.86, f*0.72] }
        else if selected.count == 2 { selected.append(selected[1]*0.7 + selected[0]*0.3) }
        return selected.prefix(maxColors).map { Color(red: $0.x, green: $0.y, blue: $0.z) }
    }
}
