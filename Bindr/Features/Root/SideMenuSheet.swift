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
    case backupRestore
    case dataExport
    case libraryStorage
    case legalDisclaimer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .account: return "Account"
        case .social: return "Social"
        case .binders: return "Binders"
        case .decks: return "Deck Builder"
        case .transactions: return "Transactions"
        case .tradeCalculator: return "Trade Calculator"
        case .themes: return "Themes"
        case .gradingOpportunities: return "Grading Opportunities"
        case .myAccount: return "Account & Privacy"
        case .backupRestore: return "Backup and Restore"
        case .dataExport: return "Export Data"
        case .libraryStorage: return "Library Storage"
        case .legalDisclaimer: return "Legal Disclaimer"
        }
    }
}
