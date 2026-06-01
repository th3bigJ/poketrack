import SwiftUI
import SwiftData

struct BrowseInlineSearchField: View {
    let title: String
    @Binding var text: String
    private let trailingContent: AnyView?
    @Environment(\.colorScheme) private var colorScheme

    init(title: String, text: Binding<String>) {
        self.title = title
        self._text = text
        self.trailingContent = nil
    }

    init<Trailing: View>(
        title: String,
        text: Binding<String>,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self._text = text
        self.trailingContent = AnyView(trailing())
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(title, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !text.isEmpty, trailingContent == nil {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            if let trailingContent {
                trailingContent
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .modifier(GlassSearchFieldModifier())
    }
}

// MARK: - Glass search field background

struct GlassSearchFieldModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        Group {
            if #available(iOS 26.0, *) {
                content
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.04))
                    )
                    .glassEffect(.regular.tint(nil).interactive(), in: Capsule(style: .continuous))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.12), lineWidth: 1)
                    )
            } else {
                content
                    .background(
                        Capsule(style: .continuous)
                            .fill(.thinMaterial)
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.1), lineWidth: 1)
                    )
            }
        }
    }
}

private enum BrowseAllSetsTab: String, CaseIterable {
    case cards = "Cards"
    case sealed = "Sealed"
}

