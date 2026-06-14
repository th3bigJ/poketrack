import SwiftUI

struct FriendProfileView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    let username: String
    var navigationPath: Binding<NavigationPath>? = nil
    var initialTab: ProfileTab = .posts

    init(username: String, navigationPath: Binding<NavigationPath>? = nil, initialTab: ProfileTab = .posts) {
        self.username = username
        self.navigationPath = navigationPath
        self.initialTab = initialTab
        _selectedTab = State(initialValue: initialTab)
    }

    enum ProfileTab: String, CaseIterable {
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
    @State private var selectedTab: ProfileTab
    @Namespace private var tabNamespace
    @State private var sharedWishlistCardIDs: [String] = []
    @State private var friendCollectionCardIDs: [String] = []
    @State private var isLoadingCollection = false
    @State private var collectionLoadError: String? = nil
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

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading profile…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let profile {
                ScrollView {
                    VStack(spacing: 0) {
                        profileHeader(profile)
                        tabPicker
                            .padding(.top, BindrSpacing.lg)
                        tabContent(profile)
                    }
                    .padding(.top, BindrSpacing.lg)
                    .padding(.bottom, 32)
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
        .background(BindrPageBackground().ignoresSafeArea())
        .tint(.primary)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            profileTopBar
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
                directTradeContext: friendCardTradeContext()
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
                if let profile {
                    profileActionsMenu(for: profile)
                }
            }
        )
    }

    /// Liquid Glass menu anchored to the ellipsis button — expands from the
    /// chrome control instead of a bottom confirmation sheet.
    private func profileActionsMenu(for profile: SocialProfile) -> some View {
        Menu {
            if relationship == .friends {
                Button {
                    Haptics.mediumImpact()
                    Task { await unfriend(profile.id) }
                } label: {
                    Label("Unfriend", systemImage: "person.badge.minus")
                        .foregroundStyle(.white)
                }
            }

            Button {
                Haptics.mediumImpact()
                Task { await block(profile.id) }
            } label: {
                Label("Block User", systemImage: "hand.raised.fill")
                    .foregroundStyle(.white)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.primary)
                .modifier(ChromeGlassCircleGlyphModifier())
        }
        .buttonStyle(.plain)
        .menuOrder(.fixed)
        .menuIndicator(.hidden)
        .frame(width: 48, height: 48)
        .contentShape(Rectangle())
        .accessibilityLabel("Profile actions")
    }

    // MARK: - Subviews

    private func profileHeader(_ profile: SocialProfile) -> some View {
        let accent = themeColor(for: profile)
        let hasFavoriteCard = favoriteCardImageExists(profile)
        let roleTitles = roleTitles(for: profile)

        return VStack(alignment: .leading, spacing: BindrSpacing.md) {
            HStack(alignment: .top, spacing: BindrSpacing.md) {
                ZStack(alignment: .bottomTrailing) {
                    ProfileAvatarView(profile: profile, size: 72)
                        .clipShape(Circle())
                        .shadow(color: accent.opacity(0.35), radius: 8, x: 0, y: 4)
                        .overlay(Circle().stroke(accent, lineWidth: 2))
                        .padding(2)
                        .overlay(Circle().stroke(accent.opacity(0.2), lineWidth: 1))
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
                
                statBlock(value: "\(cardCount)", label: cardCount == 1 ? "Card" : "Cards")
                
                Divider()
                    .frame(height: 24)
                    .background(Color.primary.opacity(0.08))
                
                statBlock(value: "\(deckCount)", label: deckCount == 1 ? "Deck" : "Decks")
                
                Divider()
                    .frame(height: 24)
                    .background(Color.primary.opacity(0.08))
                
                statBlock(value: "\(binderCount)", label: binderCount == 1 ? "Binder" : "Binders")
                
                Divider()
                    .frame(height: 24)
                    .background(Color.primary.opacity(0.08))
                
                statBlock(value: "\(friendCount)", label: friendCount == 1 ? "Friend" : "Friends")
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
        HStack(spacing: 0) {
            ForEach(ProfileTab.allCases, id: \.self) { tab in
                let isSelected = selectedTab == tab
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        selectedTab = tab
                    }
                    Haptics.lightImpact()
                } label: {
                    Text(tabTitle(tab))
                        .font(.system(size: 13, weight: isSelected ? .bold : .semibold))
                        .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(accentColor)
                                    .matchedGeometryEffect(id: "friendProfileTabHighlight", in: tabNamespace)
                                    .shadow(color: accentColor.opacity(0.25), radius: 6, x: 0, y: 3)
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
                        isSelectMode: .constant(false),
                        selectedCardIDs: .constant([]),
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
                        isSelectMode: .constant(false),
                        selectedCardIDs: .constant([]),
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
            .font(.system(size: 9, weight: .bold))
            .tracking(1.0)
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(tint.opacity(0.08))
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(tint.opacity(0.2), lineWidth: 1)
            }
    }

    private func statBlock(value: String, label: String) -> some View {
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
            let collectionIDs = snapshot.collection.compactMap { entry -> String? in
                guard !entry.cardID.isEmpty else { return nil }
                return entry.cardID
            }
            let wishlistIDs = snapshot.wishlist.compactMap { entry -> String? in
                guard !entry.cardID.isEmpty else { return nil }
                return entry.cardID
            }
            friendCollectionCardIDs = collectionIDs
            sharedWishlistCardIDs = wishlistIDs
            Task { @MainActor in
                await warmSharedCardCache(ids: collectionIDs + wishlistIDs)
            }
        } catch CollectionSyncError.httpError(404) {
            friendCollectionCardIDs = []
            sharedWishlistCardIDs = []
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

    private func unfriend(_ userID: UUID) async {
        isMutating = true
        defer { isMutating = false }
        do {
            try await services.socialFriend.removeFriend(userID: userID)
            relationship = .none
            sharedWishlistCardIDs = []
            friendCollectionCardIDs = []
            resolvedSharedCardsByID = [:]
            Haptics.success()
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
            sharedWishlistCardIDs = []
            friendCollectionCardIDs = []
            resolvedSharedCardsByID = [:]
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resolvedWishlistCardIDs() -> [String] {
        sharedWishlistCardIDs.filter { !$0.isEmpty }
    }

    @MainActor
    private func openCardDetail(tappedID: String, orderedIDs: [String]) async {
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

    private func friendCardTradeContext() -> CardTradeContext? {
        guard navigationPath != nil, let profile, relationship == .friends else { return nil }
        let name = profile.shortDisplayName
        switch selectedTab {
        case .wishlist:
            return .friendWants(name: name) { card in
                offerSingleCardTrade(cardID: card.masterCardId)
            }
        case .collection:
            return .friendHas(name: name) { card in
                offerSingleCardTrade(cardID: card.masterCardId)
            }
        case .posts:
            return nil
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
