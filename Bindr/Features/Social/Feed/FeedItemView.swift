import SwiftUI

// MARK: - FeedItemView

struct FeedItemView: View {
    @Environment(AppServices.self) private var services
    let group: GroupedFeedItem
    var showsInteractionBar: Bool = true
    var isCardTapEnabled: Bool = true

    private var item: SocialFeedService.FeedItem { group.primary }

    @State private var isCommentsPresented = false
    @State private var commentsRefreshToken = 0

    private var canOpenComments: Bool {
        item.content != nil && item.type != .friendship
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            content

            if showsInteractionBar, item.type != .friendship {
                InteractionBar(
                    item: item,
                    refreshToken: commentsRefreshToken,
                    onOpenComments: { isCommentsPresented = true }
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(Color(hex: "141414"))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard isCardTapEnabled, canOpenComments else { return }
            isCommentsPresented = true
        }
        .sheet(isPresented: $isCommentsPresented, onDismiss: {
            commentsRefreshToken += 1
        }) {
            if let content = item.content {
                NavigationStack {
                    CommentsView(content: content, sourceItem: item)
                        .environment(services)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            if let username = item.actor?.username {
                NavigationLink(value: SocialDestination.friendProfile(username: username)) {
                    avatarView
                }
                .buttonStyle(.plain)
            } else {
                avatarView
            }

            VStack(alignment: .leading, spacing: 1) {
                if let username = item.actor?.username {
                    NavigationLink(value: SocialDestination.friendProfile(username: username)) {
                        Text(actorName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(hex: "F0F0F0"))
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(actorName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: "F0F0F0"))
                }

                Text("@\(item.actor?.username ?? "trainer") · \(SocialFeedService.shortRelativeDate(item.createdAt))")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: "F0F0F0").opacity(0.55))
            }

            Spacer()
            TypePill(label: badgeText, color: typeAccentColor)
        }
    }

    private var avatarView: some View {
        Group {
            if let actor = item.actor {
                ProfileAvatarView(profile: actor, size: 34)
            } else {
                Circle()
                    .fill(Color(hex: "1C1C1C"))
                    .frame(width: 34, height: 34)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color(hex: "F0F0F0").opacity(0.55))
                    }
            }
        }
        .frame(width: 34, height: 34)
        .clipShape(Circle())
        .overlay {
            Circle().stroke(typeAccentColor.opacity(0.85), lineWidth: 2)
        }
    }

    private var content: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text(cardTitle)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color(hex: "F0F0F0"))
                    .lineLimit(2)

                if let bodyText {
                    Text(bodyText)
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: "F0F0F0").opacity(0.55))
                        .lineLimit(2)
                }

                if let metaText {
                    Text(metaText)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: "F0F0F0").opacity(0.3))
                }

                if item.type == .pull, let pullCard = item.pullCardName {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(typeAccentColor)
                            .frame(width: 6, height: 6)
                        Text(pullCard)
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(typeAccentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(typeAccentColor.opacity(0.094), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(typeAccentColor.opacity(0.25), lineWidth: 1)
                    }
                }
            }

            Spacer(minLength: 8)
            CardStackPreview(colors: stackColors, size: item.type == .pull ? 42 : 38)
        }
    }

    private var actorName: String {
        item.actor?.displayName ?? item.actor?.username ?? "Trainer"
    }

    private var cardTitle: String {
        if item.type == .pull {
            return item.pullSetName ?? "Pack pull"
        }
        return item.content?.title ?? fallbackTitle
    }

    private var bodyText: String? {
        switch item.type {
        case .pull:
            return item.pullRarity ?? "Shared a new pull."
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

    private var badgeText: String {
        switch item.type {
        case .pull: return "PULL"
        case .dailyDigest: return "DIGEST"
        case .sharedContent:
            switch item.content?.contentType {
            case .binder: return "BINDER"
            case .deck: return "DECK"
            case .wishlist: return "WISHLIST"
            default: return "SHARE"
            }
        case .friendship: return "CONNECTED"
        case .wishlistMatch: return "MATCH"
        case .vote: return "VOTE"
        case .comment: return "COMMENT"
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
            case .binder: return Color(hex: "E8B84B")
            case .deck: return Color(hex: "5B9CF6")
            case .wishlist: return Color(hex: "A78BFA")
            default: return Color(hex: "E8B84B")
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
        }
    }
}

private struct TypePill: View {
    let label: String
    let color: Color

    var body: some View {
        Text(label.uppercased())
            .font(.system(size: 10, weight: .bold))
            .tracking(0.4)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(color.opacity(0.19), lineWidth: 1)
            }
    }
}

