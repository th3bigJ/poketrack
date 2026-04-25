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
        downloadedBytes += max(0, byteCount)
        await emit()
    }

    /// Delivers each snapshot on the main actor so SwiftUI does not coalesce async `Task { @MainActor }` updates into a single 100% frame.
    private func emit() async {
        guard let handler else { return }
        let naiveEstimate: Int64
        if completedFiles > 0, totalFiles > 0 {
            let average = Double(downloadedBytes) / Double(completedFiles)
            naiveEstimate = Int64(average * Double(totalFiles))
        } else {
            naiveEstimate = 0
        }
        peakEstimatedTotalBytes = max(peakEstimatedTotalBytes, naiveEstimate, downloadedBytes)
        let estimatedTotalBytes = peakEstimatedTotalBytes

        let fileFraction: Double
        if totalFiles > 0 {
            fileFraction = min(max(Double(completedFiles) / Double(totalFiles), 0), 1)
        } else {
            fileFraction = 0
        }
        let byteFraction: Double
        if estimatedTotalBytes > 0 {
            byteFraction = min(1, Double(downloadedBytes) / Double(estimatedTotalBytes))
        } else {
            byteFraction = 0
        }
        let blended = max(fileFraction, byteFraction)
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

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Run after app launch: refresh catalog for **enabled** brands only (Pokémon → SQLite + pricing + daily blobs; ONE PIECE → card JSON on disk).
    func syncAllIfNeeded(
        enabledBrands: Set<TCGBrand>,
        progressHandler: (@MainActor @Sendable (CatalogSyncProgressSnapshot) -> Void)? = nil
    ) async {
        let progress = CatalogSyncProgressReporter(handler: progressHandler)
        if enabledBrands.contains(.pokemon) {
            do {
                try CatalogStore.shared.open()
                await progress.setStatus("Checking card catalog…")
                await syncCatalogIfNeeded(progress: progress)
            } catch {
                // Local catalog DB unavailable; still prefetch ONE PIECE below if enabled.
            }
        }
        if enabledBrands.contains(.onePiece) {
            try? CatalogStore.shared.open()
            await syncOnePieceCatalogIfNeeded(progress: progress)
        }
        // Per-set market JSON for every enabled brand, once per local day after 03:00 (same gate as daily blobs below).
        if !enabledBrands.isEmpty {
            try? CatalogStore.shared.open()
            await syncAllMarketPricingIfNeeded(progress: progress, enabledBrands: enabledBrands)
        }
        // Global market JSON (not franchise-specific) — run whenever any catalog is enabled, including ONE PIECE–only.
        if !enabledBrands.isEmpty {
            try? CatalogStore.shared.open()
            await syncDailyBlobsIfNeeded(progress: progress, enabledBrands: enabledBrands)
        }
        await progress.setStatus("Finishing card setup…")
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
        let prevHash = store.meta("catalog_sets_sha256")
        let prevEtag = store.meta("catalog_etag")
        let unchangedHash = (hash == prevHash)
        let unchangedEtag = (etag != nil && etag == prevEtag)
        let hasCards = (try? store.hasAnyCards(for: .pokemon)) ?? false
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
            await progress.addPlannedFiles(1 + sets.count * 2)
            await progress.completeFile(byteCount: Int64(data.count))
            try store.purgeCatalogTables(for: .pokemon)
            for set in sets {
                await progress.setStatus("Updating \(set.name)…")
                try store.upsertSet(set, brand: .pokemon)
                let code = set.setCode
                let cardsURL = AppConfiguration.r2CatalogURL(path: "cards/\(code).json")
                if let (cData, _) = try? await session.data(from: cardsURL) {
                    let cards = try JSONDecoder().decode([Card].self, from: cData)
                    try store.insertCards(cards, setCode: code, brand: .pokemon)
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
                    try store.upsertPricing(setCode: code, json: pData, brand: .pokemon)
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
            // Mark sync as failed so next launch retries
            try? store.setMeta("sync_failed", "1")
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
            if let prevEtagHeader = store.meta("onepiece_catalog_sets_etag"), !prevEtagHeader.isEmpty {
                request.setValue(prevEtagHeader, forHTTPHeaderField: "If-None-Match")
            }
            let pair = try await session.data(for: request)
            var d = pair.0
            var h = pair.1 as? HTTPURLResponse

            if h?.statusCode == 304 {
                let hasLocalCards = (try? store.hasAnyCards(for: .onePiece)) ?? false
                if hasLocalCards {
                    // Server agrees our cached catalog index is current — skip re-downloading every set JSON (~multi‑MB).
                    await progress.addPlannedFiles(2)
                    await progress.completeFile(byteCount: 0)
                    await progress.completeFile(byteCount: 0)
                    if let e = h?.value(forHTTPHeaderField: "ETag") ?? h?.value(forHTTPHeaderField: "Etag") {
                        try? store.setMeta("onepiece_catalog_sets_etag", e)
                    }
                    // Patch any sets whose card download failed in a prior sync.
                    let emptyCodes = (try? store.fetchSetCodesWithNoCards(for: .onePiece)) ?? []
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
        let prevHash = store.meta("onepiece_catalog_sets_sha256")
        let prevEtag = store.meta("onepiece_catalog_sets_etag")
        let unchangedHash = (hash == prevHash)
        let unchangedEtag = (etag != nil && etag == prevEtag)
        let hasCards = (try? store.hasAnyCards(for: .onePiece)) ?? false
        // Same-bytes / same-ETag fast path (Pokémon-style) when we did get a 200 body this run.
        if hasCards && (unchangedHash || unchangedEtag) {
            if let rows = try? JSONDecoder().decode([OnePieceSetRow].self, from: data) {
                let fp = Self.onePieceCatalogFingerprint(from: rows)
                try? store.setMeta("onepiece_catalog_row_fingerprint", fp)
            }
            await progress.addPlannedFiles(2)
            await progress.completeFile(byteCount: Int64(data.count))
            await progress.completeFile(byteCount: 0)
            if let etag {
                try? store.setMeta("onepiece_catalog_sets_etag", etag)
            }
            // Even though the catalog index is unchanged, individual set card downloads may have
            // failed on a prior sync (e.g. OP15 set exists in DB but its cards never downloaded).
            // Patch only the empty sets so a partial failure self-heals without a full re-import.
            let emptyCodes = (try? store.fetchSetCodesWithNoCards(for: .onePiece)) ?? []
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
        let storedFp = store.meta("onepiece_catalog_row_fingerprint")
        let localFp: String? = {
            guard let sets = try? store.fetchAllSets(for: .onePiece), !sets.isEmpty else { return nil }
            return Self.onePieceCatalogFingerprint(fromSetCodes: sets.map(\.setCode))
        }()
        let catalogStructureUnchanged =
            (storedFp == rowFingerprint) || (storedFp == nil && localFp == rowFingerprint)
        if hasCards && catalogStructureUnchanged {
            try? store.setMeta("onepiece_catalog_sets_sha256", hash)
            if let etag {
                try? store.setMeta("onepiece_catalog_sets_etag", etag)
            }
            try? store.setMeta("onepiece_catalog_row_fingerprint", rowFingerprint)
            await progress.addPlannedFiles(2)
            await progress.completeFile(byteCount: Int64(data.count))
            await progress.completeFile(byteCount: 0)
            // Same as above: patch any sets that are registered but have no cards.
            let emptyCodes = (try? store.fetchSetCodesWithNoCards(for: .onePiece)) ?? []
            if !emptyCodes.isEmpty {
                await patchMissingOnePieceCards(setCodes: emptyCodes, store: store, progress: progress)
            }
            return
        }

        await progress.addPlannedFiles(1 + rows.count * 2)
        await progress.completeFile(byteCount: Int64(data.count))

        do {
            try store.purgeCatalogTables(for: .onePiece)
            for row in rows {
                let set = row.asTCGSet()
                let code = row.setCode
                await progress.setStatus("Updating \(row.name)…")
                try store.upsertSet(set, brand: .onePiece)
                let cardsURL = AppConfiguration.r2OnePieceURL(path: "cards/data/\(code).json")
                if let (cData, _) = try? await session.data(from: cardsURL), !cData.isEmpty {
                    let dtos = try JSONDecoder().decode([OnePieceCardDTO].self, from: cData)
                    let cards = dtos.map { OnePieceCatalogMapping.card(from: $0) }
                    try store.insertCards(cards, setCode: code, brand: .onePiece)
                    await progress.completeFile(byteCount: Int64(cData.count))
                } else {
                    await progress.completeFile()
                }
                var pricingBytes: Int64 = 0
                for stem in Self.onePiecePricingStemVariants(for: code) {
                    let pURL = AppConfiguration.r2OnePieceMarketPricingSetURL(setCodeStem: stem)
                    guard let (pData, resp) = try? await session.data(from: pURL),
                          let http = resp as? HTTPURLResponse,
                          (200...299).contains(http.statusCode),
                          !pData.isEmpty
                    else { continue }
                    try store.upsertPricing(setCode: code, json: pData, brand: .onePiece)
                    pricingBytes = Int64(pData.count)
                    break
                }
                await progress.completeFile(byteCount: pricingBytes)
            }
            try store.setMeta("onepiece_catalog_sets_sha256", hash)
            if let etag {
                try store.setMeta("onepiece_catalog_sets_etag", etag)
            }
            try store.setMeta("onepiece_catalog_row_fingerprint", rowFingerprint)
        } catch {
            // Leave partial; browse may be empty until next sync.
            // Mark sync as failed so next launch retries
            try? store.setMeta("sync_failed", "1")
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
        do {
            var request = URLRequest(url: url)
            if let prevEtag = store.meta(etagMetaKey), !prevEtag.isEmpty {
                request.setValue(prevEtag, forHTTPHeaderField: "If-None-Match")
            }
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return }
            if http.statusCode == 304 { return }
            guard (200...299).contains(http.statusCode), !data.isEmpty else { return }
            guard (try? JSONDecoder().decode([String].self, from: data)) != nil else { return }
            try? store.setMetaData(jsonMetaKey, data: data)
            if let etag = http.value(forHTTPHeaderField: "ETag") ?? http.value(forHTTPHeaderField: "Etag") {
                try? store.setMeta(etagMetaKey, etag)
            }
        } catch {
            // Keep the last successful local copy.
        }
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
            try? store.insertCards(cards, setCode: code, brand: .onePiece)
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
    private func syncAllMarketPricingIfNeeded(progress: CatalogSyncProgressReporter, enabledBrands: Set<TCGBrand>) async {
        guard AppConfiguration.r2BaseURL.host != "invalid.local" else { return }
        let store = CatalogStore.shared
        let last = lastMarketPricingSyncDate(store: store)
        let needsPeriodRefresh = DailyMarketPricingSchedule.needsRefreshAfterNewPeriod(lastSync: last)
        let needsAuxBackfill = store.meta("pricing_aux_sqlite_v1") != "1"
        guard needsPeriodRefresh || needsAuxBackfill else { return }

        await progress.setStatus("Refreshing pricing data…")
        if needsPeriodRefresh {
            if enabledBrands.contains(.pokemon) {
                await syncPokemonMarketPricingFullRefresh(progress: progress, store: store)
            }
            if enabledBrands.contains(.onePiece) {
                await syncOnePieceMarketPricingFullRefresh(progress: progress, store: store)
            }
            try? store.setMeta("pricing_last_synced_at", String(Date().timeIntervalSince1970))
            try? store.setMeta("pricing_aux_sqlite_v1", "1")
        } else if needsAuxBackfill {
            var downloaded: Int64 = 0
            if enabledBrands.contains(.pokemon) {
                downloaded += await syncPokemonHistoryTrendsOnly(progress: progress, store: store)
            }
            if enabledBrands.contains(.onePiece) {
                downloaded += await syncOnePieceHistoryTrendsOnly(progress: progress, store: store)
            }
            // Avoid marking complete offline: retry chart backfill on a later launch when networked.
            if downloaded > 0 {
                try? store.setMeta("pricing_aux_sqlite_v1", "1")
            }
        }
    }

    private func lastMarketPricingSyncDate(store: CatalogStore) -> Date? {
        guard let s = store.meta("pricing_last_synced_at"), let t = Double(s) else { return nil }
        return Date(timeIntervalSince1970: t)
    }

    private func syncPokemonMarketPricingFullRefresh(progress: CatalogSyncProgressReporter, store: CatalogStore) async {
        let sets: [TCGSet]
        do {
            sets = try store.fetchAllSets(for: .pokemon)
        } catch {
            return
        }
        guard !sets.isEmpty else { return }
        await progress.addPlannedFiles(sets.count)
        await withTaskGroup(of: (String, Int64)?.self) { group in
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
                        var totalBytes = Int64(pData.count)
                        try? store.upsertPricing(setCode: code, json: pData, brand: .pokemon)
                        for hStem in AppConfiguration.pricingFileStemVariants(for: code) {
                            let hURL = AppConfiguration.r2PricingHistoryURL(setCode: hStem)
                            if let hData = await Self.fetchHTTPBodyIfOK(session: sess, url: hURL) {
                                try? store.upsertPriceHistory(setCode: code, json: hData, brand: .pokemon)
                                totalBytes += Int64(hData.count)
                                break
                            }
                        }
                        for tStem in AppConfiguration.pricingFileStemVariants(for: code) {
                            let tURL = AppConfiguration.r2PriceTrendsURL(setCode: tStem)
                            if let tData = await Self.fetchHTTPBodyIfOK(session: sess, url: tURL) {
                                try? store.upsertPriceTrends(setCode: code, json: tData, brand: .pokemon)
                                totalBytes += Int64(tData.count)
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
            }
        }
    }

    /// ONE PIECE catalog sync may skip per-set downloads; this still pulls fresh market + history + trends JSON after each 03:00 boundary.
    private func syncOnePieceMarketPricingFullRefresh(progress: CatalogSyncProgressReporter, store: CatalogStore) async {
        let sets: [TCGSet]
        do {
            sets = try store.fetchAllSets(for: .onePiece)
        } catch {
            return
        }
        guard !sets.isEmpty else { return }
        await progress.addPlannedFiles(sets.count)
        await withTaskGroup(of: (String, Int64)?.self) { group in
            for set in sets {
                let code = set.setCode
                let sess = session
                group.addTask {
                    for stem in Self.onePiecePricingStemVariants(for: code) {
                        let pURL = AppConfiguration.r2OnePieceMarketPricingSetURL(setCodeStem: stem)
                        guard let (pData, resp) = try? await sess.data(from: pURL),
                              let http = resp as? HTTPURLResponse,
                              (200...299).contains(http.statusCode),
                              !pData.isEmpty
                        else { continue }
                        var totalBytes = Int64(pData.count)
                        try? store.upsertPricing(setCode: code, json: pData, brand: .onePiece)
                        for hStem in Self.onePiecePricingStemVariants(for: code) {
                            let hURL = AppConfiguration.r2OnePiecePricingHistoryURL(setCodeStem: hStem)
                            if let hData = await Self.fetchHTTPBodyIfOK(session: sess, url: hURL) {
                                try? store.upsertPriceHistory(setCode: code, json: hData, brand: .onePiece)
                                totalBytes += Int64(hData.count)
                                break
                            }
                        }
                        for tStem in Self.onePiecePricingStemVariants(for: code) {
                            let tURL = AppConfiguration.r2OnePiecePriceTrendsURL(setCodeStem: tStem)
                            if let tData = await Self.fetchHTTPBodyIfOK(session: sess, url: tURL) {
                                try? store.upsertPriceTrends(setCode: code, json: tData, brand: .onePiece)
                                totalBytes += Int64(tData.count)
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
            }
        }
    }

    /// History + trends SQLite columns only (market JSON already present); used once after upgrade. Returns total bytes stored.
    private func syncPokemonHistoryTrendsOnly(progress: CatalogSyncProgressReporter, store: CatalogStore) async -> Int64 {
        let sets: [TCGSet]
        do {
            sets = try store.fetchAllSets(for: .pokemon)
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
                    for hStem in AppConfiguration.pricingFileStemVariants(for: code) {
                        let hURL = AppConfiguration.r2PricingHistoryURL(setCode: hStem)
                        if let hData = await Self.fetchHTTPBodyIfOK(session: sess, url: hURL) {
                            try? store.upsertPriceHistory(setCode: code, json: hData, brand: .pokemon)
                            total += Int64(hData.count)
                            break
                        }
                    }
                    for tStem in AppConfiguration.pricingFileStemVariants(for: code) {
                        let tURL = AppConfiguration.r2PriceTrendsURL(setCode: tStem)
                        if let tData = await Self.fetchHTTPBodyIfOK(session: sess, url: tURL) {
                            try? store.upsertPriceTrends(setCode: code, json: tData, brand: .pokemon)
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
            sets = try store.fetchAllSets(for: .onePiece)
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
                            try? store.upsertPriceHistory(setCode: code, json: hData, brand: .onePiece)
                            total += Int64(hData.count)
                            break
                        }
                    }
                    for tStem in Self.onePiecePricingStemVariants(for: code) {
                        let tURL = AppConfiguration.r2OnePiecePriceTrendsURL(setCodeStem: tStem)
                        if let tData = await Self.fetchHTTPBodyIfOK(session: sess, url: tURL) {
                            try? store.upsertPriceTrends(setCode: code, json: tData, brand: .onePiece)
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

    private func syncDailyBlobsIfNeeded(progress: CatalogSyncProgressReporter, enabledBrands: Set<TCGBrand>) async {
        guard AppConfiguration.r2BaseURL.host != "invalid.local" else { return }
        let store = CatalogStore.shared
        let periodStart = DailyMarketPricingSchedule.currentPeriodStart(now: Date(), calendar: .current)
        var keys: [(String, URL)] = [
            (DailyBlobKey.priceTrends, AppConfiguration.r2MarketURL(path: DailyBlobPath.priceTrends)),
            (DailyBlobKey.marketTrend, AppConfiguration.r2MarketURL(path: DailyBlobPath.marketTrend)),
        ]
        if enabledBrands.contains(.pokemon) {
            keys.insert(
                (DailyBlobKey.pokedataEnglishPokemonPrices, AppConfiguration.r2MarketURL(path: DailyBlobPath.pokedataEnglishPokemonPrices)),
                at: 0
            )
        }
        let staleKeys = keys.filter { key, _ in
            guard let last = store.dailyBlobFetchedAt(key: key) else { return true }
            return last < periodStart
        }
        guard !staleKeys.isEmpty else { return }
        await progress.setStatus("Refreshing daily market data…")
        await progress.addPlannedFiles(staleKeys.count)
        for (key, url) in staleKeys {
            let etagMetaKey = "daily_blob_http_etag_" + key
            var request = URLRequest(url: url)
            if let prev = store.meta(etagMetaKey), !prev.isEmpty {
                request.setValue(prev, forHTTPHeaderField: "If-None-Match")
            }
            guard let (data, resp) = try? await session.data(for: request),
                  let http = resp as? HTTPURLResponse
            else {
                await progress.completeFile()
                continue
            }
            if http.statusCode == 304 {
                try? store.touchDailyBlobFetchedAt(key: key)
                if let e = http.value(forHTTPHeaderField: "ETag") ?? http.value(forHTTPHeaderField: "Etag") {
                    try? store.setMeta(etagMetaKey, e)
                }
                await progress.completeFile(byteCount: 0)
                continue
            }
            guard (200...299).contains(http.statusCode), !data.isEmpty else {
                await progress.completeFile()
                continue
            }
            do {
                try store.upsertDailyBlob(key: key, data: data)
                if let e = http.value(forHTTPHeaderField: "ETag") ?? http.value(forHTTPHeaderField: "Etag") {
                    try? store.setMeta(etagMetaKey, e)
                }
                await progress.completeFile(byteCount: Int64(data.count))
            } catch {
                await progress.completeFile()
            }
        }
    }

}

enum DailyBlobKey {
    static let pokedataEnglishPokemonPrices = "pokedata_english_pokemon_prices"
    static let priceTrends = "price_trends"
    static let marketTrend = "market_trend"
}

/// Paths relative to `r2MarketPathPrefix` (default: bucket root). Adjust in `AppConfiguration` / plist if your tidy layout differs.
enum DailyBlobPath {
    static let pokedataEnglishPokemonPrices = "sealed-products/pokedata/pokedata-english-pokemon-prices.json"
    static let priceTrends = "data/price-trends.json"
    static let marketTrend = "pricing/market-trend.json"
}