struct BrowseAllSetsView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Query private var collectionItems: [CollectionItem]
    @State private var query = ""
    @State private var selectedTab: BrowseAllSetsTab = .cards

    // Pricing state
    @State private var setMarketValueUSDByKey: [String: Double] = [:]
    @State private var loadedSetMarketValueKeys: Set<String> = []
    @State private var loadingSetMarketValueKeys: Set<String> = []

    // Collected counts
    @State private var uniqueCollectedCountBySetCode: [String: Int] = [:]
    @State private var isFirstAppear = true

    // Master set toggle
    @State private var showMasterSet = false

    private var filteredSets: [TCGSet] {
        let sets = services.cardData.allSetsSortedByReleaseDateNewestFirst()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return sets }
        let q = trimmed.lowercased()
        return sets.filter { set in
            set.name.lowercased().contains(q)
                || set.setCode.lowercased().contains(q)
                || (set.seriesName?.lowercased().contains(q) == true)
        }
    }

    private var groupedSets: [(title: String, sets: [TCGSet])] {
        let grouped = Dictionary(grouping: filteredSets, by: browseSeriesTitle(for:))
        switch services.brandSettings.selectedCatalogBrand {
        case .pokemon:
            return grouped
                .map { (title: $0.key, sets: sortSetsNewestFirst($0.value)) }
                .sorted { lhs, rhs in
                    let lhsOldest = lhs.sets.map(\.releaseDate).compactMap { $0 }.min() ?? ""
                    let rhsOldest = rhs.sets.map(\.releaseDate).compactMap { $0 }.min() ?? ""
                    if lhsOldest != rhsOldest { return lhsOldest > rhsOldest }
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
        case .onePiece:
            return grouped
                .map { (title: $0.key, sets: sortSetsNewestFirst($0.value)) }
                .sorted { lhs, rhs in
                    let li = onePieceSeriesOrderIndex(lhs.title)
                    let ri = onePieceSeriesOrderIndex(rhs.title)
                    if li != ri { return li < ri }
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
        }
    }

    var body: some View {
        Group {
            if filteredSets.isEmpty && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedTab == .cards {
                ContentUnavailableView(
                    "No sets",
                    systemImage: "rectangle.stack",
                    description: Text("Load your catalog to browse sets.")
                )
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        Picker("Tab", selection: $selectedTab) {
                            ForEach(BrowseAllSetsTab.allCases, id: \.self) { tab in
                                Text(tab.rawValue).tag(tab)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                        .padding(.top)

                        if selectedTab == .cards {
                            BrowseInlineSearchField(title: "Search sets", text: $query)
                                .padding(.horizontal)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    masterSetChip(label: "Full Set", isMaster: false)
                                    masterSetChip(label: "Master Set", isMaster: true)
                                }
                                .padding(.horizontal, 16)
                            }

                            globalProgressHeader
                            if filteredSets.isEmpty {
                                ContentUnavailableView(
                                    "No matching sets",
                                    systemImage: "magnifyingglass",
                                    description: Text("Try a different set name or code.")
                                )
                                .padding(.horizontal)
                                .padding(.bottom)
                            } else {
                                LazyVStack(alignment: .leading, spacing: 20) {
                                    ForEach(groupedSets, id: \.title) { group in
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text(group.title)
                                                .font(.title2.weight(.bold))
                                                .foregroundStyle(.primary)
                                            Rectangle()
                                                .fill(Color.primary.opacity(0.08))
                                                .frame(height: 1)
                                        }
                                        .padding(.horizontal)
                                        .padding(.top, 10)
                                        LazyVStack(spacing: 0) {
                                            ForEach(group.sets) { set in
                                                NavigationLink(value: set) {
                                                    HStack(spacing: 14) {
                                                        SetLogoAsyncImage(
                                                            logoSrc: set.logoSrc,
                                                            height: 44,
                                                            brand: services.brandSettings.selectedCatalogBrand
                                                        )
                                                        .frame(width: 80)

                                                        VStack(alignment: .leading, spacing: 2) {
                                                            let progress = setProgress(for: set)
                                                            HStack(alignment: .top, spacing: 8) {
                                                                Text(set.name)
                                                                    .font(.subheadline.weight(.medium))
                                                                    .foregroundStyle(.primary)
                                                                    .lineLimit(2)
                                                                Spacer(minLength: 6)
                                                                Text(showMasterSet ? "Master Set Value" : "Full Set Value")
                                                                    .font(.caption2.weight(.semibold))
                                                                    .foregroundStyle(.secondary)
                                                                    .lineLimit(1)
                                                            }

                                                            if let total = progress.total, total > 0 {
                                                                ProgressView(value: min(Double(progress.collected), Double(total)), total: Double(total))
                                                                    .progressViewStyle(.linear)
                                                                    .tint(services.theme.accentColor)
                                                                    .padding(.top, 2)
                                                                HStack(spacing: 8) {
                                                                    Text("\(progress.collected) out of \(total) collected")
                                                                        .font(.caption2)
                                                                        .foregroundStyle(.secondary)
                                                                        .lineLimit(1)
                                                                    Spacer(minLength: 6)
                                                                    Text(setMarketValueText(for: set))
                                                                        .font(.caption2.weight(.semibold))
                                                                        .foregroundStyle(.secondary)
                                                                        .lineLimit(1)
                                                                }
                                                            } else {
                                                                HStack(spacing: 8) {
                                                                    Text("\(progress.collected) collected")
                                                                        .font(.caption2)
                                                                        .foregroundStyle(.secondary)
                                                                        .lineLimit(1)
                                                                    Spacer(minLength: 6)
                                                                    Text(setMarketValueText(for: set))
                                                                        .font(.caption2.weight(.semibold))
                                                                        .foregroundStyle(.secondary)
                                                                        .lineLimit(1)
                                                                }
                                                            }
                                                        }

                                                        Spacer()
                                                        Image(systemName: "chevron.right")
                                                            .font(.caption.weight(.semibold))
                                                            .foregroundStyle(.tertiary)
                                                    }
                                                    .padding(.horizontal)
                                                    .padding(.vertical, 10)
                                                    .contentShape(Rectangle())
                                                }
                                                .buttonStyle(.plain)
                                                .task(id: setMarketValueTaskID(for: set)) {
                                                    await ensureSetMarketValueLoaded(for: set)
                                                }
                                                Divider().padding(.leading, 108)
                                            }
                                        }
                                        .padding(.top, 4)
                                    }
                                }
                                .padding(.bottom)
                            }
                        } else {
                            AllSetsAllSealedView()
                        }
                    }
                }
                .defaultScrollAnchor(.top)
            }
        }
        .navigationDestination(for: TCGSet.self) { set in
            SetCardsView(set: set)
        }
        .navigationTitle("Browse sets")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") { dismiss() }
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear {
            if isFirstAppear {
                Task {
                    await refreshCollectedCounts()
                    isFirstAppear = false
                }
            }
        }
        .onChange(of: collectionItems.count) { _, _ in
            Task { await refreshCollectedCounts() }
        }
    }

    private var globalProgressHeader: some View {
        let allSets = services.cardData.sets
        
        // Better: let's calculate based on unique card IDs in collection that match the current brand.
        let brandOwned = collectionItems.filter { item in
            let brand = TCGBrand.inferredFromMasterCardId(item.cardID)
            return brand == services.brandSettings.selectedCatalogBrand
        }
        let uniqueOwnedCount = Set(brandOwned.map(\.cardID)).count
        
        let totalCardsInCatalog = allSets.reduce(0) { acc, set in
            acc + (showMasterSet ? (set.masterSetTotal ?? set.cardCountTotal ?? 0) : (set.cardCountTotal ?? 0))
        }

        return VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(showMasterSet ? "Master Set Completion" : "Overall Completion")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Group {
                    Text("\(uniqueOwnedCount)")
                        .foregroundStyle(services.theme.accentColor)
                    + Text(" / \(totalCardsInCatalog)")
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 13, weight: .black, design: .monospaced))
            }
            
            let progress = totalCardsInCatalog > 0 ? CGFloat(uniqueOwnedCount) / CGFloat(totalCardsInCatalog) : 0
            
            Capsule()
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08))
                .frame(height: 6)
                .overlay(alignment: .leading) {
                    services.theme.accentColor
                        .frame(maxWidth: .infinity)
                        .scaleEffect(x: max(progress, 0.005), y: 1.0, anchor: .leading)
                        .clipShape(Capsule())
                        .shadow(color: services.theme.accentColor.opacity(0.3), radius: 2, x: 0, y: 1)
                }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.05 : 0.025))
                .padding(.horizontal, 12)
        }
    }

    private func masterSetChip(label: String, isMaster: Bool) -> some View {
        let isSelected = showMasterSet == isMaster
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                showMasterSet = isMaster
            }
            Haptics.lightImpact()
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background {
                    Capsule()
                        .fill(isSelected ? services.theme.accentColor : Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.06))
                }
                .foregroundStyle(isSelected ? .white : .primary.opacity(0.8))
        }
        .buttonStyle(.plain)
    }

    private func setProgress(for set: TCGSet) -> (collected: Int, total: Int?) {
        let collected = uniqueCollectedCountBySetCode[set.setCode.lowercased()] ?? 0
        let total = showMasterSet ? (set.masterSetTotal ?? set.cardCountTotal) : set.cardCountTotal
        return (collected, total)
    }

    private func setMarketValueTaskID(for set: TCGSet) -> String {
        "\(services.brandSettings.selectedCatalogBrand.rawValue)|\(set.setCode.lowercased())"
    }

    private func setMarketValueKey(for set: TCGSet) -> String {
        setMarketValueTaskID(for: set)
    }

    private func setMarketValueText(for set: TCGSet) -> String {
        let key = setMarketValueKey(for: set)
        if let usd = setMarketValueUSDByKey[key] {
            return services.priceDisplay.currency.format(amountUSD: usd, usdToGbp: services.pricing.usdToGbp)
        }
        if loadedSetMarketValueKeys.contains(key) {
            return "—"
        }
        return "…"
    }

    @MainActor
    private func ensureSetMarketValueLoaded(for set: TCGSet) async {
        let key = setMarketValueKey(for: set)
        if loadedSetMarketValueKeys.contains(key) || loadingSetMarketValueKeys.contains(key) {
            return
        }
        loadingSetMarketValueKeys.insert(key)
        defer { loadingSetMarketValueKeys.remove(key) }

        let cards = await services.cardData.loadCards(forSetCode: set.setCode)
        var totalUSD = 0.0
        var pricedCardCount = 0

        for card in cards {
            guard let entry = await services.pricing.pricing(for: card) else { continue }
            guard let cheapestUSD = cheapestVariantMarketUSD(for: entry), cheapestUSD > 0 else { continue }
            totalUSD += cheapestUSD
            pricedCardCount += 1
        }

        if pricedCardCount > 0 {
            setMarketValueUSDByKey[key] = totalUSD
        } else {
            setMarketValueUSDByKey.removeValue(forKey: key)
        }
        loadedSetMarketValueKeys.insert(key)
    }

    private func cheapestVariantMarketUSD(for entry: CardPricingEntry) -> Double? {
        if let scrydex = entry.scrydex, !scrydex.isEmpty {
            return scrydex.values
                .compactMap { $0.marketEstimateUSD() }
                .filter { $0 > 0 }
                .min()
        }
        if let usd = entry.tcgplayerMarketEstimateUSD(), usd > 0 {
            return usd
        }
        return nil
    }

    @MainActor
    private func refreshCollectedCounts() async {
        let activeSetCodes = Set(services.cardData.sets.map { $0.setCode.lowercased() })
        var uniqueCardKeysBySetCode: [String: Set<String>] = [:]

        for item in collectionItems where item.quantity > 0 {
            guard let identity = await resolveCollectionCardIdentity(
                for: item.cardID,
                activeSetCodes: activeSetCodes
            ) else { continue }
            uniqueCardKeysBySetCode[identity.setCode, default: []].insert(identity.uniqueCardKey)
        }

        uniqueCollectedCountBySetCode = uniqueCardKeysBySetCode.mapValues(\.count)
    }

    private func resolveCollectionCardIdentity(
        for cardID: String,
        activeSetCodes: Set<String>
    ) async -> (setCode: String, uniqueCardKey: String)? {
        if let parsed = collectionCardIdentity(for: cardID), activeSetCodes.contains(parsed.setCode) {
            return parsed
        }

        guard let card = await services.cardData.loadCard(masterCardId: cardID) else { return nil }
        let setCode = card.setCode.lowercased()
        guard activeSetCodes.contains(setCode) else { return nil }
        if card.masterCardId.contains("::") {
            let number = card.cardNumber.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let uniqueKey = number.isEmpty ? card.masterCardId.lowercased() : "\(setCode)::\(number)"
            return (setCode, uniqueKey)
        }
        return (setCode, card.masterCardId.lowercased())
    }

    private func collectionCardIdentity(for cardID: String) -> (setCode: String, uniqueCardKey: String)? {
        let components = cardID.split(separator: ":", omittingEmptySubsequences: false)
        guard components.count >= 2 else { return nil }
        
        let setCode = String(components[0]).lowercased()
        if components.count == 3 {
            let number = String(components[2]).lowercased()
            return (setCode, "\(setCode)::\(number)")
        }
        return (setCode, cardID.lowercased())
    }

    private func browseSeriesTitle(for set: TCGSet) -> String {
        switch services.brandSettings.selectedCatalogBrand {
        case .pokemon:
            let title = set.seriesName?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (title?.isEmpty == false ? title! : "Other")
        case .onePiece:
            return normalizedOnePieceSeriesTitle(set.seriesName)
        }
    }

    private func sortSetsNewestFirst(_ sets: [TCGSet]) -> [TCGSet] {
        sets.sorted { lhs, rhs in
            let ld = lhs.releaseDate ?? ""
            let rd = rhs.releaseDate ?? ""
            if ld != rd { return ld > rd }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func normalizedOnePieceSeriesTitle(_ raw: String?) -> String {
        let title = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let lower = title.lowercased()
        if lower.contains("booster pack") { return "Booster Pack" }
        if lower.contains("extra booster") { return "Extra Boosters" }
        if lower.contains("starter") { return "Starter deck" }
        if lower.contains("premium booster") { return "Premium Booster" }
        if lower.contains("promo") { return "Promo" }
        return title.isEmpty ? "Other" : title
    }

    private func onePieceSeriesOrderIndex(_ title: String) -> Int {
        switch title {
        case "Booster Pack": return 0
        case "Extra Boosters": return 1
        case "Starter deck": return 2
        case "Premium Booster": return 3
        case "Promo": return 4
        default: return 5
        }
    }
}

// MARK: - Sealed tab for Browse Sets

private struct AllSetsAllSealedView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.presentSealedProduct) private var presentSealedProduct
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \CollectionItem.dateAcquired, order: .reverse) private var collectionItems: [CollectionItem]
    @Query(sort: \WishlistItem.dateAdded, order: .reverse) private var wishlistItems: [WishlistItem]

    @State private var query = ""
    @State private var filters = BrowseCardGridFilters()
    @State private var displayedProducts: [SealedProduct] = []
    @State private var addToCollectionProduct: SealedProduct?
    @State private var addToFolderProduct: SealedProduct?
    @State private var showWishlistPaywall = false
    @State private var showWishlistAlert = false
    @State private var wishlistAlertMessage: String?

    private let horizontalPadding: CGFloat = 16
    private let gridSpacing: CGFloat = 12

    private var columnCount: Int {
        min(max(services.browseGridOptions.options.columnCount, 1), 4)
    }

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
        let allProducts = services.sealedProducts.products
        let base = allProducts.compactMap { product -> SealedProduct? in
            if productMatchesSelectedTypes(product.type, selectedOptionIDs: filters.productTypes) == false {
                return nil
            }
            guard !normalizedQuery.isEmpty else { return product }
            return product.searchBlob.contains(normalizedQuery) ? product : nil
        }
        return sortSealedProducts(base)
    }

    private func sortSealedProducts(_ products: [SealedProduct]) -> [SealedProduct] {
        switch filters.sortBy {
        case .random:
            return products.sorted { stableRandomRank(for: $0.id) < stableRandomRank(for: $1.id) }
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
                case let (lv?, rv?): if lv != rv { return lv > rv }
                case (.some, nil): return true
                case (nil, .some): return false
                case (nil, nil): break
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

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                BrowseInlineSearchField(title: "Search sealed products", text: $query)
                Menu {
                    BrowseGridFiltersMenuContent(
                        brand: services.brandSettings.selectedCatalogBrand,
                        filters: $filters,
                        energyOptions: [],
                        rarityOptions: [],
                        trainerTypeOptions: [],
                        config: .products
                    )
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle\(filters.isVisiblyCustomized || filters.sortBy != .newestSet ? ".fill" : "")")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(filters.isVisiblyCustomized || filters.sortBy != .newestSet ? services.theme.accentColor : .primary)
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.06))
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.bottom, 12)

            if services.sealedProducts.isLoading && services.sealedProducts.products.isEmpty {
                ProgressView("Loading products…")
                    .frame(maxWidth: .infinity, minHeight: 280)
                    .padding(.horizontal, 16)
            } else if displayedProducts.isEmpty {
                ContentUnavailableView(
                    services.sealedProducts.products.isEmpty ? "No products yet" : "No matching products",
                    systemImage: "shippingbox",
                    description: Text(services.sealedProducts.products.isEmpty
                        ? "Products will appear after the next market sync."
                        : "Try a different product name, series, or year.")
                )
                .frame(maxWidth: .infinity, minHeight: 280)
                .padding(.horizontal, 16)
            } else {
                EagerVGrid(items: displayedProducts, columns: columnCount, spacing: gridSpacing) { product in
                    Button {
                        let index = displayedProducts.firstIndex(where: { $0.id == product.id }) ?? 0
                        presentSealedProduct(product, displayedProducts, index)
                    } label: {
                        SealedProductGridCell(
                            product: product,
                            gridOptions: services.browseGridOptions.options,
                            priceUSD: services.sealedProducts.marketPriceUSD(for: product.id),
                            isOwned: ownedCollectionCardIDs.contains(product.collectionCardID),
                            isWishlisted: wishlistedCollectionCardIDs.contains(product.collectionCardID)
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
                .padding(.horizontal, horizontalPadding)
                .padding(.bottom, 16)
            }
        }
        .task {
            await services.sealedProducts.loadFromLocalIfAvailable()
            if services.sealedProducts.products.isEmpty {
                await services.sealedProducts.refreshFromNetworkAndStoreLocallyIfNeeded()
            }
            displayedProducts = filteredProducts
        }
        .onChange(of: query) { _, _ in displayedProducts = filteredProducts }
        .onChange(of: filters) { _, _ in displayedProducts = filteredProducts }
        .onChange(of: services.sealedProducts.products) { _, _ in displayedProducts = filteredProducts }
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
