import Foundation

enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case dashboard
    case browse
    case collection
    case wishlist
    case bindrs

    var id: String { rawValue }

    /// Only these tabs appear in the tab bar.
    static let visibleTabs: [AppTab] = [.dashboard, .browse, .collection, .wishlist, .bindrs]

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .browse: return "Cards"
        case .collection: return "Collection"
        case .wishlist: return "Wishlist"
        case .bindrs: return "Bindrs"
        }
    }

    var symbolName: String {
        switch self {
        case .dashboard: return "square.grid.2x2.fill"
        case .browse: return "rectangle.stack"
        case .collection: return "square.stack.3d.up.fill"
        case .wishlist: return "star.fill"
        case .bindrs: return "books.vertical.fill"
        }
    }
}
