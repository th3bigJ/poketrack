import Foundation

/// Maps UI printing strings to Scrydex variant keys inside pricing JSON.
enum PrintingVariant {
    static func scrydexKey(forPrinting printing: String) -> String {
        switch printing {
        case "Standard": return "normal"
        case "Holo": return "holofoil"
        case "Reverse Holo": return "reverseHolofoil"
        case "First Edition": return "firstEdition"
        case "First Edition Holo": return "firstEditionHolofoil"
        case "Unlimited": return "unlimited"
        case "Unlimited Holo": return "unlimitedHolofoil"
        case "Shadowless": return "shadowless"
        case "Pokemon Day Stamp": return "pokemonDayStamp"
        case "Pokémon Center Stamp": return "pokemonCenterStamp"
        case "Staff Stamp": return "staffStamp"
        default: return "normal"
        }
    }
}
