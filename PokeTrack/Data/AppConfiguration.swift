import Foundation

/// Builds URLs for your public R2 (or other) CDN. Intended layout when **catalog prefix** is `data`:
/// - `…/data/sets.json`
/// - `…/data/pokemon.json` (National Dex browse: `nationalDexNumber`, `name`, `imageUrl`, optional `generation`)
/// - `…/data/cards/{setCode}.json`
/// - `…/data/tcg/pricing/card-pricing/{setCode}.json` (per-set card pricing; see `r2CardPricingSetJSONURL`)
/// - Card images in JSON as `cards/…` resolve under **assets prefix** (default: bucket root → `…/cards/…`).
/// - Set logos: try exact `logoSrc` path first, then `tcg/…` mirrors — see `setLogoURLCandidates`.
enum AppConfiguration {
    /// Single non-consumable premium product — create the same ID in App Store Connect.
    static let premiumProductID = "app1xy.PokeTrack.premium"

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

    /// Prefix for URLs built with `r2PricingURL` (e.g. per-set card pricing under `tcg/pricing/card-pricing/`). Key: `POKETRACK_R2_PRICING_PREFIX`.
    /// If omitted, defaults to **`r2CatalogPathPrefix`** (e.g. `data/…`).
    /// Set the plist key to an **empty string** to use bucket root.
    static var r2PricingPathPrefix: String {
        if hasPlistOrEnv("POKETRACK_R2_PRICING_PREFIX") {
            return plistOrEnvTrimmed("POKETRACK_R2_PRICING_PREFIX") ?? ""
        }
        return r2CatalogPathPrefix
    }

    /// Directory under `r2PricingPathPrefix` containing `me03.json`, etc. Default `pricing/card-pricing`. Override: `POKETRACK_R2_CARD_PRICING_DIR`.
    static var r2CardPricingRelativeDirectory: String {
        if hasPlistOrEnv("POKETRACK_R2_CARD_PRICING_DIR") {
            let s = plistOrEnvTrimmed("POKETRACK_R2_CARD_PRICING_DIR") ?? ""
            return s.isEmpty ? "pricing/card-pricing" : s
        }
        return "pricing/card-pricing"
    }

