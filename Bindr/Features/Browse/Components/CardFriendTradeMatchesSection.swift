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
    @State private var isLoading = false
    @State private var isSignedIn = false

    var body: some View {
        VStack(spacing: 8) {
            if let directContext {
                CardTradeContextRow(card: card, context: directContext)
            } else if !contexts.isEmpty {
                ForEach(Array(contexts.enumerated()), id: \.offset) { _, context in
                    CardTradeContextRow(card: card, context: context)
                }
            } else if isLoading {
                tradeLoadingRow
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

    private var tradeLoadingRow: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text("Checking friend trades…")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassCardStyle(cornerRadius: 18, interactive: false)
    }

    @MainActor
    private func loadMatches() async {
        if directContext != nil {
            contexts = []
            isLoading = false
            return
        }

        guard services.socialAuth.isSignedIn else {
            contexts = []
            isLoading = false
            return
        }

        isLoading = true
        contexts = await services.cardFriendTradeMatches.tradeContexts(for: card, services: services) { card, side in
            services.launchTradeFromCardDetail(cardID: card.masterCardId, preferredSide: side)
            dismiss()
        }
        isLoading = false
    }
}
