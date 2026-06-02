import Foundation
import SwiftData

@MainActor
final class PTCGLService {
    static let shared = PTCGLService()
    
    private init() {}
    
    /// Parses a PTCGL plaintext decklist and returns a list of card components.
    struct ParsedLine {
        let quantity: Int
        let name: String
        let setCode: String
        let cardNumber: String
    }
    
    func parseDecklist(_ text: String) -> [ParsedLine] {
        let lines = text.components(separatedBy: .newlines)
        var parsed: [ParsedLine] = []
        
        // Regex for: (Quantity) (Name) (SetToken) (CardToken)
        // e.g. "1 Boss's Orders MEG 114" or "4 Basic {P} Energy MEE 5"
        // Keep set/number tokens permissive because catalog setKey tokens vary by source.
        let regex = try? NSRegularExpression(pattern: #"^(\d+)\s+(.+)\s+(\S+)\s+(\S+)$"#, options: [])
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            
            // Skip headers like "Pokémon:", "Trainer:", "Energy:"
            if trimmed.hasSuffix(":") { continue }
            
            if let match = regex?.firstMatch(in: trimmed, options: [], range: NSRange(trimmed.startIndex..., in: trimmed)) {
                if let qtyRange = Range(match.range(at: 1), in: trimmed),
                   let nameRange = Range(match.range(at: 2), in: trimmed),
                   let setRange = Range(match.range(at: 3), in: trimmed),
                   let numRange = Range(match.range(at: 4), in: trimmed) {
                    
                    let qty = Int(trimmed[qtyRange]) ?? 1
                    let name = String(trimmed[nameRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let set = String(trimmed[setRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let num = String(trimmed[numRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    parsed.append(ParsedLine(quantity: qty, name: name, setCode: set, cardNumber: num))
                }
            } else {
                // Fallback for basic energy which often lacks set/number in some exports
                // e.g. "12 Fire Energy" or "12 Fire Energy SVE 2"
                let energyRegex = try? NSRegularExpression(pattern: #"^(\d+)\s+(.+ Energy)(?:\s+(\S+)\s+(\S+))?$"#, options: [])
                if let match = energyRegex?.firstMatch(in: trimmed, options: [], range: NSRange(trimmed.startIndex..., in: trimmed)) {
                     if let qtyRange = Range(match.range(at: 1), in: trimmed),
                        let nameRange = Range(match.range(at: 2), in: trimmed) {
                         
                         let qty = Int(trimmed[qtyRange]) ?? 1
                         let name = String(trimmed[nameRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                         let set = match.range(at: 3).location != NSNotFound ? String(trimmed[Range(match.range(at: 3), in: trimmed)!]) : "SVE"
                         let num = match.range(at: 4).location != NSNotFound ? String(trimmed[Range(match.range(at: 4), in: trimmed)!]) : ""
                         
                         parsed.append(ParsedLine(quantity: qty, name: name, setCode: set, cardNumber: num))
                     }
                }
            }
        }
        
        return parsed
    }
    
    /// Converts a Deck into PTCGL plaintext.
    func exportToPTCGL(deck: Deck, sets: [TCGSet], cardsByMasterId: [String: Card] = [:]) -> String {
        var output = ""
        let cards = deck.cardList
        let abbreviationBySetKey = buildSetAbbreviationLookup(from: sets)
        
        // Group by category for cleaner output
        let pokemon = cards.filter { ($0.catalogCategory ?? "").lowercased() == "pokémon" }
        let trainers = cards.filter { ($0.catalogCategory ?? "").lowercased() == "trainer" }
        let energy = cards.filter { ($0.catalogCategory ?? "").lowercased() == "energy" }
        
        if !pokemon.isEmpty {
            output += "Pokémon: \(pokemon.reduce(0) { $0 + $1.quantity })\n"
            for card in pokemon {
                output += formatCard(card, abbreviationBySetKey: abbreviationBySetKey, cardsByMasterId: cardsByMasterId) + "\n"
            }
            output += "\n"
        }
        
        if !trainers.isEmpty {
            output += "Trainer: \(trainers.reduce(0) { $0 + $1.quantity })\n"
            for card in trainers {
                output += formatCard(card, abbreviationBySetKey: abbreviationBySetKey, cardsByMasterId: cardsByMasterId) + "\n"
            }
            output += "\n"
        }
        
        if !energy.isEmpty {
            output += "Energy: \(energy.reduce(0) { $0 + $1.quantity })\n"
            for card in energy {
                output += formatCard(card, abbreviationBySetKey: abbreviationBySetKey, cardsByMasterId: cardsByMasterId) + "\n"
            }
        }
        
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Converts a Deck into official league formatted plain text.
    func exportToOfficialLeague(deck: Deck, sets: [TCGSet], cardsByMasterId: [String: Card] = [:]) -> String {
        var output = ""
        let cards = deck.cardList
        let setNameLookup = buildSetNameLookup(from: sets)
        
        output += "DECK LIST: \(deck.title)\n"
        output += "TCG: \(deck.tcgBrand == .pokemon ? "Pokémon" : "One Piece")\n"
        output += "Format: \(deck.deckFormat.displayName)\n"
        output += "Total Cards: \(deck.totalCardCount)\n\n"
        
        if deck.tcgBrand == .onePiece {
            let leaders = cards.filter { $0.opCategory == .leader }
            let characters = cards.filter { $0.opCategory == .character }
            let events = cards.filter { $0.opCategory == .event }
            let stages = cards.filter { $0.opCategory == .stage }
            
            if !leaders.isEmpty {
                output += "LEADER (\(leaders.reduce(0) { $0 + $1.quantity })):\n"
                for card in leaders {
                    output += formatLeagueCard(card, nameBySetKey: setNameLookup, cardsByMasterId: cardsByMasterId) + "\n"
                }
                output += "\n"
            }
            if !characters.isEmpty {
                output += "CHARACTERS (\(characters.reduce(0) { $0 + $1.quantity })):\n"
                for card in characters {
                    output += formatLeagueCard(card, nameBySetKey: setNameLookup, cardsByMasterId: cardsByMasterId) + "\n"
                }
                output += "\n"
            }
            if !events.isEmpty {
                output += "EVENTS (\(events.reduce(0) { $0 + $1.quantity })):\n"
                for card in events {
                    output += formatLeagueCard(card, nameBySetKey: setNameLookup, cardsByMasterId: cardsByMasterId) + "\n"
                }
                output += "\n"
            }
            if !stages.isEmpty {
                output += "STAGES (\(stages.reduce(0) { $0 + $1.quantity })):\n"
                for card in stages {
                    output += formatLeagueCard(card, nameBySetKey: setNameLookup, cardsByMasterId: cardsByMasterId) + "\n"
                }
            }
        } else {
            let pokemon = cards.filter { $0.pokemonCategory == .pokemon }
            let trainers = cards.filter { $0.pokemonCategory == .trainer }
            let energy = cards.filter { $0.pokemonCategory == .energy }
            
            if !pokemon.isEmpty {
                output += "POKÉMON (\(pokemon.reduce(0) { $0 + $1.quantity })):\n"
                for card in pokemon {
                    output += formatLeagueCard(card, nameBySetKey: setNameLookup, cardsByMasterId: cardsByMasterId) + "\n"
                }
                output += "\n"
            }
            if !trainers.isEmpty {
                output += "TRAINER (\(trainers.reduce(0) { $0 + $1.quantity })):\n"
                for card in trainers {
                    output += formatLeagueCard(card, nameBySetKey: setNameLookup, cardsByMasterId: cardsByMasterId) + "\n"
                }
                output += "\n"
            }
            if !energy.isEmpty {
                output += "ENERGY (\(energy.reduce(0) { $0 + $1.quantity })):\n"
                for card in energy {
                    output += formatLeagueCard(card, nameBySetKey: setNameLookup, cardsByMasterId: cardsByMasterId) + "\n"
                }
            }
        }
        
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func buildSetNameLookup(from sets: [TCGSet]) -> [String: String] {
        var out: [String: String] = [:]
        for set in sets {
            let name = set.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let candidates = [
                set.setCode,
                set.setKey,
                set.code,
                set.tcgdexId
            ]
            for candidate in candidates {
                let key = (candidate ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if !key.isEmpty { out[key] = name }
            }
        }
        return out
    }

    private func formatLeagueCard(_ card: DeckCard, nameBySetKey: [String: String], cardsByMasterId: [String: Card]) -> String {
        let setKey = card.setKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let setName = nameBySetKey[setKey] ?? (card.setKey.isEmpty ? "Unknown Set" : card.setKey.uppercased())
        let localId = normalizedExportLocalId(resolvedLocalId(for: card, cardsByMasterId: cardsByMasterId))
        let numberToken = localId.isEmpty ? "" : " \(localId)"
        
        return "\(card.quantity) \(card.cardName) - \(setName)\(numberToken)"
    }
    
    private func formatCard(_ card: DeckCard, abbreviationBySetKey: [String: String], cardsByMasterId: [String: Card]) -> String {
        let setKey = card.setKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let setToken = abbreviationBySetKey[setKey]
        let localId = normalizedExportLocalId(resolvedLocalId(for: card, cardsByMasterId: cardsByMasterId))
        let exportName = normalizedPTCGLName(for: card)
        
        // TCG Live export/import expects: "<qty> <name> <setAbbreviation> <localId>".
        // Legacy deck rows may not have `localId`; derive from known id formats when possible.
        let numberToken = localId.isEmpty ? "0" : localId
        let abbreviationToken = (setToken?.isEmpty == false) ? setToken! : "UNK"
        return "\(card.quantity) \(exportName) \(abbreviationToken) \(numberToken)"
    }

    private func normalizedExportLocalId(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let stripped = trimmed.replacingOccurrences(of: "^0+", with: "", options: .regularExpression)
        return stripped.isEmpty ? "0" : stripped
    }

    private func buildSetAbbreviationLookup(from sets: [TCGSet]) -> [String: String] {
        var out: [String: String] = [:]
        for set in sets {
            let abbreviation = (set.setAbbreviation ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let code = (set.code ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            // Prefer the dedicated setAbbreviation field; fallback to set metadata code.
            let token = !abbreviation.isEmpty ? abbreviation : code
            guard !token.isEmpty else { continue }
            let candidates = [
                set.setCode,
                set.setKey,
                set.code,
                set.tcgdexId
            ]
            for candidate in candidates {
                let key = (candidate ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if !key.isEmpty { out[key] = token }
            }
        }
        return out
    }

    private func resolvedLocalId(for card: DeckCard, cardsByMasterId: [String: Card]) -> String {
        let persisted = (card.localId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !persisted.isEmpty { return persisted }

        if let lookup = cardsByMasterId[card.cardID] {
            let fromLookup = (lookup.localId ?? lookup.cardNumber).trimmingCharacters(in: .whitespacesAndNewlines)
            if !fromLookup.isEmpty { return fromLookup }
        }

        // Common Pokemon master ids are shaped like "<set>-<localId>".
        if let tail = card.cardID.split(separator: "-").last {
            let candidate = String(tail).trimmingCharacters(in: .whitespacesAndNewlines)
            if !candidate.isEmpty, candidate != card.cardID { return candidate }
        }

        return ""
    }

    private func normalizedPTCGLName(for card: DeckCard) -> String {
        guard card.isEnergyCard else { return card.cardName }
        guard card.isBasicEnergy else { return card.cardName }

        if let type = card.elementTypes?.first, let symbol = ptcglEnergySymbol(for: type) {
            return "Basic {\(symbol)} Energy"
        }

        let lower = card.cardName.lowercased()
        let fallbackTypes = ["grass", "fire", "water", "lightning", "psychic", "fighting", "darkness", "metal", "dragon", "fairy", "colorless"]
        if let matched = fallbackTypes.first(where: { lower.contains($0) }),
           let symbol = ptcglEnergySymbol(for: matched) {
            return "Basic {\(symbol)} Energy"
        }

        return card.cardName
    }

    private func ptcglEnergySymbol(for type: String) -> String? {
        switch type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "grass": return "G"
        case "fire": return "R"
        case "water": return "W"
        case "lightning": return "L"
        case "psychic": return "P"
        case "fighting": return "F"
        case "darkness": return "D"
        case "metal": return "M"
        case "dragon": return "N"
        case "fairy": return "Y"
        case "colorless": return "C"
        default: return nil
        }
    }
}
