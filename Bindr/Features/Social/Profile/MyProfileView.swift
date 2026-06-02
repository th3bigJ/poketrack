import SwiftUI
import SwiftData

struct MyProfileView: View {
    enum ProfileTab: String, CaseIterable {
        case posts
        case wishlist
        case tradeList = "trade list"
        case friends
    }

    let profile: SocialProfile
    var selectedTab: Binding<SocialTab>? = nil
    var selectedProfileTab: Binding<ProfileTab>? = nil
    var headerInset: CGFloat = 0
    var onOpenFriendsSearch: (() -> Void)? = nil
    var onOpenFriendsQR: (() -> Void)? = nil
    var onOpenFriendUsername: ((String) -> Void)? = nil
    var onSelectFriendForTrade: ((SocialProfile) -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services
    @Environment(\.colorScheme) private var colorScheme

    @State private var cardCount: Int = 0
    @State private var binderCount: Int = 0
    @State private var deckCount: Int = 0
    @State private var favoriteCard: Card?
    @State private var favoriteCardPrice: Double?
    @State private var myActivity: [SocialFeedService.FeedItem] = []
    @State private var localSelectedProfileTab: ProfileTab = .posts
    @Query(sort: \CollectionItem.dateAcquired, order: .reverse) private var collectionItems: [CollectionItem]
    @Query(sort: \TradeListItem.dateAdded, order: .reverse) private var tradeListItems: [TradeListItem]

    private var tradeListSyncSignature: String {
        tradeListItems
            .map { "\($0.cardID)|\($0.variantKey)|\($0.notes)" }
            .sorted()
            .joined(separator: ";")
    }
    
    private var roleTitles: [String] {
        (profile.profileRoles ?? []).map { role in
            switch role {
            case "collector": return "Collector"
            case "tcg_player": return "TCG Player"
            default: return role.replacingOccurrences(of: "_", with: " ").capitalized
            }
        }
    }

    /// Accent colour driven by the user's chosen avatar background (their
    /// "theme colour"). Falls back to the original gold so anyone who hasn't
    /// picked a colour yet still sees the polished default. Used everywhere
    /// the profile previously hard-coded `#E8B84B` so the screen actually
    /// reflects the user's taste instead of looking the same for everyone.
    private var themeColor: Color {
        if let hex = profile.avatarBackgroundColor, !hex.isEmpty {
            return Color(hex: hex)
        }
        return Color(hex: "E8B84B")
    }

    private var profileTabBinding: Binding<ProfileTab> {
        selectedProfileTab ?? $localSelectedProfileTab
    }

    private var activeProfileTab: ProfileTab {
        profileTabBinding.wrappedValue
    }

    // Prefer local counts on My Profile so totals remain correct
    // when remote profile stats are stale.
    private var displayedCardCount: Int {
        max(cardCount, profile.collectionCardCount ?? 0)
    }

    private var displayedDeckCount: Int {
        max(deckCount, profile.collectionDeckCount ?? 0)
    }

    private var displayedBinderCount: Int {
        max(binderCount, profile.collectionBinderCount ?? 0)
    }

    var body: some View {
        Group {
            if activeProfileTab == .friends {
                VStack(spacing: 0) {
                    profileIntro
                    friendsTabContent
                }
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        profileIntro
                        profileTabContent
                    }
                }
            }
        }
        .refreshable {
            await refreshProfileContent()
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refreshProfileContent()
        }
        .onChange(of: tradeListSyncSignature) { _, _ in
            services.socialCardLibrary.scheduleAutoSyncTradeList(items: tradeListItems)
        }
    }
    
    // MARK: - Subviews

    private var profileIntro: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: headerInset)
            if let selectedTab {
                SlidingSegmentedPicker(
                    selection: selectedTab,
                    items: SocialTab.allCases,
                    title: { $0.title }
                )
                .padding(.horizontal, BindrSpacing.lg)
            }
            VStack(spacing: BindrSpacing.lg) {
                profileHeader
                profileTabPicker
            }
            .padding(.top, BindrSpacing.lg)
        }
    }

    private var profileHeader: some View {
        VStack(alignment: .leading, spacing: BindrSpacing.md) {
            HStack(alignment: .top, spacing: BindrSpacing.md) {
                ZStack(alignment: .bottomTrailing) {
                    ProfileAvatarView(profile: profile, size: 64)
                        .overlay(Circle().stroke(themeColor, lineWidth: 3))
                    Circle()
                        .fill(Color(hex: "52C97C"))
                        .frame(width: 18, height: 18)
                        .overlay(Circle().stroke(Color(uiColor: .systemBackground), lineWidth: 3))
                }

                VStack(alignment: .leading, spacing: BindrSpacing.sm) {
                    HStack(alignment: .center, spacing: BindrSpacing.sm) {
                        Text(profile.displayName ?? profile.username)
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundStyle(Color.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        PremiumBadgeView(profile: profile, size: 14)
                    }
                    if !roleTitles.isEmpty {
                        HStack(spacing: BindrSpacing.sm) {
                            ForEach(roleTitles, id: \.self) { title in
                                rolePill(title)
                            }
                        }
                    }
                }

                Spacer()

            }

            if let bio = profile.bio, !bio.isEmpty {
                Text(bio)
                    .font(.system(size: 13))
                    .lineSpacing(3)
                    .foregroundStyle(Color.secondary)
            }

            HStack(spacing: 0) {
                let friendCount = profile.friendCount ?? 0
                statColumn(value: "\(displayedCardCount)", label: displayedCardCount == 1 ? "Card" : "Cards")
                statColumn(value: "\(displayedDeckCount)", label: displayedDeckCount == 1 ? "Deck" : "Decks")
                statColumn(value: "\(displayedBinderCount)", label: displayedBinderCount == 1 ? "Binder" : "Binders")
                statColumn(value: "\(friendCount)", label: friendCount == 1 ? "Friend" : "Friends")
            }
            .padding(.vertical, BindrSpacing.md)
            .glassCardStyle(cornerRadius: 12, interactive: false)
        }
        .padding(BindrSpacing.lg)
        .background {
            // Layered backdrop driven by the user's theme colour.
            // Both colour layers fade vertically toward `.clear` so the colour
            // never meets the bottom edge of the header with a hard line. The
            // bottom 30% is dedicated to a long, gradual ramp so the
            // transition into the page background reads as a soft glow rather
            // than a stripe that "stops" at the stats row.
            ZStack(alignment: .topTrailing) {
                // Vertical Fade (Main Glow) — smoother multi-stop ramp
                // dedicates the bottom third to a slow fade-out so the
                // gradient eases into the page background instead of cutting
                // off mid-section.
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: themeColor.opacity(0.22), location: 0.30),
                        .init(color: themeColor.opacity(0.16), location: 0.50),
                        .init(color: themeColor.opacity(0.08), location: 0.72),
                        .init(color: themeColor.opacity(0.03), location: 0.88),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Diagonal Beam (replaces the old leading→trailing wash that
                // had no vertical falloff and produced a hard left-side edge
                // at the bottom of the header). Fading topLeading→bottomTrailing
                // means the bottom-left corner naturally fades to clear.
                LinearGradient(
                    stops: [
                        .init(color: themeColor.opacity(0.18), location: 0.0),
                        .init(color: themeColor.opacity(0.06), location: 0.55),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // Favourite card peek below remains as the personalised visual anchor.
                if let imageURL = profile.favoriteCardImageURL,
                   let url = URL(string: imageURL) {
                    CachedAsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color.gray.opacity(0.08)
                    }
                    .frame(width: 64, height: 90)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.white.opacity(0.35), lineWidth: 0.5)
                    }
                    .shadow(color: themeColor.opacity(0.45), radius: 10, x: 0, y: 6)
                    .rotationEffect(.degrees(8))
                    .opacity(0.85)
                    .padding(.top, BindrSpacing.md)
                    .padding(.trailing, BindrSpacing.lg)
                    .allowsHitTesting(false)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.06), lineWidth: 1)
        }
        .padding(.horizontal, BindrSpacing.lg)
    }


    private func profileTabTitle(_ tab: ProfileTab) -> String {
        switch tab {
        case .posts: return "Posts"
        case .wishlist: return "Wishlist"
        case .tradeList: return "Trade List"
        case .friends: return "Friends"
        }
    }

    private var profileTabPicker: some View {
        // Equal-width segmented picker, mirrors the Feed/Friends/Profile bar
        // up top: Title-Case labels, accent-filled active pill, primary text
        // for inactive segments so contrast holds in light mode.
        HStack(spacing: 0) {
            ForEach(ProfileTab.allCases, id: \.self) { tab in
                Button {
                    Haptics.selectionChanged()
                    profileTabBinding.wrappedValue = tab
                } label: {
                    Text(profileTabTitle(tab))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(activeProfileTab == tab ? Color.white : Color.primary.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.vertical, 9)
                        .background(activeProfileTab == tab ? themeColor : .clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(BindrSpacing.xs)
        .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
        .overlay {
            Capsule().stroke(Color.primary.opacity(0.06), lineWidth: 1)
        }
        .padding(.horizontal, BindrSpacing.lg)
    }

    @ViewBuilder
    private var profileTabContent: some View {
        VStack(spacing: BindrSpacing.md) {
            switch activeProfileTab {
            case .posts:
                if groupedActivity.isEmpty {
                    emptyProfileCard("Your shared posts will appear here.")
                } else {
                    ForEach(groupedActivity) { group in
                        FeedItemView(group: group)
                    }
                }
            case .wishlist:
                let ids = (services.wishlist?.items.map(\.cardID) ?? [])
                    .filter(isRenderableCardIDForProfileGrid)
                if ids.isEmpty {
                    emptyProfileCard("Your public wishlist will appear here.")
                } else {
                    WishlistCardGrid(cardIDs: ids, cardLoader: { id in
                        await services.cardData.loadCard(masterCardId: id)
                    })
                }
            case .tradeList:
                let ids = tradeListItems.map(\.cardID).filter(isRenderableCardIDForProfileGrid)
                if ids.isEmpty {
                    emptyProfileCard("Cards you add to your trade list will appear here.")
                } else {
                    WishlistCardGrid(cardIDs: ids, cardLoader: { id in
                        await services.cardData.loadCard(masterCardId: id)
                    })
                }
            case .friends:
                EmptyView()
            }
        }
        .padding(.horizontal, BindrSpacing.lg)
    }

    private var friendsTabContent: some View {
        FriendsListView(
            onOpenSearch: onOpenFriendsSearch ?? {},
            onOpenQR: onOpenFriendsQR ?? {},
            onOpenUsername: onOpenFriendUsername ?? { _ in },
            onSelectFriendForTrade: onSelectFriendForTrade
        )
    }

    private func isRenderableCardIDForProfileGrid(_ cardID: String) -> Bool {
        // Shared profile card grid renders trading cards only.
        // Sealed product ids (e.g. "sealed:pokemon:123") produce permanent placeholders.
        !cardID.hasPrefix("sealed:")
    }

    private func rolePill(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .bold))
            .tracking(0.4)
            .foregroundStyle(themeColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(themeColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(themeColor.opacity(0.19), lineWidth: 1)
            }
    }

    private func statColumn(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Color.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
    }

    private func emptyProfileCard(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Color.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(BindrSpacing.md)
            .glassCardStyle(cornerRadius: 14, interactive: false)
    }
    
    private func favoritePokemonTile(name: String, dex: Int?) -> some View {
        HStack(spacing: 16) {
            // Icon/Sprite
            ZStack {
                Circle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 60, height: 60)
                
                if let urlString = profile.favoritePokemonImageURL, let url = URL(string: urlString) {
                    CachedAsyncImage(url: url) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        ProgressView().scaleEffect(0.8)
                    }
                    .frame(width: 44, height: 44)
                } else {
                    Image(systemName: "hare.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(name)
                        .font(.system(size: 18, weight: .bold))
                    if let dex = dex {
                        Text("#\(String(format: "%03d", dex))")
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                
                // Type Badges (Neutral Glass)
                HStack(spacing: 6) {
                    // We don't have types in the profile easily, 
                    // so we'll show "Pokémon" as a generic tag or try to derive if possible.
                    // For now, let's just show a glass tag as requested.
                    glassTag(text: "Pokémon")
                }
            }
            
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.primary.opacity(0.07), lineWidth: 1)
                )
        )
    }
    
    private func favoriteCardTile(name: String) -> some View {
        HStack(spacing: 16) {
            // Card Thumbnail
            if let imageURL = profile.favoriteCardImageURL, let url = URL(string: imageURL) {
                CachedAsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.gray.opacity(0.1)
                }
                .frame(width: 62, height: 87)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                )
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.system(size: 18, weight: .bold))
                    .lineLimit(1)
                
                if let setCode = profile.favoriteCardSetCode {
                    Text(setCode)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                if let price = favoriteCardPrice {
                    Text(formattedValue(price))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .padding(.top, 2)
                }
            }
            
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.primary.opacity(0.07), lineWidth: 1)
                )
        )
    }
    
    private func glassTag(text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.primary.opacity(0.06))
            )
            .overlay(
                Capsule()
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
    }
    
    private func formattedValue(_ usd: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = services.priceDisplay.currency == .gbp ? "£" : "$"
        let val = services.priceDisplay.currency == .gbp ? usd * services.pricing.usdToGbp : usd
        return formatter.string(from: NSNumber(value: val)) ?? "$0"
    }

    // MARK: - Data Fetching
    
    private func fetchStats() {
        cardCount = (try? modelContext.fetchCount(FetchDescriptor<CollectionItem>())) ?? 0
        binderCount = (try? modelContext.fetchCount(FetchDescriptor<Binder>())) ?? 0
        deckCount = (try? modelContext.fetchCount(FetchDescriptor<Deck>())) ?? 0
    }

    private func refreshProfileContent() async {
        fetchStats()
        if let cardID = profile.favoriteCardID {
            favoriteCard = await services.cardData.loadCard(masterCardId: cardID)
            if let card = favoriteCard {
                favoriteCardPrice = await services.pricing.usdPrice(for: card, printing: "normal")
            } else {
                favoriteCardPrice = nil
            }
        } else {
            favoriteCard = nil
            favoriteCardPrice = nil
        }
        do {
            myActivity = try await services.socialFeed.fetchUserActivity(limit: 10)
        } catch {
            print("Error fetching my activity: \(error)")
        }
        services.socialCardLibrary.scheduleAutoSyncTradeList(items: tradeListItems)
        if let wishlistItems = services.wishlist?.items {
            services.socialCardLibrary.scheduleAutoSyncWishlist(items: wishlistItems)
        }
    }

    // MARK: - Grouping Logic
    
    private var groupedActivity: [GroupedFeedItem] {
        var groups: [GroupedFeedItem] = []
        var contentIndex: [UUID: Int] = [:]

        for item in myActivity {
            switch item.type {
            case .vote, .comment:
                if let contentID = item.content?.id, let idx = contentIndex[contentID] {
                    groups[idx].interactions.append(item)
                    continue
                }
                let group = GroupedFeedItem(id: item.id, primary: item, interactions: [])
                groups.append(group)
            default:
                let group = GroupedFeedItem(id: item.id, primary: item, interactions: [])
                let idx = groups.count
                groups.append(group)
                if let contentID = item.content?.id {
                    contentIndex[contentID] = idx
                }
            }
        }
        return groups
    }
}
