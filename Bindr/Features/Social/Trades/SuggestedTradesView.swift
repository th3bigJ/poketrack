import SwiftUI
import SwiftData

struct SuggestedTradesView: View {
    @Environment(AppServices.self) private var services
    @Binding var navigationPath: NavigationPath
    @Query private var collectionItems: [CollectionItem]

    @State private var suggestions: [TradeSuggestion] = []
    @State private var isLoading = false
    @State private var hasLoaded = false

    var body: some View {
        VStack(spacing: 0) {
            if isLoading && suggestions.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else if suggestions.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(suggestions.prefix(10)) { suggestion in
                        SuggestionRow(
                            suggestion: suggestion,
                            cardLoader: { id in await services.cardData.loadCard(masterCardId: id) }
                        ) {
                            offerTrade(for: suggestion)
                        }
                        Divider().padding(.leading, 72)
                    }
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
        .task { await loadAfterFirstPaint() }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(Color.secondary.opacity(0.4))
            Text("No suggested trades")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Text("Add cards to your wishlist and connect with friends to see matches here.")
                .font(.system(size: 12))
                .foregroundStyle(Color.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func offerTrade(for suggestion: TradeSuggestion) {
        let items = suggestion.matchingCardIDs.map { cardID in
            TradeItem(
                id: UUID(),
                tradeID: UUID(),
                ownerID: suggestion.friend.id,
                cardID: cardID,
                variantKey: "normal",
                quantity: 1,
                createdAt: nil
            )
        }

        switch suggestion.matchType {
        case .theyHaveWhatIWant, .mutual:
            navigationPath.append(SocialDestination.tradeBuilder(
                receiverID: suggestion.friend.id,
                theirCards: items,
                myCards: []
            ))
        case .iHaveWhatTheyWant:
            navigationPath.append(SocialDestination.tradeBuilder(
                receiverID: suggestion.friend.id,
                theirCards: [],
                myCards: items
            ))
        }
    }

    private func loadAfterFirstPaint() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await Task.yield()
        try? await Task.sleep(nanoseconds: 180_000_000)
        await loadSuggestions()
    }

    private func loadSuggestions() async {
        guard case .signedIn = services.socialAuth.authState else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let friends = try await services.socialFriend.fetchFriends()
            guard !friends.isEmpty else { return }

            let friendIDs = friends.map(\.id)

            async let friendWishlists = services.socialCardLibrary.fetchWishlistCardIDsByUser(for: friendIDs)

            let myWishlist = Set<String>(services.wishlist?.items.map(\.cardID) ?? [])
            let friendWishlistMap = try await friendWishlists
            let myOwnedCardIDs = Set<String>(collectionItems.compactMap { item in
                guard item.quantity > 0, !item.cardID.isEmpty else { return nil }
                return item.cardID
            })

            var result: [TradeSuggestion] = []

            for friend in friends {
                let theyWant = Set<String>(friendWishlistMap[friend.id] ?? [])
                let theyWantAndIHave = theyWant.intersection(myOwnedCardIDs)

                if !theyWantAndIHave.isEmpty {
                    result.append(TradeSuggestion(
                        friend: friend,
                        matchType: .iHaveWhatTheyWant,
                        matchingCardIDs: Array(theyWantAndIHave.prefix(5))
                    ))
                }
            }

            // Mutual first, then by type, then by match count
            suggestions = result.sorted {
                if $0.matchType.priority != $1.matchType.priority {
                    return $0.matchType.priority < $1.matchType.priority
                }
                return $0.matchingCardIDs.count > $1.matchingCardIDs.count
            }
        } catch {
            // Non-fatal; suggestions are best-effort
        }
    }
}

private extension TradeSuggestion.MatchType {
    var priority: Int {
        switch self {
        case .mutual: return 0
        case .theyHaveWhatIWant: return 1
        case .iHaveWhatTheyWant: return 2
        }
    }
}

// MARK: - SuggestionRow

private struct SuggestionRow: View {
    let suggestion: TradeSuggestion
    let cardLoader: (String) async -> Card?
    let onOfferTrade: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ProfileAvatarView(profile: suggestion.friend, size: 44)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(suggestion.friend.displayName ?? "@\(suggestion.friend.username)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    matchTypeBadge
                }
                cardThumbnailRow
            }

            Spacer(minLength: 0)

            Button("Offer Trade") {
                Haptics.lightImpact()
                onOfferTrade()
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color(hex: "E8B84B"))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(hex: "E8B84B").opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(Color(hex: "E8B84B").opacity(0.3), lineWidth: 1))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(uiColor: .systemBackground))
    }

    private var matchTypeBadge: some View {
        let (text, color): (String, Color) = switch suggestion.matchType {
        case .mutual: ("Mutual", Color(hex: "52C97C"))
        case .theyHaveWhatIWant: ("They have it", Color(hex: "E8B84B"))
        case .iHaveWhatTheyWant: ("They want it", Color(hex: "5B8CF5"))
        }

        return Text(text)
            .font(.system(size: 9, weight: .bold))
            .tracking(0.3)
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
    }

    private var cardThumbnailRow: some View {
        HStack(spacing: 4) {
            ForEach(suggestion.matchingCardIDs.prefix(3), id: \.self) { cardID in
                SuggestionCardThumb(cardID: cardID, cardLoader: cardLoader)
            }
            if suggestion.matchingCardIDs.count > 3 {
                Text("+\(suggestion.matchingCardIDs.count - 3)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SuggestionCardThumb: View {
    let cardID: String
    let cardLoader: (String) async -> Card?
    @State private var card: Card?

    var body: some View {
        ZStack {
            if let imageURLString = card?.displayImageSrc {
                CachedAsyncImage(url: AppConfiguration.imageURL(relativePath: imageURLString)) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.05))
                }
            } else {
                RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.05))
            }
        }
        .frame(width: 22, height: 31)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .task { card = await cardLoader(cardID) }
    }
}
