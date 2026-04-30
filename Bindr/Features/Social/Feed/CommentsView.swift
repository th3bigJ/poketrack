import SwiftUI

struct CommentsView: View {
    @Environment(AppServices.self) private var services

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
                                                    .background(.ultraThinMaterial, in: Circle())
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
        .task {
            await loadComments()
        }
        .sheet(item: $sharedContentDetail) { sharedContent in
            NavigationStack {
                SharedContentView(content: sharedContent)
                    .environment(services)
            }
        }
    }

    @ViewBuilder
    private func commentRow(_ row: SocialFeedService.CommentDisplay) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.author?.displayName ?? row.author?.username ?? "Collector")
                    .font(.subheadline.weight(.semibold))
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

            Button {
                Task { await openSharedContent() }
            } label: {
                HStack(spacing: 8) {
                    if isLoadingSharedContent {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.up.right.square")
                    }
                    Text("View Content")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoadingSharedContent)
        }
    }

    private var postCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let actor = sourceItem?.actor {
                    ProfileAvatarView(profile: actor, size: 26)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(sourceItem?.actor?.displayName ?? sourceItem?.actor?.username ?? "Post")
                        .font(.subheadline.weight(.semibold))
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
