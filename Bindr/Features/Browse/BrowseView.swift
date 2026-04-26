import SwiftData
import SwiftUI

/// A premium, sliding-highlight segmented picker that respects the user's theme accent color.
/// Kept with Browse because Browse owns the primary tab treatment reused by collection/social.
struct SlidingSegmentedPicker<SelectionValue: Hashable & Identifiable>: View {
    @Binding var selection: SelectionValue
    let items: [SelectionValue]
    let title: (SelectionValue) -> String

    @Environment(AppServices.self) private var services
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                let isSelected = selection == item

                Button {
                    if selection != item {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            selection = item
                        }
                        Haptics.lightImpact()
                    }
                } label: {
                    Text(title(item))
                        .font(.system(size: 14, weight: isSelected ? .bold : .medium))
                        .foregroundStyle(isSelected ? .white : .primary.opacity(0.7))
                        .padding(.vertical, 8)
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(services.theme.accentColor)
                                    .matchedGeometryEffect(id: "highlight", in: namespace)
                                    .shadow(color: services.theme.accentColor.opacity(0.3), radius: 4, x: 0, y: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule()
                        .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
                }
        }
    }
}

// MARK: - Shared card grid cell

struct CardGridCell: View {
    let card: Card
    var gridOptions = BrowseGridOptions()
    var setName: String? = nil
    var isOwned = false
    var isWishlisted = false
    /// Optional owned-count badge for collection surfaces. Renders as `xN` in the thumbnail corner.
    var ownedCountBadge: Int? = nil
    /// Optional line under the name (e.g. wishlist variant key).
    var footnote: String? = nil
    /// Optional line rendered after pricing in the footer (used by grading opportunities for upside text).
    var postPriceFootnote: String? = nil
    /// When provided, shown as the price instead of doing a live lookup (used by collection grid to show grade-correct price).
    var overridePrice: Double? = nil
    /// When provided, shown as a small badge next to the price (e.g. "PSA 10", "ACE 10").
    var gradeLabel: String? = nil
    @Environment(AppServices.self) private var services
    @Environment(\.colorScheme) private var colorScheme

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
        (gridOptions.showSetName && !(setName?.isEmpty ?? true))
            || (gridOptions.showOwned && !(footnote?.isEmpty ?? true))
            || gridOptions.showSetID
            || gridOptions.showPricing
            || !(postPriceFootnote?.isEmpty ?? true)
    }

    private var visibleOwnedCountBadge: Int? {
        guard gridOptions.showOwned, let ownedCountBadge, ownedCountBadge > 1 else { return nil }
        // Defensive clamp in case bad data creates extreme values.
        return min(max(ownedCountBadge, 2), 999)
    }

    private var cardCornerRadius: CGFloat {
        (gridOptions.showCardName || showsFooter) ? 18 : 0
    }

    var body: some View {
        VStack(spacing: 0) {
            if gridOptions.showCardName {
                Text(card.cardName)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .padding(.horizontal, 8)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(dividerColor)
                            .frame(height: 1)
                    }
            }

            BrowseCardThumbnailView(
                imageURL: safeImageURL(relativePath: card.imageLowSrc),
                isOwned: isOwned,
                isWishlisted: isWishlisted,
                ownedCountBadge: visibleOwnedCountBadge
            )
            .frame(maxWidth: .infinity)
            .aspectRatio(5/7, contentMode: .fit)

            if showsFooter {
                VStack(spacing: 3) {
                    if gridOptions.showSetName, let setName, !setName.isEmpty {
                        Text(setName)
                            .font(.caption2)
                            .lineLimit(1)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }

                    if gridOptions.showOwned, let footnote, !footnote.isEmpty {
                        Text(footnote)
                            .font(.caption2)
                            .lineLimit(1)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }

                    if gridOptions.showSetID {
                        Text(trailingCardID)
                            .font(.caption2)
                            .lineLimit(1)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                    }

                    if gridOptions.showPricing {
                        BrowseGridPriceText(
                            card: card,
                            overridePrice: overridePrice,
                            gradeLabel: gradeLabel,
                            usesAccentColor: true
                        )
                        .frame(maxWidth: .infinity, alignment: .center)
                    }

                    if let postPriceFootnote, !postPriceFootnote.isEmpty {
                        Text(postPriceFootnote)
                            .font(.caption2)
                            .lineLimit(1)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity)
                .background(insetBackground)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(dividerColor)
                        .frame(height: 1)
                }
            }
        }
        .background(tileBackground)
        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .stroke(
                    isOwned ? services.theme.accentColor : tileBorder,
                    lineWidth: isOwned ? 1.8 : 1.2
                )
        }
    }

    private func safeImageURL(relativePath: String) -> URL? {
        let trimmed = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("http") {
            return URL(string: trimmed)
        }
        return AppConfiguration.imageURL(relativePath: trimmed)
    }

    private var trailingCardID: String {
        let number = card.cardNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        if number.isEmpty { return card.setCode }
        return number
    }
}

