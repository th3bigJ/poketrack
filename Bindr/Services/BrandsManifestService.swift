import Foundation
import Observation

/// Fetches the hosted `brands.json` to determine **order** and optional **logo** paths on R2. Falls back to enum order if offline.
/// Uses ETag caching: persists the last ETag and decoded brand order in UserDefaults so subsequent launches
/// load instantly from the local cache and only re-parse when R2 actually has new data.
@Observable
@MainActor
final class BrandsManifestService {
    private static let etagKey = "brands_manifest_etag"
    private static let orderedBrandsKey = "brands_manifest_ordered_ids"
    private static let logoKeysKey = "brands_manifest_logo_keys"

    private(set) var orderedBrands: [TCGBrand] = TCGBrand.allCases.sorted { $0.menuOrder < $1.menuOrder }
    private var logoR2Keys: [TCGBrand: String] = [:]

    init() {
        loadFromCache()
    }

    /// Refreshes from the CDN using ETag; skips parsing when server returns 304. No-op when `BINDR_R2_BASE_URL` is unset.
    func refresh() async {
        guard AppConfiguration.r2BaseURL.host != "invalid.local" else { return }
        let url = AppConfiguration.brandsManifestURL
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let savedEtag = UserDefaults.standard.string(forKey: Self.etagKey), !savedEtag.isEmpty {
            request.setValue(savedEtag, forHTTPHeaderField: "If-None-Match")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            return
        }

        let http = response as? HTTPURLResponse

        // 304 Not Modified — cached brand order is still current, nothing to do.
        if http?.statusCode == 304 { return }

        let dto: BrandsManifestDTO
        do {
            dto = try JSONDecoder().decode(BrandsManifestDTO.self, from: data)
        } catch {
            return
        }

        var next: [TCGBrand] = []
        var logos: [TCGBrand: String] = [:]
        next.reserveCapacity(dto.brands.count)
        for row in dto.brands {
            guard let b = TCGBrand.fromManifestBrandId(row.id) else { continue }
            next.append(b)
            if let k = row.logo?.r2ObjectKey?.trimmingCharacters(in: .whitespacesAndNewlines), !k.isEmpty {
                logos[b] = k
            }
        }
        guard !next.isEmpty else { return }

        orderedBrands = next
        logoR2Keys = logos
        persistToCache(etag: http?.value(forHTTPHeaderField: "ETag") ?? http?.value(forHTTPHeaderField: "Etag"))
    }

    /// Remote logo when the bundled asset should not be used (see ``BrandCatalogCarousel``).
    func remoteLogoURL(for brand: TCGBrand) -> URL? {
        guard let key = logoR2Keys[brand], !key.isEmpty else { return nil }
        return AppConfiguration.imageURL(relativePath: key)
    }

    func sortBrands(_ brands: Set<TCGBrand>) -> [TCGBrand] {
        let order = orderedBrands
        return brands.sorted { a, b in
            let ia = order.firstIndex(of: a) ?? Int.max
            let ib = order.firstIndex(of: b) ?? Int.max
            if ia != ib { return ia < ib }
            return a.menuOrder < b.menuOrder
        }
    }

    func brandsAvailableToAdd(enabled: Set<TCGBrand>) -> [TCGBrand] {
        orderedBrands.filter { !enabled.contains($0) }
    }

    // MARK: - UserDefaults persistence

    private func loadFromCache() {
        let defaults = UserDefaults.standard
        guard let ids = defaults.array(forKey: Self.orderedBrandsKey) as? [String], !ids.isEmpty else { return }
        let brands = ids.compactMap { TCGBrand.fromManifestBrandId($0) }
        guard !brands.isEmpty else { return }
        orderedBrands = brands

        if let logoDict = defaults.dictionary(forKey: Self.logoKeysKey) as? [String: String] {
            var logos: [TCGBrand: String] = [:]
            for (id, key) in logoDict {
                if let brand = TCGBrand.fromManifestBrandId(id) {
                    logos[brand] = key
                }
            }
            logoR2Keys = logos
        }
    }

    private func persistToCache(etag: String?) {
        let defaults = UserDefaults.standard
        defaults.set(orderedBrands.map { $0.manifestBrandId }, forKey: Self.orderedBrandsKey)
        var logoDict: [String: String] = [:]
        for (brand, key) in logoR2Keys {
            logoDict[brand.manifestBrandId] = key
        }
        defaults.set(logoDict, forKey: Self.logoKeysKey)
        if let etag, !etag.isEmpty {
            defaults.set(etag, forKey: Self.etagKey)
        }
    }
}

private struct BrandsManifestDTO: Codable, Sendable {
    let schemaVersion: Int
    let brands: [BrandRow]

    struct BrandRow: Codable, Sendable {
        let id: String
        let logo: Logo?

        struct Logo: Codable, Sendable {
            let r2ObjectKey: String?
        }
    }
}
