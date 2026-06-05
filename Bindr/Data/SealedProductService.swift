import Foundation
import Observation

/// SQLite fetch + JSON decode for sealed daily blobs — runs off the main actor.
private enum SealedProductSQLiteLoader {
    struct LocalCache: Sendable {
        var products: [SealedProduct]?
        var marketPriceByID: [Int: Double]?
        var historyByID: [Int: SealedProductHistorySeries]?
    }

    static func load(includeHistory: Bool) async throws -> LocalCache {
        try await CatalogStore.shared.open()
        async let productsData = CatalogStore.shared.dailyBlob(key: DailyBlobKey.pokedataEnglishPokemonProducts)
        async let pricesData = CatalogStore.shared.dailyBlob(key: DailyBlobKey.sealedPrices)
        let historyData: Data?
        if includeHistory {
            historyData = await CatalogStore.shared.dailyBlob(key: DailyBlobKey.sealedPriceHistory)
        } else {
            historyData = nil
        }
        let (productsBlob, pricesBlob) = await (productsData, pricesData)

        return await Task.detached(priority: .userInitiated) {
            decode(productsData: productsBlob, pricesData: pricesBlob, historyData: historyData)
        }.value
    }

    static func loadHistoryOnly() async throws -> [Int: SealedProductHistorySeries]? {
        try await CatalogStore.shared.open()
        let historyData = await CatalogStore.shared.dailyBlob(key: DailyBlobKey.sealedPriceHistory)
        return await Task.detached(priority: .utility) {
            decode(productsData: nil, pricesData: nil, historyData: historyData).historyByID
        }.value
    }

    private static func parseFlatStringDoubleMap(_ data: Data) -> [String: Double]? {
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var bucket: [String: Double] = [:]
        bucket.reserveCapacity(raw.count)
        for (key, value) in raw {
            switch value {
            case let d as Double: bucket[key] = d
            case let f as Float: bucket[key] = Double(f)
            case let i as Int: bucket[key] = Double(i)
            case let n as NSNumber: bucket[key] = n.doubleValue
            case let s as String:
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if let d = Double(t) { bucket[key] = d }
            default: continue
            }
        }
        return bucket
    }

    private static func decode(
        productsData: Data?,
        pricesData: Data?,
        historyData: Data?
    ) -> LocalCache {
        let decoder = JSONDecoder()

        var decodedProducts: [SealedProduct]?
        if let data = productsData,
           let payload = try? decoder.decode(SealedProductsPayload.self, from: data) {
            decodedProducts = payload.products.sorted { lhs, rhs in
                let lDate = lhs.releaseDate ?? .distantPast
                let rDate = rhs.releaseDate ?? .distantPast
                if lDate != rDate { return lDate > rDate }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }

        var decodedPrices: [Int: Double]?
        if let data = pricesData,
           let flat = Self.parseFlatStringDoubleMap(data) {
            var next: [Int: Double] = [:]
            next.reserveCapacity(flat.count)
            for (k, v) in flat {
                if let id = Int(k) { next[id] = v }
            }
            decodedPrices = next
        }

        var decodedHistory: [Int: SealedProductHistorySeries]?
        if let data = historyData,
           let raw = try? JSONSerialization.jsonObject(with: data) as? [String: [String: [[Any]]]] {
            var result: [Int: SealedProductHistorySeries] = [:]
            result.reserveCapacity(raw.count)
            for (key, windows) in raw {
                guard let id = Int(key) else { continue }
                func parseWindow(_ wKey: String) -> [PriceDataPoint] {
                    guard let pairs = windows[wKey] else { return [] }
                    return pairs.compactMap { pair -> PriceDataPoint? in
                        guard pair.count >= 2, let label = pair[0] as? String else { return nil }
                        let price: Double
                        if let d = pair[1] as? Double { price = d }
                        else if let n = pair[1] as? NSNumber { price = n.doubleValue }
                        else if let s = pair[1] as? String, let d = Double(s) { price = d }
                        else { return nil }
                        return PriceDataPoint(id: label, label: label, price: price)
                    }
                }
                result[id] = SealedProductHistorySeries(
                    daily: parseWindow("daily"),
                    weekly: parseWindow("weekly"),
                    monthly: parseWindow("monthly")
                )
            }
            decodedHistory = result
        }

        return LocalCache(
            products: decodedProducts,
            marketPriceByID: decodedPrices,
            historyByID: decodedHistory
        )
    }
}

@Observable
@MainActor
final class SealedProductService {
    private(set) var products: [SealedProduct] = []
    private(set) var marketPriceByID: [Int: Double] = [:]
    private(set) var historyByID: [Int: SealedProductHistorySeries] = [:]
    private(set) var isLoading = false
    private(set) var lastError: String?

