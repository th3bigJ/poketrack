import SwiftUI

struct TradesView: View {
    @Environment(AppServices.self) private var services
    @Binding var navigationPath: NavigationPath

    @State private var trades: [TradeWithItems] = []
    @State private var profileCache: [UUID: SocialProfile] = [:]
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showsCompletedTrades = false

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
                SuggestedTradesView(navigationPath: $navigationPath)
                    .padding(.bottom, 22)

                openTradesHeader
                    .padding(.bottom, 8)

                if isLoading && displayedTrades.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else if displayedTrades.isEmpty && !isLoading {
                    emptyState
                } else {
                    tradesList
                }
            }
            .padding(.bottom, 32)
        }
        .background(Color(uiColor: .systemBackground))
        .refreshable { await refresh() }
        .task { await refresh() }
        .alert("Error", isPresented: .constant(errorMessage != nil), actions: {
            Button("OK") { errorMessage = nil }
        }, message: {
            Text(errorMessage ?? "")
        })
    }

    private var openTradesHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("OPEN TRADES")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(.secondary)
            Spacer()
            HStack {
                Text("Show Completed trades")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Toggle("", isOn: $showsCompletedTrades)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .scaleEffect(0.85)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
    }

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

    private var emptyState: some View {
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
        .padding(.top, 60)
    }

    private func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            trades = try await services.trade.fetchMyTrades()
            await loadProfilesForTrades()
            errorMessage = nil
        } catch is CancellationError {
            // Pull-to-refresh and task refresh can overlap; cancellation here is expected.
        } catch let error as URLError where error.code == .cancelled {
            // Ignore URLSession cancellation noise for user-initiated refresh gestures.
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
