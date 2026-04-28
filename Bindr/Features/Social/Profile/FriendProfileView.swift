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
    @State private var sharedCollectionCardIDs: [String] = []
    @State private var hasSharedCollection = false

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
                        relationshipSection(profile)
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
                    if !roleTitles.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(roleTitles, id: \.self) { title in
                                rolePill(title, accent: accent)
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
                statColumn(value: "\(profile.collectionCardCount ?? 0)", label: "Cards")
                statColumn(value: "\(profile.collectionDeckCount ?? 0)", label: "Decks")
                statColumn(value: "\(profile.collectionBinderCount ?? 0)", label: "Binders")
                statColumn(value: "\(profile.friendCount ?? 0)", label: "Friends")
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

                if let dex = profile.favoritePokemonDex {
                    Text("#\(String(format: "%03d", dex))")
                        .font(.system(size: 110, weight: .black))
                        .foregroundStyle(accent)
                        .opacity(0.06)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .offset(x: -16, y: 12)
                        .allowsHitTesting(false)
                }

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
    /// `actionButton`, etc.) can pick it up without each one taking an arg.
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
        if profile.favoritePokemonName != nil || profile.favoriteCardName != nil || profile.favoriteDeckArchetype != nil {
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("FAVORITES")
                if let name = profile.favoritePokemonName {
                    infoRow(icon: "star.fill", label: "Pokémon", value: name)
                }
                if let name = profile.favoriteCardName {
                    infoRow(icon: "rectangle.portrait.fill", label: "Card", value: name)
                }
                if let deck = profile.favoriteDeckArchetype {
                    infoRow(icon: "square.stack.3d.up.fill", label: "Deck", value: deck)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func relationshipSection(_ profile: SocialProfile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("FRIENDSHIP")
            HStack(spacing: 12) {
                Text(relationshipLabel)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.secondary)
                Spacer()
                actionButton(for: profile.id)
            }
            .padding(12)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.09), lineWidth: 1)
            }
        }
        .padding(.horizontal, 16)
    }

    private var tabPicker: some View {
        HStack(spacing: 8) {
            ForEach(ProfileTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selectedTab == tab ? Color.white : Color.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(selectedTab == tab ? accentColor : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
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
                if profile.isWishlistPublic == true, let ids = profile.wishlistCardIDs, !ids.isEmpty {
                    WishlistCardGrid(cardIDs: ids, cardLoader: { id in
                        await services.cardData.loadCard(masterCardId: id)
                    })
                } else if profile.isWishlistPublic != true {
                    emptyCard("This user's wishlist is private.")
                } else {
                    emptyCard("No wishlist items yet.")
                }
            case .collection:
                if hasSharedCollection, !sharedCollectionCardIDs.isEmpty {
                    WishlistCardGrid(cardIDs: sharedCollectionCardIDs, cardLoader: { id in
                        await services.cardData.loadCard(masterCardId: id)
                    })
                } else if hasSharedCollection {
                    emptyCard("No cards in this user's shared collection yet.")
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
            .foregroundStyle(Color.secondary.opacity(0.3))
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
                .foregroundStyle(Color.secondary.opacity(0.3))
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
                    .foregroundStyle(Color.secondary.opacity(0.3))
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

    @ViewBuilder
    private func actionButton(for userID: UUID) -> some View {
        switch relationship {
        case .none:
            Button("Add Friend") {
                Task { await sendRequest(to: userID) }
            }
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.black)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(accentColor, in: Capsule())
            .disabled(isMutating)
        case .friends:
            Label("Friends", systemImage: "checkmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(hex: "52C97C"))
        case .pendingOutgoing:
            Label("Pending", systemImage: "clock")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.secondary.opacity(0.45))
        case .pendingIncoming(let friendshipID):
            Button("Accept") {
                Task { await respond(to: friendshipID, accepted: true) }
            }
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.black)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(accentColor, in: Capsule())
            .disabled(isMutating)
        case .blocked:
            Label("Blocked", systemImage: "hand.raised.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(hex: "E05252"))
        }
    }

    private var relationshipLabel: String {
        switch relationship {
        case .none: return "Not connected"
        case .pendingIncoming: return "Requested you"
        case .pendingOutgoing: return "Request sent"
        case .friends: return "Friends"
        case .blocked: return "Blocked"
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
                async let shared = services.socialShare.fetchSharedContent(ownerID: loaded.id)
                relationship = try await rel
                activity = (try? await posts) ?? []
                let sharedContent = (try? await shared) ?? []
                if let collection = sharedContent.first(where: { $0.contentType == .collection }) {
                    hasSharedCollection = true
                    sharedCollectionCardIDs = collectionCardIDs(from: collection)
                } else {
                    hasSharedCollection = false
                    sharedCollectionCardIDs = []
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func sendRequest(to userID: UUID) async {
        isMutating = true
        defer { isMutating = false }
        do {
            try await services.socialFriend.sendRequest(to: userID)
            relationship = try await services.socialFriend.fetchRelationshipState(for: userID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func respond(to friendshipID: UUID, accepted: Bool) async {
        isMutating = true
        defer { isMutating = false }
        do {
            try await services.socialFriend.respond(to: friendshipID, accepted: accepted)
            relationship = accepted ? .friends : .none
        } catch {
            errorMessage = error.localizedDescription
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

    private func collectionCardIDs(from content: SharedContent) -> [String] {
        guard case .some(.array(let items)) = content.payload["items"] else { return [] }
        var ordered: [String] = []
        var seen: Set<String> = []
        for entry in items {
            guard case .object(let object) = entry else { continue }
            guard let cardID = object["cardID"]?.stringValue, !cardID.isEmpty else { continue }
            if seen.insert(cardID).inserted {
                ordered.append(cardID)
            }
        }
        return ordered
    }
}
