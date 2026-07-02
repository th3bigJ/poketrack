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
    @State private var isRestoring: Bool = false
    @State private var purchaseError: String?
    @State private var restoreMessage: String?
    @State private var hasLoadedProducts = false
    @State private var showRestoreAlert = false
    @State private var restoreAlertMessage = ""

    private var isAlreadySubscribed: Bool {
        services.store.isPremium
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: BindrSpacing.lg) {
                    badgeBlock
                    if isAlreadySubscribed {
                        OnboardingHeadline(
                            title: "You're all set.",
                            subtitle: "Your Premium subscription is active on this Apple ID — unlimited scans, binders, price history, and offline mode are ready to go."
                        )
                    } else {
                        OnboardingHeadline(
                            title: "Unlock the full experience.",
                            subtitle: "Unlimited everything — scans, collection, binders, and available-card trade tools — plus full price history and offline mode."
                        )
                        featureBullets
                        planPicker
                        if let purchaseError {
                            Text(purchaseError)
                                .font(.footnote)
                                .foregroundStyle(BindrPalette.alertRed)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                        }
                        if let restoreMessage {
                            Text(restoreMessage)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    Color.clear.frame(height: 12)
                }
                .padding(.horizontal, BindrSpacing.lg)
                .padding(.top, BindrSpacing.md)
            }
            .scrollIndicators(.hidden)

            OnboardingFooterBar(
                primary: {
                    if isAlreadySubscribed {
                        OnboardingPrimaryButton(title: "Continue", action: onFinish)
                    } else {
                        OnboardingPrimaryButton(
                            title: subscribeTitle,
                            isLoading: isPurchasing,
                            disabled: !hasLoadedProducts
                                || !services.store.hasPurchaseOptions
                        ) {
                            Task { await runPurchase() }
                        }
                    }
                },
                secondary: {
                    if isAlreadySubscribed {
                        EmptyView()
                    } else {
                        VStack(spacing: BindrSpacing.xs) {
                            Button {
                                Haptics.lightImpact()
                                Task { await runRestore() }
                            } label: {
                                HStack(spacing: 6) {
                                    if isRestoring {
                                        ProgressView()
                                            .controlSize(.small)
                                    }
                                    Text("Restore Purchases")
                                        .font(.system(size: 14, weight: .semibold))
                                }
                                .foregroundStyle(accent)
                                .padding(.vertical, BindrSpacing.sm)
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                            .disabled(isRestoring || isPurchasing)

                            OnboardingSecondaryLink(title: "Maybe later", action: onFinish)

                            PremiumPaywallLegalFooter(disclosureText: subscribeCopy.footerNote)
                                .padding(.top, BindrSpacing.xs)
                        }
                    }
                }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            // Fresh installs stay free until the user subscribes or taps Restore — no launch-time sync here.
            if services.store.products.isEmpty {
                await services.store.loadProducts()
            }
            hasLoadedProducts = true
        }
        .alert("Restore Purchases", isPresented: $showRestoreAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(restoreAlertMessage)
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

    private var pricing: PremiumSubscriptionPricing {
        services.store.subscriptionPricing
    }

    private var planPicker: some View {
        HStack(spacing: BindrSpacing.md) {
            squarePlanTile(
                isAnnual: false,
                label: "Monthly",
                price: hasLoadedProducts ? pricing.monthlyDisplayPrice : "…",
                breakdown: hasLoadedProducts ? pricing.monthlyBreakdown : " ",
                meta: hasLoadedProducts
                    ? pricing.trialBadge(annual: false, introEligible: services.store.isIntroOfferEligible(annual: false))
                    : nil,
                subMeta: nil
            )

            squarePlanTile(
                isAnnual: true,
                label: "Annual",
                price: hasLoadedProducts ? pricing.annualDisplayPrice : "…",
                breakdown: hasLoadedProducts ? pricing.annualMonthlyBreakdown : " ",
                meta: hasLoadedProducts
                    ? (pricing.trialBadge(annual: true, introEligible: services.store.isIntroOfferEligible(annual: true))
                       ?? pricing.annualSavingsBadge)
                    : nil,
                subMeta: hasLoadedProducts ? pricing.annualSavingsDetail : nil
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
            .glassCardStyle(cornerRadius: BindrRadius.xl, interactive: false)
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
            featureGridItem(sfIcon: "books.vertical",     title: "Unlimited Binders & Decks", desc: "No collection or deck limits")
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

    /// Special grid cell showing the Pokéball premium badge
    private func pokeballGridItem() -> some View {
        HStack(spacing: 8) {
            PokeballEmblemView(size: 20)
                .frame(width: 34, height: 32, alignment: .center)

            VStack(alignment: .leading, spacing: 3) {
                Text("Premium Badge")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("Pokéball style")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCardStyle(cornerRadius: BindrRadius.md, interactive: false)
    }

    // MARK: - Purchase

    private var subscribeCopy: PremiumSubscribeCopy {
        pricing.subscribeCopy(
            annual: selectAnnual,
            introEligible: services.store.isIntroOfferEligible(annual: selectAnnual)
        )
    }

    private var subscribeTitle: String {
        subscribeCopy.ctaTitle
    }

    private func runPurchase() async {
        isPurchasing = true
        purchaseError = nil
        restoreMessage = nil
        defer { isPurchasing = false }
        do {
            try await services.store.purchase(annual: selectAnnual)
        } catch {
            purchaseError = error.localizedDescription
        }
        if services.store.isPremium { onFinish() }
    }

    private func runRestore() async {
        isRestoring = true
        purchaseError = nil
        restoreMessage = nil
        defer { isRestoring = false }
        do {
            try await services.store.restore()
            if services.store.isPremium {
                restoreAlertMessage = "Your Premium subscription has been restored."
                showRestoreAlert = true
            } else {
                restoreAlertMessage = services.store.restoreMessage
                    ?? "No active subscription was found for this Apple ID."
                restoreMessage = restoreAlertMessage
                showRestoreAlert = true
            }
        } catch {
            restoreAlertMessage = services.store.purchaseError ?? error.localizedDescription
            restoreMessage = restoreAlertMessage
            showRestoreAlert = true
        }
    }
}
