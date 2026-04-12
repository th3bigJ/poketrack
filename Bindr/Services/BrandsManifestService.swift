import Foundation
import Observation

/// Fetches the hosted `brands.json` to determine **order** and optional **logo** paths on R2. Falls back to enum order if offline.
@Observable
@MainActor
final class BrandsManifestService {
    private(set) var orderedBrands: [TCGBrand] = TCGBrand.allCases.sorted { $0.menuOrder < $1.menuOrder }
    private var logoR2Keys: [TCGBrand: String] = [:]

    /// Refreshes from the CDN (no-op when `BINDR_R2_BASE_URL` is unset).
    func refresh() async {
        guard AppConfiguration.r2BaseURL.host != "invalid.local" else { return }
        let url = AppConfiguration.brandsManifestURL
        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(from: url)
        } catch {
            return
        }
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
