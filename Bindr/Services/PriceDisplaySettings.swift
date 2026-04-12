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
    private enum Keys {
        static let showCardName = "browseGridShowCardName"
        static let showSetName = "browseGridShowSetName"
        static let showPricing = "browseGridShowPricing"
        static let columnCount = "browseGridColumnCount"
    }

    private let cloudSettings: CloudSettingsService

    var options: BrowseGridOptions {
        didSet {
            guard options != oldValue else { return }
            saveToLocalDefaults(options)
            cloudSettings.saveBrowseGridOptions(options)
        }
    }

    init(cloudSettings: CloudSettingsService) {
        self.cloudSettings = cloudSettings

        let localOptions = Self.loadFromLocalDefaults()
        if let cloudOptions = cloudSettings.loadBrowseGridOptions() {
            options = cloudOptions
            saveToLocalDefaults(cloudOptions)
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
                if self.options != cloudOptions {
                    self.options = cloudOptions
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
            showPricing: defaults.object(forKey: Keys.showPricing) != nil
                ? defaults.bool(forKey: Keys.showPricing)
                : base.showPricing,
            columnCount: defaults.object(forKey: Keys.columnCount) != nil
                ? defaults.integer(forKey: Keys.columnCount)
                : base.columnCount
        )
    }

    private func saveToLocalDefaults(_ options: BrowseGridOptions) {
        let defaults = UserDefaults.standard
        defaults.set(options.showCardName, forKey: Keys.showCardName)
        defaults.set(options.showSetName, forKey: Keys.showSetName)
        defaults.set(options.showPricing, forKey: Keys.showPricing)
        defaults.set(options.columnCount, forKey: Keys.columnCount)
    }
}
