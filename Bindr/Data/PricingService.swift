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

    /// Drops in-memory per-set pricing maps after a catalog purge or before a full re-download so SQLite stays authoritative.
    func clearSetPricingMemoryCache() {
        pricingCache.removeAll(keepingCapacity: false)
        historyCache.removeAll(keepingCapacity: false)
        trendsCache.removeAll(keepingCapacity: false)
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
        let map = await loadPricingMap(for: card)
        if let entry = Self.resolvePricingEntry(in: map, for: card) {
            return entry
        }
        // `CatalogStore` / disk may hold pricing JSON from before a card was added to R2; price history is fetched
        // fresh from the network, so the chart can work while Scrydex rows are missing. Force one network reload.
        let map2 = await loadPricingMap(for: card, forceNetwork: true)
        return Self.resolvePricingEntry(in: map2, for: card)
    }

    /// Keys to try for per-set pricing / history JSON lookups.
    /// - **Pokémon market:** `externalId`, `tcgdex_id`, derived ids, `masterCardId`.
    /// - **Pokémon history / trends:** `tcgdex_id` first (dotted ids match R2), then `externalId`, locals, `masterCardId`.
    /// - **ONE PIECE (`::` price keys):** R2 JSON is keyed by Scrydex `priceKey`.
    private static func pricingLookupKeys(for card: Card, historyStyle: Bool = false) -> [String] {
        var keys: [String] = []
        func append(_ s: String) {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty, !keys.contains(t) { keys.append(t) }
        }
        let opStyle = card.masterCardId.contains("::")
        if opStyle {
            let corePriceKey = card.masterCardId
            if let pid = card.tcgplayerProductId, !pid.isEmpty { append(pid) }
            append(corePriceKey)
            append(card.masterCardId)
            if let e = card.externalId { append(e) }
        } else if historyStyle {
            if let t = card.tcgdex_id { append(t) }
            if let e = card.externalId { append(e) }
        } else {
            if let e = card.externalId { append(e) }
            if let t = card.tcgdex_id { append(t) }
        }
        if let local = card.localId, !local.isEmpty {
            let sc = card.setCode.trimmingCharacters(in: .whitespacesAndNewlines)
            append("\(sc)-\(local)")
            if let n = Int(local) {
                append("\(sc)-\(n)")
                append(String(format: "%@-%03d", sc, n))
            }
        }
        if !opStyle {
            append(card.masterCardId)
        }
        return keys
    }

    /// Exact key, case-insensitive, then unified form (`me02.5-280` ≡ `me2pt5-280`, `sm4-030` ≡ `sm4-30`, …).
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
        let unified = Set(candidates.map { unifiedPricingCardKey($0) })
        for (mapKey, entry) in map {
            if unified.contains(unifiedPricingCardKey(mapKey)) {
                return entry
            }
        }
        return nil
    }

    /// One comparable form for card ids in pricing JSON: dotted TCGdex (`me02.5-280`) and Scrydex `pt` ids (`me2pt5-280`) become the same key.
    private static func unifiedPricingCardKey(_ id: String) -> String {
        let t = id.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard let idx = t.lastIndex(of: "-") else { return t }
        let left = String(t[..<idx])
        let right = String(t[t.index(after: idx)...])
        guard right.allSatisfy({ $0.isNumber }), let num = Int(right) else { return t }
        let leftU = unifySetPortionOfPricingCardKey(left)
        return "\(leftU)-\(num)"
    }

    /// `me02.5` / `me2pt5` / `me02pt5` → `me2pt5`; `me03` → `me3`; `sm4` → `sm4`.
    private static func unifySetPortionOfPricingCardKey(_ left: String) -> String {
        let s = left.lowercased()
        if s.contains(".") {
            return dottedSetPrefixToPtCollapsed(s)
        }
        if s.contains("pt") {
            if let regex = try? NSRegularExpression(pattern: #"^([a-z]+)(\d+)pt(\d+)$"#, options: []),
               let m = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
               m.numberOfRanges == 4,
               let r1 = Range(m.range(at: 1), in: s),
               let r2 = Range(m.range(at: 2), in: s),
               let r3 = Range(m.range(at: 3), in: s) {
                let letters = String(s[r1])
                let mid = String(s[r2])
                let tail = String(s[r3])
                if let n = Int(mid) {
                    return "\(letters)\(n)pt\(tail)"
                }
            }
        }
        return normalizeTcgdxSetPrefix(s)
    }

    /// `me02.5` → `me2pt5` (collapse digits before dot, then `pt` + fractional index).
    private static func dottedSetPrefixToPtCollapsed(_ dotted: String) -> String {
        guard let dot = dotted.firstIndex(of: ".") else { return dotted }
        let a = String(dotted[..<dot])
        let b = String(dotted[dotted.index(after: dot)...])
        guard b.allSatisfy({ $0.isNumber }) else { return dotted }
        var collapsed = a
        if let range = a.range(of: #"\d+$"#, options: .regularExpression) {
            let p = String(a[..<range.lowerBound])
            let tail = String(a[range])
            if let n = Int(tail) {
                collapsed = p + String(n)
            }
        }
        return collapsed + "pt" + b
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

    /// All scrydex variant keys present for a card (used to populate the variant picker).
    func variantKeys(for card: Card) async -> [String] {
        guard let entry = await pricing(for: card) else { return [] }
        if let scrydex = entry.scrydex, !scrydex.isEmpty {
            return scrydex.keys.sorted()
        }
        // ONE PIECE: one TCGplayer product per catalog row — labels come from `pricingVariants` (catalog `variant`), not `"normal"`.
        if card.masterCardId.contains("::") {
            if let pv = card.pricingVariants, !pv.isEmpty { return pv }
            return []
        }
        if let pv = card.pricingVariants, !pv.isEmpty {
            return pv
        }
        if entry.tcgplayerMarketEstimateUSD() != nil {
            return ["normal"]
        }
        return []
    }

    /// USD market price for a specific variant key (not printing label).
    func usdPriceForVariant(for card: Card, variantKey: String) async -> Double? {
        guard let entry = await pricing(for: card) else { return nil }
        if let scrydex = entry.scrydex, !scrydex.isEmpty {
            return scrydex[variantKey]?.marketEstimateUSD()
                ?? scrydexUSD(from: scrydex, printing: variantKey)
        }
        return entry.tcgplayerMarketEstimateUSD()
    }

    /// GBP price for a specific variant key directly (not printing label).
    func gbpPriceForVariant(for card: Card, variantKey: String) async -> Double? {
        guard let usd = await usdPriceForVariant(for: card, variantKey: variantKey) else { return nil }
        return usd * usdToGbp
    }

    /// USD price for a variant + grade combination (matches R2 / Scrydex fields).
    /// Grade "raw" uses the standard market estimate; "psa10" / "ace10" use their respective fields.
    ///
    /// Price-history JSON often labels variants differently than Scrydex (e.g. `specialIllustrationRare` vs `holofoil`).
    /// When the requested key is missing or has no price for this grade, we fall through the same variant order as
    /// ``usdPrice(for:printing:)`` so the headline market price still matches available Scrydex rows.
    func usdPriceForVariantAndGrade(for card: Card, variantKey: String, grade: String) async -> Double? {
        guard let entry = await pricing(for: card) else { return nil }
        if let scrydex = entry.scrydex, !scrydex.isEmpty {
            for key in Self.scrydexVariantKeyFallbackOrder(preferred: variantKey, scrydex: scrydex) {
                guard let pricing = scrydex[key] else { continue }
                if let usd = Self.usdForScrydexVariant(pricing, grade: grade) { return usd }
            }
            return nil
        }
        if grade == "psa10" || grade == "ace10" { return nil }
        return entry.tcgplayerMarketEstimateUSD()
    }

    private static func usdForScrydexVariant(_ pricing: ScrydexVariantPricing, grade: String) -> Double? {
        switch grade {
        case "psa10": return pricing.psa10
        case "ace10": return pricing.ace10
        default: return pricing.raw ?? pricing.market ?? pricing.avg
        }
    }

    /// Scrydex keys to try: preferred (case-insensitive), then common English product types, then remaining keys.
    private static func scrydexVariantKeyFallbackOrder(
        preferred: String,
        scrydex: [String: ScrydexVariantPricing]
    ) -> [String] {
        var ordered: [String] = []
        var seen = Set<String>()
        func appendCanonical(_ raw: String) {
            let k = scrydex.keys.first(where: { $0 == raw || $0.lowercased() == raw.lowercased() }) ?? raw
            guard scrydex[k] != nil, !seen.contains(k) else { return }
            ordered.append(k)
            seen.insert(k)
        }
        appendCanonical(preferred)
        for k in [
            "normal", "holofoil", "reverseHolofoil", "reverse_holofoil",
            "pokeballReverseHolofoil", "cosmosHolofoil", "unlimited", "unlimitedHolofoil",
            "firstEdition", "firstEditionHolofoil", "shadowless", "amazingRare", "radiantHolofoil",
        ] {
            appendCanonical(k)
        }
        for k in scrydex.keys.sorted() {
            appendCanonical(k)
        }
        return ordered
    }

    /// GBP price for a variant + grade combination.
    func gbpPriceForVariantAndGrade(for card: Card, variantKey: String, grade: String) async -> Double? {
        guard let usd = await usdPriceForVariantAndGrade(for: card, variantKey: variantKey, grade: grade) else { return nil }
        return usd * usdToGbp
    }

    // Per-set history/trends raw JSON cache (cardKey → raw dict). Key includes brand so Pokémon vs ONE PIECE paths don’t collide.
    private var historyCache: [String: [String: [String: Any]]] = [:]
    private var trendsCache: [String: [String: [String: Any]]] = [:]

    private static func historyTrendsCacheKey(setCode: String, catalogBrand: TCGBrand) -> String {
        let s = setCode.lowercased()
        switch catalogBrand {
        case .pokemon: return "pk:\(s)"
        case .onePiece: return "op:\(s)"
        }
    }

    /// Resolves price history from the per-set file (SQLite after daily sync, else network), looks up by card key.
    func priceHistory(for card: Card) async -> CardPriceHistory? {
        let setCode = card.setCode.lowercased()
        let catalogBrand = Self.pricingCatalogBrand(for: card)
        let setMap = await loadSetHistoryMap(setCode: setCode, catalogBrand: catalogBrand)
        let keys = Self.pricingLookupKeys(for: card, historyStyle: true)
        guard let variantMap = Self.lookupPerCardEntry(in: setMap, keys: keys) else { return nil }
        guard let parsed = CardPriceHistory.parse(from: variantMap) else { return nil }
        if catalogBrand != .pokemon {
            return Self.remapOnePiecePriceHistory(parsed, card: card)
        }
        return parsed
    }

    /// Resolves price trends from the per-set file (SQLite after daily sync, else network), looks up by card key.
    func priceTrends(for card: Card) async -> CardPriceTrends? {
        let setCode = card.setCode.lowercased()
        let catalogBrand = Self.pricingCatalogBrand(for: card)
        let setMap = await loadSetTrendsMap(setCode: setCode, catalogBrand: catalogBrand)
        let keys = Self.pricingLookupKeys(for: card, historyStyle: true)
        guard let raw = Self.lookupPerCardEntry(in: setMap, keys: keys) else { return nil }
        guard let parsed = CardPriceTrends.parse(from: raw) else { return nil }
        if catalogBrand != .pokemon {
            return Self.remapOnePiecePriceTrends(parsed, card: card)
        }
        return parsed
    }

    private static func remapOnePiecePriceHistory(_ history: CardPriceHistory, card: Card) -> CardPriceHistory {
        guard let label = card.pricingVariants?.first, !label.isEmpty else { return history }
        return history.remappingVariantPlaceholder("default", to: label)
    }

    private static func remapOnePiecePriceTrends(_ trends: CardPriceTrends, card: Card) -> CardPriceTrends {
        guard let label = card.pricingVariants?.first, !label.isEmpty else { return trends }
        return trends.remappingVariantPlaceholder("default", to: label)
    }

    /// Resolves a card row in per-set JSON keyed by `me2pt5-280`, `me02.5-280`, etc.
    private static func lookupPerCardEntry(in map: [String: [String: Any]], keys: [String]) -> [String: Any]? {
        for k in keys {
            if let v = map[k] { return v }
        }
        for k in keys {
            let lower = k.lowercased()
            if let v = map.first(where: { $0.key.lowercased() == lower })?.value { return v }
        }
        let unified = Set(keys.map { unifiedPricingCardKey($0) })
        for (mapKey, value) in map {
            if unified.contains(unifiedPricingCardKey(mapKey)) {
                return value
            }
        }
        return nil
    }

    private func loadSetHistoryMap(setCode: String, catalogBrand: TCGBrand) async -> [String: [String: Any]] {
        let cacheKey = Self.historyTrendsCacheKey(setCode: setCode, catalogBrand: catalogBrand)
        // Move the synchronous SQLite queue.sync call off the main actor so it doesn't block the UI
        // or serialise concurrent card detail views behind each other during catalog sync.
        let blob = await Task.detached(priority: .userInitiated) {
            try? CatalogStore.shared.open()
            return CatalogStore.shared.fetchPriceHistoryData(setCode: setCode, brand: catalogBrand)
        }.value
        if let blob,
           let root = try? JSONSerialization.jsonObject(with: blob) as? [String: Any] {
            let typed = root.compactMapValues { $0 as? [String: Any] }
            if !typed.isEmpty {
                historyCache[cacheKey] = typed
                return typed
            }
        }
        if let cached = historyCache[cacheKey] { return cached }
        guard AppConfiguration.r2BaseURL.host != "invalid.local" else { return [:] }
        switch catalogBrand {
        case .onePiece:
            for stem in Self.onePieceMarketPricingStemVariants(for: setCode) {
                let url = AppConfiguration.r2OnePiecePricingHistoryURL(setCodeStem: stem)
                guard let data = await fetchDataIfOK(from: url),
                      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                let typed = root.compactMapValues { $0 as? [String: Any] }
                historyCache[cacheKey] = typed
                return typed
            }
            return [:]
        case .pokemon:
            for stem in AppConfiguration.pricingFileStemVariants(for: setCode) {
                let url = AppConfiguration.r2PricingHistoryURL(setCode: stem)
                guard let data = await fetchDataIfOK(from: url),
                      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                let typed = root.compactMapValues { $0 as? [String: Any] }
                historyCache[cacheKey] = typed
                return typed
            }
            return [:]
        }
    }

    private func loadSetTrendsMap(setCode: String, catalogBrand: TCGBrand) async -> [String: [String: Any]] {
        let cacheKey = Self.historyTrendsCacheKey(setCode: setCode, catalogBrand: catalogBrand)
        // Move the synchronous SQLite queue.sync call off the main actor so it doesn't block the UI.
        let blob = await Task.detached(priority: .userInitiated) {
            try? CatalogStore.shared.open()
            return CatalogStore.shared.fetchPriceTrendsData(setCode: setCode, brand: catalogBrand)
        }.value
        if let blob,
           let root = try? JSONSerialization.jsonObject(with: blob) as? [String: Any] {
            let typed = root.compactMapValues { $0 as? [String: Any] }
            if !typed.isEmpty {
                trendsCache[cacheKey] = typed
                return typed
            }
        }
        if let cached = trendsCache[cacheKey] { return cached }
        guard AppConfiguration.r2BaseURL.host != "invalid.local" else { return [:] }
        switch catalogBrand {
        case .onePiece:
            for stem in Self.onePieceMarketPricingStemVariants(for: setCode) {
                let url = AppConfiguration.r2OnePiecePriceTrendsURL(setCodeStem: stem)
                guard let data = await fetchDataIfOK(from: url),
                      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                let typed = root.compactMapValues { $0 as? [String: Any] }
                trendsCache[cacheKey] = typed
                return typed
            }
            return [:]
        case .pokemon:
            for stem in AppConfiguration.pricingFileStemVariants(for: setCode) {
                let url = AppConfiguration.r2PriceTrendsURL(setCode: stem)
                guard let data = await fetchDataIfOK(from: url),
                      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                let typed = root.compactMapValues { $0 as? [String: Any] }
                trendsCache[cacheKey] = typed
                return typed
            }
            return [:]
        }
    }

    private func fetchDataIfOK(from url: URL) async -> Data? {
        do {
            let (data, resp) = try await session.data(from: url)
            guard let http = resp as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  !data.isEmpty else { return nil }
            return data
        } catch {
            return nil
        }
    }

    func usdPrice(for card: Card, printing: String) async -> Double? {
        guard let entry = await pricing(for: card) else { return nil }
        if let scrydex = entry.scrydex, !scrydex.isEmpty {
            return scrydexUSD(from: scrydex, printing: printing)
        }
        return entry.tcgplayerMarketEstimateUSD()
    }

    func gbpPrice(for card: Card, printing: String) async -> Double? {
        guard let usd = await usdPrice(for: card, printing: printing) else { return nil }
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

    /// Loads per-set pricing: Pokémon from `pricing/card-pricing/…`; ONE PIECE from `onepiece/pricing/market/{set}.json` (keys match catalog `priceKey`).
    private func loadPricingMap(for card: Card, forceNetwork: Bool = false) async -> SetPricingMap {
        let key = card.setCode.lowercased()
        if !forceNetwork, let hit = pricingCache[key], hit.expiry > Date() {
            return hit.map
        }
        if forceNetwork {
            pricingCache.removeValue(forKey: key)
        }

        // Local reads: SQLite is the catalog runtime source of truth (sync fills this). Legacy disk JSON may exist from older builds.
        if !forceNetwork {
            try? CatalogStore.shared.open()
            let catalogBrand = Self.pricingCatalogBrand(for: card)
            if let blob = CatalogStore.shared.fetchPricingData(setCode: card.setCode, brand: catalogBrand),
               let map = Self.decodePricingMap(from: blob) {
                pricingCache[key] = (map, Date().addingTimeInterval(cacheTTL))
                return map
            }
            if catalogBrand == .pokemon, let disk = loadDiskCache(setCode: key) {
                pricingCache[key] = (disk, Date().addingTimeInterval(cacheTTL))
                return disk
            }
            return [:]
        }

        // Explicit refresh: fetch R2, upsert SQLite + legacy disk cache, then return.
        let base = AppConfiguration.r2BaseURL
        if base.host != "invalid.local" {
            switch Self.pricingCatalogBrand(for: card) {
            case .onePiece:
                for stem in Self.onePieceMarketPricingStemVariants(for: card.setCode) {
                    let url = AppConfiguration.r2OnePieceMarketPricingSetURL(setCodeStem: stem)
                    if let (map, data) = await fetchPricingMapAndDataIfOK(from: url) {
                        pricingCache[key] = (map, Date().addingTimeInterval(cacheTTL))
                        saveDiskCache(setCode: key, data: data)
                        try? CatalogStore.shared.open()
                        try? CatalogStore.shared.upsertPricing(setCode: key, json: data, brand: .onePiece)
                        return map
                    }
                }
            case .pokemon:
                for stem in AppConfiguration.pricingFileStemVariants(for: key) {
                    let url = AppConfiguration.r2CardPricingSetJSONURL(setCodeStem: stem)
                    if let (map, data) = await fetchPricingMapAndDataIfOK(from: url) {
                        pricingCache[key] = (map, Date().addingTimeInterval(cacheTTL))
                        saveDiskCache(setCode: key, data: data)
                        try? CatalogStore.shared.open()
                        try? CatalogStore.shared.upsertPricing(setCode: key, json: data, brand: .pokemon)
                        return map
                    }
                }
            }
        }

        try? CatalogStore.shared.open()
        let catalogBrand = Self.pricingCatalogBrand(for: card)
        if let blob = CatalogStore.shared.fetchPricingData(setCode: card.setCode, brand: catalogBrand),
           let map = Self.decodePricingMap(from: blob) {
            pricingCache[key] = (map, Date().addingTimeInterval(cacheTTL))
            return map
        }

        return [:]
    }

    /// Which SQLite partition / R2 pricing tree this card uses.
    private static func pricingCatalogBrand(for card: Card) -> TCGBrand {
        if card.masterCardId.contains("::") { return .onePiece }
        return .pokemon
    }

    /// Filenames on R2 use set codes like `OP01` (case-sensitive); try a small set of stems.
    private static func onePieceMarketPricingStemVariants(for setCode: String) -> [String] {
        let s = setCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return [] }
        var stems: [String] = []
        func add(_ x: String) {
            let t = x.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty, !stems.contains(t) { stems.append(t) }
        }
        add(s)
        add(s.uppercased())
        add(s.lowercased())
        return stems
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
