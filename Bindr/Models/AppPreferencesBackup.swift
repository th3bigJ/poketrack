import Foundation

/// UserDefaults-backed app preferences included in Bindr Cloud (R2) backups.
/// Device-only flags (onboarding completion, splash version, etc.) are excluded.
struct AppPreferencesBackup: Codable, Equatable {
    var priceDisplayCurrency: String?
    var browseGrid: BrowseGridOptions?
    var themeAccentColorHex: String?
    var themeAppearance: String?
    var themeBackgroundGlowEnabled: Bool?
    var offlineStrictMode: Bool?
    var offlinePackPokemonEnabled: Bool?
    var collectionFilters: BrowseCardGridFilters?
    var wishlistFilters: BrowseCardGridFilters?
    var tradeListFilters: BrowseCardGridFilters?
    var collectGridOptions: BrowseGridOptions?
    var folderGridOptions: BrowseGridOptions?
    var browseCardsFilters: BrowseCardGridFilters?
    var browseSetsFilters: BrowseCardGridFilters?
    var browsePokemonFilters: BrowseCardGridFilters?
    var browseProductsFilters: BrowseCardGridFilters?
    var browseCardsInlineFilters: BrowseCardGridFilters?
    var browseSetsInlineFilters: BrowseCardGridFilters?
    var browsePokemonInlineFilters: BrowseCardGridFilters?
    var browseProductsInlineFilters: BrowseCardGridFilters?
    var browseProductsGridOptions: BrowseGridOptions?

    static func capture() -> AppPreferencesBackup {
        let defaults = UserDefaults.standard
        return AppPreferencesBackup(
            priceDisplayCurrency: defaults.string(forKey: Keys.priceDisplayCurrency),
            browseGrid: loadBrowseGridFromLegacyKeys(defaults: defaults),
            themeAccentColorHex: defaults.string(forKey: Keys.themeAccentColorHex),
            themeAppearance: defaults.string(forKey: Keys.themeAppearance),
            themeBackgroundGlowEnabled: boolIfPresent(defaults, key: Keys.themeBackgroundGlowEnabled),
            offlineStrictMode: boolIfPresent(defaults, key: Keys.offlineStrictMode),
            offlinePackPokemonEnabled: boolIfPresent(defaults, key: Keys.offlinePackPokemon),
            collectionFilters: decodeJSON(BrowseCardGridFilters.self, key: Keys.collectionFiltersJSON, defaults: defaults),
            wishlistFilters: decodeJSON(BrowseCardGridFilters.self, key: Keys.wishlistFiltersJSON, defaults: defaults),
            tradeListFilters: decodeJSON(BrowseCardGridFilters.self, key: Keys.tradeListFiltersJSON, defaults: defaults),
            collectGridOptions: loadCollectGridOptions(defaults: defaults),
            folderGridOptions: loadFolderGridOptions(defaults: defaults),
            browseCardsFilters: decodeJSON(BrowseCardGridFilters.self, key: Keys.browseCardsFiltersJSON, defaults: defaults),
            browseSetsFilters: decodeJSON(BrowseCardGridFilters.self, key: Keys.browseSetsFiltersJSON, defaults: defaults),
            browsePokemonFilters: decodeJSON(BrowseCardGridFilters.self, key: Keys.browsePokemonFiltersJSON, defaults: defaults),
            browseProductsFilters: decodeJSON(BrowseCardGridFilters.self, key: Keys.browseProductsFiltersJSON, defaults: defaults),
            browseCardsInlineFilters: decodeJSON(BrowseCardGridFilters.self, key: Keys.browseCardsInlineFiltersJSON, defaults: defaults),
            browseSetsInlineFilters: decodeJSON(BrowseCardGridFilters.self, key: Keys.browseSetsInlineFiltersJSON, defaults: defaults),
            browsePokemonInlineFilters: decodeJSON(BrowseCardGridFilters.self, key: Keys.browsePokemonInlineFiltersJSON, defaults: defaults),
            browseProductsInlineFilters: decodeJSON(BrowseCardGridFilters.self, key: Keys.browseProductsInlineFiltersJSON, defaults: defaults),
            browseProductsGridOptions: decodeJSON(BrowseGridOptions.self, key: Keys.browseProductsGridOptionsJSON, defaults: defaults)
        )
    }

