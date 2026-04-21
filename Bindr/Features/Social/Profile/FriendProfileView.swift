import SwiftUI

struct FriendProfileView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.colorScheme) private var colorScheme

    let username: String

    @State private var profile: SocialProfile?
    @State private var relationship: SocialFriendService.RelationshipState = .none
    @State private var sharedContent: [SharedContent] = []
    @State private var isLoading = false
    @State private var isLoadingSharedContent = false
    @State private var isMutating = false
    @State private var errorMessage: String?
    @State private var showWishlistDetail = false
    
    // Stats are limited for friends unless we add them to SocialProfile model later,
    // so we'll show follower count from profile and 0/--- for others or remove them.
    // For now, let's show what we have.

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading profile…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let profile {
                ScrollView {
                    VStack(spacing: 0) {
                        // 1. Hero Header
                        ProfileHeroHeader(profile: profile, onEditTapped: nil) // Pass nil since can't edit friend
                        
                        VStack(spacing: 24) {
                            // 2. Stats Row
                            ProfileStatsRow(
                                cardCount: 0, // Not synced yet
                                totalValue: "---", // Not synced yet
                                followerCount: profile.followerCount ?? 0,
                                binderCount: 0 // Not synced yet
                            )
                            
                            // 3. Profile Type Chips
                            let roleTitles = (profile.profileRoles ?? []).map { role in
                                switch role {
                                case "collector": return "Collector"
                                case "tcg_player": return "TCG Player"
                                default: return role.replacingOccurrences(of: "_", with: " ").capitalized
                                }
                            }
                            
                            if !roleTitles.isEmpty {
                                HStack(spacing: 10) {
                                    ForEach(roleTitles, id: \.self) { title in
                                        Text(title)
                                            .font(.system(size: 14, weight: .semibold))
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 8)
                                            .background(
                                                Capsule()
                                                    .fill(colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.05))
                                            )
                                            .overlay(
                                                Capsule()
                                                    .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08), lineWidth: 1)
                                            )
                                    }
                                }
                            }
                            
                            // 4. Friend Status Section
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Friend Status")
                                    .font(.headline)
                                    .padding(.horizontal, 20)
                                
                                HStack(spacing: 12) {
                                    Text(relationshipLabel)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    actionButton(for: profile.id)
                                }
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(.ultraThinMaterial)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05), lineWidth: 1)
                                        )
                                )
                                .padding(.horizontal, 20)
                            }
                            
                            // 5. Favorites Section
                            if profile.favoritePokemonName != nil || profile.favoriteCardName != nil {
                                VStack(alignment: .leading, spacing: 16) {
                                    Text("Favorites")
                                        .font(.headline)
                                        .padding(.horizontal, 20)
                                    
                                    VStack(spacing: 12) {
                                        if let pokemonName = profile.favoritePokemonName {
                                            favoritePokemonTile(profile: profile, name: pokemonName, dex: profile.favoritePokemonDex)
                                        }
                                        
                                        if let cardName = profile.favoriteCardName {
                                            favoriteCardTile(profile: profile, name: cardName)
                                        }
                                    }
                                    .padding(.horizontal, 20)
                                }
                            }
                            
                            // 6. Public Wishlist Preview
                            if profile.isWishlistPublic == true, let wishlistIDs = profile.wishlistCardIDs, !wishlistIDs.isEmpty {
                                ProfileWishlistPreview(
                                    cardIDs: wishlistIDs,
                                    onViewAllTapped: { showWishlistDetail = true },
                                    cardLoader: { id in await services.cardData.loadCard(masterCardId: id) },
                                    priceFormatter: { val in
                                        let formatter = NumberFormatter()
                                        formatter.numberStyle = .currency
                                        formatter.currencySymbol = services.priceDisplay.currency == .gbp ? "£" : "$"
                                        return formatter.string(from: NSNumber(value: val)) ?? "$0"
                                    }
                                )
                                .sheet(isPresented: $showWishlistDetail) {
                                    PublicWishlistDetailView(
                                        cardIDs: wishlistIDs,
                                        title: "@\(username)'s Wishlist",
                                        cardLoader: { id in await services.cardData.loadCard(masterCardId: id) },
                                        priceFormatter: { val in
                                            let formatter = NumberFormatter()
                                            formatter.numberStyle = .currency
                                            formatter.currencySymbol = services.priceDisplay.currency == .gbp ? "£" : "$"
                                            return formatter.string(from: NSNumber(value: val)) ?? "$0"
                                        }
                                    )
                                }
                            }
                            
                            // 7. Shared Content List
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("Shared Content")
                                        .font(.headline)
                                    Spacer()
                                    if isLoadingSharedContent {
                                        ProgressView().scaleEffect(0.8)
                                    }
                                }
                                .padding(.horizontal, 20)
                                
                                if sharedContent.isEmpty {
                                    Text("No published binders or decks yet.")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 20)
                                } else {
                                    VStack(spacing: 0) {
                                        ForEach(sharedContent) { entry in
                                            NavigationLink {
                                                SharedContentView(content: entry)
                                                    .environment(services)
                                            } label: {
                                                HStack(spacing: 12) {
                                                    VStack(alignment: .leading, spacing: 3) {
                                                        Text(entry.title)
                                                            .font(.subheadline.weight(.semibold))
                                                            .foregroundStyle(.primary)
                                                        Text(entry.contentType.rawValue.capitalized)
                                                            .font(.caption)
                                                            .foregroundStyle(.secondary)
                                                    }
                                                    Spacer()
                                                    Image(systemName: "chevron.right")
                                                        .font(.system(size: 14, weight: .semibold))
                                                        .foregroundStyle(.tertiary)
                                                }
                                                .padding()
                                                .background(colorScheme == .dark ? Color(hex: "1c1c1e") : .white)
                                            }
                                            .buttonStyle(.plain)
                                            
                                            if entry.id != sharedContent.last?.id {
                                                Divider().padding(.leading)
                                            }
                                        }
                                    }
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .padding(.horizontal, 20)
                                }
                            }
                            
                            Spacer().frame(height: 40)
                        }
                        .padding(.top, 24)
                    }
                }
                .background(colorScheme == .dark ? Color.black : Color(uiColor: .systemGroupedBackground))
            } else {
                ContentUnavailableView(
                    "Profile Not Found",
                    systemImage: "person.crop.circle.badge.exclamationmark",
                    description: Text("This username does not exist or is no longer available.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("@\(username)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu("Actions", systemImage: "ellipsis.circle") {
                    if let profile {
                        Button("Block User", role: .destructive) {
                            Task { await block(profile.id) }
                        }
                    }
                }
            }
        }
        .task {
            await refresh()
        }
    }

    // MARK: - Helper Subviews (Mirrored from MyProfileView)

    private func favoritePokemonTile(profile: SocialProfile, name: String, dex: Int?) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
                    .frame(width: 60, height: 60)
                
                if let urlString = profile.favoritePokemonImageURL, let url = URL(string: urlString) {
                    CachedAsyncImage(url: url) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        ProgressView().scaleEffect(0.8)
                    }
                    .frame(width: 44, height: 44)
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
                glassTag(text: "Pokémon")
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05), lineWidth: 1)
                )
        )
    }

    private func favoriteCardTile(profile: SocialProfile, name: String) -> some View {
        HStack(spacing: 16) {
            if let imageURL = profile.favoriteCardImageURL, let url = URL(string: imageURL) {
                CachedAsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.gray.opacity(0.1)
                }
                .frame(width: 62, height: 87)
                .clipShape(RoundedRectangle(cornerRadius: 6))
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
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05), lineWidth: 1)
                )
        )
    }

    private func glassTag(text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.05)))
    }

    @ViewBuilder
    private func actionButton(for userID: UUID) -> some View {
        switch relationship {
        case .none:
            Button("Add Friend") {
                Task { await sendRequest(to: userID) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isMutating)
        case .friends:
            Label("Friends", systemImage: "checkmark")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)
        case .pendingOutgoing:
            Label("Pending", systemImage: "clock")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        case .pendingIncoming(let friendshipID):
            Button("Accept") {
                Task { await respond(to: friendshipID, accepted: true) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isMutating)
        case .blocked:
            Label("Blocked", systemImage: "hand.raised.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.red)
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

    private func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await services.socialFriend.fetchProfile(username: username)
            profile = loaded
            if let loaded {
                relationship = try await services.socialFriend.fetchRelationshipState(for: loaded.id)
                await refreshSharedContent(ownerID: loaded.id)
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

    private func refreshSharedContent(ownerID: UUID) async {
        isLoadingSharedContent = true
        defer { isLoadingSharedContent = false }
        do {
            sharedContent = try await services.socialShare.fetchSharedContent(ownerID: ownerID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
