import Foundation
import StoreKit

/// Localized premium plan copy derived from StoreKit `Product` prices so every
/// string uses the same App Store currency (no hard-coded £ amounts in views).
struct PremiumSubscriptionPricing {
    let monthlyProduct: Product?
    let annualProduct: Product?

    var monthlyDisplayPrice: String {
        monthlyProduct?.displayPrice ?? Self.fallbackDisplayPrice(2.99)
    }

    var annualDisplayPrice: String {
        annualProduct?.displayPrice ?? Self.fallbackDisplayPrice(24.99)
    }

    var monthlyBreakdown: String {
        "\(monthlyDisplayPrice) / mo"
    }

    var annualMonthlyBreakdown: String {
        guard let annual = annualProduct else {
            return "\(Self.fallbackDisplayPrice(2.08)) / mo"
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

    private static func fallbackDisplayPrice(_ amount: Decimal) -> String {
        amount.formatted(.currency(code: Locale.current.currency?.identifier ?? "GBP"))
    }
}
