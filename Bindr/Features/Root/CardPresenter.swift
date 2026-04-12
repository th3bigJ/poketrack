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

extension EnvironmentValues {
    /// Present card detail; pass the **same ordered array** the user is browsing (search, set, dex, or feed) so paging matches that filter.
    var presentCard: (Card, [Card]) -> Void {
        get { self[CardPresenterKey.self] }
        set { self[CardPresenterKey.self] = newValue }
    }
}