    func apply() {
        let defaults = UserDefaults.standard

        if let priceDisplayCurrency {
            defaults.set(priceDisplayCurrency, forKey: Keys.priceDisplayCurrency)
        }

        if let browseGrid {
            Self.saveBrowseGrid(browseGrid, defaults: defaults)
        }

        if let themeAccentColorHex {
            defaults.set(themeAccentColorHex, forKey: Keys.themeAccentColorHex)
        }
        if let themeAppearance {
            defaults.set(themeAppearance, forKey: Keys.themeAppearance)
        }
        if let themeBackgroundGlowEnabled {
            defaults.set(themeBackgroundGlowEnabled, forKey: Keys.themeBackgroundGlowEnabled)
        }

        if let offlineStrictMode {
            defaults.set(offlineStrictMode, forKey: Keys.offlineStrictMode)
        }
        if let offlinePackPokemonEnabled {
            defaults.set(offlinePackPokemonEnabled, forKey: Keys.offlinePackPokemon)
        }

        Self.encodeJSON(collectionFilters, key: Keys.collectionFiltersJSON, defaults: defaults)
        Self.encodeJSON(wishlistFilters, key: Keys.wishlistFiltersJSON, defaults: defaults)
        Self.encodeJSON(tradeListFilters, key: Keys.tradeListFiltersJSON, defaults: defaults)

        if let collectGridOptions {
            Self.saveCollectGridOptions(collectGridOptions, defaults: defaults)
        }
        if let folderGridOptions {
            Self.saveFolderGridOptions(folderGridOptions, defaults: defaults)
        }

        Self.encodeJSON(browseCardsFilters, key: Keys.browseCardsFiltersJSON, defaults: defaults)
        Self.encodeJSON(browseSetsFilters, key: Keys.browseSetsFiltersJSON, defaults: defaults)
        Self.encodeJSON(browsePokemonFilters, key: Keys.browsePokemonFiltersJSON, defaults: defaults)
        Self.encodeJSON(browseProductsFilters, key: Keys.browseProductsFiltersJSON, defaults: defaults)
        Self.encodeJSON(browseCardsInlineFilters, key: Keys.browseCardsInlineFiltersJSON, defaults: defaults)
        Self.encodeJSON(browseSetsInlineFilters, key: Keys.browseSetsInlineFiltersJSON, defaults: defaults)
        Self.encodeJSON(browsePokemonInlineFilters, key: Keys.browsePokemonInlineFiltersJSON, defaults: defaults)
        Self.encodeJSON(browseProductsInlineFilters, key: Keys.browseProductsInlineFiltersJSON, defaults: defaults)
        Self.encodeJSON(browseProductsGridOptions, key: Keys.browseProductsGridOptionsJSON, defaults: defaults)

        NotificationCenter.default.post(name: .appPreferencesDidRestore, object: nil)
    }

    static func notifyDidChange() {
        NotificationCenter.default.post(name: .appPreferencesDidChange, object: nil)
    }

    var isEmpty: Bool {
        self == AppPreferencesBackup()
    }

    // MARK: - Keys

