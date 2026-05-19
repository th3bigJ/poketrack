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
                VStack(alignment: .leading, spacing: BindrSpacing.xl) {
                    heroBlock
                    planPickerBlock
                    comparisonGrid
                    Color.clear.frame(height: 20)
                }
                .padding(.horizontal, BindrSpacing.lg)
                .padding(.top, BindrSpacing.lg)
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
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Restore") {
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
            .task {
                if services.store.products.isEmpty {
                    await services.store.loadProducts()
                }
            }
        }
    }

    // MARK: Hero

    private var heroBlock: some View {
        VStack(alignment: .leading, spacing: BindrSpacing.lg) {
            PremiumLineCardBadge()
                .frame(width: 120, height: 154)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, BindrSpacing.sm)

            OnboardingHeadline(
                title: "Unlock the full experience.",
                subtitle: "Advanced tools to track value, discover suggested trades, and manage your binders with a professional edge."
            )
        }
    }

    // MARK: Plan Picker

    private var planPickerBlock: some View {
        VStack(spacing: BindrSpacing.sm) {
            planTile(
                plan: .monthly,
                label: "Monthly",
                price: services.store.products.first?.displayPrice ?? "—",
                cadence: "per month",
                meta: nil
            )
            planTile(
                plan: .annual,
                label: "Annual",
                price: annualPrice,
                cadence: "per year",
                meta: "Save 30%"
            )
        }
    }

    private var annualPrice: String {
        services.store.annualProduct?.displayPrice ?? "£24.99"
    }

    private func planTile(
        plan: PlanOption,
        label: String,
        price: String,
        cadence: String,
        meta: String?
    ) -> some View {
        let isSelected = selectedPlan == plan
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) { selectedPlan = plan }
            Haptics.lightImpact()
        } label: {
            HStack(spacing: BindrSpacing.md) {
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

    // MARK: Comparison Grid

    private var comparisonGrid: some View {
        VStack(alignment: .leading, spacing: BindrSpacing.md) {
            Text("What's included")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                comparisonHeader
                comparisonRow(label: "Card scans", free: "20 / mo", premium: "Unlimited")
                comparisonRow(label: "Collection", free: "25 cards", premium: "Unlimited")
                comparisonRow(label: "Trade list", free: "5 listings", premium: "Unlimited")
                comparisonRow(label: "Wishlist", free: "5 cards", premium: "Unlimited")
                comparisonRow(label: "Binders", free: "1", premium: "Unlimited")
                comparisonRow(label: "Decks", free: "1", premium: "Unlimited")
                comparisonRow(label: "Price history", free: "7 days", premium: "Full")
                comparisonRow(label: "Offline mode", free: nil, premium: "Included")
                comparisonRow(label: "Trade notifications", free: nil, premium: "Priority")
            }
            .background {
                RoundedRectangle(cornerRadius: BindrRadius.xl, style: .continuous)
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.05 : 0.035))
            }
            .clipShape(RoundedRectangle(cornerRadius: BindrRadius.xl, style: .continuous))
        }
    }

    private var comparisonHeader: some View {
        HStack {
            Spacer()
            Text("Free")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .center)
            Text("Premium")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 90, alignment: .center)
        }
        .padding(.horizontal, BindrSpacing.md)
        .padding(.vertical, BindrSpacing.sm)
        .background(Color.primary.opacity(colorScheme == .dark ? 0.04 : 0.02))
    }

    private func comparisonRow(label: String, free: String?, premium: String) -> some View {
        VStack(spacing: 0) {
            Divider().opacity(0.08)
            HStack(spacing: BindrSpacing.sm) {
                Text(label)
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
                Spacer()
                // Free column — uniform "–" for missing features rather
                // than a coloured xmark.
                Group {
                    if let free {
                        Text(free)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("—")
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(width: 90, alignment: .center)

                // Premium column — uniform accent checkmark for
                // included-but-not-quantified, otherwise an accent label.
                Group {
                    if premium == "Included" {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(accent)
                    } else {
                        Text(premium)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(accent)
                    }
                }
                .frame(width: 90, alignment: .center)
            }
            .padding(.horizontal, BindrSpacing.md)
            .frame(height: 44)
        }
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
        let price = selectedPlan == .annual ? annualPrice : (services.store.products.first?.displayPrice ?? "—")
        return "Subscribe · \(price)"
    }

    private var footerNote: String {
        if let product = services.store.products.first {
            return "\(product.displayName) · auto-renews until cancelled."
        }
        return "Configure in App Store Connect to enable purchase."
    }
}
