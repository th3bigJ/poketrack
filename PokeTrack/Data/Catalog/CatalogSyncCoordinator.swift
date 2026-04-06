import CryptoKit
import Foundation

/// Downloads catalog + per-set pricing into `CatalogStore`. Compares `sets.json` SHA256 to avoid full re-import when unchanged.
final class CatalogSyncCoordinator: @unchecked Sendable {
    static let shared = CatalogSyncCoordinator()

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Run after app launch: refresh catalog if needed, refresh pricing if stale (> 24h), then refresh daily blobs if stale (> 24h).
    func syncAllIfNeeded() async {
        do {
            try CatalogStore.shared.open()
        } catch {
            return
        }
        await syncCatalogIfNeeded()
        await syncPricingIfNeeded()
        await syncDailyBlobsIfNeeded()
    }

    private func syncCatalogIfNeeded() async {
        guard AppConfiguration.r2BaseURL.host != "invalid.local" else { return }
        let setsURL = AppConfiguration.r2CatalogURL(path: "sets.json")
        let (data, resp): (Data, URLResponse)
        do {
            (data, resp) = try await session.data(from: setsURL)
        } catch {
            return
        }
        let http = resp as? HTTPURLResponse
        let etag = http?.value(forHTTPHeaderField: "ETag") ?? http?.value(forHTTPHeaderField: "Etag")
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()

        let store = CatalogStore.shared
        let prevHash = store.meta("catalog_sets_sha256")
        let prevEtag = store.meta("catalog_etag")
        let unchangedHash = (hash == prevHash)
        let unchangedEtag = (etag != nil && etag == prevEtag)
        let hasCards = (try? store.hasAnyCards()) ?? false
        if hasCards && (unchangedHash || unchangedEtag) {
            return
        }

        do {
            let sets = try JSONDecoder().decode([TCGSet].self, from: data)
            try store.clearCatalog()
            for set in sets {
                try store.upsertSet(set)
                let code = set.setCode
                let cardsURL = AppConfiguration.r2CatalogURL(path: "cards/\(code).json")
                if let (cData, _) = try? await session.data(from: cardsURL) {
                    let cards = try JSONDecoder().decode([Card].self, from: cData)
                    try store.insertCards(cards, setCode: code)
                }
                for stem in Self.pricingFileStemVariants(forSetCode: code) {
                    let pURL = AppConfiguration.r2CardPricingSetJSONURL(setCodeStem: stem)
                    guard let (pData, resp) = try? await session.data(from: pURL),
                          let http = resp as? HTTPURLResponse,
                          (200...299).contains(http.statusCode),
                          !pData.isEmpty
                    else { continue }
                    try store.upsertPricing(setCode: code, json: pData)
                    break
                }
            }
            try store.setMeta("catalog_sets_sha256", hash)
            if let etag {
                try store.setMeta("catalog_etag", etag)
            }
            try store.setMeta("catalog_import_at", String(Date().timeIntervalSince1970))
        } catch {
            // Leave DB partial or empty; UI can fall back to network.
        }
    }

    private func syncPricingIfNeeded() async {
        guard AppConfiguration.r2BaseURL.host != "invalid.local" else { return }
        let store = CatalogStore.shared
        let day: TimeInterval = 24 * 60 * 60
        if let lastStr = store.meta("pricing_last_synced_at"),
           let last = Double(lastStr),
           Date().timeIntervalSince1970 - last < day {
            return
        }
        let sets: [TCGSet]
        do {
            sets = try store.fetchAllSets()
        } catch {
            return
        }
        guard !sets.isEmpty else { return }
        await withTaskGroup(of: (String, Data)?.self) { group in
            for set in sets {
                let code = set.setCode
                let stems = Self.pricingFileStemVariants(forSetCode: code)
                let sess = session
                group.addTask {
                    for stem in stems {
                        let pURL = AppConfiguration.r2CardPricingSetJSONURL(setCodeStem: stem)
                        guard let (pData, resp) = try? await sess.data(from: pURL),
                              let http = resp as? HTTPURLResponse,
                              (200...299).contains(http.statusCode),
                              !pData.isEmpty
                        else { continue }
                        return (code, pData)
                    }
                    return nil
                }
            }
            for await result in group {
                guard let (code, data) = result else { continue }
                try? store.upsertPricing(setCode: code, json: data)
            }
        }
        try? store.setMeta("pricing_last_synced_at", String(Date().timeIntervalSince1970))
    }

    private func syncDailyBlobsIfNeeded() async {
        guard AppConfiguration.r2BaseURL.host != "invalid.local" else { return }
        let store = CatalogStore.shared
        let day: TimeInterval = 24 * 60 * 60
        let keys: [(String, URL)] = [
            (DailyBlobKey.pokedataEnglishPokemonPrices, AppConfiguration.r2MarketURL(path: DailyBlobPath.pokedataEnglishPokemonPrices)),
            (DailyBlobKey.priceTrends, AppConfiguration.r2MarketURL(path: DailyBlobPath.priceTrends)),
        ]
        for (key, url) in keys {
            if let last = store.dailyBlobFetchedAt(key: key), Date().timeIntervalSince(last) < day {
                continue
            }
            if let (data, _) = try? await session.data(from: url), !data.isEmpty {
                try? store.upsertDailyBlob(key: key, data: data)
            }
        }
    }

    /// Same rules as `PricingService.pricingFileStemVariants` (e.g. `me03` vs `me3` pricing filenames).
    private static func pricingFileStemVariants(forSetCode setCode: String) -> [String] {
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
}

enum DailyBlobKey {
    static let pokedataEnglishPokemonPrices = "pokedata_english_pokemon_prices"
    static let priceTrends = "price_trends"
}

/// Paths relative to `r2MarketPathPrefix` (default: bucket root). Adjust in `AppConfiguration` / plist if your tidy layout differs.
enum DailyBlobPath {
    static let pokedataEnglishPokemonPrices = "sealed-products/pokedata/pokedata-english-pokemon-prices.json"
    static let priceTrends = "data/price-trends.json"
}
