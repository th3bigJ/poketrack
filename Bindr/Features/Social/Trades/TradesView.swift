import SwiftUI

struct TradesView: View {
    @Environment(AppServices.self) private var services
    @Binding var navigationPath: NavigationPath
    var selectedTab: Binding<SocialTab>? = nil
    var headerInset: CGFloat = 0

    @State private var trades: [TradeWithItems] = []
    @State private var profileCache: [UUID: SocialProfile] = [:]
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showsCompletedTrades = false
    @State private var isSuggestedExpanded = true
    @State private var isOpenTradesExpanded = true

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
                suggestedTradesSection

                Divider()
                    .padding(.vertical, 4)

                openTradesSection

                Divider()
                    .padding(.vertical, 8)

                tradeWallSection
            }
            // Generous bottom padding so the last section never slides under
            // the app's custom bottom tab bar (≈60pt) plus the home indicator
            // (~34pt). The Social shell ignores the bottom safe area so this
            // padding is what keeps content above the nav.
            .padding(.bottom, 120)
        }
        .background(Color(uiColor: .systemBackground))
        .refreshable { await refresh() }
        .task { await refresh() }
        .task(id: services.trade.lastMutationAt) {
            await refresh()
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
            sectionHeader(title: "TRADE WALL", systemImage: "square.grid.2x2")
                .padding(.bottom, 8)

            TradeWallView(navigationPath: $navigationPath)
        }
        .padding(.top, 4)
    }

    // MARK: - Suggested Trades Section

    private var suggestedTradesSection: some View {
        VStack(spacing: 0) {
            collapsibleSectionHeader(
                title: "SUGGESTED TRADES",
                isExpanded: $isSuggestedExpanded
            )

            if isSuggestedExpanded {
                SuggestedTradesView(navigationPath: $navigationPath)
                    .padding(.bottom, 4)
            }
        }
    }

    // MARK: - Open Trades Section

    private var openTradesSection: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                collapsibleSectionHeader(
                    title: "OPEN TRADES",
                    isExpanded: $isOpenTradesExpanded
                )

                HStack {
                    Text("Show Completed")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Toggle("", isOn: $showsCompletedTrades)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .scaleEffect(0.85)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.trailing, 16)
            }

            if isOpenTradesExpanded {
                if isLoading && displayedTrades.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else if displayedTrades.isEmpty && !isLoading {
                    openTradesEmptyState
                } else {
                    tradesList
                }
            }
        }
    }

    // MARK: - Shared Header Helpers

    private func sectionHeader(title: String, systemImage: String) -> some View {
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

    private func collapsibleSectionHeader(title: String, isExpanded: Binding<Bool>) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.wrappedValue.toggle()
            }
        } label: {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.7)
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: isExpanded.wrappedValue ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Trades List

    private var tradesList: some View {
        LazyVStack(spacing: 0) {
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

                Divider()
                    .padding(.leading, 72)
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
                 ? "Offer a trade from a friend's collection or wishlist to get started."
                 : "Your active pending/countered/accepted trades will appear here.")
                .font(.system(size: 13))
                .foregroundStyle(Color.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
        .padding(.bottom, 20)
    }

    // MARK: - Data

    private func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            trades = try await services.trade.fetchMyTrades()
            await loadProfilesForTrades()
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
