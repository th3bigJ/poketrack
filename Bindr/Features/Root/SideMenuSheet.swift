import Foundation

/// Screens opened only from the side menu as fullScreenCover (not shown in the tab bar).
enum SideMenuSheet: String, Identifiable {
    case account
    case social
    case decks
    case transactions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .account: return "Account"
        case .social: return "Social"
        case .decks: return "Deck Builder"
        case .transactions: return "Transactions"
        }
    }
}
