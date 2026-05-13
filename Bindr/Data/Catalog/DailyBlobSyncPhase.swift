import Foundation

/// Handles global market JSON blobs (not franchise-specific): market trend, price trends, pokedata products.
struct DailyBlobSyncPhase {
    let session: URLSession
    let store: CatalogStore

    func estimatedFileCount(enabledBrands: Set<TCGBrand>, forceRefresh: Bool = false) async -> Int {
        guard AppConfiguration.r2BaseURL.host != "invalid.local" else { return 0 }
        let periodStart = DailyMarketPricingSchedule.currentPeriodStart(now: Date(), calendar: .current)
        var keys: [String] = [DailyBlobKey.priceTrends, DailyBlobKey.marketTrend]
        if enabledBrands.contains(.pokemon) { keys.insert(DailyBlobKey.pokedataEnglishPokemonProducts, at: 0) }
        if forceRefresh { return keys.count }
        var stale = 0
        for key in keys {
            guard let last = await store.dailyBlobFetchedAt(key: key) else { stale += 1; continue }
            if last < periodStart { stale += 1 }
        }
        return stale
    }

    func syncIfNeeded(
        progress: CatalogSyncProgressReporter,
        enabledBrands: Set<TCGBrand>,
        forceRefresh: Bool = false
    ) async -> Int64 {
        guard AppConfiguration.r2BaseURL.host != "invalid.local" else { return 0 }
        let periodStart = DailyMarketPricingSchedule.currentPeriodStart(now: Date(), calendar: .current)
        var keys: [(String, URL)] = [
            (DailyBlobKey.priceTrends, AppConfiguration.r2MarketURL(path: DailyBlobPath.priceTrends)),
            (DailyBlobKey.marketTrend, AppConfiguration.r2MarketURL(path: DailyBlobPath.marketTrend)),
        ]
        if enabledBrands.contains(.pokemon) {
            keys.insert((DailyBlobKey.pokedataEnglishPokemonProducts, AppConfiguration.r2MarketURL(path: DailyBlobPath.pokedataEnglishPokemonProducts)), at: 0)
        }
        let staleKeys: [(String, URL)]
        if forceRefresh {
            staleKeys = keys
        } else {
            var result: [(String, URL)] = []
            for (key, url) in keys {
                guard let last = await store.dailyBlobFetchedAt(key: key) else { result.append((key, url)); continue }
                if last < periodStart { result.append((key, url)) }
            }
            staleKeys = result
        }
        guard !staleKeys.isEmpty else { return 0 }

        var downloaded: Int64 = 0
        await progress.setStatus("Refreshing daily market data…")
        await progress.addPlannedFiles(staleKeys.count)

        for (key, url) in staleKeys {
            let etagMetaKey = "daily_blob_http_etag_" + key
            var request = URLRequest(url: url)
            if !forceRefresh, let prev = await store.meta(etagMetaKey), !prev.isEmpty {
                request.setValue(prev, forHTTPHeaderField: "If-None-Match")
            }
            guard let (data, resp) = try? await session.data(for: request),
                  let http = resp as? HTTPURLResponse
            else { await progress.completeFile(); continue }

            if http.statusCode == 304 {
                try? await store.touchDailyBlobFetchedAt(key: key)
                if let e = http.value(forHTTPHeaderField: "ETag") ?? http.value(forHTTPHeaderField: "Etag") {
                    try? await store.setMeta(etagMetaKey, e)
                }
                await progress.completeFile(byteCount: 0)
                continue
            }
            guard (200...299).contains(http.statusCode), !data.isEmpty else {
                await progress.completeFile(); continue
            }
            do {
                try await store.upsertDailyBlob(key: key, data: data)
                if let e = http.value(forHTTPHeaderField: "ETag") ?? http.value(forHTTPHeaderField: "Etag") {
                    try? await store.setMeta(etagMetaKey, e)
                }
                await progress.completeFile(byteCount: Int64(data.count))
                downloaded += Int64(data.count)
            } catch {
                await progress.completeFile()
            }
        }
        return downloaded
    }
}
