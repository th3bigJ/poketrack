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

// MARK: - Collection filter + grid persistence

/// Persists the collection tab's filter choices (sort, toggles) and grid options across launches.
/// Only the stable, non-set-specific fields are saved: sortBy, showDuplicates, and all grid options.
/// Set-specific filters (energy, rarity, trainer type) are intentionally left ephemeral.
@Observable
final class CollectionFiltersSettings {
    private static let validColumnRange = 1...4

    private enum Keys {
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
        let d = UserDefaults.standard
        var f = BrowseCardGridFilters()
        f.sortBy = BrowseCardGridSortOption(rawValue: d.string(forKey: Keys.collectionSortBy) ?? "") ?? .price
        f.showDuplicates = d.object(forKey: Keys.collectionShowDups) != nil
            ? d.bool(forKey: Keys.collectionShowDups) : false
        return f
    }

    private static func loadWishlistFilters() -> BrowseCardGridFilters {
        let d = UserDefaults.standard
        var f = BrowseCardGridFilters()
        f.sortBy = BrowseCardGridSortOption(rawValue: d.string(forKey: Keys.wishlistSortBy) ?? "") ?? .random
        return f
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
        let d = UserDefaults.standard
        d.set(f.sortBy.rawValue, forKey: Keys.collectionSortBy)
        d.set(f.showDuplicates, forKey: Keys.collectionShowDups)
    }

    private func saveWishlistFilters(_ f: BrowseCardGridFilters) {
        UserDefaults.standard.set(f.sortBy.rawValue, forKey: Keys.wishlistSortBy)
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
}
