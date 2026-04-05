import Foundation

enum AppConfiguration {
    /// Single non-consumable premium product — create the same ID in App Store Connect.
    static let premiumProductID = "app1xy.PokeTrack.premium"

    static let cloudKitContainerIdentifier = "iCloud.app1xy.PokeTrack"

    /// Public CDN base (no trailing slash). Set `POKETRACK_R2_BASE_URL` in Info.plist or env.
    static var r2BaseURL: URL {
        if let s = Bundle.main.object(forInfoDictionaryKey: "POKETRACK_R2_BASE_URL") as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty, let u = URL(string: t) { return u }
        }
        if let env = ProcessInfo.processInfo.environment["POKETRACK_R2_BASE_URL"],
           !env.isEmpty,
           let u = URL(string: env) {
            return u
        }
        return URL(string: "https://invalid.local")!
    }

    // MARK: - Path prefixes (your bucket may mix folders: e.g. JSON under `data/`, pricing + images at root)

    /// `sets.json` and `cards/{setCode}.json` — e.g. `data` → `…/data/sets.json`. Keys: `POKETRACK_R2_CATALOG_PREFIX` or legacy `POKETRACK_R2_DATA_PREFIX`; default `data`.
    static var r2CatalogPathPrefix: String {
        if hasPlistOrEnv("POKETRACK_R2_CATALOG_PREFIX") {
            return plistOrEnvTrimmed("POKETRACK_R2_CATALOG_PREFIX") ?? ""
        }
        if hasPlistOrEnv("POKETRACK_R2_DATA_PREFIX") {
            return plistOrEnvTrimmed("POKETRACK_R2_DATA_PREFIX") ?? ""
        }
        return "data"
    }

    /// `pricing/{setCode}.json` — empty = bucket root. Key: `POKETRACK_R2_PRICING_PREFIX`.
    static var r2PricingPathPrefix: String {
        if hasPlistOrEnv("POKETRACK_R2_PRICING_PREFIX") {
            return plistOrEnvTrimmed("POKETRACK_R2_PRICING_PREFIX") ?? ""
        }
        return ""
    }

    /// `sealed-products/...` — empty = bucket root. Key: `POKETRACK_R2_SEALED_PREFIX`.
    static var r2SealedPathPrefix: String {
        if hasPlistOrEnv("POKETRACK_R2_SEALED_PREFIX") {
            return plistOrEnvTrimmed("POKETRACK_R2_SEALED_PREFIX") ?? ""
        }
        return ""
    }

    /// Card/set images (`cards/…`, `sets/logo/…`) — usually bucket root. Key: `POKETRACK_R2_ASSETS_PREFIX`.
    static var r2AssetsPathPrefix: String {
        if hasPlistOrEnv("POKETRACK_R2_ASSETS_PREFIX") {
            return plistOrEnvTrimmed("POKETRACK_R2_ASSETS_PREFIX") ?? ""
        }
        return ""
    }

    /// Backwards-compatible label for Account screen.
    static var r2DataPathPrefix: String { r2CatalogPathPrefix }

    static func r2CatalogURL(path: String) -> URL {
        url(prefix: r2CatalogPathPrefix, path: path)
    }

    static func r2PricingURL(path: String) -> URL {
        url(prefix: r2PricingPathPrefix, path: path)
    }

    static func r2SealedURL(path: String) -> URL {
        url(prefix: r2SealedPathPrefix, path: path)
    }

    /// Images and logos from JSON relative paths (`cards/foo.png`, `sets/logo/...`).
    static func imageURL(relativePath: String) -> URL {
        if relativePath.hasPrefix("http") {
            return URL(string: relativePath)!
        }
        let path = relativePath.hasPrefix("/") ? String(relativePath.dropFirst()) : relativePath
        return url(prefix: r2AssetsPathPrefix, path: path)
    }

    private static func url(prefix: String, path: String) -> URL {
        var base = r2BaseURL
        let p = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !p.isEmpty {
            for segment in p.split(separator: "/") where !segment.isEmpty {
                base = base.appendingPathComponent(String(segment))
            }
        }
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        for segment in trimmed.split(separator: "/") where !segment.isEmpty {
            base = base.appendingPathComponent(String(segment))
        }
        return base
    }

    private static func hasPlistOrEnv(_ key: String) -> Bool {
        if Bundle.main.object(forInfoDictionaryKey: key) != nil { return true }
        if let v = ProcessInfo.processInfo.environment[key], !v.isEmpty { return true }
        return false
    }

    private static func plistOrEnvTrimmed(_ key: String) -> String? {
        if let s = Bundle.main.object(forInfoDictionaryKey: key) as? String {
            return s.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        if let env = ProcessInfo.processInfo.environment[key] {
            return env.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        return nil
    }
}
