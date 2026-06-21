import Foundation
import StoreKit

/// Paywall button label, plan badge, and subscription disclosure derived from StoreKit.
struct PremiumSubscribeCopy: Equatable {
    let ctaTitle: String
    let footerNote: String
    let trialBadge: String?
}

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

    func product(annual: Bool) -> Product? {
        annual ? annualProduct : monthlyProduct
    }

    func subscribeCopy(annual: Bool, introEligible: Bool) -> PremiumSubscribeCopy {
        let product = product(annual: annual)
        let price = displayPrice(annual: annual)
        let billingPeriod = Self.billingPeriodLabel(for: product)

        guard introEligible,
              let offer = product?.subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial else {
            let name = product?.displayName ?? "Bindr Premium"
            return PremiumSubscribeCopy(
                ctaTitle: "Subscribe · \(price)",
                footerNote: "\(name) auto-renews until cancelled in iOS Settings → Apple ID → Subscriptions.",
                trialBadge: nil
            )
        }

        let trialPeriod = Self.localizedPeriodDescription(
            period: offer.period,
            count: offer.periodCount
        )
        let badge = "\(trialPeriod) free"

        return PremiumSubscribeCopy(
            ctaTitle: "Start Free Trial",
            footerNote: "\(trialPeriod) free, then \(price)/\(billingPeriod). Auto-renews until cancelled in iOS Settings → Apple ID → Subscriptions. One introductory offer per Apple ID.",
            trialBadge: badge
        )
    }

    func trialBadge(annual: Bool, introEligible: Bool) -> String? {
        subscribeCopy(annual: annual, introEligible: introEligible).trialBadge
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

    static func localizedPeriodDescription(
        period: Product.SubscriptionPeriod,
        count: Int = 1
    ) -> String {
        let value = period.value * count
        switch period.unit {
        case .day:
            return value == 1 ? "1 day" : "\(value) days"
        case .week:
            return value == 1 ? "1 week" : "\(value) weeks"
        case .month:
            return value == 1 ? "1 month" : "\(value) months"
        case .year:
            return value == 1 ? "1 year" : "\(value) years"
        @unknown default:
            return value == 1 ? "1 period" : "\(value) periods"
        }
    }

    static func billingPeriodLabel(for product: Product?) -> String {
        guard let unit = product?.subscription?.subscriptionPeriod.unit else { return "period" }
        switch unit {
        case .month: return "month"
        case .year: return "year"
        case .week: return "week"
        case .day: return "day"
        @unknown default: return "period"
        }
    }
}
