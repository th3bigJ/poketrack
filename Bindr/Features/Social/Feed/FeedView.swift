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

/// A run of consecutive feed items that share a "shape" — currently used for
/// collapsing multiple pulls from the same set or several shares of the same
/// content type into a single condensed row. Tapping the row expands the
/// underlying items inline so nothing is hidden.
struct ClusteredFeedRow: Identifiable {
    let id: String
    let kind: Kind
    let items: [GroupedFeedItem]

    enum Kind {
        /// Multiple pulls, same set, ≥2 distinct actors.
        case pullsFromSet(setName: String)
        /// Multiple shares of the same content type (e.g. 3 binders).
        case sharedContent(contentType: SharedContentType)
    }
}

/// Top-level row in the rendered feed — either a single grouped item or an
/// auto-consolidated cluster.
enum FeedRow: Identifiable {
    case single(GroupedFeedItem)
    case cluster(ClusteredFeedRow)

    var id: String {
        switch self {
        case .single(let g): return "single-\(g.id)"
        case .cluster(let c): return "cluster-\(c.id)"
        }
    }
}

// MARK: - FeedView

struct FeedView: View {
    @Environment(AppServices.self) private var services
    var selectedTab: Binding<SocialTab>? = nil
    var headerInset: CGFloat = 0

    @State private var isInitialLoading = false
    @State private var isLoadingMore = false
    @State private var errorMessage: String?
    /// Cluster IDs the user has tapped to expand. Persists for the life of the
    /// view so scrolling away and back doesn't collapse the user's choice.
    @State private var expandedClusterIDs: Set<String> = []

