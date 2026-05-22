import Foundation

/// Handles per-set market pricing, price history, trends, and bucket sync for all enabled brands.
struct MarketPricingSyncPhase {
    // Combined files cut total requests from ~43,000 to ~410. Use more concurrent connections
    // so the history backfill completes in seconds rather than minutes. Catalog session is
    // capped at 4 connections per host, so additional Swift tasks queue behind those slots
    // without opening extra sockets — safe to set higher than the connection limit.
    private static let maxConcurrentBackfillRequests = 8
    let session: URLSession
    let store: CatalogStore

    /// Returns the number of files this phase will download, without doing any work.
    /// Used by the coordinator to pre-announce the total so the progress bar starts correctly.
    func estimatedFileCount(enabledBrands: Set<TCGBrand>, forceRefresh: Bool = false) async -> Int {
        guard AppConfiguration.r2BaseURL.host != "invalid.local" else { return 0 }
        guard enabledBrands.contains(.pokemon) else { return 0 }
        var count = 0
        let needsNormalizedMigration = (await store.meta("pricing_normalized_v1")) != "1"
        let last = await lastSyncDate()
        let needsPeriodRefresh = DailyMarketPricingSchedule.needsRefreshAfterNewPeriod(lastSync: last)
        let shouldRunPeriodRefresh = forceRefresh || needsPeriodRefresh
        let needsHistoryBackfill = (await store.meta("pricing_history_backfill_v1")) != "1"
        let needsSealedHistoryBackfill = (await store.meta("sealed_pricing_history_backfill_v1")) != "1"
        let auxSqliteV1 = await store.meta("pricing_aux_sqlite_v1")
        let needsAuxBackfill = needsNormalizedMigration || auxSqliteV1 != "1"
        let shouldRunAuxBackfill = !forceRefresh && needsAuxBackfill

        if shouldRunPeriodRefresh || shouldRunAuxBackfill {
            // Card delta sets + market pricing sets (one file each)
            let pokemonSetCount = (try? await store.fetchAllSets(for: .pokemon).count) ?? 0
            count += pokemonSetCount * 2  // card deltas + market pricing
        }
        if shouldRunPeriodRefresh || shouldRunAuxBackfill || needsHistoryBackfill {
            // Daily pricing buckets (up to 31) + sealed buckets (up to 31)
            let dailyCandidates = BucketDateMath.last31DailyKeys()
            var missingDaily = await store.unprocessedBucketKeys(from: dailyCandidates)
            if forceRefresh {
                let today = BucketDateMath.todayUTCKey()
                if !missingDaily.contains(today) { missingDaily.append(today) }
            }
            count += missingDaily.count
            let candidateSealed = dailyCandidates.map { "sealed/\($0)" }
            var missingSealed = await store.unprocessedBucketKeys(from: candidateSealed)
            if forceRefresh {
                let todaySealed = "sealed/\(BucketDateMath.todayUTCKey())"
                if !missingSealed.contains(todaySealed) { missingSealed.append(todaySealed) }
            }
            count += missingSealed.count
        }
        if needsHistoryBackfill {
            let processed = await store.processedBucketKeys(withPrefix: "20")
            count += BucketDateMath.allWeeklyKeys(from: 2020).filter { !processed.contains($0) }.count
            count += BucketDateMath.allMonthlyKeys(from: 2020).filter { !processed.contains($0) }.count
        }
        if needsSealedHistoryBackfill {
            let processed = await store.processedBucketKeys(withPrefix: "sealed/")
            count += BucketDateMath.allWeeklyKeys(from: 2020).map { "sealed/\($0)" }.filter { !processed.contains($0) }.count
            count += BucketDateMath.allMonthlyKeys(from: 2020).map { "sealed/\($0)" }.filter { !processed.contains($0) }.count
        }
        return count
    }

