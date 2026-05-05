import SwiftUI

struct TradeWallView: View {
    @Environment(AppServices.self) private var services
    @Binding var navigationPath: NavigationPath

    @State private var entries: [WallEntry] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var cardDetailSession: CardDetailSession?

    struct WallEntry: Identifiable {
        let id: String
        let card: Card
        let owner: SocialProfile
        var setName: String?
    }

    private struct CardDetailSession: Identifiable {
        let id = UUID()
        let card: Card
        let owner: SocialProfile
    }

    private static let gridOptions = BrowseGridOptions(
        showCardName: true,
        showSetName: true,
        showSetID: false,
        showPricing: true,
        showOwned: false
    )

    var body: some View {
        Group {
            if isLoading && entries.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
            } else if entries.isEmpty {
                emptyState
            } else {
                cardGrid
            }
        }
        .task { await load() }
        .sheet(item: $cardDetailSession) { session in
            CardDetailSheet(
                cards: [session.card],
                startIndex: 0,
                tradeAction: { card, _ in startTrade(card: card, with: session.owner) },
                tradeActionLabel: "Start Trade"
            )
            .environment(services)
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var cardGrid: some View {
        EagerVGrid(items: entries, columns: 3, spacing: 8) { entry in
            Button {
                Haptics.lightImpact()
                cardDetailSession = CardDetailSession(card: entry.card, owner: entry.owner)
            } label: {
                CardGridCell(
                    card: entry.card,
                    gridOptions: Self.gridOptions,
                    setName: entry.setName
                )
                .overlay(alignment: .topTrailing) {
                    ProfileAvatarView(profile: entry.owner, size: 20)
                        .overlay(Circle().stroke(Color(uiColor: .systemBackground), lineWidth: 1.5))
                        .padding(4)
                }
            }
            .buttonStyle(CardCellButtonStyle())
        }
        .padding(.horizontal, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.secondary.opacity(0.4))
            Text("Trade Wall is empty")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.secondary)
            Text("Cards your friends have on their trade list will appear here.")
                .font(.system(size: 13))
                .foregroundStyle(Color.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private func load() async {
        guard case .signedIn = services.socialAuth.authState else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let friends = try await services.socialFriend.fetchFriends()
            guard !friends.isEmpty else { return }

            let friendIDs = friends.map(\.id)
            let tradeListMap = try await services.socialCardLibrary.fetchTradeListCardIDsByUser(for: friendIDs)

            var newEntries: [WallEntry] = []
            for friend in friends {
                let cardIDs = tradeListMap[friend.id] ?? []
                for cardID in cardIDs {
                    if let card = await services.cardData.loadCard(masterCardId: cardID) {
                        let setName = services.cardData.sets.first { $0.setCode == card.setCode }?.name
                        newEntries.append(WallEntry(id: "\(friend.id)-\(cardID)", card: card, owner: friend, setName: setName))
                    }
                }
            }
            entries = newEntries
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startTrade(card: Card, with friend: SocialProfile) {
        let item = TradeItem(
            id: UUID(),
            tradeID: UUID(),
            ownerID: friend.id,
            cardID: card.masterCardId,
            variantKey: "normal",
            quantity: 1,
            createdAt: nil
        )
        navigationPath.append(SocialDestination.tradeBuilder(
            receiverID: friend.id,
            theirCards: [item],
            myCards: []
        ))
    }
}
