import StoreKit
import SwiftUI

// MARK: - PremiumUpgradeView
//
// Account-side Premium upgrade sheet. Refactor brief:
//   * Replaced the gold-crown gradient badge with `PremiumLineCardBadge`
//     (minimalist accent line-art).
//   * Headline drops from .heavy 36pt italic to .bold 28pt — same
//     emphasis, less marketing-flyer energy.
//   * Plan picker uses native checkmark selection; "Best Value" pill is
//     gone — savings render as borderless metadata.
//   * Comparison grid checkmarks now use a single accent colour, no
//     mixed-palette crowns / chevrons.
//   * Subscribe button has no leading crown icon; price is part of the
//     centered label.

struct PremiumUpgradeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.bindrAccent) private var accent
    @Environment(AppServices.self) private var services

    @State private var isPurchasing = false
    @State private var restoreError: String?
    @State private var selectedPlan: PlanOption = .annual

    enum PlanOption { case monthly, annual }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BindrSpacing.lg) {
                    heroBlock
                    benefitsList
                    planPickerBlock
                    Color.clear.frame(height: 10)
                }
                .padding(.horizontal, BindrSpacing.lg)
                .padding(.top, BindrSpacing.md)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ctaPanel
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemBackground).ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    ChromeGlassCircleButton(accessibilityLabel: "Close") {
                        Haptics.lightImpact()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.primary)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    ChromeGlassCapsuleButton(label: "Restore") {
                        Task {
                            do {
                                try await services.store.restore()
                                if services.store.isPremium { dismiss() }
                            } catch {
                                restoreError = error.localizedDescription
                            }
                        }
                    }
                }
            }
            .tint(.primary)
            .task {
                if services.store.products.isEmpty {
                    await services.store.loadProducts()
                }
            }
        }
    }

    // MARK: Hero

    private var heroBlock: some View {
        VStack(alignment: .leading, spacing: BindrSpacing.md) {
            PremiumLineCardBadge()
                .frame(width: 90, height: 115)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, BindrSpacing.xs)

            OnboardingHeadline(
                title: "Unlock the full experience.",
                subtitle: "Advanced tools to track value, discover suggested trades, and manage your binders with a professional edge."
            )
        }
    }

    // MARK: Benefits Checklist

    private var benefitsList: some View {
        VStack(alignment: .leading, spacing: BindrSpacing.xs) {
            Text("What's included")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)

            VStack(alignment: .leading, spacing: 8) {
                benefitRow(label: "Unlimited card scans")
                benefitRow(label: "Unlimited collection & binders")
                benefitRow(label: "Full price history & trends")
                benefitRow(label: "Offline database access")
                benefitRow(label: "Priority trade notifications")
                benefitRow(label: "Premium badges (Pokéball & Straw Hat)")
            }
            .padding(BindrSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: BindrRadius.lg, style: .continuous)
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.04 : 0.025))
            }
        }
    }

    private func benefitRow(label: String) -> some View {
        HStack(spacing: BindrSpacing.md) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(accent)
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)
        }
    }

    // MARK: Plan Picker

    private var planPickerBlock: some View {
        HStack(spacing: BindrSpacing.md) {
            squarePlanTile(
                plan: .monthly,
                label: "Monthly",
                price: monthlyPrice,
                breakdown: "£2.99 / mo",
                meta: nil
            )
            
            squarePlanTile(
                plan: .annual,
                label: "Annual",
                price: annualPrice,
                breakdown: "£2.08 / mo",
                meta: "Save 30%",
                subMeta: "Save £10.89/yr"
            )
        }
        .padding(.top, 8)
    }

    private var monthlyPrice: String {
        services.store.products.first?.displayPrice ?? "£2.99"
    }

    private var annualPrice: String {
        services.store.annualProduct?.displayPrice ?? "£24.99"
    }

    private func squarePlanTile(
        plan: PlanOption,
        label: String,
        price: String,
        breakdown: String,
        meta: String?,
        subMeta: String? = nil
    ) -> some View {
        let isSelected = selectedPlan == plan
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) { selectedPlan = plan }
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

    // MARK: CTA panel

    private var ctaPanel: some View {
        VStack(spacing: BindrSpacing.sm) {
            if let restoreError {
                Text(restoreError)
                    .font(.footnote)
                    .foregroundStyle(BindrPalette.alertRed)
                    .multilineTextAlignment(.center)
            }
            if let err = services.store.purchaseError {
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(BindrPalette.alertRed)
                    .multilineTextAlignment(.center)
            }

            OnboardingPrimaryButton(
                title: subscribeTitle,
                isLoading: isPurchasing,
                disabled: services.store.products.isEmpty
            ) {
                Task {
                    isPurchasing = true
                    defer { isPurchasing = false }
                    try? await services.store.purchase(annual: selectedPlan == .annual)
                    if services.store.isPremium { dismiss() }
                }
            }
            .padding(.horizontal, BindrSpacing.lg)

            Text(footerNote)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BindrSpacing.lg)
                .padding(.bottom, BindrSpacing.sm)
        }
        .padding(.top, BindrSpacing.sm)
        .frame(maxWidth: .infinity)
        .background {
            LinearGradient(
                colors: [
                    Color.clear,
                    Color(uiColor: .systemBackground).opacity(0.65),
                    Color(uiColor: .systemBackground)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }

    private var subscribeTitle: String {
        let price = selectedPlan == .annual ? annualPrice : monthlyPrice
        return "Subscribe · \(price)"
    }

    private var footerNote: String {
        if let product = services.store.products.first {
            return "\(product.displayName) · auto-renews until cancelled."
        }
        return "Configure in App Store Connect to enable purchase."
    }
}

// MARK: - Premium-specific Capsule Glass button
private struct ChromeGlassCapsuleButton: View {
    let label: String
    let action: () -> Void

    private var glassStroke: Color { Color.primary.opacity(0.1) }

    var body: some View {
        Button(action: { Haptics.lightImpact(); action() }) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background {
                    if #available(iOS 26.0, *) {
                        Capsule()
                            .fill(.clear)
                            .glassEffect(.clear.tint(nil).interactive(), in: Capsule())
                    } else {
                        Capsule()
                            .fill(.thinMaterial)
                            .overlay {
                                Capsule()
                                    .strokeBorder(glassStroke, lineWidth: 0.5)
                            }
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