    func syncAllIfNeeded(
        progress: CatalogSyncProgressReporter,
        enabledBrands: Set<TCGBrand>,
        forceRefresh: Bool = false
    ) async -> Int64 {
        guard AppConfiguration.r2BaseURL.host != "invalid.local" else { return 0 }
        let needsNormalizedMigration = (await store.meta("pricing_normalized_v1")) != "1"
        if needsNormalizedMigration {
            try? await store.setMeta("pricing_history_backfill_v1", "")
            try? await store.setMeta("sealed_pricing_history_backfill_v1", "")
        }
        let last = await lastSyncDate()
        let needsPeriodRefresh = DailyMarketPricingSchedule.needsRefreshAfterNewPeriod(lastSync: last)
        let auxSqliteV1 = await store.meta("pricing_aux_sqlite_v1")
        let needsAuxBackfill = needsNormalizedMigration || auxSqliteV1 != "1"
        let needsHistoryBackfill = (await store.meta("pricing_history_backfill_v1")) != "1"
        let needsSealedHistoryBackfill = (await store.meta("sealed_pricing_history_backfill_v1")) != "1"
        let shouldRunPeriodRefresh = forceRefresh || needsPeriodRefresh
        let shouldRunAuxBackfill = !forceRefresh && needsAuxBackfill
        guard shouldRunPeriodRefresh || shouldRunAuxBackfill || needsHistoryBackfill || needsSealedHistoryBackfill else { return 0 }

        await progress.setStatus("Refreshing pricing data…")
        if shouldRunPeriodRefresh {
            var downloaded: Int64 = 0
            if enabledBrands.contains(.pokemon) {
                downloaded += await syncPokemonCardDeltas(progress: progress)
            }
            if enabledBrands.contains(.onePiece) {
                downloaded += await syncOnePieceCardDeltas(progress: progress)
            }
            if enabledBrands.contains(.pokemon) {
                downloaded += await syncPokemonMarketPricingFullRefresh(progress: progress)
                downloaded += await syncPricingBuckets(progress: progress, forceRefresh: forceRefresh)
                downloaded += await syncSealedPricingBuckets(progress: progress, forceRefresh: forceRefresh)
                if needsHistoryBackfill {
                    downloaded += await syncPricingHistoryBackfill(progress: progress)
                    try? await store.setMeta("pricing_history_backfill_v1", "1")
                }
                if needsSealedHistoryBackfill {
                    downloaded += await syncSealedPricingHistoryBackfill(progress: progress)
                    try? await store.setMeta("sealed_pricing_history_backfill_v1", "1")
                }
            }
            if enabledBrands.contains(.onePiece) {
                downloaded += await syncOnePieceMarketPricingFullRefresh(progress: progress)
            }
            try? await store.setMeta("pricing_last_synced_at", String(Date().timeIntervalSince1970))
            try? await store.setMeta("pricing_aux_sqlite_v1", "1")
            try? await store.setMeta("pricing_normalized_v1", "1")
            return downloaded
        } else if shouldRunAuxBackfill {
            var downloaded: Int64 = 0
            if enabledBrands.contains(.pokemon) {
                downloaded += await syncPokemonHistoryTrendsOnly(progress: progress)
                downloaded += await syncPricingBuckets(progress: progress)
                downloaded += await syncSealedPricingBuckets(progress: progress)
                if needsHistoryBackfill {
                    downloaded += await syncPricingHistoryBackfill(progress: progress)
                    try? await store.setMeta("pricing_history_backfill_v1", "1")
                }
                if needsSealedHistoryBackfill {
                    downloaded += await syncSealedPricingHistoryBackfill(progress: progress)
                    try? await store.setMeta("sealed_pricing_history_backfill_v1", "1")
                }
            }
            if enabledBrands.contains(.onePiece) {
                downloaded += await syncOnePieceHistoryTrendsOnly(progress: progress)
            }
            if downloaded > 0 {
                try? await store.setMeta("pricing_aux_sqlite_v1", "1")
                try? await store.setMeta("pricing_normalized_v1", "1")
            }
            return downloaded
        } else if needsHistoryBackfill || needsSealedHistoryBackfill {
            var downloaded: Int64 = 0
            if enabledBrands.contains(.pokemon) {
                if needsHistoryBackfill {
                    downloaded += await syncPricingHistoryBackfill(progress: progress)
                    try? await store.setMeta("pricing_history_backfill_v1", "1")
                }
                if needsSealedHistoryBackfill {
                    downloaded += await syncSealedPricingHistoryBackfill(progress: progress)
                    try? await store.setMeta("sealed_pricing_history_backfill_v1", "1")
                }
            }
            return downloaded
        }
        return 0
    }

    private func lastSyncDate() async -> Date? {
        guard let s = await store.meta("pricing_last_synced_at"), let t = Double(s) else { return nil }
        return Date(timeIntervalSince1970: t)
    }

