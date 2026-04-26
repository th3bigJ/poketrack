import Foundation
import Observation

/// How card market prices and history should be shown. R2 pricing JSON is always USD; GBP applies a live FX rate from `PricingService`.
enum PriceDisplayCurrency: String, CaseIterable, Identifiable, Sendable {
    case usd
    case gbp

    var id: String { rawValue }

    var pickerTitle: String {
        switch self {
        case .usd: return "US Dollar"
        case .gbp: return "British Pound"
        }
    }

    var symbol: String {
        switch self {
        case .usd: return "$"
        case .gbp: return "£"
        }
    }

    /// Formats a stored USD amount for this display mode.
    func format(amountUSD: Double, usdToGbp: Double) -> String {
        switch self {
        case .usd:
            return String(format: "$%.2f", amountUSD)
        case .gbp:
            return String(format: "£%.2f", amountUSD * usdToGbp)
        }
    }

    /// Y-axis tick: `value` is the chart’s USD coordinate (same as history JSON).
    func formatAxisTick(usd: Double, usdToGbp: Double) -> String {
        format(amountUSD: usd, usdToGbp: usdToGbp)
    }
}

@Observable
@MainActor
final class PriceDisplaySettings {
    private static let defaultsKey = "priceDisplayCurrency"
    private let cloudSettings: CloudSettingsService

    var currency: PriceDisplayCurrency {
        didSet {
            guard currency != oldValue else { return }
            UserDefaults.standard.set(currency.rawValue, forKey: Self.defaultsKey)
            cloudSettings.saveCurrency(currency)
        }
    }

    init(cloudSettings: CloudSettingsService) {
        self.cloudSettings = cloudSettings

        let localRaw = UserDefaults.standard.string(forKey: Self.defaultsKey)
        if let cloudCurrency = cloudSettings.loadCurrency() {
            currency = cloudCurrency
            UserDefaults.standard.set(cloudCurrency.rawValue, forKey: Self.defaultsKey)
        } else if let localRaw, let parsed = PriceDisplayCurrency(rawValue: localRaw) {
            currency = parsed
            cloudSettings.saveCurrency(parsed)
        } else {
            currency = .gbp
            cloudSettings.saveCurrency(.gbp)
        }

        NotificationCenter.default.addObserver(
            forName: .cloudSettingsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let cloudCurrency = self.cloudSettings.loadCurrency() else { return }
                if self.currency != cloudCurrency {
                    self.currency = cloudCurrency
                }
            }
        }
    }

}

@Observable
@MainActor
final class BrowseGridOptionsSettings {
    private static let validColumnRange = 1...4

    private enum Keys {
        static let showCardName = "browseGridShowCardName"
        static let showSetName = "browseGridShowSetName"
        static let showSetID = "browseGridShowSetID"
        static let showPricing = "browseGridShowPricing"
        static let columnCount = "browseGridColumnCount"
    }

    private let cloudSettings: CloudSettingsService

    var options: BrowseGridOptions {
        didSet {
            let sanitized = Self.sanitize(options)
            if sanitized != options {
                options = sanitized
                return
            }
            guard options != oldValue else { return }
            saveToLocalDefaults(options)
            cloudSettings.saveBrowseGridOptions(options)
        }
    }

