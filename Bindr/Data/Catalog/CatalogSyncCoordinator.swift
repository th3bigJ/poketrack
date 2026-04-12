import CryptoKit
import Foundation

struct CatalogSyncProgressSnapshot: Sendable {
    let status: String
    let completedFiles: Int
    let totalFiles: Int
    let downloadedBytes: Int64
    let estimatedTotalBytes: Int64

    var fractionCompleted: Double {
        guard totalFiles > 0 else { return 0 }
        return min(max(Double(completedFiles) / Double(totalFiles), 0), 1)
    }
}

private actor CatalogSyncProgressReporter {
    typealias Handler = @Sendable (CatalogSyncProgressSnapshot) -> Void

    private let handler: Handler?
    private var status: String = "Preparing card data…"
    private var completedFiles = 0
    private var totalFiles = 0
    private var downloadedBytes: Int64 = 0

    init(handler: Handler?) {
        self.handler = handler
    }

    func setStatus(_ status: String) {
        self.status = status
        emit()
    }

    func addPlannedFiles(_ count: Int) {
        guard count > 0 else { return }
        totalFiles += count
        emit()
    }

    func completeFile(byteCount: Int64 = 0) {
        completedFiles += 1
        downloadedBytes += max(0, byteCount)
        emit()
    }

    private func emit() {
        guard let handler else { return }
        let estimatedTotalBytes: Int64
        if completedFiles > 0, totalFiles > 0 {
            let average = Double(downloadedBytes) / Double(completedFiles)
            estimatedTotalBytes = Int64(average * Double(totalFiles))
        } else {
            estimatedTotalBytes = 0
        }
        handler(
            CatalogSyncProgressSnapshot(
                status: status,
                completedFiles: completedFiles,
                totalFiles: totalFiles,
                downloadedBytes: downloadedBytes,
                estimatedTotalBytes: estimatedTotalBytes
            )
        )
    }
}

/// Downloads catalog + per-set pricing into `CatalogStore`. Compares `sets.json` SHA256 to avoid full re-import when unchanged.
final class CatalogSyncCoordinator: @unchecked Sendable {
    static let shared = CatalogSyncCoordinator()

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Run after app launch: refresh catalog if needed, refresh pricing if stale (> 24h), then refresh daily blobs if stale (> 24h).
    func syncAllIfNeeded(
        progressHandler: (@Sendable (CatalogSyncProgressSnapshot) -> Void)? = nil
    ) async {
        let progress = CatalogSyncProgressReporter(handler: progressHandler)
        do {
            try CatalogStore.shared.open()
        } catch {
            return
        }
        await progress.setStatus("Checking card catalog…")
        await syncCatalogIfNeeded(progress: progress)
        await syncPricingIfNeeded(progress: progress)
        await syncDailyBlobsIfNeeded(progress: progress)
        await progress.setStatus("Finishing card setup…")
    }

    private func syncCatalogIfNeeded(progress: CatalogSyncProgressReporter) async {
        guard AppConfiguration.r2BaseURL.host != "invalid.local" else { return }
        let setsURL = AppConfiguration.r2CatalogURL(path: "sets.json")
        let (data, resp): (Data, URLResponse)
        await progress.setStatus("Checking card catalog…")
        await progress.addPlannedFiles(1)
        do {
            (data, resp) = try await session.data(from: setsURL)
            await progress.completeFile(byteCount: Int64(data.count))
        } catch {
            await progress.completeFile()
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
            await progress.addPlannedFiles(sets.count * 2)
            try store.clearCatalog()
            for set in sets {
                await progress.setStatus("Updating \(set.name)…")
                try store.upsertSet(set)
                let code = set.setCode
                let cardsURL = AppConfiguration.r2CatalogURL(path: "cards/\(code).json")
                if let (cData, _) = try? await session.data(from: cardsURL) {
                    let cards = try JSONDecoder().decode([Card].self, from: cData)
                    try store.insertCards(cards, setCode: code)
                    await progress.completeFile(byteCount: Int64(cData.count))
                } else {
                    await progress.completeFile()
                }
                var pricingBytes: Int64 = 0
                for stem in AppConfiguration.pricingFileStemVariants(for: code) {
                    let pURL = AppConfiguration.r2CardPricingSetJSONURL(setCodeStem: stem)
                    guard let (pData, resp) = try? await session.data(from: pURL),
                          let http = resp as? HTTPURLResponse,
                          (200...299).contains(http.statusCode),
                          !pData.isEmpty
                    else { continue }
                    try store.upsertPricing(setCode: code, json: pData)
                    pricingBytes = Int64(pData.count)
                    break
                }
                await progress.completeFile(byteCount: pricingBytes)
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

    private func syncPricingIfNeeded(progress: CatalogSyncProgressReporter) async {
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
        await progress.setStatus("Refreshing pricing data…")
        await progress.addPlannedFiles(sets.count)
        await withTaskGroup(of: (String, Data)?.self) { group in
            for set in sets {
                let code = set.setCode
                let stems = AppConfiguration.pricingFileStemVariants(for: code)
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
                guard let (code, data) = result else {
                    await progress.completeFile()
                    continue
                }
                try? store.upsertPricing(setCode: code, json: data)
                let _ = code
                await progress.completeFile(byteCount: Int64(data.count))
            }
        }
        try? store.setMeta("pricing_last_synced_at", String(Date().timeIntervalSince1970))
    }

    private func syncDailyBlobsIfNeeded(progress: CatalogSyncProgressReporter) async {
        guard AppConfiguration.r2BaseURL.host != "invalid.local" else { return }
        let store = CatalogStore.shared
        let day: TimeInterval = 24 * 60 * 60
        let keys: [(String, URL)] = [
            (DailyBlobKey.pokedataEnglishPokemonPrices, AppConfiguration.r2MarketURL(path: DailyBlobPath.pokedataEnglishPokemonPrices)),
            (DailyBlobKey.priceTrends, AppConfiguration.r2MarketURL(path: DailyBlobPath.priceTrends)),
        ]
        let staleKeys = keys.filter { key, _ in
            guard let last = store.dailyBlobFetchedAt(key: key) else { return true }
            return Date().timeIntervalSince(last) >= day
        }
        guard !staleKeys.isEmpty else { return }
        await progress.setStatus("Refreshing daily market data…")
        await progress.addPlannedFiles(staleKeys.count)
        for (key, url) in staleKeys {
            if let (data, _) = try? await session.data(from: url), !data.isEmpty {
                try? store.upsertDailyBlob(key: key, data: data)
                await progress.completeFile(byteCount: Int64(data.count))
            } else {
                await progress.completeFile()
            }
        }
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
