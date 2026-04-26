import Charts
import SwiftData
import SwiftUI

struct BrowseSealedTabContent: View {
    @Environment(AppServices.self) private var services
    @Query(sort: \CollectionItem.dateAcquired, order: .reverse) private var collectionItems: [CollectionItem]
    @Query(sort: \WishlistItem.dateAdded, order: .reverse) private var wishlistItems: [WishlistItem]

    let query: String
    let filters: BrowseCardGridFilters
    let gridOptions: BrowseGridOptions

    @State private var selectedProduct: SealedProduct?
    @State private var detailProducts: [SealedProduct] = []

    private var ownedCollectionCardIDs: Set<String> {
        Set(collectionItems.compactMap { item in
            guard item.itemKind == ProductKind.sealedProduct.rawValue else { return nil }
            return item.cardID
        })
    }

    private var wishlistedCollectionCardIDs: Set<String> {
        Set(wishlistItems.map(\.cardID).filter { SealedProduct.parseCollectionProductID($0) != nil })
    }

    private var filteredProducts: [SealedProduct] {
        let normalizedQuery = normalizeSealedSearchText(query)
        let base = services.sealedProducts.products.filter { product in
            guard normalizedQuery.isEmpty == false else { return true }
            return product.searchBlob.contains(normalizedQuery)
        }
        return sort(products: base)
    }