    init(cloudSettings: CloudSettingsService) {
        self.cloudSettings = cloudSettings

        let localOptions = Self.loadFromLocalDefaults()
        if let cloudOptions = cloudSettings.loadBrowseGridOptions() {
            let sanitized = Self.sanitize(cloudOptions)
            options = sanitized
            saveToLocalDefaults(sanitized)
        } else {
            options = localOptions
            cloudSettings.saveBrowseGridOptions(localOptions)
        }

        NotificationCenter.default.addObserver(
            forName: .cloudSettingsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let cloudOptions = self.cloudSettings.loadBrowseGridOptions() else { return }
                let sanitized = Self.sanitize(cloudOptions)
                if self.options != sanitized {
                    self.options = sanitized
                }
            }
        }
    }

    private static func loadFromLocalDefaults() -> BrowseGridOptions {
        let defaults = UserDefaults.standard
        let base = BrowseGridOptions()

        return BrowseGridOptions(
            showCardName: defaults.object(forKey: Keys.showCardName) != nil
                ? defaults.bool(forKey: Keys.showCardName)
                : base.showCardName,
            showSetName: defaults.object(forKey: Keys.showSetName) != nil
                ? defaults.bool(forKey: Keys.showSetName)
                : base.showSetName,
            showSetID: defaults.object(forKey: Keys.showSetID) != nil
                ? defaults.bool(forKey: Keys.showSetID)
                : base.showSetID,
            showPricing: defaults.object(forKey: Keys.showPricing) != nil
                ? defaults.bool(forKey: Keys.showPricing)
                : base.showPricing,
            columnCount: sanitizedColumnCount(
                defaults.object(forKey: Keys.columnCount) != nil
                    ? defaults.integer(forKey: Keys.columnCount)
                    : base.columnCount
            )
        )
    }

    private func saveToLocalDefaults(_ options: BrowseGridOptions) {
        let defaults = UserDefaults.standard
        defaults.set(options.showCardName, forKey: Keys.showCardName)
        defaults.set(options.showSetName, forKey: Keys.showSetName)
        defaults.set(options.showSetID, forKey: Keys.showSetID)
        defaults.set(options.showPricing, forKey: Keys.showPricing)
        defaults.set(options.columnCount, forKey: Keys.columnCount)
    }

    private static func sanitize(_ options: BrowseGridOptions) -> BrowseGridOptions {
        var sanitized = options
        sanitized.columnCount = sanitizedColumnCount(options.columnCount)
        return sanitized
    }

    private static func sanitizedColumnCount(_ count: Int) -> Int {
        min(max(count, validColumnRange.lowerBound), validColumnRange.upperBound)
    }
}

private func decodeDefaultsJSON<T: Decodable>(_ type: T.Type, key: String) -> T? {
    guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
    return try? JSONDecoder().decode(T.self, from: data)
}

private func encodeDefaultsJSON<T: Encodable>(_ value: T, key: String) {
    guard let data = try? JSONEncoder().encode(value) else { return }
    UserDefaults.standard.set(data, forKey: key)
}

// MARK: - Collection filter + grid persistence

/// Persists the collection tab's filter choices (all fields) and grid options across launches.
@Observable
final class CollectionFiltersSettings {
    private static let validColumnRange = 1...4

    private enum Keys {
        static let collectionFiltersJSON = "collectFiltersJSON"
        static let wishlistFiltersJSON   = "wishlistFiltersJSON"

        // Legacy keys retained for migration fallback.
        static let collectionSortBy     = "collectFilterSortBy"
        static let collectionShowDups   = "collectFilterShowDuplicates"
        static let wishlistSortBy       = "wishlistFilterSortBy"

        static let gridShowCardName     = "collectGridShowCardName"
        static let gridShowSetName      = "collectGridShowSetName"
        static let gridShowSetID        = "collectGridShowSetID"
        static let gridShowPricing      = "collectGridShowPricing"
        static let gridShowOwned        = "collectGridShowOwned"
        static let gridColumnCount      = "collectGridColumnCount"
    }

    var collectionFilters: BrowseCardGridFilters {
        didSet {
            guard collectionFilters != oldValue else { return }
            saveCollectionFilters(collectionFilters)
        }
    }

    var wishlistFilters: BrowseCardGridFilters {
        didSet {
            guard wishlistFilters != oldValue else { return }
            saveWishlistFilters(wishlistFilters)
        }
    }

    var gridOptions: BrowseGridOptions {
        didSet {
            let sanitized = Self.sanitizeGrid(gridOptions)
            if sanitized != gridOptions { gridOptions = sanitized; return }
            guard gridOptions != oldValue else { return }
            saveGridOptions(gridOptions)
        }
    }

