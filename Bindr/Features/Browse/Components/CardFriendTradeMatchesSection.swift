import SwiftUI

/// Trade prompts for a card — either a caller-supplied direct context (friend profile, trade wall)
/// or automatically discovered friends who have or want the card.
struct CardFriendTradeMatchesSection: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    let card: Card
    /// When set, skips the friend lookup and shows this row only.
    var directContext: CardTradeContext? = nil

    @State private var contexts: [CardTradeContext] = []
    @State private var isSignedIn = false

    var body: some View {
        VStack(spacing: 8) {
            if let directContext {
                CardTradeContextRow(card: card, context: directContext)
            } else if !contexts.isEmpty {
                ForEach(Array(contexts.enumerated()), id: \.offset) { _, context in
                    CardTradeContextRow(card: card, context: context)
                }
            }
        }
        .onAppear {
            isSignedIn = services.socialAuth.isSignedIn
            guard directContext == nil, isSignedIn else { return }
            Task { await loadMatches() }
        }
        .task(id: card.masterCardId) {
            isSignedIn = services.socialAuth.isSignedIn
            await loadMatches()
        }
        .onChange(of: services.socialAuth.authState) { _, _ in
            isSignedIn = services.socialAuth.isSignedIn
            Task { await loadMatches() }
        }
    }

    @MainActor
    private func loadMatches() async {
        if directContext != nil {
            contexts = []
            return
        }

        guard services.socialAuth.isSignedIn else {
            contexts = []
            return
        }

        contexts = await services.cardFriendTradeMatches.tradeContexts(for: card, services: services) { card, side in
            services.launchTradeFromCardDetail(cardID: card.masterCardId, preferredSide: side)
            dismiss()
        }
    }
}