    private var groupedItems: [GroupedFeedItem] {
        // Only show actual content posts (binders, pulls, etc) in the main Feed list.
        // Interactions (votes, comments) are visible in the Alerts tab or collapsed 
        // underneath their parents in this group logic.
        let allItems = services.socialFeed.items
        let items = allItems.filter { item in
            switch item.type {
            case .vote, .comment, .friendship, .wishlistMatch:
                return false
            default:
                return true
            }
        }
        
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

    /// Walk the grouped items in order and collapse adjacent runs that share
    /// the same "shape" (same set for pulls, same contentType for shares) and
    /// were posted by ≥2 distinct actors. The user's eye reads four "Sam
    /// pulled from Twilight Masquerade / Alex pulled from Twilight Masquerade"
    /// rows as visual noise; collapsing them into "Sam, Alex and 2 others
    /// pulled from Twilight Masquerade" keeps signal density high and makes
    /// the feed feel curated rather than a raw firehose.
    private var feedRows: [FeedRow] {
        let groups = groupedItems
        guard !groups.isEmpty else { return [] }

        var rows: [FeedRow] = []
        var run: [GroupedFeedItem] = []
        var runKey: String?
        var runKind: ClusteredFeedRow.Kind?

        func flushRun() {
            guard !run.isEmpty else { return }
            // Need at least 2 distinct actors before we collapse — a single
            // actor double-posting shouldn't disappear behind "and 1 other".
            let distinctActors = Set(run.compactMap { $0.primary.actor?.id })
            if run.count >= 2, distinctActors.count >= 2, let kind = runKind, let key = runKey {
                let cluster = ClusteredFeedRow(
                    id: "\(key)-\(run.first?.id ?? "")",
                    kind: kind,
                    items: run
                )
                rows.append(.cluster(cluster))
            } else {
                rows.append(contentsOf: run.map { FeedRow.single($0) })
            }
            run = []
            runKey = nil
            runKind = nil
        }

        for group in groups {
            let (key, kind) = clusterKey(for: group)
            if let key, let kind {
                if key == runKey {
                    run.append(group)
                } else {
                    flushRun()
                    run = [group]
                    runKey = key
                    runKind = kind
                }
            } else {
                flushRun()
                rows.append(.single(group))
            }
        }
        flushRun()
        return rows
    }

    private func clusterKey(for group: GroupedFeedItem) -> (String?, ClusteredFeedRow.Kind?) {
        let item = group.primary
        switch item.type {
        case .pull:
            // Resolve the catalog set name so older posts that stored a raw
            // set code still cluster with newer ones using the human name.
            let raw = item.pullSetName ?? ""
            let resolved = services.cardData.sets.first(where: { $0.setCode == raw })?.name ?? raw
            guard !resolved.isEmpty else { return (nil, nil) }
            return ("pull:\(resolved)", .pullsFromSet(setName: resolved))
        case .sharedContent:
            guard let type = item.content?.contentType else { return (nil, nil) }
            return ("shared:\(type.rawValue)", .sharedContent(contentType: type))
        default:
            return (nil, nil)
        }
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
        .onChange(of: services.socialFeed.selectedScope) { _, _ in
            Task { await refresh() }
        }
        .task {
            await refresh()
        }
        .onAppear {
            services.socialFeed.clearUnreadState()
            services.socialPush.clearAppBadgeCount()
        }
    }

    @ViewBuilder
    private var tabPickerHeader: some View {
        // Explicit spacer instead of `.safeAreaInset` on the parent container.
        // `NavigationStack` in SwiftUI often fails to pass safe area insets
        // down to its internal scroll views, so we must manually reserve
        // space for the floating header here at the top of the scroll content.
        Color.clear.frame(height: headerInset)
        if let selectedTab {
            SlidingSegmentedPicker(
                selection: selectedTab,
                items: SocialTab.allCases,
                title: { $0.title }
            )
            // Force a full-width layout regardless of the parent stack's
            // alignment. The 16pt horizontal padding here matches Browse's
            // segmented picker so the visible capsule width is identical
            // edge-to-edge across the app.
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
        }
    }

    // MARK: - Subviews

    private var loadingState: some View {
        ScrollView {
            // Picker outside the padded VStack so its width matches Browse's
            // segmented picker exactly — the inner shimmer cards keep their
            // own indent.
            VStack(spacing: 0) {
                tabPickerHeader

                VStack(spacing: 12) {
                    ForEach(0..<4, id: \.self) { _ in
                        ShimmerCard()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
        }
    }

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 0) {
                tabPickerHeader

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
        }
    }

    private var feedList: some View {
        let rows = feedRows
        let sections = groupRowsByDate(rows)

        return ScrollView {
            // The picker lives OUTSIDE the padded LazyVStack so it inherits
            // the ScrollView's full width and matches Browse's picker
            // dimensions exactly. Posts/headers below keep their own
            // tighter horizontal inset so card stacks read clearly.
            VStack(spacing: 0) {
                tabPickerHeader

                LazyVStack(spacing: 16) {
                    ForEach(sections, id: \.title) { section in
                        Section {
                            ForEach(section.rows) { row in
                                rowView(row)
                                    .onAppear {
                                        guard row.id == rows.last?.id else { return }
                                        Task { await loadMore() }
                                    }
                            }
                        } header: {
                            Text(section.title)
                                .font(.system(size: 11, weight: .bold))
                                .tracking(0.8)
                                .foregroundStyle(.secondary.opacity(0.5))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 4)
                                .padding(.bottom, 4)
                                .padding(.horizontal, 4)
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
                .padding(.horizontal, 20)
                .padding(.top, 0)
                .padding(.bottom, 100)
            }
        }
        .refreshable { await refresh() }
    }

    private struct FeedSection {
        let title: String
        let rows: [FeedRow]
    }

    private func groupRowsByDate(_ rows: [FeedRow]) -> [FeedSection] {
        guard !rows.isEmpty else { return [] }
        
        var today: [FeedRow] = []
        var yesterday: [FeedRow] = []
        var earlier: [FeedRow] = []
        
        let calendar = Calendar.current
        let now = Date()
        
        for row in rows {
            let date: Date = {
                switch row {
                case .single(let g): return g.primary.createdAt
                case .cluster(let c): return c.items.first?.primary.createdAt ?? now
                }
            }()
            
            if calendar.isDateInToday(date) {
                today.append(row)
            } else if calendar.isDateInYesterday(date) {
                yesterday.append(row)
            } else {
                earlier.append(row)
            }
        }
        
        var sections: [FeedSection] = []
        if !today.isEmpty { sections.append(FeedSection(title: "TODAY", rows: today)) }
        if !yesterday.isEmpty { sections.append(FeedSection(title: "YESTERDAY", rows: yesterday)) }
        if !earlier.isEmpty { sections.append(FeedSection(title: "EARLIER", rows: earlier)) }
        return sections
    }

    @ViewBuilder
    private func rowView(_ row: FeedRow) -> some View {
        switch row {
        case .single(let group):
            FeedItemView(group: group)
        case .cluster(let cluster):
            let isExpanded = expandedClusterIDs.contains(cluster.id)
            VStack(spacing: 12) {
                ConsolidatedFeedRow(
                    cluster: cluster,
                    isExpanded: isExpanded,
                    onToggle: {
                        Haptics.lightImpact()
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                            if isExpanded {
                                expandedClusterIDs.remove(cluster.id)
                            } else {
                                expandedClusterIDs.insert(cluster.id)
                            }
                        }
                    }
                )
                if isExpanded {
                    ForEach(cluster.items) { group in
                        FeedItemView(group: group)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
        }
    }


    // MARK: - Data

    private func refresh() async {
        isInitialLoading = true
        defer { isInitialLoading = false }
        do {
            _ = try await services.socialFeed.fetchFeed(refresh: true, pageSize: 30, scope: services.socialFeed.selectedScope)
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

// MARK: - Consolidated Cluster Row

/// Compact "Sam, Alex and 2 others pulled from Twilight Masquerade" row that
/// stands in for a run of similar feed events. Tap to expand the underlying
/// items inline; tap again to collapse. Visually quieter than a single
/// FeedItemView so a cluster of 5 reads as *one* unit, not five competing
/// cards.
struct ConsolidatedFeedRow: View {
    let cluster: ClusteredFeedRow
    let isExpanded: Bool
    let onToggle: () -> Void

    private var distinctActors: [SocialProfile] {
        var seen = Set<UUID>()
        var result: [SocialProfile] = []
        for item in cluster.items {
            guard let actor = item.primary.actor else { continue }
            if seen.insert(actor.id).inserted {
                result.append(actor)
            }
        }
        return result
    }

    private var summaryText: String {
        let actors = distinctActors
        let names = actors.prefix(2).map { $0.displayName ?? $0.username }
        let leadIn: String
        switch names.count {
        case 0:
            leadIn = "Several trainers"
        case 1:
            leadIn = names[0]
        case 2 where actors.count == 2:
            leadIn = "\(names[0]) and \(names[1])"
        default:
            let extra = actors.count - 2
            leadIn = "\(names[0]), \(names[1]) and \(extra) other\(extra == 1 ? "" : "s")"
        }
        switch cluster.kind {
        case .pullsFromSet(let setName):
            return "\(leadIn) pulled from \(setName)"
        case .sharedContent(let contentType):
            switch contentType {
            case .binder:    return "\(leadIn) shared binders"
            case .deck:      return "\(leadIn) shared decks"
            case .wishlist:  return "\(leadIn) updated wishlists"
            case .collection:return "\(leadIn) shared their collection"
            case .folder:    return "\(leadIn) shared folders"
            case .pull:      return "\(leadIn) shared pulls"
            case .dailyDigest: return "\(leadIn) posted updates"
            }
        }
    }

    private var tint: Color {
        switch cluster.kind {
        case .pullsFromSet:
            return Color(hex: "52C97C")
        case .sharedContent(let type):
            switch type {
            case .binder: return Color(hex: "E8B84B")
            case .deck: return Color(hex: "5B9CF6")
            case .wishlist: return Color(hex: "A78BFA")
            default: return Color(hex: "5B9CF6")
            }
        }
    }

    private var icon: String {
        switch cluster.kind {
        case .pullsFromSet: return "sparkles"
        case .sharedContent(let type):
            switch type {
            case .binder: return "books.vertical.fill"
            case .deck: return "rectangle.stack.fill"
            case .wishlist: return "heart.fill"
            default: return "square.grid.2x2.fill"
            }
        }
    }

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                Circle()
                    .fill(tint.opacity(0.15))
                    .frame(width: 38, height: 38)
                    .overlay {
                        Image(systemName: icon)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(tint)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(summaryText)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text("\(cluster.items.count) posts · tap to \(isExpanded ? "collapse" : "expand")")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary.opacity(0.6))
                }

                Spacer(minLength: 0)

                avatarStack
            }
            .padding(14)
            .glassCardStyle(cornerRadius: 14, interactive: false)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var avatarStack: some View {
        let visible = Array(distinctActors.prefix(3))
        return HStack(spacing: -10) {
            ForEach(Array(visible.enumerated()), id: \.element.id) { index, actor in
                ProfileAvatarView(profile: actor, size: 28)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color(uiColor: .secondarySystemBackground), lineWidth: 2))
                    .zIndex(Double(visible.count - index))
            }
        }
    }
}

// MARK: - Shimmer Placeholder

/// Animated shimmer fill shared by feed and alerts skeleton rows. The gradient
/// sweeps left → right on a loop so loading content reads as "actively
/// arriving" rather than "stuck". Pulled out into a `ViewModifier` so the same
/// motion phase drives every block in a row simultaneously — staggered phases
/// look unprofessional in side-by-side blocks.
private struct ShimmerFill: View {
    let phase: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.primary.opacity(0.05),
                        Color.primary.opacity(0.13),
                        Color.primary.opacity(0.05)
                    ],
                    startPoint: .init(x: phase - 0.3, y: 0.5),
                    endPoint: .init(x: phase + 0.3, y: 0.5)
                )
            )
    }
}

/// Skeleton placeholder mirroring the real `FeedItemView` row geometry —
/// avatar + name/timestamp on top, three text bars on the left, card stack in
/// the middle, type pill on the right, vote bar on the bottom. Mirroring the
/// actual layout means the load-to-content transition doesn't shift anything,
/// and users perceive the app as "ready in the right shape" instead of staring
/// at a generic spinner.
struct ShimmerCard: View {
    @State private var phase: CGFloat = -0.3

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row: avatar + name + timestamp
            HStack(spacing: 10) {
                ShimmerFill(phase: phase, cornerRadius: 17)
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 4) {
                    ShimmerFill(phase: phase, cornerRadius: 3)
                        .frame(width: 110, height: 11)
                    ShimmerFill(phase: phase, cornerRadius: 3)
                        .frame(width: 70, height: 9)
                }
                Spacer(minLength: 0)
            }

