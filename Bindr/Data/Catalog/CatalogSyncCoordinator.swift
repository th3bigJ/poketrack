import CryptoKit
import Foundation

/// R2 market pricing and per-set price history/trends are published once per calendar day after **03:00** in the user’s local time zone.
/// We refresh SQLite the first time the app runs in a new period (after that boundary).
private enum DailyMarketPricingSchedule {
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

    /// `true` if we have not recorded a sync on or after the current period start (missing key, or last sync before this period’s 03:00).
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

    /// Smooth progress from bytes vs. total; avoids jumps when `totalFiles` grows mid-sync.
    let fractionCompleted: Double
}

private actor CatalogSyncProgressReporter {
    /// Called on the main actor so progress updates are applied in order (no coalesced “jump to 82%”).
    typealias Handler = @MainActor @Sendable (CatalogSyncProgressSnapshot) -> Void

    private let handler: Handler?
    private var status: String = "Preparing card data…"
    private var completedFiles = 0
    private var totalFiles = 0
    private var downloadedBytes: Int64 = 0
    /// Number of completed payloads that actually transferred body bytes (excludes 304/unchanged checks).
    private var completedBytePayloads = 0
    /// Only increases so the total size line does not shrink when the average shifts.
    private var peakEstimatedTotalBytes: Int64 = 0
    /// Never decreases so the bar does not move backward when phases add more planned work.
    private var peakFractionCompleted: Double = 0

    init(handler: Handler?) {
        self.handler = handler
    }

    func setStatus(_ status: String) async {
        self.status = status
        await emit()
    }

    func addPlannedFiles(_ count: Int) async {
        guard count > 0 else { return }
        totalFiles += count
        await emit()
    }

    func completeFile(byteCount: Int64 = 0) async {
        completedFiles += 1
        let positiveBytes = max(0, byteCount)
        downloadedBytes += positiveBytes
        if positiveBytes > 0 {
            completedBytePayloads += 1
        }
        await emit()
    }

    /// Delivers each snapshot on the main actor so SwiftUI does not coalesce async `Task { @MainActor }` updates into a single 100% frame.
    private func emit() async {
        guard let handler else { return }
        let naiveEstimate: Int64
        if completedBytePayloads > 0, totalFiles > 0 {
            let averagePayloadSize = Double(downloadedBytes) / Double(completedBytePayloads)
            naiveEstimate = Int64(averagePayloadSize * Double(totalFiles))
        } else {
            naiveEstimate = 0
        }
        peakEstimatedTotalBytes = max(peakEstimatedTotalBytes, naiveEstimate, downloadedBytes)
        let estimatedTotalBytes = peakEstimatedTotalBytes

        let byteFraction: Double
        if estimatedTotalBytes > 0 {
            byteFraction = min(1, Double(downloadedBytes) / Double(estimatedTotalBytes))
        } else {
            byteFraction = 0
        }
        // Launch bar should represent transferred bytes, not "checks completed".
        let blended = downloadedBytes > 0 ? byteFraction : 0
        peakFractionCompleted = max(peakFractionCompleted, blended)

        let snapshot = CatalogSyncProgressSnapshot(
            status: status,
            completedFiles: completedFiles,
            totalFiles: totalFiles,
            downloadedBytes: downloadedBytes,
            estimatedTotalBytes: estimatedTotalBytes,
            fractionCompleted: peakFractionCompleted
        )
        await MainActor.run {
            handler(snapshot)
        }
    }
}

/// Downloads catalog + per-set pricing into `CatalogStore`. Compares `sets.json` SHA256 to avoid full re-import when unchanged.
final class CatalogSyncCoordinator: @unchecked Sendable {
    static let shared = CatalogSyncCoordinator()
    private let pokemonNationalDexAuxBlobKey = "pokemon_national_dex_json"

    private let session: URLSession
    private enum ConditionalJSONFetchResult {
        case downloaded(Data)
        case unchanged
        case unavailable
    }

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Launch-gate predicate: `true` on the first app open after local 03:00 when market pricing/trends
    /// (or required daily blobs) must refresh before the app shell appears to avoid in-session value jumps.
    func requiresDailyBlockingRefresh(enabledBrands: Set<TCGBrand>) -> Bool {
        guard !enabledBrands.isEmpty else { return false }
        guard AppConfiguration.r2BaseURL.host != "invalid.local" else { return false }
        let store = CatalogStore.shared
        store.openSync()

        let lastPricingSync: Date? = {
            guard let raw = store.metaSync("pricing_last_synced_at"),
                  let ts = Double(raw) else { return nil }
            return Date(timeIntervalSince1970: ts)
        }()
        let needsPricingRefresh = DailyMarketPricingSchedule.needsRefreshAfterNewPeriod(lastSync: lastPricingSync)
        if needsPricingRefresh { return true }

        let periodStart = DailyMarketPricingSchedule.currentPeriodStart(now: Date(), calendar: .current)
        var dailyKeys: [String] = [DailyBlobKey.priceTrends, DailyBlobKey.marketTrend]
        if enabledBrands.contains(.pokemon) {
            dailyKeys.append(contentsOf: [
                DailyBlobKey.pokedataEnglishPokemonProducts,
                DailyBlobKey.pokedataEnglishPokemonPrices,
                DailyBlobKey.pokedataEnglishPokemonPriceHistory,
                DailyBlobKey.pokedataEnglishPokemonPriceTrends,
            ])
        }
        return dailyKeys.contains { key in
            guard let fetchedAt = store.dailyBlobFetchedAtSync(key: key) else { return true }
            return fetchedAt < periodStart
        }
    }

    /// Run after app launch: refresh catalog for **enabled** brands only (Pokémon → SQLite + pricing + daily blobs; ONE PIECE → card JSON on disk).
    func syncAllIfNeeded(
        enabledBrands: Set<TCGBrand>,
        progressHandler: (@MainActor @Sendable (CatalogSyncProgressSnapshot) -> Void)? = nil
    ) async {
        let progress = CatalogSyncProgressReporter(handler: progressHandler)
        if enabledBrands.contains(.pokemon) {
            do {
                try await CatalogStore.shared.open()
                await progress.setStatus("Checking card catalog…")
                await checkAndApplyCatalogVersionIfNeeded(store: CatalogStore.shared)
                await syncCatalogIfNeeded(progress: progress)
                await refreshPokemonNationalDexMetadata(store: CatalogStore.shared)
            } catch {
                // Local catalog DB unavailable; still prefetch ONE PIECE below if enabled.
            }
        }
        if enabledBrands.contains(.onePiece) {
            try? await CatalogStore.shared.open()
            await syncOnePieceCatalogIfNeeded(progress: progress)
        }
        // Per-set market JSON for every enabled brand, once per local day after 03:00 (same gate as daily blobs below).
        if !enabledBrands.isEmpty {
            try? await CatalogStore.shared.open()
            _ = await syncAllMarketPricingIfNeeded(progress: progress, enabledBrands: enabledBrands)
        }
        // Global market JSON (not franchise-specific) — run whenever any catalog is enabled, including ONE PIECE–only.
        if !enabledBrands.isEmpty {
            try? await CatalogStore.shared.open()
            _ = await syncDailyBlobsIfNeeded(progress: progress, enabledBrands: enabledBrands)
        }
        await progress.setStatus("Finishing card setup…")
    }

