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

    var currency: PriceDisplayCurrency {
        didSet {
            guard currency != oldValue else { return }
            UserDefaults.standard.set(currency.rawValue, forKey: Self.defaultsKey)
        }
    }

    init() {
        let raw = UserDefaults.standard.string(forKey: Self.defaultsKey)
        if let raw, let parsed = PriceDisplayCurrency(rawValue: raw) {
            currency = parsed
        } else {
            currency = .gbp
        }
    }
}
