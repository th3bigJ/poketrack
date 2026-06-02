import SwiftUI

struct TradesView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.bindrAccent) private var accent
    @Binding var navigationPath: NavigationPath
    var selectedTab: Binding<SocialTab>? = nil
    var headerInset: CGFloat = 0

    @State private var trades: [TradeWithItems] = []
    @State private var profileCache: [UUID: SocialProfile] = [:]
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showsCompletedTrades = false
    @State private var isSuggestedExpanded = true
    @State private var isOpenTradesExpanded = false
    @State private var hasLoadedTrades = false

    private var currentUserID: UUID? {
        if case .signedIn(let uid, _) = services.socialAuth.authState { return uid }
        return nil
    }

    private var openTrades: [TradeWithItems] {
        trades.filter { tradeWithItems in
            switch tradeWithItems.trade.status {
            case .pending, .countered, .accepted:
                return true
            case .complete, .cancelled:
                return false
            }
        }
    }

    private var completedTrades: [TradeWithItems] {
        trades.filter { $0.trade.status == .complete }
    }

    private var displayedTrades: [TradeWithItems] {
        showsCompletedTrades ? (openTrades + completedTrades) : openTrades
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                Color.clear.frame(height: headerInset)
                if let selectedTab {
                    SlidingSegmentedPicker(
                        selection: selectedTab,
                        items: SocialTab.allCases,
                        title: { $0.title }
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
                }
                tradeOpportunityTray
                    .padding(.top, 6)
                    .padding(.bottom, 14)

                tradeWallSection
            }
            // Generous bottom padding so the last section never slides under
            // the app's custom bottom tab bar (≈60pt) plus the home indicator
            // (~34pt). The Social shell ignores the bottom safe area so this
            // padding is what keeps content above the nav.
            .padding(.bottom, 120)
        }
        .refreshable { await refresh() }
        .task {
            await loadAfterFirstPaint()
        }
        .onChange(of: services.trade.lastMutationAt) { _, _ in
            Task { await refresh(force: true) }
        }
        .alert("Error", isPresented: .constant(errorMessage != nil), actions: {
            Button("OK") { errorMessage = nil }
        }, message: {
            Text(errorMessage ?? "")
        })
    }

    // MARK: - Trade Wall Section

    private var tradeWallSection: some View {
        VStack(spacing: 0) {
            sectionHeader(title: "TRADE WALL")
                .padding(.bottom, 8)

            TradeWallView(navigationPath: $navigationPath)
        }
        .padding(.top, 4)
    }

    // MARK: - Suggested Trades Section

    private var tradeOpportunityTray: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                tradeOpportunityButton(
                    title: "Matches",
                    subtitle: "Wishlist hits",
                    systemImage: "sparkles",
                    count: nil,
                    isExpanded: isSuggestedExpanded
                ) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        isSuggestedExpanded.toggle()
                        if isSuggestedExpanded {
                            isOpenTradesExpanded = false
                        }
                    }
                }

                tradeOpportunityButton(
                    title: "Active",
                    subtitle: showsCompletedTrades ? "Including completed" : "Open offers",
                    systemImage: "arrow.left.arrow.right",
                    count: openTrades.count,
                    isExpanded: isOpenTradesExpanded
                ) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        isOpenTradesExpanded.toggle()
                        if isOpenTradesExpanded {
                            isSuggestedExpanded = false
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            if isSuggestedExpanded {
                SuggestedTradesView(navigationPath: $navigationPath)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, 16)
            }

            if isOpenTradesExpanded {
                VStack(spacing: 10) {
                    HStack {
                        Text("Show Completed")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Toggle("", isOn: $showsCompletedTrades)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .scaleEffect(0.85)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    if isLoading && displayedTrades.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 26)
                    } else if displayedTrades.isEmpty && !isLoading {
                        openTradesEmptyState
                    } else {
                        tradesList
                    }
                }
                .padding(12)
                .background(Color(uiColor: .secondarySystemBackground).opacity(0.55), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.primary.opacity(0.07), lineWidth: 1)
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Shared Header Helpers

    private func sectionHeader(title: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func tradeOpportunityButton(
        title: String,
        subtitle: String,
        systemImage: String,
        count: Int?,
        isExpanded: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.selectionChanged()
            action()
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(isExpanded ? Color.white.opacity(0.22) : Color.primary.opacity(0.06))
                        .frame(width: 34, height: 34)
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(isExpanded ? Color.white : Color.primary.opacity(0.75))
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(isExpanded ? Color.white : Color.primary)
                            .lineLimit(1)
                        if let count {
                            Text("\(count)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(isExpanded ? Color.white : Color.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background((isExpanded ? Color.white.opacity(0.20) : Color.primary.opacity(0.07)), in: Capsule())
                        }
                    }
                    Text(subtitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isExpanded ? Color.white.opacity(0.78) : Color.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(isExpanded ? accent : Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isExpanded ? Color.white.opacity(0.18) : Color.primary.opacity(0.07), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Trades List

    private var tradesList: some View {
        LazyVStack(spacing: 8) {
            ForEach(displayedTrades) { tradeWithItems in
                Button {
                    navigationPath.append(SocialDestination.tradeDetail(tradeID: tradeWithItems.id))
                } label: {
                    TradeRowView(
                        tradeWithItems: tradeWithItems,
                        currentUserID: currentUserID ?? UUID(),
                        counterpartProfile: profileCache[tradeWithItems.counterpartID(currentUserID: currentUserID ?? UUID())]
                    )
                }
                .buttonStyle(.plain)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                }
            }
        }
    }

    private var openTradesEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.secondary.opacity(0.4))
            Text(showsCompletedTrades ? "No trades yet" : "No open trades")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.secondary)
            Text(showsCompletedTrades
                 ? "Offer a trade from a friend's trade list or wishlist to get started."
                 : "Your active pending/countered/accepted trades will appear here.")
                .font(.system(size: 13))
                .foregroundStyle(Color.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
    }

    // MARK: - Data

    private func loadAfterFirstPaint() async {
        guard !hasLoadedTrades else { return }
        hasLoadedTrades = true
        await Task.yield()
        try? await Task.sleep(nanoseconds: 120_000_000)
        await refresh(force: true)
    }

    private func refresh(force: Bool = false) async {
        guard force || !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            trades = try await services.trade.fetchMyTrades()
            await loadProfilesForTrades()
            
            // Auto-expand open trades if there are active trades to see; otherwise collapse to keep vertical space free for the Trade Wall
            withAnimation(.easeInOut(duration: 0.25)) {
                isOpenTradesExpanded = !openTrades.isEmpty
            }
            errorMessage = nil
        } catch is CancellationError {
        } catch let error as URLError where error.code == .cancelled {
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadProfilesForTrades() async {
        guard let uid = currentUserID else { return }
        let counterpartIDs = Set(trades.map { $0.counterpartID(currentUserID: uid) })
        let missingIDs = counterpartIDs.filter { profileCache[$0] == nil }
        guard !missingIDs.isEmpty else { return }

        await withTaskGroup(of: SocialProfile?.self) { group in
            for userID in missingIDs {
                group.addTask {
                    try? await services.socialProfile.fetchProfile(id: userID)
                }
            }
            for await profile in group {
                if let profile {
                    profileCache[profile.id] = profile
                }
            }
        }
    }
}
