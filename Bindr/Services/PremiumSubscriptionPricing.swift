import Foundation
import StoreKit

/// Localized premium plan copy derived from StoreKit `Product` prices so every
/// string uses the same App Store currency (no hard-coded currency symbols in views).
struct PremiumSubscriptionPricing {
    let monthlyProduct: Product?
    let annualProduct: Product?
    /// ISO 3166-1 alpha-3 from `Storefront.current` when products were loaded (e.g. `GBR`).
    let storefrontCountryCode: String?

    private var referenceProduct: Product? { annualProduct ?? monthlyProduct }

    var monthlyDisplayPrice: String {
        if let monthlyProduct { return monthlyProduct.displayPrice }
        return formatPlaceholderAmount(2.99)
    }

    var annualDisplayPrice: String {
        if let annualProduct { return annualProduct.displayPrice }
        return formatPlaceholderAmount(24.99)
    }

    var monthlyBreakdown: String {
        "\(monthlyDisplayPrice) / mo"
    }

    var annualMonthlyBreakdown: String {
        guard let annual = annualProduct else {
            return "\(formatPlaceholderAmount(2.08)) / mo"
        }
        let perMonth = annual.price / 12
        return "\(annual.priceFormatStyle.format(perMonth)) / mo"
    }

    var annualSavingsBadge: String? {
        guard let monthly = monthlyProduct, let annual = annualProduct else {
            return "Save 30%"
        }
        let yearlyAtMonthlyRate = monthly.price * 12
        guard yearlyAtMonthlyRate > 0 else { return nil }
        let percent = ((yearlyAtMonthlyRate - annual.price) / yearlyAtMonthlyRate) * 100
        let rounded = Int(NSDecimalNumber(decimal: percent).doubleValue.rounded())
        guard rounded > 0 else { return nil }
        return "Save \(rounded)%"
    }

    var annualSavingsDetail: String? {
        guard let monthly = monthlyProduct, let annual = annualProduct else {
            return nil
        }
        let savings = (monthly.price * 12) - annual.price
        guard savings > 0 else { return nil }
        return "Save \(annual.priceFormatStyle.format(savings))/yr"
    }

    func displayPrice(annual: Bool) -> String {
        annual ? annualDisplayPrice : monthlyDisplayPrice
    }

    /// Formats placeholder tiers before StoreKit products arrive, or if loading failed.
    private func formatPlaceholderAmount(_ amount: Decimal) -> String {
        if let referenceProduct {
            return referenceProduct.priceFormatStyle.format(amount)
        }
        let code = Self.currencyCode(
            storefrontCountryCode: storefrontCountryCode,
            regionCode: Locale.current.region?.identifier
        )
        return amount.formatted(.currency(code: code).locale(Self.locale(forCurrencyCode: code)))
    }

    /// Maps App Store storefront / device region to ISO 4217 currency.
    /// Uses **region** (Settings → General → Language & Region), not language alone,
    /// so UK devices set to English (UK) or English (US) language still get GBP when region is GB.
    static func currencyCode(storefrontCountryCode: String?, regionCode: String?) -> String {
        if let storefrontCountryCode {
            switch storefrontCountryCode.uppercased() {
            case "GBR": return "GBP"
            case "USA": return "USD"
            case "AUS": return "AUD"
            case "CAN": return "CAD"
            case "NZL": return "NZD"
            case "DEU", "FRA", "ITA", "ESP", "IRL", "NLD", "BEL", "AUT", "PRT", "FIN", "GRC":
                return "EUR"
            default:
                break
            }
        }

        switch regionCode?.uppercased() {
        case "GB": return "GBP"
        case "US": return "USD"
        case "AU": return "AUD"
        case "CA": return "CAD"
        case "NZ": return "NZD"
        case "DE", "FR", "IT", "ES", "IE", "NL", "BE", "AT", "PT", "FI", "GR":
            return "EUR"
        default:
            break
        }

        return Locale.current.currency?.identifier ?? "GBP"
    }

    static func locale(forCurrencyCode code: String) -> Locale {
        switch code {
        case "GBP": return Locale(identifier: "en_GB")
        case "USD": return Locale(identifier: "en_US")
        case "EUR": return Locale(identifier: "en_IE")
        case "AUD": return Locale(identifier: "en_AU")
        case "CAD": return Locale(identifier: "en_CA")
        case "NZD": return Locale(identifier: "en_NZ")
        default: return Locale.current
        }
    }
}
