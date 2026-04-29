import SwiftUI
import SwiftData

struct MyProfileView: View {
    private enum ProfileTab: String, CaseIterable {
        case posts
        case wishlist
        case collection
    }

    let profile: SocialProfile
    let onSignOutTapped: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services
    @Environment(\.colorScheme) private var colorScheme

    @State private var cardCount: Int = 0
    @State private var binderCount: Int = 0
    @State private var deckCount: Int = 0
    @State private var favoriteCard: Card?
    @State private var favoriteCardPrice: Double?
    @State private var myActivity: [SocialFeedService.FeedItem] = []
    @State private var selectedProfileTab: ProfileTab = .posts
    @State private var isCollectionPublished = false
    @State private var showCollectionShareSettings = false
    @Query(sort: \CollectionItem.dateAcquired, order: .reverse) private var collectionItems: [CollectionItem]

    private var collectionShareAutoSyncSignature: String {
        collectionItems
            .map { "\($0.cardID)|\($0.variantKey)|\($0.quantity)|\($0.notes)" }
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
        ScrollView {
            VStack(spacing: 18) {
                profileHeader
                favoritesSection
                profileTabPicker
                profileTabContent

                Button(role: .destructive, action: onSignOutTapped) {
                    Text("Sign Out")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.primary.opacity(0.09), lineWidth: 1)
                        }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
        }
        .background(Color(uiColor: .systemBackground))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCollectionShareSettings) {
            ShareSettingsView(source: .collection(items: collectionItems)) {
                Task { await refreshCollectionShareStatus() }
            }
            .environment(services)
        }
        .task {
            fetchStats()
            if let cardID = profile.favoriteCardID {
                favoriteCard = await services.cardData.loadCard(masterCardId: cardID)
                if let card = favoriteCard {
                    favoriteCardPrice = await services.pricing.usdPrice(for: card, printing: "normal")
                }
            }
            do {
                myActivity = try await services.socialFeed.fetchUserActivity(limit: 10)
            } catch {
                print("Error fetching my activity: \(error)")
            }
            await refreshCollectionShareStatus()
        }
        .onChange(of: collectionShareAutoSyncSignature) { _, _ in
            fetchStats()
            services.socialShare.scheduleAutoSyncCollection(items: collectionItems)
            Task { await refreshCollectionShareStatus() }
        }
    }
    
    // MARK: - Subviews

    private var profileHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                ZStack(alignment: .bottomTrailing) {
                    ProfileAvatarView(profile: profile, size: 64)
                        .overlay(Circle().stroke(themeColor, lineWidth: 3))
                    Circle()
                        .fill(Color(hex: "52C97C"))
                        .frame(width: 18, height: 18)
                        .overlay(Circle().stroke(Color(uiColor: .systemBackground), lineWidth: 3))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(profile.displayName ?? profile.username)
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(Color.primary)
                    Text("@\(profile.username)")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.secondary)
                    if !roleTitles.isEmpty {
                        HStack(spacing: 6) {
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
                statColumn(value: "\(displayedCardCount)", label: "Cards")
                statColumn(value: "\(displayedDeckCount)", label: "Decks")
                statColumn(value: "\(displayedBinderCount)", label: "Binders")
                statColumn(value: "\(profile.friendCount ?? 0)", label: "Friends")
            }
            .padding(.vertical, 12)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
        }
        .padding(16)
        .background {
            // Layered backdrop driven by the user's theme colour, favourite
            // Pokémon (huge faded silhouette behind everything), and favourite
            // card (tilted ghost card peeking from the top-right). Gives every
            // profile a personalised feel rather than the same gold gradient
            // for everyone.
            ZStack(alignment: .topTrailing) {
                LinearGradient(
                    colors: [themeColor.opacity(0.22), themeColor.opacity(0.06), Color(uiColor: .systemBackground)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // (Pokémon dex watermark removed — the giant "#xxx" sat behind
                // the stats bar and looked like a glitch. Favourite card peek
                // below remains as the personalised visual anchor.)

                // Tilted favourite card peek — visual anchor on the right that
                // signals "this is *their* shelf", not a stock template.
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
                    .padding(.top, 14)
                    .padding(.trailing, 18)
                    .allowsHitTesting(false)
                }
            }
        }
    }

    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("FAVORITES")

            if let pokemonName = profile.favoritePokemonName {
                favoriteRow(icon: "star.fill", label: "Pokémon", value: pokemonName)
            }
            if let cardName = profile.favoriteCardName {
                favoriteRow(icon: "rectangle.portrait.fill", label: "Card", value: cardName)
            }
            if let deck = profile.favoriteDeckArchetype {
                favoriteRow(icon: "square.stack.3d.up.fill", label: "Deck", value: deck)
            }
            if profile.favoritePokemonName == nil && profile.favoriteCardName == nil && profile.favoriteDeckArchetype == nil {
                favoriteRow(icon: "sparkles", label: "Favorites", value: "Choose favorites in Edit")
            }
        }
        .padding(.horizontal, 16)
    }

    private var profileTabPicker: some View {
        HStack(spacing: 8) {
            ForEach(ProfileTab.allCases, id: \.self) { tab in
                Button {
                    selectedProfileTab = tab
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selectedProfileTab == tab ? Color.white : Color.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(selectedProfileTab == tab ? themeColor : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            if selectedProfileTab == .collection {
                Button {
                    showCollectionShareSettings = true
                } label: {
                    Image(systemName: isCollectionPublished ? "checkmark.circle.fill" : "square.and.arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isCollectionPublished ? Color(hex: "52C97C") : Color.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var profileTabContent: some View {
        VStack(spacing: 10) {
            switch selectedProfileTab {
            case .posts:
                if groupedActivity.isEmpty {
                    emptyProfileCard("Your shared posts will appear here.")
                } else {
                    ForEach(groupedActivity) { group in
                        FeedItemView(group: group)
                    }
                }
            case .wishlist:
                let ids = (services.wishlist?.items.map(\.cardID) ?? profile.wishlistCardIDs ?? [])
                    .filter(isRenderableCardIDForProfileGrid)
                if ids.isEmpty {
                    emptyProfileCard("Your public wishlist will appear here.")
                } else {
                    WishlistCardGrid(cardIDs: ids, cardLoader: { id in
                        await services.cardData.loadCard(masterCardId: id)
                    })
                }
            case .collection:
                let ids = collectionItems.map(\.cardID).filter(isRenderableCardIDForProfileGrid)
                if ids.isEmpty {
                    emptyProfileCard("Cards you've added to your collection will appear here.")
                } else {
                    WishlistCardGrid(cardIDs: ids, cardLoader: { id in
                        await services.cardData.loadCard(masterCardId: id)
                    })
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func isRenderableCardIDForProfileGrid(_ cardID: String) -> Bool {
        // Shared profile card grid renders trading cards only.
        // Sealed product ids (e.g. "sealed:pokemon:123") produce permanent placeholders.
        !cardID.hasPrefix("sealed:")
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .tracking(0.88)
            .foregroundStyle(Color.secondary.opacity(0.3))
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
                .foregroundStyle(Color.secondary.opacity(0.3))
        }
        .frame(maxWidth: .infinity)
    }

    private func favoriteRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(themeColor.opacity(0.15))
                .frame(width: 34, height: 34)
                .overlay {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(themeColor)
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

    private func emptyProfileCard(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Color.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
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
                .fill(.ultraThinMaterial)
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
                .fill(.ultraThinMaterial)
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

    private func refreshCollectionShareStatus() async {
        do {
            let snapshot = try await services.socialShare.shareSnapshotForCollection()
            isCollectionPublished = snapshot.isPublished
        } catch {
            isCollectionPublished = false
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
