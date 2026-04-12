import Foundation

/// Maps UI printing strings to Scrydex variant keys inside pricing JSON.
enum PrintingVariant {
    static func scrydexKey(forPrinting printing: String) -> String {
        guard let p = CardPrinting(rawValue: printing) else { return "normal" }
        switch p {
        case .standard: return "normal"
        case .holo: return "holofoil"
        case .reverseHolo: return "reverseHolofoil"
        case .firstEdition: return "firstEdition"
        case .firstEditionHolo: return "firstEditionHolofoil"
        case .unlimited: return "unlimited"
        case .unlimitedHolo: return "unlimitedHolofoil"
        case .shadowless: return "shadowless"
        case .pokemonDayStamp: return "pokemonDayStamp"
        case .pokemonCenterStamp: return "pokemonCenterStamp"
        case .staffStamp: return "staffStamp"
        }
    }
}
