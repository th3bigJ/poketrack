import SwiftUI

struct FeedItemView: View {
    @Environment(AppServices.self) private var services

    let item: SocialFeedService.FeedItem

    @State private var reactionAggregate = SocialFeedService.ReactionAggregate(totalCount: 0, byType: [:], myReactionType: nil)
    @State private var isReactionBusy = false
    @State private var isCommentsPresented = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(Color.secondary.opacity(0.16))
                    .frame(width: 32, height: 32)
                    .overlay {
                        Image(systemName: iconName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }

                VStack(alignment: .leading, spacing: 6) {
                    Text(primaryText)
                        .font(.subheadline.weight(.semibold))
                    if let secondaryText {
                        Text(secondaryText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text(item.createdAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            if let content = item.content, item.type != .friendship {
                interactionBar(for: content)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(12)
        .background(cardBackground)
        .task(id: item.id) {
            await refreshReactionAggregateIfNeeded()
        }
    }

    private var primaryText: String {
        let actorName = item.actor?.displayName ?? item.actor?.username ?? "A collector"
        switch item.type {
        case .sharedContent:
            guard let content = item.content else { return "\(actorName) shared something new." }
            return "\(actorName) shared a \(content.contentType.rawValue)."
        case .reaction:
            let reactionLabel = item.reactionType?.rawValue.capitalized ?? "Reacted"
            return "\(actorName) reacted (\(reactionLabel))."
        case .comment:
            return "\(actorName) commented on a post."
        case .friendship:
            return "You and \(actorName) are now friends."
        case .wishlistMatch:
            return "\(actorName) has a card from your wishlist."
        }
    }

    private var secondaryText: String? {
        switch item.type {
        case .sharedContent:
            return item.content?.title
        case .reaction:
            return item.content?.title
        case .comment:
            return item.commentBody
        case .friendship:
            return nil
        case .wishlistMatch:
            return item.wishlistCardID
        }
    }

    private var iconName: String {
        switch item.type {
        case .sharedContent:
            return "square.and.arrow.up"
        case .reaction:
            return "hand.thumbsup"
        case .comment:
            return "bubble.left"
        case .friendship:
            return "person.badge.plus"
        case .wishlistMatch:
            return "sparkles"
        }
    }

    @ViewBuilder
    private func interactionBar(for content: SocialFeedService.FeedContentSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ForEach(ReactionType.allCases, id: \.self) { type in
                    Button {
                        Task { await toggleReaction(type, contentID: content.id) }
                    } label: {
                        Image(systemName: type.systemImage)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(reactionAggregate.myReactionType == type ? Color.accentColor : Color.secondary)
                            .frame(width: 28, height: 28)
                            .background(
                                Circle()
                                    .fill((reactionAggregate.myReactionType == type ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12)))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(isReactionBusy)
                }

                Text("\(reactionAggregate.totalCount)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                if content.contentType != .wishlist {
                    Button {
                        isCommentsPresented = true
                    } label: {
                        Label("Comments", systemImage: "bubble.left.and.bubble.right")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .sheet(isPresented: $isCommentsPresented) {
            NavigationStack {
                CommentsView(content: content)
                    .environment(services)
            }
        }
    }

    @ViewBuilder
    private var cardBackground: some View {
        if #available(iOS 26.0, *) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                }
        }
    }

    private func refreshReactionAggregateIfNeeded() async {
        guard let contentID = item.content?.id else { return }
        do {
            reactionAggregate = try await services.socialFeed.fetchReactionAggregate(for: contentID)
        } catch {
            // Reactions are additive UX; keep feed card visible if this call fails.
        }
    }

    private func toggleReaction(_ type: ReactionType, contentID: UUID) async {
        isReactionBusy = true
        defer { isReactionBusy = false }
        do {
            try await services.socialFeed.toggleReaction(type: type, to: contentID)
            reactionAggregate = try await services.socialFeed.fetchReactionAggregate(for: contentID)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