    init() {
        collectionFilters = Self.loadCollectionFilters()
        wishlistFilters   = Self.loadWishlistFilters()
        gridOptions       = Self.loadGridOptions()
    }

    // MARK: - Load

    private static func loadCollectionFilters() -> BrowseCardGridFilters {
        if let decoded = decodeDefaultsJSON(BrowseCardGridFilters.self, key: Keys.collectionFiltersJSON) {
            return sanitizeCollectionFilters(decoded)
        }

        let d = UserDefaults.standard
        var f = BrowseCardGridFilters()
        f.sortBy = BrowseCardGridSortOption(rawValue: d.string(forKey: Keys.collectionSortBy) ?? "") ?? .price
        f.showDuplicates = d.object(forKey: Keys.collectionShowDups) != nil
            ? d.bool(forKey: Keys.collectionShowDups) : false
        return sanitizeCollectionFilters(f)
    }

    private static func loadWishlistFilters() -> BrowseCardGridFilters {
        if let decoded = decodeDefaultsJSON(BrowseCardGridFilters.self, key: Keys.wishlistFiltersJSON) {
            return sanitizeCollectionFilters(decoded)
        }

        let d = UserDefaults.standard
        var f = BrowseCardGridFilters()
        f.sortBy = BrowseCardGridSortOption(rawValue: d.string(forKey: Keys.wishlistSortBy) ?? "") ?? .price
        return sanitizeCollectionFilters(f)
    }

    private static func loadGridOptions() -> BrowseGridOptions {
        let d = UserDefaults.standard
        let base = BrowseGridOptions()
        return BrowseGridOptions(
            showCardName: d.object(forKey: Keys.gridShowCardName) != nil ? d.bool(forKey: Keys.gridShowCardName) : base.showCardName,
            showSetName:  d.object(forKey: Keys.gridShowSetName)  != nil ? d.bool(forKey: Keys.gridShowSetName)  : base.showSetName,
            showSetID:    d.object(forKey: Keys.gridShowSetID)    != nil ? d.bool(forKey: Keys.gridShowSetID)    : base.showSetID,
            showPricing:  d.object(forKey: Keys.gridShowPricing)  != nil ? d.bool(forKey: Keys.gridShowPricing)  : base.showPricing,
            showOwned:    d.object(forKey: Keys.gridShowOwned)    != nil ? d.bool(forKey: Keys.gridShowOwned)    : base.showOwned,
            columnCount:  sanitizedColumnCount(
                d.object(forKey: Keys.gridColumnCount) != nil ? d.integer(forKey: Keys.gridColumnCount) : base.columnCount
            )
        )
    }

    // MARK: - Save

    private func saveCollectionFilters(_ f: BrowseCardGridFilters) {
        let sanitized = Self.sanitizeCollectionFilters(f)
        if collectionFilters != sanitized {
            collectionFilters = sanitized
            return
        }
        encodeDefaultsJSON(sanitized, key: Keys.collectionFiltersJSON)

        let d = UserDefaults.standard
        d.set(sanitized.sortBy.rawValue, forKey: Keys.collectionSortBy)
        d.set(sanitized.showDuplicates, forKey: Keys.collectionShowDups)
    }

    private func saveWishlistFilters(_ f: BrowseCardGridFilters) {
        let sanitized = Self.sanitizeCollectionFilters(f)
        if wishlistFilters != sanitized {
            wishlistFilters = sanitized
            return
        }
        encodeDefaultsJSON(sanitized, key: Keys.wishlistFiltersJSON)
        UserDefaults.standard.set(sanitized.sortBy.rawValue, forKey: Keys.wishlistSortBy)
    }

