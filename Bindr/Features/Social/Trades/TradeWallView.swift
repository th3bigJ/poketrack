import SwiftUI
import SwiftData

struct TradeWallView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.bindrAccent) private var accent
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
                directTradeContext: tradeWallTradeContext(for: session)
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
        EagerVGrid(items: gridItems, columns: 3, spacing: BindrSpacing.cardGrid) { item in
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
                    TradeWallSuggestedCell(entry: entry)
                }
                .buttonStyle(TradeWallCellButtonStyle())

            case .card(let entry):
                Button {
                    Haptics.lightImpact()
                    cardDetailSession = CardDetailSession(card: entry.card, owner: entry.owner, matchType: nil)
                } label: {
                    TradeWallCardCell(entry: entry)
                }
                .buttonStyle(TradeWallCellButtonStyle())

            case .sealed(let entry):
                Button {
                    Haptics.lightImpact()
                    selectedSealedProduct = entry.product
                } label: {
                    TradeWallSealedCell(entry: entry)
                }
                .buttonStyle(TradeWallCellButtonStyle())

            case .seeAll(let profile):
                Button {
                    Haptics.lightImpact()
                    navigationPath.append(SocialDestination.friendsCollection)
                } label: {
                    TradeWallSeeAllCell(profile: profile)
                }
                .buttonStyle(TradeWallCellButtonStyle())
            }
        }
        .padding(.horizontal, BindrSpacing.cardGridScreenInset)
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
                Text("Suggested matches, wishlist opportunities, and cards your friends have marked available will appear here.")
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

    private func tradeWallTradeContext(for session: CardDetailSession) -> CardTradeContext {
        let name = session.owner.shortDisplayName
        let message: String = {
            switch session.matchType {
            case .iHaveWhatTheyWant:
                return "\(name) wants this card"
            case .theyHaveWhatIWant, .mutual:
                return "\(name) has this card"
            case .none:
                return "\(name) has this card"
            }
        }()
        return CardTradeContext(message: message) { card in
            startTrade(card: card, with: session.owner, matchType: session.matchType)
        }
    }

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
    let tag: TradeWallStatusTag

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 7) {
                ProfileAvatarView(profile: owner, size: 24)
                    .overlay(
                        Circle().stroke(Color.primary.opacity(0.10), lineWidth: 1)
                    )

                Text(owner.displayName ?? owner.username)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            TradeWallStatusBadge(tag: tag)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

@ViewBuilder
private func tradeWallItemHeader(name: String, setName: String? = nil) -> some View {
    VStack(alignment: .leading, spacing: 1) {
        Text(name)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundStyle(.primary)

        if let setName, !setName.isEmpty {
            Text(setName)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.secondary)
        }
    }
    .multilineTextAlignment(.leading)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 8)
    .padding(.bottom, 4)
}

@ViewBuilder
private func tradeWallCardImage(url: URL?, placeholderIcon: String) -> some View {
    CachedAsyncImage(url: url) { image in
        image
            .resizable()
            .scaledToFit()
    } placeholder: {
        tradeWallImagePlaceholder(icon: placeholderIcon)
    }
    .aspectRatio(5/7, contentMode: .fit)
    .frame(maxWidth: .infinity)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
}

// MARK: - TradeWallSuggestedCell

private struct TradeWallSuggestedCell: View {
    let entry: TradeWallView.SuggestedWallEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            tradeWallItemHeader(name: entry.card.cardName)

            tradeWallCardImage(
                url: AppConfiguration.imageURL(relativePath: entry.card.displayImageSrc),
                placeholderIcon: "photo"
            )

            TradeWallCellFooter(
                owner: entry.owner,
                tag: .suggested(entry.matchType)
            )
        }
        .padding(.bottom, BindrSpacing.xs)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - TradeWallCardCell

/// Compact trade wall cell for the 3-column grid.
private struct TradeWallCardCell: View {
    let entry: TradeWallView.WallEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            tradeWallItemHeader(name: entry.card.cardName, setName: entry.setName)

            tradeWallCardImage(
                url: AppConfiguration.imageURL(relativePath: entry.card.displayImageSrc),
                placeholderIcon: "photo"
            )

            TradeWallCellFooter(
                owner: entry.owner,
                tag: .inCollection
            )
        }
        .padding(.bottom, BindrSpacing.xs)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - TradeWallSealedCell

private struct TradeWallSealedCell: View {
    let entry: TradeWallView.SealedWallEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            tradeWallItemHeader(name: entry.product.name, setName: entry.product.setName)

            tradeWallCardImage(url: entry.product.imageURL, placeholderIcon: "shippingbox")

            TradeWallCellFooter(
                owner: entry.owner,
                tag: .inCollection
            )
        }
        .padding(.bottom, BindrSpacing.xs)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - TradeWallSeeAllCell

private struct TradeWallSeeAllCell: View {
    let profile: SocialProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            tradeWallItemHeader(name: "See all", setName: "friends' cards")

            ZStack {
                tradeWallImagePlaceholder(icon: "person.2.fill")
                    .aspectRatio(5/7, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(spacing: 8) {
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.primary.opacity(0.28))
                }
            }

            TradeWallCellFooter(owner: profile, tag: .inCollection)
                .hidden()
        }
        .padding(.bottom, BindrSpacing.xs)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Trade wall placeholders

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