    private func syncPokemonCardDeltas(progress: CatalogSyncProgressReporter) async -> Int64 {
        let sets: [TCGSet]
        do { sets = try await store.fetchAllSets(for: .pokemon) } catch { return 0 }
        guard !sets.isEmpty else { return 0 }
        await progress.addPlannedFiles(sets.count)
        let sess = session
        var totalDownloaded: Int64 = 0
        await withTaskGroup(of: Int64.self) { group in
            for set in sets {
                let code = set.setCode
                group.addTask {
                    let cardsURL = AppConfiguration.r2CatalogURL(path: "cards/\(code).json")
                    let result = await CatalogSyncCoordinator.fetchJSONWithETag(
                        url: cardsURL,
                        etagMetaKey: CatalogSyncCoordinator.etagMetaKey(brand: .pokemon, kind: "cards", setCode: code),
                        store: self.store,
                        session: sess
                    )
                    guard case .downloaded(let data) = result,
                          let cards = try? JSONDecoder().decode([Card].self, from: data)
                    else { return 0 }
                    try? await self.store.deleteCards(forSet: code, brand: .pokemon)
                    try? await self.store.insertCards(cards, setCode: code, brand: .pokemon)
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

    private func syncOnePieceCardDeltas(progress: CatalogSyncProgressReporter) async -> Int64 {
        let sets: [TCGSet]
        do { sets = try await store.fetchAllSets(for: .onePiece) } catch { return 0 }
        guard !sets.isEmpty else { return 0 }
        await progress.addPlannedFiles(sets.count)
        let sess = session
        var totalDownloaded: Int64 = 0
        await withTaskGroup(of: Int64.self) { group in
            for set in sets {
                let code = set.setCode
                group.addTask {
                    let cardsURL = AppConfiguration.r2OnePieceURL(path: "cards/data/\(code).json")
                    let result = await CatalogSyncCoordinator.fetchJSONWithETag(
                        url: cardsURL,
                        etagMetaKey: CatalogSyncCoordinator.etagMetaKey(brand: .onePiece, kind: "cards", setCode: code),
                        store: self.store,
                        session: sess
                    )
                    guard case .downloaded(let data) = result,
                          let dtos = try? JSONDecoder().decode([OnePieceCardDTO].self, from: data)
                    else { return 0 }
                    let cards = dtos.map { OnePieceCatalogMapping.card(from: $0) }
                    try? await self.store.deleteCards(forSet: code, brand: .onePiece)
                    try? await self.store.insertCards(cards, setCode: code, brand: .onePiece)
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

    private func syncPokemonMarketPricingFullRefresh(progress: CatalogSyncProgressReporter) async -> Int64 {
        let sets: [TCGSet]
        do { sets = try await store.fetchAllSets(for: .pokemon) } catch { return 0 }
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
                        let tResult = await CatalogSyncCoordinator.fetchJSONWithETag(
                            url: tURL,
                            etagMetaKey: CatalogSyncCoordinator.etagMetaKey(brand: .pokemon, kind: "trends", setCode: code),
                            store: self.store,
                            session: sess
                        )
                        if case .downloaded(let tData) = tResult {
                            try? await self.store.upsertPriceTrends(setCode: code, json: tData, brand: .pokemon)
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

    private func syncOnePieceMarketPricingFullRefresh(progress: CatalogSyncProgressReporter) async -> Int64 {
        let sets: [TCGSet]
        do { sets = try await store.fetchAllSets(for: .onePiece) } catch { return 0 }
        guard !sets.isEmpty else { return 0 }
        var downloaded: Int64 = 0
        await progress.addPlannedFiles(sets.count)
        let sess = session
        await withTaskGroup(of: (String, Int64)?.self) { group in
            for set in sets {
                let code = set.setCode
                group.addTask {
                    for stem in OnePieceCatalogSyncPhase.pricingStemVariants(for: code) {
                        let pURL = AppConfiguration.r2OnePieceMarketPricingSetURL(setCodeStem: stem)
                        let pricingResult = await CatalogSyncCoordinator.fetchJSONWithETag(
                            url: pURL,
                            etagMetaKey: CatalogSyncCoordinator.etagMetaKey(brand: .onePiece, kind: "pricing", setCode: code),
                            store: self.store,
                            session: sess
                        )
                        var totalBytes: Int64 = 0
                        switch pricingResult {
                        case .downloaded(let pData):
                            try? await self.store.upsertPricing(setCode: code, json: pData, brand: .onePiece)
                            totalBytes += Int64(pData.count)
                        case .unchanged: break
                        case .unavailable: continue
                        }
                        for hStem in OnePieceCatalogSyncPhase.pricingStemVariants(for: code) {
                            let hURL = AppConfiguration.r2OnePiecePricingHistoryURL(setCodeStem: hStem)
                            let hResult = await CatalogSyncCoordinator.fetchJSONWithETag(
                                url: hURL,
                                etagMetaKey: CatalogSyncCoordinator.etagMetaKey(brand: .onePiece, kind: "history", setCode: code),
                                store: self.store,
                                session: sess
                            )
                            if case .downloaded(let hData) = hResult {
                                try? await self.store.upsertPriceHistory(setCode: code, json: hData, brand: .onePiece)
                                totalBytes += Int64(hData.count)
                                break
                            }
                            if case .unchanged = hResult { break }
                        }
                        for tStem in OnePieceCatalogSyncPhase.pricingStemVariants(for: code) {
                            let tURL = AppConfiguration.r2OnePiecePriceTrendsURL(setCodeStem: tStem)
                            let tResult = await CatalogSyncCoordinator.fetchJSONWithETag(
                                url: tURL,
                                etagMetaKey: CatalogSyncCoordinator.etagMetaKey(brand: .onePiece, kind: "trends", setCode: code),
                                store: self.store,
                                session: sess
                            )
                            if case .downloaded(let tData) = tResult {
                                try? await self.store.upsertPriceTrends(setCode: code, json: tData, brand: .onePiece)
                                totalBytes += Int64(tData.count)
                                break
                            }
                            if case .unchanged = tResult { break }
                        }
                        return (code, totalBytes)
                    }
                    return nil
                }
            }
            for await result in group {
                guard let (_, byteCount) = result else { await progress.completeFile(); continue }
                await progress.completeFile(byteCount: byteCount)
                downloaded += byteCount
            }
        }
        return downloaded
    }

    private func syncPokemonHistoryTrendsOnly(progress: CatalogSyncProgressReporter) async -> Int64 {
        let sets: [TCGSet]
        do { sets = try await store.fetchAllSets(for: .pokemon) } catch { return 0 }
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
                        if let tData = await Self.fetchBodyIfOK(session: sess, url: tURL) {
                            try? await self.store.upsertPriceTrends(setCode: code, json: tData, brand: .pokemon)
                            total += Int64(tData.count)
                            break
                        }
                    }
                    return total
                }
            }
            for await result in group { let n = result ?? 0; sum += n; await progress.completeFile(byteCount: n) }
        }
        return sum
    }

    private func syncOnePieceHistoryTrendsOnly(progress: CatalogSyncProgressReporter) async -> Int64 {
        let sets: [TCGSet]
        do { sets = try await store.fetchAllSets(for: .onePiece) } catch { return 0 }
        guard !sets.isEmpty else { return 0 }
        await progress.addPlannedFiles(sets.count)
        let sess = session
        var sum: Int64 = 0
        await withTaskGroup(of: Int64?.self) { group in
            for set in sets {
                let code = set.setCode
                group.addTask {
                    var total: Int64 = 0
                    for hStem in OnePieceCatalogSyncPhase.pricingStemVariants(for: code) {
                        let hURL = AppConfiguration.r2OnePiecePricingHistoryURL(setCodeStem: hStem)
                        if let hData = await Self.fetchBodyIfOK(session: sess, url: hURL) {
                            try? await self.store.upsertPriceHistory(setCode: code, json: hData, brand: .onePiece)
                            total += Int64(hData.count)
                            break
                        }
                    }
                    for tStem in OnePieceCatalogSyncPhase.pricingStemVariants(for: code) {
                        let tURL = AppConfiguration.r2OnePiecePriceTrendsURL(setCodeStem: tStem)
                        if let tData = await Self.fetchBodyIfOK(session: sess, url: tURL) {
                            try? await self.store.upsertPriceTrends(setCode: code, json: tData, brand: .onePiece)
                            total += Int64(tData.count)
                            break
                        }
                    }
                    return total
                }
            }
            for await result in group { let n = result ?? 0; sum += n; await progress.completeFile(byteCount: n) }
        }
        return sum
    }

    private func syncPricingBuckets(progress: CatalogSyncProgressReporter, forceRefresh: Bool = false) async -> Int64 {
        guard AppConfiguration.r2BaseURL.host != "invalid.local" else { return 0 }

        let todayDateKey = BucketDateMath.todayUTCKey()
        let candidateDateKeys = BucketDateMath.last31DailyKeys()
        var missingDateKeys = await store.unprocessedBucketKeys(from: candidateDateKeys)
        // Today's bucket may already be marked processed (e.g. before a new set was added to R2).
        // Force refresh must re-download it so `card_prices` picks up new cards like me4.
        if forceRefresh, !missingDateKeys.contains(todayDateKey) {
            missingDateKeys.append(todayDateKey)
        }
        guard !missingDateKeys.isEmpty else { return 0 }

        await progress.setStatus("Downloading daily price data…")
        await progress.addPlannedFiles(missingDateKeys.count)

        typealias DailyBucketResult = (
            points: [CatalogStore.PriceHistoryPoint],
            todayPricing: [String: [String: [String: [String: Double]]]],
            bytes: Int64,
            dateKey: String
        )

        func fetchDailyBucket(dateKey: String) async -> DailyBucketResult {
            let url = AppConfiguration.r2NewPricingDailyURL(dateKey: dateKey)
            guard let data = await Self.fetchBodyIfOK(session: session, url: url),
                  let bucket = try? JSONSerialization.jsonObject(with: data) as? [String: [String: [String: Double]]]
            else { return ([], [:], 0, dateKey) }
            let isToday = dateKey == todayDateKey
            var pts: [CatalogStore.PriceHistoryPoint] = []
            var todayMap: [String: [String: [String: [String: Double]]]] = [:]
            for (cardId, variants) in bucket {
                let setCode = BucketDateMath.setCodeFromCardId(cardId)
                for (variant, grades) in variants {
                    for (grade, price) in grades {
                        pts.append(CatalogStore.PriceHistoryPoint(
                            cardKey: cardId, variant: variant, grade: grade,
                            periodType: "daily", periodKey: dateKey, price: price
                        ))
                        if isToday {
                            todayMap[setCode, default: [:]][cardId, default: [:]][variant, default: [:]][grade] = price
                        }
                    }
                }
            }
            return (pts, todayMap, Int64(data.count), dateKey)
        }

        var totalBytes: Int64 = 0
        var allPoints: [CatalogStore.PriceHistoryPoint] = []
        var todayPricing: [String: [String: [String: [String: Double]]]] = [:]

        await withTaskGroup(of: DailyBucketResult.self) { group in
            var iterator = missingDateKeys.makeIterator()
            for _ in 0..<min(Self.maxConcurrentBackfillRequests, missingDateKeys.count) {
                if let key = iterator.next() { group.addTask { await fetchDailyBucket(dateKey: key) } }
            }
            for await result in group {
                if let key = iterator.next() { group.addTask { await fetchDailyBucket(dateKey: key) } }
                totalBytes += result.bytes
                allPoints.append(contentsOf: result.points)
                for (setCode, cardMap) in result.todayPricing {
                    for (cardId, variants) in cardMap {
                        for (variant, grades) in variants {
                            for (grade, price) in grades {
                                todayPricing[setCode, default: [:]][cardId, default: [:]][variant, default: [:]][grade] = price
                            }
                        }
                    }
                }
                try? await store.markBucketProcessed(key: result.dateKey)
                await progress.completeFile(byteCount: result.bytes)
            }
        }

        for (setCode, cardMap) in todayPricing {
            let storageSetCode = BucketDateMath.normalizedSetCode(setCode)
            var entries: [(cardKey: String, json: Data)] = []
            for (cardId, variants) in cardMap {
                var scrydex: [String: [String: Double]] = [:]
                for (variant, grades) in variants {
                    var entry: [String: Double] = [:]
                    if let v = grades["raw"] { entry["raw"] = v }
                    if let v = grades["psa10"] { entry["psa10"] = v }
                    if let v = grades["ace10"] { entry["ace10"] = v }
                    if !entry.isEmpty { scrydex[variant] = entry }
                }
                guard !scrydex.isEmpty,
                      let json = try? JSONSerialization.data(withJSONObject: ["scrydex": scrydex])
                else { continue }
                entries.append((cardKey: cardId, json: json))
            }
            if !entries.isEmpty {
                try? await store.upsertCardPrices(setCode: storageSetCode, brand: .pokemon, entries: entries)
            }
        }

        if !allPoints.isEmpty {
            let bySet = Dictionary(grouping: allPoints) { BucketDateMath.setCodeFromCardId($0.cardKey) }
            for (setCode, pts) in bySet {
                let storageSetCode = BucketDateMath.normalizedSetCode(setCode)
                try? await store.upsertPriceHistoryPoints(brand: .pokemon, setCode: storageSetCode, points: pts)
            }
        }

        return totalBytes
    }

    private func syncPricingHistoryBackfill(progress: CatalogSyncProgressReporter) async -> Int64 {
        guard AppConfiguration.r2BaseURL.host != "invalid.local" else { return 0 }

        let processed = await store.processedBucketKeys(withPrefix: "20")
        let missingWeekly = BucketDateMath.allWeeklyKeys(from: 2020).filter { !processed.contains($0) }
        let missingMonthly = BucketDateMath.allMonthlyKeys(from: 2020).filter { !processed.contains($0) }
        guard !missingWeekly.isEmpty || !missingMonthly.isEmpty else { return 0 }

        await progress.setStatus("Downloading price history…")
        await progress.addPlannedFiles(missingWeekly.count + missingMonthly.count)

        typealias BackfillResult = (points: [CatalogStore.PriceHistoryPoint], bytes: Int64, key: String)

        func fetchBucket(periodKey: String, periodType: String) async -> BackfillResult {
            let url = periodType == "weekly"
                ? AppConfiguration.r2NewPricingWeeklyURL(weekKey: periodKey)
                : AppConfiguration.r2NewPricingMonthlyURL(monthKey: periodKey)
            guard let data = await Self.fetchBodyIfOK(session: session, url: url),
                  let bucket = try? JSONSerialization.jsonObject(with: data) as? [String: [String: [String: Double]]]
            else { return ([], 0, periodKey) }
            var pts: [CatalogStore.PriceHistoryPoint] = []
            for (cardId, variants) in bucket {
                for (variant, grades) in variants {
                    for (grade, price) in grades {
                        pts.append(CatalogStore.PriceHistoryPoint(
                            cardKey: cardId, variant: variant, grade: grade,
                            periodType: periodType, periodKey: periodKey, price: price
                        ))
                    }
                }
            }
            return (pts, Int64(data.count), periodKey)
        }

        let allKeys: [(key: String, periodType: String)] =
            missingWeekly.map { ($0, "weekly") } + missingMonthly.map { ($0, "monthly") }

        var totalBytes: Int64 = 0
        var pendingPoints: [CatalogStore.PriceHistoryPoint] = []

        await withTaskGroup(of: BackfillResult.self) { group in
            var iterator = allKeys.makeIterator()
            for _ in 0..<min(Self.maxConcurrentBackfillRequests, allKeys.count) {
                if let (key, type) = iterator.next() {
                    group.addTask { await fetchBucket(periodKey: key, periodType: type) }
                }
            }
            for await result in group {
                if let (key, type) = iterator.next() {
                    group.addTask { await fetchBucket(periodKey: key, periodType: type) }
                }
                totalBytes += result.bytes
                pendingPoints.append(contentsOf: result.points)
                try? await store.markBucketProcessed(key: result.key)
                await progress.completeFile(byteCount: result.bytes)
                if pendingPoints.count > 10_000 {
                    let bySet = Dictionary(grouping: pendingPoints) { BucketDateMath.setCodeFromCardId($0.cardKey) }
                    for (setCode, pts) in bySet {
                        try? await store.upsertPriceHistoryPoints(brand: .pokemon, setCode: setCode, points: pts)
                    }
                    pendingPoints.removeAll(keepingCapacity: true)
                }
            }
        }

        if !pendingPoints.isEmpty {
            let bySet = Dictionary(grouping: pendingPoints) { BucketDateMath.setCodeFromCardId($0.cardKey) }
            for (setCode, pts) in bySet {
                try? await store.upsertPriceHistoryPoints(brand: .pokemon, setCode: setCode, points: pts)
            }
        }

        return totalBytes
    }

    private func syncSealedPricingBuckets(progress: CatalogSyncProgressReporter, forceRefresh: Bool = false) async -> Int64 {
        guard AppConfiguration.r2BaseURL.host != "invalid.local" else { return 0 }
        let candidateDailyKeys = BucketDateMath.last31DailyKeys().map { "sealed/\($0)" }
        var missingDailyKeys = await store.unprocessedBucketKeys(from: candidateDailyKeys)
        if forceRefresh {
            let todaySealed = "sealed/\(BucketDateMath.todayUTCKey())"
            if !missingDailyKeys.contains(todaySealed) { missingDailyKeys.append(todaySealed) }
        }
        guard !missingDailyKeys.isEmpty else { return 0 }

        await progress.setStatus("Downloading sealed price data…")
        await progress.addPlannedFiles(missingDailyKeys.count)

        typealias SealedDailyResult = (
            compositeKey: String,
            dateKey: String,
            bucket: [String: Double]?,
            bytes: Int64
        )

        var totalBytes: Int64 = 0
        var accumulated: [String: [[String]]] = [:]
        var latestPrices: [String: Double] = [:]
        var latestDate: String = ""

        await withTaskGroup(of: SealedDailyResult.self) { group in
            var iterator = missingDailyKeys.makeIterator()
            for _ in 0..<min(Self.maxConcurrentBackfillRequests, missingDailyKeys.count) {
                if let key = iterator.next() {
                    let dateKey = String(key.dropFirst("sealed/".count))
                    group.addTask {
                        let url = AppConfiguration.r2SealedDailyURL(dateKey: dateKey)
                        guard let data = await Self.fetchBodyIfOK(session: self.session, url: url),
                              let bucket = try? JSONSerialization.jsonObject(with: data) as? [String: Double]
                        else { return (key, dateKey, nil, 0) }
                        return (key, dateKey, bucket, Int64(data.count))
                    }
                }
            }
            for await result in group {
                if let key = iterator.next() {
                    let dateKey = String(key.dropFirst("sealed/".count))
                    group.addTask {
                        let url = AppConfiguration.r2SealedDailyURL(dateKey: dateKey)
                        guard let data = await Self.fetchBodyIfOK(session: self.session, url: url),
                              let bucket = try? JSONSerialization.jsonObject(with: data) as? [String: Double]
                        else { return (key, dateKey, nil, 0) }
                        return (key, dateKey, bucket, Int64(data.count))
                    }
                }
                guard let bucket = result.bucket else {
                    try? await store.markBucketProcessed(key: result.compositeKey)
                    await progress.completeFile(); continue
                }
                totalBytes += result.bytes
                let dateKey = result.dateKey
                for (productIdStr, price) in bucket {
                    accumulated[productIdStr, default: []].append([dateKey, String(price)])
                    if dateKey >= latestDate { latestDate = dateKey; latestPrices[productIdStr] = price }
                }
                try? await store.markBucketProcessed(key: result.compositeKey)
                await progress.completeFile(byteCount: result.bytes)
            }
        }

        if !latestPrices.isEmpty {
            var merged: [String: Double] = [:]
            if let existing = await store.dailyBlob(key: DailyBlobKey.sealedPrices),
               let parsed = try? JSONSerialization.jsonObject(with: existing) as? [String: Double] {
                merged = parsed
            }
            for (k, v) in latestPrices { merged[k] = v }
            if let json = try? JSONSerialization.data(withJSONObject: merged) {
                try? await store.upsertDailyBlob(key: DailyBlobKey.sealedPrices, data: json)
            }
        }

        if !accumulated.isEmpty {
            var historyMap: [String: [String: [[String]]]] = [:]
            if let existing = await store.dailyBlob(key: DailyBlobKey.sealedPriceHistory),
               let parsed = try? JSONSerialization.jsonObject(with: existing) as? [String: [String: [[String]]]] {
                historyMap = parsed
            }
            for (productIdStr, newPoints) in accumulated {
                var window = historyMap[productIdStr] ?? [:]
                var daily = window["daily"] ?? []
                for point in newPoints { daily.removeAll { $0.first == point.first }; daily.append(point) }
                daily.sort { ($0.first ?? "") < ($1.first ?? "") }
                if daily.count > 31 { daily = Array(daily.suffix(31)) }
                window["daily"] = daily
                window["weekly"] = BucketDateMath.weeklyAverages(from: daily, limit: 52)
                window["monthly"] = BucketDateMath.monthlyAverages(from: daily, limit: 60)
                historyMap[productIdStr] = window
            }
            if let json = try? JSONSerialization.data(withJSONObject: historyMap) {
                try? await store.upsertDailyBlob(key: DailyBlobKey.sealedPriceHistory, data: json)
            }
        }
        return totalBytes
    }

    private func syncSealedPricingHistoryBackfill(progress: CatalogSyncProgressReporter) async -> Int64 {
        guard AppConfiguration.r2BaseURL.host != "invalid.local" else { return 0 }
        let processed = await store.processedBucketKeys(withPrefix: "sealed/")
        let missingWeekly = BucketDateMath.allWeeklyKeys(from: 2020).map { "sealed/\($0)" }.filter { !processed.contains($0) }
        let missingMonthly = BucketDateMath.allMonthlyKeys(from: 2020).map { "sealed/\($0)" }.filter { !processed.contains($0) }
        guard !missingWeekly.isEmpty || !missingMonthly.isEmpty else { return 0 }

        await progress.setStatus("Downloading sealed price history…")
        await progress.addPlannedFiles(missingWeekly.count + missingMonthly.count)

        typealias SealedBackfillResult = (points: [(id: String, periodKey: String, price: Double)], bytes: Int64, key: String)

        func fetchSealedBucket(compositeKey: String, isWeekly: Bool) async -> SealedBackfillResult {
            let periodKey = String(compositeKey.dropFirst("sealed/".count))
            let url = isWeekly
                ? AppConfiguration.r2SealedWeeklyURL(weekKey: periodKey)
                : AppConfiguration.r2SealedMonthlyURL(monthKey: periodKey)
            guard let data = await Self.fetchBodyIfOK(session: session, url: url),
                  let bucket = try? JSONSerialization.jsonObject(with: data) as? [String: Double]
            else { return ([], 0, compositeKey) }
            let pts = bucket.map { (id: $0.key, periodKey: periodKey, price: $0.value) }
            return (pts, Int64(data.count), compositeKey)
        }

        let allSealedKeys: [(key: String, isWeekly: Bool)] =
            missingWeekly.map { ($0, true) } + missingMonthly.map { ($0, false) }

        var totalBytes: Int64 = 0
        var accumulated: [String: [[String]]] = [:]

        await withTaskGroup(of: SealedBackfillResult.self) { group in
            var iterator = allSealedKeys.makeIterator()
            for _ in 0..<min(Self.maxConcurrentBackfillRequests, allSealedKeys.count) {
                if let (key, isWeekly) = iterator.next() {
                    group.addTask { await fetchSealedBucket(compositeKey: key, isWeekly: isWeekly) }
                }
            }
            for await result in group {
                if let (key, isWeekly) = iterator.next() {
                    group.addTask { await fetchSealedBucket(compositeKey: key, isWeekly: isWeekly) }
                }
                totalBytes += result.bytes
                for pt in result.points { accumulated[pt.id, default: []].append([pt.periodKey, String(pt.price)]) }
                try? await store.markBucketProcessed(key: result.key)
                await progress.completeFile(byteCount: result.bytes)
            }
        }

        guard !accumulated.isEmpty else { return totalBytes }

        var historyMap: [String: [String: [[String]]]] = [:]
        if let existing = await store.dailyBlob(key: DailyBlobKey.sealedPriceHistory),
           let parsed = try? JSONSerialization.jsonObject(with: existing) as? [String: [String: [[String]]]] {
            historyMap = parsed
        }

        for (productIdStr, newPoints) in accumulated {
            var window = historyMap[productIdStr] ?? [:]
            let newWeekly = newPoints.filter { $0.first?.contains("-W") == true }
            let newMonthly = newPoints.filter { pt in
                guard let k = pt.first else { return false }
                return !k.contains("-W") && k.count == 7
            }
            func mergePoints(existing arr: [[String]], with newPts: [[String]]) -> [[String]] {
                var result = arr
                for pt in newPts { result.removeAll { $0.first == pt.first }; result.append(pt) }
                return result.sorted { ($0.first ?? "") < ($1.first ?? "") }
            }
            window["weekly"] = mergePoints(existing: window["weekly"] ?? [], with: newWeekly)
            window["monthly"] = mergePoints(existing: window["monthly"] ?? [], with: newMonthly)
            historyMap[productIdStr] = window
        }

        if let json = try? JSONSerialization.data(withJSONObject: historyMap) {
            try? await store.upsertDailyBlob(key: DailyBlobKey.sealedPriceHistory, data: json)
        }
        return totalBytes
    }

    private static func fetchBodyIfOK(session: URLSession, url: URL) async -> Data? {
        let request = URLRequest(url: url, timeoutInterval: 20)
        do {
            let (data, resp) = try await session.data(for: request)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode), !data.isEmpty else { return nil }
            return data
        } catch { return nil }
    }
}
