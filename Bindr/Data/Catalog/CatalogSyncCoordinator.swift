import CryptoKit
import Foundation

/// R2 market pricing and per-set price history/trends are published once per calendar day after **03:00** in the user's local time zone.
/// We refresh SQLite the first time the app runs in a new period (after that boundary).
enum DailyMarketPricingSchedule {
    private static let boundaryHour = 3
    private static let boundaryMinute = 0

    /// Start of the active pricing period containing `now` (the most recent 03:00 local on or before `now`).
    static func currentPeriodStart(now: Date = Date(), calendar: Calendar = .current) -> Date {
        let cal = calendar
        let comps = cal.dateComponents([.year, .month, .day], from: now)
        guard let dayStart = cal.date(from: comps),
              let threeToday = cal.date(
                  bySettingHour: boundaryHour,
                  minute: boundaryMinute,
                  second: 0,
                  of: dayStart
              )
        else {
            return now
        }
        if now >= threeToday {
            return threeToday
        }
        return cal.date(byAdding: .day, value: -1, to: threeToday) ?? threeToday
    }

    /// `true` if we have not recorded a sync on or after the current period start (missing key, or last sync before this period's 03:00).
    static func needsRefreshAfterNewPeriod(lastSync: Date?, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        let periodStart = currentPeriodStart(now: now, calendar: calendar)
        guard let last = lastSync else { return true }
        return last < periodStart
    }
}

struct CatalogSyncProgressSnapshot: Sendable {
    let status: String
    let completedFiles: Int
    let totalFiles: Int
    let downloadedBytes: Int64
    let estimatedTotalBytes: Int64
    let fractionCompleted: Double
}

actor CatalogSyncProgressReporter {
    typealias Handler = @MainActor @Sendable (CatalogSyncProgressSnapshot) -> Void

    private let handler: Handler?
    private var status: String = "Preparing card data..."
    private var completedFiles = 0
    private var totalFiles = 0
    private var downloadedBytes: Int64 = 0
    // Synthetic completed offset: when a new phase adds files we bump this so
    // the fraction never visibly goes backward.
    private var completedOffset = 0

    init(handler: Handler?) {
        self.handler = handler
    }

    func setStatus(_ status: String) async {
        self.status = status
        await emit()
    }

    func addPlannedFiles(_ count: Int) async {
        guard count > 0 else { return }
        // Before expanding totalFiles, capture the current fraction and ensure
        // completedOffset is large enough that the new fraction is >= the old one.
        let currentFraction: Double = totalFiles > 0
            ? Double(completedFiles + completedOffset) / Double(totalFiles)
            : 0
        totalFiles += count
        // Solve: (completedFiles + completedOffset) / totalFiles >= currentFraction
        let neededCompleted = Int((currentFraction * Double(totalFiles)).rounded(.up))
        if neededCompleted > completedFiles + completedOffset {
            completedOffset = neededCompleted - completedFiles
        }
        await emit()
    }

    func completeFile(byteCount: Int64 = 0) async {
        completedFiles += 1
        downloadedBytes += max(0, byteCount)
        await emit()
    }

    private func emit() async {
        guard let handler else { return }
        let fraction: Double = totalFiles > 0
            ? min(1, Double(completedFiles + completedOffset) / Double(totalFiles))
            : 0
        let snapshot = CatalogSyncProgressSnapshot(
            status: status,
            completedFiles: completedFiles,
            totalFiles: totalFiles,
            downloadedBytes: downloadedBytes,
            estimatedTotalBytes: downloadedBytes,
            fractionCompleted: fraction
        )
        await MainActor.run { handler(snapshot) }
    }
}

/// Thin orchestrator: delegates to phase structs, owns only public API and shared HTTP helpers.
final class CatalogSyncCoordinator: @unchecked Sendable {
    static let shared = CatalogSyncCoordinator()

    private let session: URLSession

    enum ConditionalJSONFetchResult {
        case downloaded(Data)
        case unchanged
        case unavailable
    }

    init(session: URLSession = AppURLSession.catalog) {
        self.session = session
    }

    // MARK: - Public API

