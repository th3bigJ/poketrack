import Foundation

/// Maps UI printing strings to Scrydex variant keys inside pricing JSON.
enum CardPrinting: String, CaseIterable, Codable {
    case standard = "Standard"
    case holo = "Holo"
    case reverseHolo = "Reverse Holo"
    case firstEdition = "First Edition"
    case firstEditionHolo = "First Edition Holo"
    case unlimited = "Unlimited"
    case unlimitedHolo = "Unlimited Holo"
    case shadowless = "Shadowless"
    case pokemonDayStamp = "Pokemon Day Stamp"
    case pokemonCenterStamp = "Pokémon Center Stamp"
    case staffStamp = "Staff Stamp"
}
