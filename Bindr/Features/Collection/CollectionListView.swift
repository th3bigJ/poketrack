import SwiftData
import SwiftUI

/// Owned cards — same grid pattern as Wishlist / Browse.
struct CollectionListView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(\.presentCard) private var presentCard
    @Environment(\.rootFloatingChromeInset) private var rootFloatingChromeInset
    @Query(sort: \CollectionItem.dateAcquired, order: .reverse) private var items: [CollectionItem]

    @Binding var filters: BrowseCardGridFilters
    var onFilterOptionsChange: (([String], [String], [String]) -> Void)?
    @Binding var wishlistFilters: BrowseCardGridFilters
    @Binding var isWishlistActive: Bool
    var onWishlistFilterOptionsChange: (([String], [String], [String]) -> Void)?

    private var visibleCollectionItems: [CollectionItem] {
        let enabled = services.brandSettings.enabledBrands
        return items.filter { enabled.contains(TCGBrand.inferredFromMasterCardId($0.cardID)) }
    }

    @State private var cardsByCardID: [String: Card] = [:]

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    private var ownedCardIDs: Set<String> {
        Set(visibleCollectionItems.map { $0.cardID })
    }

    private var filteredCollectionItems: [CollectionItem] {
        guard filters.hasActiveFieldFilters else { return visibleCollectionItems }
        let cards = orderedCards
        let filteredCards = filterBrowseCards(
            cards,
            query: "",
            filters: filters,
            ownedCardIDs: ownedCardIDs,
            brand: services.brandSettings.selectedCatalogBrand,
            sets: services.cardData.sets
        )
        let filteredIDs = Set(filteredCards.map { $0.masterCardId })
        return visibleCollectionItems.filter { filteredIDs.contains($0.cardID) }
    }

    private var collectionSignature: String {
        let brandKey = services.brandSettings.enabledBrands.map(\.rawValue).sorted().joined(separator: ",")
        return visibleCollectionItems.map { "\($0.cardID)|\($0.variantKey)|\($0.quantity)" }.joined(separator: "§") + "|" + brandKey
    }

    private var orderedCards: [Card] {
        visibleCollectionItems.compactMap { cardsByCardID[$0.cardID] }
    }

    var body: some View {
        Group {
            if items.isEmpty {
                emptyState
            } else if visibleCollectionItems.isEmpty {
                hiddenByBrandEmptyState
            } else {
                collectionScrollGrid
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: String.self) { route in
            if route == "wishlist" {
                WishlistView(
                    filters: $wishlistFilters,
                    isActive: $isWishlistActive,
                    onFilterOptionsChange: onWishlistFilterOptionsChange
                )
            }
        }
        .task(id: collectionSignature) {
            await resolveCollectionCards()
        }
        .onAppear {
            services.setupCollectionLedger(modelContext: modelContext)
        }
    }

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 16) {
                Color.clear.frame(height: rootFloatingChromeInset)

                wishlistEntryRow
                    .padding(.horizontal, 16)

                ContentUnavailableView(
                    "No collection yet",
                    systemImage: "square.stack.3d.up.slash",
                    description: Text("Add cards from card details with the + button.")
                )
                .frame(minHeight: 280)
            }
        }
    }

    private var hiddenByBrandEmptyState: some View {
        ScrollView {
            VStack(spacing: 16) {
                Color.clear.frame(height: rootFloatingChromeInset)

                wishlistEntryRow
                    .padding(.horizontal, 16)

                ContentUnavailableView(
                    "No visible collection items",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text("Turn a game back on under Account → Card catalog to see collection cards for that game.")
                )
                .frame(minHeight: 280)
            }
        }
    }

    private var wishlistEntryRow: some View {
        NavigationLink(value: "wishlist") {
            HStack(spacing: 12) {
                Image(systemName: "star.fill")
                    .font(.title3)
                    .foregroundStyle(.yellow)
                    .frame(width: 36, height: 36)
                    .background(Color.yellow.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wishlist")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Cards you want to collect")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var collectionScrollGrid: some View {
        ScrollView {
            VStack(spacing: 0) {
                Color.clear.frame(height: rootFloatingChromeInset)

                wishlistEntryRow
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Array(filteredCollectionItems.enumerated()), id: \.element.id) { index, item in
                        collectionCell(for: item)
                            .onAppear {
                                ImagePrefetcher.shared.prefetchCardWindow(orderedCards, startingAt: index + 1)
                            }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
    }

    @ViewBuilder
    private func collectionCell(for item: CollectionItem) -> some View {
        if let card = cardsByCardID[item.cardID] {
            Button {
                presentCard(card, orderedCards)
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
                    .overlay {
                        ProgressView()
                    }
                Text(item.cardID)
                    .font(.caption2)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func collectionFootnote(for item: CollectionItem) -> String {
        let v = item.variantKey
            .replacingOccurrences(of: "_", with: " ")
        return "×\(item.quantity) · \(v)"
    }

    private func resolveCollectionCards() async {
        var next = cardsByCardID  // preserve already-resolved cards
        for item in visibleCollectionItems {
            if next[item.cardID] != nil { continue }
            if let c = await services.cardData.loadCard(masterCardId: item.cardID) {
                next[item.cardID] = c
            }
        }
        cardsByCardID = next
        ImagePrefetcher.shared.prefetchCardWindow(orderedCards, startingAt: 0, count: 24)
        onFilterOptionsChange?(
            cardEnergyOptions(orderedCards),
            cardRarityOptions(orderedCards),
            cardTrainerTypeOptions(orderedCards)
        )
    }
}
