import SwiftUI

enum BrowseCardGridSortOption: String, CaseIterable, Identifiable, Sendable, Codable {
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

enum BrowseCardTypeFilter: String, CaseIterable, Identifiable, Sendable, Codable {
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

    static let pokemonOptions: [BrowseCardTypeFilter] = [.pokemon, .trainer, .energy]

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

enum BrowseCardLegalityFilter: String, CaseIterable, Identifiable, Sendable, Codable {
    case standard
    case expanded

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: return "Standard"
        case .expanded: return "Expanded"
        }
    }

    var deckFormat: DeckFormat {
        switch self {
        case .standard: return .pokemonStandard
        case .expanded: return .pokemonExpanded
        }
    }
}

enum BrowseCardAbilityPresenceFilter: String, CaseIterable, Identifiable, Sendable, Codable {
    case yes
    case no

    var id: String { rawValue }

    var title: String {
        switch self {
        case .yes: return "Yes"
        case .no: return "No"
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
let pokemonSubtypeAllOptions: [String] = [
    "Basic",
    "Stage 1",
    "Stage 2",
    "VMAX",
    "VSTAR",
    "MEGA",
    "EX",
    "Level-Up:",
    "BREAK",
    "V-UNION",
    "Baby",
    "LEGEND",
    "Restored"
]

struct SealedProductTypeFilterOption: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let rawTypes: Set<String>
}

let sealedProductTypeFilterOptions: [SealedProductTypeFilterOption] = [
    SealedProductTypeFilterOption(id: "battlebox", title: "battlebox", rawTypes: ["battlebox"]),
    SealedProductTypeFilterOption(id: "blisterpack", title: "blisterpack", rawTypes: ["blisterpack"]),
    SealedProductTypeFilterOption(id: "boosterbox", title: "boosterbox", rawTypes: ["boosterbox"]),
    SealedProductTypeFilterOption(id: "boosterpack", title: "boosterpack", rawTypes: ["boosterpack"]),
    SealedProductTypeFilterOption(
        id: "collections",
        title: "Collections",
        rawTypes: ["collectionbox", "collectionchest"]
    ),
    SealedProductTypeFilterOption(id: "deck", title: "deck", rawTypes: ["deck"]),
    SealedProductTypeFilterOption(id: "elitetrainerbox", title: "elitetrainerbox", rawTypes: ["elitetrainerbox"]),
    SealedProductTypeFilterOption(id: "miscellaneous", title: "miscellaneous", rawTypes: ["miscellaneous"]),
    SealedProductTypeFilterOption(id: "pincollection", title: "pincollection", rawTypes: ["pincollection"]),
    SealedProductTypeFilterOption(
        id: "special",
        title: "Special",
        rawTypes: ["specialbox", "specialpack", "specialset"]
    ),
    SealedProductTypeFilterOption(id: "starterset", title: "starterset", rawTypes: ["starterset"]),
    SealedProductTypeFilterOption(id: "tin", title: "tin", rawTypes: ["tin"])
]

private let sealedProductTypeFilterOptionByID: [String: SealedProductTypeFilterOption] = Dictionary(
    uniqueKeysWithValues: sealedProductTypeFilterOptions.map { ($0.id, $0) }
)

func normalizeSealedProductTypeToken(_ value: String?) -> String {
    guard let value else { return "" }
    return value
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
        .replacingOccurrences(of: "_", with: "")
        .replacingOccurrences(of: " ", with: "")
}

func sealedProductMatchesSelectedTypes(_ rawType: String?, selectedOptionIDs: Set<String>) -> Bool {
    guard !selectedOptionIDs.isEmpty else { return true }
    let normalizedRawType = normalizeSealedProductTypeToken(rawType)
    guard !normalizedRawType.isEmpty else { return false }
    for optionID in selectedOptionIDs {
        guard let option = sealedProductTypeFilterOptionByID[optionID] else { continue }
        if option.rawTypes.contains(normalizedRawType) {
            return true
        }
    }
    return false
}

struct BrowseCardGridFilters: Equatable, Sendable, Codable {
    var sortBy: BrowseCardGridSortOption = .random
    var cardTypes: Set<BrowseCardTypeFilter> = []
    var rarePlusOnly = false
    var hideOwned = false
    var showDuplicates = false
    var energyTypes: Set<String> = []
    var rarities: Set<String> = []
    var trainerTypes: Set<String> = []
    var pokemonSubtypes: Set<String> = []
    var abilityPresence: BrowseCardAbilityPresenceFilter? = nil
    var legalities: Set<BrowseCardLegalityFilter> = []
    /// ONE PIECE card type filter (Character / Event / Leader / Stage).
    var opCardTypes: Set<String> = []
    var opAttributes: Set<String> = []
    var opCosts: Set<Int> = []
    var opCounters: Set<Int> = []
    var opLives: Set<Int> = []
    var opPowers: Set<Int> = []
    /// Sealed product type filters (supports grouped options like Collections / Special).
    var sealedProductTypes: Set<String> = []

    var isDefault: Bool {
        self == Self()
    }

    var hasActiveCardFieldFilters: Bool {
        !cardTypes.isEmpty
            || rarePlusOnly
            || hideOwned
            || showDuplicates
            || !energyTypes.isEmpty
            || !rarities.isEmpty
            || !trainerTypes.isEmpty
            || !pokemonSubtypes.isEmpty
            || abilityPresence != nil
            || !legalities.isEmpty
            || !opCardTypes.isEmpty
            || !opAttributes.isEmpty
            || !opCosts.isEmpty
            || !opCounters.isEmpty
            || !opLives.isEmpty
            || !opPowers.isEmpty
    }

    var hasActiveSealedFieldFilters: Bool {
        !sealedProductTypes.isEmpty
    }

    var hasActiveFieldFilters: Bool {
        hasActiveCardFieldFilters || hasActiveSealedFieldFilters
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

    enum CodingKeys: String, CodingKey {
        case sortBy
        case cardTypes
        case rarePlusOnly
        case hideOwned
        case showDuplicates
        case energyTypes
        case rarities
        case trainerTypes
        case pokemonSubtypes
        case abilityPresence
        case legalities
        case opCardTypes
        case opAttributes
        case opCosts
        case opCounters
        case opLives
        case opPowers
        case sealedProductTypes
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sortBy = try container.decodeIfPresent(BrowseCardGridSortOption.self, forKey: .sortBy) ?? .random
        cardTypes = try container.decodeIfPresent(Set<BrowseCardTypeFilter>.self, forKey: .cardTypes) ?? []
        rarePlusOnly = try container.decodeIfPresent(Bool.self, forKey: .rarePlusOnly) ?? false
        hideOwned = try container.decodeIfPresent(Bool.self, forKey: .hideOwned) ?? false
        showDuplicates = try container.decodeIfPresent(Bool.self, forKey: .showDuplicates) ?? false
        energyTypes = try container.decodeIfPresent(Set<String>.self, forKey: .energyTypes) ?? []
        rarities = try container.decodeIfPresent(Set<String>.self, forKey: .rarities) ?? []
        trainerTypes = try container.decodeIfPresent(Set<String>.self, forKey: .trainerTypes) ?? []
        pokemonSubtypes = try container.decodeIfPresent(Set<String>.self, forKey: .pokemonSubtypes) ?? []
        abilityPresence = try container.decodeIfPresent(BrowseCardAbilityPresenceFilter.self, forKey: .abilityPresence)
        legalities = try container.decodeIfPresent(Set<BrowseCardLegalityFilter>.self, forKey: .legalities) ?? []
        opCardTypes = try container.decodeIfPresent(Set<String>.self, forKey: .opCardTypes) ?? []
        opAttributes = try container.decodeIfPresent(Set<String>.self, forKey: .opAttributes) ?? []
        opCosts = try container.decodeIfPresent(Set<Int>.self, forKey: .opCosts) ?? []
        opCounters = try container.decodeIfPresent(Set<Int>.self, forKey: .opCounters) ?? []
        opLives = try container.decodeIfPresent(Set<Int>.self, forKey: .opLives) ?? []
        opPowers = try container.decodeIfPresent(Set<Int>.self, forKey: .opPowers) ?? []
        sealedProductTypes = try container.decodeIfPresent(Set<String>.self, forKey: .sealedProductTypes) ?? []
    }
}

struct BrowseGridOptions: Equatable, Sendable, Codable {
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
