import SwiftUI

// MARK: - FeedItemView

struct FeedItemView: View {
    @Environment(AppServices.self) private var services
    let group: GroupedFeedItem

    @State private var isExpanded = false

    private var item: SocialFeedService.FeedItem { group.primary }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Header ──────────────────────────────────────────────
            HStack(alignment: .center, spacing: 10) {
                // Avatar — taps to profile
                if let username = item.actor?.username {
                    NavigationLink(value: SocialDestination.friendProfile(username: username)) {
                        avatarView
                    }
                    .buttonStyle(.plain)
                } else {
                    avatarView
                }

                // Name + time — also taps to profile
                VStack(alignment: .leading, spacing: 1) {
                    if let username = item.actor?.username {
                        NavigationLink(value: SocialDestination.friendProfile(username: username)) {
                            Text(actorName)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text(actorName)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                    }
                    Text(SocialFeedService.shortRelativeDate(item.createdAt))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()
                eventBadge
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            // ── Content ─────────────────────────────────────────────
            contentView
                .padding(.horizontal, 14)
                .padding(.bottom, 12)

            // ── Interaction bar ──────────────────────────────────────
            if item.type != .friendship {
                interactionBar
            }
        }
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(typeAccentColor.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: typeAccentColor.opacity(0.07), radius: 12, y: 4)
    }

    // MARK: - Avatar

    private var avatarView: some View {
        ZStack {
            if let actor = item.actor {
                ProfileAvatarView(profile: actor, size: 38)
            } else {
                Circle()
                    .fill(LinearGradient(colors: [Color(hex: "6366f1"), Color(hex: "4f46e5")], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 38, height: 38)
                    .overlay(Image(systemName: "person.fill").foregroundStyle(.white.opacity(0.8)))
            }
        }
        .frame(width: 38, height: 38)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(typeAccentColor.opacity(0.5), lineWidth: 1.5)
        )
    }

    // MARK: - Event Badge

    @ViewBuilder
    private var eventBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: badgeIcon)
                .font(.system(size: 9, weight: .black))
            Text(badgeText)
                .font(.system(size: 9, weight: .black))
                .kerning(0.5)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(typeAccentColor.opacity(0.15))
        .foregroundStyle(typeAccentColor)
        .clipShape(Capsule())
    }

    // MARK: - Content

    @ViewBuilder
    private var contentView: some View {
        switch item.type {
        case .pull:
            PullEventView(item: item)
        case .dailyDigest:
            DailyDigestView(item: item)
        case .sharedContent:
            if item.content?.contentType == .binder {
                BinderShareView(item: item)
            } else if item.content?.contentType == .deck {
                DeckShareView(item: item)
            } else if let title = item.content?.title {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
        case .friendship:
            HStack(spacing: 6) {
                Image(systemName: "person.2.fill")
                    .foregroundStyle(.green)
                Text("You're now connected!")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        case .wishlistMatch:
            HStack(spacing: 6) {
                Image(systemName: "star.fill")
                    .foregroundStyle(.pink)
                Text("Has a card from your wishlist!")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        case .reaction:
            if let title = item.content?.title {
                Text("Reacted to **\(title)**")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        case .comment:
            VStack(alignment: .leading, spacing: 4) {
                if let title = item.content?.title {
                    Text("Commented on **\(title)**")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let body = item.commentBody {
                    Text("\"\(body)\"")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                }
            }
        }
    }

    // MARK: - Styling Helpers

    private var actorName: String {
        item.actor?.displayName ?? item.actor?.username ?? "Trainer"
    }

    private var typeAccentColor: Color {
        switch item.type {
        case .pull:          return Color(hex: "f59e0b")
        case .dailyDigest:   return Color(hex: "5b9df9")
        case .sharedContent:
            switch item.content?.contentType {
            case .binder:    return Color(hex: "a855f7")
            case .deck:      return Color(hex: "22c55e")
            default:         return Color(hex: "5b9df9")
            }
        case .friendship:    return Color(hex: "22c55e")
        case .wishlistMatch: return Color(hex: "f43f5e")
        case .reaction:      return Color(hex: "f59e0b")
        case .comment:       return Color(hex: "5b9df9")
        }
    }

    private var cardBackground: some ShapeStyle {
        let base = Color(uiColor: .systemBackground)
        return AnyShapeStyle(base)
    }

    private var badgeText: String {
        switch item.type {
        case .pull:          return "PULL"
        case .dailyDigest:   return "DIGEST"
        case .sharedContent:
            switch item.content?.contentType {
            case .binder: return "BINDER"
            case .deck:   return "DECK"
            default:      return "SHARE"
            }
        case .friendship:    return "CONNECTED"
        case .wishlistMatch: return "MATCH"
        case .reaction:      return "REACTION"
        case .comment:       return "COMMENT"
        }
    }

    private var badgeIcon: String {
        switch item.type {
        case .pull:          return "sparkles"
        case .dailyDigest:   return "calendar"
        case .sharedContent: return "square.and.arrow.up"
        case .friendship:    return "person.2.fill"
        case .wishlistMatch: return "star.fill"
        case .reaction:      return "face.smiling"
        case .comment:       return "bubble.left.fill"
        }
    }

    private var interactionBar: some View {
        InteractionBar(item: item)
            .padding(.top, 4)
    }
}

// MARK: - InteractionBar

struct InteractionBar: View {
    @Environment(AppServices.self) private var services
    let item: SocialFeedService.FeedItem
    
    @State private var aggregate = SocialFeedService.ReactionAggregate(totalCount: 0, byType: [:], myReactionType: nil)
    @State private var commentCount = 0
    @State private var isBusy = false
    @State private var isCommentsPresented = false

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .padding(.horizontal, 14)

            HStack(spacing: 10) {
                reactionPill(type: ReactionType.fire, emoji: "🔥")
                reactionPill(type: ReactionType.like, emoji: "⭐")
                reactionPill(type: ReactionType.wow, emoji: "👀")

                Spacer()

                // Unified interactions button
                Button {
                    isCommentsPresented = true
                } label: {
                    HStack(spacing: 6) {
                        if aggregate.totalCount > 0 {
                            HStack(spacing: -4) {
                                ForEach(Array(aggregate.byType.keys.prefix(3)), id: \.self) { type in
                                    Text(emoji(for: type))
                                        .font(.system(size: 10))
                                        .padding(2)
                                        .background(.ultraThinMaterial, in: Circle())
                                }
                            }
                        }
                        
                        Text("\(commentCount) comments")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.primary.opacity(0.8))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                // Comments sheet button (shortcut)
                Button {
                    isCommentsPresented = true
                } label: {
                    Image(systemName: "bubble.left.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .task { await refresh() }
        .onChange(of: isCommentsPresented) { _, newValue in
            if !newValue {
                Task { await refresh() }
            }
        }
        .sheet(isPresented: $isCommentsPresented) {
            if let content = item.content {
                NavigationStack {
                    CommentsView(content: content)
                        .environment(services)
                }
            }
        }
    }

    private func emoji(for type: ReactionType) -> String {
        switch type {
        case .fire: return "🔥"
        case .like: return "⭐"
        case .wow: return "👀"
        }
    }

    private func reactionPill(type: ReactionType, emoji: String) -> some View {
        let count = aggregate.byType[type] ?? 0
        let isActive = aggregate.myReactionType == type
        return Button {
            Task { await toggleReaction(type) }
        } label: {
            HStack(spacing: 4) {
                Text(emoji).font(.system(size: 14))
                if count > 0 {
                    Text("\(count)")
                        .font(.caption.weight(.bold))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isActive ? Color(hex: "f59e0b").opacity(0.18) : Color.secondary.opacity(0.15))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(isActive ? Color(hex: "f59e0b").opacity(0.5) : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
    }

    private func refresh() async {
        guard let contentID = item.content?.id else { return }
        do {
            async let agg = services.socialFeed.fetchReactionAggregate(for: contentID)
            async let cnt = services.socialFeed.fetchCommentCount(for: contentID)
            aggregate = try await agg
            commentCount = try await cnt
        } catch {}
    }

    private func toggleReaction(_ type: ReactionType) async {
        guard let contentID = item.content?.id else { return }
        isBusy = true; defer { isBusy = false }
        do {
            try await services.socialFeed.toggleReaction(type: type, to: contentID)
            aggregate = try await services.socialFeed.fetchReactionAggregate(for: contentID)
        } catch {}
    }
}

// MARK: - InteractionRow (expanded)

struct InteractionRow: View {
    let item: SocialFeedService.FeedItem

    var body: some View {
        HStack(spacing: 8) {
            if let actor = item.actor {
                ProfileAvatarView(profile: actor, size: 22)
                    .clipShape(Circle())
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(item.actor?.displayName ?? item.actor?.username ?? "Trainer")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Group {
                    if item.type == .comment, let body = item.commentBody {
                        Text(body).italic()
                    } else {
                        Text(item.type == .reaction ? "reacted" : "interacted")
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
