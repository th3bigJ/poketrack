import Foundation

/// Trading-card franchise shown in browse, search, and account settings.
enum TCGBrand: String, CaseIterable, Codable, Identifiable, Sendable {
    case pokemon
    case onePiece
    case lorcana

    var id: String { rawValue }

    /// Matches `id` in the hosted `brands.json` (see ``BrandsManifestService``).
    var manifestBrandId: String {
        switch self {
        case .pokemon: return "pokemon"
        case .onePiece: return "onepiece"
        case .lorcana: return "lorcana"
        }
    }

    var displayTitle: String {
        switch self {
        case .pokemon: return "Pokémon"
        case .onePiece: return "ONE PIECE"
        case .lorcana: return "Lorcana"
        }
    }

    /// Stable ordering when the manifest is unavailable (fallback only).
    var menuOrder: Int {
        switch self {
        case .pokemon: return 0
        case .onePiece: return 1
        case .lorcana: return 2
        }
    }

    /// Browse filter menu: maps Pokémon “energy” to OP **colors** / Lorcana **ink** (same underlying `elementTypes` field on ``Card``).
    var energyFilterMenuTitle: String {
        switch self {
        case .pokemon: return "Energy"
        case .onePiece: return "Color"
        case .lorcana: return "Ink"
        }
    }

    /// Catalog / wishlist / collection: Lorcana and ONE PIECE use Scrydex-style `priceKey` ids with `::`.
    /// Lorcana rows are stored with a `lorcana::` prefix so they never collide with ONE PIECE keys.
    static func inferredFromMasterCardId(_ masterCardId: String) -> TCGBrand {
        if masterCardId.hasPrefix(Self.lorcanaMasterIdPrefix) { return .lorcana }
        if masterCardId.contains("::") { return .onePiece }
        return .pokemon
    }

    /// Prefix for `masterCardId` in SQLite for Disney Lorcana (disambiguates from ONE PIECE `::` keys).
    static let lorcanaMasterIdPrefix = "lorcana::"

    static func fromManifestBrandId(_ id: String) -> TCGBrand? {
        switch id.lowercased() {
        case "pokemon": return .pokemon
        case "onepiece": return .onePiece
        case "lorcana": return .lorcana
        default: return nil
        }
    }
}
