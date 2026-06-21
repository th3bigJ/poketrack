import Foundation
import Observation

@Observable
@MainActor
final class PricingService {
    private static let usdToGbpDefaultsKey = "pricing.usd_to_gbp.last_known"
    private(set) var usdToGbp: Double = 0.79
    private(set) var lastFXError: String?

    @ObservationIgnored private var pricingCache: [String: (map: SetPricingMap, expiry: Date)] = [:]
    /// Per-card pricing cache keyed by card key (lowercased). Populated by `prefetchPokemonCardPricing`.
    /// `nil` value means "looked up and found nothing" so we skip the SQLite round-trip.
    @ObservationIgnored private var pokemonCardPricingCache: [String: CardPricingEntry?] = [:]
    /// Secondary index keyed by masterCardId (lowercased). Built by `indexPricingForCards` once
    /// card objects are in memory, enabling O(1) lookup without knowing externalId/tcgdex_id.
    @ObservationIgnored private var pokemonPricingByMasterCardID: [String: CardPricingEntry?] = [:]
    @ObservationIgnored private var pokemonPricingPrefetchedSets: Set<String> = []
    @ObservationIgnored private var pokemonAllPricingPrefetched: Bool = false

    private let session: URLSession
    private let fileManager: FileManager
    private let cacheTTL: TimeInterval = 24 * 60 * 60

    init(session: URLSession = .shared, fileManager: FileManager = .default) {
        self.session = session
        self.fileManager = fileManager
        let savedRate = UserDefaults.standard.double(forKey: Self.usdToGbpDefaultsKey)
        if savedRate > 0 {
            usdToGbp = savedRate
        }
    }

    /// Drops in-memory per-set pricing maps after a catalog purge or before a full re-download so SQLite stays authoritative.
    func clearSetPricingMemoryCache() {
        pricingCache.removeAll(keepingCapacity: false)
        historyCache.removeAll(keepingCapacity: false)
        trendsCache.removeAll(keepingCapacity: false)
        pokemonCardPricingCache.removeAll(keepingCapacity: false)
        pokemonPricingByMasterCardID.removeAll(keepingCapacity: false)
        pokemonPricingPrefetchedSets.removeAll(keepingCapacity: false)
        pokemonAllPricingPrefetched = false
    }

    /// Build a masterCardId-keyed index from already-loaded Card objects so that
    /// `cachedUsdPriceForCardID` can do O(1) lookups without knowing externalId/tcgdex_id.
    /// Call this after `prefetchAllPokemonCardPricing` and a bulk card load both complete.
    func indexPricingForCards(_ cards: [Card]) async {
        var seen = Set<String>()
        var i = 0
        for card in cards {
            let key = card.masterCardId.lowercased()
            guard seen.insert(key).inserted else { continue }
            i += 1
            if i % 200 == 0 { await Task.yield() }
            if let existing = pokemonPricingByMasterCardID[key], existing != nil {
                continue
            }
            let lookupKeys = Self.pricingLookupKeys(for: card)
            var found: CardPricingEntry? = nil
            for lk in lookupKeys {
                if let idx = pokemonCardPricingCache.index(forKey: lk.lowercased()),
                   let entry = pokemonCardPricingCache[idx].value {
                    found = entry
                    break
                }
            }
            pokemonPricingByMasterCardID[key] = found
        }
    }

    /// Pricing entry from the warm in-memory cache after prefetch + index. Returns `nil` when
    /// the card has not been indexed yet (caller should fall back to `pricing(for:)`).
    func cachedPricingEntry(for card: Card) -> CardPricingEntry? {
        let masterKey = card.masterCardId.lowercased()
        if let idx = pokemonPricingByMasterCardID.index(forKey: masterKey) {
            return pokemonPricingByMasterCardID[idx].value
        }
        for key in Self.pricingLookupKeys(for: card) {
            if let idx = pokemonCardPricingCache.index(forKey: key.lowercased()) {
                return pokemonCardPricingCache[idx].value
            }
        }
        return nil
    }

    /// Whether pricing for this card is present in the warm cache (including cached "no price").
    func isPricingIndexed(for card: Card) -> Bool {
        pokemonPricingByMasterCardID.index(forKey: card.masterCardId.lowercased()) != nil
    }

