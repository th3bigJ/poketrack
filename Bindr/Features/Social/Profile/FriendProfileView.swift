import SwiftUI

struct FriendProfileView: View {
    @Environment(AppServices.self) private var services

    let username: String

    private enum ProfileTab: String, CaseIterable {
        case posts
        case wishlist
        case collection
    }

    @State private var profile: SocialProfile?
    @State private var relationship: SocialFriendService.RelationshipState = .none
    @State private var activity: [SocialFeedService.FeedItem] = []
    @State private var isLoading = false
    @State private var isMutating = false
    @State private var errorMessage: String?
    @State private var selectedTab: ProfileTab = .posts
    @State private var sharedWishlistCardIDs: [String] = []
    @State private var sharedCollectionCardIDs: [String] = []

    private var canViewCollection: Bool {
        relationship == .friends
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
                    VStack(spacing: 18) {
                        profileHeader(profile)
                        favoritesSection(profile)
                        tabPicker
                        tabContent(profile)
                    }
                    .padding(.bottom, 32)
                }
                .background(Color(uiColor: .systemBackground))
            } else {
                ContentUnavailableView(
                    "Profile Not Found",
                    systemImage: "person.crop.circle.badge.exclamationmark",
                    description: Text("This username does not exist or is no longer available.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .navigationTitle("@\(username)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let profile {
                    Menu("Actions", systemImage: "ellipsis.circle") {
                        Button("Block User", role: .destructive) {
                            Task { await block(profile.id) }
                        }
                    }
                }
            }
        }
        .task(id: username) { await refresh() }
    }

    // MARK: - Subviews

    private func profileHeader(_ profile: SocialProfile) -> some View {
        let accent = themeColor(for: profile)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                ProfileAvatarView(profile: profile, size: 64)
                    .overlay(Circle().stroke(accent, lineWidth: 3))

                VStack(alignment: .leading, spacing: 6) {
                    Text(profile.displayName ?? profile.username)
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(Color.primary)
                    Text("@\(profile.username)")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.secondary)
                    let roleTitles = roleTitles(for: profile)
                    // Roles + relationship status share one wrapping row so a
                    // ✓ Friends / Blocked / Pending pill reads as part of the
                    // identity block rather than living in its own section.
                    if !roleTitles.isEmpty || hasRelationshipStatusPill {
                        HStack(spacing: 6) {
                            ForEach(roleTitles, id: \.self) { title in
                                rolePill(title, accent: accent)
                            }
                            relationshipStatusPill
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

            // Primary CTA only appears for *actionable* states (Add Friend /
            // Accept request). Passive states like .friends or .blocked are
            // communicated by the status pill above; destructive actions live
            // in the navbar ⋯ menu.
            primaryRelationshipAction(for: profile.id)

            HStack(spacing: 0) {
                let cardCount = profile.collectionCardCount ?? 0
                let deckCount = profile.collectionDeckCount ?? 0
                let binderCount = profile.collectionBinderCount ?? 0
                let friendCount = profile.friendCount ?? 0
                statColumn(value: "\(cardCount)", label: cardCount == 1 ? "Card" : "Cards")
                statColumn(value: "\(deckCount)", label: deckCount == 1 ? "Deck" : "Decks")
                statColumn(value: "\(binderCount)", label: binderCount == 1 ? "Binder" : "Binders")
                statColumn(value: "\(friendCount)", label: friendCount == 1 ? "Friend" : "Friends")
            }
            .padding(.vertical, 12)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.09), lineWidth: 1)
            }
        }
        .padding(16)
        .background {
            // Layered backdrop driven by the friend's theme colour, favourite
            // Pokémon (faded silhouette behind everything), and favourite
            // card (tilted ghost card peeking from the top-right). Mirrors
            // the personalised look on `MyProfileView` so visiting a friend's
            // profile feels like *their* space, not a stock template.
            ZStack(alignment: .topTrailing) {
                LinearGradient(
                    colors: [accent.opacity(0.22), accent.opacity(0.06), Color(uiColor: .systemBackground)],
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
                    .frame(width: 64, height: 90)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.white.opacity(0.35), lineWidth: 0.5)
                    }
                    .shadow(color: accent.opacity(0.45), radius: 10, x: 0, y: 6)
                    .rotationEffect(.degrees(8))
                    .opacity(0.85)
                    .padding(.top, 14)
                    .padding(.trailing, 18)
                    .allowsHitTesting(false)
                }
            }
        }
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

    @ViewBuilder
    private func favoritesSection(_ profile: SocialProfile) -> some View {
        // Favourite Pokémon is already the profile avatar and favourite card
        // is already the tilted hero peek — re-listing them as labelled rows
        // is pure duplication. Only the favourite deck has no other place to
        // live, so this section now only renders when there's a deck to show.
        if let deck = profile.favoriteDeckArchetype, !deck.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("FAVORITE DECK")
                infoRow(icon: "square.stack.3d.up.fill", label: "Deck", value: deck)
            }
            .padding(.horizontal, 16)
        }
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
        tab.rawValue.prefix(1).uppercased() + tab.rawValue.dropFirst()
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
        .padding(4)
        .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
        .overlay {
            Capsule().stroke(Color.primary.opacity(0.06), lineWidth: 1)
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func tabContent(_ profile: SocialProfile) -> some View {
        VStack(spacing: 10) {
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
                    WishlistCardGrid(cardIDs: ids, cardLoader: { id in
                        await services.cardData.loadCard(masterCardId: id)
                    })
                } else if !canViewWishlist {
                    emptyCard("This user's wishlist is private.")
                } else {
                    emptyCard("No wishlist items yet.")
                }
            case .collection:
                if canViewCollection, !sharedCollectionCardIDs.isEmpty {
                    WishlistCardGrid(cardIDs: sharedCollectionCardIDs, cardLoader: { id in
                        await services.cardData.loadCard(masterCardId: id)
                    })
                } else if canViewCollection {
                    emptyCard("No cards in this user's collection yet.")
                } else {
                    emptyCard("This user has not shared a collection.")
                }
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .tracking(0.88)
            .foregroundStyle(Color.secondary.opacity(0.7))
    }

    private func rolePill(_ title: String, accent: Color? = nil) -> some View {
        let tint = accent ?? accentColor
        return Text(title.uppercased())
            .font(.system(size: 10, weight: .bold))
            .tracking(0.4)
            .foregroundStyle(tint)
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

    private func infoRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(accentColor.opacity(0.15))
                .frame(width: 34, height: 34)
                .overlay {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(accentColor)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.4)
                    .foregroundStyle(Color.secondary.opacity(0.7))
                Text(value)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private func emptyCard(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Color.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.09), lineWidth: 1)
            }
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
                relationship = try await rel
                activity = (try? await posts) ?? []
                if relationship == .friends {
                    async let wishlistIDs = services.socialCardLibrary.fetchWishlistCardIDs(for: loaded.id)
                    async let collectionIDs = services.socialCardLibrary.fetchCollectionCardIDs(for: loaded.id)
                    sharedWishlistCardIDs = (try? await wishlistIDs) ?? []
                    sharedCollectionCardIDs = (try? await collectionIDs) ?? []
                } else {
                    sharedWishlistCardIDs = []
                    sharedCollectionCardIDs = []
                }
            }
            errorMessage = nil
        } catch is CancellationError {
            // Ignore
        } catch let error as URLError where error.code == .cancelled {
            // Ignore
        } catch {
            errorMessage = error.localizedDescription
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
}
