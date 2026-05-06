import SwiftUI

struct TradeWallView: View {
    @Environment(AppServices.self) private var services
    @Binding var navigationPath: NavigationPath

    @State private var cardEntries: [WallEntry] = []
    @State private var sealedEntries: [SealedWallEntry] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var cardDetailSession: CardDetailSession?
    @State private var selectedSealedProduct: SealedProduct?
    @State private var selectedTab: Tab = .cards

    enum Tab: String, CaseIterable {
        case cards  = "Cards"
        case sealed = "Sealed"
    }

    struct WallEntry: Identifiable {
        let id: String
        let card: Card
        let owner: SocialProfile
        var setName: String?
    }

    struct SealedWallEntry: Identifiable {
        let id: String
        let product: SealedProduct
        let owner: SocialProfile
    }

    private struct CardDetailSession: Identifiable {
        let id = UUID()
        let card: Card
        let owner: SocialProfile
    }

    private static let gridOptions = BrowseGridOptions(
        showCardName: true,
        showSetName: true,
        showSetID: false,
        showPricing: true,
        showOwned: false
    )

    var body: some View {
        VStack(spacing: 0) {
            if !cardEntries.isEmpty || !sealedEntries.isEmpty {
                tabPicker
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
            }

            Group {
                if isLoading && cardEntries.isEmpty && sealedEntries.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else {
                    switch selectedTab {
                    case .cards:
                        if cardEntries.isEmpty {
                            emptyState(
                                icon: "square.grid.2x2",
                                title: "No cards on the trade wall",
                                message: "Cards your friends have on their trade list will appear here."
                            )
                        } else {
                            ScrollView {
                                cardGrid
                                    .padding(.top, 8)
                            }
                        }
                    case .sealed:
                        if sealedEntries.isEmpty {
                            emptyState(
                                icon: "shippingbox",
                                title: "No sealed products on the trade wall",
                                message: "Sealed products your friends have on their trade list will appear here."
                            )
                        } else {
                            ScrollView {
                                sealedGrid
                                    .padding(.top, 8)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task { await load() }
        .sheet(item: $cardDetailSession) { session in
            CardDetailSheet(
                cards: [session.card],
                startIndex: 0,
                tradeAction: { card, _ in startTrade(card: card, with: session.owner) },
                tradeActionLabel: "Offer Trade..."
            )
            .environment(services)
        }
        .sheet(item: $selectedSealedProduct) { product in
            SealedProductBrowseDetailView(products: [product], startProductID: product.id)
                .environment(services)
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Tab picker

    private var tabPicker: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { tab in
                Button {
                    Haptics.selectionChanged()
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab == .cards ? "square.stack.3d.up" : "shippingbox")
                            .font(.system(size: 11, weight: .semibold))
                        Text(tab.rawValue)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(selectedTab == tab ? .white : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(selectedTab == tab ? services.theme.accentColor : .clear, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
        .overlay { Capsule().stroke(Color.primary.opacity(0.06), lineWidth: 1) }
    }

    // MARK: - Grids

    private var cardGrid: some View {
        EagerVGrid(items: cardEntries, columns: 3, spacing: 8) { entry in
            Button {
                Haptics.lightImpact()
                cardDetailSession = CardDetailSession(card: entry.card, owner: entry.owner)
            } label: {
                CardGridCell(
                    card: entry.card,
                    gridOptions: Self.gridOptions,
                    setName: entry.setName
                )
                .overlay(alignment: .topTrailing) {
                    ProfileAvatarView(profile: entry.owner, size: 20)
                        .overlay(Circle().stroke(Color(uiColor: .systemBackground), lineWidth: 1.5))
                        .padding(4)
                }
            }
            .buttonStyle(CardCellButtonStyle())
        }
        .padding(.horizontal, 12)
    }

    private var sealedGrid: some View {
        EagerVGrid(items: sealedEntries, columns: 3, spacing: 8) { entry in
            Button {
                Haptics.lightImpact()
                selectedSealedProduct = entry.product
            } label: {
                SealedProductGridCell(
                    product: entry.product,
                    gridOptions: Self.gridOptions,
                    priceUSD: services.sealedProducts.marketPriceUSD(for: entry.product.id),
                    isOwned: false,
                    isWishlisted: false
                )
                .overlay(alignment: .topTrailing) {
                    ProfileAvatarView(profile: entry.owner, size: 20)
                        .overlay(Circle().stroke(Color(uiColor: .systemBackground), lineWidth: 1.5))
                        .padding(4)
                }
            }
            .buttonStyle(CardCellButtonStyle())
        }
        .padding(.horizontal, 12)
    }

    // MARK: - Empty state

    private func emptyState(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.secondary.opacity(0.4))
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.secondary)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Color.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    // MARK: - Load

    private func load() async {
        guard case .signedIn = services.socialAuth.authState else { return }
        isLoading = true
        defer { isLoading = false }

        await services.sealedProducts.loadFromLocalIfAvailable()

        do {
            let friends = try await services.socialFriend.fetchFriends()
            guard !friends.isEmpty else { return }

            let friendIDs = friends.map(\.id)
            let tradeListMap = try await services.socialCardLibrary.fetchTradeListCardIDsByUser(for: friendIDs)

            var newCardEntries: [WallEntry] = []
            var newSealedEntries: [SealedWallEntry] = []

            for friend in friends {
                let cardIDs = tradeListMap[friend.id] ?? []
                for cardID in cardIDs {
                    if let productID = SealedProduct.parseCollectionProductID(cardID) {
                        if let product = services.sealedProducts.products.first(where: { $0.id == productID }) {
                            newSealedEntries.append(SealedWallEntry(
                                id: "\(friend.id)-\(cardID)",
                                product: product,
                                owner: friend
                            ))
                        }
                    } else if let card = await services.cardData.loadCard(masterCardId: cardID) {
                        let setName = services.cardData.sets.first { $0.setCode == card.setCode }?.name
                        newCardEntries.append(WallEntry(
                            id: "\(friend.id)-\(cardID)",
                            card: card,
                            owner: friend,
                            setName: setName
                        ))
                    }
                }
            }

            cardEntries = newCardEntries
            sealedEntries = newSealedEntries
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Trade

    private func startTrade(card: Card, with friend: SocialProfile) {
        cardDetailSession = nil
        let item = TradeItem(
            id: UUID(),
            tradeID: UUID(),
            ownerID: friend.id,
            cardID: card.masterCardId,
            variantKey: "normal",
            quantity: 1,
            createdAt: nil
        )
        navigationPath.append(SocialDestination.tradeBuilder(
            receiverID: friend.id,
            theirCards: [item],
            myCards: []
        ))
    }
}
