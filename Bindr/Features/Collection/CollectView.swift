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
    @State private var collectionFilters = BrowseCardGridFilters()
    @State private var collectionFilterEnergyOptions: [String] = []
    @State private var collectionFilterRarityOptions: [String] = []
    @State private var collectionFilterTrainerTypeOptions: [String] = []
    @State private var cardsByCardID: [String: Card] = [:]

    // MARK: - Wishlist State
    @Query(sort: \WishlistItem.dateAdded, order: .reverse) private var wishlistItems: [WishlistItem]
    @State private var wishlistFilters = BrowseCardGridFilters()
    @State private var wishlistFilterEnergyOptions: [String] = []
    @State private var wishlistFilterRarityOptions: [String] = []
    @State private var wishlistFilterTrainerTypeOptions: [String] = []

    // MARK: - Shared State
    /// Owned by `RootView` so the top-bar menu can route the "Wishlist" quick-access into the Collect tab's Wishlist segment.
    @Binding var selectedSegment: CollectSegment

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    private var visibleCollectionItems: [CollectionItem] {
        let enabled = services.brandSettings.enabledBrands
        return collectionItems.filter { enabled.contains(TCGBrand.inferredFromMasterCardId($0.cardID)) }
    }

    private var visibleWishlistItems: [WishlistItem] {
        let enabled = services.brandSettings.enabledBrands
        return wishlistItems.filter { enabled.contains(TCGBrand.inferredFromMasterCardId($0.cardID)) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Segmented control at top
            segmentedControl
                .padding(.horizontal, 16)
                .padding(.top, rootFloatingChromeInset)
                .padding(.bottom, 8)

            // Content based on selected segment
            contentView
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            services.setupCollectionLedger(modelContext: modelContext)
            services.setupWishlist(modelContext: modelContext)
        }
        .task(id: collectionSignature) {
            await resolveCollectionCards()
        }
        .task(id: wishlistSignature) {
            await resolveWishlistCards()
        }
    }

    // MARK: - Segmented Control
    private var segmentedControl: some View {
        Picker("View", selection: $selectedSegment) {
            ForEach(CollectSegment.allCases) { segment in
                Text(segment.title)
                    .tag(segment)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Content View
    @ViewBuilder
    private var contentView: some View {
        switch selectedSegment {
        case .collection:
            collectionContent
        case .wishlist:
            wishlistContent
        }
    }

    // MARK: - Collection Content
    @ViewBuilder
    private var collectionContent: some View {
        if collectionItems.isEmpty {
            emptyState(
                title: "No collection yet",
                image: "square.stack.3d.up.slash",
                description: "Add cards from card details with the + button."
            )
        } else if visibleCollectionItems.isEmpty {
            emptyState(
                title: "No visible collection items",
                image: "line.3.horizontal.decrease.circle",
                description: "Turn a game back on under Account → Card catalog to see collection cards for that game."
            )
        } else {
            collectionScrollGrid
        }
    }

    private var collectionScrollGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(Array(filteredCollectionItems.enumerated()), id: \.element.id) { index, item in
                    collectionCell(for: item)
                        .onAppear {
                            ImagePrefetcher.shared.prefetchCardWindow(orderedCollectionCards, startingAt: index + 1)
                        }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private func collectionCell(for item: CollectionItem) -> some View {
        if let card = cardsByCardID[item.cardID] {
            Button {
                presentCard(card, orderedCollectionCards)
            } label: {
                CardGridCell(card: card, footnote: collectionFootnote(for: item))
            }
            .buttonStyle(CardCellButtonStyle())
            .accessibilityLabel("\(card.cardName), \(item.quantity) copies, \(item.variantKey)")
        } else {
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.15))
                    .aspectRatio(5 / 7, contentMode: .fit)
                    .overlay { ProgressView() }
                Text(item.cardID)
                    .font(.caption2)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func collectionFootnote(for item: CollectionItem) -> String {
        let v = item.variantKey.replacingOccurrences(of: "_", with: " ")
        return "×\(item.quantity) · \(v)"
    }

    private var filteredCollectionItems: [CollectionItem] {
        guard collectionFilters.hasActiveFieldFilters else { return visibleCollectionItems }
        let cards = orderedCollectionCards
        let filteredCards = filterBrowseCards(
            cards,
            query: "",
            filters: collectionFilters,
            ownedCardIDs: ownedCollectionCardIDs,
            brand: services.brandSettings.selectedCatalogBrand,
            sets: services.cardData.sets
        )
        let filteredIDs = Set(filteredCards.map { $0.masterCardId })
        return visibleCollectionItems.filter { filteredIDs.contains($0.cardID) }
    }

    private var ownedCollectionCardIDs: Set<String> {
        Set(visibleCollectionItems.map { $0.cardID })
    }

    private var orderedCollectionCards: [Card] {
        visibleCollectionItems.compactMap { cardsByCardID[$0.cardID] }
    }

    private var collectionSignature: String {
        let brandKey = services.brandSettings.enabledBrands.map(\.rawValue).sorted().joined(separator: ",")
        return visibleCollectionItems.map { "\($0.cardID)|\($0.variantKey)|\($0.quantity)" }.joined(separator: "§") + "|" + brandKey
    }

    private func resolveCollectionCards() async {
        var next = cardsByCardID
        for item in visibleCollectionItems {
            if next[item.cardID] != nil { continue }
            if let c = await services.cardData.loadCard(masterCardId: item.cardID) {
                next[item.cardID] = c
            }
        }
        cardsByCardID = next
        ImagePrefetcher.shared.prefetchCardWindow(orderedCollectionCards, startingAt: 0, count: 24)
    }

    // MARK: - Wishlist Content
    @ViewBuilder
    private var wishlistContent: some View {
        if wishlistItems.isEmpty {
            emptyState(
                title: "Wishlist is empty",
                image: "star.slash",
                description: "Add cards from browse or search to track cards you want."
            )
        } else if visibleWishlistItems.isEmpty {
            emptyState(
                title: "No visible wishlist items",
                image: "line.3.horizontal.decrease.circle",
                description: "Turn a game back on under Account → Card catalog to see wishlist cards for that game."
            )
        } else {
            wishlistScrollGrid
        }
    }

    private var wishlistScrollGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(Array(filteredWishlistItems.enumerated()), id: \.element.id) { index, item in
                    wishlistCell(for: item)
                        .onAppear {
                            ImagePrefetcher.shared.prefetchCardWindow(orderedWishlistCards, startingAt: index + 1)
                        }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private func wishlistCell(for item: WishlistItem) -> some View {
        if let card = wishlistCardsByID[item.cardID] {
            Button {
                presentCard(card, orderedWishlistCards)
            } label: {
                CardGridCell(card: card, footnote: nil)
            }
            .buttonStyle(CardCellButtonStyle())
            .accessibilityLabel("\(card.cardName)")
        } else {
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.15))
                    .aspectRatio(5 / 7, contentMode: .fit)
                    .overlay { ProgressView() }
                Text(item.cardID)
                    .font(.caption2)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @State private var wishlistCardsByID: [String: Card] = [:]


    private var filteredWishlistItems: [WishlistItem] {
        guard wishlistFilters.hasActiveFieldFilters else { return visibleWishlistItems }
        let cards = orderedWishlistCards
        let filteredCards = filterBrowseCards(
            cards,
            query: "",
            filters: wishlistFilters,
            ownedCardIDs: [],
            brand: services.brandSettings.selectedCatalogBrand,
            sets: services.cardData.sets
        )
        let filteredIDs = Set(filteredCards.map { $0.masterCardId })
        return visibleWishlistItems.filter { filteredIDs.contains($0.cardID) }
    }

    private var orderedWishlistCards: [Card] {
        visibleWishlistItems.compactMap { wishlistCardsByID[$0.cardID] }
    }

    private var wishlistSignature: String {
        let brandKey = services.brandSettings.enabledBrands.map(\.rawValue).sorted().joined(separator: ",")
        let itemsSignature = visibleWishlistItems.map { "\($0.cardID)" }.joined(separator: "§")
        return itemsSignature + "|" + brandKey
    }

    private func resolveWishlistCards() async {
        var next = wishlistCardsByID
        for item in visibleWishlistItems {
            if next[item.cardID] != nil { continue }
            if let c = await services.cardData.loadCard(masterCardId: item.cardID) {
                next[item.cardID] = c
            }
        }
        wishlistCardsByID = next
        ImagePrefetcher.shared.prefetchCardWindow(orderedWishlistCards, startingAt: 0, count: 24)
    }

    // MARK: - Empty State
    private func emptyState(title: String, image: String, description: String) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                Color.clear.frame(height: rootFloatingChromeInset)
                ContentUnavailableView(
                    title,
                    systemImage: image,
                    description: Text(description)
                )
                .frame(minHeight: 280)
            }
        }
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
        case .wishlist: return "Wishlist"
        }
    }
}