            // Content row: text column · card stack
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    ShimmerFill(phase: phase, cornerRadius: 4)
                        .frame(maxWidth: .infinity)
                        .frame(height: 14)
                    ShimmerFill(phase: phase, cornerRadius: 4)
                        .frame(maxWidth: 200, alignment: .leading)
                        .frame(height: 11)
                    ShimmerFill(phase: phase, cornerRadius: 4)
                        .frame(maxWidth: 140, alignment: .leading)
                        .frame(height: 11)
                }
                .padding(.leading, 16)
                .padding(.trailing, 12)
                .frame(maxWidth: .infinity, alignment: .leading)

                ShimmerFill(phase: phase, cornerRadius: 4)
                    .frame(width: 56, height: 80)
                    .padding(.trailing, 16)
            }

            // Vote bar
            HStack(spacing: 6) {
                ShimmerFill(phase: phase, cornerRadius: 12)
                    .frame(width: 44, height: 24)
                ShimmerFill(phase: phase, cornerRadius: 12)
                    .frame(width: 44, height: 24)
                Spacer()
                ShimmerFill(phase: phase, cornerRadius: 6)
                    .frame(width: 40, height: 16)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassCardStyle(cornerRadius: 14, interactive: false)
        .onAppear {
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                phase = 1.3
            }
        }
    }
}

