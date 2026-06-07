import Foundation

/// Removes downloaded catalog + on-disk files when a franchise is turned off in Account.
enum BrandCatalogMaintenance {
    static func purgeLocalData(for brand: TCGBrand) async throws {
        try await CatalogStore.shared.open()
        try await CatalogStore.shared.purgeCatalogData(for: brand)
        try OfflineImageStore.shared.deleteAll(for: brand)
    }
}
