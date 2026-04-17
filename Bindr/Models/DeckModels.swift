import SwiftData
import Foundation

// Format rules:
// Pokémon:   60 cards total, max 4 copies per card name (basic energy exempt)
// One Piece: 50 cards total, max 4 copies (Leader card treated separately — rules TBD)
// Lorcana:   60 cards total, max 4 copies per card name

enum DeckFormat: String, Codable, CaseIterable {
    case pokemonStandard  = "pokemon_standard"
    case pokemonExpanded  = "pokemon_expanded"
    case pokemonUnlimited = "pokemon_unlimited"
    case onePiece         = "onepiece_standard"
    case lorcana          = "lorcana_standard"

    var displayName: String {
        switch self {
        case .pokemonStandard:  return "Standard"
        case .pokemonExpanded:  return "Expanded"
        case .pokemonUnlimited: return "Unlimited"
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

    var maxCopiesPerCard: Int { 4 }

    static func formats(for brand: TCGBrand) -> [DeckFormat] {
        switch brand {
        case .pokemon:  return [.pokemonStandard, .pokemonExpanded, .pokemonUnlimited]
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

        let grouped = Dictionary(grouping: cardList, by: { $0.cardName })
        for (name, entries) in grouped {
            let qty = entries.reduce(0) { $0 + $1.quantity }
            let isBasicEnergy = tcgBrand == .pokemon && entries.first?.isBasicEnergy == true
            if !isBasicEnergy && qty > fmt.maxCopiesPerCard {
                issues.append("\(name): max \(fmt.maxCopiesPerCard) copies (have \(qty))")
            }
        }

        return issues
    }

    var isValid: Bool { validationIssues.isEmpty }
}

@Model final class DeckCard {
    var cardID: String = ""
    var variantKey: String = "normal"
    var cardName: String = ""
    var quantity: Int = 1
    var isBasicEnergy: Bool = false
    var deck: Deck?

    init(cardID: String, variantKey: String, cardName: String, quantity: Int, isBasicEnergy: Bool = false) {
        self.cardID = cardID
        self.variantKey = variantKey
        self.cardName = cardName
        self.quantity = quantity
        self.isBasicEnergy = isBasicEnergy
    }
}

extension Deck {
    var cardList: [DeckCard] { cards ?? [] }
}