    /// Keeps Pokémon `pokemon.json` cached in SQLite (`sync_meta`) so runtime reads are local-first.
    /// Uses ETag validation to avoid re-downloading unchanged payloads.
    private func refreshPokemonNationalDexMetadata(store: CatalogStore) async {
        guard AppConfiguration.r2BaseURL.host != "invalid.local" else { return }
        let url = AppConfiguration.r2CatalogURL(path: "pokemon.json")
        do {
            var request = URLRequest(url: url)
            if let prevEtag = await store.meta("pokemon_national_dex_etag"), !prevEtag.isEmpty {
                request.setValue(prevEtag, forHTTPHeaderField: "If-None-Match")
            }
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return }
            if http.statusCode == 304 {
                try? await store.touchAuxBlobFetchedAt(key: pokemonNationalDexAuxBlobKey)
                return
            }
            guard (200...299).contains(http.statusCode), !data.isEmpty else { return }
            // Validate shape before persisting so runtime decode remains predictable.
            guard (try? JSONDecoder().decode([NationalDexPokemon].self, from: data)) != nil else { return }
            try? await store.upsertAuxBlob(key: pokemonNationalDexAuxBlobKey, data: data)
            if let etag = http.value(forHTTPHeaderField: "ETag") ?? http.value(forHTTPHeaderField: "Etag") {
                try? await store.setMeta("pokemon_national_dex_etag", etag)
            }
        } catch {
            // Keep the last successful local copy.
        }
    }

    /// User-invoked settings action: checks per-set card JSON immediately (no 03:00 gate),
    /// then forces market pricing/history/trends and daily market blobs.
    /// Returns `true` when at least one payload changed in local SQLite.
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
            downloaded += await syncPokemonCatalogCardDeltas(progress: progress, store: store)
        }
        if enabledBrands.contains(.onePiece) {
            downloaded += await syncOnePieceCatalogCardDeltas(progress: progress, store: store)
        }

        let marketDownloaded = await syncAllMarketPricingIfNeeded(
            progress: progress,
            enabledBrands: enabledBrands,
            forceRefresh: true
        )
        let dailyBlobDownloaded = await syncDailyBlobsIfNeeded(
            progress: progress,
            enabledBrands: enabledBrands,
            forceRefresh: true
        )

        let totalDownloaded = downloaded + marketDownloaded + dailyBlobDownloaded
        if downloaded > 0 {
            try? await store.setMeta("catalog_cards_last_updated_at", String(Date().timeIntervalSince1970))
        }
        await progress.setStatus("Finishing card setup…")
        return totalDownloaded > 0
    }

    /// Fetches `version.md`, parses `Version - N`, and if N is greater than the stored value
    /// clears the catalog SHA256/ETag guards so `syncCatalogIfNeeded` forces a full re-download.
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

        // Invalidate hash/etag guards and mark that all sets need re-downloading.
        try? await store.setMeta("catalog_sets_sha256", "")
        try? await store.setMeta("catalog_etag", "")
        try? await store.setMeta("catalog_force_full_download", "1")
        try? await store.setMeta("catalog_version", String(remoteVersion))
    }

    /// Parses `Version - N` (case-insensitive, whitespace-tolerant) from version.md text.
    private static func parseCatalogVersion(from text: String) -> Int? {
        let line = text.components(separatedBy: .newlines).first(where: { $0.lowercased().contains("version") }) ?? text
        let digits = line.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        return Int(digits)
    }

    private func syncCatalogIfNeeded(progress: CatalogSyncProgressReporter) async {
        guard AppConfiguration.r2BaseURL.host != "invalid.local" else { return }
        let setsURL = AppConfiguration.r2CatalogURL(path: "sets.json")
        let (data, resp): (Data, URLResponse)
        await progress.setStatus("Checking card catalog…")
        do {
            (data, resp) = try await session.data(from: setsURL)
        } catch {
            await progress.addPlannedFiles(2)
            await progress.completeFile()
            await progress.completeFile()
            return
        }
        let http = resp as? HTTPURLResponse
        let etag = http?.value(forHTTPHeaderField: "ETag") ?? http?.value(forHTTPHeaderField: "Etag")
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()

        let store = CatalogStore.shared
        try? await store.open()
        let storedSetsHash = await store.meta("catalog_sets_sha256")
        let storedSetsEtag = await store.meta("catalog_etag")
        let unchangedHash = storedSetsHash == hash
        let unchangedEtag = etag != nil && storedSetsEtag == etag
        let hasCards = (try? await store.hasAnyCards(for: .pokemon)) ?? false
        if hasCards && (unchangedHash || unchangedEtag) {
            // Two steps so progress never reads 100% after a single "file" (index already up to date).
            await progress.addPlannedFiles(2)
            await progress.completeFile(byteCount: Int64(data.count))
            await progress.completeFile(byteCount: 0)
            return
        }

        let sets: [TCGSet]
        do {
            sets = try JSONDecoder().decode([TCGSet].self, from: data)
        } catch {
            await progress.addPlannedFiles(2)
            await progress.completeFile(byteCount: Int64(data.count))
            await progress.completeFile(byteCount: 0)
            return
        }

        do {
            try await store.open()
            // 1. Identify which sets actually need their cards downloaded/updated
            let forceFullDownload = (await store.meta("catalog_force_full_download")) == "1"
            if forceFullDownload {
                try? await store.setMeta("catalog_force_full_download", "")
            }

            let existingSets = try await store.fetchAllSets(for: .pokemon)
            let existingCodes = Set(existingSets.map(\.setCode))

            // On a version bump download all sets; otherwise only new/empty ones.
            var setsToDownload: [TCGSet] = []
            let setsWithNoCards = try await store.fetchSetCodesWithNoCards(for: .pokemon)
            for set in sets {
                let hasCards = !setsWithNoCards.contains(set.setCode)
                if forceFullDownload || !existingCodes.contains(set.setCode) || !hasCards {
                    setsToDownload.append(set)
                }
            }

            await progress.addPlannedFiles(1 + setsToDownload.count)
            await progress.completeFile(byteCount: Int64(data.count))
            
            // 2. Upsert the set metadata first
            for set in sets {
                try await store.upsertSet(set, brand: .pokemon)
            }
            
            if setsToDownload.isEmpty {
                // If no sets need card downloads, we still need to complete the progress bar
                try await store.setMeta("catalog_sets_sha256", hash)
                if let etag { try await store.setMeta("catalog_etag", etag) }
                return
            }

            // 3. Download cards for the delta sets only (pricing comes from daily bucket sync)
            let sess = session
            try await withThrowingTaskGroup(of: (String, Data?).self) { group in
                for set in setsToDownload {
                    let code = set.setCode
                    group.addTask {
                        let cardsURL = AppConfiguration.r2CatalogURL(path: "cards/\(code).json")
                        let cardsData = try? await sess.data(from: cardsURL).0
                        return (code, cardsData)
                    }
                }

                for try await (code, cardsData) in group {
                    if let cardsData, let cards = try? JSONDecoder().decode([Card].self, from: cardsData) {
                        try await store.insertCards(cards, setCode: code, brand: .pokemon)
                        await progress.completeFile(byteCount: Int64(cardsData.count))
                    } else {
                        await progress.completeFile()
                    }
                }
            }
            
            try await store.setMeta("catalog_sets_sha256", hash)
            if let etag {
                try await store.setMeta("catalog_etag", etag)
            }
            try await store.setMeta("catalog_import_at", String(Date().timeIntervalSince1970))
        } catch {
            try? await store.setMeta("sync_failed", "1")
        }
    }

    /// Imports ONE PIECE sets, cards, and per-set market pricing into SQLite (`brand = onepiece`).
    private func syncOnePieceCatalogIfNeeded(progress: CatalogSyncProgressReporter) async {
        guard AppConfiguration.r2BaseURL.host != "invalid.local" else { return }
        let store = CatalogStore.shared
        await refreshOnePieceBrowseMetadata(store: store)
        let setsURL = AppConfiguration.r2OnePieceURL(path: "sets/data/sets.json")
        await progress.setStatus("Checking ONE PIECE catalog…")
        let data: Data
        let http: HTTPURLResponse?
        do {
            var request = URLRequest(url: setsURL)
            if let prevEtagHeader = await store.meta("onepiece_catalog_sets_etag"), !prevEtagHeader.isEmpty {
                request.setValue(prevEtagHeader, forHTTPHeaderField: "If-None-Match")
            }
            let pair = try await session.data(for: request)
            var d = pair.0
            var h = pair.1 as? HTTPURLResponse

            if h?.statusCode == 304 {
                let hasLocalCards = (try? await store.hasAnyCards(for: .onePiece)) ?? false
                if hasLocalCards {
                    // Server agrees our cached catalog index is current — skip re-downloading every set JSON (~multi‑MB).
                    await progress.addPlannedFiles(2)
                    await progress.completeFile(byteCount: 0)
                    await progress.completeFile(byteCount: 0)
                    if let e = h?.value(forHTTPHeaderField: "ETag") ?? h?.value(forHTTPHeaderField: "Etag") {
                        try? await store.setMeta("onepiece_catalog_sets_etag", e)
                    }
                    // Patch any sets whose card download failed in a prior sync.
                    let emptyCodes = (try? await store.fetchSetCodesWithNoCards(for: .onePiece)) ?? []
                    if !emptyCodes.isEmpty {
                        await patchMissingOnePieceCards(setCodes: emptyCodes, store: store, progress: progress)
                    }
                    return
                }
                // No local rows but got 304 (odd): fetch a full representation without conditional headers.
                let pair2 = try await session.data(from: setsURL)
                d = pair2.0
                h = pair2.1 as? HTTPURLResponse
            }
            data = d
            http = h
        } catch {
            await progress.addPlannedFiles(2)
            await progress.completeFile()
            await progress.completeFile()
            return
        }
        guard let code = http?.statusCode, (200...299).contains(code), !data.isEmpty else {
            await progress.addPlannedFiles(2)
            await progress.completeFile()
            await progress.completeFile()
            return
        }
        let etag = http?.value(forHTTPHeaderField: "ETag") ?? http?.value(forHTTPHeaderField: "Etag")
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let storedOPHash = await store.meta("onepiece_catalog_sets_sha256")
        let storedOPEtag = await store.meta("onepiece_catalog_sets_etag")
        let unchangedHash = storedOPHash == hash
        let unchangedEtag = etag != nil && storedOPEtag == etag
        let hasCards = (try? await store.hasAnyCards(for: .onePiece)) ?? false
        // Same-bytes / same-ETag fast path (Pokémon-style) when we did get a 200 body this run.
        if hasCards && (unchangedHash || unchangedEtag) {
            if let rows = try? JSONDecoder().decode([OnePieceSetRow].self, from: data) {
                let fp = Self.onePieceCatalogFingerprint(from: rows)
                try? await store.setMeta("onepiece_catalog_row_fingerprint", fp)
            }
            await progress.addPlannedFiles(2)
            await progress.completeFile(byteCount: Int64(data.count))
            await progress.completeFile(byteCount: 0)
            if let etag {
                try? await store.setMeta("onepiece_catalog_sets_etag", etag)
            }
            // Even though the catalog index is unchanged, individual set card downloads may have
            // failed on a prior sync (e.g. OP15 set exists in DB but its cards never downloaded).
            // Patch only the empty sets so a partial failure self-heals without a full re-import.
            let emptyCodes = (try? await store.fetchSetCodesWithNoCards(for: .onePiece)) ?? []
            if !emptyCodes.isEmpty {
                await patchMissingOnePieceCards(setCodes: emptyCodes, store: store, progress: progress)
            }
            return
        }

        let rows: [OnePieceSetRow]
        do {
            rows = try JSONDecoder().decode([OnePieceSetRow].self, from: data)
        } catch {
            await progress.addPlannedFiles(2)
            await progress.completeFile(byteCount: Int64(data.count))
            await progress.completeFile(byteCount: 0)
            return
        }

        let rowFingerprint = Self.onePieceCatalogFingerprint(from: rows)
        let storedFp = await store.meta("onepiece_catalog_row_fingerprint")
        let localFp: String? = await {
            guard let sets = try? await store.fetchAllSets(for: .onePiece), !sets.isEmpty else { return nil }
            return Self.onePieceCatalogFingerprint(fromSetCodes: sets.map(\.setCode))
        }()
        let catalogStructureUnchanged =
            (storedFp == rowFingerprint) || (storedFp == nil && localFp == rowFingerprint)
        if hasCards && catalogStructureUnchanged {
            try? await store.setMeta("onepiece_catalog_sets_sha256", hash)
            if let etag {
                try? await store.setMeta("onepiece_catalog_sets_etag", etag)
            }
            try? await store.setMeta("onepiece_catalog_row_fingerprint", rowFingerprint)
            await progress.addPlannedFiles(2)
            await progress.completeFile(byteCount: Int64(data.count))
            await progress.completeFile(byteCount: 0)
            // Same as above: patch any sets that are registered but have no cards.
            let emptyCodes = (try? await store.fetchSetCodesWithNoCards(for: .onePiece)) ?? []
            if !emptyCodes.isEmpty {
                await patchMissingOnePieceCards(setCodes: emptyCodes, store: store, progress: progress)
            }
            return
        }

        await progress.addPlannedFiles(1 + rows.count * 2)
        await progress.completeFile(byteCount: Int64(data.count))

        do {
            var existingPricingBySetCode: [String: Data] = [:]
            if let existingSets = try? await store.fetchAllSets(for: .onePiece) {
                for existing in existingSets {
                    if let pricing = await store.fetchPricingData(setCode: existing.setCode, brand: .onePiece) {
                        existingPricingBySetCode[existing.setCode] = pricing
                    }
                }
            }
            try await store.purgeCatalogTables(for: .onePiece)
            for row in rows {
                try await store.upsertSet(row.asTCGSet(), brand: .onePiece)
            }
            let sess = session
            try await withThrowingTaskGroup(of: (String, Data?, Data?).self) { group in
                for row in rows {
                    let code = row.setCode
                    group.addTask {
                        let cardsURL = AppConfiguration.r2OnePieceURL(path: "cards/data/\(code).json")
                        let cardsData: Data?
                        if let (data, _) = try? await sess.data(from: cardsURL), !data.isEmpty {
                            cardsData = data
                        } else {
                            cardsData = nil
                        }

                        var pricingData: Data?
                        for stem in Self.onePiecePricingStemVariants(for: code) {
                            let pURL = AppConfiguration.r2OnePieceMarketPricingSetURL(setCodeStem: stem)
                            guard let (pData, resp) = try? await sess.data(from: pURL),
                                  let http = resp as? HTTPURLResponse,
                                  (200...299).contains(http.statusCode),
                                  !pData.isEmpty
                            else { continue }
                            pricingData = pData
                            break
                        }
                        return (code, cardsData, pricingData)
                    }
                }
                for try await (code, cardsData, pricingData) in group {
                    if let cardsData, let dtos = try? JSONDecoder().decode([OnePieceCardDTO].self, from: cardsData) {
                        let cards = dtos.map { OnePieceCatalogMapping.card(from: $0) }
                        try await store.insertCards(cards, setCode: code, brand: .onePiece)
                        await progress.completeFile(byteCount: Int64(cardsData.count))
                    } else {
                        await progress.completeFile()
                    }

                    if let pricingData {
                        try await store.upsertPricing(setCode: code, json: pricingData, brand: .onePiece)
                        await progress.completeFile(byteCount: Int64(pricingData.count))
                    } else if let fallbackPricing = existingPricingBySetCode[code] {
                        // Keep yesterday's pricing when today's per-set pricing fetch fails.
                        try await store.upsertPricing(setCode: code, json: fallbackPricing, brand: .onePiece)
                        await progress.completeFile(byteCount: 0)
                    } else {
                        await progress.completeFile()
                    }
                }
            }
            try await store.setMeta("onepiece_catalog_sets_sha256", hash)
            if let etag {
                try await store.setMeta("onepiece_catalog_sets_etag", etag)
            }
            try await store.setMeta("onepiece_catalog_row_fingerprint", rowFingerprint)
        } catch {
            // Leave partial; browse may be empty until next sync.
            // Mark sync as failed so next launch retries
            try? await store.setMeta("sync_failed", "1")
        }
    }

    /// Keeps ONE PIECE browse metadata local in SQLite so search/browse can read it offline and avoid live R2 fetches.
    private func refreshOnePieceBrowseMetadata(store: CatalogStore) async {
        await refreshOnePieceBrowseMetadataFile(
            path: "character-names.json",
            jsonMetaKey: "onepiece_character_names_json",
            etagMetaKey: "onepiece_character_names_etag",
            store: store
        )
        await refreshOnePieceBrowseMetadataFile(
            path: "character-subtypes.json",
            jsonMetaKey: "onepiece_character_subtypes_json",
            etagMetaKey: "onepiece_character_subtypes_etag",
            store: store
        )
    }

    private func refreshOnePieceBrowseMetadataFile(
        path: String,
        jsonMetaKey: String,
        etagMetaKey: String,
        store: CatalogStore
    ) async {
        let url = AppConfiguration.r2OnePieceBrowseMetadataURL(path: path)
        var request = URLRequest(url: url)
        if let prevEtag = await store.meta(etagMetaKey), !prevEtag.isEmpty {
            request.setValue(prevEtag, forHTTPHeaderField: "If-None-Match")
        }
        if let (data, resp) = try? await session.data(for: request) {
            let http = resp as? HTTPURLResponse
            if http?.statusCode == 200, !data.isEmpty {
                try? await store.setMetaData(jsonMetaKey, data: data)
                if let etag = http?.value(forHTTPHeaderField: "ETag") ?? http?.value(forHTTPHeaderField: "Etag") {
                    try? await store.setMeta(etagMetaKey, etag)
                }
            }
        }
        // Keep the last successful local copy when offline / on error.
    }


    /// Downloads and inserts card JSON for ONE PIECE sets that are registered in the DB but have no cards.
    /// Called after both skip paths so a failed card download from a previous sync self-heals.
    private func patchMissingOnePieceCards(setCodes: [String], store: CatalogStore, progress: CatalogSyncProgressReporter) async {
        await progress.addPlannedFiles(setCodes.count)
        for code in setCodes {
            let cardsURL = AppConfiguration.r2OnePieceURL(path: "cards/data/\(code).json")
            guard let (cData, _) = try? await session.data(from: cardsURL), !cData.isEmpty,
                  let dtos = try? JSONDecoder().decode([OnePieceCardDTO].self, from: cData)
            else {
                await progress.completeFile()
                continue
            }
            let cards = dtos.map { OnePieceCatalogMapping.card(from: $0) }
            try? await store.insertCards(cards, setCode: code, brand: .onePiece)
            await progress.completeFile(byteCount: Int64(cData.count))
        }
    }

    /// Stable fingerprint of which sets exist (order-independent). Raw `sets.json` bytes can change without changing this.
    private static func onePieceCatalogFingerprint(fromSetCodes codes: [String]) -> String {
        let payload = codes.sorted().joined(separator: "\n").data(using: .utf8) ?? Data()
        return SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
    }

    private static func onePieceCatalogFingerprint(from rows: [OnePieceSetRow]) -> String {
        onePieceCatalogFingerprint(fromSetCodes: rows.map(\.setCode))
    }

    private static func onePiecePricingStemVariants(for setCode: String) -> [String] {
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

    /// Refreshes per-set market pricing JSON plus per-set price history and trends for **all** enabled brands using one daily gate (`pricing_last_synced_at`).
    /// After an app update, a one-time pass downloads history/trends only (`pricing_aux_sqlite_v1`) so charts work before the next 03:00 boundary.
    private func syncAllMarketPricingIfNeeded(
        progress: CatalogSyncProgressReporter,
        enabledBrands: Set<TCGBrand>,
        forceRefresh: Bool = false
    ) async -> Int64 {
        guard AppConfiguration.r2BaseURL.host != "invalid.local" else { return 0 }
        let store = CatalogStore.shared
        let last = await lastMarketPricingSyncDate(store: store)
        let needsPeriodRefresh = DailyMarketPricingSchedule.needsRefreshAfterNewPeriod(lastSync: last)
        let needsAuxBackfill = (await store.meta("pricing_aux_sqlite_v1")) != "1"
        let shouldRunPeriodRefresh = forceRefresh || needsPeriodRefresh
        let shouldRunAuxBackfill = !forceRefresh && needsAuxBackfill
        guard shouldRunPeriodRefresh || shouldRunAuxBackfill else { return 0 }

        await progress.setStatus("Refreshing pricing data…")
        if shouldRunPeriodRefresh {
            var downloaded: Int64 = 0
            // Daily (post-03:00) delta check for per-set card JSON. This catches card catalog edits
            // even when a set list file is unchanged, while avoiding full re-downloads via ETag.
            if enabledBrands.contains(.pokemon) {
                downloaded += await syncPokemonCatalogCardDeltas(progress: progress, store: store)
            }
            if enabledBrands.contains(.onePiece) {
                downloaded += await syncOnePieceCatalogCardDeltas(progress: progress, store: store)
            }
            if enabledBrands.contains(.pokemon) {
                downloaded += await syncPokemonMarketPricingFullRefresh(progress: progress, store: store)
                downloaded += await syncPricingBuckets(store: store)
            }
            if enabledBrands.contains(.onePiece) {
                downloaded += await syncOnePieceMarketPricingFullRefresh(progress: progress, store: store)
            }
            try? await store.setMeta("pricing_last_synced_at", String(Date().timeIntervalSince1970))
            try? await store.setMeta("pricing_aux_sqlite_v1", "1")
            return downloaded
        } else if shouldRunAuxBackfill {
            var downloaded: Int64 = 0
            if enabledBrands.contains(.pokemon) {
                downloaded += await syncPokemonHistoryTrendsOnly(progress: progress, store: store)
                downloaded += await syncPricingBuckets(store: store)
            }
            if enabledBrands.contains(.onePiece) {
                downloaded += await syncOnePieceHistoryTrendsOnly(progress: progress, store: store)
            }
            // Avoid marking complete offline: retry chart backfill on a later launch when networked.
            if downloaded > 0 {
                try? await store.setMeta("pricing_aux_sqlite_v1", "1")
            }
            return downloaded
        }
        return 0
    }

    private func lastMarketPricingSyncDate(store: CatalogStore) async -> Date? {
        guard let s = await store.meta("pricing_last_synced_at"), let t = Double(s) else { return nil }
        return Date(timeIntervalSince1970: t)
    }

    /// Downloads per-set price trends from `new_pricing/price-trends/{setCode}.json` into SQLite.
    /// Per-set card pricing is now handled by `syncPricingBuckets` (built from daily bucket files).
    private func syncPokemonMarketPricingFullRefresh(progress: CatalogSyncProgressReporter, store: CatalogStore) async -> Int64 {
        let sets: [TCGSet]
        do {
            sets = try await store.fetchAllSets(for: .pokemon)
        } catch {
            return 0
        }
        guard !sets.isEmpty else { return 0 }
        var downloaded: Int64 = 0
        await progress.addPlannedFiles(sets.count)
        let sess = session
        await withTaskGroup(of: Int64.self) { group in
            for set in sets {
                let code = set.setCode
                group.addTask {
                    var totalBytes: Int64 = 0
                    for tStem in AppConfiguration.pricingFileStemVariants(for: code) {
                        let tURL = AppConfiguration.r2PriceTrendsURL(setCode: tStem)
                        let tResult = await self.fetchJSONWithETag(
                            url: tURL,
                            etagMetaKey: Self.etagMetaKey(brand: .pokemon, kind: "trends", setCode: code),
                            store: store,
                            session: sess
                        )
                        if case .downloaded(let tData) = tResult {
                            try? await store.upsertPriceTrends(setCode: code, json: tData, brand: .pokemon)
                            totalBytes += Int64(tData.count)
                            break
                        }
                        if case .unchanged = tResult { break }
                    }
                    return totalBytes
                }
            }
            for await byteCount in group {
                await progress.completeFile(byteCount: byteCount)
                downloaded += byteCount
            }
        }
        return downloaded
    }

    /// ONE PIECE catalog sync may skip per-set downloads; this still pulls fresh market + history + trends JSON after each 03:00 boundary.
    private func syncOnePieceMarketPricingFullRefresh(progress: CatalogSyncProgressReporter, store: CatalogStore) async -> Int64 {
        let sets: [TCGSet]
        do {
            sets = try await store.fetchAllSets(for: .onePiece)
        } catch {
            return 0
        }
        guard !sets.isEmpty else { return 0 }
        var downloaded: Int64 = 0
        await progress.addPlannedFiles(sets.count)
        await withTaskGroup(of: (String, Int64)?.self) { group in
            for set in sets {
                let code = set.setCode
                let sess = session
                group.addTask {
                    for stem in Self.onePiecePricingStemVariants(for: code) {
                        let pURL = AppConfiguration.r2OnePieceMarketPricingSetURL(setCodeStem: stem)
                        let pricingResult = await self.fetchJSONWithETag(
                            url: pURL,
                            etagMetaKey: Self.etagMetaKey(brand: .onePiece, kind: "pricing", setCode: code),
                            store: store,
                            session: sess
                        )
                        var totalBytes: Int64 = 0
                        switch pricingResult {
                        case .downloaded(let pData):
                            try? await store.upsertPricing(setCode: code, json: pData, brand: .onePiece)
                            totalBytes += Int64(pData.count)
                        case .unchanged:
                            break
                        case .unavailable:
                            continue
                        }
                        for hStem in Self.onePiecePricingStemVariants(for: code) {
                            let hURL = AppConfiguration.r2OnePiecePricingHistoryURL(setCodeStem: hStem)
                            let hResult = await self.fetchJSONWithETag(
                                url: hURL,
                                etagMetaKey: Self.etagMetaKey(brand: .onePiece, kind: "history", setCode: code),
                                store: store,
                                session: sess
                            )
                            if case .downloaded(let hData) = hResult {
                                try? await store.upsertPriceHistory(setCode: code, json: hData, brand: .onePiece)
                                totalBytes += Int64(hData.count)
                                break
                            }
                            if case .unchanged = hResult {
                                break
                            }
                        }
                        for tStem in Self.onePiecePricingStemVariants(for: code) {
                            let tURL = AppConfiguration.r2OnePiecePriceTrendsURL(setCodeStem: tStem)
                            let tResult = await self.fetchJSONWithETag(
                                url: tURL,
                                etagMetaKey: Self.etagMetaKey(brand: .onePiece, kind: "trends", setCode: code),
                                store: store,
                                session: sess
                            )
                            if case .downloaded(let tData) = tResult {
                                try? await store.upsertPriceTrends(setCode: code, json: tData, brand: .onePiece)
                                totalBytes += Int64(tData.count)
                                break
                            }
                            if case .unchanged = tResult {
                                break
                            }
                        }
                        return (code, totalBytes)
                    }
                    return nil
                }
            }
            for await result in group {
                guard let (_, byteCount) = result else {
                    await progress.completeFile()
                    continue
                }
                await progress.completeFile(byteCount: byteCount)
                downloaded += byteCount
            }
        }
        return downloaded
    }

    /// History + trends SQLite columns only (market JSON already present); used once after upgrade. Returns total bytes stored.
    private func syncPokemonHistoryTrendsOnly(progress: CatalogSyncProgressReporter, store: CatalogStore) async -> Int64 {
        let sets: [TCGSet]
        do {
            sets = try await store.fetchAllSets(for: .pokemon)
        } catch {
            return 0
        }
        guard !sets.isEmpty else { return 0 }
        await progress.addPlannedFiles(sets.count)
        let sess = session
        var sum: Int64 = 0
        await withTaskGroup(of: Int64?.self) { group in
            for set in sets {
                let code = set.setCode
                group.addTask {
                    var total: Int64 = 0
                    for tStem in AppConfiguration.pricingFileStemVariants(for: code) {
                        let tURL = AppConfiguration.r2PriceTrendsURL(setCode: tStem)
                        if let tData = await Self.fetchHTTPBodyIfOK(session: sess, url: tURL) {
                            try? await store.upsertPriceTrends(setCode: code, json: tData, brand: .pokemon)
                            total += Int64(tData.count)
                            break
                        }
                    }
                    return total
                }
            }
            for await result in group {
                let n = result ?? 0
                sum += n
                await progress.completeFile(byteCount: n)
            }
        }
        return sum
    }

    private func syncOnePieceHistoryTrendsOnly(progress: CatalogSyncProgressReporter, store: CatalogStore) async -> Int64 {
        let sets: [TCGSet]
        do {
            sets = try await store.fetchAllSets(for: .onePiece)
        } catch {
            return 0
        }
        guard !sets.isEmpty else { return 0 }
        await progress.addPlannedFiles(sets.count)
        let sess = session
        var sum: Int64 = 0
        await withTaskGroup(of: Int64?.self) { group in
            for set in sets {
                let code = set.setCode
                group.addTask {
                    var total: Int64 = 0
                    for hStem in Self.onePiecePricingStemVariants(for: code) {
                        let hURL = AppConfiguration.r2OnePiecePricingHistoryURL(setCodeStem: hStem)
                        if let hData = await Self.fetchHTTPBodyIfOK(session: sess, url: hURL) {
                            try? await store.upsertPriceHistory(setCode: code, json: hData, brand: .onePiece)
                            total += Int64(hData.count)
                            break
                        }
                    }
                    for tStem in Self.onePiecePricingStemVariants(for: code) {
                        let tURL = AppConfiguration.r2OnePiecePriceTrendsURL(setCodeStem: tStem)
                        if let tData = await Self.fetchHTTPBodyIfOK(session: sess, url: tURL) {
                            try? await store.upsertPriceTrends(setCode: code, json: tData, brand: .onePiece)
                            total += Int64(tData.count)
                            break
                        }
                    }
                    return total
                }
            }
            for await result in group {
                let n = result ?? 0
                sum += n
                await progress.completeFile(byteCount: n)
            }
        }
        return sum
    }

    private func syncPokemonCatalogCardDeltas(progress: CatalogSyncProgressReporter, store: CatalogStore) async -> Int64 {
        let sets: [TCGSet]
        do {
            sets = try await store.fetchAllSets(for: .pokemon)
        } catch {
            return 0
        }
        guard !sets.isEmpty else { return 0 }
        await progress.addPlannedFiles(sets.count)
        let sess = session
        var totalDownloaded: Int64 = 0
        await withTaskGroup(of: Int64.self) { group in
            for set in sets {
                let code = set.setCode
                group.addTask {
                    let cardsURL = AppConfiguration.r2CatalogURL(path: "cards/\(code).json")
                    let result = await self.fetchJSONWithETag(
                        url: cardsURL,
                        etagMetaKey: Self.etagMetaKey(brand: .pokemon, kind: "cards", setCode: code),
                        store: store,
                        session: sess
                    )
                    guard case .downloaded(let data) = result,
                          let cards = try? JSONDecoder().decode([Card].self, from: data)
                    else {
                        return 0
                    }
                    try? await store.deleteCards(forSet: code, brand: .pokemon)
                    try? await store.insertCards(cards, setCode: code, brand: .pokemon)
                    return Int64(data.count)
                }
            }
            for await byteCount in group {
                await progress.completeFile(byteCount: byteCount)
                totalDownloaded += byteCount
            }
        }
        if totalDownloaded > 0 {
            try? await store.setMeta("catalog_cards_last_updated_at", String(Date().timeIntervalSince1970))
        }
        return totalDownloaded
    }

    private func syncOnePieceCatalogCardDeltas(progress: CatalogSyncProgressReporter, store: CatalogStore) async -> Int64 {
        let sets: [TCGSet]
        do {
            sets = try await store.fetchAllSets(for: .onePiece)
        } catch {
            return 0
        }
        guard !sets.isEmpty else { return 0 }
        await progress.addPlannedFiles(sets.count)
        let sess = session
        var totalDownloaded: Int64 = 0
        await withTaskGroup(of: Int64.self) { group in
            for set in sets {
                let code = set.setCode
                group.addTask {
                    let cardsURL = AppConfiguration.r2OnePieceURL(path: "cards/data/\(code).json")
                    let result = await self.fetchJSONWithETag(
                        url: cardsURL,
                        etagMetaKey: Self.etagMetaKey(brand: .onePiece, kind: "cards", setCode: code),
                        store: store,
                        session: sess
                    )
                    guard case .downloaded(let data) = result,
                          let dtos = try? JSONDecoder().decode([OnePieceCardDTO].self, from: data)
                    else {
                        return 0
                    }
                    let cards = dtos.map { OnePieceCatalogMapping.card(from: $0) }
                    try? await store.deleteCards(forSet: code, brand: .onePiece)
                    try? await store.insertCards(cards, setCode: code, brand: .onePiece)
                    return Int64(data.count)
                }
            }
            for await byteCount in group {
                await progress.completeFile(byteCount: byteCount)
                totalDownloaded += byteCount
            }
        }
        if totalDownloaded > 0 {
            try? await store.setMeta("catalog_cards_last_updated_at", String(Date().timeIntervalSince1970))
        }
        return totalDownloaded
    }

    private static func fetchHTTPBodyIfOK(session: URLSession, url: URL) async -> Data? {
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

    private static func etagMetaKey(brand: TCGBrand, kind: String, setCode: String) -> String {
        let normalizedCode = setCode.lowercased().map { ch in
            ch.isLetter || ch.isNumber ? ch : "_"
        }
        return "etag_\(brand.rawValue)_\(kind)_\(String(normalizedCode))"
    }

    private func fetchJSONWithETag(
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

    /// Downloads missing daily bucket files from `new_pricing/daily/` (up to last 31 days),
    /// pivots each into per-set price history, and upserts into SQLite.
    /// Also upserts today's bucket as per-set card pricing (SetPricingMap shape).
    /// Only downloads bucket keys not already recorded in `processed_pricing_buckets`.
    private func syncPricingBuckets(store: CatalogStore) async -> Int64 {
        guard AppConfiguration.r2BaseURL.host != "invalid.local" else { return 0 }

        let todayDateKey = Self.todayUTCKey()
        let candidateKeys = Self.last31DailyKeys()
        let missing = await store.unprocessedBucketKeys(from: candidateKeys)
        guard !missing.isEmpty else { return 0 }

        var totalBytes: Int64 = 0

        // setCode → cardId → variant → grade → [[dateKey, price]]
        var accumulated: [String: [String: [String: [String: [[String]]]]]] = [:]
        // setCode → cardId → variant → { raw/psa10/ace10 } (today's prices only, for card_pricing)
        var todayPricing: [String: [String: [String: [String: Double]]]] = [:]

        for dateKey in missing {
            let url = AppConfiguration.r2NewPricingDailyURL(dateKey: dateKey)
            guard let data = await Self.fetchHTTPBodyIfOK(session: session, url: url),
                  let bucket = try? JSONSerialization.jsonObject(with: data) as? [String: [String: [String: Double]]]
            else { continue }
            totalBytes += Int64(data.count)

            let isToday = dateKey == todayDateKey
            for (cardId, variants) in bucket {
                let setCode = Self.setCodeFromCardId(cardId)
                for (variant, grades) in variants {
                    for (grade, price) in grades {
                        accumulated[setCode, default: [:]][cardId, default: [:]][variant, default: [:]][grade, default: []]
                            .append([dateKey, String(price)])
                        if isToday {
                            todayPricing[setCode, default: [:]][cardId, default: [:]][variant, default: [:]][grade] = price
                        }
                    }
                }
            }

            try? await store.markBucketProcessed(key: dateKey)
        }

        // Upsert today's bucket as per-set card_pricing rows (SetPricingMap: cardId → { scrydex: { variant: { raw/psa10/ace10 } } })
        for (setCode, cardMap) in todayPricing {
            var pricingMap: [String: [String: Any]] = [:]
            for (cardId, variants) in cardMap {
                var scrydex: [String: [String: Double]] = [:]
                for (variant, grades) in variants {
                    var entry: [String: Double] = [:]
                    if let v = grades["raw"] { entry["raw"] = v }
                    if let v = grades["psa10"] { entry["psa10"] = v }
                    if let v = grades["ace10"] { entry["ace10"] = v }
                    if !entry.isEmpty { scrydex[variant] = entry }
                }
                if !scrydex.isEmpty {
                    pricingMap[cardId] = ["scrydex": scrydex, "tcgplayer": NSNull(), "cardmarket": NSNull()]
                }
            }
            if let json = try? JSONSerialization.data(withJSONObject: pricingMap) {
                try? await store.upsertPricing(setCode: setCode, json: json, brand: .pokemon)
            }
        }

        // Merge accumulated points into existing SQLite history per set
        for (setCode, cardMap) in accumulated {
            let existing: [String: [String: Any]]
            if let blob = await store.fetchPriceHistoryData(setCode: setCode, brand: .pokemon),
               let root = try? JSONSerialization.jsonObject(with: blob) as? [String: Any] {
                existing = root.compactMapValues { $0 as? [String: Any] }
            } else {
                existing = [:]
            }

            var merged = existing
            for (cardId, variants) in cardMap {
                var cardEntry = merged[cardId] as? [String: [String: Any]] ?? [:]
                for (variant, grades) in variants {
                    var variantEntry = cardEntry[variant] as? [String: Any] ?? [:]
                    for (grade, newPoints) in grades {
                        var window = variantEntry[grade] as? [String: [[String]]] ?? [:]
                        var daily = window["daily"] ?? []
                        for point in newPoints {
                            daily.removeAll { $0.first == point.first }
                            daily.append(point)
                        }
                        daily.sort { ($0.first ?? "") < ($1.first ?? "") }
                        if daily.count > 31 { daily = Array(daily.suffix(31)) }
                        window["daily"] = daily
                        window["weekly"] = Self.weeklyAverages(from: daily, limit: 52)
                        window["monthly"] = Self.monthlyAverages(from: daily, limit: 60)
                        variantEntry[grade] = window
                    }
                    cardEntry[variant] = variantEntry
                }
                merged[cardId] = cardEntry
            }

            if let json = try? JSONSerialization.data(withJSONObject: merged) {
                try? await store.upsertPriceHistory(setCode: setCode, json: json, brand: .pokemon)
            }
        }

        return totalBytes
    }

    private static func todayUTCKey(now: Date = Date()) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.year, .month, .day], from: now)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    private static func setCodeFromCardId(_ cardId: String) -> String {
        // e.g. "base1-1" → "base1", "sv3pt5-200" → "sv3pt5"
        guard let dash = cardId.lastIndex(of: "-") else { return cardId }
        return String(cardId[..<dash])
    }

    /// ISO week key "YYYY-Www" from a "YYYY-MM-DD" date key.
    private static func isoWeekKey(from dateKey: String) -> String? {
        guard dateKey.count == 10 else { return nil }
        let parts = dateKey.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else { return nil }
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(identifier: "UTC")!
        guard let date = cal.date(from: comps) else { return nil }
        let isoYear = cal.component(.yearForWeekOfYear, from: date)
        let isoWeek = cal.component(.weekOfYear, from: date)
        return String(format: "%04d-W%02d", isoYear, isoWeek)
    }

    /// "YYYY-MM" from "YYYY-MM-DD".
    private static func monthKey(from dateKey: String) -> String? {
        guard dateKey.count >= 7 else { return nil }
        return String(dateKey.prefix(7))
    }

    /// Returns sorted [["weekKey", avgPrice]] from daily points, trimmed to `limit`.
    private static func weeklyAverages(from daily: [[String]], limit: Int) -> [[String]] {
        var totals: [String: (sum: Double, count: Int)] = [:]
        for point in daily {
            guard point.count == 2, let wk = isoWeekKey(from: point[0]), let p = Double(point[1]) else { continue }
            totals[wk, default: (0, 0)].sum += p
            totals[wk, default: (0, 0)].count += 1
        }
        return totals
            .map { (k, v) in [k, String(v.sum / Double(v.count))] }
            .sorted { $0[0] < $1[0] }
            .suffix(limit)
            .map { $0 }
    }

    /// Returns sorted [["YYYY-MM", avgPrice]] from daily points, trimmed to `limit`.
    private static func monthlyAverages(from daily: [[String]], limit: Int) -> [[String]] {
        var totals: [String: (sum: Double, count: Int)] = [:]
        for point in daily {
            guard point.count == 2, let mk = monthKey(from: point[0]), let p = Double(point[1]) else { continue }
            totals[mk, default: (0, 0)].sum += p
            totals[mk, default: (0, 0)].count += 1
        }
        return totals
            .map { (k, v) in [k, String(v.sum / Double(v.count))] }
            .sorted { $0[0] < $1[0] }
            .suffix(limit)
            .map { $0 }
    }

    /// Last 31 calendar days as "YYYY-MM-DD" keys (UTC), oldest first.
    private static func last31DailyKeys(relativeTo now: Date = Date()) -> [String] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return (0..<31).compactMap { offset -> String? in
            guard let date = cal.date(byAdding: .day, value: -offset, to: now) else { return nil }
            let comps = cal.dateComponents([.year, .month, .day], from: date)
            guard let y = comps.year, let m = comps.month, let d = comps.day else { return nil }
            return String(format: "%04d-%02d-%02d", y, m, d)
        }.reversed()
    }

    private func syncDailyBlobsIfNeeded(
        progress: CatalogSyncProgressReporter,
        enabledBrands: Set<TCGBrand>,
        forceRefresh: Bool = false
    ) async -> Int64 {
        guard AppConfiguration.r2BaseURL.host != "invalid.local" else { return 0 }
        let store = CatalogStore.shared
        let periodStart = DailyMarketPricingSchedule.currentPeriodStart(now: Date(), calendar: .current)
        var keys: [(String, URL)] = [
            (DailyBlobKey.priceTrends, AppConfiguration.r2MarketURL(path: DailyBlobPath.priceTrends)),
            (DailyBlobKey.marketTrend, AppConfiguration.r2MarketURL(path: DailyBlobPath.marketTrend)),
        ]
        if enabledBrands.contains(.pokemon) {
            keys.insert((DailyBlobKey.pokedataEnglishPokemonPriceTrends, AppConfiguration.r2MarketURL(path: DailyBlobPath.pokedataEnglishPokemonPriceTrends)), at: 0)
            keys.insert((DailyBlobKey.pokedataEnglishPokemonPriceHistory, AppConfiguration.r2MarketURL(path: DailyBlobPath.pokedataEnglishPokemonPriceHistory)), at: 0)
            keys.insert((DailyBlobKey.pokedataEnglishPokemonPrices, AppConfiguration.r2MarketURL(path: DailyBlobPath.pokedataEnglishPokemonPrices)), at: 0)
            keys.insert((DailyBlobKey.pokedataEnglishPokemonProducts, AppConfiguration.r2MarketURL(path: DailyBlobPath.pokedataEnglishPokemonProducts)), at: 0)
        }
        let staleKeys = forceRefresh
            ? keys
            : await filterAsync(keys) { key, _ in
                guard let last = await store.dailyBlobFetchedAt(key: key) else { return true }
                return last < periodStart
            }
        guard !staleKeys.isEmpty else { return 0 }
        var downloaded: Int64 = 0
        await progress.setStatus("Refreshing daily market data…")
        await progress.addPlannedFiles(staleKeys.count)
        for (key, url) in staleKeys {
            let etagMetaKey = "daily_blob_http_etag_" + key
            var request = URLRequest(url: url)
            if !forceRefresh,
               let prev = await store.meta(etagMetaKey),
               !prev.isEmpty {
                request.setValue(prev, forHTTPHeaderField: "If-None-Match")
            }
            guard let (data, resp) = try? await session.data(for: request),
                  let http = resp as? HTTPURLResponse
            else {
                await progress.completeFile()
                continue
            }
            if http.statusCode == 304 {
                try? await store.touchDailyBlobFetchedAt(key: key)
                if let e = http.value(forHTTPHeaderField: "ETag") ?? http.value(forHTTPHeaderField: "Etag") {
                    try? await store.setMeta(etagMetaKey, e)
                }
                await progress.completeFile(byteCount: 0)
                continue
            }
            guard (200...299).contains(http.statusCode), !data.isEmpty else {
                await progress.completeFile()
                continue
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

    private func filterAsync<T>(_ array: [T], predicate: (T) async -> Bool) async -> [T] {
        var results = [T]()
        for element in array {
            if await predicate(element) {
                results.append(element)
            }
        }
        return results
    }

}

enum DailyBlobKey {
    static let pokedataEnglishPokemonProducts = "pokedata_english_pokemon_products"
    static let pokedataEnglishPokemonPrices = "pokedata_english_pokemon_prices"
    static let pokedataEnglishPokemonPriceHistory = "pokedata_english_pokemon_price_history"
    static let pokedataEnglishPokemonPriceTrends = "pokedata_english_pokemon_price_trends"
    static let priceTrends = "price_trends"
    static let marketTrend = "market_trend"
}

/// Paths relative to `r2MarketPathPrefix` (default: bucket root). Adjust in `AppConfiguration` / plist if your tidy layout differs.
enum DailyBlobPath {
    static let pokedataEnglishPokemonProducts = "data/pokedata-english-pokemon-products.json"
    static let pokedataEnglishPokemonPrices = "new_pricing/pokedata-english-pokemon-prices.json"
    static let pokedataEnglishPokemonPriceHistory = "new_pricing/pokedata-english-pokemon-price-history.json"
    static let pokedataEnglishPokemonPriceTrends = "new_pricing/pokedata-english-pokemon-price-trends.json"
    static let priceTrends = "data/price-trends.json"
    static let marketTrend = "new_pricing/market-trend.json"
}