private struct BrowseCardThumbnailView: View {
    @Environment(AppServices.self) private var services
    let imageURL: URL?
    var isOwned = false
    var isWishlisted = false
    var ownedCountBadge: Int? = nil

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            CachedCardThumbnailImage(url: imageURL)
            if let ownedCountBadge, ownedCountBadge > 1 {
                if ownedCountBadge == 2 {
                    Image(systemName: "2.circle.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white, services.theme.accentColor)
                        .shadow(color: .black.opacity(0.18), radius: 3, x: 0, y: 1)
                        .padding(6)
                } else if ownedCountBadge == 3 {
                    Image(systemName: "3.circle.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white, services.theme.accentColor)
                        .shadow(color: .black.opacity(0.18), radius: 3, x: 0, y: 1)
                        .padding(6)
                } else if ownedCountBadge == 4 {
                    Image(systemName: "4.circle.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white, services.theme.accentColor)
                        .shadow(color: .black.opacity(0.18), radius: 3, x: 0, y: 1)
                        .padding(6)
                } else if ownedCountBadge == 5 {
                    Image(systemName: "5.circle.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white, services.theme.accentColor)
                        .shadow(color: .black.opacity(0.18), radius: 3, x: 0, y: 1)
                        .padding(6)
                } else if ownedCountBadge == 6 {
                    Image(systemName: "6.circle.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white, services.theme.accentColor)
                        .shadow(color: .black.opacity(0.18), radius: 3, x: 0, y: 1)
                        .padding(6)
                } else if ownedCountBadge == 7 {
                    Image(systemName: "7.circle.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white, services.theme.accentColor)
                        .shadow(color: .black.opacity(0.18), radius: 3, x: 0, y: 1)
                        .padding(6)
                } else if ownedCountBadge == 8 {
                    Image(systemName: "8.circle.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white, services.theme.accentColor)
                        .shadow(color: .black.opacity(0.18), radius: 3, x: 0, y: 1)
                        .padding(6)
                } else if ownedCountBadge == 9 {
                    Image(systemName: "9.circle.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white, services.theme.accentColor)
                        .shadow(color: .black.opacity(0.18), radius: 3, x: 0, y: 1)
                        .padding(6)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white, services.theme.accentColor)
                        .shadow(color: .black.opacity(0.18), radius: 3, x: 0, y: 1)
                        .padding(6)
                }
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

/// Subtle spring scale on press for all card grid cells — gives a premium tactile feel.
struct CardCellButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

private struct BrowseCardRow: Identifiable {
    let id: Int
    let card: Card
    let setName: String?
}

/// LazyVGrid inside an unbounded ScrollView triggers a SwiftUI iOS 26 layout crash.
/// Using LazyVStack with manual row chunking achieves virtualization without the bug.
struct EagerVGrid<Item: Identifiable, Cell: View>: View {
    let items: [Item]
    let columns: Int
    let spacing: CGFloat
    @ViewBuilder let cell: (Item) -> Cell

    var body: some View {
        let cols = max(columns, 1)
        let rows = stride(from: 0, to: items.count, by: cols).map {
            Array(items[$0..<min($0 + cols, items.count)])
        }
        LazyVStack(spacing: spacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, rowItems in
                HStack(spacing: spacing) {
                    ForEach(rowItems) { item in
                        cell(item)
                            .frame(maxWidth: .infinity)
                    }
                    if rowItems.count < cols {
                        ForEach(0..<(cols - rowItems.count), id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BrowseFeedSnapshot {
    var cards: [Card] = []
    var rows: [BrowseCardRow] = []
    var hasMoreCardsToLoad = false
}

enum BrowseHomeTab: String, CaseIterable, Identifiable {
    case cards
    case sets
    case pokemon
    case sealed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cards: return "Cards"
        case .sets: return "Sets"
        case .pokemon: return "Pokemon"
        case .sealed: return "Sealed"
        }
    }
}

enum BrowseInlineDetailRoute: Hashable {
    case set(TCGSet)
    case dex(dexId: Int, displayName: String)
    case onePieceCharacter(String)
    case onePieceSubtype(String)

    var title: String {
        switch self {
        case .set(let set):
            return set.name
        case .dex(_, let displayName):
            return displayName
        case .onePieceCharacter(let name), .onePieceSubtype(let name):
            return name
        }
    }
}


private struct BrowseCardGridButton: View {
    let row: BrowseCardRow
    let gridOptions: BrowseGridOptions
    let isOwned: Bool
    let isWishlisted: Bool
    let isMultiSelectActive: Bool
    @Binding var multiSelectedCardIDs: Set<String>

    @Environment(\.presentCard) private var presentCard
    @Environment(\.browseFeedCards) private var browseFeedCards

    private var isSelected: Bool {
        multiSelectedCardIDs.contains(row.card.masterCardId)
    }

    var body: some View {
        Button {
            if isMultiSelectActive {
                if isSelected {
                    multiSelectedCardIDs.remove(row.card.masterCardId)
                } else {
                    multiSelectedCardIDs.insert(row.card.masterCardId)
                    HapticManager.impact(.light)
                }
            } else {
                presentCard(row.card, browseFeedCards)
            }
        } label: {
            CardGridCell(
                card: row.card,
                gridOptions: gridOptions,
                setName: row.setName,
                isOwned: isOwned,
                isWishlisted: isWishlisted
            )
            .overlay(alignment: .topTrailing) {
                if isMultiSelectActive {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.blue : Color.white)
                        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                        .padding(6)
                }
            }
        }
        .buttonStyle(CardCellButtonStyle())
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

@MainActor
struct BrowseView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.presentCard) private var presentCard
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.rootFloatingChromeInset) private var rootFloatingChromeInset
    @Query(sort: \CardFolder.createdAt, order: .reverse) private var folders: [CardFolder]

    let collectionItems: [CollectionItem]

    @Binding var filters: BrowseCardGridFilters
    @Binding var inlineDetailFilters: BrowseCardGridFilters
    @Binding var gridOptions: BrowseGridOptions
    @Binding var isFilterMenuPresented: Bool
    @Binding var filterResultCount: Int
    @Binding var filterEnergyOptions: [String]
    @Binding var filterRarityOptions: [String]
    @Binding var filterTrainerTypeOptions: [String]
    @Binding var inlineDetailFilterResultCount: Int
    @Binding var inlineDetailFilterEnergyOptions: [String]
    @Binding var inlineDetailFilterRarityOptions: [String]
    @Binding var inlineDetailFilterTrainerTypeOptions: [String]
    @Binding var selectedTab: BrowseHomeTab
    @Binding var inlineDetailRoute: BrowseInlineDetailRoute?
    @Binding var isMultiSelectActive: Bool
    @Binding var multiSelectedCardIDs: Set<String>

    @State private var shuffledRefs: [CardRef] = []
    @State private var nextRefIndex = 0
    @State private var displayedCards: [Card] = []
    @State private var displayedRows: [BrowseCardRow] = []
    @State private var allBrowseFilterCards: [BrowseFilterCard] = []
    @State private var catalogOrderedRefs: [CardRef] = []
    @State private var catalogDisplayedCards: [Card] = []
    @State private var catalogDisplayedRows: [BrowseCardRow] = []
    @State private var browseFeedSnapshot = BrowseFeedSnapshot()
    @State private var catalogNextIndex = 0
    @State private var isLoadingInitial = true
    @State private var isLoadingMore = false
    @State private var isPreparingFilterCatalog = false
    /// Prevents concurrent full-filter-index loads (background warm vs active filter feed).
    @State private var isLoadingFullCatalog = false
    @State private var loadedBrand: TCGBrand?
    @State private var cachedSetNameByCode: [String: String] = [:]
    @State private var query = ""
    @State private var inlineDetailCards: [Card] = []
    @State private var inlineDetailPriceByCardID: [String: Double] = [:]
    @State private var inlineDetailQuery = ""
    @State private var inlineDetailLoading = false
    @State private var ownedCardIDsCache: Set<String> = []
    @State private var isUsingCatalogFeedSelection = false
    @State private var isInlineDetailPresented = false
    @State private var isViewVisible = false
    @State private var visibleBrowseResultCount = 0
    @State private var isBrowseBodyReady = false
    @State private var currentBrand: TCGBrand = .pokemon
    @State private var lastAutoLoadRowCount = 0
    @State private var multiSelectCollectionPayload: MultiSelectCollectionPayload?
    @State private var showMultiSelectFolderSheet = false
    @State private var wishlistAlertMessage: String?
    @State private var showWishlistAlert = false
    @State private var showWishlistPaywall = false
    @State private var multiSelectFolderNewTitle = ""
    @State private var showFolderCreateAlert = false
    @State private var addedMultiSelectFolderIDs: Set<UUID> = []

    private var inlineDetailPriceCacheTaskKey: String {
        let ids = inlineDetailCards.map(\.masterCardId).joined(separator: "|")
        return "\(currentBrand.rawValue)#\(ids)"
    }

    private var safeColumnCount: Int {
        min(max(gridOptions.columnCount, 1), 4)
    }

    private var visibleWishlistedCardIDs: Set<String> {
        Set((services.wishlist?.items ?? []).compactMap { item in
            let cardID = item.cardID
            let itemBrand = TCGBrand.inferredFromMasterCardId(cardID)
            return itemBrand == services.brandSettings.selectedCatalogBrand ? cardID : nil
        })
    }

    private var multiSelectedCards: [Card] {
        var cardsByMasterID: [String: Card] = [:]
        for card in browseFeedSnapshot.cards {
            cardsByMasterID[card.masterCardId] = card
        }
        for card in inlineDetailCards {
            cardsByMasterID[card.masterCardId] = card
        }
        return multiSelectedCardIDs.compactMap { cardsByMasterID[$0] }
    }

    private static let initialBatchSize = 36
    private static let catalogInitialBatchSize = 36
    private static let pageSize = 18
    private static let prefetchBuffer = 8

    var body: some View {
        Group {
            ZStack(alignment: .bottom) {
                if isBrowseBodyReady {
                    browseBodyContent
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }

                if isMultiSelectActive && !multiSelectedCardIDs.isEmpty {
                    multiSelectActionBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isMultiSelectActive && !multiSelectedCardIDs.isEmpty)
        .sheet(item: $multiSelectCollectionPayload) { payload in
            MultiSelectAddToCollectionSheet(cards: payload.cards)
                .environment(services)
        }
        .sheet(isPresented: $showMultiSelectFolderSheet, onDismiss: { addedMultiSelectFolderIDs.removeAll() }) {
            multiSelectFolderSheet
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
        .onAppear {
            isViewVisible = true
            isInlineDetailPresented = (inlineDetailRoute != nil)
            currentBrand = services.brandSettings.selectedCatalogBrand
            if isBrowseBodyReady == false {
                Task { @MainActor in
                    await Task.yield()
                    guard isViewVisible else { return }
                    isBrowseBodyReady = true
                }
            }
            let brandSnapshot = services.brandSettings.selectedCatalogBrand
            Task { @MainActor in
                await Task.yield()
                guard isViewVisible else { return }
                await scheduleOwnedCardIDsRefresh(for: brandSnapshot)
                await scheduleBrowseInitialization(for: brandSnapshot)
            }
        }
        .onDisappear {
            isViewVisible = false
        }
        .onChange(of: services.brandSettings.selectedCatalogBrand) { _, newBrand in
            currentBrand = newBrand
            Task { @MainActor in
                await Task.yield()
                guard isViewVisible else { return }
                await scheduleOwnedCardIDsRefresh(for: newBrand)
                await scheduleBrowseInitialization(for: newBrand)
            }
        }
        .onChange(of: filters) { _, newFilters in
            guard !isInlineDetailPresented else { return }
            let shouldUseCatalogFeed = selectedTab == .cards
                && (!query.isEmpty || newFilters.hasActiveFieldFilters || newFilters.hasActiveSort)
            Task { @MainActor in
                await Task.yield()
                guard isViewVisible else { return }
                handleBrowseFiltersChanged(usingCatalogFeed: shouldUseCatalogFeed)
            }
        }
        .onChange(of: query) { _, newQuery in
            guard selectedTab == .cards else { return }
            let shouldUseCatalogFeed = !newQuery.isEmpty || filters.hasActiveFieldFilters || filters.hasActiveSort
            Task { @MainActor in
                await Task.yield()
                guard isViewVisible else { return }
                handleBrowseFiltersChanged(usingCatalogFeed: shouldUseCatalogFeed)
            }
        }
        .onChange(of: selectedTab) { _, newValue in
            Task { @MainActor in
                await Task.yield()
                guard isViewVisible else { return }
                query = ""
                if tabSupportsInlineDetail(newValue) == false {
                    inlineDetailRoute = nil
                }
                if newValue != .cards {
                    isUsingCatalogFeedSelection = false
                    syncFilterMenuState(usingCatalogFeed: false)
                } else {
                    let shouldUseCatalogFeed = !query.isEmpty || filters.hasActiveFieldFilters || filters.hasActiveSort
                    handleBrowseFiltersChanged(usingCatalogFeed: shouldUseCatalogFeed)
                }
            }
        }
        .onChange(of: inlineDetailRoute) { _, newValue in
            Task { @MainActor in
                await Task.yield()
                guard isViewVisible else { return }
                isInlineDetailPresented = (newValue != nil)
                inlineDetailQuery = ""
                inlineDetailPriceByCardID = [:]
                await loadInlineDetailIfNeeded(route: newValue)
            }
        }
        .task(id: inlineDetailPriceCacheTaskKey) {
            await refreshInlineDetailPriceCache()
        }
        .onChange(of: inlineDetailFilters.sortBy) { _, sortBy in
            guard sortBy == .price else { return }
            Task { @MainActor in
                await refreshInlineDetailPriceCache()
            }
        }
    }

    @MainActor
    private func scheduleBrowseInitialization(for selectedBrand: TCGBrand) async {
        guard isViewVisible else { return }
        let selectedTabSnapshot = selectedTab
        let querySnapshot = query
        // Avoid reading filter bindings during immediate appearance updates.
        // The active filters/query pipeline will reconcile right after startup.
        let filtersSnapshot = BrowseCardGridFilters()
        // Avoid touching the `@Query`-backed collection rows during SwiftUI's
        // appearance update cycle. Ownership-sensitive filters are refreshed
        // later through the normal change handlers once the view is stable.
        let ownedCardIDsSnapshot: Set<String> = []
        let shouldUseCatalogFeedOnStartup = false
        isUsingCatalogFeedSelection = shouldUseCatalogFeedOnStartup
        await initializeBrowseData(
            for: selectedBrand,
            selectedTabSnapshot: selectedTabSnapshot,
            querySnapshot: querySnapshot,
            filtersSnapshot: filtersSnapshot,
            ownedCardIDsSnapshot: ownedCardIDsSnapshot,
            shouldUseCatalogFeedOnStartup: shouldUseCatalogFeedOnStartup
        )
    }

    @MainActor
    private func scheduleOwnedCardIDsRefresh(for brand: TCGBrand) async {
        guard isViewVisible else { return }
        await Task.yield()
        guard isViewVisible else { return }
        ownedCardIDsCache = Set(collectionItems.compactMap { item in
            let itemBrand = TCGBrand.inferredFromMasterCardId(item.cardID)
            return itemBrand == brand ? item.cardID : nil
        })
        if isInlineDetailPresented {
            syncFilterMenuState(usingCatalogFeed: false)
        } else {
            // Avoid re-entering the feed-selection decision path from the
            // ownership refresh task; preserve current feed mode and only
            // rebuild catalog results when that mode is already active.
            if isUsingCatalogFeedSelection {
                guard isViewVisible else { return }
                await ensureAllBrowseFilterCardsLoaded(showsPreparingBanner: false)
                await rebuildCatalogFeedIfNeeded(
                    selectedTab: selectedTab,
                    query: query,
                    filters: filters,
                    brand: currentBrand,
                    ownedCardIDs: ownedCardIDsCache,
                    shouldUseCatalogFeed: true
                )
            } else {
                syncFilterMenuState(usingCatalogFeed: false)
            }
        }
    }

    @ViewBuilder
    private var browseBodyContent: some View {
        if selectedTab == .cards {
            cardsTabScrollView
        } else {
            auxiliaryTabScrollView
        }
    }

    @MainActor
    private func initializeBrowseData(
        for selectedBrand: TCGBrand,
        selectedTabSnapshot: BrowseHomeTab,
        querySnapshot: String,
        filtersSnapshot: BrowseCardGridFilters,
        ownedCardIDsSnapshot: Set<String>,
        shouldUseCatalogFeedOnStartup: Bool
    ) async {
        guard isViewVisible else { return }
        if loadedBrand != selectedBrand {
            shuffledRefs = []
            nextRefIndex = 0
            displayedCards = []
            displayedRows = []
            allBrowseFilterCards = []
            catalogOrderedRefs = []
            catalogDisplayedCards = []
            catalogDisplayedRows = []
            browseFeedSnapshot = BrowseFeedSnapshot()
            lastAutoLoadRowCount = 0
            catalogNextIndex = 0
            isLoadingInitial = true

            // The root startup pipeline already refreshes catalog data.
            // Browse only needs to ensure the selected brand's sets are present.
            services.cardData.resetBrowseFeedSessionOnly()
            await services.cardData.loadSets(preferSyncedCatalog: true)
            guard isViewVisible else { return }
            cachedSetNameByCode = firstValueMap(services.cardData.sets, key: \.setCode, value: \.name)
            loadedBrand = selectedBrand
        } else if cachedSetNameByCode.isEmpty, services.cardData.sets.isEmpty == false {
            cachedSetNameByCode = firstValueMap(services.cardData.sets, key: \.setCode, value: \.name)
        }

        await Task.yield()
        await Task.yield()
        guard isViewVisible else { return }
        await bootstrapFeed(forceReshuffle: false)
        guard isViewVisible else { return }
        if shouldUseCatalogFeedOnStartup {
            await ensureAllBrowseFilterCardsLoaded(
                showsPreparingBanner: true,
                usingCatalogFeed: true
            )
            guard isViewVisible else { return }
            await rebuildCatalogFeedIfNeeded(
                selectedTab: selectedTabSnapshot,
                query: querySnapshot,
                filters: filtersSnapshot,
                brand: selectedBrand,
                ownedCardIDs: ownedCardIDsSnapshot,
                shouldUseCatalogFeed: shouldUseCatalogFeedOnStartup
            )
        } else {
            await ensureAllBrowseFilterCardsLoaded(
                showsPreparingBanner: false,
                usingCatalogFeed: false
            )
        }
    }

    @ViewBuilder
    private var browseCardGrid: some View {
        let snapshot = browseFeedSnapshot
        let usesCatalogFeed = isUsingCatalogFeedSelection
        VStack(spacing: 0) {
            EagerVGrid(items: snapshot.rows, columns: safeColumnCount, spacing: 12) { row in
                BrowseCardGridButton(
                    row: row,
                    gridOptions: gridOptions,
                    isOwned: ownedCardIDsCache.contains(row.card.masterCardId),
                    isWishlisted: visibleWishlistedCardIDs.contains(row.card.masterCardId),
                    isMultiSelectActive: isMultiSelectActive,
                    multiSelectedCardIDs: $multiSelectedCardIDs
                )
                .onAppear {
                    guard snapshot.hasMoreCardsToLoad else { return }
                    guard row.id >= max(snapshot.rows.count - safeColumnCount, 0) else { return }
                    guard snapshot.rows.count != lastAutoLoadRowCount else { return }
                    lastAutoLoadRowCount = snapshot.rows.count
                    Task { await loadNextPageIfNeeded(usingCatalogFeed: usesCatalogFeed) }
                }
            }
            if isLoadingMore {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
            }
        }
        .environment(\.browseFeedCards, snapshot.cards)
        .padding(.horizontal, 16)
        .padding(.bottom, isMultiSelectActive && !multiSelectedCardIDs.isEmpty ? 96 : 16)
        .onChange(of: snapshot.rows.count) { _, newValue in
            if newValue < lastAutoLoadRowCount {
                lastAutoLoadRowCount = 0
            }
        }
    }

    private var formattedResultCount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: visibleBrowseResultCount)) ?? "\(visibleBrowseResultCount)"
    }

    private var browseSearchPlaceholder: String {
        if let inlineDetailRoute {
            switch inlineDetailRoute {
            case .set:
                return "Search \(formattedResultCount) cards in set"
            case .dex:
                return "Search \(formattedResultCount) cards for Pokémon"
            case .onePieceCharacter:
                return "Search \(formattedResultCount) cards for character"
            case .onePieceSubtype:
                return "Search \(formattedResultCount) cards for subtype"
            }
        }
        switch selectedTab {
        case .cards:
            return "Search \(formattedResultCount) cards"
        case .sets:
            return "Search sets"
        case .pokemon:
            return currentBrand == .pokemon ? "Search Pokémon" : "Search characters or subtypes"
        case .sealed:
            return "Search sealed"
        }
    }

    @ViewBuilder
    private var browseTabsRow: some View {
        if isInlineDetailPresented {
            EmptyView()
        } else {
            SlidingSegmentedPicker(
                selection: $selectedTab,
                items: BrowseHomeTab.allCases,
                title: { $0.title }
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
    }

    private var browseSearchRow: some View {
        BrowseInlineSearchField(
            title: browseSearchPlaceholder,
            text: isInlineDetailPresented ? $inlineDetailQuery : $query
        )
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
    }

    @ViewBuilder
    private var browseResultCountRow: some View {
        if selectedTab == .cards || isInlineDetailPresented {
            EmptyView()
        }
    }

    private var cardsTabScrollView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // Keeps first row clear of the overlaid search bar; spacer scrolls away so cards can pass under the glass.
                Color.clear
                    .frame(height: rootFloatingChromeInset)
                browseTabsRow
                browseSearchRow
                browseResultCountRow
                activeTabContent
                if selectedTab == .cards && isPreparingFilterCatalog {
                    ProgressView("Preparing filters…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                if selectedTab == .cards && isLoadingMore {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 12)
                }
            }
        }
        .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y }) { _, _ in
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }

    private var auxiliaryTabScrollView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                Color.clear
                    .frame(height: rootFloatingChromeInset)
                browseTabsRow
                browseSearchRow
                browseResultCountRow
                activeTabContent
            }
        }
        .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y }) { _, _ in
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }

    @ViewBuilder
    private var activeTabContent: some View {
        switch selectedTab {
        case .cards:
            browseCardsContent
        case .sets:
            if let inlineDetailRoute {
                inlineDetailContent(route: inlineDetailRoute)
            } else {
                BrowseSetsTabContent(query: query) { set in
                    inlineDetailRoute = .set(set)
                }
            }
        case .pokemon:
            if let inlineDetailRoute {
                inlineDetailContent(route: inlineDetailRoute)
            } else {
                BrowsePokemonTabContent(query: query) { route in
                    inlineDetailRoute = route
                }
            }
        case .sealed:
            BrowseSealedTabContent(query: query, filters: filters, gridOptions: gridOptions)
        }
    }

    @ViewBuilder
    private func inlineDetailContent(route: BrowseInlineDetailRoute) -> some View {
        let filteredCards = filteredInlineDetailCards
        if inlineDetailLoading {
            ProgressView("Loading cards…")
                .frame(maxWidth: .infinity, minHeight: 280)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        } else if filteredCards.isEmpty {
            ContentUnavailableView(
                inlineDetailCards.isEmpty ? "No cards found" : "No matching cards",
                systemImage: "magnifyingglass",
                description: Text(inlineDetailCards.isEmpty ? "No cards were found for \(route.title)." : "Try a different card name or number.")
            )
            .frame(maxWidth: .infinity, minHeight: 280)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        } else {
            EagerVGrid(items: filteredCards, columns: safeColumnCount, spacing: 12) { card in
                let index = filteredCards.firstIndex(where: { $0.id == card.id }) ?? 0
                Button {
                    if isMultiSelectActive {
                        toggleMultiSelectCardID(card.masterCardId)
                    } else {
                        presentCard(card, filteredCards)
                    }
                } label: {
                    CardGridCell(
                        card: card,
                        gridOptions: gridOptions,
                        setName: cachedSetNameByCode[card.setCode],
                        isOwned: ownedCardIDsCache.contains(card.masterCardId),
                        isWishlisted: visibleWishlistedCardIDs.contains(card.masterCardId)
                    )
                    .overlay(alignment: .topTrailing) {
                        if isMultiSelectActive {
                            Image(systemName: multiSelectedCardIDs.contains(card.masterCardId) ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(multiSelectedCardIDs.contains(card.masterCardId) ? Color.blue : Color.white)
                                .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                                .padding(6)
                        }
                    }
                }
                .buttonStyle(CardCellButtonStyle())
                .onAppear {
                    ImagePrefetcher.shared.prefetchCardWindow(filteredCards, startingAt: index + 1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, isMultiSelectActive && !multiSelectedCardIDs.isEmpty ? 96 : 16)
        }
    }

    private var filteredInlineDetailCards: [Card] {
        let filtered = filterBrowseCards(
            inlineDetailCards,
            query: inlineDetailQuery,
            filters: inlineDetailFilters,
            ownedCardIDs: ownedCardIDsCache,
            brand: currentBrand,
            sets: services.cardData.sets,
            priceByCardID: inlineDetailPriceByCardID
        )
        if case .some(.set(_)) = inlineDetailRoute, inlineDetailFilters.sortBy == .cardNumber {
            return Array(filtered.reversed())
        }
        return filtered
    }

    private func toggleMultiSelectCardID(_ masterCardID: String) {
        if multiSelectedCardIDs.contains(masterCardID) {
            multiSelectedCardIDs.remove(masterCardID)
        } else {
            multiSelectedCardIDs.insert(masterCardID)
            HapticManager.impact(.light)
        }
    }

    private var multiSelectActionBar: some View {
        HStack(spacing: 8) {
            multiSelectActionButton(
                title: "Add to Collection",
                systemImage: "plus.circle.fill",
                tint: Color(red: 0.28, green: 0.84, blue: 0.39)
            ) {
                guard !multiSelectedCards.isEmpty else { return }
                multiSelectCollectionPayload = MultiSelectCollectionPayload(cards: multiSelectedCards)
            }

            multiSelectActionButton(
                title: "Wish List",
                systemImage: "star",
                tint: Color(red: 0.99, green: 0.72, blue: 0.22)
            ) {
                addSelectedToWishlist()
            }

            multiSelectActionButton(
                title: "Add to Folder",
                systemImage: "folder.badge.plus",
                tint: Color(red: 0.18, green: 0.72, blue: 0.88)
            ) {
                guard !multiSelectedCards.isEmpty else { return }
                addedMultiSelectFolderIDs.removeAll()
                showMultiSelectFolderSheet = true
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .safeAreaPadding(.bottom, 0)
    }

    private func multiSelectActionButton(title: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background {
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule(style: .continuous)
                            .fill(
                                colorScheme == .dark
                                    ? Color.black.opacity(0.30)
                                    : Color.black.opacity(0.12)
                            )
                    }
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.10), lineWidth: 0.8)
                    )
            }
            .accessibilityLabel(title)
        }
        .buttonStyle(.plain)
    }

    private var multiSelectFolderSheet: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        multiSelectFolderNewTitle = ""
                        showFolderCreateAlert = true
                    } label: {
                        Label("New Folder…", systemImage: "folder.badge.plus")
                            .foregroundStyle(.primary)
                    }
                }
                if !folders.isEmpty {
                    Section("MY FOLDERS") {
                        ForEach(folders) { folder in
                            let alreadyAdded = addedMultiSelectFolderIDs.contains(folder.id)
                            Button {
                                guard !alreadyAdded else { return }
                                addSelectedCards(to: folder)
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
                    Button("Done") { showMultiSelectFolderSheet = false }
                }
            }
            .alert("New Folder", isPresented: $showFolderCreateAlert) {
                TextField("Folder name", text: $multiSelectFolderNewTitle)
                Button("Create") { createFolderAndAddSelected() }
                Button("Cancel", role: .cancel) { multiSelectFolderNewTitle = "" }
            }
        }
    }

    private func addSelectedToWishlist() {
        guard let wl = services.wishlist else {
            wishlistAlertMessage = "Wishlist isn't available yet. Try again in a moment."
            showWishlistAlert = true
            return
        }
        var addedCount = 0
        for card in multiSelectedCards {
            do {
                try wl.addItem(cardID: card.masterCardId, variantKey: "normal", notes: "")
                addedCount += 1
            } catch let error as WishlistError {
                switch error {
                case .limitReached:
                    showWishlistPaywall = true
                    return
                case .alreadyExists:
                    break
                case .saveFailed:
                    break
                }
            } catch {
                break
            }
        }
        if addedCount > 0 {
            HapticManager.notification(.success)
        }
    }

    private func addSelectedCards(to folder: CardFolder) {
        for card in multiSelectedCards {
            let alreadyIn = (folder.items ?? []).contains { $0.cardID == card.masterCardId && $0.variantKey == "normal" }
            guard !alreadyIn else { continue }
            let item = CardFolderItem(cardID: card.masterCardId, variantKey: "normal")
            item.folder = folder
            modelContext.insert(item)
        }
        try? modelContext.save()
        addedMultiSelectFolderIDs.insert(folder.id)
        HapticManager.notification(.success)
    }

    private func createFolderAndAddSelected() {
        let title = multiSelectFolderNewTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        let folder = CardFolder(title: title)
        modelContext.insert(folder)

        for card in multiSelectedCards {
            let item = CardFolderItem(cardID: card.masterCardId, variantKey: "normal")
            item.folder = folder
            modelContext.insert(item)
        }

        try? modelContext.save()
        addedMultiSelectFolderIDs.insert(folder.id)
        multiSelectFolderNewTitle = ""
        HapticManager.notification(.success)
    }

    @MainActor
    private func refreshInlineDetailPriceCache() async {
        guard isInlineDetailPresented, !inlineDetailCards.isEmpty else {
            inlineDetailPriceByCardID = [:]
            return
        }
        var next: [String: Double] = [:]
        next.reserveCapacity(inlineDetailCards.count)
        for card in inlineDetailCards {
            guard let entry = await services.pricing.pricing(for: card),
                  let usd = browseMarketPriceUSD(for: entry) else { continue }
            next[card.masterCardId] = usd
        }
        inlineDetailPriceByCardID = next
    }

    @ViewBuilder
    private var browseCardsContent: some View {
        if isLoadingInitial {
            ProgressView("Loading cards…")
                .frame(maxWidth: .infinity, minHeight: 280)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        } else if displayedCards.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("No cards in the catalog yet.")
                    .foregroundStyle(.secondary)
                if let err = services.cardData.lastError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Text("Pull to refresh after your catalog syncs, or check BINDR_R2_BASE_URL in Info.plist.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, minHeight: 280, alignment: .center)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        } else {
            browseCardGrid
        }
    }

    @MainActor
    private func bootstrapFeed(forceReshuffle: Bool) async {
        guard isViewVisible else { return }
        if !forceReshuffle && !displayedCards.isEmpty { return }
        ImagePrefetcher.shared.cancelAll()
        isLoadingInitial = true
        let refs = await services.cardData.browseFeedCardRefs(forceReshuffle: forceReshuffle)
        guard isViewVisible else { return }
        shuffledRefs = refs
        nextRefIndex = 0
        displayedCards = []
        guard !refs.isEmpty else { isLoadingInitial = false; return }
        let firstEnd = min(Self.initialBatchSize, refs.count)
        let batch = Array(refs[..<firstEnd])
        nextRefIndex = firstEnd
        displayedCards = await services.cardData.cardsInOrder(refs: batch)
        guard isViewVisible else { return }
        displayedRows = buildBrowseRows(from: displayedCards)
        allBrowseFilterCards = []
        catalogOrderedRefs = []
        catalogDisplayedCards = []
        catalogDisplayedRows = []
        catalogNextIndex = 0
        refreshBrowseFeedSnapshot(usingCatalogFeed: false)
        isLoadingInitial = false
        ImagePrefetcher.shared.prefetchCardWindow(displayedCards, startingAt: 0, count: 24)
        prefetchNextWindow(usingCatalogFeed: false)
        syncFilterMenuState(usingCatalogFeed: false)
    }

    @MainActor
    private func loadNextPageIfNeeded(usingCatalogFeed: Bool) async {
        guard isViewVisible else { return }
        guard !isLoadingMore else { return }
        if usingCatalogFeed {
            guard catalogNextIndex < catalogOrderedRefs.count else { return }
            isLoadingMore = true
            let end = min(catalogNextIndex + Self.pageSize, catalogOrderedRefs.count)
            let batch = Array(catalogOrderedRefs[catalogNextIndex..<end])
            catalogNextIndex = end
            let more = await services.cardData.cardsInOrder(refs: batch)
            guard isViewVisible else { return }
            catalogDisplayedCards.append(contentsOf: more)
            catalogDisplayedRows = buildBrowseRows(from: catalogDisplayedCards)
            refreshBrowseFeedSnapshot(usingCatalogFeed: true)
            isLoadingMore = false
            syncFilterMenuState(usingCatalogFeed: true)
            return
        }
        guard nextRefIndex < shuffledRefs.count else { return }
        isLoadingMore = true
        let end = min(nextRefIndex + Self.pageSize, shuffledRefs.count)
        let batch = Array(shuffledRefs[nextRefIndex..<end])
        nextRefIndex = end
        let more = await services.cardData.cardsInOrder(refs: batch)
        guard isViewVisible else { return }
        displayedCards.append(contentsOf: more)
        displayedRows = buildBrowseRows(from: displayedCards)
        refreshBrowseFeedSnapshot(usingCatalogFeed: false)
        isLoadingMore = false
        prefetchNextWindow(usingCatalogFeed: false)
        syncFilterMenuState(usingCatalogFeed: false)
    }

    private func prefetchNextWindow(usingCatalogFeed: Bool) {
        guard usingCatalogFeed == false else { return }
        let end = min(nextRefIndex + Self.pageSize, shuffledRefs.count)
        guard nextRefIndex < end else { return }
        let upcoming = Array(shuffledRefs[nextRefIndex..<end])
        Task(priority: .low) {
            let cards = await services.cardData.cardsInOrder(refs: upcoming)
            let urls = cards.map { AppConfiguration.imageURL(relativePath: $0.imageLowSrc) }
            ImagePrefetcher.shared.prefetch(urls)
        }
    }

    @MainActor
    private func ensureAllBrowseFilterCardsLoaded(
        showsPreparingBanner: Bool = true,
        usingCatalogFeed: Bool? = nil
    ) async {
        guard isViewVisible else { return }
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
        guard isViewVisible else { return }
        allBrowseFilterCards = loaded
        isLoadingFullCatalog = false
        if showsPreparingBanner {
            isPreparingFilterCatalog = false
        }
        syncFilterMenuState(usingCatalogFeed: usingCatalogFeed)
    }

    @MainActor
    private func rebuildCatalogFeedIfNeeded(
        selectedTab: BrowseHomeTab,
        query: String,
        filters: BrowseCardGridFilters,
        brand: TCGBrand,
        ownedCardIDs: Set<String>,
        shouldUseCatalogFeed: Bool
    ) async {
        guard isViewVisible else { return }
        if shouldUseCatalogFeed == false {
            isUsingCatalogFeedSelection = false
            catalogOrderedRefs = []
            catalogDisplayedCards = []
            catalogDisplayedRows = []
            catalogNextIndex = 0
            refreshBrowseFeedSnapshot(usingCatalogFeed: false)
            syncFilterMenuState(usingCatalogFeed: false)
            return
        }
        guard !allBrowseFilterCards.isEmpty else { return }
        let ordered = await orderedFilteredRefs(
            from: allBrowseFilterCards,
            query: query,
            filters: filters,
            brand: brand,
            ownedCardIDs: ownedCardIDs
        )
        guard isViewVisible else { return }
        isUsingCatalogFeedSelection = true
        catalogOrderedRefs = ordered
        let initialEnd = min(Self.catalogInitialBatchSize, ordered.count)
        let initialRefs = Array(ordered.prefix(initialEnd))
        catalogDisplayedCards = await services.cardData.cardsInOrder(refs: initialRefs)
        guard isViewVisible else { return }
        catalogDisplayedRows = buildBrowseRows(from: catalogDisplayedCards)
        catalogNextIndex = initialEnd
        refreshBrowseFeedSnapshot(usingCatalogFeed: true)
        syncFilterMenuState(usingCatalogFeed: true)
    }

    @MainActor
    private func handleBrowseFiltersChanged(usingCatalogFeed: Bool) {
        if isInlineDetailPresented {
            syncFilterMenuState(usingCatalogFeed: false)
            return
        }
        let selectedTabSnapshot = selectedTab
        let querySnapshot = query
        let filtersSnapshot = filters
        let brandSnapshot = currentBrand
        let ownedCardIDsSnapshot = ownedCardIDsCache
        let isUsingCatalogFeed = usingCatalogFeed
        self.isUsingCatalogFeedSelection = isUsingCatalogFeed
        if isUsingCatalogFeed {
            Task {
                await ensureAllBrowseFilterCardsLoaded(showsPreparingBanner: true)
                await rebuildCatalogFeedIfNeeded(
                    selectedTab: selectedTabSnapshot,
                    query: querySnapshot,
                    filters: filtersSnapshot,
                    brand: brandSnapshot,
                    ownedCardIDs: ownedCardIDsSnapshot,
                    shouldUseCatalogFeed: isUsingCatalogFeed
                )
            }
        } else {
            catalogOrderedRefs = []
            catalogDisplayedCards = []
            catalogDisplayedRows = []
            catalogNextIndex = 0
            refreshBrowseFeedSnapshot(usingCatalogFeed: false)
            syncFilterMenuState(usingCatalogFeed: false)
        }
    }

    private func refreshBrowseFeedSnapshot(usingCatalogFeed: Bool) {
        if usingCatalogFeed {
            browseFeedSnapshot = BrowseFeedSnapshot(
                cards: catalogDisplayedCards,
                rows: catalogDisplayedRows,
                hasMoreCardsToLoad: catalogNextIndex < catalogOrderedRefs.count
            )
        } else {
            browseFeedSnapshot = BrowseFeedSnapshot(
                cards: displayedCards,
                rows: displayedRows,
                hasMoreCardsToLoad: nextRefIndex < shuffledRefs.count
            )
        }
    }

    private func buildBrowseRows(from cards: [Card]) -> [BrowseCardRow] {
        let setNames = cachedSetNameByCode
        var rows: [BrowseCardRow] = []
        rows.reserveCapacity(cards.count)
        for (index, card) in cards.enumerated() {
            rows.append(
                BrowseCardRow(
                    id: index,
                    card: card,
                    setName: setNames[card.setCode]
                )
            )
        }
        return rows
    }

    private func orderedFilteredRefs(
        from cards: [BrowseFilterCard],
        query: String,
        filters: BrowseCardGridFilters,
        brand: TCGBrand,
        ownedCardIDs: Set<String>
    ) async -> [CardRef] {
        let filtered = filterCards(
            cards,
            query: query,
            filters: filters,
            brand: brand,
            ownedCardIDs: ownedCardIDs
        )
        switch filters.sortBy {
        case .random, .acquiredDateNewest:
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
        case .price:
            let refs = filtered.map(\.ref)
            let cards = await services.cardData.cardsInOrder(refs: refs)
            var pricedCards: [(card: Card, price: Double?)] = []
            pricedCards.reserveCapacity(cards.count)
            for card in cards {
                let entry = await services.pricing.pricing(for: card)
                pricedCards.append((card, browseMarketPriceUSD(for: entry)))
            }
            return pricedCards.sorted { lhs, rhs in
                switch (lhs.price, rhs.price) {
                case let (l?, r?):
                    if l != r { return l > r }
                case (.some, nil):
                    return true
                case (nil, .some):
                    return false
                case (nil, nil):
                    break
                }
                if lhs.card.cardName != rhs.card.cardName {
                    return lhs.card.cardName.localizedCaseInsensitiveCompare(rhs.card.cardName) == .orderedAscending
                }
                if lhs.card.setCode != rhs.card.setCode {
                    return compareReleaseDateNewestFirst(lhsSetCode: lhs.card.setCode, rhsSetCode: rhs.card.setCode)
                }
                return lhs.card.cardNumber.localizedStandardCompare(rhs.card.cardNumber) == .orderedAscending
            }.map { CardRef(masterCardId: $0.card.masterCardId, setCode: $0.card.setCode) }
        }
    }

    private func filterCards(
        _ cards: [BrowseFilterCard],
        query: String,
        filters: BrowseCardGridFilters,
        brand: TCGBrand,
        ownedCardIDs: Set<String>
    ) -> [BrowseFilterCard] {
        let normalizedQuery = normalizedBrowseSearchText(query)
        let setReleaseDateByCode = firstValueMap(services.cardData.sets, key: \.setCode) { $0.releaseDate ?? "" }
        return cards.filter { card in
            let matchesQuery = normalizedQuery.isEmpty
                || normalizedBrowseSearchText(card.cardName).contains(normalizedQuery)
                || normalizedBrowseSearchText(card.cardNumber).contains(normalizedQuery)
                || normalizedBrowseSearchText(card.setCode).contains(normalizedQuery)
                || normalizedBrowseSearchText(card.subtype).contains(normalizedQuery)
                || (card.subtypes?.contains { normalizedBrowseSearchText($0).contains(normalizedQuery) } == true)
            guard matchesQuery else { return false }

            if brand == .pokemon,
               filters.cardTypes.isEmpty == false,
               filters.cardTypes.contains(resolvedCardType(for: card, brand: brand)) == false {
                return false
            }
            if filters.rarePlusOnly && isCommonOrUncommon(card.rarity) {
                return false
            }
            if filters.hideOwned && ownedCardIDs.contains(card.masterCardId) {
                return false
            }
            if brand == .pokemon,
               filters.legalities.isEmpty == false,
               pokemonCardMatchesLegalityFilters(
                    selectedLegalityFilters: filters.legalities,
                    setCode: card.setCode,
                    releaseDate: setReleaseDateByCode[card.setCode],
                    category: card.category,
                    energyType: card.energyType,
                    regulationMark: card.regulationMark,
                    cardName: card.cardName
               ) == false {
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
            return true
        }
    }

    private func resolvedCardType(for card: BrowseFilterCard, brand: TCGBrand) -> BrowseCardTypeFilter {
        if brand == .onePiece {
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

    @MainActor
    private func syncFilterMenuState(usingCatalogFeed: Bool? = nil) {
        if isInlineDetailPresented {
            let inlineCount = filteredInlineDetailCards.count
            visibleBrowseResultCount = inlineCount
            filterResultCount = inlineCount
            filterEnergyOptions = cardEnergyOptions(inlineDetailCards)
            filterRarityOptions = cardRarityOptions(inlineDetailCards)
            filterTrainerTypeOptions = cardTrainerTypeOptions(inlineDetailCards)
            inlineDetailFilterResultCount = inlineCount
            return
        }
        let isUsingCatalogFeed = usingCatalogFeed ?? isUsingCatalogFeedSelection
        let hasCardFeedFilters = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || filters.hasActiveFieldFilters
            || filters.hasActiveSort
        let count: Int
        if selectedTab != .cards {
            count = 0
        } else if isUsingCatalogFeed {
            count = catalogOrderedRefs.count
        } else if hasCardFeedFilters == false, shuffledRefs.isEmpty == false {
            // No filters/search: show total available browse feed size, not just current page.
            count = shuffledRefs.count
        } else {
            count = browseFeedSnapshot.cards.count
        }
        visibleBrowseResultCount = count
        filterResultCount = count
        if allBrowseFilterCards.isEmpty {
            filterEnergyOptions = cardEnergyOptions(browseFeedSnapshot.cards)
            filterRarityOptions = cardRarityOptions(browseFeedSnapshot.cards)
            filterTrainerTypeOptions = []
        } else {
            filterEnergyOptions = browseFilterEnergyOptions(allBrowseFilterCards)
            filterRarityOptions = browseFilterRarityOptions(allBrowseFilterCards)
            filterTrainerTypeOptions = browseFilterTrainerTypeOptions(allBrowseFilterCards)
        }
    }

    private func tabSupportsInlineDetail(_ tab: BrowseHomeTab) -> Bool {
        switch tab {
        case .sets, .pokemon:
            return true
        case .cards, .sealed:
            return false
        }
    }

    @MainActor
    private func loadInlineDetailIfNeeded(route: BrowseInlineDetailRoute?) async {
        guard let route else {
            inlineDetailCards = []
            inlineDetailLoading = false
            syncFilterMenuState(usingCatalogFeed: false)
            return
        }

        inlineDetailLoading = true
        defer { inlineDetailLoading = false }

        switch route {
        case .set(let set):
            let loaded = await services.cardData.loadCards(forSetCode: set.setCode)
            inlineDetailCards = sortCardsByLocalIdHighestFirst(loaded)
        case .dex(let dexId, _):
            inlineDetailCards = await services.cardData.cards(matchingNationalDex: dexId)
        case .onePieceCharacter(let name):
            inlineDetailCards = await services.cardData.cards(matchingOnePieceCharacterName: name)
        case .onePieceSubtype(let name):
            inlineDetailCards = await services.cardData.cards(matchingOnePieceSubtype: name)
        }

        ImagePrefetcher.shared.prefetchCardWindow(inlineDetailCards, startingAt: 0, count: 24)
        syncFilterMenuState(usingCatalogFeed: false)
    }
}

private struct BrowseSetsTabContent: View {
    @Environment(AppServices.self) private var services
    @Query private var collectionItems: [CollectionItem]

    let query: String
    let onSelectSet: (TCGSet) -> Void

    @State private var uniqueCollectedCountBySetCode: [String: Int] = [:]
    @State private var setMarketValueUSDByKey: [String: Double] = [:]
    @State private var loadedSetMarketValueKeys: Set<String> = []
    @State private var loadingSetMarketValueKeys: Set<String> = []

    private var filteredSets: [TCGSet] {
        let sets = services.cardData.allSetsSortedByReleaseDateNewestFirst()
        let normalizedQuery = normalizedBrowseSearchText(query)
        guard !normalizedQuery.isEmpty else { return sets }
        return sets.filter { set in
            normalizedBrowseSearchText(set.name).contains(normalizedQuery)
                || normalizedBrowseSearchText(set.setCode).contains(normalizedQuery)
                || normalizedBrowseSearchText(set.seriesName).contains(normalizedQuery)
        }
    }

    private var groupedSets: [(title: String, sets: [TCGSet])] {
        let grouped = Dictionary(grouping: filteredSets, by: browseSeriesTitle(for:))
        return grouped
            .map { (title: $0.key, sets: sortSetsNewestFirst($0.value)) }
            .sorted { lhs, rhs in
                let lhsNewest = lhs.sets.map(\.releaseDate).compactMap { $0 }.max() ?? ""
                let rhsNewest = rhs.sets.map(\.releaseDate).compactMap { $0 }.max() ?? ""
                if lhsNewest != rhsNewest { return lhsNewest > rhsNewest }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    private var collectionProgressTaskKey: String {
        let snapshot = collectionItems
            .map { "\($0.cardID)|\($0.quantity)" }
            .sorted()
            .joined(separator: ",")
        return "\(services.brandSettings.selectedCatalogBrand.rawValue)#\(snapshot)"
    }

    var body: some View {
        Group {
            if filteredSets.isEmpty {
                ContentUnavailableView(
                    "No matching sets",
                    systemImage: "magnifyingglass",
                    description: Text("Try a different set name or code.")
                )
                .frame(maxWidth: .infinity, minHeight: 280)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
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
                        .padding(.horizontal, 16)
                        .padding(.top, 10)

                        LazyVStack(spacing: 0) {
                            ForEach(Array(group.sets.enumerated()), id: \.offset) { _, set in
                                Button {
                                    onSelectSet(set)
                                } label: {
                                    HStack(spacing: 14) {
                                        SetLogoAsyncImage(
                                            logoSrc: set.logoSrc,
                                            height: 44,
                                            brand: services.brandSettings.selectedCatalogBrand
                                        )
                                        .frame(width: 80)

                                        VStack(alignment: .leading, spacing: 2) {
                                            let progress = setProgress(for: set)
                                            Text(set.name)
                                                .font(.subheadline.weight(.medium))
                                                .foregroundStyle(.primary)
                                                .lineLimit(2)
                                            if let total = progress.total, total > 0 {
                                                ProgressView(value: min(Double(progress.collected), Double(total)), total: Double(total))
                                                    .progressViewStyle(.linear)
                                                    .tint(.accentColor)
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
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .task(id: setMarketValueTaskID(for: set)) {
                                    await ensureSetMarketValueLoaded(for: set)
                                }

                                Divider()
                                    .padding(.leading, 124)
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.bottom, 16)
            }
        }
        .task(id: collectionProgressTaskKey) {
            await refreshCollectedCounts()
        }
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

    private func setProgress(for set: TCGSet) -> (collected: Int, total: Int?) {
        let collected = uniqueCollectedCountBySetCode[set.setCode.lowercased()] ?? 0
        return (collected, set.cardCountTotal)
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
        let trimmed = cardID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }

        if trimmed.contains("::") {
            let parts = trimmed.components(separatedBy: "::")
            guard parts.count >= 2 else { return nil }
            let setCode = parts[0].lowercased()
            let cardNumber = parts[1].lowercased()
            guard setCode.isEmpty == false, cardNumber.isEmpty == false else { return nil }
            return (setCode, "\(setCode)::\(cardNumber)")
        }

        guard let separatorIndex = trimmed.firstIndex(of: "-"), separatorIndex > trimmed.startIndex else {
            return nil
        }
        let setCode = String(trimmed[..<separatorIndex]).lowercased()
        return (setCode, trimmed.lowercased())
    }
}

private struct BrowsePokemonTabContent: View {
    @Environment(AppServices.self) private var services
    @Query private var collectionItems: [CollectionItem]

    let query: String
    let onSelectRoute: (BrowseInlineDetailRoute) -> Void

    @State private var rows: [NationalDexPokemon] = []
    @State private var isLoading = true
    @State private var characterRows: [String] = []
    @State private var subtypeRows: [String] = []
    @State private var ownedNationalDexIDs: Set<Int> = []
    @State private var dexCollectionProgress: [Int: (owned: Int, total: Int)] = [:]
    @State private var hideCollectedPokemon = false

    private let pokemonColumnCount = 3

    private var filteredPokemonRows: [NationalDexPokemon] {
        let normalizedQuery = normalizedBrowseSearchText(query)
        var filtered = rows
        if !normalizedQuery.isEmpty {
            filtered = filtered.filter { item in
                normalizedBrowseSearchText(item.name).contains(normalizedQuery)
                    || normalizedBrowseSearchText(item.displayName).contains(normalizedQuery)
                    || normalizedBrowseSearchText(String(item.nationalDexNumber)).contains(normalizedQuery)
            }
        }
        if hideCollectedPokemon {
            filtered = filtered.filter { !ownedNationalDexIDs.contains($0.nationalDexNumber) }
        }
        return filtered
    }

    private var filteredCharacterRows: [String] {
        let normalizedQuery = normalizedBrowseSearchText(query)
        guard !normalizedQuery.isEmpty else { return characterRows }
        return characterRows.filter { normalizedBrowseSearchText($0).contains(normalizedQuery) }
    }

    private var filteredSubtypeRows: [String] {
        let normalizedQuery = normalizedBrowseSearchText(query)
        guard !normalizedQuery.isEmpty else { return subtypeRows }
        return subtypeRows.filter { normalizedBrowseSearchText($0).contains(normalizedQuery) }
    }

    private var ownedDexTaskKey: String {
        let collectionSnapshot = collectionItems
            .filter { $0.quantity > 0 }
            .map { "\($0.cardID)|\($0.quantity)" }
            .sorted()
            .joined(separator: ",")
        let setSnapshot = services.cardData.sets
            .map(\.setCode)
            .sorted()
            .joined(separator: ",")
        return "\(services.brandSettings.selectedCatalogBrand.rawValue)#\(setSnapshot)#\(collectionSnapshot)"
    }

    private var hideCollectedToggleTitle: String {
        let total = rows.count
        let collected = min(ownedNationalDexIDs.count, total)
        return "Hide Collected (\(collected) of \(total) Pokemon collected)"
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView(activeTitle)
                    .frame(maxWidth: .infinity, minHeight: 280)
                    .padding(.horizontal, 16)
            } else if services.brandSettings.selectedCatalogBrand == .pokemon {
                pokemonBody
            } else {
                onePieceBody
            }
        }
        .onAppear {
            scheduleRowLoad(for: services.brandSettings.selectedCatalogBrand)
        }
        .onChange(of: services.brandSettings.selectedCatalogBrand) { _, newBrand in
            scheduleRowLoad(for: newBrand)
        }
        .task(id: ownedDexTaskKey) {
            await refreshOwnedNationalDexIDs()
        }
    }

    @MainActor
    private func scheduleRowLoad(for _: TCGBrand) {
        Task { @MainActor in
            await loadRows()
        }
    }

    private var activeTitle: String {
        services.brandSettings.selectedCatalogBrand == .pokemon ? "Loading Pokémon…" : "Loading characters…"
    }

    @ViewBuilder
    private var pokemonBody: some View {
        if rows.isEmpty {
            ContentUnavailableView(
                "No Pokédex list",
                systemImage: "hare",
                description: Text("Add pokemon.json next to sets.json on your CDN.")
            )
            .frame(maxWidth: .infinity, minHeight: 280)
            .padding(.horizontal, 16)
        } else if filteredPokemonRows.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(hideCollectedToggleTitle, isOn: $hideCollectedPokemon)
                    .font(.caption.weight(.semibold))
                    .toggleStyle(.switch)
                    .padding(.horizontal, 16)

                ContentUnavailableView(
                    "No matching Pokémon",
                    systemImage: "magnifyingglass",
                    description: Text("Try a different name or National Dex number.")
                )
                .frame(maxWidth: .infinity, minHeight: 280)
                .padding(.horizontal, 16)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(hideCollectedToggleTitle, isOn: $hideCollectedPokemon)
                    .font(.caption.weight(.semibold))
                    .toggleStyle(.switch)
                    .padding(.horizontal, 16)

                EagerVGrid(items: filteredPokemonRows, columns: pokemonColumnCount, spacing: 12) { item in
                    Button {
                        onSelectRoute(.dex(dexId: item.nationalDexNumber, displayName: item.displayName))
                    } label: {
                        VStack(spacing: 6) {
                            CachedAsyncImage(
                                url: AppConfiguration.pokemonArtURL(imageFileName: item.imageUrl)
                            ) { img in
                                img.resizable().scaledToFit()
                            } placeholder: {
                                Color.gray.opacity(0.12)
                            }
                            .frame(height: 140)

                            HStack(alignment: .center, spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.displayName)
                                        .font(.caption2)
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    Text("#\(item.nationalDexNumber)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)

                                    Text(dexCollectionSummary(for: item.nationalDexNumber))
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                }

                                Spacer(minLength: 0)

                                if ownedNationalDexIDs.contains(item.nationalDexNumber) {
                                    PokemonOwnedPokeBallBadge()
                                        .frame(width: 18, height: 18)
                                        .accessibilityHidden(true)
                                }
                            }
                        }
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
    }

    @ViewBuilder
    private var onePieceBody: some View {
        if characterRows.isEmpty && subtypeRows.isEmpty {
            ContentUnavailableView(
                "No browse lists",
                systemImage: "list.bullet",
                description: Text("Character names and subtypes will appear here after the ONE PIECE catalog sync completes.")
            )
            .frame(maxWidth: .infinity, minHeight: 280)
            .padding(.horizontal, 16)
        } else if filteredCharacterRows.isEmpty && filteredSubtypeRows.isEmpty {
            ContentUnavailableView(
                "No matches",
                systemImage: "magnifyingglass",
                description: Text("Try a different search term.")
            )
            .frame(maxWidth: .infinity, minHeight: 280)
            .padding(.horizontal, 16)
        } else {
            LazyVStack(alignment: .leading, spacing: 20) {
                if !filteredCharacterRows.isEmpty {
                        listSection(title: "Characters", rows: filteredCharacterRows) { row in
                        Button {
                            onSelectRoute(.onePieceCharacter(row))
                        } label: {
                            browseListRow(title: row)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !filteredSubtypeRows.isEmpty {
                    listSection(title: "Subtypes", rows: filteredSubtypeRows) { row in
                        Button {
                            onSelectRoute(.onePieceSubtype(row))
                        } label: {
                            browseListRow(title: row)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.bottom, 16)
        }
    }

    private func loadRows() async {
        isLoading = true
        defer { isLoading = false }

        if services.brandSettings.selectedCatalogBrand == .pokemon {
            characterRows = []
            subtypeRows = []
            if services.cardData.nationalDexPokemon.isEmpty {
                await services.cardData.loadNationalDexPokemon()
            }
            rows = services.cardData.nationalDexPokemonSorted()
        } else {
            rows = []
            if services.cardData.onePieceCharacterNames.isEmpty || services.cardData.onePieceCharacterSubtypes.isEmpty {
                await services.cardData.loadOnePieceBrowseMetadata()
            }
            characterRows = services.cardData.onePieceCharacterNames
            subtypeRows = services.cardData.onePieceCharacterSubtypes
        }
    }

    @MainActor
    private func refreshOwnedNationalDexIDs() async {
        guard services.brandSettings.selectedCatalogBrand == .pokemon else {
            ownedNationalDexIDs = []
            dexCollectionProgress = [:]
            return
        }

        var allPokemonCards: [Card] = []
        for set in services.cardData.sets {
            allPokemonCards.append(contentsOf: await services.cardData.loadCards(forSetCode: set.setCode))
        }

        var totalByDex: [Int: Int] = [:]
        for card in allPokemonCards {
            guard let dexIDs = card.dexIds else { continue }
            for dexID in Set(dexIDs) {
                totalByDex[dexID, default: 0] += 1
            }
        }

        let ownedCardIDs: Set<String> = Set(collectionItems.compactMap { item in
            guard item.quantity > 0 else { return nil }
            guard TCGBrand.inferredFromMasterCardId(item.cardID) == .pokemon else { return nil }
            return item.cardID
        })

        var nextOwnedDexIDs: Set<Int> = []
        var ownedByDex: [Int: Int] = [:]
        for cardID in ownedCardIDs {
            guard let card = await services.cardData.loadCard(masterCardId: cardID) else { continue }
            guard let dexIDs = card.dexIds else { continue }
            for dexID in Set(dexIDs) {
                nextOwnedDexIDs.insert(dexID)
                ownedByDex[dexID, default: 0] += 1
            }
        }

        var nextDexCollectionProgress: [Int: (owned: Int, total: Int)] = [:]
        for (dexID, total) in totalByDex {
            nextDexCollectionProgress[dexID] = (ownedByDex[dexID] ?? 0, total)
        }

        ownedNationalDexIDs = nextOwnedDexIDs
        dexCollectionProgress = nextDexCollectionProgress
    }

    private func dexCollectionSummary(for dexID: Int) -> String {
        let progress = dexCollectionProgress[dexID] ?? (0, 0)
        return "\(progress.owned) of \(progress.total) collected"
    }

    private func listSection<RowContent: View>(
        title: String,
        rows: [String],
        @ViewBuilder rowBuilder: @escaping (String) -> RowContent
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)

            LazyVStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    rowBuilder(row)
                    Divider()
                        .padding(.leading, 32)
                }
            }
        }
    }

    private func browseListRow(title: String) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
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

            if gridOptions.showSetID {
                Text(card.setCode)
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

private struct PokemonOwnedPokeBallBadge: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white)
                .overlay(Circle().stroke(Color.primary.opacity(0.9), lineWidth: 1.1))

            Circle()
                .trim(from: 0, to: 0.5)
                .fill(Color.red)
                .rotationEffect(.degrees(180))

            Rectangle()
                .fill(Color.primary.opacity(0.9))
                .frame(height: 1.1)

            Circle()
                .fill(Color.white)
                .frame(width: 6.6, height: 6.6)
                .overlay(Circle().stroke(Color.primary.opacity(0.9), lineWidth: 1.0))
        }
    }
}

private struct BrowseGridPriceText: View {
    @Environment(AppServices.self) private var services

    let card: Card
    /// When set, displayed directly without a live lookup (used by collection grid for grade-correct pricing).
    var overridePrice: Double? = nil
    /// When set, shown as a small pill badge next to the price (e.g. "PSA 10", "ACE 10").
    var gradeLabel: String? = nil
    /// When true, render the resolved price in the current theme accent color.
    var usesAccentColor: Bool = false

    /// `nil` until the pricing task finishes; then a single price, a `low - high` range, or an em dash when unknown.
    @State private var priceLine: String?

    var body: some View {
        Group {
            if let priceLine {
                HStack(spacing: 3) {
                    if let gradeLabel {
                        Text(gradeLabel)
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1.5)
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 3))
                    }
                    if usesAccentColor {
                        Text(priceLine)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .foregroundStyle(services.theme.accentColor)
                    } else {
                        Text(priceLine)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .foregroundStyle(.secondary)
                    }
                }
                .multilineTextAlignment(.center)
            } else {
                Text(" ")
                    .font(.caption2.weight(.semibold))
                    .redacted(reason: .placeholder)
            }
        }
        .task(id: taskID) {
            priceLine = nil
            let currency = services.priceDisplay.currency
            let fx = services.pricing.usdToGbp
            if let usd = overridePrice {
                priceLine = currency.format(amountUSD: usd, usdToGbp: fx)
                return
            }
            guard let entry = await services.pricing.pricing(for: card),
                  let range = resolvedMarketPriceRange(entry) else {
                priceLine = "—"
                return
            }
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
        "\(card.id)|\(overridePrice ?? -1)|\(services.priceDisplay.currency.rawValue)|\(services.pricing.usdToGbp)"
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

private func chunkedBrowseCards(_ cards: [Card], columnCount: Int) -> [[Card]] {
    guard columnCount > 0, cards.isEmpty == false else { return [] }
    var rows: [[Card]] = []
    rows.reserveCapacity((cards.count + columnCount - 1) / columnCount)
    var index = 0
    while index < cards.count {
        let end = min(index + columnCount, cards.count)
        rows.append(Array(cards[index..<end]))
        index = end
    }
    return rows
}

private func safeBrowseGridColumnCount(_ count: Int) -> Int {
    min(max(count, 1), 4)
}

// MARK: - Set cards

struct SetCardsView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.presentCard) private var presentCard
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query private var collectionItems: [CollectionItem]
    @Query(sort: \WishlistItem.dateAdded, order: .reverse) private var wishlistItems: [WishlistItem]
    @Query(sort: \CardFolder.createdAt, order: .reverse) private var folders: [CardFolder]
    let set: TCGSet

    @State private var cards: [Card] = []
    @State private var isLoading = true
    @State private var query = ""
    @State private var filters = BrowseCardGridFilters()
    @State private var priceByCardID: [String: Double] = [:]

    // Multi-select
    @State private var isMultiSelectActive = false
    @State private var selectedCardIDs: Set<String> = []
    @State private var multiSelectCollectionPayload: MultiSelectCollectionPayload?
    @State private var showMultiSelectFolderSheet = false
    @State private var wishlistAlertMessage: String?
    @State private var showWishlistAlert = false
    @State private var showWishlistPaywall = false
    @State private var multiSelectFolderNewTitle = ""
    @State private var showFolderCreateAlert = false
    @State private var addedMultiSelectFolderIDs: Set<UUID> = []

    private var ownedCardIDs: Set<String> {
        return Set(collectionItems.compactMap { item in
            let brand = TCGBrand.inferredFromMasterCardId(item.cardID)
            return brand == services.brandSettings.selectedCatalogBrand ? item.cardID : nil
        })
    }

    private var wishlistedCardIDs: Set<String> {
        Set(wishlistItems.compactMap { item in
            let brand = TCGBrand.inferredFromMasterCardId(item.cardID)
            return brand == services.brandSettings.selectedCatalogBrand ? item.cardID : nil
        })
    }

    private var filteredCards: [Card] {
        filterBrowseCards(
            cards,
            query: query,
            filters: filters,
            ownedCardIDs: ownedCardIDs,
            brand: services.brandSettings.selectedCatalogBrand,
            sets: services.cardData.sets,
            priceByCardID: priceByCardID
        )
    }

    private var priceCacheTaskKey: String {
        let ids = cards.map(\.masterCardId).joined(separator: "|")
        return "\(services.brandSettings.selectedCatalogBrand.rawValue)#\(ids)"
    }

    private var selectedCards: [Card] {
        cards.filter { selectedCardIDs.contains($0.masterCardId) }
    }

    private var glassButtonBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04)
    }

    private var glassButtonBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                if isLoading {
                    ProgressView().padding()
                } else {
                    VStack(spacing: 12) {
                        BrowseInlineSearchField(title: "Search cards in set", text: $query)
                            .padding(.horizontal)
                            .padding(.top, 2)
                        if filteredCards.isEmpty {
                            ContentUnavailableView(
                                "No matching cards",
                                systemImage: "magnifyingglass",
                                description: Text("Try a different card name or number.")
                            )
                            .padding(.horizontal)
                            .padding(.bottom)
                        } else {
                            EagerVGrid(items: filteredCards, columns: safeBrowseGridColumnCount(services.browseGridOptions.options.columnCount), spacing: 12) { card in
                                let index = filteredCards.firstIndex(where: { $0.id == card.id }) ?? 0
                                let isSelected = selectedCardIDs.contains(card.masterCardId)
                                Button {
                                    if isMultiSelectActive {
                                        toggleSelection(card)
                                    } else {
                                        presentCard(card, filteredCards)
                                    }
                                } label: {
                                    CardGridCell(
                                        card: card,
                                        gridOptions: services.browseGridOptions.options,
                                        setName: set.name,
                                        isOwned: ownedCardIDs.contains(card.masterCardId),
                                        isWishlisted: wishlistedCardIDs.contains(card.masterCardId)
                                    )
                                    .overlay(alignment: .topTrailing) {
                                        if isMultiSelectActive {
                                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                                .font(.system(size: 22, weight: .semibold))
                                                .foregroundStyle(isSelected ? Color.blue : Color.white)
                                                .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                                                .padding(6)
                                        }
                                    }
                                }
                                .buttonStyle(CardCellButtonStyle())
                                .onAppear {
                                    ImagePrefetcher.shared.prefetchCardWindow(filteredCards, startingAt: index + 1)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.bottom, isMultiSelectActive && !selectedCardIDs.isEmpty ? 88 : 0)
                        }
                    }
                }
            }

            if isMultiSelectActive && !selectedCardIDs.isEmpty {
                multiSelectActionBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isMultiSelectActive && !selectedCardIDs.isEmpty)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top) {
            BrowseDetailNavBar(
                title: set.name,
                isFilterActive: filters.isVisiblyCustomized,
                isGridOptionsActive: !services.browseGridOptions.options.isDefault,
                isMultiSelectActive: isMultiSelectActive,
                onMultiSelectToggle: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        isMultiSelectActive.toggle()
                        if !isMultiSelectActive { selectedCardIDs.removeAll() }
                    }
                }
            ) {
                BrowseGridFiltersMenuContent(
                    brand: services.brandSettings.selectedCatalogBrand,
                    filters: $filters,
                    energyOptions: cardEnergyOptions(cards),
                    rarityOptions: cardRarityOptions(cards),
                    trainerTypeOptions: cardTrainerTypeOptions(cards),
                    config: FilterMenuConfig(showGridOptions: false)
                )
            } gridMenuContent: {
                BrowseGridOptionsMenuContent()
            }
        }
        .sheet(item: $multiSelectCollectionPayload) { payload in
            MultiSelectAddToCollectionSheet(cards: payload.cards)
                .environment(services)
        }
        .sheet(isPresented: $showMultiSelectFolderSheet, onDismiss: { addedMultiSelectFolderIDs.removeAll() }) {
            multiSelectFolderSheet
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
        .task {
            isLoading = true
            let loaded = await services.cardData.loadCards(forSetCode: set.setCode)
            cards = sortCardsByLocalIdHighestFirst(loaded)
            ImagePrefetcher.shared.prefetchCardWindow(cards, startingAt: 0, count: 24)
            isLoading = false
        }
        .task(id: priceCacheTaskKey) {
            await refreshPriceCache()
        }
        .onChange(of: filters.sortBy) { _, sortBy in
            guard sortBy == .price else { return }
            Task { @MainActor in
                await refreshPriceCache()
            }
        }
    }

    private var multiSelectActionBar: some View {
        HStack(spacing: 8) {
            multiSelectActionButton(
                title: "Add to Collection",
                systemImage: "plus.circle.fill",
                tint: Color(red: 0.28, green: 0.84, blue: 0.39)
            ) {
                multiSelectCollectionPayload = MultiSelectCollectionPayload(cards: selectedCards)
            }
            multiSelectActionButton(
                title: "Wish List",
                systemImage: "star",
                tint: Color(red: 0.99, green: 0.72, blue: 0.22)
            ) {
                addSelectedToWishlist()
            }
            multiSelectActionButton(
                title: "Add to Folder",
                systemImage: "folder.badge.plus",
                tint: Color(red: 0.18, green: 0.72, blue: 0.88)
            ) {
                addedMultiSelectFolderIDs.removeAll()
                showMultiSelectFolderSheet = true
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .safeAreaPadding(.bottom, 0)
    }

    private func multiSelectActionButton(title: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(glassButtonBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(glassButtonBorder, lineWidth: 1)
                    )
            }
            .accessibilityLabel(title)
        }
        .buttonStyle(.plain)
    }

    private var multiSelectFolderSheet: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        multiSelectFolderNewTitle = ""
                        showFolderCreateAlert = true
                    } label: {
                        Label("New Folder…", systemImage: "folder.badge.plus")
                            .foregroundStyle(.primary)
                    }
                }
                if !folders.isEmpty {
                    Section("MY FOLDERS") {
                        ForEach(folders) { folder in
                            let alreadyAdded = addedMultiSelectFolderIDs.contains(folder.id)
                            Button {
                                guard !alreadyAdded else { return }
                                addSelectedCards(to: folder)
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
                    Button("Done") { showMultiSelectFolderSheet = false }
                }
            }
            .alert("New Folder", isPresented: $showFolderCreateAlert) {
                TextField("Folder name", text: $multiSelectFolderNewTitle)
                Button("Create") { createFolderAndAddSelected() }
                Button("Cancel", role: .cancel) { multiSelectFolderNewTitle = "" }
            }
        }
    }

    private func toggleSelection(_ card: Card) {
        if selectedCardIDs.contains(card.masterCardId) {
            selectedCardIDs.remove(card.masterCardId)
        } else {
            selectedCardIDs.insert(card.masterCardId)
            HapticManager.impact(.light)
        }
    }

    private func addSelectedToWishlist() {
        guard let wl = services.wishlist else {
            wishlistAlertMessage = "Wishlist isn't available yet. Try again in a moment."
            showWishlistAlert = true
            return
        }
        var addedCount = 0
        for card in selectedCards {
            do {
                try wl.addItem(cardID: card.masterCardId, variantKey: "normal", notes: "")
                addedCount += 1
            } catch let error as WishlistError {
                switch error {
                case .limitReached:
                    showWishlistPaywall = true
                    return
                case .alreadyExists:
                    break
                case .saveFailed:
                    break
                }
            } catch {
                break
            }
        }
        if addedCount > 0 {
            HapticManager.notification(.success)
        }
    }

    private func addSelectedCards(to folder: CardFolder) {
        for card in selectedCards {
            let alreadyIn = (folder.items ?? []).contains { $0.cardID == card.masterCardId && $0.variantKey == "normal" }
            guard !alreadyIn else { continue }
            let item = CardFolderItem(cardID: card.masterCardId, variantKey: "normal")
            item.folder = folder
            modelContext.insert(item)
        }
        try? modelContext.save()
        addedMultiSelectFolderIDs.insert(folder.id)
        HapticManager.notification(.success)
    }

    private func createFolderAndAddSelected() {
        let title = multiSelectFolderNewTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let folder = CardFolder(title: title)
        modelContext.insert(folder)
        for card in selectedCards {
            let item = CardFolderItem(cardID: card.masterCardId, variantKey: "normal")
            item.folder = folder
            modelContext.insert(item)
        }
        try? modelContext.save()
        addedMultiSelectFolderIDs.insert(folder.id)
        multiSelectFolderNewTitle = ""
        HapticManager.notification(.success)
    }

    @MainActor
    private func refreshPriceCache() async {
        var next: [String: Double] = [:]
        next.reserveCapacity(cards.count)
        for card in cards {
            guard let entry = await services.pricing.pricing(for: card),
                  let usd = browseMarketPriceUSD(for: entry) else { continue }
            next[card.masterCardId] = usd
        }
        priceByCardID = next
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
    @Query private var collectionItems: [CollectionItem]
    @Query(sort: \WishlistItem.dateAdded, order: .reverse) private var wishlistItems: [WishlistItem]
    let dexId: Int
    let displayName: String

    @State private var cards: [Card] = []
    @State private var isLoading = true
    @State private var query = ""
    @State private var filters = BrowseCardGridFilters()
    @State private var priceByCardID: [String: Double] = [:]

    private var setNameByCode: [String: String] {
        firstValueMap(services.cardData.sets, key: \.setCode, value: \.name)
    }

    private var ownedCardIDs: Set<String> {
        return Set(collectionItems.compactMap { item in
            let brand = TCGBrand.inferredFromMasterCardId(item.cardID)
            return brand == services.brandSettings.selectedCatalogBrand ? item.cardID : nil
        })
    }

    private var wishlistedCardIDs: Set<String> {
        Set(wishlistItems.compactMap { item in
            let brand = TCGBrand.inferredFromMasterCardId(item.cardID)
            return brand == services.brandSettings.selectedCatalogBrand ? item.cardID : nil
        })
    }

    private var filteredCards: [Card] {
        filterBrowseCards(
            cards,
            query: query,
            filters: filters,
            ownedCardIDs: ownedCardIDs,
            brand: services.brandSettings.selectedCatalogBrand,
            sets: services.cardData.sets,
            priceByCardID: priceByCardID
        )
    }

    private var priceCacheTaskKey: String {
        let ids = cards.map(\.masterCardId).joined(separator: "|")
        return "\(services.brandSettings.selectedCatalogBrand.rawValue)#\(ids)"
    }

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView().padding()
            } else {
                VStack(spacing: 12) {
                    BrowseInlineSearchField(title: "Search cards for Pokémon", text: $query)
                        .padding(.horizontal)
                        .padding(.top, 2)
                    if filteredCards.isEmpty {
                        ContentUnavailableView(
                            "No matching cards",
                            systemImage: "magnifyingglass",
                            description: Text("Try a different card name or number.")
                        )
                        .padding(.horizontal)
                        .padding(.bottom)
                    } else {
                        EagerVGrid(items: filteredCards, columns: safeBrowseGridColumnCount(services.browseGridOptions.options.columnCount), spacing: 12) { card in
                            let index = filteredCards.firstIndex(where: { $0.id == card.id }) ?? 0
                            Button {
                                presentCard(card, filteredCards)
                            } label: {
                                CardGridCell(
                                    card: card,
                                    gridOptions: services.browseGridOptions.options,
                                    setName: setNameByCode[card.setCode],
                                    isOwned: ownedCardIDs.contains(card.masterCardId),
                                    isWishlisted: wishlistedCardIDs.contains(card.masterCardId)
                                )
                            }
                            .buttonStyle(CardCellButtonStyle())
                            .onAppear {
                                ImagePrefetcher.shared.prefetchCardWindow(filteredCards, startingAt: index + 1)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom)
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top) {
            BrowseDetailNavBar(
                title: displayName,
                isFilterActive: filters.isVisiblyCustomized,
                isGridOptionsActive: !services.browseGridOptions.options.isDefault
            ) {
                BrowseGridFiltersMenuContent(
                    brand: services.brandSettings.selectedCatalogBrand,
                    filters: $filters,
                    energyOptions: cardEnergyOptions(cards),
                    rarityOptions: cardRarityOptions(cards),
                    trainerTypeOptions: cardTrainerTypeOptions(cards),
                    config: FilterMenuConfig(showGridOptions: false)
                )
            } gridMenuContent: {
                BrowseGridOptionsMenuContent()
            }
        }
        .task {
            isLoading = true
            cards = await services.cardData.cards(matchingNationalDex: dexId)
            ImagePrefetcher.shared.prefetchCardWindow(cards, startingAt: 0, count: 24)
            isLoading = false
        }
        .task(id: priceCacheTaskKey) {
            await refreshPriceCache()
        }
        .onChange(of: filters.sortBy) { _, sortBy in
            guard sortBy == .price else { return }
            Task { @MainActor in
                await refreshPriceCache()
            }
        }
    }

    @MainActor
    private func refreshPriceCache() async {
        var next: [String: Double] = [:]
        next.reserveCapacity(cards.count)
        for card in cards {
            guard let entry = await services.pricing.pricing(for: card),
                  let usd = browseMarketPriceUSD(for: entry) else { continue }
            next[card.masterCardId] = usd
        }
        priceByCardID = next
    }
}

// MARK: - ONE PIECE browse detail

struct OnePieceCharacterCardsView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.presentCard) private var presentCard
    @Query private var collectionItems: [CollectionItem]
    @Query(sort: \WishlistItem.dateAdded, order: .reverse) private var wishlistItems: [WishlistItem]

    let characterName: String

    @State private var cards: [Card] = []
    @State private var isLoading = true
    @State private var query = ""
    @State private var filters = BrowseCardGridFilters()

    private var setNameByCode: [String: String] {
        firstValueMap(services.cardData.sets, key: \.setCode, value: \.name)
    }

    private var ownedCardIDs: Set<String> {
        return Set(collectionItems.compactMap { item in
            let brand = TCGBrand.inferredFromMasterCardId(item.cardID)
            return brand == services.brandSettings.selectedCatalogBrand ? item.cardID : nil
        })
    }

    private var wishlistedCardIDs: Set<String> {
        Set(wishlistItems.compactMap { item in
            let brand = TCGBrand.inferredFromMasterCardId(item.cardID)
            return brand == services.brandSettings.selectedCatalogBrand ? item.cardID : nil
        })
    }

    private var filteredCards: [Card] {
        filterBrowseCards(
            cards,
            query: query,
            filters: filters,
            ownedCardIDs: ownedCardIDs,
            brand: services.brandSettings.selectedCatalogBrand,
            sets: services.cardData.sets
        )
    }

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView().padding()
            } else {
                VStack(spacing: 12) {
                    BrowseInlineSearchField(title: "Search cards for character", text: $query)
                        .padding(.horizontal)
                        .padding(.top, 2)
                    if filteredCards.isEmpty {
                        ContentUnavailableView(
                            "No matching cards",
                            systemImage: "person.text.rectangle",
                            description: Text(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No ONE PIECE cards matched \(characterName)." : "Try a different card name or number.")
                        )
                        .padding(.horizontal)
                        .padding(.bottom)
                    } else {
                        EagerVGrid(items: filteredCards, columns: safeBrowseGridColumnCount(services.browseGridOptions.options.columnCount), spacing: 12) { card in
                            let index = filteredCards.firstIndex(where: { $0.id == card.id }) ?? 0
                            Button {
                                presentCard(card, filteredCards)
                            } label: {
                                CardGridCell(
                                    card: card,
                                    gridOptions: services.browseGridOptions.options,
                                    setName: setNameByCode[card.setCode],
                                    isOwned: ownedCardIDs.contains(card.masterCardId),
                                    isWishlisted: wishlistedCardIDs.contains(card.masterCardId)
                                )
                            }
                            .buttonStyle(CardCellButtonStyle())
                            .onAppear {
                                ImagePrefetcher.shared.prefetchCardWindow(filteredCards, startingAt: index + 1)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom)
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top) {
            BrowseDetailNavBar(
                title: characterName,
                isFilterActive: filters.isVisiblyCustomized,
                isGridOptionsActive: !services.browseGridOptions.options.isDefault
            ) {
                BrowseGridFiltersMenuContent(
                    brand: services.brandSettings.selectedCatalogBrand,
                    filters: $filters,
                    energyOptions: cardEnergyOptions(cards),
                    rarityOptions: cardRarityOptions(cards),
                    trainerTypeOptions: cardTrainerTypeOptions(cards),
                    config: FilterMenuConfig(showGridOptions: false)
                )
            } gridMenuContent: {
                BrowseGridOptionsMenuContent()
            }
        }
        .task(id: characterName) {
            isLoading = true
            cards = await services.cardData.cards(matchingOnePieceCharacterName: characterName)
            ImagePrefetcher.shared.prefetchCardWindow(cards, startingAt: 0, count: 24)
            isLoading = false
        }
    }
}

struct OnePieceSubtypeCardsView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.presentCard) private var presentCard
    @Query private var collectionItems: [CollectionItem]
    @Query(sort: \WishlistItem.dateAdded, order: .reverse) private var wishlistItems: [WishlistItem]

    let subtypeName: String

    @State private var cards: [Card] = []
    @State private var isLoading = true
    @State private var query = ""
    @State private var filters = BrowseCardGridFilters()

    private var setNameByCode: [String: String] {
        firstValueMap(services.cardData.sets, key: \.setCode, value: \.name)
    }

    private var ownedCardIDs: Set<String> {
        return Set(collectionItems.compactMap { item in
            let brand = TCGBrand.inferredFromMasterCardId(item.cardID)
            return brand == services.brandSettings.selectedCatalogBrand ? item.cardID : nil
        })
    }

    private var wishlistedCardIDs: Set<String> {
        Set(wishlistItems.compactMap { item in
            let brand = TCGBrand.inferredFromMasterCardId(item.cardID)
            return brand == services.brandSettings.selectedCatalogBrand ? item.cardID : nil
        })
    }

    private var filteredCards: [Card] {
        filterBrowseCards(
            cards,
            query: query,
            filters: filters,
            ownedCardIDs: ownedCardIDs,
            brand: services.brandSettings.selectedCatalogBrand,
            sets: services.cardData.sets
        )
    }

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView().padding()
            } else {
                VStack(spacing: 12) {
                    BrowseInlineSearchField(title: "Search cards for subtype", text: $query)
                        .padding(.horizontal)
                        .padding(.top, 2)
                    if filteredCards.isEmpty {
                        ContentUnavailableView(
                            "No matching cards",
                            systemImage: "line.3.horizontal.decrease.circle",
                            description: Text(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No ONE PIECE cards matched \(subtypeName)." : "Try a different card name or number.")
                        )
                        .padding(.horizontal)
                        .padding(.bottom)
                    } else {
                        EagerVGrid(items: filteredCards, columns: safeBrowseGridColumnCount(services.browseGridOptions.options.columnCount), spacing: 12) { card in
                            let index = filteredCards.firstIndex(where: { $0.id == card.id }) ?? 0
                            Button {
                                presentCard(card, filteredCards)
                            } label: {
                                CardGridCell(
                                    card: card,
                                    gridOptions: services.browseGridOptions.options,
                                    setName: setNameByCode[card.setCode],
                                    isOwned: ownedCardIDs.contains(card.masterCardId),
                                    isWishlisted: wishlistedCardIDs.contains(card.masterCardId)
                                )
                            }
                            .buttonStyle(CardCellButtonStyle())
                            .onAppear {
                                ImagePrefetcher.shared.prefetchCardWindow(filteredCards, startingAt: index + 1)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom)
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top) {
            BrowseDetailNavBar(
                title: subtypeName,
                isFilterActive: filters.isVisiblyCustomized,
                isGridOptionsActive: !services.browseGridOptions.options.isDefault
            ) {
                BrowseGridFiltersMenuContent(
                    brand: services.brandSettings.selectedCatalogBrand,
                    filters: $filters,
                    energyOptions: cardEnergyOptions(cards),
                    rarityOptions: cardRarityOptions(cards),
                    trainerTypeOptions: cardTrainerTypeOptions(cards),
                    config: FilterMenuConfig(showGridOptions: false)
                )
            } gridMenuContent: {
                BrowseGridOptionsMenuContent()
            }
        }
        .task(id: subtypeName) {
            isLoading = true
            cards = await services.cardData.cards(matchingOnePieceSubtype: subtypeName)
            ImagePrefetcher.shared.prefetchCardWindow(cards, startingAt: 0, count: 24)
            isLoading = false
        }
    }
}

private struct BrowseDetailNavBar<FilterMenuContent: View, GridMenuContent: View>: View {
    let title: String
    let isFilterActive: Bool
    let isGridOptionsActive: Bool
    var isMultiSelectActive: Bool = false
    var onMultiSelectToggle: (() -> Void)? = nil
    @ViewBuilder let filterMenuContent: () -> FilterMenuContent
    @ViewBuilder let gridMenuContent: () -> GridMenuContent
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Text(title)
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 64)

            HStack {
                ChromeGlassCircleButton(accessibilityLabel: "Back") { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.primary)
                }

                Spacer(minLength: 0)

                HStack(spacing: 10) {
                    if let onMultiSelectToggle {
                        Button {
                            onMultiSelectToggle()
                        } label: {
                            Image(systemName: isMultiSelectActive ? "checkmark.circle.fill" : "checkmark.circle")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(isMultiSelectActive ? Color.blue : Color.primary)
                                .modifier(ChromeGlassCircleGlyphModifier())
                        }
                        .buttonStyle(.plain)
                        .frame(width: 48, height: 48)
                        .contentShape(Rectangle())
                        .accessibilityLabel(isMultiSelectActive ? "Exit multi-select" : "Multi-select")
                    }

                    Menu {
                        gridMenuContent()
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.primary)
                            .modifier(ChromeGlassCircleGlyphModifier())
                    }
                    .buttonStyle(.plain)
                    .menuActionDismissBehavior(.disabled)
                    .menuOrder(.fixed)
                    .menuIndicator(.hidden)
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Grid options")

                    Menu {
                        filterMenuContent()
                    } label: {
                        Image(systemName: isFilterActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.primary)
                            .modifier(ChromeGlassCircleGlyphModifier())
                    }
                    .buttonStyle(.plain)
                    .menuActionDismissBehavior(.disabled)
                    .menuOrder(.fixed)
                    .menuIndicator(.hidden)
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Filters")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

struct BrowseFilterToolbarButton: View {
    let isActive: Bool

    var body: some View {
        Image(systemName: isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(isActive ? Color.blue : Color.primary)
            .modifier(ChromeGlassCircleGlyphModifier())
            .frame(width: 48, height: 48)
            .contentShape(Rectangle())
    }
}

struct FilterMenuConfig {
    var showSortBy: Bool = true
    var showAcquiredDateSort: Bool = false
    var showRandomSort: Bool = true
    var showCardNumberSort: Bool = true
    var showBrandFilters: Bool = true
    var showRarity: Bool = true
    var showRarePlusOnly: Bool = true
    var showHideOwned: Bool = true
    var showShowDuplicates: Bool = false
    var showGridOptions: Bool = true
    var defaultSortBy: BrowseCardGridSortOption = .random
    var gridNameToggleTitle: String = "Show card name"
    var showGridCardIDToggle: Bool = true
    var showGridColumns: Bool = true
    var showGridOwnedToggle: Bool = true
    var showSealedProductTypeFilter: Bool = false

    static let browse = FilterMenuConfig()
    static let collect = FilterMenuConfig(
        showAcquiredDateSort: true,
        showRandomSort: false,
        showCardNumberSort: false,
        showHideOwned: false,
        showShowDuplicates: true,
        defaultSortBy: .price
    )
}

struct BrowseGridFiltersMenuContent: View {
    @Environment(AppServices.self) private var services

    let brand: TCGBrand
    @Binding var filters: BrowseCardGridFilters
    let energyOptions: [String]
    let rarityOptions: [String]
    let trainerTypeOptions: [String]
    var isAllBrands: Bool = false
    /// When nil, falls back to `services.browseGridOptions` (browse behaviour). Pass a binding to use separate grid options.
    var gridOptions: Binding<BrowseGridOptions>? = nil
    var config: FilterMenuConfig = .browse

    var body: some View {
        if filters.isVisiblyCustomized || filters.sortBy != config.defaultSortBy {
            Section {
                Button("Reset filters", role: .destructive) {
                    filters = BrowseCardGridFilters()
                    filters.sortBy = config.defaultSortBy
                }
            }
        }

        Section("Sort by") {
            Menu(menuTitle("Sort by", summary: filters.sortBy.title)) {
                Picker("Sort by", selection: $filters.sortBy) {
                    ForEach(BrowseCardGridSortOption.allCases.filter {
                        ($0 != .acquiredDateNewest || config.showAcquiredDateSort)
                            && ($0 != .random || config.showRandomSort)
                            && ($0 != .cardNumber || config.showCardNumberSort)
                    }) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            .menuActionDismissBehavior(.disabled)
            .menuOrder(.fixed)
        }

        if !isAllBrands && config.showBrandFilters {
        Section("Filters") {
            if brand == .onePiece {
                filterMenu(title: "Card type", summary: selectionSummary(for: filters.opCardTypes)) {
                    ForEach(opCardTypeAllOptions, id: \.self) { cardType in
                        Toggle(cardType, isOn: stringBinding(for: cardType, keyPath: \.opCardTypes))
                    }
                }

                filterMenu(title: "Attribute", summary: selectionSummary(for: filters.opAttributes)) {
                    ForEach(opAttributeAllOptions, id: \.self) { attr in
                        Toggle(attr, isOn: stringBinding(for: attr, keyPath: \.opAttributes))
                    }
                }

                filterMenu(
                    title: "Stats",
                    summary: combinedSelectionSummary(
                        ("Cost", filters.opCosts.count),
                        ("Counter", filters.opCounters.count),
                        ("Life", filters.opLives.count),
                        ("Power", filters.opPowers.count)
                    )
                ) {
                    filterMenu(title: "Cost", summary: selectionSummary(for: filters.opCosts)) {
                        ForEach(opCostAllOptions, id: \.self) { cost in
                            Toggle("\(cost)", isOn: intBinding(for: cost, keyPath: \.opCosts))
                        }
                    }
                    filterMenu(title: "Counter", summary: selectionSummary(for: filters.opCounters)) {
                        ForEach(opCounterAllOptions, id: \.self) { counter in
                            Toggle("\(counter)", isOn: intBinding(for: counter, keyPath: \.opCounters))
                        }
                    }
                    filterMenu(title: "Life", summary: selectionSummary(for: filters.opLives)) {
                        ForEach(opLifeAllOptions, id: \.self) { life in
                            Toggle("\(life)", isOn: intBinding(for: life, keyPath: \.opLives))
                        }
                    }
                    filterMenu(title: "Power", summary: selectionSummary(for: filters.opPowers)) {
                        ForEach(opPowerAllOptions, id: \.self) { power in
                            Toggle("\(power)", isOn: intBinding(for: power, keyPath: \.opPowers))
                        }
                    }
                }
            } else {
                filterMenu(title: "Card type", summary: selectionSummary(for: filters.cardTypes)) {
                    ForEach(BrowseCardTypeFilter.pokemonOptions) { type in
                        Toggle(type.title, isOn: cardTypeBinding(for: type))
                    }
                }
                filterMenu(title: "Legal", summary: selectionSummary(for: filters.legalities)) {
                    ForEach(BrowseCardLegalityFilter.allCases) { legality in
                        Toggle(legality.title, isOn: legalityBinding(for: legality))
                    }
                }
            }

            filterMenu(title: brand.energyFilterMenuTitle, summary: selectionSummary(for: filters.energyTypes)) {
                if energyOptions.isEmpty {
                    Text("No options available")
                } else {
                    ForEach(energyOptions, id: \.self) { energy in
                        Toggle(energy, isOn: stringBinding(for: energy, keyPath: \.energyTypes))
                    }
                }
            }

            if brand == .pokemon {
                filterMenu(title: "Trainer type", summary: selectionSummary(for: filters.trainerTypes)) {
                    if trainerTypeOptions.isEmpty {
                        Text("No trainer types available")
                    } else {
                        ForEach(trainerTypeOptions, id: \.self) { trainerType in
                            Toggle(trainerType, isOn: stringBinding(for: trainerType, keyPath: \.trainerTypes))
                        }
                    }
                }
            }

            if config.showSealedProductTypeFilter {
                filterMenu(title: "Product type", summary: selectionSummary(for: filters.sealedProductTypes)) {
                    ForEach(sealedProductTypeFilterOptions) { option in
                        Toggle(option.title, isOn: stringBinding(for: option.id, keyPath: \.sealedProductTypes))
                    }
                }
            }
        }

        if config.showRarity || config.showRarePlusOnly || config.showHideOwned || config.showShowDuplicates {
            Section("Collection") {
                if config.showRarity {
                    filterMenu(title: "Rarity", summary: selectionSummary(for: filters.rarities)) {
                        if rarityOptions.isEmpty {
                            Text("No rarities available")
                        } else {
                            ForEach(rarityOptions, id: \.self) { rarity in
                                Toggle(rarity, isOn: stringBinding(for: rarity, keyPath: \.rarities))
                            }
                        }
                    }
                }
                if config.showRarePlusOnly {
                    Toggle("Rare + only", isOn: $filters.rarePlusOnly)
                }
                if config.showHideOwned {
                    Toggle("Hide owned", isOn: $filters.hideOwned)
                }
                if config.showShowDuplicates {
                    Toggle("Show duplicates", isOn: $filters.showDuplicates)
                }
            }
        }
        } // end if !isAllBrands && showBrandFilters

        if config.showSealedProductTypeFilter && (!isAllBrands && config.showBrandFilters) == false {
            Section("Filters") {
                filterMenu(title: "Product type", summary: selectionSummary(for: filters.sealedProductTypes)) {
                    ForEach(sealedProductTypeFilterOptions) { option in
                        Toggle(option.title, isOn: stringBinding(for: option.id, keyPath: \.sealedProductTypes))
                    }
                }
            }
        }

        if config.showGridOptions {
            Section("Grid options") {
                BrowseGridOptionsMenuContent(
                    gridOptions: gridOptions,
                    nameToggleTitle: config.gridNameToggleTitle,
                    showCardIDToggle: config.showGridCardIDToggle,
                    showColumns: config.showGridColumns,
                    showOwnedToggle: config.showGridOwnedToggle
                )
            }
        }
    }

    @ViewBuilder
    private func filterMenu<Content: View>(title: String, summary: String?, @ViewBuilder content: () -> Content) -> some View {
        Menu(menuTitle(title, summary: summary)) {
            content()
        }
        .menuActionDismissBehavior(.disabled)
        .menuOrder(.fixed)
    }

    private func cardTypeBinding(for type: BrowseCardTypeFilter) -> Binding<Bool> {
        Binding(
            get: { filters.cardTypes.contains(type) },
            set: { isOn in
                if isOn { filters.cardTypes.insert(type) }
                else { filters.cardTypes.remove(type) }
            }
        )
    }

    private func legalityBinding(for legality: BrowseCardLegalityFilter) -> Binding<Bool> {
        Binding(
            get: { filters.legalities.contains(legality) },
            set: { isOn in
                if isOn { filters.legalities.insert(legality) }
                else { filters.legalities.remove(legality) }
            }
        )
    }

    private func stringBinding(for value: String, keyPath: WritableKeyPath<BrowseCardGridFilters, Set<String>>) -> Binding<Bool> {
        Binding(
            get: { filters[keyPath: keyPath].contains(value) },
            set: { isOn in
                if isOn { filters[keyPath: keyPath].insert(value) }
                else { filters[keyPath: keyPath].remove(value) }
            }
        )
    }

    private func intBinding(for value: Int, keyPath: WritableKeyPath<BrowseCardGridFilters, Set<Int>>) -> Binding<Bool> {
        Binding(
            get: { filters[keyPath: keyPath].contains(value) },
            set: { isOn in
                if isOn { filters[keyPath: keyPath].insert(value) }
                else { filters[keyPath: keyPath].remove(value) }
            }
        )
    }

    private func gridOptionBinding<T>(_ keyPath: WritableKeyPath<BrowseGridOptions, T>) -> Binding<T> {
        if let gridOptions {
            return Binding(
                get: { gridOptions.wrappedValue[keyPath: keyPath] },
                set: { newValue in
                    var updated = gridOptions.wrappedValue
                    updated[keyPath: keyPath] = newValue
                    gridOptions.wrappedValue = updated
                }
            )
        }
        return Binding(
            get: { services.browseGridOptions.options[keyPath: keyPath] },
            set: { newValue in
                var updated = services.browseGridOptions.options
                updated[keyPath: keyPath] = newValue
                services.browseGridOptions.options = updated
            }
        )
    }

    private func menuTitle(_ title: String, summary: String?) -> String {
        guard let summary, !summary.isEmpty else { return title }
        return "\(title) (\(summary))"
    }

    private func selectionSummary<T>(for values: Set<T>) -> String? {
        guard !values.isEmpty else { return nil }
        return values.count == 1 ? "1 selected" : "\(values.count) selected"
    }

    private func combinedSelectionSummary(_ groups: (String, Int)...) -> String? {
        let active = groups.filter { $0.1 > 0 }
        guard !active.isEmpty else { return nil }
        return active.map { "\($0.0) \($0.1)" }.joined(separator: ", ")
    }
}

struct BrowseGridOptionsMenuContent: View {
    @Environment(AppServices.self) private var services

    /// When nil, falls back to `services.browseGridOptions` (browse behaviour). Pass a binding to use separate grid options.
    var gridOptions: Binding<BrowseGridOptions>? = nil
    var nameToggleTitle: String = "Show card name"
    var showCardIDToggle: Bool = true
    var showColumns: Bool = true
    var showOwnedToggle: Bool = true

    var body: some View {
        Toggle(nameToggleTitle, isOn: gridOptionBinding(\.showCardName))
        Toggle("Show set name", isOn: gridOptionBinding(\.showSetName))
        if showCardIDToggle {
            Toggle("Show card ID", isOn: gridOptionBinding(\.showSetID))
        }
        if showOwnedToggle, gridOptions != nil {
            Toggle("Owned", isOn: gridOptionBinding(\.showOwned))
        }
        Toggle("Show pricing", isOn: gridOptionBinding(\.showPricing))
        if showColumns {
            Stepper(value: gridOptionBinding(\.columnCount), in: 1...4) {
                let count = gridOptions?.wrappedValue.columnCount ?? services.browseGridOptions.options.columnCount
                Text("Columns: \(count)")
            }
            .tint(.primary)
        }
    }

    private func gridOptionBinding<T>(_ keyPath: WritableKeyPath<BrowseGridOptions, T>) -> Binding<T> {
        if let gridOptions {
            return Binding(
                get: { gridOptions.wrappedValue[keyPath: keyPath] },
                set: { newValue in
                    var updated = gridOptions.wrappedValue
                    updated[keyPath: keyPath] = newValue
                    gridOptions.wrappedValue = updated
                }
            )
        }
        return Binding(
            get: { services.browseGridOptions.options[keyPath: keyPath] },
            set: { newValue in
                var updated = services.browseGridOptions.options
                updated[keyPath: keyPath] = newValue
                services.browseGridOptions.options = updated
            }
        )
    }
}

func cardEnergyOptions(_ cards: [Card]) -> [String] {
    var values = Set<String>()
    for card in cards {
        if let energyType = card.energyType?.trimmingCharacters(in: .whitespacesAndNewlines), !energyType.isEmpty {
            values.insert(energyType)
        }
        for type in card.elementTypes ?? [] {
            let trimmed = type.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                values.insert(trimmed)
            }
        }
    }
    return values.sorted()
}

func cardRarityOptions(_ cards: [Card]) -> [String] {
    Set(cards.compactMap { $0.rarity?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }).sorted()
}

func cardTrainerTypeOptions(_ cards: [Card]) -> [String] {
    Set(cards.compactMap { $0.trainerType?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }).sorted()
}

func browseFilterEnergyOptions(_ cards: [BrowseFilterCard]) -> [String] {
    var values = Set<String>()
    for card in cards {
        if let energyType = card.energyType?.trimmingCharacters(in: .whitespacesAndNewlines), !energyType.isEmpty {
            values.insert(energyType)
        }
        for type in card.elementTypes ?? [] {
            let trimmed = type.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                values.insert(trimmed)
            }
        }
    }
    return values.sorted()
}

func browseFilterRarityOptions(_ cards: [BrowseFilterCard]) -> [String] {
    Set(cards.compactMap { $0.rarity?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }).sorted()
}

func browseFilterTrainerTypeOptions(_ cards: [BrowseFilterCard]) -> [String] {
    Set(cards.compactMap { $0.trainerType?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }).sorted()
}

private func browseMarketPriceUSD(for entry: CardPricingEntry?) -> Double? {
    guard let entry else { return nil }
    if let scrydex = entry.scrydex, !scrydex.isEmpty {
        return scrydex.values.compactMap { $0.marketEstimateUSD() }.max()
    }
    return entry.tcgplayerMarketEstimateUSD()
}

private func isCommonOrUncommon(_ rarity: String?) -> Bool {
    let normalized = rarity?.lowercased() ?? ""
    return normalized.contains("common") || normalized.contains("uncommon")
}

func filterBrowseCards(
    _ cards: [Card],
    query: String,
    filters: BrowseCardGridFilters,
    ownedCardIDs: Set<String>,
    brand: TCGBrand,
    sets: [TCGSet] = [],
    priceByCardID: [String: Double] = [:]
) -> [Card] {
    let normalizedQuery = normalizedBrowseSearchText(query)
    let setReleaseDateByCode = firstValueMap(sets, key: \.setCode) { $0.releaseDate ?? "" }
    let filtered = cards.filter { card in
        let matchesQuery = normalizedQuery.isEmpty
            || normalizedBrowseSearchText(card.cardName).contains(normalizedQuery)
            || normalizedBrowseSearchText(card.cardNumber).contains(normalizedQuery)
            || normalizedBrowseSearchText(card.setCode).contains(normalizedQuery)
            || normalizedBrowseSearchText(card.subtype).contains(normalizedQuery)
            || (card.subtypes?.contains { normalizedBrowseSearchText($0).contains(normalizedQuery) } == true)
        guard matchesQuery else { return false }

        if brand == .pokemon,
           filters.cardTypes.isEmpty == false,
           filters.cardTypes.contains(resolvedBrowseCardType(for: card, brand: brand)) == false {
            return false
        }
        if filters.rarePlusOnly && isCommonOrUncommon(card.rarity) {
            return false
        }
        if filters.hideOwned && ownedCardIDs.contains(card.masterCardId) {
            return false
        }
        if brand == .pokemon,
           filters.legalities.isEmpty == false,
           pokemonCardMatchesLegalityFilters(
                selectedLegalityFilters: filters.legalities,
                setCode: card.setCode,
                releaseDate: setReleaseDateByCode[card.setCode],
                category: card.category,
                energyType: card.energyType,
                regulationMark: card.regulationMark,
                cardName: card.cardName
           ) == false {
            return false
        }
        if filters.energyTypes.isEmpty == false {
            let energies = Set(cardEnergyOptions([card]))
            if energies.isDisjoint(with: filters.energyTypes) {
                return false
            }
        }
        if filters.rarities.isEmpty == false {
            let rarity = card.rarity?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if rarity.isEmpty || filters.rarities.contains(rarity) == false {
                return false
            }
        }
        if filters.trainerTypes.isEmpty == false {
            let trainerType = card.trainerType?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
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
            let power = card.hp
            guard let power, filters.opPowers.contains(power) else { return false }
        }
        return true
    }

    switch filters.sortBy {
    case .cardName:
        return filtered.sorted { $0.cardName.localizedCaseInsensitiveCompare($1.cardName) == .orderedAscending }
    case .newestSet:
        return sortCardsByReleaseDateNewestFirst(filtered, sets: sets)
    case .cardNumber:
        return filtered.sorted { lhs, rhs in
            if lhs.setCode != rhs.setCode {
                let lhsDate = setReleaseDateByCode[lhs.setCode] ?? ""
                let rhsDate = setReleaseDateByCode[rhs.setCode] ?? ""
                if lhsDate != rhsDate { return lhsDate > rhsDate }
                return lhs.setCode.localizedStandardCompare(rhs.setCode) == .orderedAscending
            }
            return lhs.cardNumber.localizedStandardCompare(rhs.cardNumber) == .orderedAscending
        }
    case .random:
        return filtered.shuffled()
    case .price:
        return filtered.sorted { lhs, rhs in
            let lhsPrice = priceByCardID[lhs.masterCardId]
            let rhsPrice = priceByCardID[rhs.masterCardId]
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
            if lhs.cardName != rhs.cardName {
                return lhs.cardName.localizedCaseInsensitiveCompare(rhs.cardName) == .orderedAscending
            }
            if lhs.setCode != rhs.setCode {
                let lhsDate = setReleaseDateByCode[lhs.setCode] ?? ""
                let rhsDate = setReleaseDateByCode[rhs.setCode] ?? ""
                if lhsDate != rhsDate { return lhsDate > rhsDate }
                return lhs.setCode.localizedStandardCompare(rhs.setCode) == .orderedAscending
            }
            return lhs.cardNumber.localizedStandardCompare(rhs.cardNumber) == .orderedAscending
        }
    case .acquiredDateNewest:
        return filtered
    }
}

private func normalizedBrowseSearchText(_ value: String?) -> String {
    guard let value else { return "" }
    let scalars = value.lowercased().unicodeScalars.compactMap { scalar -> Character? in
        if CharacterSet.alphanumerics.contains(scalar) || CharacterSet.whitespacesAndNewlines.contains(scalar) {
            return Character(scalar)
        }
        return nil
    }
    return String(scalars)
        .split(whereSeparator: \.isWhitespace)
        .joined(separator: " ")
}

private func resolvedBrowseCardType(for card: Card, brand: TCGBrand) -> BrowseCardTypeFilter {
    let category = card.category?.lowercased() ?? ""
    if category.contains("trainer") || card.trainerType != nil {
        return .trainer
    }
    if category.contains("energy") || card.energyType != nil {
        return .energy
    }
    if brand == .onePiece, category.contains("event") {
        return .trainer
    }
    return .pokemon
}

private func pokemonCardMatchesLegalityFilters(
    selectedLegalityFilters: Set<BrowseCardLegalityFilter>,
    setCode: String,
    releaseDate: String?,
    category: String?,
    energyType: String?,
    regulationMark: String?,
    cardName: String
) -> Bool {
    selectedLegalityFilters.contains { legality in
        pokemonCardIsLegalInDeckFormat(
            legality.deckFormat,
            setCode: setCode,
            releaseDate: releaseDate,
            category: category,
            energyType: energyType,
            regulationMark: regulationMark,
            cardName: cardName
        )
    }
}

private func pokemonCardIsLegalInDeckFormat(
    _ format: DeckFormat,
    setCode: String,
    releaseDate: String?,
    category: String?,
    energyType: String?,
    regulationMark: String?,
    cardName: String
) -> Bool {
    if let legalSets = format.legalSetKeys, legalSets.contains(setCode) == false {
        return false
    }
    if format == .pokemonStandard,
       pokemonSetIsTournamentLegal(releaseDate: releaseDate) == false {
        return false
    }
    if let legalMarks = format.legalRegulationMarks {
        let trimmedMark = regulationMark?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmedMark.isEmpty {
            if pokemonCardIsBasicEnergy(category: category, energyType: energyType) == false {
                return false
            }
        } else if legalMarks.contains(trimmedMark) == false {
            return false
        }
    }
    if format.isBanned(cardName: cardName) {
        return false
    }
    return true
}

private func pokemonCardIsBasicEnergy(category: String?, energyType: String?) -> Bool {
    guard category == "Energy" else { return false }
    return energyType?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .caseInsensitiveCompare("Basic") == .orderedSame
}

private func pokemonSetIsTournamentLegal(releaseDate: String?, now: Date = Date()) -> Bool {
    guard let releaseDate, releaseDate.isEmpty == false else { return true }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withFullDate]
    guard let release = formatter.date(from: releaseDate) else { return true }
    guard let legalDate = Calendar(identifier: .gregorian).date(byAdding: .day, value: 14, to: release) else {
        return true
    }
    return legalDate <= now
}

#Preview {
    NavigationStack {
        BrowseView(
            collectionItems: [],
            filters: .constant(BrowseCardGridFilters()),
            inlineDetailFilters: .constant(BrowseCardGridFilters()),
            gridOptions: .constant(BrowseGridOptions()),
            isFilterMenuPresented: .constant(false),
            filterResultCount: .constant(0),
            filterEnergyOptions: .constant([]),
            filterRarityOptions: .constant([]),
            filterTrainerTypeOptions: .constant([]),
            inlineDetailFilterResultCount: .constant(0),
            inlineDetailFilterEnergyOptions: .constant([]),
            inlineDetailFilterRarityOptions: .constant([]),
            inlineDetailFilterTrainerTypeOptions: .constant([]),
            selectedTab: .constant(.cards),
            inlineDetailRoute: .constant(nil),
            isMultiSelectActive: .constant(false),
            multiSelectedCardIDs: .constant([])
        )
    }
        .environment(AppServices())
        .environmentObject(ChromeScrollCoordinator())
}
