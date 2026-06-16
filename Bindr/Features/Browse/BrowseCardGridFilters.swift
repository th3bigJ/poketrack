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
    case pokemon
    case trainer
    case energy

    var id: String { rawValue }

    static let pokemonOptions: [BrowseCardTypeFilter] = [.pokemon, .trainer, .energy]

    var title: String {
        switch self {
        case .pokemon: return "Pokemon"
        case .trainer: return "Trainer"
        case .energy:  return "Energy"
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
let pokemonWeaknessFilterAllOptions: [String] = [
    "Colorless",
    "Darkness",
    "Dragon",
    "Fairy",
    "Fighting",
    "Fire",
    "Grass",
    "Lightning",
    "Metal",
    "Psychic",
    "Water"
]
let pokemonResistanceFilterAllOptions: [String] = [
    "Colorless",
    "Darkness",
    "Fighting",
    "Fire",
    "Lightning",
    "Metal",
    "Psychic",
    "Water"
]

struct ProductTypeFilterOption: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let rawTypes: Set<String>
}

let productTypeFilterOptions: [ProductTypeFilterOption] = [
    ProductTypeFilterOption(
        id: "battlebox",
        title: "Battle Box",
        rawTypes: ["battlebox", "buildbattlebox", "build&battlebox", "buildbattle"]
    ),
    ProductTypeFilterOption(
        id: "blisterpack",
        title: "Blister Pack",
        rawTypes: ["blisterpack", "blister", "3packblister", "checklanepack"]
    ),
    ProductTypeFilterOption(
        id: "boosterbox",
        title: "Booster Box",
        rawTypes: ["boosterbox", "boosterdisplay", "boosterbundle"]
    ),
    ProductTypeFilterOption(
        id: "boosterpack",
        title: "Booster Pack",
        rawTypes: ["boosterpack", "booster", "sleevedbooster"]
    ),
    ProductTypeFilterOption(
        id: "collections",
        title: "Collections",
        rawTypes: ["collectionbox", "collectionchest", "collection", "box", "case", "premiumcollection"]
    ),
    ProductTypeFilterOption(
        id: "deck",
        title: "Deck",
        rawTypes: ["deck", "starterdeck", "themedeck", "vbattledeck"]
    ),
    ProductTypeFilterOption(
        id: "elitetrainerbox",
        title: "Elite Trainer Box",
        rawTypes: ["elitetrainerbox", "etb", "pokemoncenterelitetrainerbox"]
    ),
    ProductTypeFilterOption(
        id: "miscellaneous",
        title: "Miscellaneous",
        rawTypes: ["miscellaneous", "misc", "accessories", "other"]
    ),
    ProductTypeFilterOption(
        id: "pincollection",
        title: "Pin Collection",
        rawTypes: ["pincollection", "pinbox"]
    ),
    ProductTypeFilterOption(
        id: "special",
        title: "Special",
        rawTypes: ["specialbox", "specialpack", "specialset", "celebrations", "anniversary"]
    ),
    ProductTypeFilterOption(
        id: "starterset",
        title: "Starter Set",
        rawTypes: ["starterset", "starterpack"]
    ),
    ProductTypeFilterOption(
        id: "tin",
        title: "Tin",
        rawTypes: ["tin", "stackingtin", "pokeballtin"]
    )
]

private let productTypeFilterOptionByID: [String: ProductTypeFilterOption] = Dictionary(
    uniqueKeysWithValues: productTypeFilterOptions.map { ($0.id, $0) }
)

func normalizeSealedProductTypeToken(_ value: String?) -> String {
    guard let value else { return "" }
    return value
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
        .replacingOccurrences(of: "_", with: "")
        .replacingOccurrences(of: " ", with: "")
}

func productMatchesSelectedTypes(_ rawType: String?, selectedOptionIDs: Set<String>) -> Bool {
    guard !selectedOptionIDs.isEmpty else { return true }
    let normalizedRawType = normalizeSealedProductTypeToken(rawType)
    guard !normalizedRawType.isEmpty else { return false }
    for optionID in selectedOptionIDs {
        guard let option = productTypeFilterOptionByID[optionID] else { continue }
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
    var ownedOnly = false
    var showDuplicates = false
    var energyTypes: Set<String> = []
    var rarities: Set<String> = []
    var trainerTypes: Set<String> = []
    var weaknessTypes: Set<String> = []
    var resistanceTypes: Set<String> = []
    var pokemonSubtypes: Set<String> = []
    var abilityPresence: BrowseCardAbilityPresenceFilter? = nil
    var legalities: Set<BrowseCardLegalityFilter> = []
    /// When non-empty, only cards whose set belongs to one of these series names are shown.
    var seriesNames: Set<String> = []
    /// Product type filters (supports grouped options like Collections / Special).
    var productTypes: Set<String> = []

    var isDefault: Bool {
        self == Self()
    }

    var hasActiveCardFieldFilters: Bool {
        !cardTypes.isEmpty
            || rarePlusOnly
            || hideOwned
            || ownedOnly
            || showDuplicates
            || !energyTypes.isEmpty
            || !rarities.isEmpty
            || !trainerTypes.isEmpty
            || !weaknessTypes.isEmpty
            || !resistanceTypes.isEmpty
            || !pokemonSubtypes.isEmpty
            || abilityPresence != nil
            || !legalities.isEmpty
            || !seriesNames.isEmpty
    }

    var hasActiveProductFieldFilters: Bool {
        !productTypes.isEmpty
    }

    var hasActiveFieldFilters: Bool {
        hasActiveCardFieldFilters || hasActiveProductFieldFilters
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
        case ownedOnly
        case showDuplicates
        case energyTypes
        case rarities
        case trainerTypes
        case weaknessTypes
        case resistanceTypes
        case pokemonSubtypes
        case abilityPresence
        case legalities
        case seriesNames
        case productTypes
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sortBy = try container.decodeIfPresent(BrowseCardGridSortOption.self, forKey: .sortBy) ?? .random
        cardTypes = try container.decodeIfPresent(Set<BrowseCardTypeFilter>.self, forKey: .cardTypes) ?? []
        rarePlusOnly = try container.decodeIfPresent(Bool.self, forKey: .rarePlusOnly) ?? false
        hideOwned = try container.decodeIfPresent(Bool.self, forKey: .hideOwned) ?? false
        ownedOnly = try container.decodeIfPresent(Bool.self, forKey: .ownedOnly) ?? false
        showDuplicates = try container.decodeIfPresent(Bool.self, forKey: .showDuplicates) ?? false
        energyTypes = try container.decodeIfPresent(Set<String>.self, forKey: .energyTypes) ?? []
        rarities = try container.decodeIfPresent(Set<String>.self, forKey: .rarities) ?? []
        trainerTypes = try container.decodeIfPresent(Set<String>.self, forKey: .trainerTypes) ?? []
        weaknessTypes = try container.decodeIfPresent(Set<String>.self, forKey: .weaknessTypes) ?? []
        resistanceTypes = try container.decodeIfPresent(Set<String>.self, forKey: .resistanceTypes) ?? []
        pokemonSubtypes = try container.decodeIfPresent(Set<String>.self, forKey: .pokemonSubtypes) ?? []
        abilityPresence = try container.decodeIfPresent(BrowseCardAbilityPresenceFilter.self, forKey: .abilityPresence)
        legalities = try container.decodeIfPresent(Set<BrowseCardLegalityFilter>.self, forKey: .legalities) ?? []
        seriesNames = try container.decodeIfPresent(Set<String>.self, forKey: .seriesNames) ?? []
        productTypes = try container.decodeIfPresent(Set<String>.self, forKey: .productTypes) ?? []
    }
}

func browseFilterSeriesOptions(from sets: [TCGSet]) -> [String] {
    let grouped = Dictionary(grouping: sets) { set -> String? in
        let title = set.seriesName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? nil : title
    }
    return grouped.compactMap { key, groupedSets -> (title: String, newestReleaseDate: String)? in
        guard let key else { return nil }
        let newestReleaseDate = groupedSets.compactMap(\.releaseDate).max() ?? ""
        return (title: key, newestReleaseDate: newestReleaseDate)
    }
    .sorted { lhs, rhs in
        if lhs.newestReleaseDate != rhs.newestReleaseDate {
            return lhs.newestReleaseDate > rhs.newestReleaseDate
        }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }
    .map(\.title)
}

func seriesNameBySetCode(from sets: [TCGSet]) -> [String: String] {
    var result: [String: String] = [:]
    result.reserveCapacity(sets.count)
    for set in sets {
        if result[set.setCode] == nil {
            result[set.setCode] = set.seriesName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
    }
    return result
}

func cardMatchesSeriesNamesFilter(
    setCode: String,
    selectedSeriesNames: Set<String>,
    seriesNameBySetCode: [String: String]
) -> Bool {
    guard !selectedSeriesNames.isEmpty else { return true }
    let series = seriesNameBySetCode[setCode] ?? ""
    guard !series.isEmpty else { return false }
    return selectedSeriesNames.contains(series)
}

struct BrowseGridOptions: Equatable, Sendable, Codable {
    var showCardName = true
    var showSetName = true
    var showSetID = false
    var showPricing = true
    var showOwned = true
    var columnCount = 3

    var isDefault: Bool {
        self == Self()
    }
}
