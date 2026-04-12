import Foundation

enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case dashboard
    case browse
    case wishlist
    case collection
    case bindrs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .browse: return "Cards"
        case .wishlist: return "Wishlist"
        case .collection: return "Collection"
        case .bindrs: return "Bindrs"
        }
    }

    var symbolName: String {
        switch self {
        case .dashboard: return "square.grid.2x2.fill"
        case .browse: return "rectangle.stack"
        case .wishlist: return "star"
        case .collection: return "square.stack.3d.up.fill"
        case .bindrs: return "person.2.fill"
        }
    }
}
