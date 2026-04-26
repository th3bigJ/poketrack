import Foundation
import Observation

@Observable
@MainActor
final class SealedProductService {
    private(set) var products: [SealedProduct] = []
    private(set) var marketPriceByID: [Int: Double] = [:]
    private(set) var historyByID: [Int: SealedProductHistorySeries] = [:]
    private(set) var trendsByID: [Int: SealedProductTrendEntry] = [:]
    private(set) var isLoading = false
    private(set) var lastError: String?

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func loadFromLocalIfAvailable() {
        if products.isEmpty == false,
           marketPriceByID.isEmpty == false,
           historyByID.isEmpty == false,
           trendsByID.isEmpty == false {
            return
        }
        loadFromSQLiteDailyBlobs()
    }

    func refreshFromNetworkAndStoreLocallyIfNeeded() async {
        guard AppConfiguration.r2BaseURL.host != "invalid.local" else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let productsURL = AppConfiguration.r2MarketURL(path: DailyBlobPath.pokedataEnglishPokemonProducts)
            let pricesURL = AppConfiguration.r2MarketURL(path: DailyBlobPath.pokedataEnglishPokemonPrices)
            let historyURL = AppConfiguration.r2MarketURL(path: DailyBlobPath.pokedataEnglishPokemonPriceHistory)
            let trendsURL = AppConfiguration.r2MarketURL(path: DailyBlobPath.pokedataEnglishPokemonPriceTrends)

            async let productsDataTask = session.data(from: productsURL)
            async let pricesDataTask = session.data(from: pricesURL)
            async let historyDataTask = session.data(from: historyURL)
            async let trendsDataTask = session.data(from: trendsURL)

            let productsData = try validatedBody(await productsDataTask)
            let pricesData = try validatedBody(await pricesDataTask)
            let historyData = try validatedBody(await historyDataTask)
            let trendsData = try validatedBody(await trendsDataTask)

            try CatalogStore.shared.open()
            try CatalogStore.shared.upsertDailyBlob(key: DailyBlobKey.pokedataEnglishPokemonProducts, data: productsData)
            try CatalogStore.shared.upsertDailyBlob(key: DailyBlobKey.pokedataEnglishPokemonPrices, data: pricesData)
            try CatalogStore.shared.upsertDailyBlob(key: DailyBlobKey.pokedataEnglishPokemonPriceHistory, data: historyData)
            try CatalogStore.shared.upsertDailyBlob(key: DailyBlobKey.pokedataEnglishPokemonPriceTrends, data: trendsData)

            decodeAndAssign(
                productsData: productsData,
                pricesData: pricesData,
                historyData: historyData,
                trendsData: trendsData
            )
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

    func trends(for productID: Int) -> SealedProductTrendEntry? {
        trendsByID[productID]
    }

    private func loadFromSQLiteDailyBlobs() {
        do {
            try CatalogStore.shared.open()
            let productsData = CatalogStore.shared.dailyBlob(key: DailyBlobKey.pokedataEnglishPokemonProducts)
            let pricesData = CatalogStore.shared.dailyBlob(key: DailyBlobKey.pokedataEnglishPokemonPrices)
            let historyData = CatalogStore.shared.dailyBlob(key: DailyBlobKey.pokedataEnglishPokemonPriceHistory)
            let trendsData = CatalogStore.shared.dailyBlob(key: DailyBlobKey.pokedataEnglishPokemonPriceTrends)

            guard let productsData,
                  let pricesData,
                  let historyData,
                  let trendsData else {
                return
            }

            decodeAndAssign(
                productsData: productsData,
                pricesData: pricesData,
                historyData: historyData,
                trendsData: trendsData
            )
            lastError = nil
        } catch {
            if products.isEmpty {
                lastError = "Failed to load sealed products: \(error.localizedDescription)"
            }
        }
    }

    private func decodeAndAssign(
        productsData: Data,
        pricesData: Data,
        historyData: Data,
        trendsData: Data
    ) {
        let decoder = JSONDecoder()
        let productsPayload = (try? decoder.decode(SealedProductsPayload.self, from: productsData))
        let pricesPayload = (try? decoder.decode(SealedProductPricesPayload.self, from: pricesData))
        let historyPayload = (try? decoder.decode([String: SealedProductHistorySeries].self, from: historyData)) ?? [:]
        let trendsPayload = (try? decoder.decode([String: SealedProductTrendEntry].self, from: trendsData)) ?? [:]

        products = (productsPayload?.products ?? []).sorted { lhs, rhs in
            let lDate = lhs.releaseDate ?? .distantPast
            let rDate = rhs.releaseDate ?? .distantPast
            if lDate != rDate { return lDate > rDate }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        var nextPrices: [Int: Double] = [:]
        for (key, value) in pricesPayload?.prices ?? [:] {
            let id = value.id
            let numericKey = Int(key) ?? id
            if let market = value.marketValue {
                nextPrices[numericKey] = market
            }
        }
        marketPriceByID = nextPrices

        historyByID = Dictionary(uniqueKeysWithValues: historyPayload.compactMap { key, value in
            guard let id = Int(key) else { return nil }
            return (id, value)
        })

        trendsByID = Dictionary(uniqueKeysWithValues: trendsPayload.compactMap { key, value in
            guard let id = Int(key) else { return nil }
            return (id, value)
        })
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
