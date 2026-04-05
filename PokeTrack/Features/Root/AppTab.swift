import Foundation

enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case collection
    case wishlist
    case browse
    case portfolio
    case account

    var id: String { rawValue }

    var title: String {
        switch self {
        case .collection: return "Collection"
        case .wishlist: return "Wishlist"
        case .browse: return "Cards"
        case .portfolio: return "Portfolio"
        case .account: return "Account"
        }
    }

    var symbolName: String {
        switch self {
        case .collection: return "square.grid.2x2"
        case .wishlist: return "heart"
        case .browse: return "rectangle.stack"
        case .portfolio: return "chart.line.uptrend.xyaxis"
        case .account: return "person.circle"
        }
    }
}
