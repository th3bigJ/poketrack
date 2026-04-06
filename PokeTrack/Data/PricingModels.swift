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

// MARK: - Price History

/// One data point in a price history series.
struct PriceDataPoint: Identifiable {
    let id: String   // the label string (date / week / month)
    let label: String
    let price: Double
}

/// Decoded from `pricing/price-history/{setCode}.json`.
/// Structure: `{ cardKey: { variant: { grade: { daily, weekly, monthly } } } }`
struct CardPriceHistory {
    struct Series {
        let daily: [PriceDataPoint]
        let weekly: [PriceDataPoint]
        let monthly: [PriceDataPoint]
    }
    /// Keyed by "variant/grade" e.g. "holofoil/raw", "holofoil/psa10"
    let series: [String: Series]

    static func parse(from variantMap: [String: Any]) -> CardPriceHistory? {
        func parseSeries(_ d: [String: Any]) -> Series {
            func points(_ key: String) -> [PriceDataPoint] {
                guard let arr = d[key] as? [[Any]] else { return [] }
                return arr.compactMap { pair -> PriceDataPoint? in
                    guard pair.count >= 2,
                          let label = pair[0] as? String,
                          let price = (pair[1] as? Double) ?? (pair[1] as? Int).map(Double.init)
                    else { return nil }
                    return PriceDataPoint(id: label, label: label, price: price)
                }
            }
            return Series(daily: points("daily"), weekly: points("weekly"), monthly: points("monthly"))
        }

        var series: [String: Series] = [:]
        for (variant, variantValue) in variantMap {
            guard let gradeMap = variantValue as? [String: Any] else { continue }
            for (grade, gradeValue) in gradeMap {
                guard let seriesDict = gradeValue as? [String: Any] else { continue }
                series["\(variant)/\(grade)"] = parseSeries(seriesDict)
            }
        }
        guard !series.isEmpty else { return nil }
        return CardPriceHistory(series: series)
    }
}


// MARK: - Price Trends

/// Decoded from `pricing/price-trends/{setCode}.json` for a single card entry.
/// Structure: `{ variant, grade, current, daily: { changePct }, weekly: { changePct }, monthly: { changePct } }`
struct CardPriceTrends {
    let variant: String
    let grade: String
    let change1d: Double?
    let change7d: Double?
    let change30d: Double?

    static func parse(from d: [String: Any]) -> CardPriceTrends? {
        let variant = d["variant"] as? String ?? ""
        let grade = d["grade"] as? String ?? "raw"
        func changePct(_ key: String) -> Double? {
            (d[key] as? [String: Any])?["changePct"] as? Double
        }
        return CardPriceTrends(
            variant: variant,
            grade: grade,
            change1d: changePct("daily"),
            change7d: changePct("weekly"),
            change30d: changePct("monthly")
        )
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
