import Foundation

/// Large pricing-history JSON: primary copy is stored in SQLite (`card_price_history`) during daily market sync; network fetch is fallback.
enum PricingHistoryFetcher {
    static func fetchJSON(
        session: URLSession = .shared,
        setCode: String
    ) async throws -> Data {
        let url = AppConfiguration.r2PricingHistoryURL(setCode: setCode)
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}