    private enum Keys {
        static let priceDisplayCurrency = "priceDisplayCurrency"
        static let browseShowCardName = "browseGridShowCardName"
        static let browseShowSetName = "browseGridShowSetName"
        static let browseShowSetID = "browseGridShowSetID"
        static let browseShowPricing = "browseGridShowPricing"
        static let browseColumnCount = "browseGridColumnCount"
        static let themePrefix = "Bindr.theme."
        static let themeAccentColorHex = themePrefix + "user_accent_color_hex"
        static let themeAppearance = themePrefix + "user_app_appearance"
        static let themeBackgroundGlowEnabled = themePrefix + "user_background_glow_enabled"
        static let offlineStrictMode = "offline_strict_no_cdn"
        static let offlinePackPokemon = "offline_pack_pokemon"
        static let collectionFiltersJSON = "collectFiltersJSON"
        static let wishlistFiltersJSON = "wishlistFiltersJSON"
        static let tradeListFiltersJSON = "tradeListFiltersJSON"
        static let gridShowCardName = "collectGridShowCardName"
        static let gridShowSetName = "collectGridShowSetName"
        static let gridShowSetID = "collectGridShowSetID"
        static let gridShowPricing = "collectGridShowPricing"
        static let gridShowOwned = "collectGridShowOwned"
        static let gridColumnCount = "collectGridColumnCount"
        static let folderGridShowCardName = "folderGridShowCardName"
        static let folderGridShowSetName = "folderGridShowSetName"
        static let folderGridShowSetID = "folderGridShowSetID"
        static let folderGridShowPricing = "folderGridShowPricing"
        static let folderGridShowOwned = "folderGridShowOwned"
        static let folderGridColumnCount = "folderGridColumnCount"
        static let browseCardsFiltersJSON = "browseFiltersCardsJSON"
        static let browseSetsFiltersJSON = "browseFiltersSetsJSON"
        static let browsePokemonFiltersJSON = "browseFiltersPokemonJSON"
        static let browseProductsFiltersJSON = "browseFiltersProductsJSON"
        static let browseCardsInlineFiltersJSON = "browseInlineFiltersCardsJSON"
        static let browseSetsInlineFiltersJSON = "browseInlineFiltersSetsJSON"
        static let browsePokemonInlineFiltersJSON = "browseInlineFiltersPokemonJSON"
        static let browseProductsInlineFiltersJSON = "browseInlineFiltersProductsJSON"
        static let browseProductsGridOptionsJSON = "browseGridOptionsProductsJSON"
    }

    private static func boolIfPresent(_ defaults: UserDefaults, key: String) -> Bool? {
        guard defaults.object(forKey: key) != nil else { return nil }
        return defaults.bool(forKey: key)
    }

