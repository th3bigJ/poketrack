import SwiftUI

enum BrowseCardGridSortOption: String, CaseIterable, Identifiable, Sendable {
    case random
    case newestSet
    case cardName
    case cardNumber
    case rarity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .random: return "Random"
        case .newestSet: return "Newest set"
        case .cardName: return "Card name"
        case .cardNumber: return "Card number"
        case .rarity: return "Rarity"
        }
    }
}

enum BrowseCardTypeFilter: String, CaseIterable, Identifiable, Sendable {
    case pokemon
    case trainer
    case energy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pokemon: return "Pokemon"
        case .trainer: return "Trainer"
        case .energy: return "Energy"
        }
    }
}

/// Fixed One Piece card type values — these are catalog-defined and don't change.
let opCardTypeAllOptions: [String] = ["Character", "Event", "Leader", "Stage"]

struct BrowseCardGridFilters: Equatable, Sendable {
    var sortBy: BrowseCardGridSortOption = .random
    var cardTypes: Set<BrowseCardTypeFilter> = []
    var rarePlusOnly = false
    var hideOwned = false
    var energyTypes: Set<String> = []
    var rarities: Set<String> = []
    var trainerTypes: Set<String> = []
    /// ONE PIECE card type filter (Character / Event / Leader / Stage).
    var opCardTypes: Set<String> = []

    var isDefault: Bool {
        self == Self()
    }

    var hasActiveFieldFilters: Bool {
        !cardTypes.isEmpty
            || rarePlusOnly
            || hideOwned
            || !energyTypes.isEmpty
            || !rarities.isEmpty
            || !trainerTypes.isEmpty
            || !opCardTypes.isEmpty
    }

    var hasActiveSort: Bool {
        sortBy != .random
    }

    var hasActiveDataFilters: Bool {
        hasActiveFieldFilters
    }

    var isVisiblyCustomized: Bool {
        hasActiveFieldFilters
    }
}

struct BrowseGridOptions: Equatable, Sendable {
    var showCardName = true
    var showSetName = false
    var showPricing = false
    var columnCount = 3
}
