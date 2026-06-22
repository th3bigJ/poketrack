import Foundation

struct CatalogSetKey: Hashable, Sendable {
    let brand: TCGBrand
    let setCode: String
}

actor CardCatalogWorker {
    struct CatalogSetsResult: Sendable {
        let sets: [TCGSet]
        let errorMessage: String?
    }

    private let store: CatalogStore

    // These caches become the worker-owned source of truth as the card lookup,
    // feed and search methods move across in the next phase.
    private var cardsBySet: [CatalogSetKey: [Card]] = [:]
    private var cardByMasterID: [String: Card] = [:]
    private var normalizedNameByCardID: [String: String] = [:]
    private var normalizedSearchBlobByCardID: [String: String] = [:]
    private var sessionFeedRefs: [TCGBrand: [CardRef]] = [:]

    init(store: CatalogStore = .shared) {
        self.store = store
    }

    func catalogSetsResult(for brand: TCGBrand) async -> CatalogSetsResult {
        do {
            try await store.open()
            let rows = try await store.fetchAllSets(for: brand)
            let sortedSets = rows.sorted {
                ($0.releaseDate ?? "") > ($1.releaseDate ?? "")
            }
            guard !sortedSets.isEmpty else {
                return CatalogSetsResult(
                    sets: [],
                    errorMessage: "No \(brand.displayTitle) catalog on this device. Turn the game on under Card catalog and download while online."
                )
            }
            return CatalogSetsResult(sets: sortedSets, errorMessage: nil)
        } catch {
            return CatalogSetsResult(sets: [], errorMessage: error.localizedDescription)
        }
    }
}
