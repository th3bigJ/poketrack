import SwiftUI
import SwiftData

struct TradeWallView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.bindrAccent) private var accent
    @Environment(\.colorScheme) private var colorScheme
    @Binding var navigationPath: NavigationPath
    @Query private var collectionItems: [CollectionItem]

    @State private var suggestedEntries: [SuggestedWallEntry] = []
    @State private var cardEntries: [WallEntry] = []
    @State private var sealedEntries: [SealedWallEntry] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var cardDetailSession: CardDetailSession?
    @State private var selectedSealedProduct: SealedProduct?
    @State private var hasLoaded = false

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

    struct SuggestedWallEntry: Identifiable {
        let id: String
        let card: Card
        let owner: SocialProfile
        let matchType: TradeSuggestion.MatchType
    }

    enum TradeWallGridItem: Identifiable {
        case suggested(SuggestedWallEntry)
        case card(WallEntry)
        case sealed(SealedWallEntry)
        case seeAll(SocialProfile)

        var id: String {
            switch self {
            case .suggested(let entry): "suggested-\(entry.id)"
            case .card(let entry): "card-\(entry.id)"
            case .sealed(let entry): "sealed-\(entry.id)"
            case .seeAll(let profile): "seeall-\(profile.id)"
            }
        }
    }

    private struct CardDetailSession: Identifiable {
        let id = UUID()
        let card: Card
        let owner: SocialProfile
        let matchType: TradeSuggestion.MatchType?
    }

    private var gridItems: [TradeWallGridItem] {
        // Interleave suggested entries with a "see all" card after the last
        // suggestion for each friend.
        var items: [TradeWallGridItem] = []
        var seenFriendIDs: Set<UUID> = []
        let friendsWithSuggestions = Set(suggestedEntries.map(\.owner.id))
        for entry in suggestedEntries {
            items.append(.suggested(entry))
            let isLastForFriend = suggestedEntries.last(where: { $0.owner.id == entry.owner.id })?.id == entry.id
            if isLastForFriend, !seenFriendIDs.contains(entry.owner.id) {
                seenFriendIDs.insert(entry.owner.id)
                items.append(.seeAll(entry.owner))
            }
        }
        // Only show card/sealed wall entries for friends who had no suggestions
        items += cardEntries.filter { !friendsWithSuggestions.contains($0.owner.id) }.map { .card($0) }
        items += sealedEntries.filter { !friendsWithSuggestions.contains($0.owner.id) }.map { .sealed($0) }
        return items
    }

    var body: some View {
        Group {
            if isLoading && gridItems.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else if gridItems.isEmpty {
                emptyState
            } else {
                unifiedGrid
                    .padding(.top, 4)
            }
        }
        .task { await loadAfterFirstPaint() }
        .sheet(item: $cardDetailSession) { session in
            CardDetailSheet(
                cards: [session.card],
                startIndex: 0,
                tradeAction: { card, _ in startTrade(card: card, with: session.owner, matchType: session.matchType) },
                offerTradeOnly: true
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

    // MARK: - Grid

    private var unifiedGrid: some View {
        EagerVGrid(items: gridItems, columns: 3, spacing: 8) { item in
            switch item {
            case .suggested(let entry):
                Button {
                    Haptics.lightImpact()
                    cardDetailSession = CardDetailSession(
                        card: entry.card,
                        owner: entry.owner,
                        matchType: entry.matchType
                    )
                } label: {
                    TradeWallSuggestedCell(entry: entry, colorScheme: colorScheme)
                }
                .buttonStyle(TradeWallCellButtonStyle())

            case .card(let entry):
                Button {
                    Haptics.lightImpact()
                    cardDetailSession = CardDetailSession(card: entry.card, owner: entry.owner, matchType: nil)
                } label: {
                    TradeWallCardCell(entry: entry, colorScheme: colorScheme)
                }
                .buttonStyle(TradeWallCellButtonStyle())

            case .sealed(let entry):
                Button {
                    Haptics.lightImpact()
                    selectedSealedProduct = entry.product
                } label: {
                    TradeWallSealedCell(entry: entry, colorScheme: colorScheme)
                }
                .buttonStyle(TradeWallCellButtonStyle())

            case .seeAll(let profile):
                Button {
                    Haptics.lightImpact()
                    navigationPath.append(SocialDestination.friendsCollection)
                } label: {
                    TradeWallSeeAllCell(profile: profile, colorScheme: colorScheme)
                }
                .buttonStyle(TradeWallCellButtonStyle())
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.08))
                    .frame(width: 56, height: 56)
                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(accent.gradient)
            }

            VStack(spacing: 6) {
                Text("Nothing on the trade wall yet")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.primary)
                Text("Suggested matches and cards or sealed products your friends have on their trade lists will appear here.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
        .padding(.vertical, 36)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Load

    private func loadAfterFirstPaint() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await Task.yield()
        try? await Task.sleep(nanoseconds: 160_000_000)
        await load()
    }

    private func load() async {
        guard case .signedIn = services.socialAuth.authState else { return }
        isLoading = true
        defer { isLoading = false }

        await services.sealedProducts.loadFromLocalIfAvailable()

        do {
            let friends = try await services.socialFriend.fetchFriends()
            guard !friends.isEmpty else {
                suggestedEntries = []
                cardEntries = []
                sealedEntries = []
                return
            }

            let friendIDs = friends.map(\.id)

            var friendWishlistMap: [UUID: [String]] = [:]
            await withTaskGroup(of: (UUID, [String]).self) { group in
                for friend in friends {
                    group.addTask {
                        guard let snapshot = try? await services.collectionSync.fetchFriendCollection(userID: friend.id) else {
                            return (friend.id, [])
                        }
                        return (friend.id, snapshot.wishlist.compactMap { $0.cardID.isEmpty ? nil : $0.cardID })
                    }
                }
                for await (id, ids) in group {
                    friendWishlistMap[id] = ids
                }
            }

            let myWishlist = Set<String>(services.wishlist?.items.map(\.cardID) ?? [])
            let myOwnedCardIDs = Set<String>(collectionItems.compactMap { item in
                guard item.quantity > 0, !item.cardID.isEmpty else { return nil }
                return item.cardID
            })

            var newSuggested: [SuggestedWallEntry] = []
            let newCardEntries: [WallEntry] = []
            let newSealedEntries: [SealedWallEntry] = []

            for friend in friends {
                let theyWant = Set<String>(friendWishlistMap[friend.id] ?? [])
                let theyWantAndIHave = theyWant.intersection(myOwnedCardIDs)

                for cardID in theyWantAndIHave {
                    if let card = await services.cardData.loadCard(masterCardId: cardID) {
                        newSuggested.append(SuggestedWallEntry(
                            id: "\(friend.id)-want-\(cardID)",
                            card: card,
                            owner: friend,
                            matchType: .iHaveWhatTheyWant
                        ))
                    }
                }

            }

            suggestedEntries = newSuggested
            cardEntries = newCardEntries
            sealedEntries = newSealedEntries
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Trade

    private func startTrade(card: Card, with friend: SocialProfile, matchType: TradeSuggestion.MatchType?) {
        cardDetailSession = nil
        let theirItem = TradeItem(
            id: UUID(),
            tradeID: UUID(),
            ownerID: friend.id,
            cardID: card.masterCardId,
            variantKey: "normal",
            quantity: 1,
            createdAt: nil
        )
        let myItem = TradeItem(
            id: UUID(),
            tradeID: UUID(),
            ownerID: friend.id,
            cardID: card.masterCardId,
            variantKey: "normal",
            quantity: 1,
            createdAt: nil
        )

        switch matchType {
        case .iHaveWhatTheyWant:
            navigationPath.append(SocialDestination.tradeBuilder(
                receiverID: friend.id,
                theirCards: [],
                myCards: [myItem]
            ))
        case .theyHaveWhatIWant, .mutual, .none:
            navigationPath.append(SocialDestination.tradeBuilder(
                receiverID: friend.id,
                theirCards: [theirItem],
                myCards: []
            ))
        }
    }
}

// MARK: - Trade wall tags & footer

private enum TradeWallStatusTag {
    case theyWantIt
    case theyHaveIt
    case inCollection

    var label: String {
        switch self {
        case .theyWantIt: "They want it"
        case .theyHaveIt: "They have it"
        case .inCollection: "In collection"
        }
    }

    var color: Color {
        switch self {
        case .theyWantIt: Color(hex: "5B8CF5")
        case .theyHaveIt: Color(hex: "E8B84B")
        case .inCollection: Color.secondary
        }
    }

    static func suggested(_ matchType: TradeSuggestion.MatchType) -> TradeWallStatusTag {
        switch matchType {
        case .iHaveWhatTheyWant: .theyWantIt
        case .theyHaveWhatIWant, .mutual: .theyHaveIt
        }
    }
}

private struct TradeWallStatusBadge: View {
    let tag: TradeWallStatusTag

    var body: some View {
        Text(tag.label)
            .font(.system(size: 8, weight: .bold))
            .tracking(0.2)
            .foregroundStyle(tag.color)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(tag.color.opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(tag.color.opacity(0.28), lineWidth: 0.5))
    }
}

private struct TradeWallCellFooter: View {
    let owner: SocialProfile
    let itemName: String
    let tag: TradeWallStatusTag

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 7) {
                ProfileAvatarView(profile: owner, size: 24)
                    .overlay(
                        Circle().stroke(Color.primary.opacity(0.10), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)

                VStack(alignment: .leading, spacing: 2) {
                    Text(owner.displayName ?? owner.username)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(itemName)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            TradeWallStatusBadge(tag: tag)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - TradeWallSuggestedCell

private struct TradeWallSuggestedCell: View {
    let entry: TradeWallView.SuggestedWallEntry
    let colorScheme: ColorScheme

    var body: some View {
        tradeWallCellChrome(colorScheme: colorScheme) {
            CachedAsyncImage(url: AppConfiguration.imageURL(relativePath: entry.card.displayImageSrc)) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                tradeWallImagePlaceholder(icon: "photo")
            }
            .aspectRatio(5/7, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipped()

            TradeWallCellFooter(
                owner: entry.owner,
                itemName: entry.card.cardName,
                tag: .suggested(entry.matchType)
            )
        }
    }
}

// MARK: - TradeWallCardCell

/// Compact trade wall cell for the 3-column grid.
private struct TradeWallCardCell: View {
    let entry: TradeWallView.WallEntry
    let colorScheme: ColorScheme

    var body: some View {
        tradeWallCellChrome(colorScheme: colorScheme) {
            CachedAsyncImage(url: AppConfiguration.imageURL(relativePath: entry.card.displayImageSrc)) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                tradeWallImagePlaceholder(icon: "photo")
            }
            .aspectRatio(5/7, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipped()

            TradeWallCellFooter(
                owner: entry.owner,
                itemName: entry.card.cardName,
                tag: .inCollection
            )
        }
    }
}

// MARK: - TradeWallSealedCell

private struct TradeWallSealedCell: View {
    let entry: TradeWallView.SealedWallEntry
    let colorScheme: ColorScheme

    var body: some View {
        tradeWallCellChrome(colorScheme: colorScheme) {
            CachedAsyncImage(url: entry.product.imageURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                tradeWallImagePlaceholder(icon: "shippingbox")
            }
            .aspectRatio(5/7, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipped()

            TradeWallCellFooter(
                owner: entry.owner,
                itemName: entry.product.name,
                tag: .inCollection
            )
        }
    }
}

// MARK: - TradeWallSeeAllCell

private struct TradeWallSeeAllCell: View {
    let profile: SocialProfile
    let colorScheme: ColorScheme

    var body: some View {
        tradeWallCellChrome(colorScheme: colorScheme) {
            // Invisible footer rendered underneath to match the exact height of
            // card cells (image area + footer). The ZStack overlays the content
            // centred over both layers.
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.clear)
                        .aspectRatio(5/7, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                    TradeWallCellFooter(
                        owner: profile,
                        itemName: "",
                        tag: .inCollection
                    )
                    .hidden()
                }

                // Visible content centred over the full cell height
                VStack(spacing: 12) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(0.3))

                    VStack(spacing: 3) {
                        Text("See all")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.primary)
                        Text("friends' cards")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.primary)
                    }

                    Image(systemName: "chevron.right.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.primary.opacity(0.25))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - Trade wall cell chrome

@ViewBuilder
private func tradeWallCellChrome<Content: View>(
    colorScheme: ColorScheme,
    @ViewBuilder content: () -> Content
) -> some View {
    VStack(spacing: 0) {
        content()
    }
    .background(.thinMaterial)
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(
                Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.08),
                lineWidth: 0.5
            )
    }
    .shadow(
        color: .black.opacity(colorScheme == .dark ? 0.32 : 0.10),
        radius: 6, x: 0, y: 3
    )
}

private func tradeWallImagePlaceholder(icon: String) -> some View {
    Rectangle()
        .fill(Color.secondary.opacity(0.08))
        .overlay {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.tertiary)
        }
}

// MARK: - TradeWallCellButtonStyle

/// Scale-press feedback without the default opacity flash that `.plain` gives.
private struct TradeWallCellButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