    func requiresDailyBlockingRefreshAsync(enabledBrands: Set<TCGBrand>) async -> Bool {
        guard !enabledBrands.isEmpty else { return false }
        guard AppConfiguration.r2BaseURL.host != "invalid.local" else { return false }
        let store = CatalogStore.shared
        try? await store.open()

        let lastPricingSync: Date? = {
            guard let raw = store.metaSync("pricing_last_synced_at"),
                  let ts = Double(raw) else { return nil }
            return Date(timeIntervalSince1970: ts)
        }()
        let needsPricingRefresh = DailyMarketPricingSchedule.needsRefreshAfterNewPeriod(lastSync: lastPricingSync)
        if needsPricingRefresh { return true }

        if enabledBrands.contains(.pokemon) {
            // Sealed prices only come from daily R2 buckets. A background refresh at 03:15 can
            // run before today's file exists; without this gate the foreground launch would skip
            // sync because pricing_last_synced_at and sealed blob fetched_at were already bumped.
            let todayUTC = BucketDateMath.todayUTCKey()
            if store.metaSync(DailyBlobKey.sealedPricesAsOfDate) != todayUTC {
                return true
            }
        }

        let periodStart = DailyMarketPricingSchedule.currentPeriodStart(now: Date(), calendar: .current)
        var dailyKeys: [String] = [DailyBlobKey.priceTrends, DailyBlobKey.marketTrend]
        if enabledBrands.contains(.pokemon) {
            dailyKeys.append(contentsOf: [
                DailyBlobKey.pokedataEnglishPokemonProducts,
                DailyBlobKey.sealedPrices,
                DailyBlobKey.sealedPriceHistory,
            ])
        }

        for key in dailyKeys {
            guard let fetchedAt = await store.dailyBlobFetchedAt(key: key),
                  fetchedAt >= periodStart else {
                return true
            }
        }
        return false
    }

    func syncAllIfNeeded(
        enabledBrands: Set<TCGBrand>,
        progressHandler: (@MainActor @Sendable (CatalogSyncProgressSnapshot) -> Void)? = nil
    ) async {
        let store = CatalogStore.shared
        let progress = CatalogSyncProgressReporter(handler: progressHandler)

        // Pre-open and pre-announce total file count so the progress bar starts at 0
        // with a realistic denominator rather than creeping up as each phase discovers its work.
        if !enabledBrands.isEmpty {
            try? await store.open()
            let pricingPhase = MarketPricingSyncPhase(session: session, store: store)
            let blobPhase = DailyBlobSyncPhase(session: session, store: store)
            let pricingCount = await pricingPhase.estimatedFileCount(enabledBrands: enabledBrands)
            let blobCount = await blobPhase.estimatedFileCount(enabledBrands: enabledBrands)
            let catalogCount = 2 // sets.json + one placeholder for per-set cards
            await progress.addPlannedFiles(catalogCount + pricingCount + blobCount)
        }

        // Open the store once before branching so both catalog phases start with an open DB.
        if enabledBrands.contains(.pokemon) || enabledBrands.contains(.onePiece) {
            try? await store.open()
        }

        // Run catalog version check (Pokémon-only) before both phases so neither
        // phase races on the ETags that checkAndApply clears.
        if enabledBrands.contains(.pokemon) {
            await progress.setStatus("Checking card catalog…")
            await checkAndApplyCatalogVersionIfNeeded(store: store)
        }

        // Both catalog phases fetch entirely independent URLs and write to separate
        // SQLite namespaces, so they can run concurrently.
        async let pokemonCatalogDone: Void = {
            guard enabledBrands.contains(.pokemon) else { return }
            let phase = PokemonCatalogSyncPhase(session: session, store: store)
            await phase.syncCatalogIfNeeded(progress: progress)
            await phase.refreshNationalDexMetadata()
        }()
        async let onePieceCatalogDone: Void = {
            guard enabledBrands.contains(.onePiece) else { return }
            let phase = OnePieceCatalogSyncPhase(session: session, store: store)
            await phase.syncCatalogIfNeeded(progress: progress)
        }()
        _ = await (pokemonCatalogDone, onePieceCatalogDone)

        if !enabledBrands.isEmpty {
            try? await store.open()
            let pricingPhase = MarketPricingSyncPhase(session: session, store: store)
            let blobPhase = DailyBlobSyncPhase(session: session, store: store)
            async let pricingResult = pricingPhase.syncAllIfNeeded(progress: progress, enabledBrands: enabledBrands)
            async let blobResult = blobPhase.syncIfNeeded(progress: progress, enabledBrands: enabledBrands)
            _ = await (pricingResult, blobResult)
        }
        await progress.setStatus("Finishing card setup…")
    }

    func fillMissingSetCards(for brand: TCGBrand) async {
        guard AppConfiguration.r2BaseURL.host != "invalid.local" else { return }
        let store = CatalogStore.shared
        try? await store.open()
        switch brand {
        case .pokemon:
            await PokemonCatalogSyncPhase(session: session, store: store).fillMissingSetCards()
        case .onePiece:
            break
        }
    }