    private func saveGridOptions(_ options: BrowseGridOptions) {
        let d = UserDefaults.standard
        d.set(options.showCardName, forKey: Keys.gridShowCardName)
        d.set(options.showSetName,  forKey: Keys.gridShowSetName)
        d.set(options.showSetID,    forKey: Keys.gridShowSetID)
        d.set(options.showPricing,  forKey: Keys.gridShowPricing)
        d.set(options.showOwned,    forKey: Keys.gridShowOwned)
        d.set(options.columnCount,  forKey: Keys.gridColumnCount)
    }

    // MARK: - Helpers

    private static func sanitizeGrid(_ options: BrowseGridOptions) -> BrowseGridOptions {
        var s = options
        s.columnCount = sanitizedColumnCount(options.columnCount)
        return s
    }

    private static func sanitizedColumnCount(_ count: Int) -> Int {
        min(max(count, validColumnRange.lowerBound), validColumnRange.upperBound)
    }

    private static func sanitizeCollectionFilters(_ filters: BrowseCardGridFilters) -> BrowseCardGridFilters {
        var next = filters
        if next.sortBy == .random || next.sortBy == .cardNumber {
            next.sortBy = .price
        }
        return next
    }
}

// MARK: - Browse filter persistence (per tab)

/// Persists browse filters per tab so each page keeps independent filter/sort choices.
@Observable
final class BrowseFiltersSettings {
    private static let validColumnRange = 1...4

    private enum Keys {
        static let cardsFiltersJSON = "browseFiltersCardsJSON"
        static let setsFiltersJSON = "browseFiltersSetsJSON"
        static let pokemonFiltersJSON = "browseFiltersPokemonJSON"
        static let sealedFiltersJSON = "browseFiltersSealedJSON"
        static let cardsInlineFiltersJSON = "browseInlineFiltersCardsJSON"
        static let setsInlineFiltersJSON = "browseInlineFiltersSetsJSON"
        static let pokemonInlineFiltersJSON = "browseInlineFiltersPokemonJSON"
        static let sealedInlineFiltersJSON = "browseInlineFiltersSealedJSON"
        static let sealedGridOptionsJSON = "browseGridOptionsSealedJSON"
    }

    var cardsFilters: BrowseCardGridFilters {
        didSet {
            guard cardsFilters != oldValue else { return }
            saveBrowseFilters(cardsFilters, key: Keys.cardsFiltersJSON)
        }
    }

    var setsFilters: BrowseCardGridFilters {
        didSet {
            guard setsFilters != oldValue else { return }
            saveBrowseFilters(setsFilters, key: Keys.setsFiltersJSON)
        }
    }

    var pokemonFilters: BrowseCardGridFilters {
        didSet {
            guard pokemonFilters != oldValue else { return }
            saveBrowseFilters(pokemonFilters, key: Keys.pokemonFiltersJSON)
        }
    }

    var sealedFilters: BrowseCardGridFilters {
        didSet {
            guard sealedFilters != oldValue else { return }
            saveBrowseFilters(sealedFilters, key: Keys.sealedFiltersJSON)
        }
    }

    var cardsInlineFilters: BrowseCardGridFilters {
        didSet {
            guard cardsInlineFilters != oldValue else { return }
            saveBrowseFilters(cardsInlineFilters, key: Keys.cardsInlineFiltersJSON)
        }
    }

    var setsInlineFilters: BrowseCardGridFilters {
        didSet {
            guard setsInlineFilters != oldValue else { return }
            saveBrowseFilters(setsInlineFilters, key: Keys.setsInlineFiltersJSON)
        }
    }

    var pokemonInlineFilters: BrowseCardGridFilters {
        didSet {
            guard pokemonInlineFilters != oldValue else { return }
            saveBrowseFilters(pokemonInlineFilters, key: Keys.pokemonInlineFiltersJSON)
        }
    }

    var sealedInlineFilters: BrowseCardGridFilters {
        didSet {
            guard sealedInlineFilters != oldValue else { return }
            saveBrowseFilters(sealedInlineFilters, key: Keys.sealedInlineFiltersJSON)
        }
    }

