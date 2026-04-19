import Foundation

enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case dashboard
    case browse
    case collect
    case social
    case more

    var id: String { rawValue }

    /// Tabs that appear in the tab bar (5 tabs: Dashboard, Browse, Collect, Social, More).
    static let visibleTabs: [AppTab] = [.dashboard, .browse, .collect, .social, .more]

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .browse: return "Browse"
        case .collect: return "My Collection"
        case .social: return "Social"
        case .more: return "More"
        }
    }

    var symbolName: String {
        switch self {
        case .dashboard: return "square.grid.2x2.fill"
        case .browse: return "rectangle.stack"
        case .collect: return "square.stack.3d.up.fill"
        case .social: return "person.2.fill"
        case .more: return "line.3.horizontal"
        }
    }
}