    func forceCardDataRefresh(
        enabledBrands: Set<TCGBrand>,
        progressHandler: (@MainActor @Sendable (CatalogSyncProgressSnapshot) -> Void)? = nil
    ) async -> Bool {
        guard AppConfiguration.r2BaseURL.host != "invalid.local" else { return false }
        guard !enabledBrands.isEmpty else { return false }
        let store = CatalogStore.shared
        try? await store.open()

        let progress = CatalogSyncProgressReporter(handler: progressHandler)
        await progress.setStatus("Checking card data updates…")

        var downloaded: Int64 = 0
        if enabledBrands.contains(.pokemon) {
            downloaded += await PokemonCatalogSyncPhase(session: session, store: store).syncCatalogCardDeltas(progress: progress)
        }
        if enabledBrands.contains(.onePiece) {
            downloaded += await OnePieceCatalogSyncPhase(session: session, store: store).syncCatalogCardDeltas(progress: progress)
        }

        let pricingPhase = MarketPricingSyncPhase(session: session, store: store)
        let blobPhase = DailyBlobSyncPhase(session: session, store: store)
        let refreshTotal: Int64 =
            await pricingPhase.syncAllIfNeeded(progress: progress, enabledBrands: enabledBrands, forceRefresh: true) +
            (await blobPhase.syncIfNeeded(progress: progress, enabledBrands: enabledBrands, forceRefresh: true))

        let totalDownloaded = downloaded + refreshTotal
        if downloaded > 0 {
            try? await store.setMeta("catalog_cards_last_updated_at", String(Date().timeIntervalSince1970))
        }
        await progress.setStatus("Finishing card setup…")
        return totalDownloaded > 0
    }

    func forceMarketTrendRefresh(
        enabledBrands: Set<TCGBrand>,
        progressHandler: (@MainActor @Sendable (CatalogSyncProgressSnapshot) -> Void)? = nil
    ) async {
        guard AppConfiguration.r2BaseURL.host != "invalid.local" else { return }
        let store = CatalogStore.shared
        try? await store.open()
        let progress = CatalogSyncProgressReporter(handler: progressHandler)
        _ = await DailyBlobSyncPhase(session: session, store: store).syncIfNeeded(progress: progress, enabledBrands: enabledBrands, forceRefresh: true)
    }

    /// Re-downloads market pricing, daily buckets, and trend blobs from R2 (skips the 03:00 schedule gate). Does not refresh card catalog JSON.
    func forcePricingRefresh(
        enabledBrands: Set<TCGBrand>,
        progressHandler: (@MainActor @Sendable (CatalogSyncProgressSnapshot) -> Void)? = nil
    ) async -> Bool {
        guard AppConfiguration.r2BaseURL.host != "invalid.local" else { return false }
        guard !enabledBrands.isEmpty else { return false }
        let store = CatalogStore.shared
        try? await store.open()

        let progress = CatalogSyncProgressReporter(handler: progressHandler)
        await progress.setStatus("Refreshing pricing from R2…")

        let pricingPhase = MarketPricingSyncPhase(session: session, store: store)
        let blobPhase = DailyBlobSyncPhase(session: session, store: store)
        let pricingCount = await pricingPhase.estimatedFileCount(enabledBrands: enabledBrands, forceRefresh: true)
        let blobCount = await blobPhase.estimatedFileCount(enabledBrands: enabledBrands, forceRefresh: true)
        await progress.addPlannedFiles(pricingCount + blobCount)

        let downloaded: Int64 =
            await pricingPhase.syncAllIfNeeded(progress: progress, enabledBrands: enabledBrands, forceRefresh: true) +
            (await blobPhase.syncIfNeeded(progress: progress, enabledBrands: enabledBrands, forceRefresh: true))

        await progress.setStatus("Pricing refresh complete.")
        return downloaded > 0
    }

    // MARK: - Shared helpers (used by phase structs)

