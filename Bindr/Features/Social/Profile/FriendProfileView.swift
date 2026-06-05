import SwiftUI

struct FriendProfileView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    let username: String
    var navigationPath: Binding<NavigationPath>? = nil

    private enum ProfileTab: String, CaseIterable {
        case posts
        case wishlist
        case collection
    }

    @State private var profile: SocialProfile?
    @State private var publicFriendCount: Int?
    @State private var relationship: SocialFriendService.RelationshipState = .none
    @State private var activity: [SocialFeedService.FeedItem] = []
    @State private var isLoading = false
    @State private var isMutating = false
    @State private var errorMessage: String?
    @State private var selectedTab: ProfileTab = .posts
    @State private var sharedWishlistCardIDs: [String] = []
    @State private var friendCollectionCardIDs: [String] = []
    @State private var isLoadingCollection = false
    @State private var collectionLoadError: String? = nil
    @State private var isSelectMode = false
    @State private var selectedCardIDs: Set<String> = []
    @State private var isActionsMenuPresented = false
    @State private var resolvedSharedCardsByID: [String: Card] = [:]
    @State private var cardDetailSession: CardDetailSession?

    private struct CardDetailSession: Identifiable {
        let id = UUID()
        let cards: [Card]
        let startIndex: Int
    }

    private var canViewWishlist: Bool {
        relationship == .friends
    }

    private var showsSelectToolbarButton: Bool {
        (selectedTab == .wishlist || selectedTab == .collection) && canViewWishlist
    }

    var body: some View {
        VStack(spacing: 0) {
            profileTopBar

            Group {
                if isLoading {
                    ProgressView("Loading profile…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let profile {
                    ZStack(alignment: .bottom) {
                        ScrollView {
                            VStack(spacing: 0) {
                                profileHeader(profile)
                                tabPicker
                                    .padding(.top, BindrSpacing.lg)
                                tabContent(profile)
                            }
                            .padding(.top, BindrSpacing.lg)
                            .padding(.bottom, isSelectMode && !selectedCardIDs.isEmpty ? 80 : 32)
                        }
                        .background(Color(uiColor: .systemBackground))

                        if isSelectMode && !selectedCardIDs.isEmpty {
                            offerTradeButton(for: profile)
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "Profile Not Found",
                        systemImage: "person.crop.circle.badge.exclamationmark",
                        description: Text("This username does not exist or is no longer available.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .tint(.primary)
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog("Profile Actions", isPresented: $isActionsMenuPresented, titleVisibility: .visible) {
            if let profile {
                Button("Block User", role: .destructive) {
                    Task { await block(profile.id) }
                }
            }
            Button("Cancel", role: .cancel) { }
        }
        .onChange(of: selectedTab) { _, _ in
            isSelectMode = false
            selectedCardIDs = []
        }
        .onChange(of: relationship) { _, _ in
            Task { @MainActor in
                attemptLaunchPendingSeededTradeIfPossible()
            }
        }
        .onChange(of: profile?.id) { _, _ in
            Task { @MainActor in
                attemptLaunchPendingSeededTradeIfPossible()
            }
        }
        .sheet(item: $cardDetailSession) { session in
            CardDetailSheet(
                cards: session.cards,
                startIndex: session.startIndex,
                tradeAction: (navigationPath != nil && profile != nil) ? { card, _ in
                    offerSingleCardTrade(cardID: card.masterCardId)
                } : nil,
                tradeActionLabel: "Offer Trade"
            )
            .environment(services)
        }
        .task(id: username) { await refresh() }
    }

    /// Friend profile top bar uses ``BindrPageHeader`` so its glass chrome
    /// matches every other page in the app — transparent backdrop, glass
    /// circle buttons, identical paddings.
    private var profileTopBar: some View {
        BindrPageHeader(
            title: "@\(username)",
            leading: {
                ChromeGlassCircleButton(accessibilityLabel: "Back") {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.primary)
                }
            },
            trailing: {
                HStack(spacing: 8) {
                    if showsSelectToolbarButton {
                        ChromeGlassCircleButton(accessibilityLabel: isSelectMode ? "Exit select mode" : "Select cards") {
                            isSelectMode.toggle()
                            if !isSelectMode { selectedCardIDs = [] }
                        } label: {
                            Image(systemName: isSelectMode ? "checkmark.circle.fill" : "checkmark.circle")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(isSelectMode ? Color.blue : Color.primary)
                        }
                    }

                    if profile != nil {
                        ChromeGlassCircleButton(accessibilityLabel: "Profile actions") {
                            Haptics.lightImpact()
                            isActionsMenuPresented = true
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
        )
    }

    // MARK: - Subviews

    private func profileHeader(_ profile: SocialProfile) -> some View {
        let accent = themeColor(for: profile)
        let hasFavoriteCard = favoriteCardImageExists(profile)
        let roleTitles = roleTitles(for: profile)

        return VStack(alignment: .leading, spacing: BindrSpacing.md) {
            HStack(alignment: .top, spacing: BindrSpacing.md) {
                ProfileAvatarView(profile: profile, size: 64)
                    .overlay(Circle().stroke(accent, lineWidth: 3))

                VStack(alignment: .leading, spacing: BindrSpacing.sm) {
                    HStack(alignment: .center, spacing: BindrSpacing.sm) {
                        Text(profile.displayName ?? profile.username)
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundStyle(Color.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        PremiumBadgeView(profile: profile, size: 14)
                    }
                    Text("@\(profile.username)")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.secondary)
                }

                Spacer()
            }
            .padding(.trailing, hasFavoriteCard ? 78 : 0)

            // Full-width so the favourite card can sit above the row without
            // squeezing role/status pills into two-line labels.
            if !roleTitles.isEmpty || hasRelationshipStatusPill {
                HStack(spacing: BindrSpacing.sm) {
                    ForEach(roleTitles, id: \.self) { title in
                        rolePill(title, accent: accent)
                    }
                    relationshipStatusPill
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let bio = profile.bio, !bio.isEmpty {
                Text(bio)
                    .font(.system(size: 13))
                    .lineSpacing(3)
                    .foregroundStyle(Color.secondary)
                    .padding(.trailing, hasFavoriteCard ? 56 : 0)
            }

            // Primary CTA only appears for *actionable* states (Add Friend /
            // Accept request). Passive states like .friends or .blocked are
            // communicated by the status pill above; destructive actions live
            // in the navbar ⋯ menu.
            primaryRelationshipAction(for: profile.id)

            HStack(spacing: 0) {
                let cardCount = profile.collectionCardCount ?? 0
                let deckCount = profile.collectionDeckCount ?? 0
                let binderCount = profile.collectionBinderCount ?? 0
                let friendCount = publicFriendCount ?? profile.friendCount ?? 0
                statColumn(value: "\(cardCount)", label: cardCount == 1 ? "Card" : "Cards")
                statColumn(value: "\(deckCount)", label: deckCount == 1 ? "Deck" : "Decks")
                statColumn(value: "\(binderCount)", label: binderCount == 1 ? "Binder" : "Binders")
                statColumn(value: "\(friendCount)", label: friendCount == 1 ? "Friend" : "Friends")
            }
            .padding(.vertical, BindrSpacing.md)
            .glassCardStyle(cornerRadius: 12, interactive: false)
        }
        .padding(BindrSpacing.lg)
        .background {
            // Layered backdrop driven by the friend's theme colour, favourite
            // Pokémon (faded silhouette behind everything), and favourite
            // card (tilted ghost card peeking from the top-right). Mirrors
            // the personalised look on `MyProfileView` so visiting a friend's
            // profile feels like *their* space, not a stock template.
            ZStack(alignment: .topTrailing) {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: accent.opacity(0.22), location: 0.30),
                        .init(color: accent.opacity(0.16), location: 0.50),
                        .init(color: accent.opacity(0.08), location: 0.72),
                        .init(color: accent.opacity(0.03), location: 0.88),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                LinearGradient(
                    stops: [
                        .init(color: accent.opacity(0.18), location: 0.0),
                        .init(color: accent.opacity(0.06), location: 0.55),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // (Pokémon dex watermark removed — it sat behind the stats
                // bar and looked like a rendering glitch. Favourite card peek
                // below remains as the personalised visual anchor.)

                if let imageURL = profile.favoriteCardImageURL,
                   let url = URL(string: imageURL) {
                    CachedAsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color.gray.opacity(0.08)
                    }
                    .frame(width: 56, height: 78)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.white.opacity(0.35), lineWidth: 0.5)
                    }
                    .shadow(color: accent.opacity(0.45), radius: 10, x: 0, y: 6)
                    .rotationEffect(.degrees(8))
                    .opacity(0.75)
                    .padding(.top, BindrSpacing.sm)
                    .padding(.trailing, BindrSpacing.xl)
                    .allowsHitTesting(false)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        }
        .padding(.horizontal, BindrSpacing.lg)
    }

    private func favoriteCardImageExists(_ profile: SocialProfile) -> Bool {
        guard let imageURL = profile.favoriteCardImageURL else { return false }
        return URL(string: imageURL) != nil
    }

    /// Accent colour driven by the friend's chosen avatar background. Falls
    /// back to the original gold for friends who haven't picked one. Threaded
    /// through everywhere the view previously hard-coded `#E8B84B`. Reads
    /// from `profile` so helper subviews (`rolePill`, `infoRow`,
    /// `primaryRelationshipAction`, etc.) can pick it up without each one
    /// taking an arg.
    private var accentColor: Color {
        if let hex = profile?.avatarBackgroundColor, !hex.isEmpty {
            return Color(hex: hex)
        }
        return Color(hex: "E8B84B")
    }

    private func themeColor(for profile: SocialProfile) -> Color {
        if let hex = profile.avatarBackgroundColor, !hex.isEmpty {
            return Color(hex: hex)
        }
        return Color(hex: "E8B84B")
    }

    /// `true` when `relationshipStatusPill` will actually render a pill
    /// (used by the role row to know whether to add itself to the layout).
    private var hasRelationshipStatusPill: Bool {
        switch relationship {
        case .none: return false
        case .friends, .pendingOutgoing, .pendingIncoming, .blocked: return true
        }
    }

    /// Compact passive indicator that lives next to the role pills. Renders
    /// nothing for `.none` so the role row doesn't show an empty trailing pill.
    @ViewBuilder
    private var relationshipStatusPill: some View {
        switch relationship {
        case .friends:
            statusPill(text: "Friends", systemImage: "checkmark", color: Color(hex: "52C97C"))
        case .pendingOutgoing:
            statusPill(text: "Pending", systemImage: "clock", color: Color.secondary)
        case .pendingIncoming:
            statusPill(text: "Wants to connect", systemImage: "person.crop.circle.badge.plus", color: accentColor)
        case .blocked:
            statusPill(text: "Blocked", systemImage: "hand.raised.fill", color: Color(hex: "E05252"))
        case .none:
            EmptyView()
        }
    }

    private func statusPill(text: String, systemImage: String, color: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.system(size: 10, weight: .bold))
            .tracking(0.3)
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(color.opacity(0.22), lineWidth: 1)
            }
    }

    /// Renders a primary action (Add Friend / Accept + Decline) below the bio
    /// only when the relationship needs the user to do something. Friend /
    /// blocked / outgoing-pending states render nothing here; they're
    /// communicated by `relationshipStatusPill` instead.
    @ViewBuilder
    private func primaryRelationshipAction(for userID: UUID) -> some View {
        switch relationship {
        case .none:
            Button {
                Task { await sendRequest(to: userID) }
            } label: {
                Label("Add Friend", systemImage: "person.crop.circle.badge.plus")
                    .font(.system(size: 14, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(accentColor, in: Capsule())
                    .foregroundStyle(.black)
            }
            .buttonStyle(.plain)
            .disabled(isMutating)
        case .pendingIncoming(let friendshipID):
            HStack(spacing: 10) {
                Button {
                    Task { await respond(to: friendshipID, accepted: true) }
                } label: {
                    Text("Accept")
                        .font(.system(size: 14, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(accentColor, in: Capsule())
                        .foregroundStyle(.black)
                }
                .buttonStyle(.plain)
                .disabled(isMutating)
                Button {
                    Task { await respond(to: friendshipID, accepted: false) }
                } label: {
                    Text("Decline")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Color(uiColor: .tertiarySystemBackground), in: Capsule())
                        .foregroundStyle(.primary)
                        .overlay {
                            Capsule().stroke(Color.primary.opacity(0.12), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .disabled(isMutating)
            }
        case .friends, .pendingOutgoing, .blocked:
            EmptyView()
        }
    }

    /// Title-cased label for the sub-tabs. Driven off the `ProfileTab` enum's
    /// `rawValue` so adding a new tab automatically picks up the formatting.
    private func tabTitle(_ tab: ProfileTab) -> String {
        switch tab {
        case .posts: return "Posts"
        case .wishlist: return "Wishlist"
        case .collection: return "Collection"
        }
    }

    private var tabPicker: some View {
        // Equal-width segmented bar that mirrors the top-level Feed/Friends/
        // Profile picker treatment: Title Case, accent-filled active pill,
        // primary-colour inactive text so contrast holds in light mode.
        HStack(spacing: 0) {
            ForEach(ProfileTab.allCases, id: \.self) { tab in
                Button {
                    Haptics.selectionChanged()
                    selectedTab = tab
                } label: {
                    Text(tabTitle(tab))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(selectedTab == tab ? Color.white : Color.primary.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(selectedTab == tab ? accentColor : .clear, in: Capsule())
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
    private func tabContent(_ profile: SocialProfile) -> some View {
        VStack(spacing: BindrSpacing.md) {
            switch selectedTab {
            case .posts:
                if groupedActivity.isEmpty {
                    emptyCard("No shared posts yet.")
                } else {
                    ForEach(groupedActivity) { group in
                        FeedItemView(group: group)
                    }
                }
            case .wishlist:
                let ids = resolvedWishlistCardIDs()
                if canViewWishlist, !ids.isEmpty {
                    SelectableCardGrid(
                        cardIDs: ids,
                        isSelectMode: $isSelectMode,
                        selectedCardIDs: $selectedCardIDs,
                        cardLoader: { id in await loadSharedCard(id) },
                        onCardTap: { tappedID in
                            Task { await openCardDetail(tappedID: tappedID, orderedIDs: ids) }
                        }
                    )
                } else if !canViewWishlist {
                    emptyCard("This user's wishlist is private.")
                } else {
                    emptyCard("No wishlist items yet.")
                }
            case .collection:
                if !canViewWishlist {
                    emptyCard("Become friends to view this user's collection.")
                } else if isLoadingCollection {
                    ProgressView("Loading collection…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else if let error = collectionLoadError {
                    emptyCard("Couldn't load collection: \(error)")
                } else if friendCollectionCardIDs.isEmpty {
                    emptyCard("This friend hasn't synced their collection yet.")
                } else {
                    SelectableCardGrid(
                        cardIDs: friendCollectionCardIDs,
                        isSelectMode: $isSelectMode,
                        selectedCardIDs: $selectedCardIDs,
                        cardLoader: { id in await loadSharedCard(id) },
                        onCardTap: { tappedID in
                            Task { await openCardDetail(tappedID: tappedID, orderedIDs: friendCollectionCardIDs) }
                        }
                    )
                }
            }
        }
        .padding(.top, BindrSpacing.xl)
        .padding(.horizontal, BindrSpacing.lg)
    }

    // MARK: - Helpers

    private func rolePill(_ title: String, accent: Color? = nil) -> some View {
        let tint = accent ?? accentColor
        return Text(title.uppercased())
            .font(.system(size: 10, weight: .bold))
            .tracking(0.4)
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(tint.opacity(0.19), lineWidth: 1)
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

    private func offerTradeButton(for profile: SocialProfile) -> some View {
        Button {
            let items = selectedCardIDs.map { cardID in
                TradeItem(
                    id: UUID(),
                    tradeID: UUID(),
                    ownerID: profile.id,
                    cardID: cardID,
                    variantKey: "normal",
                    quantity: 1,
                    createdAt: nil
                )
            }
            let (theirCards, myCards) = prefills(for: items, sourceTab: selectedTab)
            isSelectMode = false
            selectedCardIDs = []
            navigationPath?.wrappedValue.append(SocialDestination.tradeBuilder(
                receiverID: profile.id,
                theirCards: theirCards,
                myCards: myCards
            ))
        } label: {
            Text("Offer Trade (\(selectedCardIDs.count))")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(accentColor, in: Capsule())
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .background(
            LinearGradient(
                colors: [Color(uiColor: .systemBackground).opacity(0), Color(uiColor: .systemBackground)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func emptyCard(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Color.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(BindrSpacing.md)
            .glassCardStyle(cornerRadius: 14, interactive: false)
    }

    private func roleTitles(for profile: SocialProfile) -> [String] {
        (profile.profileRoles ?? []).map { role in
            switch role {
            case "collector": return "Collector"
            case "tcg_player": return "TCG Player"
            default: return role.replacingOccurrences(of: "_", with: " ").capitalized
            }
        }
    }

    private var groupedActivity: [GroupedFeedItem] {
        var groups: [GroupedFeedItem] = []
        var contentIndex: [UUID: Int] = [:]
        for item in activity {
            switch item.type {
            case .vote, .comment:
                if let contentID = item.content?.id, let idx = contentIndex[contentID] {
                    groups[idx].interactions.append(item)
                    continue
                }
                groups.append(GroupedFeedItem(id: item.id, primary: item, interactions: []))
            default:
                let idx = groups.count
                groups.append(GroupedFeedItem(id: item.id, primary: item, interactions: []))
                if let contentID = item.content?.id {
                    contentIndex[contentID] = idx
                }
            }
        }
        return groups
    }

    // MARK: - Data

    private func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await services.socialFriend.fetchProfile(username: username)
            profile = loaded
            if let loaded {
                async let rel = services.socialFriend.fetchRelationshipState(for: loaded.id)
                async let posts = services.socialFeed.fetchActivityForUser(userID: loaded.id, limit: 20)
                async let friendCounts = services.socialFriend.fetchPublicFriendCounts(for: [loaded.id])
                relationship = try await rel
                activity = (try? await posts) ?? []
                publicFriendCount = (try? await friendCounts)?[loaded.id]
                if relationship == .friends {
                    async let wishlistIDs = services.socialCardLibrary.fetchWishlistCardIDs(for: loaded.id)
                    sharedWishlistCardIDs = (try? await wishlistIDs) ?? []
                    Task { @MainActor in
                        await warmSharedCardCache(ids: sharedWishlistCardIDs)
                    }
                    Task { @MainActor in
                        await loadFriendCollection(userID: loaded.id)
                    }
                } else {
                    sharedWishlistCardIDs = []
                    friendCollectionCardIDs = []
                    resolvedSharedCardsByID = [:]
                }
            }
            errorMessage = nil
            if loaded == nil {
                publicFriendCount = nil
            }
        } catch is CancellationError {
            // Ignore
        } catch let error as URLError where error.code == .cancelled {
            // Ignore
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadFriendCollection(userID: UUID) async {
        guard !isLoadingCollection else { return }
        isLoadingCollection = true
        collectionLoadError = nil
        defer { isLoadingCollection = false }
        do {
            let snapshot = try await services.collectionSync.fetchFriendCollection(userID: userID)
            let ids = snapshot.collection.compactMap { entry -> String? in
                guard !entry.cardID.isEmpty else { return nil }
                return entry.cardID
            }
            friendCollectionCardIDs = ids
            Task { @MainActor in
                await warmSharedCardCache(ids: ids)
            }
        } catch CollectionSyncError.httpError(404) {
            friendCollectionCardIDs = []
        } catch {
            collectionLoadError = error.localizedDescription
        }
    }

    private func sendRequest(to userID: UUID) async {
        Haptics.mediumImpact()
        isMutating = true
        defer { isMutating = false }
        do {
            try await services.socialFriend.sendRequest(to: userID)
            relationship = try await services.socialFriend.fetchRelationshipState(for: userID)
            Haptics.success()
        } catch {
            errorMessage = error.localizedDescription
            Haptics.error()
        }
    }

    private func respond(to friendshipID: UUID, accepted: Bool) async {
        Haptics.mediumImpact()
        isMutating = true
        defer { isMutating = false }
        do {
            try await services.socialFriend.respond(to: friendshipID, accepted: accepted)
            relationship = accepted ? .friends : .none
            if accepted { Haptics.success() }
        } catch {
            errorMessage = error.localizedDescription
            Haptics.error()
        }
    }

    private func block(_ userID: UUID) async {
        isMutating = true
        defer { isMutating = false }
        do {
            try await services.socialFriend.block(userID: userID)
            relationship = .blocked
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resolvedWishlistCardIDs() -> [String] {
        sharedWishlistCardIDs.filter { !$0.isEmpty }
    }

    @MainActor
    private func openCardDetail(tappedID: String, orderedIDs: [String]) async {
        guard !isSelectMode else { return }
        _ = await loadSharedCard(tappedID)
        let orderedCards = orderedIDs.compactMap { resolvedSharedCardsByID[$0] }
        guard let startIndex = orderedCards.firstIndex(where: { $0.masterCardId == tappedID }) else { return }
        cardDetailSession = CardDetailSession(cards: orderedCards, startIndex: startIndex)
    }

    @MainActor
    private func loadSharedCard(_ cardID: String) async -> Card? {
        if let cached = resolvedSharedCardsByID[cardID] {
            return cached
        }
        guard let loaded = await services.cardData.loadCard(masterCardId: cardID) else {
            return nil
        }
        resolvedSharedCardsByID[cardID] = loaded
        return loaded
    }

    @MainActor
    private func warmSharedCardCache(ids: [String]) async {
        for id in ids where resolvedSharedCardsByID[id] == nil {
            _ = await loadSharedCard(id)
        }
    }

    @MainActor
    private func offerSingleCardTrade(cardID: String) {
        guard let profile else { return }
        guard navigationPath != nil else { return }
        cardDetailSession = nil
        let item = TradeItem(
            id: UUID(),
            tradeID: UUID(),
            ownerID: profile.id,
            cardID: cardID,
            variantKey: "normal",
            quantity: 1,
            createdAt: nil
        )
        let (theirCards, myCards) = prefills(for: [item], sourceTab: selectedTab)
        navigationPath?.wrappedValue.append(
            SocialDestination.tradeBuilder(
                receiverID: profile.id,
                theirCards: theirCards,
                myCards: myCards
            )
        )
    }

    @MainActor
    private func attemptLaunchPendingSeededTradeIfPossible() {
        guard navigationPath != nil else { return }
        guard relationship == .friends else { return }
        guard let profile else { return }
        guard let seed = services.pendingTradeSeed else { return }

        let item = TradeItem(
            id: UUID(),
            tradeID: UUID(),
            ownerID: profile.id,
            cardID: seed.cardID,
            variantKey: "normal",
            quantity: 1,
            createdAt: nil
        )
        let (theirCards, myCards): ([TradeItem], [TradeItem]) = {
            switch seed.preferredSide {
            case .mySide:
                return ([], [item])
            case .theirSide:
                return ([item], [])
            }
        }()
        services.pendingTradeSeed = nil
        navigationPath?.wrappedValue.append(
            SocialDestination.tradeBuilder(
                receiverID: profile.id,
                theirCards: theirCards,
                myCards: myCards
            )
        )
    }

    private func prefills(for items: [TradeItem], sourceTab: ProfileTab) -> (theirCards: [TradeItem], myCards: [TradeItem]) {
        switch sourceTab {
        case .wishlist:
            // Tapping Trade on their wishlist: "I'll offer this"
            return ([], items)
        case .collection:
            // Tapping Trade on their collection: "I want this from them"
            return (items, [])
        case .posts:
            return (items, [])
        }
    }
}