    /// Bulk-populate the Pokemon card pricing cache from a single SQLite query covering all sets.
    /// Replaces per-set fetching which missed alternate set codes (swsh12tg, swsh45sv, etc.).
    func prefetchAllPokemonCardPricing() async {
        guard !pokemonAllPricingPrefetched else { return }
        let allPrices = await CatalogStore.shared.fetchAllCardPrices(brand: .pokemon)
        // Decode all JSON blobs off @MainActor — with 800+ cards this loop accounts
        // for ~250ms of main-thread freeze on every cold launch.
        let decoded: [String: CardPricingEntry?] = await Task.detached(priority: .userInitiated) {
            var result: [String: CardPricingEntry?] = [:]
            result.reserveCapacity(allPrices.count)
            for (cardKey, json) in allPrices {
                result[cardKey.lowercased()] = Self.decodePokemonCardPrice(json)
            }
            return result
        }.value
        // Bulk merge: since we only get here when pokemonAllPricingPrefetched==false (guard above),
        // the cache is empty or has only a handful of per-card misses — just merge with updateValue
        // to preserve any entries already in the cache, then flip the prefetch flag.
        // Avoid iterating 800+ entries one-by-one on @MainActor; use merging(_:uniquingKeysWith:)
        // which is a single O(n) pass done as a value-type operation before the assignment lands.
        let merged = decoded.merging(pokemonCardPricingCache) { _, existing in existing }
        pokemonCardPricingCache = merged
        pokemonAllPricingPrefetched = true
    }

    func prefetchPokemonCardPricing(forSetCodes setCodes: Set<String>) async {
        await prefetchAllPokemonCardPricing()
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
        // Perform network I/O off @MainActor so a slow response doesn't block the main thread.
        do {
            let (data, _) = try await Task.detached(priority: .utility) {
                try await URLSession.shared.data(from: url)
            }.value
            let decoded = try JSONDecoder().decode(FrankfurterResponse.self, from: data)
            if let gbp = decoded.rates["GBP"] {
                usdToGbp = gbp
                UserDefaults.standard.set(gbp, forKey: Self.usdToGbpDefaultsKey)
            }
        } catch {
            lastFXError = error.localizedDescription
        }
    }

    func pricing(for card: Card) async -> CardPricingEntry? {
        return await loadPokemonCardPricing(for: card)
    }

    private func loadPokemonCardPricing(for card: Card) async -> CardPricingEntry? {
        let keys = Self.pricingLookupKeys(for: card)
        // Fast path: return from pre-fetched cache (populated by `prefetchPokemonCardPricing`).
        // Use index(forKey:) so a cached nil ("looked up, no price") is also a hit and skips SQLite.
        for key in keys {
            let cacheKey = key.lowercased()
            if let idx = pokemonCardPricingCache.index(forKey: cacheKey) {
                return pokemonCardPricingCache[idx].value
            }
        }
        for key in keys {
            let data = await CatalogStore.shared.fetchCardPrice(cardKey: key, brand: .pokemon)
            if let entry = Self.decodePokemonCardPrice(data) { return entry }
        }
        if let entry = await Self.matchPokemonCardPriceInSet(for: card, candidateKeys: keys) {
            return entry
        }
        // card_prices not yet populated (e.g. daily bucket not synced yet). Build a synthetic entry
        // from the most recent daily point in price_history_points so pricing still returns a value.
        for key in keys {
            let pts = await CatalogStore.shared.fetchPriceHistoryPoints(brand: .pokemon, cardKey: key)
            if let entry = Self.cardPricingEntry(fromDailyHistoryPoints: pts) { return entry }
        }
        let unifiedCandidates = Set(keys.map { Self.unifiedPricingCardKey($0) })
        for setCode in Self.pricingSetCodesToQuery(for: card) {
            let setPts = await CatalogStore.shared.fetchPriceHistoryPoints(brand: .pokemon, setCode: setCode)
            let matchingPts = setPts.filter { unifiedCandidates.contains(Self.unifiedPricingCardKey($0.cardKey)) }
            if let entry = Self.cardPricingEntry(fromDailyHistoryPoints: matchingPts) { return entry }
        }
        return nil
    }

    private static func pricingSetCodesToQuery(for card: Card) -> [String] {
        var codes: [String] = []
        func append(_ s: String) {
            let raw = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !raw.isEmpty else { return }
            if !codes.contains(raw) { codes.append(raw) }
            let normalized = BucketDateMath.normalizedSetCode(raw)
            if !normalized.isEmpty, !codes.contains(normalized) { codes.append(normalized) }
        }
        append(card.setCode)
        for key in pricingLookupKeys(for: card) {
            guard let dash = key.lastIndex(of: "-") else { continue }
            append(String(key[..<dash]))
        }
        return codes
    }

