import Foundation

/// Trading-card franchise shown in browse, search, and account settings.
enum TCGBrand: String, CaseIterable, Codable, Identifiable, Sendable {
    case pokemon
    case onePiece

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .pokemon: return "Pokémon"
        case .onePiece: return "ONE PIECE"
        }
    }

    /// Stable ordering in carousels and pickers.
    var menuOrder: Int {
        switch self {
        case .pokemon: return 0
        case .onePiece: return 1
        }
    }

    /// Browse filter menu: maps Pokémon “energy” to OP **colors** (same underlying `elementTypes` field on ``Card``).
    var energyFilterMenuTitle: String {
        switch self {
        case .pokemon: return "Energy"
        case .onePiece: return "Color"
        }
    }
}
