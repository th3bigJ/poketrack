import Foundation

struct SealedProductCatalogPayload: Codable {
    let scrapedAt: String
    let products: [SealedProductEntry]
}

struct SealedProductEntry: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let tcg: String?
    let language: String?
    let type: String?
    let release_date: String?
    let year: Int?
    let series: String?
    let set_id: Int?
    let live: Bool
    let hot: Int
    let image: SealedProductImage
}

struct SealedProductImage: Codable, Hashable {
    let source_url: String?
    let r2_key: String?
    let public_url: String?
}

struct SealedProductPricesPayload: Codable {
    let prices: [String: SealedProductPriceEntry]
}

struct SealedProductPriceEntry: Codable, Hashable {
    let id: Int
    let market_value: Double?
    let currency: String
    let live: Bool
}
