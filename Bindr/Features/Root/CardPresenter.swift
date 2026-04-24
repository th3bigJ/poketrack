import SwiftUI

/// Identifies one full-screen card session: swipe horizontally within this ordered list.
struct CardPresentationContext: Identifiable {
    let id = UUID()
    let cards: [Card]
    let startIndex: Int
}

private struct CardPresenterKey: EnvironmentKey {
    static let defaultValue: (Card, [Card]) -> Void = { _, _ in }
}

private struct BrowseFeedCardsKey: EnvironmentKey {
    static let defaultValue: [Card] = []
}

extension EnvironmentValues {
    /// Present card detail; pass the **same ordered array** the user is browsing so paging matches that filter.
    var presentCard: (Card, [Card]) -> Void {
        get { self[CardPresenterKey.self] }
        set { self[CardPresenterKey.self] = newValue }
    }

    /// The current browse feed card list, set on the lazy grid container so individual cells don't store it.
    var browseFeedCards: [Card] {
        get { self[BrowseFeedCardsKey.self] }
        set { self[BrowseFeedCardsKey.self] = newValue }
    }
}
