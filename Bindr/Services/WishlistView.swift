import SwiftUI
import SwiftData

struct WishlistView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(\.presentCard) private var presentCard
    @Environment(\.rootFloatingChromeInset) private var rootFloatingChromeInset
    @Query(sort: \WishlistItem.dateAdded, order: .reverse) private var items: [WishlistItem]

    @Binding var filters: BrowseCardGridFilters
    @Binding var isActive: Bool
    var onFilterOptionsChange: (([String], [String], [String]) -> Void)?

    /// Items for games that are still enabled in Account (same rows stay in iCloud; UI hides the rest).
    private var visibleWishlistItems: [WishlistItem] {
        let enabled = services.brandSettings.enabledBrands
        return items.filter { enabled.contains(TCGBrand.inferredFromMasterCardId($0.cardID)) }
    }

    @State private var cardsByCardID: [String: Card] = [:]
    @State private var showPaywall = false
    @State private var showShareSettings = false
    @State private var isSharedPublished = false
    @State private var errorMessage: String?

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    /// Reload when membership, card ids, or enabled games change.
    private var wishlistSignature: String {
        let brandKey = services.brandSettings.enabledBrands.map(\.rawValue).sorted().joined(separator: ",")
        return visibleWishlistItems.map { "\($0.cardID)|\($0.variantKey)" }.joined(separator: "§") + "|" + brandKey
    }

    /// Same order as `visibleWishlistItems`, for horizontal paging in `CardBrowseDetailView`.
    private var orderedCards: [Card] {
        visibleWishlistItems.compactMap { cardsByCardID[$0.cardID] }
    }

    private var ownedCardIDs: Set<String> {
        Set<String>()
    }

    private var filteredItems: [(item: WishlistItem, card: Card)] {
        let resolved = visibleWishlistItems.compactMap { item -> (WishlistItem, Card)? in
            guard let card = cardsByCardID[item.cardID] else { return nil }
            return (item, card)
        }
        guard filters.hasActiveFieldFilters else {
            return resolved.map { ($0.0, $0.1) }
        }
        let cards = resolved.map { $0.1 }
        let filteredCards = filterBrowseCards(
            cards,
            query: "",
            filters: filters,
            ownedCardIDs: ownedCardIDs,
            brand: services.brandSettings.selectedCatalogBrand,
            sets: services.cardData.sets
        )
        let filteredIDs = Set(filteredCards.map { $0.masterCardId })
        return resolved.filter { filteredIDs.contains($0.1.masterCardId) }.map { ($0.0, $0.1) }
    }

    var body: some View {
        Group {
            if items.isEmpty {
                emptyState
            } else if visibleWishlistItems.isEmpty {
                hiddenByBrandEmptyState
            } else {
                wishlistScrollGrid
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showPaywall) {
            PaywallSheet()
                .environment(services)
        }
        .sheet(isPresented: $showShareSettings) {
            ShareSettingsView(source: .wishlist(items: visibleWishlistItems)) {
                Task { await refreshShareStatus() }
            }
            .environment(services)
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") {
                errorMessage = nil
            }
        } message: {
            if let errorMessage {
                Text(errorMessage)
            }
        }
        .task(id: wishlistSignature) {
            await resolveWishlistCards()
            services.socialShare.scheduleAutoSyncWishlist(items: visibleWishlistItems)
            await refreshShareStatus()
        }
        .onAppear {
            services.setupWishlist(modelContext: modelContext)
            isActive = true
            Task {
                await refreshShareStatus()
            }
        }
        .onDisappear {
            isActive = false
        }
    }

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 16) {
                Color.clear.frame(height: rootFloatingChromeInset)

                if services.cloudSettings.syncStatus != .cloudKitConnected {
                    iCloudBanner
                        .padding(.horizontal, 16)
                }

                wishlistTopBar
                    .padding(.horizontal, 16)

                ContentUnavailableView(
                    "No wishlist items",
                    systemImage: "star.slash",
                    description: Text("Open a card, then tap the star to add it here.")
                )
                .frame(minHeight: 280)
            }
        }
    }

    private var hiddenByBrandEmptyState: some View {
        ScrollView {
            VStack(spacing: 16) {
                Color.clear.frame(height: rootFloatingChromeInset)

                if services.cloudSettings.syncStatus != .cloudKitConnected {
                    iCloudBanner
                        .padding(.horizontal, 16)
                }

                wishlistTopBar
                    .padding(.horizontal, 16)

                ContentUnavailableView(
                    "No visible wishlist items",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text("Turn a game back on under Account → Card catalog to see wishlist cards for that game.")
                )
                .frame(minHeight: 280)
            }
        }
    }

    private var wishlistScrollGrid: some View {
        ScrollView {
            VStack(spacing: 0) {
                Color.clear.frame(height: rootFloatingChromeInset)

                if services.cloudSettings.syncStatus != .cloudKitConnected {
                    iCloudBanner
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }

                wishlistTopBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Array(filteredItems.enumerated()), id: \.element.item.id) { index, pair in
                        wishlistCell(for: pair.item)
                            .onAppear {
                                ImagePrefetcher.shared.prefetchCardWindow(orderedCards, startingAt: index + 1)
                            }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

                if !services.store.isPremium && items.count >= WishlistFreeTier.maxItems {
                    Button("Upgrade to Premium for unlimited wishlist items") {
                        showPaywall = true
                    }
                    .font(.caption)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }
        }
        .coordinateSpace(name: "wishlistScroll")
    }

    private var wishlistTopBar: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Wishlist")
                .font(.largeTitle.bold())
            Spacer()
            Button {
                showShareSettings = true
            } label: {
                Image(systemName: isSharedPublished ? "checkmark.circle.fill" : "square.and.arrow.up")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isSharedPublished ? .green : .primary)
                    .padding(8)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSharedPublished ? "Wishlist share settings" : "Share wishlist")
        }
    }

    private var iCloudBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.icloud")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(iCloudBannerTitle)
                    .font(.headline)
                Text(iCloudBannerMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var iCloudBannerTitle: String {
        switch services.cloudSettings.syncStatus {
        case .cloudKitConnected:
            return "iCloud connected"
        case .cloudKitFallback:
            return "CloudKit sync failed"
        case .iCloudAccountUnavailable:
            return "iCloud not available"
        }
    }

    private var iCloudBannerMessage: String {
        switch services.cloudSettings.syncStatus {
        case .cloudKitConnected:
            return "Your wishlist syncs through your private iCloud database."
        case .cloudKitFallback:
            return "This device is signed into iCloud, but the app could not open its CloudKit store and is using local-only storage."
        case .iCloudAccountUnavailable:
            return "Sign into iCloud to sync your wishlist across devices."
        }
    }

    @ViewBuilder
    private func wishlistCell(for item: WishlistItem) -> some View {
        if let card = cardsByCardID[item.cardID] {
            Button {
                presentCard(card, orderedCards)
            } label: {
                CardGridCell(card: card, footnote: item.variantKey)
            }
            .buttonStyle(CardCellButtonStyle())
            .contextMenu {
                Button("Remove from Wishlist", role: .destructive) {
                    removeItem(item)
                }
            }
            .accessibilityLabel("\(card.cardName), \(item.variantKey)")
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
                Text(item.variantKey)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .contextMenu {
                Button("Remove from Wishlist", role: .destructive) {
                    removeItem(item)
                }
            }
        }
    }

    private func resolveWishlistCards() async {
        var next = cardsByCardID  // preserve already-resolved cards
        for item in visibleWishlistItems {
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

    private func removeItem(_ item: WishlistItem) {
        guard let wishlistService = services.wishlist else { return }
        do {
            try wishlistService.removeItem(item)
            HapticManager.notification(.success)
        } catch {
            errorMessage = error.localizedDescription
            HapticManager.notification(.error)
        }
    }

    private func refreshShareStatus() async {
        do {
            let snapshot = try await services.socialShare.shareSnapshotForWishlist()
            isSharedPublished = snapshot.isPublished
        } catch {
            isSharedPublished = false
        }
    }
}

// MARK: - Preview Helpers

#Preview("Empty Wishlist") {
    NavigationStack {
        WishlistView(
            filters: .constant(BrowseCardGridFilters()),
            isActive: .constant(true)
        )
        .environment(AppServices())
    }
    .modelContainer(WishlistPreview.modelContainer)
}

private enum WishlistPreview {
    static var modelContainer: ModelContainer {
        let schema = Schema([
            WishlistItem.self,
            CollectionItem.self,
            LedgerLine.self,
            CostLot.self,
            SaleAllocation.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try! ModelContainer(for: schema, configurations: [config])
    }
}
