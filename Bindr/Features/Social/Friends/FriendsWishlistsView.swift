import SwiftUI

struct FriendsWishlistsView: View {
    @Environment(AppServices.self) private var services

    @State private var friends: [SocialProfile] = []
    @State private var isLoading = false
    @State private var selectedFriend: SocialProfile? = nil

    private var friendsWithWishlists: [SocialProfile] {
        friends.filter { $0.isWishlistPublic == true && !($0.wishlistCardIDs ?? []).isEmpty }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 24) {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else if friendsWithWishlists.isEmpty {
                    emptyState
                } else {
                    ForEach(friendsWithWishlists) { friend in
                        VStack(alignment: .leading, spacing: 10) {
                            friendHeader(friend)
                            ProfileWishlistPreview(
                                cardIDs: friend.wishlistCardIDs ?? [],
                                onViewAllTapped: { selectedFriend = friend },
                                cardLoader: { id in await services.cardData.loadCard(masterCardId: id) },
                                priceFormatter: priceFormatter
                            )
                        }
                    }
                }
            }
            .padding(.vertical, 12)
        }
        .background(Color(uiColor: .systemBackground))
        .sheet(item: $selectedFriend) { friend in
            PublicWishlistDetailView(
                cardIDs: friend.wishlistCardIDs ?? [],
                title: "@\(friend.username)'s Wishlist",
                cardLoader: { id in await services.cardData.loadCard(masterCardId: id) },
                priceFormatter: priceFormatter
            )
            .environment(services)
        }
        .task { await refresh() }
        .refreshable { await refresh() }
    }

    private func friendHeader(_ friend: SocialProfile) -> some View {
        HStack(spacing: 10) {
            ProfileAvatarView(profile: friend, size: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(friend.displayName ?? friend.username)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)
                Text("@\(friend.username)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(friend.wishlistCardIDs?.count ?? 0) cards")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.secondary.opacity(0.7))
        }
        .padding(.horizontal, 20)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart.slash")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.secondary.opacity(0.4))
            Text("No shared wishlists yet")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.secondary)
            Text("Friends can share their wishlist from their profile settings.")
                .font(.system(size: 13))
                .foregroundStyle(Color.secondary.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private var priceFormatter: (Double) -> String {
        { val in
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.currencySymbol = services.priceDisplay.currency == .gbp ? "£" : "$"
            return formatter.string(from: NSNumber(value: val)) ?? "$0"
        }
    }

    private func refresh() async {
        isLoading = true
        defer { isLoading = false }
        friends = (try? await services.socialFriend.fetchFriends()) ?? []
    }
}
