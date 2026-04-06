import Foundation

struct TCGSet: Codable, Identifiable, Hashable, Sendable {
    var id: String { tcgdexId ?? internalId }

    let internalId: String
    let name: String
    let slug: String
    let code: String?
    let tcgdexId: String?
    let releaseDate: String?
    let isActive: Bool
    let cardCountTotal: Int?
    let cardCountOfficial: Int?
    let seriesName: String?
    let seriesSlug: String?
    let logoSrc: String
    let symbolSrc: String?

    enum CodingKeys: String, CodingKey {
        case internalId = "id"
        case name, slug, code, tcgdexId, releaseDate, isActive
        case cardCountTotal, cardCountOfficial, seriesName, seriesSlug
        case logoSrc, symbolSrc
    }

    /// Primary key used for bundled JSON filenames and R2 paths.
    var setCode: String {
        if let c = tcgdexId, !c.isEmpty { return c }
        if let c = code, !c.isEmpty { return c }
        return internalId
    }
}
