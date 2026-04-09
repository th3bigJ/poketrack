import Foundation

enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case browse
    case wishlist
    case collection
    case transactions
    case account

    var id: String { rawValue }

    var title: String {
        switch self {
        case .browse: return "Cards"
        case .wishlist: return "Wishlist"
        case .collection: return "Collection"
        case .transactions: return "Transactions"
        case .account: return "Account"
        }
    }

    var symbolName: String {
        switch self {
        case .browse: return "rectangle.stack"
        case .wishlist: return "star"
        case .collection: return "square.stack.3d.up.fill"
        case .transactions: return "list.bullet.rectangle"
        case .account: return "person.circle"
        }
    }
}
