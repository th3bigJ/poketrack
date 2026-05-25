import SwiftUI

struct CommentsView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    let content: SocialFeedService.FeedContentSummary
    let sourceItem: SocialFeedService.FeedItem?

    @State private var comments: [SocialFeedService.CommentDisplay] = []
    @State private var votes: [SocialFeedService.FeedItem] = []
    @State private var isLoading = false
    @State private var composerText = ""
    @State private var replyingTo: UUID?
    @State private var errorMessage: String?
    @State private var sharedContentDetail: SharedContent?
    @State private var isLoadingSharedContent = false
    /// For pull-type posts: the resolved ``Card`` shown inline in the post
    /// header so the user can tap straight to ``CardDetailSheet`` without the
    /// View Content → SharedContentView detour.
    @State private var pullCard: Card?
    /// Drives the ``CardDetailSheet`` presentation for pull posts.
    @State private var presentedPullCard: Card?
    @FocusState private var isComposerFocused: Bool

    init(
        content: SocialFeedService.FeedContentSummary,
        sourceItem: SocialFeedService.FeedItem? = nil
    ) {
        self.content = content
        self.sourceItem = sourceItem
    }

    var body: some View {
        VStack(spacing: 0) {
            sheetPullArea

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("POST")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                        
                        postHeader
                            .padding(.horizontal, 16)
                    }
                    .padding(.top, 16)
                    .contentShape(Rectangle())
                    .gesture(sheetDismissDragGesture)

                    VStack(alignment: .leading, spacing: 16) {
                        Text("COMMENTS")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)

                        if isLoading {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("Loading comments…")
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)
                        } else if comments.isEmpty {
                            ContentUnavailableView(
                                "No Comments Yet",
                                systemImage: "bubble.left.and.bubble.right",
                                description: Text("Start the conversation on this \(content.contentType == .deck ? "deck" : "binder").")
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.top, 20)
                        } else {
                            LazyVStack(alignment: .leading, spacing: 20) {
                                ForEach(comments) { row in
                                    commentRow(row)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }

                    if !votes.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("VOTES")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 16)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(votes, id: \.id) { item in
                                        VStack(spacing: 4) {
                                            if let profile = item.actor {
                                                ProfileAvatarView(profile: profile, size: 32)
                                            }
                                            if let type = item.voteType {
                                                Text(emoji(for: type))
                                                    .font(.caption2)
                                                    .padding(2)
                                                    .background(.thinMaterial, in: Circle())
                                                    .offset(x: 10, y: -10)
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 16)
                    }
                    
                    Spacer(minLength: 100) // Space for composer
                }
            }
            .refreshable {
                await loadComments()
            }

            composer
        }
        .navigationTitle("Comments")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await loadComments()
            // For pull posts, resolve the card up-front so the inline
            // card row is ready immediately — no "View Content" tap needed.
            if content.contentType == .pull,
               let cardID = sourceItem?.pullCardID ?? sourceItem?.thumbnails?.first,
               pullCard == nil {
                pullCard = await services.cardData.loadCard(masterCardId: cardID)
            }
        }
        .sheet(item: $sharedContentDetail) { sharedContent in
            NavigationStack {
                SharedContentView(content: sharedContent)
                    .environment(services)
            }
        }
        .sheet(item: $presentedPullCard) { card in
            CardDetailSheet(cards: [card], startIndex: 0)
                .environment(services)
        }
    }

    private var sheetPullArea: some View {
        VStack(spacing: 0) {
            Text("Comments")
                .font(.headline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.top, 18)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .gesture(sheetDismissDragGesture)
    }

    private var sheetDismissDragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onEnded { value in
                guard value.translation.height > 70,
                      abs(value.translation.height) > abs(value.translation.width) else { return }
                dismiss()
            }
    }

    @ViewBuilder
    private func commentRow(_ row: SocialFeedService.CommentDisplay) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 4) {
                    Text(row.author?.displayName ?? row.author?.username ?? "Collector")
                        .font(.subheadline.weight(.semibold))
                    if let author = row.author {
                        PremiumBadgeView(profile: author, size: 10)
                    }
                }
                Spacer(minLength: 8)
                if let createdAt = row.comment.createdAt {
                    Text(SocialFeedService.shortRelativeDate(createdAt))
                        .font(.caption)
                        .foregroundStyle(Color.secondary.opacity(0.8))
                }
            }

            Text(row.comment.body)
                .font(.subheadline)
                .foregroundStyle(.primary)

            Button("Reply") {
                replyingTo = row.comment.id
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.leading, CGFloat(row.depth) * 14)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if replyingTo != nil {
                HStack {
                    Label("Replying in thread", systemImage: "arrowshape.turn.up.left")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel") {
                        replyingTo = nil
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.plain)
                }
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField("Write a comment…", text: $composerText, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($isComposerFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )

                Button {
                    Task { await submitComment() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? Color(uiColor: .secondarySystemFill)
                            : services.theme.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .animation(.easeInOut(duration: 0.15), value: composerText.isEmpty)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var postHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let sourceItem {
                FeedItemView(
                    group: GroupedFeedItem(id: sourceItem.id, primary: sourceItem, interactions: []),
                    showsInteractionBar: false,
                    isCardTapEnabled: false
                )
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            } else {
                postCard
            }

            if content.contentType == .pull {
                if let card = pullCard {
                    Button {
                        presentedPullCard = card
                    } label: {
                        HStack(spacing: 12) {
                            let imageURL = AppConfiguration.imageURL(relativePath: card.imageLowSrc)
                            CachedAsyncImage(url: imageURL, targetSize: CGSize(width: 80, height: 112)) { img in
                                img.resizable().scaledToFit()
                            } placeholder: {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.secondary.opacity(0.15))
                            }
                            .frame(width: 44, height: 62)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                            VStack(alignment: .leading, spacing: 3) {
                                Text(card.cardName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text("Tap to view card")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(uiColor: .secondarySystemBackground),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    // Still resolving the card — show a quiet placeholder so
                    // the layout doesn't jump when the card loads in.
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Loading card…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .background(Color(uiColor: .secondarySystemBackground),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            } else {
                sharedContentBanner
            }
        }
    }

    private var sharedContentBanner: some View {
        Button {
            Task { await openSharedContent() }
        } label: {
            HStack(spacing: 12) {
                CommentsContentPreviewThumb(
                    contentType: content.contentType,
                    thumbnailIDs: Array((sourceItem?.thumbnails ?? []).prefix(4)),
                    cardCount: content.cardCount
                )
                .frame(width: 54, height: 62)

                VStack(alignment: .leading, spacing: 3) {
                    Text(content.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(openBannerSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if isLoadingSharedContent {
                    ProgressView()
                        .controlSize(.small)
                        .tint(services.theme.accentColor)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(uiColor: .secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(isLoadingSharedContent)
    }

    private var openBannerSubtitle: String {
        let noun: String = {
            switch content.contentType {
            case .binder: return "binder"
            case .deck: return "deck"
            case .folder: return "folder"
            case .wishlist: return "wishlist"
            case .collection: return "collection"
            case .dailyDigest: return "digest"
            case .pull: return "card"
            }
        }()
        if let count = content.cardCount, count > 0, content.contentType != .dailyDigest {
            return "Tap to view \(noun) · \(count) \(count == 1 ? "card" : "cards")"
        }
        return "Tap to view \(noun)"
    }

    private var postCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let actor = sourceItem?.actor {
                    ProfileAvatarView(profile: actor, size: 26)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(sourceItem?.actor?.displayName ?? sourceItem?.actor?.username ?? "Post")
                            .font(.subheadline.weight(.semibold))
                        if let actor = sourceItem?.actor {
                            PremiumBadgeView(profile: actor, size: 10)
                        }
                    }
                    if let createdAt = sourceItem?.createdAt {
                        Text(createdAt, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(content.contentType.rawValue.capitalized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            Text(content.title)
                .font(.headline)
                .foregroundStyle(.primary)

            if let description = content.description, !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let cardCount = content.cardCount {
                Text("\(cardCount) cards")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func openSharedContent() async {
        isLoadingSharedContent = true
        defer { isLoadingSharedContent = false }
        do {
            sharedContentDetail = try await services.socialShare.fetchSharedContent(id: content.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadComments() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let commentsTask = services.socialFeed.fetchComments(for: content.id)
            async let votesTask = services.socialFeed.fetchVotes(for: content.id)
            
            let (loadedComments, loadedVotes) = try await (commentsTask, votesTask)
            comments = loadedComments
            votes = loadedVotes
            errorMessage = nil
        } catch is CancellationError {
            // Ignore
        } catch let error as URLError where error.code == .cancelled {
            // Ignore
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func emoji(for type: ReactionType) -> String {
        switch type {
        case .upvote: return "⬆️"
        case .downvote: return "⬇️"
        }
    }

    private func submitComment() async {
        let text = composerText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        // Crisp click on send — the user is committing to a post, so the
        // feedback should feel firmer than a mere navigation tap.
        Haptics.rigidImpact()
        do {
            try await services.socialFeed.postComment(body: text, parentID: replyingTo, to: content.id)
            composerText = ""
            replyingTo = nil
            isComposerFocused = false
            Haptics.success()
            await loadComments()
        } catch {
            errorMessage = error.localizedDescription
            Haptics.error()
        }
    }
}

private struct CommentsContentPreviewThumb: View {
    @Environment(AppServices.self) private var services
    @Environment(\.colorScheme) private var colorScheme

    let contentType: SharedContentType
    let thumbnailIDs: [String]
    let cardCount: Int?

    @State private var cardImageURLs: [URL?] = []

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if thumbnailIDs.isEmpty {
                fallbackIcon
            } else {
                cardStack
            }

            if let cardCount, cardCount > 1 {
                Text("\(cardCount)")
                    .font(.system(size: 9, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.thinMaterial, in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(Color.white.opacity(0.35), lineWidth: 0.5)
                    }
                    .shadow(color: .black.opacity(0.24), radius: 2, x: 0, y: 1)
                    .offset(x: 3, y: 2)
            }
        }
        .task(id: thumbnailIDs.joined(separator: ",")) {
            await resolveCardImageURLs()
        }
    }

    private var cardStack: some View {
        ZStack(alignment: .leading) {
            ForEach(Array(thumbnailIDs.prefix(4).enumerated()), id: \.offset) { index, _ in
                let url = index < cardImageURLs.count ? cardImageURLs[index] : nil
                cardThumb(url: url, index: index)
            }
        }
        .frame(width: 52, height: 62, alignment: .leading)
    }

    private func cardThumb(url: URL?, index: Int) -> some View {
        Group {
            if let url {
                CachedAsyncImage(url: url, targetSize: CGSize(width: 56, height: 78)) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(accentColor.opacity(0.16))
                }
            } else {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(accentColor.opacity(0.16))
            }
        }
        .frame(width: 38, height: 54)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.14 : 0.45), lineWidth: 0.5)
        }
        .rotationEffect(.degrees(Double(index) * 2.5 - 3))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.22 : 0.12), radius: 4, x: 0, y: 2)
        .offset(x: CGFloat(index) * 5)
        .zIndex(Double(index))
    }

    private var fallbackIcon: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(accentColor.opacity(colorScheme == .dark ? 0.20 : 0.14))
            .overlay {
                Image(systemName: iconName)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(accentColor)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(accentColor.opacity(0.18), lineWidth: 1)
            }
    }

    private func resolveCardImageURLs() async {
        guard !thumbnailIDs.isEmpty else {
            cardImageURLs = []
            return
        }
        var resolved: [URL?] = []
        for cardID in thumbnailIDs.prefix(4) {
            if let card = await services.cardData.loadCard(masterCardId: cardID) {
                resolved.append(AppConfiguration.imageURL(relativePath: card.imageLowSrc))
            } else {
                resolved.append(nil)
            }
        }
        cardImageURLs = resolved
    }

    private var iconName: String {
        switch contentType {
        case .binder: return "books.vertical.fill"
        case .deck: return "rectangle.stack.fill"
        case .folder: return "folder.fill"
        case .wishlist: return "heart.fill"
        case .collection: return "square.grid.2x2.fill"
        case .dailyDigest: return "chart.line.uptrend.xyaxis"
        case .pull: return "sparkles"
        }
    }

    private var accentColor: Color {
        switch contentType {
        case .binder: return Color(hex: "E8B84B")
        case .deck: return Color(hex: "5B9CF6")
        case .folder: return Color(hex: "22B8CF")
        case .wishlist: return Color(hex: "A78BFA")
        case .collection: return Color(hex: "52C97C")
        case .dailyDigest: return Color(hex: "5B9CF6")
        case .pull: return Color(hex: "52C97C")
        }
    }
}
