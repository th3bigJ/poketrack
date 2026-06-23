import SwiftData
import SwiftUI

/// Owned cards — same grid pattern as Wishlist / Browse.
struct CollectionListView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Environment(\.presentCardAtIndex) private var presentCardAtIndex
    @Environment(\.rootFloatingChromeInset) private var rootFloatingChromeInset
    @Query(sort: \CollectionItem.dateAcquired, order: .reverse) private var items: [CollectionItem]

    @Binding var filters: BrowseCardGridFilters
    var onFilterOptionsChange: (([String], [String], [String]) -> Void)?
    @Binding var wishlistFilters: BrowseCardGridFilters
    @Binding var isWishlistActive: Bool
    var onWishlistFilterOptionsChange: (([String], [String], [String]) -> Void)?

    private var visibleCollectionItems: [CollectionItem] {
        items
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
        visibleCollectionItems.map { "\($0.cardID)|\($0.variantKey)|\($0.quantity)" }.joined(separator: "§")
    }

    private var orderedCards: [Card] {
        visibleCollectionItems.compactMap { cardsByCardID[$0.cardID] }
    }

    private var filteredCollectionGroups: [CollectionGridGroup] {
        groupCollectionItemsForGrid(filteredCollectionItems)
    }

    private var filteredOrderedCards: [Card] {
        filteredCollectionGroups.compactMap { cardsByCardID[$0.cardID] }
    }

    private func groupCollectionItemsForGrid(_ items: [CollectionItem]) -> [CollectionGridGroup] {
        CollectionGridGrouping.groupedItems(items, isSealed: { _ in false })
    }

    var body: some View {
        Group {
            if items.isEmpty {
                emptyState
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

    private var collectionScrollGrid: some View {
        ScrollView {
            VStack(spacing: 0) {
                Color.clear.frame(height: rootFloatingChromeInset)

                EagerVGrid(items: filteredCollectionGroups, columns: columnCount, spacing: BindrSpacing.cardGrid) { group in
                    let index = filteredCollectionGroups.firstIndex(where: { $0.id == group.id }) ?? 0
                    collectionCell(for: group)
                        .onAppear {
                            ImagePrefetcher.shared.prefetchCardWindow(orderedCards, startingAt: index + 1)
                        }
                }
                .padding(.horizontal, BindrSpacing.cardGridScreenInset)
                .padding(.bottom, 8)
            }
        }
    }

    @ViewBuilder
    private func collectionCell(for group: CollectionGridGroup) -> some View {
        let item = group.representativeItem
        if let card = cardsByCardID[item.cardID] {
            Button {
                let cards = filteredOrderedCards
                let index = cards.firstIndex(where: { $0.masterCardId == card.masterCardId }) ?? 0
                presentCardAtIndex(cards, index)
            } label: {
                CardGridCell(
                    card: card,
                    services: services,
                    colorScheme: colorScheme,
                    accentColor: services.theme.accentColor,
                    ownedCountBadge: group.totalQuantity,
                    footnote: collectionFootnote(for: group)
                )
            }
            .buttonStyle(CardCellButtonStyle())
            .accessibilityLabel(collectionAccessibilityLabel(for: card, group: group))
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

    private func collectionFootnote(for group: CollectionGridGroup) -> String {
        if group.variantKeys.count > 1 {
            return "×\(group.totalQuantity) · \(group.variantKeys.count) variants"
        }
        let variant = group.variantKeys.first ?? itemVariantLabel(group.representativeItem)
        return "×\(group.totalQuantity) · \(variant)"
    }

    private func itemVariantLabel(_ item: CollectionItem) -> String {
        item.variantKey.replacingOccurrences(of: "_", with: " ")
    }

    private func collectionAccessibilityLabel(for card: Card, group: CollectionGridGroup) -> String {
        if group.variantKeys.count > 1 {
            return "\(card.cardName), \(group.totalQuantity) copies, \(group.variantKeys.count) variants"
        }
        return "\(card.cardName), \(group.totalQuantity) copies, \(group.variantKeys.first ?? "normal")"
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