    nonisolated private static func decodePokemonCardPrice(_ data: Data?) -> CardPricingEntry? {
        guard let data else { return nil }
        if let entry = try? JSONDecoder().decode(CardPricingEntry.self, from: data) { return entry }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let subData = try? JSONSerialization.data(withJSONObject: obj),
           let entry = try? JSONDecoder().decode(CardPricingEntry.self, from: subData) {
            return entry
        }
        return nil
    }

    private static func matchPokemonCardPriceInSet(for card: Card, candidateKeys: [String]) async -> CardPricingEntry? {
        let setCodes = Self.pricingSetCodesToQuery(for: card)
        guard !setCodes.isEmpty else { return nil }
        let unifiedCandidates = Set(candidateKeys.map { unifiedPricingCardKey($0) })
        for setCode in setCodes {
            let rows = await CatalogStore.shared.fetchCardPricesForSet(setCode: setCode, brand: .pokemon)
            for row in rows {
                guard unifiedCandidates.contains(unifiedPricingCardKey(row.cardKey)) else { continue }
                if let entry = try? JSONDecoder().decode(CardPricingEntry.self, from: row.json) { return entry }
                if let obj = try? JSONSerialization.jsonObject(with: row.json) as? [String: Any],
                   let subData = try? JSONSerialization.data(withJSONObject: obj),
                   let entry = try? JSONDecoder().decode(CardPricingEntry.self, from: subData) {
                    return entry
                }
            }
        }
        return nil
    }

    private static func cardPricingEntry(fromDailyHistoryPoints points: [CatalogStore.PriceHistoryPoint]) -> CardPricingEntry? {
        let dailyPts = points.filter { $0.periodType == "daily" }
        guard !dailyPts.isEmpty else { return nil }
        var latestByVariantGrade: [String: CatalogStore.PriceHistoryPoint] = [:]
        for pt in dailyPts {
            let k = "\(pt.variant)/\(pt.grade)"
            if latestByVariantGrade[k] == nil || pt.periodKey > latestByVariantGrade[k]!.periodKey {
                latestByVariantGrade[k] = pt
            }
        }
        var scrydexDict: [String: [String: Double]] = [:]
        for (_, pt) in latestByVariantGrade {
            scrydexDict[pt.variant, default: [:]][pt.grade == "raw" ? "raw" : pt.grade] = pt.price
        }
        guard !scrydexDict.isEmpty,
              let json = try? JSONSerialization.data(withJSONObject: ["scrydex": scrydexDict]),
              let entry = try? JSONDecoder().decode(CardPricingEntry.self, from: json)
        else { return nil }
        return entry
    }

    /// Keys to try for per-set pricing / history JSON lookups.
    /// - **Pokémon market:** `externalId`, `tcgdex_id`, derived ids, `masterCardId`.
    /// - **Pokémon history / trends:** `tcgdex_id` first (dotted ids match R2), then `externalId`, locals, `masterCardId`.
    private static func pricingLookupKeys(for card: Card, historyStyle: Bool = false) -> [String] {
        var keys: [String] = []
        func append(_ s: String) {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty, !keys.contains(t) { keys.append(t) }
        }
        if historyStyle {
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
            // Some sets have sub-sets with separate pricing files (e.g. swsh12 Trainer Gallery cards
            // are priced under swsh12tg-*, swsh12pt5 Galaxy cards under swsh12pt5gg-*, etc.).
            // Generate alternate-set-code keys so lookups find the correct pricing row.
            for alt in Self.alternatePricingSetCodes(for: sc, localId: local) {
                append("\(alt)-\(local)")
                if let n = Int(local) {
                    append("\(alt)-\(n)")
                    append(String(format: "%@-%03d", alt, n))
                }
            }
        }
        append(card.masterCardId)
        return keys
    }

    /// Returns alternate pricing-file set codes for cards whose pricing is published under a
    /// sub-set code rather than the parent set code.
    ///
    /// e.g. swsh12 Trainer Gallery → swsh12tg, swsh12pt5 Galaxy Gallery → swsh12pt5gg,
    ///      swshN Trainer Gallery  → swshNtg,  swsh45 Shining Fates SV → swsh45sv
    nonisolated private static func alternatePricingSetCodes(for setCode: String, localId: String) -> [String] {
        let sc = setCode.lowercased()
        let lid = localId.uppercased()

        // swsh12pt5 (Crown Zenith): Galaxy Gallery cards have localId prefix GG
        if sc == "swsh12pt5" && lid.hasPrefix("GG") { return ["swsh12pt5gg"] }

        // swsh45 (Shining Fates): Shiny Vault cards have localId prefix SV
        if sc == "swsh45" && lid.hasPrefix("SV") { return ["swsh45sv"] }

        // swshN Trainer Gallery sets: TG prefix
        let tgSets = ["swsh12", "swsh11", "swsh10", "swsh9"]
        if tgSets.contains(sc) && lid.hasPrefix("TG") { return ["\(sc)tg"] }

        return []
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
        return Self.resolveUsdPrice(entry: entry, variantKey: variantKey, grade: grade)
    }

