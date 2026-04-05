import Foundation
import Observation

@Observable
final class PricingService {
    private(set) var usdToGbp: Double = 0.79
    private(set) var lastFXError: String?

    private var pricingCache: [String: (map: SetPricingMap, expiry: Date)] = [:]

    private let session: URLSession
    private let fileManager: FileManager
    private let cacheTTL: TimeInterval = 24 * 60 * 60

    init(session: URLSession = .shared, fileManager: FileManager = .default) {
        self.session = session
        self.fileManager = fileManager
    }

    private var cacheDirectory: URL {
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("pricing", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func refreshFXRate() async {
        lastFXError = nil
        let url = URL(string: "https://api.frankfurter.app/latest?from=USD&to=GBP")!
        do {
            let (data, _) = try await session.data(from: url)
            let decoded = try JSONDecoder().decode(FrankfurterResponse.self, from: data)
            if let gbp = decoded.rates["GBP"] {
                usdToGbp = gbp
            }
        } catch {
            lastFXError = error.localizedDescription
            usdToGbp = 0.79
        }
    }

    func pricing(for card: Card) async -> CardPricingEntry? {
        guard let external = card.externalId, !external.isEmpty else { return nil }
        let map = await loadPricingMap(setCode: card.setCode)
        // Ignore catalog `noPricing` when R2 has a row — flag is often stale vs nightly pricing JSON.
        return map[external]
    }

    func gbpPrice(for card: Card, printing: String) async -> Double? {
        guard let entry = await pricing(for: card) else { return nil }
        guard let scrydex = entry.scrydex, !scrydex.isEmpty else { return nil }
        guard let usd = scrydexUSD(from: scrydex, printing: printing) else { return nil }
        return usd * usdToGbp
    }

    /// Picks a Scrydex `raw` USD price. Many sets only publish `holofoil` (no `normal`); try common keys before any available variant.
    private func scrydexUSD(from scrydex: [String: ScrydexVariantPricing], printing: String) -> Double? {
        let preferred = PrintingVariant.scrydexKey(forPrinting: printing)
        let fallbackKeys = [
            preferred,
            "normal",
            "holofoil",
            "reverseHolofoil",
            "unlimited",
            "unlimitedHolofoil",
            "firstEdition",
            "firstEditionHolofoil",
            "shadowless",
        ]
        for key in fallbackKeys {
            if let raw = scrydex[key]?.raw {
                return raw
            }
        }
        for (_, variant) in scrydex {
            if let raw = variant.raw {
                return raw
            }
        }
        return nil
    }

    private func loadPricingMap(setCode: String) async -> SetPricingMap {
        if let hit = pricingCache[setCode], hit.expiry > Date() {
            return hit.map
        }

        if let disk = loadDiskCache(setCode: setCode) {
            pricingCache[setCode] = (disk, Date().addingTimeInterval(cacheTTL))
            return disk
        }

        let base = AppConfiguration.r2BaseURL
        guard base.host != "invalid.local" else { return [:] }

        let url = AppConfiguration.r2PricingURL(path: "pricing/\(setCode).json")
        do {
            let (data, _) = try await session.data(from: url)
            let map = try JSONDecoder().decode(SetPricingMap.self, from: data)
            pricingCache[setCode] = (map, Date().addingTimeInterval(cacheTTL))
            saveDiskCache(setCode: setCode, data: data)
            return map
        } catch {
            return [:]
        }
    }

    private func loadDiskCache(setCode: String) -> SetPricingMap? {
        let url = cacheDirectory.appendingPathComponent("\(setCode).json")
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        guard let attrs = try? fileManager.attributesOfItem(atPath: url.path),
              let mod = attrs[.modificationDate] as? Date,
              Date().timeIntervalSince(mod) < cacheTTL else {
            return nil
        }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SetPricingMap.self, from: data)
    }

    private func saveDiskCache(setCode: String, data: Data) {
        let url = cacheDirectory.appendingPathComponent("\(setCode).json")
        try? data.write(to: url, options: .atomic)
    }
}

private struct FrankfurterResponse: Decodable {
    let rates: [String: Double]
}
