import Foundation

/// Builds URLs for your public R2 (or other) CDN. Intended layout when **catalog prefix** is `data`:
/// - `…/data/sets.json`
/// - `…/data/pokemon.json` (National Dex browse: `nationalDexNumber`, `name`, `imageUrl`, optional `generation`)
/// - `…/data/variants.json` (master / grand master / championship variant allow-lists for set completion)
/// - `…/data/cards/{setCode}.json`
/// - `…/data/tcg/pricing/card-pricing/{setCode}.json` (per-set card pricing; see `r2CardPricingSetJSONURL`)
/// - Card images in JSON as `cards/…` resolve under **assets prefix** (default: bucket root → `…/cards/…`).
/// - Set logos: try exact `logoSrc` path first, then `tcg/…` mirrors — see `setLogoURLCandidates`.
enum AppConfiguration {
    /// Monthly premium subscription product ID.
    static let premiumProductID = "app1xy.bindr.premium"
    /// Annual premium subscription product ID.
    static let premiumAnnualProductID = "app1xy.bindr.premium.annual"

    /// Supabase project URL used for social/auth APIs.
    static var supabaseURL: URL? {
        if let s = Bundle.main.object(forInfoDictionaryKey: "BINDR_SUPABASE_URL") as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty, let u = URL(string: t) { return u }
        }
        if let env = ProcessInfo.processInfo.environment["BINDR_SUPABASE_URL"] {
            let t = env.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty, let u = URL(string: t) { return u }
        }
        return nil
    }

    /// iOS Google OAuth client ID (optional). Set `BINDR_GOOGLE_IOS_CLIENT_ID` in Info.plist
    /// when enabling native Google Sign-In. Used for future SDK integration.
    static var googleIOSClientID: String? {
        trimmedPlistOrEnv("BINDR_GOOGLE_IOS_CLIENT_ID")
    }

    /// Google OAuth web client ID (optional). Required in Supabase Google provider settings.
    static var googleWebClientID: String? {
        trimmedPlistOrEnv("BINDR_GOOGLE_WEB_CLIENT_ID")
    }

    /// Custom URL scheme used for Supabase OAuth callbacks (`bindr://auth-callback`).
    static var oauthRedirectScheme: String { "bindr" }

    static var googleOAuthRedirectURL: URL {
        URL(string: "\(oauthRedirectScheme)://auth-callback")!
    }

    /// True when Google OAuth credentials are present and sign-in can complete.
    static var isGoogleSignInAvailable: Bool {
        googleWebClientID != nil || googleIOSClientID != nil
    }

    /// Show the Google button in sign-in UI whenever social auth is configured,
    /// even before Google credentials are wired up.
    static var showsGoogleSignInButton: Bool {
        isSocialAuthConfigured
    }

    /// True when Supabase auth is configured for social sign-in.
    static var isSocialAuthConfigured: Bool {
        supabaseURL != nil && !supabasePublishableKey.isEmpty
    }

    /// Backwards-compatible alias used by existing call sites.
    static var isGoogleSignInConfigured: Bool {
        isGoogleSignInAvailable
    }

    /// Publishable Supabase key (safe for client apps when RLS is enabled).
    static var supabasePublishableKey: String {
        if let s = Bundle.main.object(forInfoDictionaryKey: "BINDR_SUPABASE_PUBLISHABLE_KEY") as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
        }
        if let env = ProcessInfo.processInfo.environment["BINDR_SUPABASE_PUBLISHABLE_KEY"] {
            let t = env.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
        }
        return ""
    }

    /// Public CDN base (no trailing slash). Set `BINDR_R2_BASE_URL` in Info.plist or env.
    static var r2BaseURL: URL {
        if let s = Bundle.main.object(forInfoDictionaryKey: "BINDR_R2_BASE_URL") as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty, let u = URL(string: t) { return u }
        }
        if let env = ProcessInfo.processInfo.environment["BINDR_R2_BASE_URL"],
           !env.isEmpty,
           let u = URL(string: env) {
            return u
        }
        return URL(string: "https://invalid.local")!
    }

    // MARK: - Path prefixes (your bucket may mix folders: e.g. JSON under `data/`, pricing + images at root)

    /// `sets.json` and `cards/{setCode}.json` — e.g. `data` → `…/data/sets.json`. Keys: `BINDR_R2_CATALOG_PREFIX` or legacy `BINDR_R2_DATA_PREFIX`; default `data`.
    static var r2CatalogPathPrefix: String {
        if hasPlistOrEnv("BINDR_R2_CATALOG_PREFIX") {
            return plistOrEnvTrimmed("BINDR_R2_CATALOG_PREFIX") ?? ""
        }
        if hasPlistOrEnv("BINDR_R2_DATA_PREFIX") {
            return plistOrEnvTrimmed("BINDR_R2_DATA_PREFIX") ?? ""
        }
        return "data"
    }

    /// Prefix for URLs built with `r2PricingURL` (e.g. per-set card pricing under `tcg/pricing/card-pricing/`). Key: `BINDR_R2_PRICING_PREFIX`.
    /// If omitted, defaults to **`r2CatalogPathPrefix`** (e.g. `data/…`).
    /// Set the plist key to an **empty string** to use bucket root.
    static var r2PricingPathPrefix: String {
        if hasPlistOrEnv("BINDR_R2_PRICING_PREFIX") {
            return plistOrEnvTrimmed("BINDR_R2_PRICING_PREFIX") ?? ""
        }
        return r2CatalogPathPrefix
    }

    /// Directory under `r2PricingPathPrefix` containing `me03.json`, etc. Default `pricing/card-pricing`. Override: `BINDR_R2_CARD_PRICING_DIR`.
    static var r2CardPricingRelativeDirectory: String {
        if hasPlistOrEnv("BINDR_R2_CARD_PRICING_DIR") {
            let s = plistOrEnvTrimmed("BINDR_R2_CARD_PRICING_DIR") ?? ""
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

    /// Card/set images (`cards/…`, `sets/logo/…`) — usually bucket root. Key: `BINDR_R2_ASSETS_PREFIX`.
    static var r2AssetsPathPrefix: String {
        if hasPlistOrEnv("BINDR_R2_ASSETS_PREFIX") {
            return plistOrEnvTrimmed("BINDR_R2_ASSETS_PREFIX") ?? ""
        }
        return ""
    }

    /// Backwards-compatible label for Account screen.
    static var r2DataPathPrefix: String { r2CatalogPathPrefix }

    static func r2CatalogURL(path: String) -> URL {
        url(prefix: r2CatalogPathPrefix, path: path)
    }

    /// Catalog version sentinel: `version.md` at bucket root. Text format: `Version - N`.
    /// When N increases the app re-downloads sets, series, and all card JSONs.
    static var r2CatalogVersionURL: URL {
        url(prefix: "", path: "version.md")
    }

    /// Hosted list of franchises (order = carousel / Account). Default: `brands/data/brands.json` under ``r2BaseURL``.
    static var brandsManifestURL: URL {
        if hasPlistOrEnv("BINDR_BRANDS_MANIFEST_URL"),
           let s = plistOrEnvTrimmed("BINDR_BRANDS_MANIFEST_URL"),
           !s.isEmpty,
           let u = URL(string: s) {
            return u
        }
        return url(prefix: "", path: "brands/data/brands.json")
    }

    static func r2PricingURL(path: String) -> URL {
        url(prefix: r2PricingPathPrefix, path: path)
    }

    /// Sealed / Pokedata / price-trends JSON (paths under this prefix). Key: `BINDR_R2_MARKET_PREFIX`; default root.
    static var r2MarketPathPrefix: String {
        if hasPlistOrEnv("BINDR_R2_MARKET_PREFIX") {
            return plistOrEnvTrimmed("BINDR_R2_MARKET_PREFIX") ?? ""
        }
        return ""
    }

    static func r2MarketURL(path: String) -> URL {
        url(prefix: r2MarketPathPrefix, path: path)
    }

    /// Per-set price trends file: `new_pricing/price-trends/{setCode}.json`
    static func r2PriceTrendsURL(setCode: String) -> URL {
        r2MarketURL(path: "new_pricing/price-trends/\(setCode).json")
    }

    /// Combined daily card price bucket (all sets): `new_pricing/daily/{YYYY-MM-DD}.json`
    static func r2NewPricingDailyURL(dateKey: String) -> URL {
        r2MarketURL(path: "new_pricing/daily/\(dateKey).json")
    }

    /// Combined weekly card price bucket (all sets): `new_pricing/weekly/{YYYY-Www}.json`
    static func r2NewPricingWeeklyURL(weekKey: String) -> URL {
        r2MarketURL(path: "new_pricing/weekly/\(weekKey).json")
    }

    /// Combined monthly card price bucket (all sets): `new_pricing/monthly/{YYYY-MM}.json`
    static func r2NewPricingMonthlyURL(monthKey: String) -> URL {
        r2MarketURL(path: "new_pricing/monthly/\(monthKey).json")
    }

    /// Sealed product daily price bucket: `new_pricing/sealed/daily/{YYYY-MM-DD}.json`
    /// Shape: `{ "productId": price }` (flat Double, not an object).
    static func r2SealedDailyURL(dateKey: String) -> URL {
        r2MarketURL(path: "new_pricing/sealed/daily/\(dateKey).json")
    }

    /// Sealed product weekly price bucket: `new_pricing/sealed/weekly/{YYYY-Www}.json`
    static func r2SealedWeeklyURL(weekKey: String) -> URL {
        r2MarketURL(path: "new_pricing/sealed/weekly/\(weekKey).json")
    }

    /// Sealed product monthly price bucket: `new_pricing/sealed/monthly/{YYYY-MM}.json`
    static func r2SealedMonthlyURL(monthKey: String) -> URL {
        r2MarketURL(path: "new_pricing/sealed/monthly/\(monthKey).json")
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
    /// Default folder `images/pokemon` (alongside `images/sets/…`). Override with `BINDR_R2_POKEMON_IMAGE_PREFIX` (empty = assets root + filename only).
    static func pokemonArtURL(imageFileName: String) -> URL {
        let trimmed = imageFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("/") || trimmed.hasPrefix("http") {
            return imageURL(relativePath: trimmed)
        }
        let folder = plistOrEnvTrimmed("BINDR_R2_POKEMON_IMAGE_PREFIX") ?? "images/pokemon"
        if folder.isEmpty {
            return imageURL(relativePath: trimmed)
        }
        return imageURL(relativePath: "\(folder)/\(trimmed)")
    }

    /// Same path logic as ``pokemonArtURL`` but returns the catalog-relative key used for offline packs (no host).
    static func pokemonArtRelativePath(imageFileName: String) -> String {
        let trimmed = imageFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("http"),
           let url = resolvedImageURL(stored: trimmed),
           let key = offlineImageKey(for: url) {
            return key
        }
        if trimmed.contains("/") {
            return trimmed.hasPrefix("/") ? String(trimmed.dropFirst()) : trimmed
        }
        let folder = plistOrEnvTrimmed("BINDR_R2_POKEMON_IMAGE_PREFIX") ?? "images/pokemon"
        if folder.isEmpty {
            return trimmed
        }
        return "\(folder)/\(trimmed)"
    }

    /// Images and logos from JSON relative paths (`cards/foo.png`, `sets/logo/...`).
    static func imageURL(relativePath: String) -> URL {
        resolvedImageURL(stored: relativePath) ?? assetURL(relativePath: relativePath)
    }

    /// Previous custom domains for the public R2 bucket (catalog JSON may still embed absolute URLs).
    private static let legacyR2Hosts: Set<String> = ["www.bindr-tcg.com"]

    private static func isR2CDNHost(_ host: String?) -> Bool {
        guard let host else { return false }
        return host == r2BaseURL.host || legacyR2Hosts.contains(host)
    }

    /// Resolves a stored absolute or relative image URL against the current CDN base.
    /// Profile and catalog JSON often persist absolute URLs from an old R2 / Cloudflare host
    /// after a custom-domain migration — rebuild them from the path on the configured CDN.
    static func resolvedImageURL(stored: String?) -> URL? {
        guard let raw = stored?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if !raw.hasPrefix("http") {
            return assetURL(relativePath: raw)
        }
        guard let url = URL(string: raw) else { return nil }
        if url.host == r2BaseURL.host {
            return url
        }
        var path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let basePath = r2BaseURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !basePath.isEmpty, path.hasPrefix(basePath) {
            path = String(path.dropFirst(basePath.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        guard !path.isEmpty else { return nil }
        return assetURL(relativePath: path)
    }

    private static func assetURL(relativePath path: String) -> URL {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.hasPrefix("/") ? String(trimmed.dropFirst()) : trimmed
        return url(prefix: r2AssetsPathPrefix, path: normalized)
    }

    /// Upcoming release artwork from `upcoming.json` (`image`, e.g. `upcoming/pitchBlack.jpg`).
    /// Files are hosted at bucket root: `…/upcoming/<file>`.
    static func upcomingReleaseImageURL(imageSrc: String) -> URL? {
        let path = normalizedSetLogoPath(imageSrc)
        guard !path.isEmpty else { return nil }
        return imageURL(relativePath: path)
    }

    /// Candidate URLs for offline pack sync — exact JSON path first, then common extension swaps.
    static func upcomingReleaseImageURLCandidates(imageSrc: String) -> [URL] {
        let path = normalizedSetLogoPath(imageSrc)
        guard !path.isEmpty else { return [] }

        var urls: [URL] = []
        func appendPath(_ relativePath: String) {
            let primary = imageURL(relativePath: relativePath)
            let catalog = r2CatalogURL(path: relativePath)
            if !urls.contains(primary) { urls.append(primary) }
            if !urls.contains(catalog) { urls.append(catalog) }
        }

        appendPath(path)

        let nsPath = path as NSString
        let ext = nsPath.pathExtension.lowercased()
        guard !ext.isEmpty else { return urls }

        let stem = nsPath.deletingPathExtension
        for alternate in ["png", "jpg", "jpeg", "webp"] where alternate != ext {
            appendPath("\(stem).\(alternate)")
        }
        return urls
    }

    /// Canonical offline-store key for an upcoming release image path from JSON.
    static func upcomingReleaseOfflineKey(imageSrc: String) -> String? {
        let path = normalizedSetLogoPath(imageSrc)
        return path.isEmpty ? nil : path
    }

    /// Returns the canonical relative path (offline store key) for an R2 image URL, or nil if the
    /// URL does not belong to our CDN. Strips base URL and optional assets prefix.
    static func offlineImageKey(for url: URL) -> String? {
        // Compare hosts so this correctly returns nil for non-R2 URLs.
        // Use url.path (percent-decoded by Foundation) so the key matches
        // the raw imageLowSrc string stored in the manifest — appendingPathComponent
        // percent-encodes spaces/specials, so absoluteString comparison fails.
        guard isR2CDNHost(url.host) else { return nil }
        let basePath = r2BaseURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var relative = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if url.host == r2BaseURL.host, !basePath.isEmpty, relative.hasPrefix(basePath) {
            relative = String(relative.dropFirst(basePath.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        let prefix = r2AssetsPathPrefix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !prefix.isEmpty, relative.hasPrefix(prefix) {
            relative = String(relative.dropFirst(prefix.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        return relative.isEmpty ? nil : relative
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

    private static func trimmedPlistOrEnv(_ key: String) -> String? {
        let value = plistOrEnvTrimmed(key)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value, !value.isEmpty else { return nil }
        return value
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

    // MARK: - Card pricing file stems

    /// Sub-set pricing stems for sets whose cards are priced under a separate R2 path.
    /// e.g. swsh12 → [swsh12tg], swsh12pt5 → [swsh12pt5gg], swsh45 → [swsh45sv]
    static func subSetPricingStems(for setCode: String) -> [String] {
        let sc = setCode.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        switch sc {
        case "swsh12":    return ["swsh12tg"]
        case "swsh12pt5": return ["swsh12pt5gg"]
        case "swsh11":    return ["swsh11tg"]
        case "swsh10":    return ["swsh10tg"]
        case "swsh9":     return ["swsh9tg"]
        case "swsh45":    return ["swsh45sv"]
        default:          return []
        }
    }

    /// Stems to try for `pricing/card-pricing/{stem}.json` when catalog `setCode` does not match your export filename.
    /// - Example: `me03` vs `me3` (leading zeros in the letter+digits prefix).
    /// - Example: dotted TCGdex ids like **`me02.5`** vs Scrydex filenames using **`pt`** instead of **`.`** (`me2pt5.json`, `me02pt5.json`).
    static func pricingFileStemVariants(for setCode: String) -> [String] {
        let s = setCode.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        var stems: [String] = []
        func add(_ x: String) {
            if !stems.contains(x) { stems.append(x) }
        }
        add(s)
        if let regex = try? NSRegularExpression(pattern: #"^([a-z]+)0+(\d+)$"#, options: []),
           let m = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
           m.numberOfRanges == 3,
           let r1 = Range(m.range(at: 1), in: s),
           let r2 = Range(m.range(at: 2), in: s) {
            let letters = String(s[r1])
            let digits = String(s[r2])
            if let n = Int(digits) {
                add("\(letters)\(n)")
            }
        }
        for v in dottedSetCodePtNotationVariants(s) {
            add(v)
        }
        return stems
    }

    /// `me02.5` → `me2pt5` (collapse trailing digits before the dot, then `pt`) and `me02pt5` (literal dot → `pt`).
    private static func dottedSetCodePtNotationVariants(_ s: String) -> [String] {
        guard let dot = s.firstIndex(of: ".") else { return [] }
        let left = String(s[..<dot])
        let right = String(s[s.index(after: dot)...])
        guard !left.isEmpty, !right.isEmpty, right.allSatisfy(\.isNumber) else { return [] }
        let literalPt = left + "pt" + right
        var collapsedLeft = left
        if let range = left.range(of: #"\d+$"#, options: .regularExpression) {
            let prefix = String(left[..<range.lowerBound])
            let tail = String(left[range])
            if let n = Int(tail) {
                collapsedLeft = prefix + String(n)
            }
        }
        let collapsedPt = collapsedLeft + "pt" + right
        if collapsedPt == literalPt {
            return [literalPt]
        }
        return [collapsedPt, literalPt]
    }

    // MARK: - Collection Sync Worker

    /// Base URL for the Cloudflare collection-sync Worker. Set `BINDR_COLLECTION_SYNC_WORKER_URL` in Info.plist.
    static var collectionSyncWorkerURL: URL? {
        if let s = Bundle.main.object(forInfoDictionaryKey: "BINDR_COLLECTION_SYNC_WORKER_URL") as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty, let u = URL(string: t) { return u }
        }
        if let env = ProcessInfo.processInfo.environment["BINDR_COLLECTION_SYNC_WORKER_URL"] {
            let t = env.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty, let u = URL(string: t) { return u }
        }
        return nil
    }

    /// PUT endpoint — upload the signed-in user's collection snapshot.
    static var collectionSyncPutURL: URL? {
        collectionSyncWorkerURL?.appending(path: "user-collection")
    }

    /// GET endpoint — download a user's collection snapshot by their UUID.
    static func collectionSyncGetURL(userID: UUID) -> URL? {
        guard var components = collectionSyncWorkerURL.flatMap({ URLComponents(url: $0.appending(path: "user-collection"), resolvingAgainstBaseURL: false) }) else { return nil }
        components.queryItems = [URLQueryItem(name: "userID", value: userID.uuidString.lowercased())]
        return components.url
    }
}
