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
        
        // Regex for: (Quantity) (Name) (SetCode) (Number)
        // e.g. "1 Boss's Orders BRS 132"
        // Note: Name can have spaces. SetCode is usually uppercase alphanumeric. Number can have letters (e.g. TG01).
        let regex = try? NSRegularExpression(pattern: #"^(\d+)\s+(.+)\s+([A-Z0-9]{2,})\s+([A-Z0-9/]+)$"#, options: [])
        
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
                let energyRegex = try? NSRegularExpression(pattern: #"^(\d+)\s+(.+ Energy)(?:\s+([A-Z0-9]{2,})\s+([A-Z0-9/]+))?$"#, options: [])
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
    func exportToPTCGL(deck: Deck, sets: [TCGSet]) -> String {
        var output = ""
        let cards = deck.cardList
        
        // Group by category for cleaner output
        let pokemon = cards.filter { ($0.catalogCategory ?? "").lowercased() == "pokémon" }
        let trainers = cards.filter { ($0.catalogCategory ?? "").lowercased() == "trainer" }
        let energy = cards.filter { ($0.catalogCategory ?? "").lowercased() == "energy" }
        
        if !pokemon.isEmpty {
            output += "Pokémon: \(pokemon.reduce(0) { $0 + $1.quantity })\n"
            for card in pokemon {
                output += formatCard(card, sets: sets) + "\n"
            }
            output += "\n"
        }
        
        if !trainers.isEmpty {
            output += "Trainer: \(trainers.reduce(0) { $0 + $1.quantity })\n"
            for card in trainers {
                output += formatCard(card, sets: sets) + "\n"
            }
            output += "\n"
        }
        
        if !energy.isEmpty {
            output += "Energy: \(energy.reduce(0) { $0 + $1.quantity })\n"
            for card in energy {
                output += formatCard(card, sets: sets) + "\n"
            }
        }
        
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func formatCard(_ card: DeckCard, sets: [TCGSet]) -> String {
        let set = sets.first(where: { $0.setCode == card.setKey })
        let code = set?.code?.uppercased() ?? card.setKey.uppercased()
        
        // PTCGL typically wants the number without leading zeros unless it's a specific set requirement.
        // But our cardNumber should already be the correct printed number.
        return "\(card.quantity) \(card.cardName) \(code) \(card.cardID)"
    }
}
