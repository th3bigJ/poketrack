import Foundation

/// Hosted at `{catalogPrefix}/variants.json` on R2. Drives which printing variants count toward
/// master / grand master set lists. Championship variants are excluded from all completion grids.
struct VariantsCatalog: Codable, Sendable, Equatable {
    let masterSet: [String]
    let grandMasterSet: [String]
    let championship: [String]

    private enum CodingKeys: String, CodingKey {
        case masterSet
        case grandMasterSet
        case championship
    }

    static let fallback = VariantsCatalog(
        masterSet: ["normal", "holofoil", "reverseHolofoil"],
        grandMasterSet: [],
        championship: []
    )

    func normalizedMasterSet() -> Set<String> {
        Set(masterSet.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty })
    }

    func normalizedGrandMasterSet() -> Set<String> {
        Set(grandMasterSet.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty })
    }

    func normalizedChampionshipSet() -> Set<String> {
        Set(championship.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty })
    }
}
