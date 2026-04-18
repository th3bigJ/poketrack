import Foundation

enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case dashboard
    case browse
    case collect
    case bindrs

    var id: String { rawValue }

    /// Only these tabs appear in the tab bar (4 tabs: Dashboard, Browse, Collect, Bindrs).
    static let visibleTabs: [AppTab] = [.dashboard, .browse, .collect, .bindrs]

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .browse: return "Browse"
        case .collect: return "Collect"
        case .bindrs: return "Bindrs"
        }
    }

    var symbolName: String {
        switch self {
        case .dashboard: return "square.grid.2x2.fill"
        case .browse: return "rectangle.stack"
        case .collect: return "square.stack.3d.up.fill"
        case .bindrs: return "books.vertical.fill"
        }
    }
}
