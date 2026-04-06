import Foundation

/// Large pricing-history JSON: fetch from R2 when needed (not stored in the main SQLite catalog).
enum PricingHistoryFetcher {
    static func fetchJSON(
        session: URLSession = .shared,
        setCode: String,
        cardKey: String
    ) async throws -> Data {
        let url = AppConfiguration.r2PricingHistoryURL(setCode: setCode, cardKey: cardKey)
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}
