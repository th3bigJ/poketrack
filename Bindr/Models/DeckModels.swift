import SwiftData
import Foundation

// Format rules:
// Pokémon:   60 cards total, max 4 copies per card name (basic energy exempt)
// One Piece: 50 cards total, max 4 copies (Leader card treated separately — rules TBD)
// Lorcana:   60 cards total, max 4 copies per card name

// MARK: - Expanded legal set whitelist (Black & White onward, April 2011+)
let expandedLegalSetKeys: Set<String> = [
    "bw1","bw2","bw3","bw4","bw5","bw6","bw7","bw8","bw9","bw10","bw11","bwp",
    "xy0","xy1","xy2","xy3","xy4","xy5","xy6","xy7","xy8","xy9","xy10","xy11","xy12","xyp",
    "g1","dc1","dv1",
    "sm1","sm2","sm3","sm35","sm4","sm5","sm6","sm7","sm75","sm8","sm9","sm10","sm11","sm115","sm12","sma","smp",
    "swsh1","swsh2","swsh3","swsh35","swsh4","swsh45","swsh5","swsh6","swsh7","swsh8","swsh9","swsh10","swsh11","swsh12","swsh12pt5","swshp",
    "sv1","sv2","sv3","sv3pt5","sv4","sv4pt5","sv5","sv6","sv6pt5","sv7","sv8","sv8pt5","sv9","sv10","sve","svp",
    "rsv10pt5","zsv10pt5",
    "me1","me2","me2pt5","me3","mee","mep",
    "cel25","cel25c","clv","clc","clb",
    "pgo","fut20","det1",
    "mcd11","mcd12","mcd14","mcd15","mcd16","mcd17","mcd18","mcd19","mcd21","mcd22","mcd23","mcd24",
]

// MARK: - Expanded ban list (card names, English)
let expandedBannedCardNames: Set<String> = [
    "Archeops",
    "Chip-Chip Ice Axe",
    "Delinquent",
    "Duskull",
    "Flabébé",
    "Flapple",
    "Forest of Giant Plants",
    "Ghetsis",
    "Hex Maniac",
    "Island Challenge Amulet",
    "Jessie & James",
    "Lt. Surge's Strategy",
    "Lysandre's Trump Card",
    "Marshadow",
    "Maxie's Hidden Ball Trick",
    "Medicham V",
    "Milotic",
    "Mismagius",
    "Oranguru",
    "Puzzle of Time",
    "Red Card",
    "Reset Stamp",
    "Sableye",
    "Scoop Up Net",
    "Shaymin-EX",
    "Unown",
]

enum DeckFormat: String, Codable, CaseIterable {
    case pokemonStandard  = "pokemon_standard"
    case pokemonExpanded  = "pokemon_expanded"
    case pokemonUnlimited = "pokemon_unlimited"
    case pokemonGLC       = "pokemon_glc"
    case onePiece         = "onepiece_standard"
    case lorcana          = "lorcana_standard"

    var displayName: String {
        switch self {
        case .pokemonStandard:  return "Standard"
        case .pokemonExpanded:  return "Expanded"
        case .pokemonUnlimited: return "Unlimited"
        case .pokemonGLC:       return "GLC"
        case .onePiece:         return "Standard"
        case .lorcana:          return "Standard"
        }
    }

    var deckSize: Int {
        switch self {
        case .onePiece: return 50
        default:        return 60
        }
    }

    var maxCopiesPerCard: Int {
        switch self {
        case .pokemonGLC: return 1
        default:          return 4
        }
    }

    /// Set keys legal in this format. nil = all sets legal.
    var legalSetKeys: Set<String>? {
        switch self {
        case .pokemonStandard:  return nil  // enforced via regulation mark instead
        case .pokemonExpanded:  return expandedLegalSetKeys
        case .pokemonGLC:       return expandedLegalSetKeys
        case .pokemonUnlimited: return nil
        case .onePiece:         return nil
        case .lorcana:          return nil
        }
    }

    /// Regulation marks legal in Standard. nil = no mark restriction.
    var legalRegulationMarks: Set<String>? {
        switch self {
        case .pokemonStandard: return ["H", "I", "J"]
        default:               return nil
        }
    }

