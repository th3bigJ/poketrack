import Foundation

typealias SetPricingMap = [String: CardPricingEntry]

struct CardPricingEntry: Codable, Hashable {
    let scrydex: [String: ScrydexVariantPricing]?
    let tcgplayer: JSONValue?
    let cardmarket: JSONValue?
}

struct ScrydexVariantPricing: Codable, Hashable {
    let raw: Double?
    let psa10: Double?
    let ace10: Double?
    /// Alternate field names seen in some Scrydex-style blobs for the ungraded line.
    let market: Double?
    let avg: Double?

    enum CodingKeys: String, CodingKey {
        case raw, psa10, ace10, market, avg
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        raw = Self.decodeNumber(c, forKey: .raw)
        psa10 = Self.decodeNumber(c, forKey: .psa10)
        ace10 = Self.decodeNumber(c, forKey: .ace10)
        market = Self.decodeNumber(c, forKey: .market)
        avg = Self.decodeNumber(c, forKey: .avg)
    }

    /// JSON sometimes encodes prices as strings; tolerate both.
    private static func decodeNumber(_ c: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> Double? {
        if let d = try? c.decodeIfPresent(Double.self, forKey: key) { return d }
        if let i = try? c.decodeIfPresent(Int.self, forKey: key) { return Double(i) }
        if let s = try? c.decodeIfPresent(String.self, forKey: key) {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if let d = Double(t) { return d }
        }
        return nil
    }

    /// Best-effort ungraded market USD; falls through to graded (`psa10` / `ace10`) only when ungraded fields are absent.
    func marketEstimateUSD() -> Double? {
        raw ?? market ?? avg ?? psa10 ?? ace10
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(raw, forKey: .raw)
        try c.encodeIfPresent(psa10, forKey: .psa10)
        try c.encodeIfPresent(ace10, forKey: .ace10)
        try c.encodeIfPresent(market, forKey: .market)
        try c.encodeIfPresent(avg, forKey: .avg)
    }
}

/// Minimal dynamic JSON for fields we do not model strongly.
enum JSONValue: Codable, Hashable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? c.decode(Double.self) {
            self = .number(n)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let a = try? c.decode([JSONValue].self) {
            self = .array(a)
        } else if let o = try? c.decode([String: JSONValue].self) {
            self = .object(o)
        } else {
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let o): try c.encode(o)
        case .array(let a): try c.encode(a)
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        case .null: try c.encodeNil()
        }
    }
}
