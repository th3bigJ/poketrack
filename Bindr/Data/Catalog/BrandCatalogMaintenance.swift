import Foundation

/// Removes downloaded catalog + legacy on-disk ONE PIECE files when a franchise is turned off in Account.
enum BrandCatalogMaintenance {
    static func purgeLocalData(for brand: TCGBrand) throws {
        try CatalogStore.shared.open()
        try CatalogStore.shared.purgeCatalogData(for: brand)
        try OfflineImageStore.shared.deleteAll(for: brand)
        if brand == .onePiece {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let dir = docs.appendingPathComponent("onepiece", isDirectory: true)
            if FileManager.default.fileExists(atPath: dir.path) {
                try? FileManager.default.removeItem(at: dir)
            }
        }
    }
}
