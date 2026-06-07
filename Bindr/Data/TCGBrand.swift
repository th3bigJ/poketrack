import Foundation

/// The single supported TCG franchise.
enum TCGBrand: String, CaseIterable, Codable, Identifiable, Sendable {
    case pokemon

    var id: String { rawValue }

    var manifestBrandId: String { "pokemon" }

    var displayTitle: String { "Pok\u{00E9}mon" }

    var menuOrder: Int { 0 }

    var energyFilterMenuTitle: String { "Energy" }

    static func inferredFromMasterCardId(_ masterCardId: String) -> TCGBrand { .pokemon }

    static func fromManifestBrandId(_ id: String) -> TCGBrand? {
        id.lowercased() == "pokemon" ? .pokemon : nil
    }
}
