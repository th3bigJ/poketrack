import Foundation

/// Screens opened only from the side menu and not shown in the tab bar.
enum SideMenuPage: String, Identifiable, Hashable {
    case account
    case social
    case binders
    case decks
    case transactions
    case tradeCalculator
    case themes
    case gradingOpportunities
    case myAccount
    case subscription
    case backupRestore
    case libraryStorage
    case legalDisclaimer
    case privacyPolicy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .account: return "Account"
        case .social: return "Social"
        case .binders: return "Binders"
        case .decks: return "Deck Builder"
        case .transactions: return "Transactions"
        case .tradeCalculator: return "Local Trade"
        case .themes: return "Themes"
        case .gradingOpportunities: return "Grading Opportunities"
        case .myAccount: return "Account & Privacy"
        case .subscription: return "Premium"
        case .backupRestore: return "Backup and Restore"
        case .libraryStorage: return "Library Storage"
        case .legalDisclaimer: return "Legal Disclaimer"
        case .privacyPolicy: return "Privacy Policy"
        }
    }
}
