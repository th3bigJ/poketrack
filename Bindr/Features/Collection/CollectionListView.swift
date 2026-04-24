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

    private let columnCount = 3

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

                ContentUnavailableView(
                    "No visible collection items",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text("Turn a game back on under Account → Card catalog to see collection cards for that game.")
                )
                .frame(minHeight: 280)
            }
        }
    }

    private var collectionScrollGrid: some View {
        ScrollView {
            VStack(spacing: 0) {
                Color.clear.frame(height: rootFloatingChromeInset)

                EagerVGrid(items: filteredCollectionItems, columns: columnCount, spacing: 12) { item in
                    let index = filteredCollectionItems.firstIndex(where: { $0.id == item.id }) ?? 0
                    collectionCell(for: item)
                        .onAppear {
                            ImagePrefetcher.shared.prefetchCardWindow(orderedCards, startingAt: index + 1)
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