    var rulesDescription: String {
        switch self {
        case .pokemonStandard:
            return """
                • 60 cards total
                • Max 4 copies per card (Basic Energy exempt)
                • Regulation marks H, I, J only
                • At least 1 Basic Pokémon required
                • ACE SPEC cards: max 1 per deck
                • Radiant Pokémon: max 1 per deck
                """
        case .pokemonExpanded:
            return """
                • 60 cards total
                • Max 4 copies per card (Basic Energy exempt)
                • Black & White sets onward
                • At least 1 Basic Pokémon required
                • ACE SPEC cards: max 1 per deck
                • Radiant Pokémon: max 1 per deck
                • Ban list applies
                """
        case .pokemonUnlimited:
            return """
                • 60 cards total
                • Max 4 copies per card (Basic Energy exempt)
                • All sets legal
                • At least 1 Basic Pokémon required
                • ACE SPEC cards: max 1 per deck
                • Radiant Pokémon: max 1 per deck
                """
        case .pokemonGLC:
            return """
                • 60 cards total
                • 1 copy of each card (Basic Energy exempt)
                • No rule-box Pokémon (ex/V/GX/VMAX/VSTAR)
                • All Pokémon must share one type
                • Black & White sets onward
                • Ban list applies
                """
        case .onePiece:
            return """
                • 50 cards total
                • Max 4 copies per card
                """
        case .lorcana:
            return """
                • 60 cards total
                • Max 4 copies per card
                """
        }
    }

    func isBanned(cardName: String) -> Bool {
        switch self {
        case .pokemonExpanded, .pokemonGLC:
            return expandedBannedCardNames.contains(cardName)
        default:
            return false
        }
    }

    static func formats(for brand: TCGBrand) -> [DeckFormat] {
        switch brand {
        case .pokemon:  return [.pokemonStandard, .pokemonExpanded, .pokemonUnlimited, .pokemonGLC]
        case .onePiece: return [.onePiece]
        case .lorcana:  return [.lorcana]
        }
    }
}

@Model final class Deck {
    var id: UUID = UUID()
    var title: String = ""
    var brand: String = TCGBrand.pokemon.rawValue
    var format: String = DeckFormat.pokemonStandard.rawValue
    var createdAt: Date = Date()
    @Relationship(deleteRule: .cascade, inverse: \DeckCard.deck)
    var cards: [DeckCard]? = []

    init(title: String, brand: TCGBrand, format: DeckFormat) {
        self.id = UUID()
        self.title = title
        self.brand = brand.rawValue
        self.format = format.rawValue
        self.createdAt = Date()
    }

    var tcgBrand: TCGBrand {
        TCGBrand(rawValue: brand) ?? .pokemon
    }

    var deckFormat: DeckFormat {
        DeckFormat(rawValue: format) ?? .pokemonStandard
    }

    var totalCardCount: Int {
        cardList.reduce(0) { $0 + $1.quantity }
    }

