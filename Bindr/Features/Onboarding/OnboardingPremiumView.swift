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
                VStack(alignment: .leading, spacing: BindrSpacing.lg) {
                    badgeBlock
                    OnboardingHeadline(
                        title: "Unlock the full experience.",
                        subtitle: "Unlimited everything — scans, collection, binders, and trade listings — plus full price history and offline mode."
                    )
                    featureBullets
                    planPicker
                    Color.clear.frame(height: 12)
                }
                .padding(.horizontal, BindrSpacing.lg)
                .padding(.top, BindrSpacing.md)
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

    // MARK: - Badge

    private var badgeBlock: some View {
        VStack {
            PremiumLineCardBadge()
                .frame(width: 88, height: 110)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, BindrSpacing.sm)
    }

    // MARK: - Plan picker

    private var planPicker: some View {
        HStack(spacing: BindrSpacing.md) {
            squarePlanTile(
                isAnnual: false,
                label: "Monthly",
                price: services.store.products.first?.displayPrice ?? "£2.99",
                breakdown: "£2.99 / mo",
                meta: nil
            )
            
            squarePlanTile(
                isAnnual: true,
                label: "Annual",
                price: services.store.annualProduct?.displayPrice ?? "£24.99",
                breakdown: "£2.08 / mo",
                meta: "Save 30%",
                subMeta: "Save £10.89/yr"
            )
        }
        .padding(.top, 4)
    }

    private func squarePlanTile(
        isAnnual: Bool,
        label: String,
        price: String,
        breakdown: String,
        meta: String?,
        subMeta: String? = nil
    ) -> some View {
        let isSelected = selectAnnual == isAnnual
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) { selectAnnual = isAnnual }
            Haptics.lightImpact()
        } label: {
            VStack(spacing: 8) {
                if let meta {
                    Text(meta)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(accent.gradient, in: Capsule())
                        .offset(y: -14)
                        .padding(.bottom, -14)
                } else {
                    Spacer().frame(height: 12)
                }
                
                Text(label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                
                Text(price)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.primary)
                
                Text(breakdown)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                
                if let subMeta {
                    Text(subMeta)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(accent)
                        .padding(.top, 2)
                } else {
                    Spacer().frame(height: 16)
                }
            }
            .padding(.vertical, BindrSpacing.md)
            .padding(.horizontal, BindrSpacing.sm)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: BindrRadius.xl, style: .continuous)
                    .fill(isSelected
                          ? accent.opacity(colorScheme == .dark ? 0.14 : 0.08)
                          : Color.primary.opacity(colorScheme == .dark ? 0.05 : 0.04))
            }
            .overlay {
                RoundedRectangle(cornerRadius: BindrRadius.xl, style: .continuous)
                    .stroke(isSelected ? accent : Color.clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Feature bullets

    private var featureBullets: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            featureGridItem(sfIcon: "camera.viewfinder",  title: "Unlimited Scans",    desc: "Scan cards instantly")
            featureGridItem(sfIcon: "books.vertical",     title: "Unlimited Binders",  desc: "No collection limits")
            featureGridItem(sfIcon: "chart.line.uptrend.xyaxis", title: "Price History", desc: "Track market trends")
            pokeballGridItem()
            featureGridItem(sfIcon: "arrow.left.arrow.right", title: "Priority Trades", desc: "Faster local matches")
            featureGridItem(sfIcon: "lock.shield",        title: "Offline Database",   desc: "Access cards offline")
        }
    }

    /// Standard grid cell with an SF Symbol icon
    private func featureGridItem(sfIcon: String, title: String, desc: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: sfIcon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 32, height: 32, alignment: .center)
                .background(accent.opacity(colorScheme == .dark ? 0.12 : 0.07), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(desc)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCardStyle(cornerRadius: BindrRadius.md, interactive: false)
    }

    /// Special grid cell using the real PokeballEmblemView instead of an SF Symbol
    private func pokeballGridItem() -> some View {
        HStack(spacing: 10) {
            PokeballEmblemView(size: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text("Pokéball Badge")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text("Premium profile style")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCardStyle(cornerRadius: BindrRadius.md, interactive: false)
    }

    // MARK: - Purchase

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
