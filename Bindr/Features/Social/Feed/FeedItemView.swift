import SwiftUI

private struct PresentedPostCards: Identifiable {
    let id = UUID()
    let cards: [Card]
}

// MARK: - FeedItemView

struct FeedItemView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.restoreTabBarChrome) private var restoreTabBarChrome
    let group: GroupedFeedItem
    var showsInteractionBar: Bool = true
    var isCardTapEnabled: Bool = true
    var onPostEdited: (() -> Void)? = nil

    private var item: SocialFeedService.FeedItem { group.primary }

    @State private var isCommentsPresented = false
    @State private var commentsRefreshToken = 0
    /// Resolved cards for pull-type posts. These open directly in a swipeable
    /// card detail sheet, avoiding the Comments → Shared Content detour.
    @State private var presentedPostCards: PresentedPostCards?

    @State private var showDeleteAlert = false
    @State private var showEditSheet = false
    @State private var isProcessing = false

    private var canEditPost: Bool {
        isMyItem
            && item.content != nil
            && item.type != .friendship
            && item.type != .dailyDigest
    }

    private var canOpenComments: Bool {
        item.content != nil && item.type != .friendship
    }

    private var isMyItem: Bool {
        guard let myID = services.socialAuth.currentUserID else { return false }
        return item.actor?.id == myID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .top, spacing: 12) {
                if let username = item.actor?.username {
                    NavigationLink(value: SocialDestination.friendProfile(username: username)) {
                        ProfileAvatarView(profile: item.actor!, size: 32)
                            .overlay(Circle().stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(cardTitle)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    HStack(spacing: 4) {
                        Text(actorName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        
                        if let actor = item.actor {
                            PremiumBadgeView(profile: actor, size: 10)
                        }
                        
                        if isEdited {
                            Text("• Edited")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary.opacity(0.3))
                        }
                        
                        Text("• \(SocialFeedService.shortRelativeDate(item.createdAt))")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary.opacity(0.5))
                    }
                }
                
                Spacer()
                
                HStack(spacing: 12) {
                    if canEditPost {
                        postMenuButton
                    }
                    
                    if let badgeText = badgeText {
                        TypePill(label: badgeText, color: typeAccentColor)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            // Content
            // The description area and the card preview have separate tap
            // targets. For pull posts (single card) the card image goes
            // directly to ``CardDetailSheet`` — no Comments → View Content
            // → SharedContentView detour needed. Every other post type and
            // tapping the description area still opens comments as before.
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    if let description = cleanedDescription, !description.isEmpty {
                        ExpandableDescription(text: description, collapsedLineLimit: 4)
                            .padding(.top, 2)
                    }

                    Spacer(minLength: 8)

                    hashtagRow
                }
                .padding(.leading, 16)
                .padding(.trailing, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard isCardTapEnabled, canOpenComments else { return }
                    Haptics.lightImpact()
                    isCommentsPresented = true
                }

                CardStackPreview(item: item, size: 110)
                    .padding(.trailing, 22)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard isCardTapEnabled else { return }
                        if item.type == .pull {
                            let cardIDs = item.thumbnails?.isEmpty == false
                                ? item.thumbnails ?? []
                                : item.pullCardID.map { [$0] } ?? []
                            guard !cardIDs.isEmpty else { return }
                            Haptics.lightImpact()
                            Task {
                                var orderedCards: [Card] = []
                                for cardID in cardIDs {
                                    if let card = await services.cardData.loadCard(masterCardId: cardID) {
                                        orderedCards.append(card)
                                    }
                                }
                                if !orderedCards.isEmpty {
                                    presentedPostCards = PresentedPostCards(cards: orderedCards)
                                }
                            }
                        } else if canOpenComments {
                            Haptics.lightImpact()
                            isCommentsPresented = true
                        }
                    }
            }
            .frame(minHeight: 110)
            .padding(.bottom, 14)

            // Footer
            if showsInteractionBar, item.type != .friendship {
                VStack(spacing: 0) {
                    if let summary = group.interactionSummary {
                        Text(summary)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary.opacity(colorScheme == .dark ? 0.6 : 0.75))
                            .padding(.horizontal, 16)
                            .padding(.top, 4)
                            .padding(.bottom, 8)
                    }

                    InteractionBar(
                        item: item,
                        refreshToken: commentsRefreshToken,
                        onOpenComments: { isCommentsPresented = true }
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(colorScheme == .dark ? Color.primary.opacity(0.06) : BindrPalette.feedCardBorder)
                        .frame(height: 1)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .feedPostCardStyle(cornerRadius: 20)
        .sheet(isPresented: $isCommentsPresented, onDismiss: {
            commentsRefreshToken += 1
            restoreTabBarChrome?()
        }) {
            if let content = item.content {
                NavigationStack {
                    CommentsView(content: content, sourceItem: item)
                        .environment(services)
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(item: $presentedPostCards, onDismiss: {
            restoreTabBarChrome?()
        }) { selection in
            CardDetailSheet(cards: selection.cards, startIndex: 0)
                .environment(services)
        }
        .alert("Delete Post?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                if let contentID = item.content?.id {
                    Task {
                        isProcessing = true
                        try? await services.socialFeed.deleteSharedContent(id: contentID)
                        isProcessing = false
                    }
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently remove this post from the feed.")
        }
        .sheet(isPresented: $showEditSheet) {
            if let contentID = item.content?.id {
                SocialShareSheet(
                    item: .card,
                    editingContentID: contentID,
                    onPostSaved: {
                        onPostEdited?()
                        Haptics.success()
                    }
                )
                .environment(services)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
            }
        }
    }

    private var postMenuButton: some View {
        Menu {
            Button {
                showEditSheet = true
            } label: {
                Label("Edit Post", systemImage: "pencil")
            }

            Button(role: .destructive) {
                showDeleteAlert = true
            } label: {
                Label("Delete Post", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.secondary.opacity(0.5))
                .padding(8)
                .contentShape(Rectangle())
        }
    }

    private var hashtagRow: some View {
        HStack(spacing: 6) {
            let tags: [String] = {
                var t: [String] = []
                if let name = item.pullCardName { t.append(name.replacingOccurrences(of: " ", with: "")) }
                if let set = resolvedPullSetName { t.append(set.replacingOccurrences(of: " ", with: "")) }
                if t.isEmpty { t = ["Collection", "Trainer"] }
                return t
            }()
            
            ForEach(tags.prefix(2), id: \.self) { tag in
                Text("#\(tag)")
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        colorScheme == .dark
                            ? Color.primary.opacity(0.06)
                            : BindrPalette.feedTagBackground
                    )
                    .foregroundStyle(.secondary)
                    .clipShape(Capsule())
            }
        }
    }


    private var actorName: String {
        item.actor?.displayName ?? item.actor?.username ?? "Trainer"
    }

    private var isActorPremium: Bool {
        guard let actor = item.actor else { return false }
        if let myID = services.socialAuth.currentUserID, actor.id == myID {
            return services.store.isPremium
        }
        return actor.hasPremium
    }

    private var cardTitle: String {
        if item.type == .pull {
            return item.pullCardName ?? resolvedPullSetName ?? "Pack pull"
        }
        return item.content?.title ?? fallbackTitle
    }

    /// Older feed posts stored the raw set code (e.g. `me2pt5`) in
    /// `pullSetName` because the publish flow forwarded the wrong field. Look
    /// the code up against the loaded catalog so we render "Mega Evolution"
    /// rather than the cryptic code, while still surfacing the original value
    /// when no match is found (covers brand-new sets we haven't synced yet).
    private var resolvedPullSetName: String? {
        guard let raw = item.pullSetName else { return nil }
        if let match = services.cardData.sets.first(where: { $0.setCode == raw }) {
            return match.name
        }
        return raw
    }

    private var bodyText: String? {
        switch item.type {
        case .pull:
            return resolvedPullSetName ?? item.pullRarity ?? "Shared a new pull."
        case .dailyDigest:
            return "Daily collection update."
        case .wishlistMatch:
            return "Has a card from your wishlist."
        case .vote:
            return "Voted on your post."
        case .comment:
            return item.commentBody
        case .friendship:
            return "You're now connected."
        case .sharedContent:
            return item.content?.description
        }
    }

    private var metaText: String? {
        if let count = item.digestCollectionCount, item.type == .dailyDigest {
            return "\(count) cards logged today"
        }
        if let content = item.content, let count = content.cardCount {
            let typeLabel: String = {
                switch content.contentType {
                case .binder: return "cards in binder"
                case .deck: return "cards in deck"
                case .wishlist: return "wishlist cards"
                case .collection: return "cards in collection"
                case .pull: return "pull"
                case .dailyDigest: return "daily updates"
                case .folder: return "cards in folder"
                }
            }()
            if let brand = content.brand, !brand.isEmpty {
                return "\(count) \(typeLabel) · \(brand.capitalized)"
            }
            return "\(count) \(typeLabel)"
        }
        return nil
    }

    private var fallbackTitle: String {
        switch item.type {
        case .dailyDigest: return "Daily Digest"
        case .wishlistMatch: return "Wishlist Match"
        case .vote: return "Vote"
        case .comment: return "Comment"
        case .friendship: return "New Connection"
        case .sharedContent: return "Shared Content"
        case .pull: return "Pack Pull"
        }
    }

    private var isEdited: Bool {
        guard let updatedAt = item.content?.updatedAt else { return false }
        return updatedAt.timeIntervalSince(item.createdAt) > 1
    }

    private var cleanedDescription: String? {
        guard let description = item.content?.description else { return nil }
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var badgeText: String? {
        switch item.type {
        case .pull: return "PULL"
        case .dailyDigest: return "DIGEST"
        case .sharedContent:
            switch item.content?.contentType {
            case .binder: return "BINDER"
            case .deck: return "DECK"
            case .wishlist: return "WISHLIST"
            case .folder: return "FOLDER"
            case .collection: return "COLLECTION"
            default: return "SHARE"
            }
        case .friendship: return nil
        case .wishlistMatch: return "MATCH"
        case .vote, .comment: return nil
        }
    }

    private var typeAccentColor: Color {
        switch item.type {
        case .pull:
            return Color(hex: "52C97C")
        case .dailyDigest:
            return Color(hex: "5B9CF6")
        case .sharedContent:
            switch item.content?.contentType {
            case .binder: return BindrPalette.binderGold
            case .deck: return BindrPalette.feedDeckPurple
            case .wishlist: return BindrPalette.wishlistViolet
            default: return BindrPalette.binderGold
            }
        case .friendship:
            return Color(hex: "52C97C")
        case .wishlistMatch:
            return Color(hex: "A78BFA")
        case .vote:
            return Color(hex: "E8B84B")
        case .comment:
            return Color(hex: "5B9CF6")
        }
    }

    private var stackColors: [Color] {
        switch item.content?.contentType ?? (item.type == .pull ? .pull : .binder) {
        case .binder:
            return [Color(hex: "E8B84B"), Color(hex: "E05252"), Color(hex: "5B9CF6"), Color(hex: "52C97C")]
        case .deck:
            return [Color(hex: "5B9CF6"), Color(hex: "E8B84B"), Color(hex: "E05252")]
        case .wishlist:
            return [Color(hex: "A78BFA"), Color(hex: "5B9CF6"), Color(hex: "52C97C")]
        case .collection:
            return [Color(hex: "52C97C"), Color(hex: "5B9CF6"), Color(hex: "E8B84B")]
        case .pull:
            return [typeAccentColor]
        case .dailyDigest:
            return [Color(hex: "5B9CF6"), Color(hex: "52C97C"), Color(hex: "E8B84B")]
        case .folder:
            return [Color(hex: "22B8CF"), Color(hex: "5B9CF6"), Color(hex: "52C97C")]
        }
    }
}

private struct TypePill: View {
    let label: String
    let color: Color

    var body: some View {
        Text(label)
            .font(.system(size: 9, weight: .bold))
            .tracking(0.4)
            .foregroundStyle(color.opacity(0.85))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

private struct CardStackPreview: View {
    @Environment(AppServices.self) private var services
    @Environment(\.colorScheme) var colorScheme
    let item: SocialFeedService.FeedItem
    let size: CGFloat

    /// Resolved image URLs aligned to the first four cardIDs in
    /// ``item.thumbnails``. `nil` slots are still rendering or weren't found
    /// in the catalog. Filling this asynchronously is necessary because card
    /// image paths (``Card.imageLowSrc``) can't be inferred from the cardID
    /// alone — guessing a filename like `<cardID>.png` only works for some
    /// brands and fails for others (which is why the previous implementation
    /// was rendering grey placeholders).
    @State private var cardImageURLs: [URL?] = []

    private var thumbnailIDs: [String] {
        Array((item.thumbnails ?? []).prefix(4).reversed())
    }

    var body: some View {
        let placeholderCount = stackColors.prefix(4).count
        let count = thumbnailIDs.isEmpty ? placeholderCount : thumbnailIDs.count

        ZStack(alignment: .leading) {
            if !thumbnailIDs.isEmpty {
                ForEach(Array(thumbnailIDs.enumerated()), id: \.offset) { index, _ in
                    let url = index < cardImageURLs.count ? cardImageURLs[index] : nil
                    cardImage(at: index, url: url)
                }
            } else {
                ForEach(Array(stackColors.prefix(4).enumerated()), id: \.offset) { index, color in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(color)
                        .frame(width: size * 0.7, height: size)
                        .overlay {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                        }
                        .offset(x: CGFloat(index) * 6)
                        .zIndex(Double(index))
                }
            }
        }
        .frame(width: size * 0.7 + CGFloat(max(count - 1, 0)) * 6, height: size)
        .task(id: thumbnailIDs.joined(separator: ",")) {
            await resolveCardImageURLs()
        }
    }

    @ViewBuilder
    private func cardImage(at index: Int, url: URL?) -> some View {
        let rotation = Double(index) * 2.0 - 2.0 // Subtle fan effect
        
        Group {
            if let url {
                CachedAsyncImage(
                    url: url,
                    targetSize: BindrImageSizing.compactCardThumbnail
                ) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.1))
                }
            } else {
                RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.1))
            }
        }
        .frame(width: size * 0.7, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay {
            // Subtle Holo Glint
            LinearGradient(
                colors: [.clear, .white.opacity(0.08), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blendMode(.plusLighter)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
        }
        .rotationEffect(.degrees(rotation))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.15), radius: 6, x: 0, y: 3)
        .offset(x: CGFloat(index) * 6)
        .zIndex(Double(index))
    }

    /// Looks up each thumbnail card in the catalog and converts
    /// ``Card.imageLowSrc`` (a relative path) into a full asset URL. Mirrors
    /// the approach used by ``BinderCardCell.loadCardURLs`` on the binders
    /// listing.
    private func resolveCardImageURLs() async {
        var resolved: [URL?] = []
        for cardID in thumbnailIDs {
            if let card = await services.cardData.loadCard(masterCardId: cardID) {
                resolved.append(AppConfiguration.imageURL(relativePath: card.displayImageSrc))
            } else {
                resolved.append(nil)
            }
        }
        cardImageURLs = resolved
    }

    private var stackColors: [Color] {
        switch item.content?.contentType ?? (item.type == .pull ? .pull : .binder) {
        case .binder:
            return [Color(hex: "E8B84B"), Color(hex: "E05252"), Color(hex: "5B9CF6"), Color(hex: "52C97C")]
        case .deck:
            return [Color(hex: "5B9CF6"), Color(hex: "E8B84B"), Color(hex: "E05252")]
        case .wishlist:
            return [Color(hex: "A78BFA"), Color(hex: "5B9CF6"), Color(hex: "52C97C")]
        case .collection:
            return [Color(hex: "52C97C"), Color(hex: "5B9CF6"), Color(hex: "E8B84B")]
        case .pull:
            return [Color(hex: "5B9CF6")]
        case .dailyDigest:
            return [Color(hex: "5B9CF6"), Color(hex: "52C97C"), Color(hex: "E8B84B")]
        case .folder:
            return [Color(hex: "22B8CF"), Color(hex: "5B9CF6"), Color(hex: "52C97C")]
        }
    }
}

// MARK: - InteractionBar

struct InteractionBar: View {
    @Environment(AppServices.self) private var services
    @Environment(\.colorScheme) var colorScheme
    let item: SocialFeedService.FeedItem
    let refreshToken: Int
    let onOpenComments: () -> Void

    @State private var aggregate = SocialFeedService.VoteAggregate(upvoteCount: 0, downvoteCount: 0, myVoteType: nil)
    @State private var commentCount = 0
    /// Last error shown to the user under the bar — surfaces what previously
    /// only printed to the Xcode console (auth, RLS, missing content id, etc.)
    /// so we can tell *why* a vote silently fails on device.
    @State private var voteErrorMessage: String?

    var body: some View {
        HStack(spacing: 20) {
            // Left: Votes
            HStack(spacing: 12) {
                voteButton(type: .upvote)
                
                Text("\(aggregate.score)")
                    .font(.system(size: 13, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Color.secondary.opacity(0.85))
                
                voteButton(type: .downvote)
            }

            Spacer()

            // Right: Comments
            Button {
                Haptics.lightImpact()
                onOpenComments()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "bubble.right")
                        .font(.system(size: 13, weight: .semibold))
                    Text("\(commentCount)")
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundStyle(Color.secondary.opacity(0.75))
            }
            .buttonStyle(.plain)
        }
        .task { await refresh() }
        .onChange(of: refreshToken) { _, _ in
            Task { await refresh() }
        }
    }

    private func voteButton(type: ReactionType) -> some View {
        let isActive = aggregate.myVoteType == type
        let symbol = type == .upvote ? "arrow.up" : "arrow.down"

        return Image(systemName: symbol)
            .font(.system(size: 14, weight: isActive ? .heavy : .semibold))
            .foregroundStyle(
                isActive
                    ? Color.primary.opacity(0.85)
                    : Color.secondary.opacity(0.45)
            )
            .scaleEffect(isActive ? 1.05 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isActive)
            .contentShape(Rectangle())
            .onTapGesture {
                Haptics.mediumImpact()
                Task { await toggleVote(type) }
            }
    }

    private func refresh() async {
        guard let contentID = item.content?.id else { return }
        do {
            async let agg = services.socialFeed.fetchVoteAggregate(for: contentID)
            async let cnt = services.socialFeed.fetchCommentCount(for: contentID)
            aggregate = try await agg
            commentCount = try await cnt
        } catch {
            // Silent — the bar still renders, just with zeroed counts.
        }
    }

    private func toggleVote(_ type: ReactionType) async {
        guard let contentID = item.content?.id else {
            voteErrorMessage = "Can't vote on this post."
            return
        }
        // Optimistic update — flip the local aggregate immediately so the
        // user gets feedback before the network round-trip lands.
        let previous = aggregate
        aggregate = optimisticToggle(current: previous, tapped: type)
        voteErrorMessage = nil

        do {
            try await services.socialFeed.toggleVote(type: type, to: contentID)
            // Reconcile against the server in case our optimistic guess was
            // off (e.g. the row was deleted server-side).
            aggregate = try await services.socialFeed.fetchVoteAggregate(for: contentID)
        } catch {
            // Roll back the optimistic change and surface the error so we
            // can see what's actually wrong on device instead of failing
            // silently.
            aggregate = previous
            voteErrorMessage = "Vote failed: \(error.localizedDescription)"
            Haptics.error()
        }
    }

    /// Produces what the aggregate *should* look like immediately after a
    /// tap, without waiting for the server. Mirrors the toggle/swap logic in
    /// ``SocialFeedService.toggleVote`` so the UI guess matches.
    private func optimisticToggle(
        current: SocialFeedService.VoteAggregate,
        tapped: ReactionType
    ) -> SocialFeedService.VoteAggregate {
        var up = current.upvoteCount
        var down = current.downvoteCount
        let nextMine: ReactionType?
        switch (current.myVoteType, tapped) {
        case (nil, .upvote):
            up += 1; nextMine = .upvote
        case (nil, .downvote):
            down += 1; nextMine = .downvote
        case (.upvote?, .upvote):
            up = max(0, up - 1); nextMine = nil
        case (.downvote?, .downvote):
            down = max(0, down - 1); nextMine = nil
        case (.upvote?, .downvote):
            up = max(0, up - 1); down += 1; nextMine = .downvote
        case (.downvote?, .upvote):
            down = max(0, down - 1); up += 1; nextMine = .upvote
        }
        return SocialFeedService.VoteAggregate(
            upvoteCount: up,
            downvoteCount: down,
            myVoteType: nextMine
        )
    }
}

// MARK: - InteractionRow

struct InteractionRow: View {
    @Environment(AppServices.self) private var services
    let item: SocialFeedService.FeedItem

    private var isActorPremium: Bool {
        guard let actor = item.actor else { return false }
        if let myID = services.socialAuth.currentUserID, actor.id == myID {
            return services.store.isPremium
        }
        return actor.hasPremium
    }

    var body: some View {
        HStack(spacing: 8) {
            if let actor = item.actor {
                ProfileAvatarView(profile: actor, size: 22)
                    .clipShape(Circle())
            }
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(item.actor?.displayName ?? item.actor?.username ?? "Trainer")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                    
                    if let actor = item.actor {
                        PremiumBadgeView(profile: actor, size: 8)
                    }
                }
                Group {
                    if item.type == .comment, let body = item.commentBody {
                        Text(body).italic()
                    } else {
                        Text(item.type == .vote ? "voted" : "interacted")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            }
            Spacer()
            Text(SocialFeedService.shortRelativeDate(item.createdAt))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - ExpandableDescription

/// A description block that collapses to ``collapsedLineLimit`` lines and
/// surfaces a "Read more" toggle when — and only when — the text is actually
/// being truncated. Truncation is detected by laying out two hidden ghost
/// copies of the same text (one unbounded, one line-limited) and comparing
/// their rendered heights via preference keys, which is more reliable than a
/// character-count heuristic when posts mix short paragraphs with long ones.
private struct ExpandableDescription: View {
    let text: String
    let collapsedLineLimit: Int

    @State private var isExpanded: Bool = true
    @State private var fullHeight: CGFloat = 0
    @State private var collapsedHeight: CGFloat = 0

    /// True when the unbounded version is taller than the line-limited
    /// version — i.e. the visible text would be cut off if we kept the
    /// `lineLimit` applied. The half-pixel epsilon avoids flapping caused by
    /// sub-pixel layout rounding.
    private var isTruncated: Bool {
        fullHeight > 0
            && collapsedHeight > 0
            && fullHeight > collapsedHeight + 0.5
    }

    private var showsToggle: Bool {
        // Only offer the toggle when the text would actually be cut off at
        // the collapsed line limit. Short posts never need a "Show less" button.
        isTruncated
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(.primary.opacity(0.9))
                .lineLimit(isExpanded ? nil : collapsedLineLimit)
                .fixedSize(horizontal: false, vertical: true)
                .background(fullHeightProbe)
                .background(collapsedHeightProbe)
                .onPreferenceChange(ExpandableTextFullHeightKey.self) { value in
                    fullHeight = value
                }
                .onPreferenceChange(ExpandableTextCollapsedHeightKey.self) { value in
                    collapsedHeight = value
                }

            if showsToggle {
                Button {
                    Haptics.lightImpact()
                    withAnimation(.easeInOut(duration: 0.22)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(isExpanded ? "Show less" : "Read more")
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.85))
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Hidden full-height ghost. Reports its rendered height back through a
    /// preference so the parent can compare it against the collapsed version.
    private var fullHeightProbe: some View {
        Text(text)
            .font(.system(size: 14))
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .hidden()
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: ExpandableTextFullHeightKey.self,
                        value: proxy.size.height
                    )
                }
            )
    }

    /// Hidden collapsed-height ghost. Always rendered with the line limit so
    /// `isTruncated` stays accurate even while the visible text is expanded.
    private var collapsedHeightProbe: some View {
        Text(text)
            .font(.system(size: 14))
            .lineLimit(collapsedLineLimit)
            .fixedSize(horizontal: false, vertical: true)
            .hidden()
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: ExpandableTextCollapsedHeightKey.self,
                        value: proxy.size.height
                    )
                }
            )
    }
}

private struct ExpandableTextFullHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ExpandableTextCollapsedHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