/// Compact skeleton row tuned for the alerts sheet — circular icon, title bar,
/// timestamp bar, status dot. Same shimmer phase, matching the alerts row card
/// so the swap-in is invisible.
struct ShimmerAlertRow: View {
    @State private var phase: CGFloat = -0.3

    var body: some View {
        HStack(spacing: 10) {
            ShimmerFill(phase: phase, cornerRadius: 18)
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 5) {
                ShimmerFill(phase: phase, cornerRadius: 3)
                    .frame(maxWidth: .infinity)
                    .frame(height: 12)
                ShimmerFill(phase: phase, cornerRadius: 3)
                    .frame(width: 80, height: 10)
            }
            Spacer(minLength: 0)
            ShimmerFill(phase: phase, cornerRadius: 3.5)
                .frame(width: 7, height: 7)
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.primary.opacity(0.06), lineWidth: 1))
        .onAppear {
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                phase = 1.3
            }
        }
    }
}

struct SocialAlertsSheet: View {
    struct TradeAlertItem: Identifiable {
        let id: String
        let tradeID: UUID
        let status: TradeStatus
        let title: String
        let createdAt: Date
    }

    @Binding var isPresented: Bool
    let onDeepLinkSelected: (URL) -> Void
    @Environment(AppServices.self) private var services

