import Foundation

/// Screens opened only from the side menu (not shown in the tab bar).
enum SideMenuSheet: String, Identifiable {
    case account
    case transactions

    var id: String { rawValue }
}
