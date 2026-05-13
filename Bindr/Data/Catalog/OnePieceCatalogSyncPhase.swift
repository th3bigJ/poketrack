import CryptoKit
import Foundation

/// Handles ONE PIECE sets + card JSON sync into SQLite.
struct OnePieceCatalogSyncPhase {
    let session: URLSession
    let store: CatalogStore

    func syncCatalogIfNeeded(progress: CatalogSyncProgressReporter) async {
        guard AppConfiguration.r2BaseURL.host != "invalid.local" else { return }
        await refreshBrowseMetadata()
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
                    await progress.addPlannedFiles(2)
                    await progress.completeFile(byteCount: 0)
                    await progress.completeFile(byteCount: 0)
                    if let e = h?.value(forHTTPHeaderField: "ETag") ?? h?.value(forHTTPHeaderField: "Etag") {
                        try? await store.setMeta("onepiece_catalog_sets_etag", e)
                    }
                    let emptyCodes = (try? await store.fetchSetCodesWithNoCards(for: .onePiece)) ?? []
                    if !emptyCodes.isEmpty {
                        await patchMissingCards(setCodes: emptyCodes, progress: progress)
                    }
                    return
                }
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

        if hasCards && (unchangedHash || unchangedEtag) {
            if let rows = try? JSONDecoder().decode([OnePieceSetRow].self, from: data) {
                let fp = Self.catalogFingerprint(from: rows)
                try? await store.setMeta("onepiece_catalog_row_fingerprint", fp)
            }
            await progress.addPlannedFiles(2)
            await progress.completeFile(byteCount: Int64(data.count))
            await progress.completeFile(byteCount: 0)
            if let etag { try? await store.setMeta("onepiece_catalog_sets_etag", etag) }
            let emptyCodes = (try? await store.fetchSetCodesWithNoCards(for: .onePiece)) ?? []
            if !emptyCodes.isEmpty { await patchMissingCards(setCodes: emptyCodes, progress: progress) }
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

        let rowFingerprint = Self.catalogFingerprint(from: rows)
        let storedFp = await store.meta("onepiece_catalog_row_fingerprint")
        let localFp: String? = await {
            guard let sets = try? await store.fetchAllSets(for: .onePiece), !sets.isEmpty else { return nil }
            return Self.catalogFingerprint(fromSetCodes: sets.map(\.setCode))
        }()
        let catalogStructureUnchanged =
            (storedFp == rowFingerprint) || (storedFp == nil && localFp == rowFingerprint)
        if hasCards && catalogStructureUnchanged {
            try? await store.setMeta("onepiece_catalog_sets_sha256", hash)
            if let etag { try? await store.setMeta("onepiece_catalog_sets_etag", etag) }
            try? await store.setMeta("onepiece_catalog_row_fingerprint", rowFingerprint)
            await progress.addPlannedFiles(2)
            await progress.completeFile(byteCount: Int64(data.count))
            await progress.completeFile(byteCount: 0)
            let emptyCodes = (try? await store.fetchSetCodesWithNoCards(for: .onePiece)) ?? []
            if !emptyCodes.isEmpty { await patchMissingCards(setCodes: emptyCodes, progress: progress) }
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
            try await store.upsertSets(rows.map { $0.asTCGSet() }, brand: .onePiece)
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
                        for stem in Self.pricingStemVariants(for: code) {
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
                    } else if let fallback = existingPricingBySetCode[code] {
                        try await store.upsertPricing(setCode: code, json: fallback, brand: .onePiece)
                        await progress.completeFile(byteCount: 0)
                    } else {
                        await progress.completeFile()
                    }
                }
            }
            try await store.setMeta("onepiece_catalog_sets_sha256", hash)
            if let etag { try await store.setMeta("onepiece_catalog_sets_etag", etag) }
            try await store.setMeta("onepiece_catalog_row_fingerprint", rowFingerprint)
        } catch {
            try? await store.setMeta("sync_failed", "1")
        }
    }

    func syncCatalogCardDeltas(progress: CatalogSyncProgressReporter) async -> Int64 {
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

    private func refreshBrowseMetadata() async {
        await refreshBrowseMetadataFile(
            path: "character-names.json",
            jsonMetaKey: "onepiece_character_names_json",
            etagMetaKey: "onepiece_character_names_etag"
        )
        await refreshBrowseMetadataFile(
            path: "character-subtypes.json",
            jsonMetaKey: "onepiece_character_subtypes_json",
            etagMetaKey: "onepiece_character_subtypes_etag"
        )
    }

    private func refreshBrowseMetadataFile(path: String, jsonMetaKey: String, etagMetaKey: String) async {
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
    }

    private func patchMissingCards(setCodes: [String], progress: CatalogSyncProgressReporter) async {
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

    static func pricingStemVariants(for setCode: String) -> [String] {
        let s = setCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return [] }
        var stems: [String] = []
        func add(_ x: String) {
            let t = x.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty, !stems.contains(t) { stems.append(t) }
        }
        add(s); add(s.uppercased()); add(s.lowercased())
        return stems
    }

    static func catalogFingerprint(fromSetCodes codes: [String]) -> String {
        let payload = codes.sorted().joined(separator: "\n").data(using: .utf8) ?? Data()
        return SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
    }

    static func catalogFingerprint(from rows: [OnePieceSetRow]) -> String {
        catalogFingerprint(fromSetCodes: rows.map(\.setCode))
    }
}