    /// Activity rows (votes, comments, friendships) that
    /// target the current user. These are fetched specifically for the alerts
    /// sheet — the main feed deliberately excludes activity rows
    /// (`includeActivityRows: false` in ``SocialFeedService.fetchFeed``), so
    /// reading from ``services.socialFeed.items`` returns nothing alert-shaped
    /// and the sheet shows "No notifications" even when the user has unread
    /// activity. Loading them here makes the sheet's data source independent
    /// of the main feed.
    @State private var activity: [SocialFeedService.FeedItem] = []
    @State private var tradeUpdates: [TradeAlertItem] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?

    private var groupedItems: [GroupedFeedItem] {
        var groups: [GroupedFeedItem] = []
        var contentIndex: [UUID: Int] = [:]
        for item in activity {
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
            tradeUpdates: tradeUpdates,
            isLoading: isLoading && activity.isEmpty,
            errorMessage: errorMessage,
            onDone: { isPresented = false },
            onDeepLinkSelected: { url in
                onDeepLinkSelected(url)
                isPresented = false
            },
            onRetry: { Task { await refresh() } }
        )
        .task { await refresh() }
    }

    private func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let fetchedActivity = try await services.socialFeed
                .fetchUserActivity(limit: 40)
                .filter { $0.type != .wishlistMatch }
            let fetchedTrades = try await services.trade.fetchMyTrades()
            activity = fetchedActivity
            tradeUpdates = buildTradeAlerts(from: fetchedTrades)
            
