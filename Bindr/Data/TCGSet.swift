import Foundation

/// Set row from catalog `sets.json` on R2.
///
/// `setKey` is the stable stem for `cards/{setKey}.json` and pricing paths; `id` is an internal id string.
/// Falls back to `tcgdexId`, then `code`, then `id` when `setKey` is absent.
struct TCGSet: Codable, Identifiable, Hashable, Sendable {
    /// Stable identity for navigation and caching: same as `setCode` (file stem).
    var id: String { setCode }

    let internalId: String
    let name: String
    /// File stem for card JSON and pricing (e.g. `me3`).
    let setKey: String?
    let code: String?
    let tcgdexId: String?
    let releaseDate: String?
    let cardCountTotal: Int?
    let cardCountOfficial: Int?
    let seriesName: String?
    let logoSrc: String
    let symbolSrc: String?
    let scannerEnExpansionNumber: String?

    enum CodingKeys: String, CodingKey {
        case internalId = "id"
        case name, setKey, code, tcgdexId, releaseDate
        case cardCountTotal, cardCountOfficial, seriesName
        case logoSrc, symbolSrc
        case scannerEnExpansionNumber
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        internalId = try c.decode(String.self, forKey: .internalId)
        name = try c.decode(String.self, forKey: .name)
        setKey = try c.decodeIfPresent(String.self, forKey: .setKey)
        code = try c.decodeIfPresent(String.self, forKey: .code)
        tcgdexId = try c.decodeIfPresent(String.self, forKey: .tcgdexId)
        releaseDate = try c.decodeIfPresent(String.self, forKey: .releaseDate)
        cardCountTotal = try c.decodeIfPresent(Int.self, forKey: .cardCountTotal)
        cardCountOfficial = try c.decodeIfPresent(Int.self, forKey: .cardCountOfficial)
        seriesName = try c.decodeIfPresent(String.self, forKey: .seriesName)
        logoSrc = try c.decode(String.self, forKey: .logoSrc)
        symbolSrc = try c.decodeIfPresent(String.self, forKey: .symbolSrc)
        scannerEnExpansionNumber = try c.decodeIfPresent(String.self, forKey: .scannerEnExpansionNumber)
    }

    /// Memberwise (e.g. One Piece catalog rows mapped into the shared ``TCGSet`` type).
    init(
        internalId: String,
        name: String,
        setKey: String?,
        code: String?,
        tcgdexId: String?,
        releaseDate: String?,
        cardCountTotal: Int?,
        cardCountOfficial: Int?,
        seriesName: String?,
        logoSrc: String,
        symbolSrc: String?,
        scannerEnExpansionNumber: String? = nil
    ) {
        self.internalId = internalId
        self.name = name
        self.setKey = setKey
        self.code = code
        self.tcgdexId = tcgdexId
        self.releaseDate = releaseDate
        self.cardCountTotal = cardCountTotal
        self.cardCountOfficial = cardCountOfficial
        self.seriesName = seriesName
        self.logoSrc = logoSrc
        self.symbolSrc = symbolSrc
        self.scannerEnExpansionNumber = scannerEnExpansionNumber
    }

    /// Primary key used for bundled JSON filenames and R2 paths (`cards/{setCode}.json`, pricing stems, SQLite rows).
    var setCode: String {
        if let k = setKey, !k.isEmpty { return k }
        if let c = tcgdexId, !c.isEmpty { return c }
        if let c = code, !c.isEmpty { return c }
        return internalId
    }
}
