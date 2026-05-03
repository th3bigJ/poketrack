import SwiftUI

struct TradesView: View {
    @Environment(AppServices.self) private var services
    @Binding var navigationPath: NavigationPath

    @State private var trades: [TradeWithItems] = []
    @State private var profileCache: [UUID: SocialProfile] = [:]
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var statusFilter: TradeStatusFilter = .all
    @State private var isSuggestionsExpanded = true

    private var currentUserID: UUID? {
        if case .signedIn(let uid, _) = services.socialAuth.authState { return uid }
        return nil
    }

    private var filteredTrades: [TradeWithItems] {
        guard let matchingStatus = statusFilter.matchingStatus else { return trades }
        return trades.filter { $0.trade.status == matchingStatus }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                filterPicker
                    .padding(.bottom, 8)

                if isLoading && trades.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else if filteredTrades.isEmpty && !isLoading {
                    emptyState
                } else {
                    tradesList
                }

                if !trades.isEmpty {
                    SuggestedTradesView(navigationPath: $navigationPath)
                        .padding(.top, 24)
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

    private var filterPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TradeStatusFilter.allCases) { filter in
                    Button {
                        statusFilter = filter
                    } label: {
                        Text(filter.rawValue)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(statusFilter == filter ? Color.primary : Color.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                statusFilter == filter
                                ? Color(uiColor: .secondarySystemBackground)
                                : Color.clear,
                                in: Capsule()
                            )
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var tradesList: some View {
        LazyVStack(spacing: 0) {
            ForEach(filteredTrades) { tradeWithItems in
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
            Text(statusFilter == .all ? "No trades yet" : "No \(statusFilter.rawValue.lowercased()) trades")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.secondary)
            Text("Offer a trade from a friend's collection or wishlist to get started.")
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