    /// Sealed browse has dedicated grid options so columns/toggles don't affect cards/sets/pokemon.
    var sealedGridOptions: BrowseGridOptions {
        didSet {
            let sanitized = Self.sanitizeGridOptions(sealedGridOptions)
            if sanitized != sealedGridOptions {
                sealedGridOptions = sanitized
                return
            }
            guard sealedGridOptions != oldValue else { return }
            saveSealedGridOptions(sealedGridOptions)
        }
    }

    init() {
        cardsFilters = Self.loadBrowseFilters(key: Keys.cardsFiltersJSON)
        setsFilters = Self.loadBrowseFilters(key: Keys.setsFiltersJSON)
        pokemonFilters = Self.loadBrowseFilters(key: Keys.pokemonFiltersJSON)
        sealedFilters = Self.loadBrowseFilters(key: Keys.sealedFiltersJSON)
        cardsInlineFilters = Self.loadBrowseFilters(key: Keys.cardsInlineFiltersJSON)
        setsInlineFilters = Self.loadBrowseFilters(key: Keys.setsInlineFiltersJSON)
        pokemonInlineFilters = Self.loadBrowseFilters(key: Keys.pokemonInlineFiltersJSON)
        sealedInlineFilters = Self.loadBrowseFilters(key: Keys.sealedInlineFiltersJSON)
        sealedGridOptions = Self.loadSealedGridOptions()
    }

    private static func loadBrowseFilters(key: String) -> BrowseCardGridFilters {
        if let decoded = decodeDefaultsJSON(BrowseCardGridFilters.self, key: key) {
            var sanitized = sanitizeBrowseFilters(decoded)
            if (key == Keys.sealedFiltersJSON || key == Keys.sealedInlineFiltersJSON),
               sanitized.sortBy == .random {
                sanitized.sortBy = .newestSet
            }
            return sanitized
        }
        var defaults = BrowseCardGridFilters()
        defaults.sortBy = defaultBrowseSort(for: key)
        return defaults
    }

    private func saveBrowseFilters(_ filters: BrowseCardGridFilters, key: String) {
        let sanitized = Self.sanitizeBrowseFilters(filters)
        encodeDefaultsJSON(sanitized, key: key)
    }

    private static func sanitizeBrowseFilters(_ filters: BrowseCardGridFilters) -> BrowseCardGridFilters {
        var next = filters
        if next.sortBy == .acquiredDateNewest {
            next.sortBy = .random
        }
        return next
    }

    private static func defaultBrowseSort(for key: String) -> BrowseCardGridSortOption {
        switch key {
        case Keys.setsFiltersJSON, Keys.setsInlineFiltersJSON:
            return .cardNumber
        case Keys.pokemonFiltersJSON, Keys.pokemonInlineFiltersJSON, Keys.sealedFiltersJSON, Keys.sealedInlineFiltersJSON:
            return .newestSet
        default:
            return .random
        }
    }

    private static func loadSealedGridOptions() -> BrowseGridOptions {
        if let decoded = decodeDefaultsJSON(BrowseGridOptions.self, key: Keys.sealedGridOptionsJSON) {
            return sanitizeGridOptions(decoded)
        }
        var defaults = BrowseGridOptions()
        defaults.columnCount = 2
        return sanitizeGridOptions(defaults)
    }

    private func saveSealedGridOptions(_ options: BrowseGridOptions) {
        let sanitized = Self.sanitizeGridOptions(options)
        encodeDefaultsJSON(sanitized, key: Keys.sealedGridOptionsJSON)
    }

    private static func sanitizeGridOptions(_ options: BrowseGridOptions) -> BrowseGridOptions {
        var next = options
        next.columnCount = min(max(options.columnCount, validColumnRange.lowerBound), validColumnRange.upperBound)
        return next
    }
}
