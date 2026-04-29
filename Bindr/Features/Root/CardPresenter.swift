import SwiftUI

/// Identifies one full-screen card session: swipe horizontally within this ordered list.
struct CardPresentationContext: Identifiable {
    let id = UUID()
    let cards: [Card]
    let startIndex: Int
}

/// Identifies one sealed detail session: swipe horizontally within this ordered list.
struct SealedProductPresentationContext: Identifiable {
    let id = UUID()
    let products: [SealedProduct]
    let startIndex: Int
}

private struct CardPresenterKey: EnvironmentKey {
    static let defaultValue: (Card, [Card]) -> Void = { _, _ in }
}

private struct CardPresenterAtIndexKey: EnvironmentKey {
    static let defaultValue: ([Card], Int) -> Void = { _, _ in }
}

private struct BrowseFeedCardsKey: EnvironmentKey {
    static let defaultValue: [Card] = []
}

private struct SealedProductPresenterKey: EnvironmentKey {
    static let defaultValue: (SealedProduct, [SealedProduct], Int) -> Void = { _, _, _ in }
}

extension EnvironmentValues {
    /// Present card detail; pass the **same ordered array** the user is browsing so paging matches that filter.
    var presentCard: (Card, [Card]) -> Void {
        get { self[CardPresenterKey.self] }
        set { self[CardPresenterKey.self] = newValue }
    }

    /// Present card detail when caller already knows the tapped index in the list.
    var presentCardAtIndex: ([Card], Int) -> Void {
        get { self[CardPresenterAtIndexKey.self] }
        set { self[CardPresenterAtIndexKey.self] = newValue }
    }

    /// The current browse feed card list, set on the lazy grid container so individual cells don't store it.
    var browseFeedCards: [Card] {
        get { self[BrowseFeedCardsKey.self] }
        set { self[BrowseFeedCardsKey.self] = newValue }
    }

    /// Present sealed product detail from the root presenter path (same architecture as card detail).
    var presentSealedProduct: (SealedProduct, [SealedProduct], Int) -> Void {
        get { self[SealedProductPresenterKey.self] }
        set { self[SealedProductPresenterKey.self] = newValue }
    }
}
