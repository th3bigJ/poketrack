import SwiftUI

/// Identifies one full-screen card session: swipe horizontally within this ordered list.
struct CardPresentationContext: Identifiable {
    let id = UUID()
    let cards: [Card]
    let startIndex: Int

    /// How many neighbors to include on each side of the tapped card for horizontal paging.
    private static let swipeWindowRadius = 24

    init(cards: [Card], startIndex: Int) {
        self.cards = cards
        self.startIndex = startIndex
    }

    /// Presents a swipeable window around `startIndex` so the sheet does not build thousands of pages.
    init(windowedFrom allCards: [Card], startIndex: Int, radius: Int = CardPresentationContext.swipeWindowRadius) {
        guard !allCards.isEmpty else {
            cards = []
            self.startIndex = 0
            return
        }
        let safeIndex = min(max(startIndex, 0), allCards.count - 1)
        let lower = max(0, safeIndex - radius)
        let upper = min(allCards.count - 1, safeIndex + radius)
        cards = Array(allCards[lower...upper])
        self.startIndex = safeIndex - lower
    }
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

private struct RestoreTabBarChromeKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

private struct SuppressTabBarForModalChromeKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
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

    /// Re-applies tab bar accent tint after a modal dismisses (provided by `RootView`).
    var restoreTabBarChrome: (() -> Void)? {
        get { self[RestoreTabBarChromeKey.self] }
        set { self[RestoreTabBarChromeKey.self] = newValue }
    }

    /// Hides the tab bar while a card/product sheet is showing (provided by `RootView`).
    var suppressTabBarForModalChrome: (() -> Void)? {
        get { self[SuppressTabBarForModalChromeKey.self] }
        set { self[SuppressTabBarForModalChromeKey.self] = newValue }
    }
}