    private static func decodeJSON<T: Decodable>(
        _ type: T.Type,
        key: String,
        defaults: UserDefaults
    ) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func encodeJSON<T: Encodable>(
        _ value: T?,
        key: String,
        defaults: UserDefaults
    ) {
        guard let value else { return }
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private static func loadBrowseGridFromLegacyKeys(defaults: UserDefaults) -> BrowseGridOptions? {
        let hasValue =
            defaults.object(forKey: Keys.browseShowCardName) != nil
            || defaults.object(forKey: Keys.browseShowSetName) != nil
            || defaults.object(forKey: Keys.browseShowSetID) != nil
            || defaults.object(forKey: Keys.browseShowPricing) != nil
            || defaults.object(forKey: Keys.browseColumnCount) != nil
        guard hasValue else { return nil }

        let base = BrowseGridOptions()
        return BrowseGridOptions(
            showCardName: defaults.object(forKey: Keys.browseShowCardName) != nil
                ? defaults.bool(forKey: Keys.browseShowCardName) : base.showCardName,
            showSetName: defaults.object(forKey: Keys.browseShowSetName) != nil
                ? defaults.bool(forKey: Keys.browseShowSetName) : base.showSetName,
            showSetID: defaults.object(forKey: Keys.browseShowSetID) != nil
                ? defaults.bool(forKey: Keys.browseShowSetID) : base.showSetID,
            showPricing: defaults.object(forKey: Keys.browseShowPricing) != nil
                ? defaults.bool(forKey: Keys.browseShowPricing) : base.showPricing,
            columnCount: defaults.object(forKey: Keys.browseColumnCount) != nil
                ? defaults.integer(forKey: Keys.browseColumnCount) : base.columnCount
        )
    }

    private static func saveBrowseGrid(_ options: BrowseGridOptions, defaults: UserDefaults) {
        defaults.set(options.showCardName, forKey: Keys.browseShowCardName)
        defaults.set(options.showSetName, forKey: Keys.browseShowSetName)
        defaults.set(options.showSetID, forKey: Keys.browseShowSetID)
        defaults.set(options.showPricing, forKey: Keys.browseShowPricing)
        defaults.set(options.columnCount, forKey: Keys.browseColumnCount)
    }

    private static func loadCollectGridOptions(defaults: UserDefaults) -> BrowseGridOptions? {
        let hasValue =
            defaults.object(forKey: Keys.gridShowCardName) != nil
            || defaults.object(forKey: Keys.gridColumnCount) != nil
        guard hasValue else { return nil }
        let base = BrowseGridOptions()
        return BrowseGridOptions(
            showCardName: defaults.object(forKey: Keys.gridShowCardName) != nil ? defaults.bool(forKey: Keys.gridShowCardName) : base.showCardName,
            showSetName: defaults.object(forKey: Keys.gridShowSetName) != nil ? defaults.bool(forKey: Keys.gridShowSetName) : base.showSetName,
            showSetID: defaults.object(forKey: Keys.gridShowSetID) != nil ? defaults.bool(forKey: Keys.gridShowSetID) : base.showSetID,
            showPricing: defaults.object(forKey: Keys.gridShowPricing) != nil ? defaults.bool(forKey: Keys.gridShowPricing) : base.showPricing,
            showOwned: defaults.object(forKey: Keys.gridShowOwned) != nil ? defaults.bool(forKey: Keys.gridShowOwned) : base.showOwned,
            columnCount: defaults.object(forKey: Keys.gridColumnCount) != nil ? defaults.integer(forKey: Keys.gridColumnCount) : base.columnCount
        )
    }

    private static func saveCollectGridOptions(_ options: BrowseGridOptions, defaults: UserDefaults) {
        defaults.set(options.showCardName, forKey: Keys.gridShowCardName)
        defaults.set(options.showSetName, forKey: Keys.gridShowSetName)
        defaults.set(options.showSetID, forKey: Keys.gridShowSetID)
        defaults.set(options.showPricing, forKey: Keys.gridShowPricing)
        defaults.set(options.showOwned, forKey: Keys.gridShowOwned)
        defaults.set(options.columnCount, forKey: Keys.gridColumnCount)
    }

    private static func loadFolderGridOptions(defaults: UserDefaults) -> BrowseGridOptions? {
        let hasValue =
            defaults.object(forKey: Keys.folderGridShowCardName) != nil
            || defaults.object(forKey: Keys.folderGridColumnCount) != nil
        guard hasValue else { return nil }
        let base = BrowseGridOptions()
        return BrowseGridOptions(
            showCardName: defaults.object(forKey: Keys.folderGridShowCardName) != nil ? defaults.bool(forKey: Keys.folderGridShowCardName) : base.showCardName,
            showSetName: defaults.object(forKey: Keys.folderGridShowSetName) != nil ? defaults.bool(forKey: Keys.folderGridShowSetName) : base.showSetName,
            showSetID: defaults.object(forKey: Keys.folderGridShowSetID) != nil ? defaults.bool(forKey: Keys.folderGridShowSetID) : base.showSetID,
            showPricing: defaults.object(forKey: Keys.folderGridShowPricing) != nil ? defaults.bool(forKey: Keys.folderGridShowPricing) : base.showPricing,
            showOwned: defaults.object(forKey: Keys.folderGridShowOwned) != nil ? defaults.bool(forKey: Keys.folderGridShowOwned) : base.showOwned,
            columnCount: defaults.object(forKey: Keys.folderGridColumnCount) != nil ? defaults.integer(forKey: Keys.folderGridColumnCount) : base.columnCount
        )
    }

    private static func saveFolderGridOptions(_ options: BrowseGridOptions, defaults: UserDefaults) {
        defaults.set(options.showCardName, forKey: Keys.folderGridShowCardName)
        defaults.set(options.showSetName, forKey: Keys.folderGridShowSetName)
        defaults.set(options.showSetID, forKey: Keys.folderGridShowSetID)
        defaults.set(options.showPricing, forKey: Keys.folderGridShowPricing)
        defaults.set(options.showOwned, forKey: Keys.folderGridShowOwned)
        defaults.set(options.columnCount, forKey: Keys.folderGridColumnCount)
    }
}

extension Notification.Name {
    static let appPreferencesDidChange = Notification.Name("appPreferencesDidChange")
    static let appPreferencesDidRestore = Notification.Name("appPreferencesDidRestore")
}
