import StoreKit
import SwiftUI

// MARK: - OnboardingPremiumView
//
// Step 5. Refactor brief:
//   * Replaced the stock gold-crown graphic with `PremiumLineCardBadge` —
//     a minimal line-art "premium card" with the brand wordmark inside.
//     Reads as a refined collectible, not a stock paywall asset.
//   * Plan picker uses native checkmark selection (no radio dot, no
//     gradient stroke). "Best value" pill stripped; the savings appears
//     as a borderless caption next to the annual price.
//   * Feature bullets all use a single uniform checkmark color (accent).
//     No more rainbow of multi-colored ticks.
//   * Heavy weights everywhere → bold/semibold.
//   * Primary CTA: "Subscribe" / "Subscribe · £24.99" — no trailing icon.

struct OnboardingPremiumView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.bindrAccent) private var accent

    let onFinish: () -> Void

    @State private var selectAnnual: Bool = true
    @State private var isPurchasing: Bool = false
    @State private var purchaseError: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: BindrSpacing.xl) {
                    badgeBlock
                    OnboardingHeadline(
                        title: "Unlock the full experience.",
                        subtitle: "Unlimited everything — scans, collection, binders, and trade listings — plus full price history and offline mode."
                    )
                    planPicker
                    featureBullets
                    Color.clear.frame(height: 90)
                }
                .padding(.horizontal, BindrSpacing.lg)
                .padding(.top, BindrSpacing.lg)
            }
            .scrollIndicators(.hidden)

            OnboardingFooterBar(
                primary: {
                    OnboardingPrimaryButton(
                        title: subscribeTitle,
                        isLoading: isPurchasing,
                        disabled: services.store.products.isEmpty
                    ) {
                        Task { await runPurchase() }
                    }
                },
                secondary: {
                    OnboardingSecondaryLink(title: "Maybe later", action: onFinish)
                }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            if services.store.isPremium {
                onFinish()
                return
            }
            if services.store.products.isEmpty {
                await services.store.loadProducts()
            }
        }
    }

    // MARK: Badge

    private var badgeBlock: some View {
        VStack {
            PremiumLineCardBadge()
                .frame(width: 110, height: 140)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, BindrSpacing.lg)
    }

    // MARK: Plan picker

    private var planPicker: some View {
        VStack(spacing: BindrSpacing.sm) {
            planTile(
                isAnnual: false,
                label: "Monthly",
                price: services.store.products.first?.displayPrice ?? "£2.99",
                cadence: "per month",
                meta: nil
            )
            planTile(
                isAnnual: true,
                label: "Annual",
                price: services.store.annualProduct?.displayPrice ?? "£24.99",
                cadence: "per year",
                meta: "Save 30%"
            )
        }
    }

    private func planTile(
        isAnnual: Bool,
        label: String,
        price: String,
        cadence: String,
        meta: String?
    ) -> some View {
        let isSelected = selectAnnual == isAnnual
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) { selectAnnual = isAnnual }
            Haptics.lightImpact()
        } label: {
            HStack(spacing: BindrSpacing.md) {
                // Native checkmark selection cue.
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(isSelected ? accent : Color.primary.opacity(0.18))
                    .symbolRenderingMode(.hierarchical)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: BindrSpacing.sm) {
                        Text(label)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                        if let meta {
                            // Borderless metadata. No pill background.
                            Text(meta)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(cadence)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Text(price)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .padding(BindrSpacing.md)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: BindrRadius.xl, style: .continuous)
                    .fill(isSelected
                          ? accent.opacity(colorScheme == .dark ? 0.14 : 0.08)
                          : Color.primary.opacity(colorScheme == .dark ? 0.05 : 0.04))
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Feature bullets

    private var featureBullets: some View {
        VStack(alignment: .leading, spacing: BindrSpacing.sm) {
            bulletRow(label: "Unlimited card scans")
            bulletRow(label: "Unlimited collection & wishlist")
            bulletRow(label: "Unlimited binders & decks")
            bulletRow(label: "Full price history")
            bulletRow(label: "Offline mode included")
        }
        .padding(BindrSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCardStyle(cornerRadius: BindrRadius.xl, interactive: false)
    }

    private func bulletRow(label: String) -> some View {
        HStack(spacing: BindrSpacing.md) {
            // Unified accent check — no more rainbow of icon tints.
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(accent)
                .frame(width: 18, alignment: .leading)
            Text(label)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
    }

    // MARK: Purchase

    private var subscribeTitle: String {
        let price = selectAnnual
            ? (services.store.annualProduct?.displayPrice ?? "£24.99")
            : (services.store.products.first?.displayPrice ?? "£2.99")
        return "Subscribe · \(price)"
    }

    private func runPurchase() async {
        isPurchasing = true
        purchaseError = nil
        defer { isPurchasing = false }
        do {
            try await services.store.purchase(annual: selectAnnual)
        } catch {
            purchaseError = error.localizedDescription
        }
        if services.store.isPremium { onFinish() }
    }
}
