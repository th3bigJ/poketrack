import Foundation

struct SealedProductImage: Codable, Hashable, Sendable {
    let r2Key: String?
    let publicURL: String?

    enum CodingKeys: String, CodingKey {
        case r2Key = "r2_key"
        case publicURL = "public_url"
    }

    /// Prefer ``r2Key`` on the configured CDN. ``publicURL`` in the catalog JSON is often a stale
    /// absolute mirror (e.g. old R2 `.dev` hosts) after the Cloudflare custom domain changes.
    var resolvedURL: URL? {
        if let r2Key {
            let key = r2Key.trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty {
                return AppConfiguration.imageURL(relativePath: key)
            }
        }

        guard let publicURL,
              let url = URL(string: publicURL.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return nil }

        if url.host == AppConfiguration.r2BaseURL.host {
            return url
        }

        // Legacy absolute URL on another host — rebuild from its path on the current CDN.
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !path.isEmpty else { return nil }
        return AppConfiguration.imageURL(relativePath: path)
    }
}

struct SealedProduct: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let tcg: String?
    let language: String?
    let type: String?
    let releaseDateRaw: String?
    let year: Int?
    let series: String?
    let setID: Int?
    let setName: String?
    let image: SealedProductImage?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case tcg
        case language
        case type
        case releaseDateRaw = "release_date"
        case year
        case series
        case setID = "set_id"
        case setName = "set_name"
        case image
    }

    static func collectionCardID(productID: Int) -> String {
        "sealed:pokemon:\(productID)"
    }

    static func collectionCardID(for product: SealedProduct) -> String {
        collectionCardID(productID: product.id)
    }

    static func parseCollectionProductID(_ cardID: String) -> Int? {
        guard cardID.hasPrefix("sealed:pokemon:") else { return nil }
        let suffix = String(cardID.dropFirst("sealed:pokemon:".count))
        return Int(suffix)
    }

    var collectionCardID: String {
        Self.collectionCardID(for: self)
    }

    var imageURL: URL? {
        image?.resolvedURL
    }

    var releaseDate: Date? {
        guard let raw = releaseDateRaw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        return Self.rfc1123DateFormatter.date(from: raw)
    }

    var typeDisplayName: String {
        guard let type else { return "Unknown" }
        let raw = type.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "Unknown" }
        let lower = raw.lowercased()
        return lower.replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    var searchBlob: String {
        [
            name,
            series ?? "",
            setName ?? "",
            type ?? "",
            language ?? "",
            String(year ?? 0),
            String(id)
        ].joined(separator: " ").lowercased()
    }

    private static let rfc1123DateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }()
}

struct SealedProductsPayload: Decodable {
    let scrapedAt: String?
    let count: Int?
    let products: [SealedProduct]
}

struct SealedProductHistorySeries: Decodable, Sendable {
    let daily: [PriceDataPoint]
    let weekly: [PriceDataPoint]
    let monthly: [PriceDataPoint]

    init(daily: [PriceDataPoint], weekly: [PriceDataPoint], monthly: [PriceDataPoint]) {
        self.daily = daily
        self.weekly = weekly
        self.monthly = monthly
    }

    private enum CodingKeys: String, CodingKey {
        case daily
        case weekly
        case monthly
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        daily = try Self.decodeSeries(container: container, key: .daily)
        weekly = try Self.decodeSeries(container: container, key: .weekly)
        monthly = try Self.decodeSeries(container: container, key: .monthly)
    }

    private static func decodeSeries(
        container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) throws -> [PriceDataPoint] {
        guard let raw = try container.decodeIfPresent([[JSONScalar]].self, forKey: key) else {
            return []
        }
        return raw.compactMap { tuple in
            guard tuple.count >= 2,
                  let label = tuple[0].stringValue,
                  let price = tuple[1].doubleValue else {
                return nil
            }
            return PriceDataPoint(id: label, label: label, price: price)
        }
    }
}

private enum JSONScalar: Decodable {
    case string(String)
    case number(Double)
    case int(Int)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode(Double.self) { self = .number(v); return }
        if let v = try? c.decode(Int.self) { self = .int(v); return }
        if let v = try? c.decode(Bool.self) { self = .bool(v); return }
        self = .null
    }

    var stringValue: String? {
        switch self {
        case .string(let value): return value
        case .number(let value): return String(value)
        case .int(let value): return String(value)
        case .bool(let value): return String(value)
        case .null: return nil
        }
    }

    var doubleValue: Double? {
        switch self {
        case .string(let value): return Double(value)
        case .number(let value): return value
        case .int(let value): return Double(value)
        case .bool: return nil
        case .null: return nil
        }
    }
}