    /// Per-set card pricing JSON: `{prefix}/tcg/pricing/card-pricing/{setCode}.json` (prefix is usually `data`).
    static func r2CardPricingSetJSONURL(setCodeStem: String) -> URL {
        let stem = setCodeStem.trimmingCharacters(in: .whitespacesAndNewlines)
        let dir = r2CardPricingRelativeDirectory.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return r2PricingURL(path: "\(dir)/\(stem).json")
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

    /// Sealed / Pokedata / price-trends JSON (paths under this prefix). Key: `POKETRACK_R2_MARKET_PREFIX`; default root.
    static var r2MarketPathPrefix: String {
        if hasPlistOrEnv("POKETRACK_R2_MARKET_PREFIX") {
            return plistOrEnvTrimmed("POKETRACK_R2_MARKET_PREFIX") ?? ""
        }
        return ""
    }

    static func r2MarketURL(path: String) -> URL {
        url(prefix: r2MarketPathPrefix, path: path)
    }

    /// Per-set price history file: `pricing/price-history/{setCode}.json`
    static func r2PricingHistoryURL(setCode: String) -> URL {
        r2PricingURL(path: "pricing/price-history/\(setCode).json")
    }

    /// Per-set price trends file: `pricing/price-trends/{setCode}.json`
    static func r2PriceTrendsURL(setCode: String) -> URL {
        r2PricingURL(path: "pricing/price-trends/\(setCode).json")
    }

    private static func normalizedSetLogoPath(_ logoSrc: String) -> String {
        let t = logoSrc.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("/") { return String(t.dropFirst()) }
        return t
    }

    /// Set logos from `sets.json` (`logoSrc`, e.g. `images/sets/logo/….jpg`). Empty `logoSrc` yields `nil`.
    static func setLogoURL(logoSrc: String) -> URL? {
        setLogoURLCandidates(logoSrc: logoSrc).first
    }

    /// Tries paths most likely to exist first: **exact `logoSrc` under assets + catalog**, then `tcg/images/sets/logo/…` and other mirrors (bucket layouts differ).
    static func setLogoURLCandidates(logoSrc: String) -> [URL] {
        let path = normalizedSetLogoPath(logoSrc)
        guard !path.isEmpty else { return [] }

        var urls: [URL] = []
        func appendUnique(_ url: URL) {
            if !urls.contains(url) { urls.append(url) }
        }

        let fileName = path.split(separator: "/").last.map(String.init)

        // 1. Exact path from `sets.json`.
        appendUnique(imageURL(relativePath: path))

        // 2. `images/` prefix — live sets.json uses `sets/logo/…` but files live at `images/sets/logo/…`.
        if path.hasPrefix("sets/logo/") {
            appendUnique(imageURL(relativePath: "images/" + path))
        }

        // 3. Catalog-prefixed exact path.
        appendUnique(r2CatalogURL(path: path))

        // 4. `tcg/images/sets/logo/<file>` (alternate layout).
        if let fileName, !fileName.isEmpty {
            appendUnique(imageURL(relativePath: "tcg/images/sets/logo/\(fileName)"))
            appendUnique(r2CatalogURL(path: "tcg/images/sets/logo/\(fileName)"))
        }

        // 5. `tcg/` + full path when JSON uses `images/sets/…`.
        if path.hasPrefix("images/sets/") {
            appendUnique(imageURL(relativePath: "tcg/" + path))
            appendUnique(r2CatalogURL(path: "tcg/" + path))
        }

        // 6. `sets/logo/<file>` only.
        if let fileName, !fileName.isEmpty {
            appendUnique(imageURL(relativePath: "sets/logo/\(fileName)"))
            appendUnique(r2CatalogURL(path: "sets/logo/\(fileName)"))
        }

        return urls
    }

    /// Paths from `sets.json` `symbolSrc` (e.g. `images/sets/symbol/me02.5.webp`). Empty yields `[]`.
    static func setSymbolURLCandidates(symbolSrc: String) -> [URL] {
        let path = normalizedSetLogoPath(symbolSrc)
        guard !path.isEmpty else { return [] }

        var urls: [URL] = []
        func appendUnique(_ url: URL) {
            if !urls.contains(url) { urls.append(url) }
        }

        let fileName = path.split(separator: "/").last.map(String.init)

        appendUnique(imageURL(relativePath: path))

        if path.hasPrefix("sets/symbol/") {
            appendUnique(imageURL(relativePath: "images/" + path))
        }

        appendUnique(r2CatalogURL(path: path))

        if let fileName, !fileName.isEmpty {
            appendUnique(imageURL(relativePath: "tcg/images/sets/symbol/\(fileName)"))
            appendUnique(r2CatalogURL(path: "tcg/images/sets/symbol/\(fileName)"))
        }

        if path.hasPrefix("images/sets/") {
            appendUnique(imageURL(relativePath: "tcg/" + path))
            appendUnique(r2CatalogURL(path: "tcg/" + path))
        }

        if let fileName, !fileName.isEmpty {
            appendUnique(imageURL(relativePath: "sets/symbol/\(fileName)"))
            appendUnique(r2CatalogURL(path: "sets/symbol/\(fileName)"))
        }

        return urls
    }

    /// Art for `pokemon.json` rows: `imageUrl` is usually a filename like `1-1.png`.
    /// Default folder `images/pokemon` (alongside `images/sets/…`). Override with `POKETRACK_R2_POKEMON_IMAGE_PREFIX` (empty = assets root + filename only).
    static func pokemonArtURL(imageFileName: String) -> URL {
        let trimmed = imageFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("http") {
            return URL(string: trimmed)!
        }
        if trimmed.contains("/") {
            return imageURL(relativePath: trimmed)
        }
        let folder = plistOrEnvTrimmed("POKETRACK_R2_POKEMON_IMAGE_PREFIX") ?? "images/pokemon"
        if folder.isEmpty {
            return imageURL(relativePath: trimmed)
        }
        return imageURL(relativePath: "\(folder)/\(trimmed)")
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