    /// Synchronous variant — only reads the pre-warmed in-memory cache, never touches SQLite.
    /// Call this inside bulk pricing loops after `prefetchPokemonCardPricing` has run.
    func cachedUsdPriceForVariantAndGrade(for card: Card, variantKey: String, grade: String) -> Double? {
        let keys = Self.pricingLookupKeys(for: card)
        for key in keys {
            if let idx = pokemonCardPricingCache.index(forKey: key.lowercased()) {
                guard let entry = pokemonCardPricingCache[idx].value else { return nil }
                return Self.resolveUsdPrice(entry: entry, variantKey: variantKey, grade: grade)
            }
        }
        return nil
    }

    /// Highest cached USD price across all variants — used when sorting a collection grid group.
    func cachedBestUsdPriceForCard(for card: Card, grade: String = "raw") -> Double? {
        let keys = Self.pricingLookupKeys(for: card)
        for key in keys {
            if let idx = pokemonCardPricingCache.index(forKey: key.lowercased()) {
                guard let entry = pokemonCardPricingCache[idx].value else { continue }
                if let scrydex = entry.scrydex, !scrydex.isEmpty {
                    let prices = scrydex.values.compactMap { Self.usdForScrydexVariant($0, grade: grade) }
                    if let best = prices.max() { return best }
                }
                if grade == "raw", let tcg = entry.tcgplayerMarketEstimateUSD() {
                    return tcg
                }
            }
        }
        return nil
    }

    /// Best cached USD price for sort/display — tries the owned variant first, then any variant in the entry.
    func cachedMarketSortUSD(for card: Card, variantKey: String, grade: String) -> Double? {
        if let direct = cachedUsdPriceForVariantAndGrade(for: card, variantKey: variantKey, grade: grade) {
            return direct
        }
        if let best = cachedBestUsdPriceForCard(for: card, grade: grade) {
            return best
        }
        let keys = Self.pricingLookupKeys(for: card)
        for key in keys {
            if let idx = pokemonCardPricingCache.index(forKey: key.lowercased()) {
                return Self.marketSortUSD(from: pokemonCardPricingCache[idx].value, variantKey: variantKey, grade: grade)
            }
        }
        return nil
    }

    /// Resolves the best USD sort price for a card, falling back to SQLite when the bulk cache misses.
    func resolveBestMarketSortUSD(
        for card: Card,
        specs: [(variantKey: String, grade: String)]
    ) async -> Double? {
        var best: Double?
        for spec in specs {
            if let price = cachedMarketSortUSD(for: card, variantKey: spec.variantKey, grade: spec.grade) {
                best = max(best ?? 0, price)
            }
        }
        if best != nil { return best }

        guard let entry = await pricing(for: card) else { return nil }
        for spec in specs {
            if let price = Self.marketSortUSD(from: entry, variantKey: spec.variantKey, grade: spec.grade) {
                best = max(best ?? 0, price)
            }
        }
        if best != nil { return best }
        return Self.marketSortUSD(from: entry, variantKey: "normal", grade: "raw")
    }

    static func marketSortUSD(from entry: CardPricingEntry?, variantKey: String, grade: String) -> Double? {
        guard let entry else { return nil }
        if let direct = resolveUsdPrice(entry: entry, variantKey: variantKey, grade: grade) {
            return direct
        }
        if let scrydex = entry.scrydex, !scrydex.isEmpty {
            let prices = scrydex.values.compactMap { usdForScrydexVariant($0, grade: grade) }.filter { $0 > 0 }
            if let best = prices.max() { return best }
        }
        if grade == "raw" {
            return entry.tcgplayerMarketEstimateUSD()
        }
        return nil
    }

