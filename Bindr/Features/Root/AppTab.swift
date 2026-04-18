import Foundation

enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case dashboard
    case browse
    case collect
    case bindrs
    /// Tapping this tab opens the `MoreSheet` modally rather than routing to content.
    /// `RootView` intercepts selection so the bar never actually settles on `.more`.
    case more

    var id: String { rawValue }

    /// Tabs that appear in the tab bar (5 tabs: Dashboard, Browse, Collect, Bindrs, More).
    static let visibleTabs: [AppTab] = [.dashboard, .browse, .collect, .bindrs, .more]

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .browse: return "Browse"
        case .collect: return "Collect"
        case .bindrs: return "Bindrs"
        case .more: return "More"
        }
    }

    var symbolName: String {
        switch self {
        case .dashboard: return "square.grid.2x2.fill"
        case .browse: return "rectangle.stack"
        case .collect: return "square.stack.3d.up.fill"
        case .bindrs: return "books.vertical.fill"
        case .more: return "line.3.horizontal"
        }
    }
}
