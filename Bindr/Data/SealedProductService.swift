import Foundation
import Observation

@Observable
@MainActor
final class SealedProductService {
    private(set) var products: [SealedProduct] = []
    private(set) var marketPriceByID: [Int: Double] = [:]
    private(set) var historyByID: [Int: SealedProductHistorySeries] = [:]
    private(set) var isLoading = false
    private(set) var lastError: String?

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func loadFromLocalIfAvailable() async {
        if products.isEmpty == false, marketPriceByID.isEmpty == false {
            return
        }
        await loadFromSQLiteDailyBlobs()
    }

    /// Always reloads from SQLite, even if products are already in memory. Use this after a catalog
    /// sync that may have updated the stored blob (e.g. version bump downloaded new products).
    func reloadFromLocal() async {
        await loadFromSQLiteDailyBlobs()
    }

    func refreshFromNetworkAndStoreLocallyIfNeeded() async {
        // Always try SQLite first — daily sync populates it before the app opens.
        await loadFromSQLiteDailyBlobs()
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

    private func loadFromSQLiteDailyBlobs() async {
        do {
            try await CatalogStore.shared.open()
            let productsData = await CatalogStore.shared.dailyBlob(key: DailyBlobKey.pokedataEnglishPokemonProducts)
            let pricesData = await CatalogStore.shared.dailyBlob(key: DailyBlobKey.sealedPrices)
            let historyData = await CatalogStore.shared.dailyBlob(key: DailyBlobKey.sealedPriceHistory)

            // All three blobs are potentially large — decode off the main actor.
            let (parsedProducts, parsedPrices, parsedHistory) = await Task.detached(priority: .userInitiated) {
                let decoder = JSONDecoder()

                var decodedProducts: [SealedProduct]? = nil
                if let data = productsData,
                   let payload = try? decoder.decode(SealedProductsPayload.self, from: data) {
                    decodedProducts = payload.products.sorted { lhs, rhs in
                        let lDate = lhs.releaseDate ?? .distantPast
                        let rDate = rhs.releaseDate ?? .distantPast
                        if lDate != rDate { return lDate > rDate }
                        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                    }
                }

                var decodedPrices: [Int: Double]? = nil
                if let data = pricesData,
                   let flat = try? JSONSerialization.jsonObject(with: data) as? [String: Double] {
                    var next: [Int: Double] = [:]
                    next.reserveCapacity(flat.count)
                    for (k, v) in flat { if let id = Int(k) { next[id] = v } }
                    decodedPrices = next
                }

                var decodedHistory: [Int: SealedProductHistorySeries]? = nil
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

                return (decodedProducts, decodedPrices, decodedHistory)
            }.value

            if let parsedProducts { products = parsedProducts }
            if let parsedPrices { marketPriceByID = parsedPrices }
            if let parsedHistory { historyByID = parsedHistory }
            lastError = nil
        } catch {
            if products.isEmpty {
                lastError = "Failed to load sealed products: \(error.localizedDescription)"
            }
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