    private let session: URLSession
    // Coalesces concurrent local loads so only one SQLite decode runs at a time.
    private var localLoadTask: Task<Void, Never>?
    private var historyLoadTask: Task<Void, Never>?

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Loads products + market prices from SQLite. When `launchMode` is true, skips the large
    /// sealed price-history blob so launch catalog priming stays off the critical path (~3s saved).
    func loadFromLocalIfAvailable(launchMode: Bool = false) async {
        if !products.isEmpty, !marketPriceByID.isEmpty {
            if launchMode || !historyByID.isEmpty { return }
        }
        if let existing = localLoadTask {
            await existing.value
            return
        }
        let includeHistory = !launchMode
        let task = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let cache = try await SealedProductSQLiteLoader.load(includeHistory: includeHistory)
                await self.applyLocalCache(cache)
            } catch {
                await self.applyLocalLoadFailure(error)
            }
        }
        localLoadTask = task
        await task.value
        localLoadTask = nil
    }

    /// Loads the sealed price-history blob after launch when charts/detail need it.
    func loadSealedPriceHistoryIfNeeded() async {
        guard historyByID.isEmpty else { return }
        if let existing = historyLoadTask {
            await existing.value
            return
        }
        let task = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            do {
                let history = try await SealedProductSQLiteLoader.loadHistoryOnly()
                await self.applyHistoryOnly(history)
            } catch {
                // History is optional for browsing; ignore.
            }
        }
        historyLoadTask = task
        await task.value
        historyLoadTask = nil
    }

    /// Always reloads from SQLite, even if products are already in memory. Use this after a catalog
    /// sync that may have updated the stored blob (e.g. version bump downloaded new products).
    func reloadFromLocal() async {
        await loadFromSQLiteDailyBlobs(includeHistory: true)
    }

    func refreshFromNetworkAndStoreLocallyIfNeeded() async {
        // Always try SQLite first — daily sync populates it before the app opens.
        await loadFromSQLiteDailyBlobs(includeHistory: true)
        // Only hit the network if SQLite had nothing (e.g. very first launch before sync completes).
        if products.isEmpty {
            await fetchProductsFromNetworkAndStore()
        }
    }

    /// Fetches only the sealed product catalog (names/images); prices come from bucket sync.
    private func fetchProductsFromNetworkAndStore() async {
        guard AppConfiguration.r2BaseURL.host != "invalid.local" else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let productsURL = AppConfiguration.r2MarketURL(path: DailyBlobPath.pokedataEnglishPokemonProducts)
            let (productsData, _) = try await session.data(from: productsURL)
            guard !productsData.isEmpty else { return }

            try await CatalogStore.shared.open()
            try await CatalogStore.shared.upsertDailyBlob(key: DailyBlobKey.pokedataEnglishPokemonProducts, data: productsData)

            let sorted = await Task.detached(priority: .userInitiated) {
                guard let payload = try? JSONDecoder().decode(SealedProductsPayload.self, from: productsData) else { return [SealedProduct]() }
                return payload.products.sorted { lhs, rhs in
                    let lDate = lhs.releaseDate ?? .distantPast
                    let rDate = rhs.releaseDate ?? .distantPast
                    if lDate != rDate { return lDate > rDate }
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
            }.value
            if !sorted.isEmpty { products = sorted }
            lastError = nil
        } catch {
            if products.isEmpty {
                lastError = "Failed to load sealed products: \(error.localizedDescription)"
            }
        }
    }

    func marketPriceUSD(for productID: Int) -> Double? {
        marketPriceByID[productID]
    }

    func history(for productID: Int) -> SealedProductHistorySeries? {
        historyByID[productID]
    }

    private func loadFromSQLiteDailyBlobs(includeHistory: Bool) async {
        do {
            let cache = try await SealedProductSQLiteLoader.load(includeHistory: includeHistory)
            applyLocalCache(cache)
        } catch {
            applyLocalLoadFailure(error)
        }
    }

    private func applyLocalCache(_ cache: SealedProductSQLiteLoader.LocalCache) {
        if let parsedProducts = cache.products { products = parsedProducts }
        if let parsedPrices = cache.marketPriceByID { marketPriceByID = parsedPrices }
        if let parsedHistory = cache.historyByID { historyByID = parsedHistory }
        lastError = nil
    }

    private func applyHistoryOnly(_ history: [Int: SealedProductHistorySeries]?) {
        guard let history, !history.isEmpty else { return }
        historyByID = history
    }

    private func applyLocalLoadFailure(_ error: Error) {
        if products.isEmpty {
            lastError = "Failed to load sealed products: \(error.localizedDescription)"
        }
    }


    private func validatedBody(_ request: (Data, URLResponse)) throws -> Data {
        let (data, response) = request
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              !data.isEmpty else {
            throw SealedProductServiceError.invalidResponse
        }
        return data
    }
}

enum SealedProductServiceError: Error {
    case invalidResponse
}