    /// Like `cachedUsdPriceForVariantAndGrade` but derives lookup keys from just the `masterCardId`
    /// string — no `Card` object required. Pokémon card IDs are `{setCode}-{localId}` so all
    /// `{setCode}-{localId}` key variants can be generated without a SQLite round-trip.
    /// Returns `nil` if the cache has no entry; caller should fall back to the full `Card`-based
    /// lookup for the rare cards where `externalId`/`tcgdex_id` is the only matching key.
    func cachedUsdPriceForCardID(_ masterCardId: String, variantKey: String, grade: String) -> Double? {
        // Fast path: masterCardId index built by indexPricingForCards — O(1) and handles externalId/tcgdex_id keys.
        let indexKey = masterCardId.lowercased()
        if let idx = pokemonPricingByMasterCardID.index(forKey: indexKey) {
            guard let entry = pokemonPricingByMasterCardID[idx].value else { return nil }
            return Self.resolveUsdPrice(entry: entry, variantKey: variantKey, grade: grade)
        }
        // Fallback: derive keys from masterCardId format (works for cards not yet indexed).
        let keys = Self.pricingLookupKeysFromMasterCardId(masterCardId)
        for key in keys {
            if let idx = pokemonCardPricingCache.index(forKey: key.lowercased()) {
                guard let entry = pokemonCardPricingCache[idx].value else { return nil }
                return Self.resolveUsdPrice(entry: entry, variantKey: variantKey, grade: grade)
            }
        }
        return nil
    }

    /// Generates pricing lookup keys from just a `masterCardId` string, without a `Card` object.
    /// Covers all `{setCode}-{localId}` patterns including alternate sub-set codes.
    nonisolated private static func pricingLookupKeysFromMasterCardId(_ masterCardId: String) -> [String] {
        // Pokémon: masterCardId is `{setCode}-{localId}` (e.g. "sv3-196", "swsh12-TG01").
        // Split on first `-` to extract setCode and localId.
        guard let dashRange = masterCardId.range(of: "-") else {
            return [masterCardId]
        }
        let sc = String(masterCardId[..<dashRange.lowerBound])
        let local = String(masterCardId[dashRange.upperBound...])
        guard !sc.isEmpty, !local.isEmpty else { return [masterCardId] }

        var keys: [String] = []
        func append(_ s: String) {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty, !keys.contains(t) { keys.append(t) }
        }
        append("\(sc)-\(local)")
        if let n = Int(local) {
            append("\(sc)-\(n)")
            append(String(format: "%@-%03d", sc, n))
        }
        for alt in alternatePricingSetCodes(for: sc, localId: local) {
            append("\(alt)-\(local)")
            if let n = Int(local) {
                append("\(alt)-\(n)")
                append(String(format: "%@-%03d", alt, n))
            }
        }
        append(masterCardId)
        return keys
    }