    static func fetchJSONWithETag(
        url: URL,
        etagMetaKey: String,
        store: CatalogStore,
        session: URLSession
    ) async -> ConditionalJSONFetchResult {
        do {
            var request = URLRequest(url: url)
            if let prevEtag = await store.meta(etagMetaKey), !prevEtag.isEmpty {
                request.setValue(prevEtag, forHTTPHeaderField: "If-None-Match")
            }
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .unavailable }
            if http.statusCode == 304 {
                if let etag = http.value(forHTTPHeaderField: "ETag") ?? http.value(forHTTPHeaderField: "Etag") {
                    try? await store.setMeta(etagMetaKey, etag)
                }
                return .unchanged
            }
            guard (200...299).contains(http.statusCode), !data.isEmpty else { return .unavailable }
            if let etag = http.value(forHTTPHeaderField: "ETag") ?? http.value(forHTTPHeaderField: "Etag") {
                try? await store.setMeta(etagMetaKey, etag)
            }
            return .downloaded(data)
        } catch {
            return .unavailable
        }
    }

    static func etagMetaKey(brand: TCGBrand, kind: String, setCode: String) -> String {
        let normalizedCode = setCode.lowercased().map { ch in
            ch.isLetter || ch.isNumber ? ch : "_"
        }
        return "etag_\(brand.rawValue)_\(kind)_\(String(normalizedCode))"
    }

    static func fetchHTTPBodyIfOK(session: URLSession, url: URL) async -> Data? {
        do {
            let (data, resp) = try await session.data(from: url)
            guard let http = resp as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  !data.isEmpty else { return nil }
            return data
        } catch { return nil }
    }

    // MARK: - Private

    private func checkAndApplyCatalogVersionIfNeeded(store: CatalogStore) async {
        guard AppConfiguration.r2BaseURL.host != "invalid.local" else { return }
        guard let data = await Self.fetchHTTPBodyIfOK(session: session, url: AppConfiguration.r2CatalogVersionURL),
              let text = String(data: data, encoding: .utf8)
        else { return }

        guard let remoteVersion = Self.parseCatalogVersion(from: text) else { return }

        let storedVersion: Int
        if let s = await store.meta("catalog_version"), let v = Int(s) {
            storedVersion = v
        } else {
            storedVersion = 0
        }
        guard remoteVersion > storedVersion else { return }

        // Invalidate the sets.json hash/etag so syncCatalogIfNeeded re-checks the set list.
        // Per-set card ETags are left intact — the server returns 304 for unchanged sets
        // and new content only for sets that actually changed.
        try? await store.setMeta("catalog_sets_sha256", "")
        try? await store.setMeta("catalog_etag", "")

        // Clear pricing sync date so the period refresh runs unconditionally on next launch,
        // re-fetching sealed products list, market trend, and per-set price trends.
        try? await store.setMeta("pricing_last_synced_at", "")

        // Clear ETags and reset fetched_at for daily blobs so they re-download on next sync
        // even if they were already fetched earlier today (the freshness gate checks fetched_at,
        // not the ETag, so clearing the ETag alone is not enough).
        for key in [DailyBlobKey.pokedataEnglishPokemonProducts, DailyBlobKey.marketTrend, DailyBlobKey.priceTrends] {
            try? await store.setMeta("daily_blob_http_etag_" + key, "")
            await store.staleDailyBlobFetchedAt(key: key)
        }

        // Clear backfill flags so any new sets added in this version get full weekly/monthly
        // price history. The backfill is efficient — existing sets' composite keys are already
        // in processed_pricing_buckets and are skipped; only new sets actually download.
        try? await store.setMeta("pricing_history_backfill_v1", "")
        try? await store.setMeta("sealed_pricing_history_backfill_v1", "")

        // Unmark today's pricing buckets so the next sync re-fetches them, picking up any
        // new cards or sealed products added in this catalog version.
        let todayKey = BucketDateMath.todayUTCKey()
        await store.unmarkBucketProcessed(key: todayKey)
        await store.unmarkBucketProcessed(key: "sealed/\(todayKey)")

        try? await store.setMeta("catalog_version", String(remoteVersion))
    }

    private static func parseCatalogVersion(from text: String) -> Int? {
        let line = text.components(separatedBy: .newlines).first(where: { $0.lowercased().contains("version") }) ?? text
        let digits = line.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        return Int(digits)
    }
}

enum DailyBlobKey {
    static let pokedataEnglishPokemonProducts = "pokedata_english_pokemon_products"
    static let priceTrends = "price_trends"
    static let marketTrend = "market_trend"
    static let sealedPrices = "sealed_prices"
    static let sealedPriceHistory = "sealed_price_history"
    /// UTC date key (`YYYY-MM-DD`) for the newest sealed daily bucket merged into `sealedPrices`.
    static let sealedPricesAsOfDate = "sealed_prices_as_of_date"
}

enum DailyBlobPath {
    static let pokedataEnglishPokemonProducts = "data/pokedata-english-pokemon-products.json"
    static let priceTrends = "data/price-trends.json"
    static let marketTrend = "new_pricing/market-trend.json"
}
