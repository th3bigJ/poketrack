import SwiftUI

// MARK: - Grouped Feed Model

/// A primary feed event with any reactions/comments on it collapsed underneath
struct GroupedFeedItem: Identifiable {
    let id: String
    let primary: SocialFeedService.FeedItem
    var interactions: [SocialFeedService.FeedItem]   // reactions + comments on this post

    var interactionSummary: String? {
        guard !interactions.isEmpty else { return nil }
        let reactors = Set(interactions.compactMap { $0.actor?.displayName ?? $0.actor?.username })
        let names = reactors.prefix(2).joined(separator: " & ")
        let extra = reactors.count > 2 ? " +\(reactors.count - 2)" : ""
        return "\(names)\(extra) interacted"
    }
}

// MARK: - FeedView

struct FeedView: View {
    @Environment(AppServices.self) private var services

    @State private var isInitialLoading = false
    @State private var isLoadingMore = false
    @State private var errorMessage: String?
    private let selectedScope: SocialFeedService.FeedScope = .everyone

    private var groupedItems: [GroupedFeedItem] {
        let items = services.socialFeed.items
        var groups: [GroupedFeedItem] = []
        var contentIndex: [UUID: Int] = [:]   // contentID → index into groups

        for item in items {
            switch item.type {
            case .reaction, .comment:
                // Try to attach to a parent post in the group list
                if let contentID = item.content?.id, let idx = contentIndex[contentID] {
                    groups[idx].interactions.append(item)
                    continue
                }
                // No parent post visible yet — show as standalone so nothing is lost
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

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if isInitialLoading && services.socialFeed.items.isEmpty {
                    loadingState
                } else if services.socialFeed.items.isEmpty {
                    emptyState
                } else {
                    feedList
                }
            }
        }
        .task {
            await refresh()
        }
        .onAppear {
            services.socialFeed.clearUnreadState()
            services.socialPush.clearAppBadgeCount()
        }
    }

    // MARK: - Subviews

    private var loadingState: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(0..<4, id: \.self) { _ in
                    ShimmerCard()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            ContentUnavailableView(
                errorMessage != nil ? "Feed Error" : "Nothing here yet",
                systemImage: errorMessage != nil ? "exclamationmark.triangle.fill" : "sparkles.rectangle.stack",
                description: Text(errorMessage ?? "When friends share binders, decks and collections, they'll appear here.")
            )
            if errorMessage != nil {
                Button("Try Again") { Task { await refresh() } }
                    .buttonStyle(.bordered)
            }
        }
    }

    private var feedList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(groupedItems) { group in
                    FeedItemView(group: group)
                        .onAppear {
                            guard group.id == groupedItems.last?.id else { return }
                            Task { await loadMore() }
                        }
                }

                if isLoadingMore {
                    ProgressView()
                        .padding()
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .refreshable { await refresh() }
    }


    // MARK: - Data

    private func refresh() async {
        isInitialLoading = true
        defer { isInitialLoading = false }
        do {
            _ = try await services.socialFeed.fetchFeed(refresh: true, pageSize: 30, scope: selectedScope)
            services.socialFeed.clearUnreadState()
            services.socialPush.clearAppBadgeCount()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadMore() async {
        guard !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            _ = try await services.socialFeed.loadMore(pageSize: 20)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Shimmer Placeholder

struct ShimmerCard: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color.white.opacity(0.05), Color.white.opacity(0.12), Color.white.opacity(0.05)],
                    startPoint: .init(x: phase - 0.3, y: 0),
                    endPoint: .init(x: phase + 0.3, y: 0)
                )
            )
            .frame(height: 100)
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1.4
                }
            }
    }
}
