import Foundation
import Observation

@Observable
final class SealedCatalogService {
    private(set) var catalog: SealedProductCatalogPayload?
    private(set) var prices: SealedProductPricesPayload?
    private(set) var lastError: String?

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func loadAll() async {
        lastError = nil
        let base = AppConfiguration.r2BaseURL
        guard base.host != "invalid.local" else {
            lastError = "Configure R2 base URL."
            return
        }
        let productsURL = AppConfiguration.r2SealedURL(path: "sealed-products/pokedata/pokedata-english-pokemon-products.json")
        let pricesURL = AppConfiguration.r2SealedURL(path: "sealed-products/pokedata/pokedata-english-pokemon-prices.json")

        do {
            async let p: Data = session.data(from: productsURL).0
            async let r: Data = session.data(from: pricesURL).0
            let (pd, rd) = try await (p, r)
            catalog = try JSONDecoder().decode(SealedProductCatalogPayload.self, from: pd)
            prices = try JSONDecoder().decode(SealedProductPricesPayload.self, from: rd)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func gbpPrice(productId: Int, usdToGbp: Double) -> Double? {
        guard let prices else { return nil }
        let key = String(productId)
        guard let entry = prices.prices[key] else { return nil }
        guard let mv = entry.market_value else { return nil }
        return mv * usdToGbp
    }
}
