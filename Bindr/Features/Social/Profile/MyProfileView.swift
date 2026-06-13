import SwiftUI
import SwiftData

struct MyProfileView: View {
    enum ProfileTab: String, CaseIterable, Identifiable {
        case posts
        case wishlist
        case collection
        case friends

        var id: String { rawValue }
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
    @Environment(\.presentCard) private var presentCard

    @Namespace private var profileTabNamespace

    @State private var cardCount: Int = 0
    @State private var binderCount: Int = 0
    @State private var deckCount: Int = 0
    @State private var acceptedFriendCount: Int?
    @State private var myActivity: [SocialFeedService.FeedItem] = []
    @State private var localSelectedProfileTab: ProfileTab = .posts
    @State private var isProfileCardSelectMode = false
    @State private var selectedProfileCardIDs: Set<String> = []
    @State private var profileCardsByID: [String: Card] = [:]

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
        let tab = profileTabBinding.wrappedValue
        return availableProfileTabs.contains(tab) ? tab : .posts
    }

    private var availableProfileTabs: [ProfileTab] {
        [.posts, .wishlist]
    }

    private var profileTabContentTopGap: CGFloat {
        BindrSpacing.xl
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

    private var displayedFriendCount: Int {
        acceptedFriendCount ?? profile.friendCount ?? 0
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                profileIntro
                profileTabContent
            }
        }
        .refreshable {
            await refreshProfileContent()
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refreshProfileContent()
        }
        .onAppear {
            normalizeProfileTab()
        }
        .onChange(of: activeProfileTab) { _, _ in
            normalizeProfileTab()
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
                    ProfileAvatarView(profile: profile, size: 72)
                        .clipShape(Circle())
                        .shadow(color: themeColor.opacity(0.35), radius: 8, x: 0, y: 4)
                        .overlay(Circle().stroke(themeColor, lineWidth: 2))
                        .padding(2)
                        .overlay(Circle().stroke(themeColor.opacity(0.2), lineWidth: 1))
                    Circle()
                        .fill(Color(hex: "52C97C"))
                        .frame(width: 18, height: 18)
                        .overlay(Circle().stroke(Color(uiColor: .systemBackground), lineWidth: 2.5))
                        .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .center, spacing: BindrSpacing.sm) {
                        Text(profile.displayName ?? profile.username)
                            .font(.system(size: 20, weight: .black))
                            .tracking(-0.3)
                            .foregroundStyle(Color.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        PremiumBadgeView(profile: profile, size: 14)
                    }
                    Text("@\(profile.username)")
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.medium)
                        .foregroundStyle(Color.secondary.opacity(0.8))
                }

                Spacer()
            }

            if !roleTitles.isEmpty {
                HStack(spacing: BindrSpacing.sm) {
                    ForEach(roleTitles, id: \.self) { title in
                        rolePill(title)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let bio = profile.bio, !bio.isEmpty {
                Text(bio)
                    .font(.system(size: 13, weight: .regular))
                    .lineSpacing(4)
                    .foregroundStyle(Color.primary.opacity(0.85))
            }

            HStack(spacing: 0) {
                let friendCount = displayedFriendCount
                
                statButton(value: "\(displayedCardCount)", label: displayedCardCount == 1 ? "Card" : "Cards") {
                    Haptics.lightImpact()
                }
                
                Divider()
                    .frame(height: 24)
                    .background(Color.primary.opacity(0.08))
                
                statButton(value: "\(displayedDeckCount)", label: displayedDeckCount == 1 ? "Deck" : "Decks") {
                    Haptics.lightImpact()
                }
                
                Divider()
                    .frame(height: 24)
                    .background(Color.primary.opacity(0.08))
                
                statButton(value: "\(displayedBinderCount)", label: displayedBinderCount == 1 ? "Binder" : "Binders") {
                    Haptics.lightImpact()
                }
                
                Divider()
                    .frame(height: 24)
                    .background(Color.primary.opacity(0.08))
                
                statButton(value: "\(friendCount)", label: friendCount == 1 ? "Friend" : "Friends") {
                    if let selectedTab {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            selectedTab.wrappedValue = .friends
                        }
                        Haptics.selectionChanged()
                    } else {
                        Haptics.lightImpact()
                    }
                }
            }
            .padding(.vertical, 4)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
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
        case .collection: return "Collection"
        case .friends: return "Friends"
        }
    }

    private var profileTabPicker: some View {
        HStack(spacing: 0) {
            ForEach(availableProfileTabs, id: \.self) { tab in
                let isSelected = activeProfileTab == tab
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        profileTabBinding.wrappedValue = tab
                    }
                    Haptics.lightImpact()
                } label: {
                    Text(profileTabTitle(tab))
                        .font(.system(size: 13, weight: isSelected ? .bold : .semibold))
                        .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.vertical, 9)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(themeColor)
                                    .matchedGeometryEffect(id: "profileTabHighlight", in: profileTabNamespace)
                                    .shadow(color: themeColor.opacity(0.25), radius: 6, x: 0, y: 3)
                            }
                        }
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
                    SelectableCardGrid(
                        cardIDs: ids,
                        isSelectMode: $isProfileCardSelectMode,
                        selectedCardIDs: $selectedProfileCardIDs,
                        cardLoader: { id in await loadProfileCard(id) },
                        onCardTap: { tappedID in
                            Task { await openProfileCardDetail(tappedID: tappedID, orderedIDs: ids) }
                        }
                    )
                }
            case .collection:
                EmptyView()
            case .friends:
                friendsTabContent
            }
        }
        .padding(.top, profileTabContentTopGap)
        .padding(.horizontal, BindrSpacing.lg)
    }

    private func normalizeProfileTab() {
        if profileTabBinding.wrappedValue == .collection {
            profileTabBinding.wrappedValue = .posts
        }
    }

    private func isRenderableCardIDForProfileGrid(_ cardID: String) -> Bool {
        // Shared profile card grid renders trading cards only.
        // Sealed product ids (e.g. "sealed:pokemon:123") produce permanent placeholders.
        !cardID.hasPrefix("sealed:")
    }

    @MainActor
    private func loadProfileCard(_ cardID: String) async -> Card? {
        if let cached = profileCardsByID[cardID] {
            return cached
        }
        guard let loaded = await services.cardData.loadCard(masterCardId: cardID) else {
            return nil
        }
        profileCardsByID[cardID] = loaded
        return loaded
    }

    @MainActor
    private func openProfileCardDetail(tappedID: String, orderedIDs: [String]) async {
        guard !isProfileCardSelectMode else { return }
        _ = await loadProfileCard(tappedID)
        guard let tappedCard = profileCardsByID[tappedID] else { return }
        let orderedCards = orderedIDs.compactMap { profileCardsByID[$0] }
        presentCard(tappedCard, orderedCards.isEmpty ? [tappedCard] : orderedCards)
    }

    private func rolePill(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 9, weight: .bold))
            .tracking(1.0)
            .foregroundStyle(themeColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(themeColor.opacity(0.08))
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(themeColor.opacity(0.2), lineWidth: 1)
            }
    }

    private func statButton(value: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(value)
                    .font(.system(size: 17, weight: .black))
                    .foregroundStyle(.primary)
                Text(label)
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(.secondary.opacity(0.8))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(StatButtonStyle())
    }

    private var friendsTabContent: some View {
        FriendsListView(
            onOpenSearch: onOpenFriendsSearch ?? {},
            onOpenQR: onOpenFriendsQR ?? {},
            onOpenUsername: onOpenFriendUsername ?? { _ in },
            onSelectFriendForTrade: onSelectFriendForTrade,
            embedInParentScrollView: true
        )
        .padding(.top, profileTabContentTopGap)
    }

    private func emptyProfileCard(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Color.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(BindrSpacing.md)
            .glassCardStyle(cornerRadius: 14, interactive: false)
    }
    
    // MARK: - Data Fetching
    
    private func fetchStats() {
        cardCount = modelContext.collectionTotalCardQuantity()
        binderCount = (try? modelContext.fetchCount(FetchDescriptor<Binder>())) ?? 0
        deckCount = (try? modelContext.fetchCount(FetchDescriptor<Deck>())) ?? 0
    }

    private func refreshProfileContent() async {
        fetchStats()
        myActivity = (try? await services.socialFeed.fetchActivityForUser(userID: profile.id, limit: 50)) ?? []
        acceptedFriendCount = try? await services.socialFriend.fetchAcceptedFriendCount(for: profile.id)
    }

    // MARK: - Grouping Logic
    
    private var groupedActivity: [GroupedFeedItem] {
        myActivity.map { GroupedFeedItem(id: $0.id, primary: $0, interactions: []) }
    }
}

private struct StatButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.primary.opacity(0.05) : Color.clear)
            .contentShape(Rectangle())
    }
}