    var body: some View {
        let products = filteredProducts
        Group {
            if services.sealedProducts.isLoading && services.sealedProducts.products.isEmpty {
                ProgressView("Loading sealed products…")
                    .frame(maxWidth: .infinity, minHeight: 280)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            } else if products.isEmpty {
                ContentUnavailableView(
                    services.sealedProducts.products.isEmpty ? "No sealed products yet" : "No matching products",
                    systemImage: "shippingbox",
                    description: Text(services.sealedProducts.products.isEmpty
                        ? "Sealed products will appear after the next market sync."
                        : "Try a different product name, series, or year.")
                )
                .frame(maxWidth: .infinity, minHeight: 280)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            } else {
                EagerVGrid(items: products, columns: min(max(gridOptions.columnCount, 1), 4), spacing: 12) { product in
                    Button {
                        detailProducts = products
                        selectedProduct = product
                    } label: {
                        SealedProductGridCell(
                            product: product,
                            gridOptions: gridOptions,
                            priceUSD: services.sealedProducts.marketPriceUSD(for: product.id),
                            isOwned: ownedCollectionCardIDs.contains(product.collectionCardID),
                            isWishlisted: wishlistedCollectionCardIDs.contains(product.collectionCardID)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(CardCellButtonStyle())
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .task {
            services.sealedProducts.loadFromLocalIfAvailable()
            if services.sealedProducts.products.isEmpty {
                await services.sealedProducts.refreshFromNetworkAndStoreLocallyIfNeeded()
            }
        }
        .sheet(item: $selectedProduct) { product in
            SealedProductBrowseDetailView(products: detailProducts.isEmpty ? [product] : detailProducts, startProductID: product.id)
                .environment(services)
        }
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
}

struct SealedProductGridCell: View {
    @Environment(AppServices.self) private var services
    @Environment(\.colorScheme) private var colorScheme

    let product: SealedProduct
    let gridOptions: BrowseGridOptions
    let priceUSD: Double?
    let isOwned: Bool
    let isWishlisted: Bool

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
        (gridOptions.showSetName && !(product.series ?? "").isEmpty)
            || gridOptions.showSetID
            || gridOptions.showPricing
    }

    private var cardCornerRadius: CGFloat {
        (gridOptions.showCardName || showsFooter) ? 18 : 0
    }

    var body: some View {
        VStack(spacing: 0) {
            if gridOptions.showCardName {
                Text(product.name)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .padding(.horizontal, 8)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(dividerColor).frame(height: 1)
                    }
            }

            SealedThumbnailView(
                imageURL: product.imageURL,
                isOwned: isOwned,
                isWishlisted: isWishlisted,
                ownedCountBadge: nil
            )
            .aspectRatio(5 / 7, contentMode: .fit)
            .frame(maxWidth: .infinity)

            if showsFooter {
                VStack(spacing: 3) {
                    if gridOptions.showSetName, let series = product.series, !series.isEmpty {
                        Text(series)
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
                .background(insetBackground)
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
                .stroke(isOwned ? services.theme.accentColor : tileBorder, lineWidth: isOwned ? 1.8 : 1.2)
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
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } placeholder: {
                Color.secondary.opacity(0.12)
                    .overlay { ProgressView() }
            }
            .clipped()

            if let ownedCountBadge, ownedCountBadge > 1 {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white, services.theme.accentColor)
                    .shadow(color: .black.opacity(0.18), radius: 3, x: 0, y: 1)
                    .padding(6)
                    .accessibilityLabel("Owned \(ownedCountBadge)")
            } else if isOwned {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white, services.theme.accentColor)
                    .shadow(color: .black.opacity(0.18), radius: 3, x: 0, y: 1)
                    .padding(6)
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
    @Environment(\.colorScheme) private var colorScheme

    let products: [SealedProduct]

    @State private var index: Int

    init(products: [SealedProduct], startProductID: Int) {
        self.products = products
        let start = products.firstIndex(where: { $0.id == startProductID }) ?? 0
        _index = State(initialValue: start)
    }

    var body: some View {
        Group {
            if products.isEmpty {
                ContentUnavailableView("No product", systemImage: "shippingbox")
            } else {
                TabView(selection: $index) {
                    ForEach(Array(products.enumerated()), id: \.element.id) { idx, product in
                        SealedProductDetailPage(product: product)
                            .tag(idx)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(pageChromeBackground)
        .presentationBackground(colorScheme == .dark ? Color.black : Color(uiColor: .systemBackground))
        .presentationDragIndicator(.visible)
        .presentationDetents([.large])
        .presentationCornerRadius(20)
    }

    private var pageChromeBackground: Color {
        colorScheme == .dark ? Color.black : Color(uiColor: .systemBackground)
    }
}

private struct SealedProductDetailPage: View {
    @Environment(AppServices.self) private var services
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Query private var collectionItems: [CollectionItem]

    let product: SealedProduct

    @State private var showAddSheet = false
    @State private var showWishlistPaywall = false
    @State private var wishlistAlertMessage: String?
    @State private var showWishlistAlert = false

    init(product: SealedProduct) {
        self.product = product
        let cardID = SealedProduct.collectionCardID(productID: product.id)
        _collectionItems = Query(filter: #Predicate<CollectionItem> { $0.cardID == cardID })
    }

    private var collectionCardID: String {
        SealedProduct.collectionCardID(productID: product.id)
    }

    private var ownedQuantity: Int {
        collectionItems
            .filter { $0.itemKind == ProductKind.sealedProduct.rawValue }
            .reduce(0) { $0 + max($1.quantity, 0) }
    }

    private var isWishlisted: Bool {
        services.wishlist?.isInWishlist(cardID: collectionCardID, variantKey: "sealed") == true
    }

    private static let wishlistActiveStarColor = Color(red: 0.98, green: 0.78, blue: 0.18)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                productImage
                    .padding(.top, 26)

                metaSection

                actionButtons

                SealedProductPricingPanel(productID: product.id)

                recentSoldOnEbayButton

                detailsSection
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 48)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(pageBackground)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .onAppear {
            services.setupCollectionLedger(modelContext: modelContext)
            services.setupWishlist(modelContext: modelContext)
        }
        .sheet(isPresented: $showAddSheet) {
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

    private var pageBackground: Color {
        colorScheme == .dark ? Color.black : Color(uiColor: .systemBackground)
    }

    private var productImage: some View {
        CachedAsyncImage(url: product.imageURL) { image in
            image
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        } placeholder: {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
                .overlay { ProgressView() }
        }
        .frame(maxWidth: .infinity)
    }

    private var metaSection: some View {
        VStack(alignment: .center, spacing: 8) {
            Text(product.name)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
            HStack(spacing: 8) {
                Text(product.typeDisplayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if let series = product.series, !series.isEmpty {
                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(series)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text("#\(product.id)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            if ownedQuantity > 0 {
                Text("Owned: \(ownedQuantity)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(services.theme.accentColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                showAddSheet = true
            } label: {
                sealedActionBody(
                    title: "Add to Collection",
                    systemImage: "plus.circle.fill",
                    tint: SealedPricingPalette.success
                )
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                toggleWishlist()
            } label: {
                sealedActionBody(
                    title: "Wish List",
                    systemImage: isWishlisted ? "star.fill" : "star",
                    tint: isWishlisted ? Self.wishlistActiveStarColor : SealedPricingPalette.gold
                )
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(maxWidth: .infinity)
    }

    private func sealedActionBody(title: String, systemImage: String, tint: Color) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 52, height: 52)
            .background {
                Circle()
                    .fill(glassButtonBackground)
                    .overlay(
                        Circle()
                            .stroke(glassButtonBorder, lineWidth: 1)
                    )
            }
            .accessibilityLabel(title)
    }

    private var glassButtonBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }

    private var glassButtonBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.10)
    }

    private var sectionInsetBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.05)
    }

    private var sectionBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }

    private var recentSoldOnEbayButton: some View {
        Button {
            guard let url = ebayRecentSoldURL else { return }
            openURL(url)
        } label: {
            HStack(spacing: 10) {
                ebayWordmark
                Text("Recent Sold on eBay")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right.square")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(sectionInsetBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(sectionBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open recent sold listings on eBay")
    }

    private var ebayWordmark: some View {
        HStack(spacing: 0) {
            Text("e").foregroundStyle(Color(red: 0.89, green: 0.15, blue: 0.13))
            Text("B").foregroundStyle(Color(red: 0.00, green: 0.38, blue: 0.75))
            Text("a").foregroundStyle(Color(red: 0.97, green: 0.74, blue: 0.06))
            Text("y").foregroundStyle(Color(red: 0.44, green: 0.68, blue: 0.11))
        }
        .font(.system(size: 18, weight: .bold, design: .rounded))
    }

    private var ebayRecentSoldURL: URL? {
        let searchText = [product.name, product.series, product.typeDisplayName, String(product.id)]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
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

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Details")
                .font(.headline)
            detailRow("Release", value: releaseDateDisplay)
            detailRow("Type", value: product.typeDisplayName)
            if let series = product.series, !series.isEmpty {
                detailRow("Series", value: series)
            }
            if let language = product.language, !language.isEmpty {
                detailRow("Language", value: language)
            }
            if let year = product.year {
                detailRow("Year", value: String(year))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private var releaseDateDisplay: String {
        if let date = product.releaseDate {
            return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none)
        }
        if let raw = product.releaseDateRaw, !raw.isEmpty {
            return raw
        }
        return "Unknown"
    }

    private func detailRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .leading)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
    }

    private func toggleWishlist() {
        guard let wishlist = services.wishlist else {
            wishlistAlertMessage = "Wishlist isn’t available yet. Try again in a moment."
            showWishlistAlert = true
            return
        }

        if isWishlisted {
            do {
                try wishlist.removeCardVariant(cardID: collectionCardID, variantKey: "sealed")
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
            try wishlist.addItem(cardID: collectionCardID, variantKey: "sealed")
        } catch WishlistError.limitReached {
            showWishlistPaywall = true
        } catch {
            wishlistAlertMessage = error.localizedDescription
            showWishlistAlert = true
        }
    }
}

private enum SealedChartRange: String, CaseIterable {
    case oneMonth = "1M"
    case threeMonths = "3M"
    case oneYear = "1Y"
}

private struct SealedProductPricingPanel: View {
    @Environment(AppServices.self) private var services
    @Environment(\.colorScheme) private var colorScheme

    let productID: Int

    @State private var history: SealedProductHistorySeries?
    @State private var trends: SealedProductTrendEntry?
    @State private var currentPrice = "—"
    @State private var chartRange: SealedChartRange = .oneMonth
    @State private var scrubPoint: PriceDataPoint? = nil

    private var chartPoints: [PriceDataPoint] {
        guard let history else { return [] }
        switch chartRange {
        case .oneMonth: return Array(history.daily.suffix(30))
        case .threeMonths: return Array(history.weekly.suffix(13))
        case .oneYear: return Array(history.monthly.suffix(12))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(scrubPoint != nil ? scrubLabel(scrubPoint!.label) : "Market Price")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 12)

            Text(scrubPoint != nil
                 ? services.priceDisplay.currency.format(amountUSD: scrubPoint!.price, usdToGbp: services.pricing.usdToGbp)
                 : currentPrice)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.primary)
                .padding(.top, 2)

            if let trends {
                HStack(spacing: 12) {
                    changeBadge(label: "1D", value: trends.daily?.changePct)
                    changeBadge(label: "7D", value: trends.weekly?.changePct)
                    changeBadge(label: "1M", value: trends.monthly?.changePct)
                }
                .padding(.top, 8)
                .padding(.bottom, 4)
            }

            if !chartPoints.isEmpty {
                chartView
                    .padding(.top, 16)

                Picker("Range", selection: $chartRange) {
                    ForEach(SealedChartRange.allCases, id: \.self) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 16)
            } else {
                Spacer().frame(height: 16)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(colorScheme == .dark ? .black : .white)
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08), lineWidth: 1)
                )
        )
        .task(id: taskID) {
            history = services.sealedProducts.history(for: productID)
            trends = services.sealedProducts.trends(for: productID)
            refreshPrice()
        }
        .onChange(of: services.priceDisplay.currency) { _, _ in
            refreshPrice()
        }
        .onChange(of: services.pricing.usdToGbp) { _, _ in
            refreshPrice()
        }
    }

    private var taskID: String {
        "\(productID)|\(services.priceDisplay.currency.rawValue)|\(services.pricing.usdToGbp)"
    }

    private var chartView: some View {
        let points = chartPoints
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
            .foregroundStyle(
                LinearGradient(
                    colors: [services.theme.accentColor.opacity(0.28), services.theme.accentColor.opacity(0.03)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .chartYScale(domain: minP...maxP)
        .chartXAxis {
            let stride = max(1, points.count / 4)
            let lastIndex = points.count - 1
            let visibleLabels = Set(points.enumerated().compactMap { idx, point -> String? in
                (idx == 0 || idx == lastIndex || idx % stride == 0) ? point.label : nil
            })
            AxisMarks(values: points.map(\.label)) { value in
                if let label = value.as(String.self), visibleLabels.contains(label) {
                    AxisValueLabel(truncatedLabel(label), anchor: .top)
                        .font(.system(size: 9))
                }
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [4]))
                    .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.10))
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing) { value in
                if let price = value.as(Double.self) {
                    AxisValueLabel(services.priceDisplay.currency.formatAxisTick(usd: price, usdToGbp: services.pricing.usdToGbp))
                        .font(.system(size: 9))
                }
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [4]))
                    .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.10))
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                if let plotAnchor = proxy.plotFrame {
                    let plotFrame = geo[plotAnchor]

                    if let scrub = scrubPoint, let xPos = proxy.position(forX: scrub.label) {
                        let x = xPos + plotFrame.origin.x
                        Rectangle()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.10))
                            .frame(width: 1.5)
                            .frame(maxHeight: .infinity)
                            .offset(x: x - 0.75)
                            .allowsHitTesting(false)

                        if let yPos = proxy.position(forY: scrub.price) {
                            Circle()
                                .fill(services.theme.accentColor)
                                .frame(width: 8, height: 8)
                                .offset(x: x - 4, y: plotFrame.origin.y + yPos - 4)
                                .allowsHitTesting(false)
                        }
                    }

                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let x = value.location.x - plotFrame.origin.x
                                    guard x >= 0, x <= plotFrame.width else { return }
                                    if let label: String = proxy.value(atX: x) {
                                        scrubPoint = nearestPoint(to: label, in: points)
                                    }
                                }
                                .onEnded { _ in
                                    scrubPoint = nil
                                }
                        )
                }
            }
        }
        .frame(height: 160)
        .padding(.horizontal, 16)
    }

    private func refreshPrice() {
        guard let usd = services.sealedProducts.marketPriceUSD(for: productID) else {
            currentPrice = "—"
            return
        }
        currentPrice = services.priceDisplay.currency.format(amountUSD: usd, usdToGbp: services.pricing.usdToGbp)
    }

    @ViewBuilder
    private func changeBadge(label: String, value: Double?) -> some View {
        if let value {
            HStack(spacing: 3) {
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Image(systemName: value >= 0 ? "arrow.up" : "arrow.down")
                    .font(.system(size: 9, weight: .bold))
                Text(String(format: "%.1f%%", abs(value)))
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(value >= 0 ? SealedPricingPalette.success : SealedPricingPalette.danger)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill((value >= 0 ? SealedPricingPalette.success : SealedPricingPalette.danger).opacity(0.15))
            )
        }
    }

    private func truncatedLabel(_ label: String) -> String {
        switch chartRange {
        case .oneMonth:
            return dailyToShortUK(label)
        case .threeMonths:
            return weekLabelToShortUK(label)
        case .oneYear:
            return monthLabelToShort(label)
        }
    }

    private func scrubLabel(_ label: String) -> String {
        switch chartRange {
        case .oneMonth:
            return dailyToFullUK(label)
        case .threeMonths:
            return weekLabelToFullUK(label)
        case .oneYear:
            let parts = label.components(separatedBy: "-")
            guard parts.count == 2, let month = Int(parts[1]) else { return label }
            let fmt = DateFormatter()
            return "\(fmt.shortMonthSymbols[month - 1]) \(parts[0])"
        }
    }

    private func dailyToShortUK(_ label: String) -> String {
        let parts = label.components(separatedBy: "-")
        guard parts.count == 3 else { return label }
        return "\(parts[2])/\(parts[1])"
    }

    private func dailyToFullUK(_ label: String) -> String {
        let parts = label.components(separatedBy: "-")
        guard parts.count == 3, parts[0].count == 4 else { return label }
        let yy = String(parts[0].suffix(2))
        return "\(parts[2])/\(parts[1])/\(yy)"
    }

    private func weekLabelToShortUK(_ label: String) -> String {
        guard let date = weekLabelToDate(label) else { return label }
        let fmt = DateFormatter()
        fmt.dateFormat = "dd/MM"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt.string(from: date)
    }

    private func weekLabelToFullUK(_ label: String) -> String {
        guard let date = weekLabelToDate(label) else { return label }
        let fmt = DateFormatter()
        fmt.dateFormat = "dd/MM/yy"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt.string(from: date)
    }

    private func weekLabelToDate(_ label: String) -> Date? {
        let parts = label.components(separatedBy: "-W")
        guard parts.count == 2,
              let year = Int(parts[0]),
              let week = Int(parts[1]) else { return nil }
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: DateComponents(weekOfYear: week, yearForWeekOfYear: year))
    }

    private func monthLabelToShort(_ label: String) -> String {
        let parts = label.components(separatedBy: "-")
        guard parts.count == 2, let month = Int(parts[1]) else { return label }
        let fmt = DateFormatter()
        return fmt.shortMonthSymbols[month - 1]
    }

    private func nearestPoint(to label: String, in points: [PriceDataPoint]) -> PriceDataPoint? {
        guard !points.isEmpty else { return nil }
        if let exact = points.first(where: { $0.label == label }) { return exact }
        let sorted = points.sorted { $0.label < $1.label }
        for (index, point) in sorted.enumerated() {
            if point.label > label {
                return index == 0 ? point : sorted[index - 1]
            }
        }
        return sorted.last
    }
}

private enum SealedPricingPalette {
    static let success = Color(red: 0.28, green: 0.84, blue: 0.39)
    static let danger = Color(red: 1.0, green: 0.36, blue: 0.34)
    static let gold = Color(red: 0.97, green: 0.74, blue: 0.06)
}

private struct AddSealedToCollectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppServices.self) private var services

    let product: SealedProduct

    @State private var acquisitionKind: CollectionAcquisitionKind = .bought
    @State private var quantity: Int = 1
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
                        Text(CollectionAcquisitionKind.gifted.title).tag(CollectionAcquisitionKind.gifted)
                        Text(CollectionAcquisitionKind.packed.title).tag(CollectionAcquisitionKind.packed)
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Stepper("Quantity: \(quantity)", value: $quantity, in: 1...999)
                }

                if acquisitionKind == .bought {
                    Section {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Price paid")
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
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                }
            }
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
                cardID: product.collectionCardID
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

private func normalizeSealedSearchText(_ value: String?) -> String {
    (value ?? "")
        .folding(options: [.diacriticInsensitive, .widthInsensitive, .caseInsensitive], locale: .current)
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
}
