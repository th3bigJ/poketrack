import Foundation

enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case browse
    case wishlist
    case collection
    case account

    var id: String { rawValue }

    var title: String {
        switch self {
        case .browse: return "Cards"
        case .wishlist: return "Wishlist"
        case .collection: return "Collection"
        case .account: return "Account"
        }
    }

    var symbolName: String {
        switch self {
        case .browse: return "rectangle.stack"
        case .wishlist: return "star"
        case .collection: return "square.stack.3d.up.fill"
        case .account: return "person.circle"
        }
    }
}
