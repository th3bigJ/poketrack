import Foundation

/// Screens opened only from the side menu and not shown in the tab bar.
enum SideMenuPage: String, Identifiable, Hashable {
    case account
    case social
    case binders
    case decks
    case transactions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .account: return "Account"
        case .social: return "Social"
        case .binders: return "Binders"
        case .decks: return "Deck Builder"
        case .transactions: return "Transactions"
        }
    }
}
