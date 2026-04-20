import Foundation

/// Trading-card franchise shown in browse, search, and account settings.
enum TCGBrand: String, CaseIterable, Codable, Identifiable, Sendable {
    case pokemon
    case onePiece

    var id: String { rawValue }

    /// Matches `id` in the hosted `brands.json` (see ``BrandsManifestService``).
    var manifestBrandId: String {
        switch self {
        case .pokemon: return "pokemon"
        case .onePiece: return "onepiece"
        }
    }

    var displayTitle: String {
        switch self {
        case .pokemon: return "Pok\u{00E9}mon"
        case .onePiece: return "ONE PIECE"
        }
    }

    /// Stable ordering when the manifest is unavailable (fallback only).
    var menuOrder: Int {
        switch self {
        case .pokemon: return 0
        case .onePiece: return 1
        }
    }

    /// Browse filter menu: maps Pok\u{00E9}mon "energy" to OP **colors** (same underlying `elementTypes` field on ``Card``).
    var energyFilterMenuTitle: String {
        switch self {
        case .pokemon: return "Energy"
        case .onePiece: return "Color"
        }
    }

    /// Catalog / wishlist / collection: ONE PIECE uses Scrydex-style `priceKey` ids with `::`.
    static func inferredFromMasterCardId(_ masterCardId: String) -> TCGBrand {
        if masterCardId.contains("::") { return .onePiece }
        return .pokemon
    }

    static func fromManifestBrandId(_ id: String) -> TCGBrand? {
        switch id.lowercased() {
        case "pokemon": return .pokemon
        case "onepiece": return .onePiece
        default: return nil
        }
    }
}
