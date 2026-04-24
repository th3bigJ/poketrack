import SwiftUI

struct CommentsView: View {
    @Environment(AppServices.self) private var services

    let content: SocialFeedService.FeedContentSummary

    @State private var comments: [SocialFeedService.CommentDisplay] = []
    @State private var reactions: [SocialFeedService.FeedItem] = []
    @State private var isLoading = false
    @State private var composerText = ""
    @State private var replyingTo: UUID?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            List {
                if !reactions.isEmpty {
                    Section("Reactions") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(reactions, id: \.id) { item in
                                    VStack(spacing: 4) {
                                        if let profile = item.actor {
                                            ProfileAvatarView(profile: profile, size: 32)
                                        }
                                        if let type = item.reactionType {
                                            Text(emoji(for: type))
                                                .font(.caption2)
                                                .padding(2)
                                                .background(.ultraThinMaterial, in: Circle())
                                                .offset(x: 10, y: -10)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 8)
                        }
                    }
                }

                if isLoading {
                    Section {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Loading comments…")
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if comments.isEmpty {
                    ContentUnavailableView(
                        "No Comments Yet",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("Start the conversation on this \(content.contentType == .deck ? "deck" : "binder").")
                    )
                    .frame(maxWidth: .infinity)
                } else {
                    ForEach(comments) { row in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(row.author?.displayName ?? row.author?.username ?? "Collector")
                                    .font(.subheadline.weight(.semibold))
                                Spacer(minLength: 8)
                                if let createdAt = row.comment.createdAt {
                                    Text(createdAt, style: .relative)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
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
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .listStyle(.plain)
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
                    .textFieldStyle(.roundedBorder)

                Button("Send") {
                    Task { await submitComment() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(12)
        .background(.bar)
    }

    private func loadComments() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let commentsTask = services.socialFeed.fetchComments(for: content.id)
            async let reactionsTask = services.socialFeed.fetchReactions(for: content.id)
            
            let (loadedComments, loadedReactions) = try await (commentsTask, reactionsTask)
            comments = loadedComments
            reactions = loadedReactions
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func emoji(for type: ReactionType) -> String {
        switch type {
        case .fire: return "🔥"
        case .like: return "⭐"
        case .wow: return "👀"
        }
    }

    private func submitComment() async {
        let text = composerText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            try await services.socialFeed.postComment(body: text, parentID: replyingTo, to: content.id)
            composerText = ""
            replyingTo = nil
            await loadComments()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