    var validationIssues: [String] {
        var issues: [String] = []
        let fmt = deckFormat
        let total = totalCardCount

        if total != fmt.deckSize {
            issues.append("Deck must have exactly \(fmt.deckSize) cards (currently \(total))")
        }

        guard tcgBrand == .pokemon else {
            // Non-Pokemon: just check copy limits
            let grouped = Dictionary(grouping: cardList, by: { $0.cardName })
            for (name, entries) in grouped {
                let qty = entries.reduce(0) { $0 + $1.quantity }
                if qty > fmt.maxCopiesPerCard {
                    issues.append("\(name): max \(fmt.maxCopiesPerCard) copies (have \(qty))")
                }
            }
            return issues
        }

        // Must contain at least one Basic Pokémon
        let hasBasicPokemon = cardList.contains { $0.isBasicPokemon }
        if !hasBasicPokemon {
            issues.append("Deck must contain at least 1 Basic Pokémon")
        }

        let grouped = Dictionary(grouping: cardList, by: { $0.cardName })

        for (name, entries) in grouped {
            let qty = entries.reduce(0) { $0 + $1.quantity }
            let first = entries.first!

            // Copy limits
            if !first.isBasicEnergy && qty > fmt.maxCopiesPerCard {
                issues.append("\(name): max \(fmt.maxCopiesPerCard) copies (have \(qty))")
            }

            // ACE SPEC: max 1 per deck
            if first.isAceSpec && qty > 1 {
                issues.append("\(name): ACE SPEC cards are limited to 1 copy")
            }

            // Radiant Pokémon: max 1 per deck
            if first.isRadiant && qty > 1 {
                issues.append("\(name): Radiant Pokémon are limited to 1 copy")
            }

            // Expanded ban list
            if fmt.isBanned(cardName: name) {
                issues.append("\(name) is banned in \(fmt.displayName)")
            }

            // Set legality
            if let legalSets = fmt.legalSetKeys, !first.setKey.isEmpty, !legalSets.contains(first.setKey) {
                issues.append("\(name) is from set \(first.setKey) which is not legal in \(fmt.displayName)")
            }

            // Standard regulation mark (energy cards are exempt — many lack marks)
            if let legalMarks = fmt.legalRegulationMarks, !first.isEnergyCard {
                if let mark = first.regulationMark {
                    if !legalMarks.contains(mark) {
                        issues.append("\(name) (mark \(mark)) is not legal in Standard")
                    }
                } else {
                    issues.append("\(name) has no regulation mark and is not legal in Standard")
                }
            }
        }

        // GLC-specific rules
        if fmt == .pokemonGLC {
            // No rule-box Pokémon
            let ruleBoxCards = cardList.filter { $0.isRuleBox }
            for card in ruleBoxCards {
                issues.append("\(card.cardName): rule-box Pokémon (ex/V/GX/VMAX/VSTAR) are not allowed in GLC")
            }

            // All Pokémon must share one type
            let pokemonCards = cardList.filter { $0.isBasicPokemon || (!$0.isBasicEnergy && !$0.isRuleBox) }
            let allTypes = pokemonCards.compactMap { $0.elementTypes }.flatMap { $0 }.filter { $0 != "Colorless" }
            let typeSet = Set(allTypes)
            if typeSet.count > 1 {
                issues.append("GLC: all Pokémon must share one type (found: \(typeSet.sorted().joined(separator: ", ")))")
            }
        }

        // ACE SPEC: only 1 total across the whole deck
        let aceSpecTotal = cardList.filter { $0.isAceSpec }.reduce(0) { $0 + $1.quantity }
        if aceSpecTotal > 1 {
            issues.append("Only 1 ACE SPEC card is allowed per deck (have \(aceSpecTotal))")
        }

        return issues
    }

    var isValid: Bool { validationIssues.isEmpty }

    /// The ID of the first card in the deck, used for the "Hero Card" preview on the deck box.
    var heroCardID: String? {
        cardList.first?.cardID
    }
}

@Model final class DeckCard {
    var cardID: String = ""
    var variantKey: String = "normal"
    var cardName: String = ""
    var quantity: Int = 1
    var isBasicEnergy: Bool = false
    var isAceSpec: Bool = false
    var isRadiant: Bool = false
    var isBasicPokemon: Bool = false
    var isRuleBox: Bool = false
    var setKey: String = ""
    var regulationMark: String? = nil
    var elementTypes: [String]? = nil
    var trainerType: String? = nil
    var isEnergy: Bool = false
    var imageLowSrc: String = ""
    /// Canonical TCG category string from catalog (e.g. `Pokémon`, `Trainer`, `Energy`). Used so deck sections match all Pokémon stages, not only Basics / rule boxes.
    var catalogCategory: String?
    var deck: Deck?

    var isEnergyCard: Bool { isBasicEnergy || isEnergy }

    init(
        cardID: String,
        variantKey: String,
        cardName: String,
        quantity: Int,
        isBasicEnergy: Bool = false,
        isAceSpec: Bool = false,
        isRadiant: Bool = false,
        isBasicPokemon: Bool = false,
        isRuleBox: Bool = false,
        setKey: String = "",
        regulationMark: String? = nil,
        elementTypes: [String]? = nil,
        trainerType: String? = nil,
        isEnergy: Bool = false,
        imageLowSrc: String = "",
        catalogCategory: String? = nil
    ) {
        self.cardID = cardID
        self.variantKey = variantKey
        self.cardName = cardName
        self.quantity = quantity
        self.isBasicEnergy = isBasicEnergy
        self.isAceSpec = isAceSpec
        self.isRadiant = isRadiant
        self.isBasicPokemon = isBasicPokemon
        self.isRuleBox = isRuleBox
        self.setKey = setKey
        self.regulationMark = regulationMark
        self.elementTypes = elementTypes
        self.trainerType = trainerType
        self.isEnergy = isEnergy
        self.imageLowSrc = imageLowSrc
        self.catalogCategory = catalogCategory
    }
}

extension Deck {
    var cardList: [DeckCard] { cards ?? [] }
}
