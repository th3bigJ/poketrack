import SwiftUI

enum BrowseCardGridSortOption: String, CaseIterable, Identifiable, Sendable {
    case random
    case newestSet
    case cardName
    case cardNumber
    case price
    case acquiredDateNewest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .random: return "Random"
        case .newestSet: return "Newest set"
        case .cardName: return "Card name"
        case .cardNumber: return "Card number"
        case .price: return "Price"
        case .acquiredDateNewest: return "Acquired date"
        }
    }
}

enum BrowseCardTypeFilter: String, CaseIterable, Identifiable, Sendable {
    // Pokémon TCG
    case pokemon
    case trainer
    case energy
    // One Piece
    case opLeader
    case opCharacter
    case opEvent
    case opStage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pokemon:      return "Pokemon"
        case .trainer:      return "Trainer"
        case .energy:       return "Energy"
        case .opLeader:     return "Leader"
        case .opCharacter:  return "Character"
        case .opEvent:      return "Event"
        case .opStage:      return "Stage"
        }
    }

    /// The One Piece catalog category string this filter maps to.
    var opCategoryString: String? {
        switch self {
        case .opLeader:    return "Leader"
        case .opCharacter: return "Character"
        case .opEvent:     return "Event"
        case .opStage:     return "Stage"
        default:           return nil
        }
    }
}

/// Fixed One Piece filter options — catalog-defined, don't change between sets.
let opCardTypeAllOptions: [String] = ["Character", "Event", "Leader", "Stage"]
let opAttributeAllOptions: [String] = ["Slash", "Strike", "Ranged", "Special", "Wisdom"]
let opCostAllOptions: [Int] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
let opCounterAllOptions: [Int] = [1000, 2000]
let opLifeAllOptions: [Int] = [3, 4, 5, 6]
let opPowerAllOptions: [Int] = [1000, 2000, 3000, 4000, 5000, 6000, 7000, 8000, 9000, 10000]

struct BrowseCardGridFilters: Equatable, Sendable {
    var sortBy: BrowseCardGridSortOption = .random
    var cardTypes: Set<BrowseCardTypeFilter> = []
    var rarePlusOnly = false
    var hideOwned = false
    var showDuplicates = false
    var energyTypes: Set<String> = []
    var rarities: Set<String> = []
    var trainerTypes: Set<String> = []
    /// ONE PIECE card type filter (Character / Event / Leader / Stage).
    var opCardTypes: Set<String> = []
    var opAttributes: Set<String> = []
    var opCosts: Set<Int> = []
    var opCounters: Set<Int> = []
    var opLives: Set<Int> = []
    var opPowers: Set<Int> = []

    var isDefault: Bool {
        self == Self()
    }

    var hasActiveFieldFilters: Bool {
        !cardTypes.isEmpty
            || rarePlusOnly
            || hideOwned
            || showDuplicates
            || !energyTypes.isEmpty
            || !rarities.isEmpty
            || !trainerTypes.isEmpty
            || !opCardTypes.isEmpty
            || !opAttributes.isEmpty
            || !opCosts.isEmpty
            || !opCounters.isEmpty
            || !opLives.isEmpty
            || !opPowers.isEmpty
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
    var showSetID = false
    var showPricing = false
    var showOwned = true
    var columnCount = 3

    var isDefault: Bool {
        self == Self()
    }
}
