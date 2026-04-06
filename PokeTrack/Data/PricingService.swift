import Foundation
import Observation

@Observable
@MainActor
final class PricingService {
    private(set) var usdToGbp: Double = 0.79
    private(set) var lastFXError: String?

    private var pricingCache: [String: (map: SetPricingMap, expiry: Date)] = [:]

    private let session: URLSession
    private let fileManager: FileManager
    private let cacheTTL: TimeInterval = 24 * 60 * 60

    init(session: URLSession = .shared, fileManager: FileManager = .default) {
        self.session = session
        self.fileManager = fileManager
    }

    private var cacheDirectory: URL {
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("pricing", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func refreshFXRate() async {
        lastFXError = nil
        let url = URL(string: "https://api.frankfurter.app/latest?from=USD&to=GBP")!
        do {
            let (data, _) = try await session.data(from: url)
            let decoded = try JSONDecoder().decode(FrankfurterResponse.self, from: data)
            if let gbp = decoded.rates["GBP"] {
                usdToGbp = gbp
            }
        } catch {
            lastFXError = error.localizedDescription
            usdToGbp = 0.79
        }
    }

    func pricing(for card: Card) async -> CardPricingEntry? {
        let map = await loadPricingMap(setCode: card.setCode)
        return Self.resolvePricingEntry(in: map, for: card)
    }

    /// Keys to try against `tcg/pricing/card-pricing/{set}.json` (see `AppConfiguration.r2CardPricingSetJSONURL`). Some sets key rows by `externalId`; most use `tcgdex_id` — **both** are tried when present.
    private static func pricingLookupKeys(for card: Card) -> [String] {
        var keys: [String] = []
        func append(_ s: String) {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty, !keys.contains(t) { keys.append(t) }
        }
        if let e = card.externalId { append(e) }
        if let t = card.tcgdex_id { append(t) }
        if let local = card.localId, !local.isEmpty {
            let sc = card.setCode.trimmingCharacters(in: .whitespacesAndNewlines)
            append("\(sc)-\(local)")
            if let n = Int(local) {
                append("\(sc)-\(n)")
                append(String(format: "%@-%03d", sc, n))
            }
        }
        append(card.masterCardId)
        return keys
    }

    /// Exact key, case-insensitive, then canonical (`sm4-030`/`sm4-30`, `me3-124`/`me03-124`).
    private static func resolvePricingEntry(in map: SetPricingMap, for card: Card) -> CardPricingEntry? {
        let candidates = pricingLookupKeys(for: card)
        guard !candidates.isEmpty else { return nil }

        for k in candidates {
            if let entry = map[k] { return entry }
        }
        for k in candidates {
            let target = k.lowercased()
            if let found = map.first(where: { $0.key.lowercased() == target })?.value {
                return found
            }
        }
        let canonSet = Set(candidates.map { canonicalCardPricingKey($0) })
        for (mapKey, entry) in map {
            if canonSet.contains(canonicalCardPricingKey(mapKey)) {
                return entry
            }
        }
        return nil
    }

    /// Unifies tcgdx-style keys: trailing card # (`030`→`30`) and set prefix (`me03`→`me3`) so catalog ↔ pricing exports match.
    private static func canonicalCardPricingKey(_ id: String) -> String {
        let t = id.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard let idx = t.lastIndex(of: "-") else { return t }
        let left = String(t[..<idx])
        let right = String(t[t.index(after: idx)...])
        guard right.allSatisfy({ $0.isNumber }), let num = Int(right) else { return t }
        let leftNorm = normalizeTcgdxSetPrefix(left)
        return "\(leftNorm)-\(num)"
    }

    /// Collapses `me03`→`me3`, keeps `sm4`, `base1`, etc.
    private static func normalizeTcgdxSetPrefix(_ s: String) -> String {
        let lower = s.lowercased()
        guard let regex = try? NSRegularExpression(pattern: #"^([a-z]+)(\d+)$"#, options: []),
              let m = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
              m.numberOfRanges == 3,
              let r1 = Range(m.range(at: 1), in: lower),
              let r2 = Range(m.range(at: 2), in: lower) else {
            return lower
        }
        let letters = String(lower[r1])
        let digits = String(lower[r2])
        guard let n = Int(digits) else { return lower }
        return "\(letters)\(n)"
    }

    /// Tries `me03.json` and `me3.json` (common mismatch between `setCode` and pricing pipeline names).
    private static func pricingFileStemVariants(for setCode: String) -> [String] {
        let s = setCode.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        var stems: [String] = []
        func add(_ x: String) {
            if !stems.contains(x) { stems.append(x) }
        }
        add(s)
        if let regex = try? NSRegularExpression(pattern: #"^([a-z]+)0+(\d+)$"#, options: []),
           let m = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
           m.numberOfRanges == 3,
           let r1 = Range(m.range(at: 1), in: s),
           let r2 = Range(m.range(at: 2), in: s) {
            let letters = String(s[r1])
            let digits = String(s[r2])
            if let n = Int(digits) {
                add("\(letters)\(n)")
            }
        }
        return stems
    }

    func gbpPrice(for card: Card, printing: String) async -> Double? {
        guard let entry = await pricing(for: card) else { return nil }
        guard let scrydex = entry.scrydex, !scrydex.isEmpty else { return nil }
        guard let usd = scrydexUSD(from: scrydex, printing: printing) else { return nil }
        return usd * usdToGbp
    }

    /// Picks a Scrydex USD price using `marketEstimateUSD()` (raw / market / avg, then psa10 / ace10). Tries common variant keys, then any key deterministically.
    private func scrydexUSD(from scrydex: [String: ScrydexVariantPricing], printing: String) -> Double? {
        let preferred = PrintingVariant.scrydexKey(forPrinting: printing)
        var fallbackKeys = [
            preferred,
            "normal",
            "holofoil",
            "reverseHolofoil",
            "reverse_holofoil",
            "pokeballReverseHolofoil",
            "cosmosHolofoil",
            "unlimited",
            "unlimitedHolofoil",
            "firstEdition",
            "firstEditionHolofoil",
            "shadowless",
            "amazingRare",
            "radiantHolofoil",
        ]
        // De-dupe while keeping order (e.g. preferred may repeat `normal`).
        var seen = Set<String>()
        fallbackKeys = fallbackKeys.filter { seen.insert($0).inserted }

        for key in fallbackKeys {
            if let usd = scrydex[key]?.marketEstimateUSD() {
                return usd
            }
        }
        for key in scrydex.keys.sorted() {
            if let usd = scrydex[key]?.marketEstimateUSD() {
                return usd
            }
        }
        return nil
    }

    private func loadPricingMap(setCode: String) async -> SetPricingMap {
        let key = setCode.lowercased()
        if let hit = pricingCache[key], hit.expiry > Date() {
            return hit.map
        }

        try? CatalogStore.shared.open()
        if let blob = CatalogStore.shared.fetchPricingData(setCode: key),
           let map = Self.decodePricingMap(from: blob) {
            pricingCache[key] = (map, Date().addingTimeInterval(cacheTTL))
            return map
        }

        if let disk = loadDiskCache(setCode: key) {
            pricingCache[key] = (disk, Date().addingTimeInterval(cacheTTL))
            return disk
        }

        let base = AppConfiguration.r2BaseURL
        guard base.host != "invalid.local" else { return [:] }

        for stem in Self.pricingFileStemVariants(for: key) {
            let url = AppConfiguration.r2CardPricingSetJSONURL(setCodeStem: stem)
            if let (map, data) = await fetchPricingMapAndDataIfOK(from: url) {
                pricingCache[key] = (map, Date().addingTimeInterval(cacheTTL))
                saveDiskCache(setCode: key, data: data)
                return map
            }
        }
        return [:]
    }

    /// Only decode on HTTP 2xx so 404 HTML pages are not mistaken for JSON.
    private func fetchPricingMapAndDataIfOK(from url: URL) async -> (SetPricingMap, Data)? {
        do {
            let (data, resp) = try await session.data(from: url)
            guard let http = resp as? HTTPURLResponse else { return nil }
            guard (200...299).contains(http.statusCode), !data.isEmpty else { return nil }
            guard let map = Self.decodePricingMap(from: data) else { return nil }
            return (map, data)
        } catch {
            return nil
        }
    }

    /// Strict decode first; if the file has one bad card object, fall back to per-key decode so the rest still load.
    private static func decodePricingMap(from data: Data) -> SetPricingMap? {
        if let map = try? JSONDecoder().decode(SetPricingMap.self, from: data) {
            return map
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var out: SetPricingMap = [:]
        out.reserveCapacity(obj.count)
        for (key, value) in obj {
            guard JSONSerialization.isValidJSONObject(value) else { continue }
            guard let subData = try? JSONSerialization.data(withJSONObject: value) else { continue }
            if let entry = try? JSONDecoder().decode(CardPricingEntry.self, from: subData) {
                out[key] = entry
            }
        }
        return out.isEmpty ? nil : out
    }

    private func loadDiskCache(setCode: String) -> SetPricingMap? {
        let url = cacheDirectory.appendingPathComponent("\(setCode).json")
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        guard let attrs = try? fileManager.attributesOfItem(atPath: url.path),
              let mod = attrs[.modificationDate] as? Date,
              Date().timeIntervalSince(mod) < cacheTTL else {
            return nil
        }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return Self.decodePricingMap(from: data)
    }

    private func saveDiskCache(setCode: String, data: Data) {
        let url = cacheDirectory.appendingPathComponent("\(setCode).json")
        try? data.write(to: url, options: .atomic)
    }
}

private struct FrankfurterResponse: Decodable {
    let rates: [String: Double]
}
