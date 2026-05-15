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

            let decoder = JSONDecoder()
            if let payload = try? decoder.decode(SealedProductsPayload.self, from: productsData) {
                products = sortedProducts(payload.products)
            }
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

            let decoder = JSONDecoder()

            if let productsData,
               let payload = try? decoder.decode(SealedProductsPayload.self, from: productsData) {
                products = sortedProducts(payload.products)
            }

            if let pricesData,
               let flatPrices = try? JSONSerialization.jsonObject(with: pricesData) as? [String: Double] {
                var next: [Int: Double] = [:]
                for (k, v) in flatPrices {
                    if let id = Int(k) { next[id] = v }
                }
                marketPriceByID = next
            }

            if let historyData,
               let raw = try? JSONSerialization.jsonObject(with: historyData) as? [String: [String: [[Any]]]] {
                historyByID = decodeSealedHistory(raw)
            }

            lastError = nil
        } catch {
            if products.isEmpty {
                lastError = "Failed to load sealed products: \(error.localizedDescription)"
            }
        }
    }

    /// Decodes sealed history from the SQLite blob shape:
    /// `{ "productId": { "daily": [[dateKey, price], …], "weekly": […], "monthly": […] } }`
    private func decodeSealedHistory(_ raw: [String: [String: [[Any]]]]) -> [Int: SealedProductHistorySeries] {
        var result: [Int: SealedProductHistorySeries] = [:]
        for (key, windows) in raw {
            guard let id = Int(key) else { continue }
            func parseWindow(_ key: String) -> [PriceDataPoint] {
                guard let pairs = windows[key] else { return [] }
                return pairs.compactMap { pair -> PriceDataPoint? in
                    guard pair.count >= 2, let label = pair[0] as? String else { return nil }
                    let price: Double
                    if let d = pair[1] as? Double {
                        price = d
                    } else if let n = pair[1] as? NSNumber {
                        price = n.doubleValue
                    } else if let s = pair[1] as? String, let d = Double(s) {
                        price = d
                    } else {
                        return nil
                    }
                    return PriceDataPoint(id: label, label: label, price: price)
                }
            }
            result[id] = SealedProductHistorySeries(
                daily: parseWindow("daily"),
                weekly: parseWindow("weekly"),
                monthly: parseWindow("monthly")
            )
        }
        return result
    }

    private func sortedProducts(_ list: [SealedProduct]) -> [SealedProduct] {
        list.sorted { lhs, rhs in
            let lDate = lhs.releaseDate ?? .distantPast
            let rDate = rhs.releaseDate ?? .distantPast
            if lDate != rDate { return lDate > rDate }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
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