            // Clear unread alerts state once successfully fetched
            services.socialFeed.clearUnreadAlertsState(items: fetchedActivity)
            
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func buildTradeAlerts(from trades: [TradeWithItems]) -> [TradeAlertItem] {
        guard case .signedIn(let uid, _) = services.socialAuth.authState else { return [] }
        return trades.compactMap { tradeWithItems in
            let trade = tradeWithItems.trade
            guard let updatedAt = trade.updatedAt ?? trade.createdAt else { return nil }
            let iStartedTrade = trade.initiatorID == uid
            let title: String = {
                switch trade.status {
                case .pending:
                    return iStartedTrade ? "Trade offer sent" : "You received a trade offer"
                case .countered:
                    return iStartedTrade ? "Counter offer sent" : "You received a counter offer"
                case .accepted:
                    return iStartedTrade ? "Your trade was accepted" : "You accepted this trade"
                case .complete:
                    return "Trade marked complete"
                case .cancelled:
                    return iStartedTrade ? "You cancelled the trade" : "Trade partner cancelled the trade"
                }
            }()
            return TradeAlertItem(
                id: "trade-\(trade.id.uuidString)-\(trade.status.rawValue)-\(updatedAt.timeIntervalSince1970)",
                tradeID: trade.id,
                status: trade.status,
                title: title,
                createdAt: updatedAt
            )
        }
        .sorted { $0.createdAt > $1.createdAt }
        .prefix(20)
        .map { $0 }
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
    private enum AlertLogEntry: Identifiable {
        case activity(GroupedFeedItem)
        case trade(SocialAlertsSheet.TradeAlertItem)

        var id: String {
            switch self {
            case .activity(let group):
                return "activity-\(group.id)"
            case .trade(let trade):
                return "trade-\(trade.id)"
            }
        }

        var createdAt: Date {
            switch self {
            case .activity(let group):
                return group.primary.createdAt
            case .trade(let trade):
                return trade.createdAt
            }
        }
    }

    let items: [GroupedFeedItem]
    var tradeUpdates: [SocialAlertsSheet.TradeAlertItem] = []
    var isLoading: Bool = false
    var errorMessage: String? = nil
    let onDone: () -> Void
    let onDeepLinkSelected: (URL) -> Void
    var onRetry: () -> Void = {}

    private var logEntries: [AlertLogEntry] {
        let activityEntries = activityItems.map(AlertLogEntry.activity)
        let tradeEntries = tradeUpdates.map(AlertLogEntry.trade)
        return (activityEntries + tradeEntries).sorted { $0.createdAt > $1.createdAt }
    }

    private var activityItems: [GroupedFeedItem] {
        items.filter { group in
            switch group.primary.type {
            case .vote, .comment, .friendship:
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

            if isLoading {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        sectionLabel("ALL ACTIVITY")
                        ForEach(0..<5, id: \.self) { _ in
                            ShimmerAlertRow()
                        }
                    }
                    .padding(16)
                }
            } else if let errorMessage {
                VStack(spacing: 12) {
                    ContentUnavailableView(
                        "Couldn't load alerts",
                        systemImage: "exclamationmark.triangle.fill",
                        description: Text(errorMessage)
                    )
                    Button("Try Again") { onRetry() }
                        .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        sectionLabel("ALL ACTIVITY")
                        if logEntries.isEmpty {
                            emptyAlert("Trade updates, votes, comments, and friend activity will appear here.")
                        } else {
                            ForEach(logEntries) { entry in
                                switch entry {
                                case .activity(let group):
                                    alertRow(group: group, tint: tint(for: group.primary), icon: icon(for: group.primary))
                                case .trade(let update):
                                    tradeAlertRow(update)
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .tracking(0.88)
            .foregroundStyle(Color.secondary.opacity(0.7))
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
                    .foregroundStyle(Color.secondary.opacity(0.6))
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

    private func tradeAlertRow(_ update: SocialAlertsSheet.TradeAlertItem) -> some View {
        let tint = tradeTint(update.status)
        return Button {
            Haptics.lightImpact()
            if let url = URL(string: "bindr://social/trades/\(update.tradeID.uuidString)") {
                onDeepLinkSelected(url)
            }
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(tint.opacity(0.15))
                    .frame(width: 36, height: 36)
                    .overlay {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(tint)
                    }

                VStack(alignment: .leading, spacing: 3) {
                    Text(update.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(2)
                    Text(SocialFeedService.shortRelativeDate(update.createdAt))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.secondary.opacity(0.6))
                }
                Spacer(minLength: 0)
                Circle()
                    .fill(tint)
                    .frame(width: 7, height: 7)
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(14)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(tint.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
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
                return URL(string: "bindr://social/feed/post/\(contentID.uuidString)")
            }
            return URL(string: "bindr://social/feed")
        case .wishlistMatch:
            if let matchID = uuidFromFeedItemID(item.id, prefix: "wishlist-") {
                return URL(string: "bindr://social/feed/wishlist-match/\(matchID.uuidString)")
            }
            if let contentID = item.content?.id {
                return URL(string: "bindr://social/feed/post/\(contentID.uuidString)")
            }
            return URL(string: "bindr://social/feed")
        case .vote, .sharedContent, .pull, .dailyDigest:
            if let contentID = item.content?.id {
                return URL(string: "bindr://social/feed/post/\(contentID.uuidString)")
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

    private func tradeTint(_ status: TradeStatus) -> Color {
        switch status {
        case .pending: return Color(hex: "E8B84B")
        case .countered: return Color(hex: "E8934B")
        case .accepted: return Color(hex: "52C97C")
        case .complete: return Color(hex: "52C97C")
        case .cancelled: return Color(hex: "E05252")
        }
    }
}
