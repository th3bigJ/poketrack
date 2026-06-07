import CryptoKit
import Foundation

/// Handles Pokémon sets.json + per-set card JSON sync into SQLite.
struct PokemonCatalogSyncPhase {
    let session: URLSession
    let store: CatalogStore

    private let pokemonNationalDexAuxBlobKey = "pokemon_national_dex_json"
    private let variantsCatalogAuxBlobKey = VariantsCatalogService.auxBlobKey

    func syncCatalogIfNeeded(progress: CatalogSyncProgressReporter) async {
        guard AppConfiguration.r2BaseURL.host != "invalid.local" else { return }
        let setsURL = AppConfiguration.r2CatalogURL(path: "sets.json")
        await progress.setStatus("Checking card catalog…")

        var setsRequest = URLRequest(url: setsURL)
        if let prevEtag = await store.meta("catalog_etag"), !prevEtag.isEmpty {
            setsRequest.setValue(prevEtag, forHTTPHeaderField: "If-None-Match")
        }

        let data: Data
        let http: HTTPURLResponse?
        do {
            let (d, resp) = try await session.data(for: setsRequest)
            http = resp as? HTTPURLResponse
            if http?.statusCode == 304 {
                await progress.addPlannedFiles(2)
                await progress.completeFile(byteCount: 0)
                await progress.completeFile(byteCount: 0)
                return
            }
            data = d
        } catch {
            await progress.addPlannedFiles(2)
            await progress.completeFile()
            await progress.completeFile()
            return
        }

        let etag = http?.value(forHTTPHeaderField: "ETag") ?? http?.value(forHTTPHeaderField: "Etag")
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()

        let storedSetsHash = await store.meta("catalog_sets_sha256")
        let storedSetsEtag = await store.meta("catalog_etag")
        let unchangedHash = storedSetsHash == hash
        let unchangedEtag = etag != nil && storedSetsEtag == etag
        let hasCards = (try? await store.hasAnyCards(for: .pokemon)) ?? false
        if hasCards && (unchangedHash || unchangedEtag) {
            await progress.addPlannedFiles(2)
            await progress.completeFile(byteCount: 0)
            await progress.completeFile(byteCount: 0)
            return
        }

        let sets: [TCGSet]
        do {
            sets = try JSONDecoder().decode([TCGSet].self, from: data)
        } catch {
            await progress.addPlannedFiles(2)
            await progress.completeFile(byteCount: 0)
            await progress.completeFile(byteCount: 0)
            return
        }

        do {
            try await store.open()
            let existingSets = try await store.fetchAllSets(for: .pokemon)
            let existingCodes = Set(existingSets.map(\.setCode))

            var setsToDownload: [TCGSet] = []
            let setsWithNoCards = try await store.fetchSetCodesWithNoCards(for: .pokemon)
            for set in sets {
                let hasCards = !setsWithNoCards.contains(set.setCode)
                if !existingCodes.contains(set.setCode) || !hasCards {
                    setsToDownload.append(set)
                }
            }

            await progress.addPlannedFiles(1 + setsToDownload.count)
            await progress.completeFile(byteCount: Int64(data.count))

            try await store.upsertSets(sets, brand: .pokemon)

            if setsToDownload.isEmpty {
                try await store.setMeta("catalog_sets_sha256", hash)
                if let etag { try await store.setMeta("catalog_etag", etag) }
                return
            }

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
            if let etag { try await store.setMeta("catalog_etag", etag) }
            try await store.setMeta("catalog_import_at", String(Date().timeIntervalSince1970))
        } catch {
            try? await store.setMeta("sync_failed", "1")
        }
    }

    func refreshVariantsCatalog() async {
        guard AppConfiguration.r2BaseURL.host != "invalid.local" else { return }
        let url = AppConfiguration.r2CatalogURL(path: "variants.json")
        do {
            var request = URLRequest(url: url)
            if let prevEtag = await store.meta(VariantsCatalogService.etagMetaKey), !prevEtag.isEmpty {
                request.setValue(prevEtag, forHTTPHeaderField: "If-None-Match")
            }
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return }
            if http.statusCode == 304 {
                try? await store.touchAuxBlobFetchedAt(key: variantsCatalogAuxBlobKey)
                return
            }
            guard (200...299).contains(http.statusCode), !data.isEmpty else { return }
            guard (try? JSONDecoder().decode(VariantsCatalog.self, from: data)) != nil else { return }
            try? await store.upsertAuxBlob(key: variantsCatalogAuxBlobKey, data: data)
            if let etag = http.value(forHTTPHeaderField: "ETag") ?? http.value(forHTTPHeaderField: "Etag") {
                try? await store.setMeta(VariantsCatalogService.etagMetaKey, etag)
            }
        } catch {}
    }

    func refreshNationalDexMetadata() async {
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
            guard (try? JSONDecoder().decode([NationalDexPokemon].self, from: data)) != nil else { return }
            try? await store.upsertAuxBlob(key: pokemonNationalDexAuxBlobKey, data: data)
            if let etag = http.value(forHTTPHeaderField: "ETag") ?? http.value(forHTTPHeaderField: "Etag") {
                try? await store.setMeta("pokemon_national_dex_etag", etag)
            }
        } catch {}
    }

    func syncCatalogCardDeltas(progress: CatalogSyncProgressReporter) async -> Int64 {
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

    func fillMissingSetCards() async {
        guard AppConfiguration.r2BaseURL.host != "invalid.local" else { return }
        let emptyCodes: [String]
        do { emptyCodes = try await store.fetchSetCodesWithNoCards(for: .pokemon) } catch { return }
        guard !emptyCodes.isEmpty else { return }
        let sess = session
        await withTaskGroup(of: Void.self) { group in
            for code in emptyCodes {
                group.addTask {
                    let url = AppConfiguration.r2CatalogURL(path: "cards/\(code).json")
                    guard let data = try? await sess.data(from: url).0,
                          let cards = try? JSONDecoder().decode([Card].self, from: data),
                          !cards.isEmpty
                    else { return }
                    try? await self.store.insertCards(cards, setCode: code, brand: .pokemon)
                }
            }
        }
    }
}
