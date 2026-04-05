import Foundation

enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case browse
    case account

    var id: String { rawValue }

    var title: String {
        switch self {
        case .browse: return "Cards"
        case .account: return "Account"
        }
    }

    var symbolName: String {
        switch self {
        case .browse: return "rectangle.stack"
        case .account: return "person.circle"
        }
    }
}