private struct CardStackPreview: View {
    let colors: [Color]
    let size: CGFloat

    var body: some View {
        ZStack(alignment: .leading) {
            ForEach(Array(colors.prefix(4).enumerated()), id: \.offset) { index, color in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(color)
                    .frame(width: size * 0.7, height: size)
                    .overlay {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    }
                    .offset(x: CGFloat(index) * 8)
                    .zIndex(Double(index))
            }
        }
        .frame(width: size * 0.7 + CGFloat(max(colors.prefix(4).count - 1, 0)) * 8, height: size)
    }
}

// MARK: - InteractionBar

struct InteractionBar: View {
    @Environment(AppServices.self) private var services
    let item: SocialFeedService.FeedItem
    let refreshToken: Int
    let onOpenComments: () -> Void

    @State private var aggregate = SocialFeedService.VoteAggregate(upvoteCount: 0, downvoteCount: 0, myVoteType: nil)
    @State private var commentCount = 0
    @State private var isBusy = false

    var body: some View {
        VStack(spacing: 10) {
            Rectangle()
                .fill(Color.white.opacity(0.05))
                .frame(height: 1)

            HStack(spacing: 6) {
                voteButton(type: .upvote)
                voteButton(type: .downvote)
                Text("\(aggregate.score)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(hex: "F0F0F0").opacity(0.75))
                    .padding(.horizontal, 8)

                Spacer()

                Button {
                    onOpenComments()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "bubble.left")
                            .font(.system(size: 12, weight: .semibold))
                        Text("\(commentCount)")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(Color(hex: "F0F0F0").opacity(0.3))
                }
                .buttonStyle(.plain)
            }
        }
        .task { await refresh() }
        .onChange(of: refreshToken) { _, _ in
            Task { await refresh() }
        }
    }

    private func voteButton(type: ReactionType) -> some View {
        let isActive = aggregate.myVoteType == type
        let count = type == .upvote ? aggregate.upvoteCount : aggregate.downvoteCount
        let symbol = type == .upvote ? "arrow.up" : "arrow.down"
        let tint = type == .upvote ? Color(hex: "52C97C") : Color(hex: "E05252")

        return Button {
            Task { await toggleVote(type) }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .bold))
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: isActive ? .bold : .regular))
                        .foregroundStyle(isActive ? tint : Color(hex: "F0F0F0").opacity(0.55))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(isActive ? tint.opacity(0.15) : .clear, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(isActive ? tint.opacity(0.37) : Color.white.opacity(0.09), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
    }

    private func refresh() async {
        guard let contentID = item.content?.id else { return }
        do {
            async let agg = services.socialFeed.fetchVoteAggregate(for: contentID)
            async let cnt = services.socialFeed.fetchCommentCount(for: contentID)
            aggregate = try await agg
            commentCount = try await cnt
        } catch {}
    }

    private func toggleVote(_ type: ReactionType) async {
        guard let contentID = item.content?.id else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await services.socialFeed.toggleVote(type: type, to: contentID)
            aggregate = try await services.socialFeed.fetchVoteAggregate(for: contentID)
        } catch {}
    }
}

// MARK: - InteractionRow

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
