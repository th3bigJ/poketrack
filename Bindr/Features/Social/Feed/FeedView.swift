import SwiftUI

// MARK: - Grouped Feed Model

/// A primary feed event with any votes/comments on it collapsed underneath
struct GroupedFeedItem: Identifiable {
    let id: String
    let primary: SocialFeedService.FeedItem
    var interactions: [SocialFeedService.FeedItem]   // votes + comments on this post

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
            case .vote, .comment:
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
            .padding(.top, 0)
            .padding(.bottom, 100)
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
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
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
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
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
                    colors: [Color.primary.opacity(0.05), Color.primary.opacity(0.12), Color.primary.opacity(0.05)],
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

struct SocialAlertsSheet: View {
    @Binding var isPresented: Bool
    let onDeepLinkSelected: (URL) -> Void
    @Environment(AppServices.self) private var services

    private var groupedItems: [GroupedFeedItem] {
        let items = services.socialFeed.items
        var groups: [GroupedFeedItem] = []
        var contentIndex: [UUID: Int] = [:]
        for item in items {
            switch item.type {
            case .vote, .comment:
                if let contentID = item.content?.id, let idx = contentIndex[contentID] {
                    groups[idx].interactions.append(item)
                    continue
                }
                groups.append(GroupedFeedItem(id: item.id, primary: item, interactions: []))
            default:
                let idx = groups.count
                groups.append(GroupedFeedItem(id: item.id, primary: item, interactions: []))
                if let contentID = item.content?.id { contentIndex[contentID] = idx }
            }
        }
        return groups
    }

    var body: some View {
        SocialAlertsPreviewView(
            items: groupedItems,
            onDone: { isPresented = false },
            onDeepLinkSelected: { url in
                onDeepLinkSelected(url)
                isPresented = false
            }
        )
    }
}

struct NewPostPlaceholderView: View {
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("New Post")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)

                HStack {
                    Spacer(minLength: 0)
                    ChromeGlassCircleButton(accessibilityLabel: "Done") {
                        Haptics.lightImpact()
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            ContentUnavailableView(
                "Coming Soon",
                systemImage: "plus.circle",
                description: Text("Post sharing will be available in a future update.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct SocialAlertsPreviewView: View {
    let items: [GroupedFeedItem]
    let onDone: () -> Void
    let onDeepLinkSelected: (URL) -> Void

    private var activityItems: [GroupedFeedItem] {
        items.filter { group in
            switch group.primary.type {
            case .vote, .comment, .friendship, .wishlistMatch:
                return true
            default:
                return !group.interactions.isEmpty
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("Alerts")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)

                HStack {
                    Spacer(minLength: 0)
                    ChromeGlassCircleButton(accessibilityLabel: "Done") {
                        Haptics.lightImpact()
                        onDone()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    sectionLabel("WISHLIST MATCHES")
                    let matches = activityItems.filter { $0.primary.type == .wishlistMatch }
                    if matches.isEmpty {
                        emptyAlert("No wishlist matches yet.")
                    } else {
                        ForEach(matches) { group in
                            alertRow(group: group, tint: Color(hex: "E8B84B"), icon: "target")
                        }
                    }

                    sectionLabel("ALL ACTIVITY")
                        .padding(.top, 8)
                    if activityItems.isEmpty {
                        emptyAlert("Votes, comments, and friend activity will appear here.")
                    } else {
                        ForEach(activityItems) { group in
                            alertRow(group: group, tint: tint(for: group.primary), icon: icon(for: group.primary))
                        }
                    }
                }
                .padding(16)
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .tracking(0.88)
            .foregroundStyle(Color.secondary.opacity(0.3))
    }

    private func emptyAlert(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Color.secondary.opacity(0.55))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.primary.opacity(0.09), lineWidth: 1))
    }

    @ViewBuilder
    private func alertRow(group: GroupedFeedItem, tint: Color, icon: String) -> some View {
        let row = HStack(spacing: 10) {
            Circle()
                .fill(tint.opacity(0.15))
                .frame(width: 36, height: 36)
                .overlay {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(tint)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(alertTitle(for: group.primary))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(2)
                Text(SocialFeedService.shortRelativeDate(group.primary.createdAt))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondary.opacity(0.3))
            }

            Spacer()

            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
        }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

        if let deepLink = deepLinkURL(for: group.primary) {
            Button {
                Haptics.lightImpact()
                onDeepLinkSelected(deepLink)
            } label: {
                row
            }
            .buttonStyle(.plain)
            .padding(14)
            .background(tint.opacity(group.primary.type == .wishlistMatch ? 0.12 : 0), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(tint.opacity(0.2), lineWidth: 1))
        } else {
            row
                .padding(14)
                .background(tint.opacity(group.primary.type == .wishlistMatch ? 0.12 : 0), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(tint.opacity(0.2), lineWidth: 1))
        }
    }

    private func deepLinkURL(for item: SocialFeedService.FeedItem) -> URL? {
        switch item.type {
        case .friendship:
            return URL(string: "bindr://social/friends")
        case .comment:
            if let commentID = uuidFromFeedItemID(item.id, prefix: "comment-") {
                return URL(string: "bindr://social/feed/comment/\(commentID.uuidString)")
            }
            if let contentID = item.content?.id {
                return URL(string: "bindr://social/feed/content/\(contentID.uuidString)")
            }
            return URL(string: "bindr://social/feed")
        case .wishlistMatch:
            if let matchID = uuidFromFeedItemID(item.id, prefix: "wishlist-") {
                return URL(string: "bindr://social/feed/wishlist-match/\(matchID.uuidString)")
            }
            if let contentID = item.content?.id {
                return URL(string: "bindr://social/feed/content/\(contentID.uuidString)")
            }
            return URL(string: "bindr://social/feed")
        case .vote, .sharedContent, .pull, .dailyDigest:
            if let contentID = item.content?.id {
                return URL(string: "bindr://social/feed/content/\(contentID.uuidString)")
            }
            return URL(string: "bindr://social/feed")
        }
    }

    private func uuidFromFeedItemID(_ id: String, prefix: String) -> UUID? {
        guard id.hasPrefix(prefix) else { return nil }
        let raw = String(id.dropFirst(prefix.count))
        return UUID(uuidString: raw)
    }

    private func alertTitle(for item: SocialFeedService.FeedItem) -> String {
        let name = item.actor?.displayName ?? item.actor?.username ?? "A trainer"
        switch item.type {
        case .wishlistMatch:
            return "\(name) has a card from your wishlist"
        case .friendship:
            return "\(name) connected with you"
        case .vote:
            return "\(name) voted on \(item.content?.title ?? "your post")"
        case .comment:
            return "\(name) commented on \(item.content?.title ?? "your post")"
        default:
            return "\(name) shared \(item.content?.title ?? "an update")"
        }
    }

    private func tint(for item: SocialFeedService.FeedItem) -> Color {
        switch item.type {
        case .comment: return Color(hex: "5B9CF6")
        case .friendship: return Color(hex: "52C97C")
        case .wishlistMatch: return Color(hex: "E8B84B")
        case .vote: return Color(hex: "E05252")
        default: return Color(hex: "E8B84B")
        }
    }

    private func icon(for item: SocialFeedService.FeedItem) -> String {
        switch item.type {
        case .comment: return "bubble.left.fill"
        case .friendship: return "person.2.fill"
        case .wishlistMatch: return "target"
        case .vote: return "arrow.up.arrow.down"
        default: return "bell.fill"
        }
    }
}