    private static func resolveUsdPrice(entry: CardPricingEntry, variantKey: String, grade: String) -> Double? {
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

    /// Latest available history-point price for a variant/grade combination.
    /// Used as a UI fallback when the live market entry is temporarily missing.
    func latestHistoryPriceUSD(for card: Card, variantKey: String, grade: String) async -> Double? {
        guard let history = await priceHistory(for: card),
              let series = history.series["\(variantKey)/\(grade)"] else { return nil }
        if let p = series.daily.last?.price { return p }
        if let p = series.weekly.last?.price { return p }
        if let p = series.monthly.last?.price { return p }
        return nil
    }

    @ObservationIgnored private var historyCache: [String: [String: [String: Any]]] = [:]
    @ObservationIgnored private var trendsCache: [String: [String: [String: Any]]] = [:]

    private static func historyTrendsCacheKey(setCode: String, catalogBrand: TCGBrand) -> String {
        return "pk:\(setCode.lowercased())"
    }

    /// Resolves price history from SQLite.
    func priceHistory(for card: Card) async -> CardPriceHistory? {
        return await loadPokemonPriceHistory(for: card)
    }

    /// Normalises variant strings that may have been stored with inconsistent casing from older R2 bucket files.
    private static func canonicalVariant(_ raw: String) -> String {
        switch raw.lowercased() {
        case "firstedition":           return "firstEdition"
        case "firsteditionholofoil":   return "firstEditionHolofoil"
        case "reverseholofoil":        return "reverseHolofoil"
        case "unlimitedholofoil":      return "unlimitedHolofoil"
        case "shadowlesholofoil",
             "shadowlessholofoil":     return "shadowlessHolofoil"
        case "amazingrare":            return "amazingRare"
        case "radiantholofoil":        return "radiantHolofoil"
        case "cosmosholofoil":         return "cosmosHolofoil"
        case "pokeballreverseholofoil": return "pokeballReverseHolofoil"
        default:                       return raw
        }
    }

    private func loadPokemonPriceHistory(for card: Card) async -> CardPriceHistory? {
        let keys = Self.pricingLookupKeys(for: card, historyStyle: true)
        for key in keys {
            let points = await CatalogStore.shared.fetchPriceHistoryPoints(brand: .pokemon, cardKey: key)
            guard !points.isEmpty else { continue }
            var seriesMap: [String: (daily: [PriceDataPoint], weekly: [PriceDataPoint], monthly: [PriceDataPoint])] = [:]
            for pt in points {
                let variant = Self.canonicalVariant(pt.variant)
                let seriesKey = "\(variant)/\(pt.grade)"
                let dataPoint = PriceDataPoint(id: pt.periodKey, label: pt.periodKey, price: pt.price)
                switch pt.periodType {
                case "daily": seriesMap[seriesKey, default: ([], [], [])].daily.append(dataPoint)
                case "weekly": seriesMap[seriesKey, default: ([], [], [])].weekly.append(dataPoint)
                case "monthly": seriesMap[seriesKey, default: ([], [], [])].monthly.append(dataPoint)
                default: break
                }
            }
            guard !seriesMap.isEmpty else { continue }
            var series: [String: CardPriceHistory.Series] = [:]
            for (k, v) in seriesMap {
                series[k] = CardPriceHistory.Series(
                    daily: v.daily.sorted { $0.id < $1.id },
                    weekly: v.weekly.sorted { $0.id < $1.id },
                    monthly: v.monthly.sorted { $0.id < $1.id }
                )
            }
            return CardPriceHistory(series: series)
        }
        return nil
    }

    /// Resolves price trends from the per-set file (SQLite after daily sync, else network), looks up by card key.
    func priceTrends(for card: Card) async -> CardPriceTrends? {
        let setCode = card.setCode.lowercased()
        let setMap = await loadSetTrendsMap(setCode: setCode, catalogBrand: .pokemon)
        let keys = Self.pricingLookupKeys(for: card, historyStyle: true)
        guard let raw = Self.lookupPerCardEntry(in: setMap, keys: keys) else { return nil }
        return CardPriceTrends.parse(from: raw)
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
        let blob = await CatalogStore.shared.fetchPriceHistoryData(setCode: setCode, brand: catalogBrand)
        if let blob,
           let root = try? JSONSerialization.jsonObject(with: blob) as? [String: Any] {
            let typed = root.compactMapValues { $0 as? [String: Any] }
            if !typed.isEmpty {
                historyCache[cacheKey] = typed
                return typed
            }
        }
        if let cached = historyCache[cacheKey] { return cached }
        // History is now built from daily bucket files during sync and stored in SQLite.
        // Per-set history files no longer exist on R2; SQLite is the only source.
        return [:]
    }

    /// Bulk-populate trendsCache from an already-fetched [setCode → raw blob] map (avoids N SQLite queries in the per-card loop).
    func prefetchTrendsCache(from allTrendsData: [String: Data], brand: TCGBrand) {
        for (setCode, blob) in allTrendsData {
            let cacheKey = Self.historyTrendsCacheKey(setCode: setCode, catalogBrand: brand)
            guard trendsCache[cacheKey] == nil else { continue }
            guard let root = try? JSONSerialization.jsonObject(with: blob) as? [String: Any] else { continue }
            let typed = root.compactMapValues { $0 as? [String: Any] }
            if !typed.isEmpty { trendsCache[cacheKey] = typed }
        }
    }

    private func loadSetTrendsMap(setCode: String, catalogBrand: TCGBrand) async -> [String: [String: Any]] {
        let cacheKey = Self.historyTrendsCacheKey(setCode: setCode, catalogBrand: catalogBrand)
        // Check in-memory cache first — prefetchTrendsCache may have already populated it.
        if let cached = trendsCache[cacheKey] { return cached }
        let blob = await CatalogStore.shared.fetchPriceTrendsData(setCode: setCode, brand: catalogBrand)
        if let blob,
           let root = try? JSONSerialization.jsonObject(with: blob) as? [String: Any] {
            let typed = root.compactMapValues { $0 as? [String: Any] }
            if !typed.isEmpty {
                trendsCache[cacheKey] = typed
                return typed
            }
        }
        if let cached = trendsCache[cacheKey] { return cached }
        // Trends are populated from daily sync into SQLite; no per-set network fallback.
        return [:]
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
