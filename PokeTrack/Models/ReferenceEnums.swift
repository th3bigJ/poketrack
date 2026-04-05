import Foundation

enum CardCondition: String, CaseIterable, Codable {
    case nearMint = "near-mint"
    case lightlyPlayed = "lightly-played"
    case moderatelyPlayed = "moderately-played"
    case heavilyPlayed = "heavily-played"
    case damaged = "damaged"
    case graded = "graded-card"

    var displayName: String {
        switch self {
        case .nearMint: return "Near Mint"
        case .lightlyPlayed: return "Lightly Played"
        case .moderatelyPlayed: return "Moderately Played"
        case .heavilyPlayed: return "Heavily Played"
        case .damaged: return "Damaged"
        case .graded: return "Graded"
        }
    }
}

enum PurchaseType: String, CaseIterable, Codable {
    case bought = "bought"
    case traded = "traded"
    case packed = "packed"
}
