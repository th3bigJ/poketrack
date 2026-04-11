import SwiftUI
import SwiftData

struct WishlistView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(\.presentCard) private var presentCard
    @Environment(\.rootFloatingChromeInset) private var rootFloatingChromeInset
    @Query(sort: \WishlistItem.dateAdded, order: .reverse) private var items: [WishlistItem]

    @State private var cardsByCardID: [String: Card] = [:]
    @State private var showPaywall = false
    @State private var errorMessage: String?

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    /// Reload when membership or card ids change.
    private var wishlistSignature: String {
        items.map { "\($0.cardID)|\($0.variantKey)" }.joined(separator: "§")
    }

    /// Same order as `items`, for horizontal paging in `CardBrowseDetailView`.
    private var orderedCards: [Card] {
        items.compactMap { cardsByCardID[$0.cardID] }
    }

    var body: some View {
        Group {
            if items.isEmpty {
                emptyState
            } else {
                wishlistScrollGrid
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showPaywall) {
            PaywallSheet()
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
        }
        .onAppear {
            services.setupWishlist(modelContext: modelContext)
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
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        wishlistCell(for: item)
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
        Text("Wishlist")
            .font(.largeTitle.bold())
            .frame(maxWidth: .infinity, alignment: .leading)
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
        for item in items {
            if next[item.cardID] != nil { continue }
            if let c = await services.cardData.loadCard(masterCardId: item.cardID) {
                next[item.cardID] = c
            }
        }
        cardsByCardID = next
        ImagePrefetcher.shared.prefetchCardWindow(orderedCards, startingAt: 0, count: 24)
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
}

// MARK: - Preview Helpers

#Preview("Empty Wishlist") {
    NavigationStack {
        WishlistView()
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
