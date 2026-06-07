import Foundation
import Observation

@Observable
@MainActor
final class VariantsCatalogService {
    static let auxBlobKey = "variants_catalog_json"
    static let etagMetaKey = "catalog_variants_etag"

    private(set) var catalog: VariantsCatalog = .fallback

    private var masterSetKeys: Set<String> = VariantsCatalog.fallback.normalizedMasterSet()
    private var grandMasterSetKeys: Set<String> = VariantsCatalog.fallback.normalizedGrandMasterSet()
    private var championshipKeys: Set<String> = VariantsCatalog.fallback.normalizedChampionshipSet()
    private var slotCountCache: [String: Int] = [:]

    func reloadFromStore() async {
        if let data = await CatalogStore.shared.auxBlob(key: Self.auxBlobKey),
           let decoded = try? JSONDecoder().decode(VariantsCatalog.self, from: data) {
            apply(decoded)
        }
    }

    func invalidateSlotCountCache() {
        slotCountCache.removeAll()
    }

    func isChampionshipVariant(_ key: String) -> Bool {
        let normalized = normalizedVariantKey(key)
        guard !normalized.isEmpty else { return false }
        return championshipKeys.contains(normalized)
    }

    func includesVariant(_ key: String, mode: SetCompletionMode) -> Bool {
        let normalized = normalizedVariantKey(key)
        guard !normalized.isEmpty else { return false }
        if championshipKeys.contains(normalized) { return false }
        switch mode {
        case .full:
            return false
        case .master:
            return masterSetKeys.contains(normalized)
        case .grandMaster:
            return masterSetKeys.contains(normalized) || grandMasterSetKeys.contains(normalized)
        }
    }

    func eligibleVariantKeys(from pricingKeys: [String], card: Card?, mode: SetCompletionMode) -> [String] {
        guard mode != .full else { return [] }

        var keys = pricingKeys.filter { $0 != "default" }
        if keys.isEmpty, let variants = card?.pricingVariants, !variants.isEmpty {
            keys = variants.filter { $0 != "default" }
        }
        if keys.isEmpty {
            keys = ["normal"]
        }

        var seen: Set<String> = []
        var eligible: [String] = []
        for key in keys {
            let normalized = normalizedVariantKey(key)
            guard !normalized.isEmpty, !seen.contains(normalized) else { continue }
            guard includesVariant(key, mode: mode) else { continue }
            seen.insert(normalized)
            eligible.append(key)
        }
        return eligible
    }

    func variantSlotCount(
        forSetCode setCode: String,
        mode: SetCompletionMode,
        cardData: CardDataService,
        pricing: PricingService
    ) async -> Int {
        guard mode != .full else { return 0 }
        let cacheKey = "\(setCode.lowercased())|\(mode.rawValue)"
        if let cached = slotCountCache[cacheKey] { return cached }

        let cards = await cardData.loadCards(forSetCode: setCode)
        var count = 0
        for card in cards {
            let pricingKeys = await pricing.variantKeys(for: card)
            count += eligibleVariantKeys(from: pricingKeys, card: card, mode: mode).count
        }
        slotCountCache[cacheKey] = count
        return count
    }

    func fullSetSlotMarketUSD(for entry: CardPricingEntry) -> Double? {
        if let scrydex = entry.scrydex, !scrydex.isEmpty {
            let prices = scrydex.compactMap { key, pricing -> Double? in
                guard !isChampionshipVariant(key) else { return nil }
                return pricing.rawMarketEstimateUSD()
            }.filter { $0 > 0 }
            if let cheapest = prices.min() {
                return cheapest
            }
        }
        if let usd = entry.tcgplayerMarketEstimateUSD(), usd > 0 {
            return usd
        }
        return nil
    }

    func marketUSD(for entry: CardPricingEntry, mode: SetCompletionMode, eligibleVariantKeys: [String]) -> Double {
        switch mode {
        case .full:
            return fullSetSlotMarketUSD(for: entry) ?? 0
        case .master, .grandMaster:
            guard let scrydex = entry.scrydex, !scrydex.isEmpty else {
                return entry.tcgplayerMarketEstimateUSD() ?? 0
            }
            let allowed = Set(eligibleVariantKeys.map { normalizedVariantKey($0) })
            return scrydex.reduce(0) { partial, pair in
                guard allowed.contains(normalizedVariantKey(pair.key)),
                      let usd = pair.value.marketEstimateUSD(),
                      usd > 0 else {
                    return partial
                }
                return partial + usd
            }
        }
    }

    private func apply(_ decoded: VariantsCatalog) {
        catalog = decoded
        masterSetKeys = decoded.normalizedMasterSet()
        grandMasterSetKeys = decoded.normalizedGrandMasterSet()
        championshipKeys = decoded.normalizedChampionshipSet()
        invalidateSlotCountCache()
    }

    private func normalizedVariantKey(_ key: String) -> String {
        key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
