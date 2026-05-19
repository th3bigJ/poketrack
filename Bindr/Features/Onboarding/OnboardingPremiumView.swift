import StoreKit
import SwiftUI

// MARK: - OnboardingPremiumView
//
// Step 5 (final) of `BindrOnboardingFlow`. Premium upsell at peak
// engagement — the user has just configured their game, offline pack,
// and notifications, so the value proposition lands with full context.
//
// If the user is already premium (e.g. restored on a new device), we
// call `onFinish` immediately on appear so they skip this step cleanly.
// "Maybe later" and "Restore purchases" both call `onFinish` without
// purchasing, so the flow always completes.

struct OnboardingPremiumView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.bindrAccent) private var accent

    let onFinish: () -> Void

    @State private var selectAnnual: Bool = true
    @State private var isPurchasing: Bool = false
    @State private var purchaseError: String?
    @State private var hasAppeared = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: BindrSpacing.xl) {
                    headline
                    planPicker
                    featureBullets
                    Color.clear.frame(height: 100)
                }
                .padding(.horizontal, BindrSpacing.lg)
                .padding(.top, BindrSpacing.xl)
            }
            .scrollIndicators(.hidden)

            ctaPanel
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
            withAnimation(.easeOut(duration: 0.5)) { hasAppeared = true }
        }
    }

    // MARK: Headline

    private var headline: some View {
        VStack(alignment: .leading, spacing: BindrSpacing.sm) {
            premiumBadge
                .frame(maxWidth: .infinity, alignment: .center)
                .scaleEffect(hasAppeared ? 1.0 : 0.85)
                .opacity(hasAppeared ? 1 : 0)
                .padding(.bottom, BindrSpacing.sm)

            SocialSectionEyebrow(title: "BINDR PREMIUM")

            VStack(alignment: .leading, spacing: 0) {
                Text("Unlock the full")
                    .font(.system(size: 34, weight: .heavy))
                HStack(spacing: 8) {
                    Text("experience.")
                        .font(.system(size: 34, weight: .heavy))
                        .italic()
                        .foregroundStyle(
                            LinearGradient(
                                colors: [accent, accent.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    Spacer(minLength: 0)
                }
            }

            Text("Unlimited everything — scans, collection, binders, and trade listings — plus full price history and offline mode.")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var premiumBadge: some View {
        ZStack {
            Ellipse()
                .fill(BindrPalette.binderGold.opacity(colorScheme == .dark ? 0.45 : 0.30))
                .frame(width: 110, height: 24)
                .blur(radius: 20)
                .offset(y: 54)

            RoundedRectangle(cornerRadius: BindrRadius.xl, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            BindrPalette.binderGold,
                            Color(hex: "F7CD63"),
                            BindrPalette.binderGold.opacity(0.85)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 110, height: 140)

            RoundedRectangle(cornerRadius: BindrRadius.xl, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.55),
                            Color.white.opacity(0.0),
                            Color.white.opacity(0.18),
                            Color.white.opacity(0.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .blendMode(.plusLighter)
                .frame(width: 110, height: 140)

            RoundedRectangle(cornerRadius: BindrRadius.xl, style: .continuous)
                .stroke(Color.white.opacity(0.45), lineWidth: 1)
                .frame(width: 110, height: 140)

            VStack(spacing: 5) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 26, weight: .black))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                Text("PREMIUM")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .tracking(3)
                    .foregroundStyle(.white)
                Text("MEMBER")
                    .font(.system(size: 8, weight: .heavy, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
    }

    // MARK: Plan picker

    private var planPicker: some View {
        VStack(alignment: .leading, spacing: BindrSpacing.md) {
            SocialSectionEyebrow(title: "CHOOSE YOUR PLAN")

            VStack(spacing: BindrSpacing.sm) {
                planTile(isAnnual: false, label: "Monthly Plan", price: services.store.products.first?.displayPrice ?? "£2.99", badge: nil)
                planTile(isAnnual: true, label: "Annual Plan", price: services.store.annualProduct?.displayPrice ?? "£24.99", badge: "Best Value")
            }
        }
    }

    private func planTile(isAnnual: Bool, label: String, price: String, badge: String?) -> some View {
        let isSelected = selectAnnual == isAnnual
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) { selectAnnual = isAnnual }
            Haptics.lightImpact()
        } label: {
            HStack {
                HStack(spacing: BindrSpacing.sm) {
                    Text(label)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    if let badge {
                        Text(badge)
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .tracking(0.5)
                            .foregroundStyle(accent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background { Capsule().fill(accent.opacity(0.15)) }
                    }
                }
                Spacer()
                Text(price)
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(isSelected ? accent : .primary)
            }
            .padding(.horizontal, BindrSpacing.lg)
            .padding(.vertical, BindrSpacing.md + 2)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: BindrRadius.xl, style: .continuous)
                    .fill(isSelected
                        ? accent.opacity(colorScheme == .dark ? 0.18 : 0.12)
                        : Color.primary.opacity(colorScheme == .dark ? 0.07 : 0.04))
            }
            .overlay {
                RoundedRectangle(cornerRadius: BindrRadius.xl, style: .continuous)
                    .stroke(
                        isSelected ? accent.opacity(0.6) : Color.primary.opacity(0.10),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Feature bullets

    private var featureBullets: some View {
        VStack(spacing: BindrSpacing.sm) {
            bulletRow(icon: "camera.viewfinder", label: "Unlimited card scans", tint: accent)
            bulletRow(icon: "square.stack.3d.up.fill", label: "Unlimited collection & wishlist", tint: BindrPalette.ownedGreen)
            bulletRow(icon: "books.vertical.fill", label: "Unlimited binders & decks", tint: BindrPalette.binderGold)
            bulletRow(icon: "chart.line.uptrend.xyaxis", label: "Full price history", tint: BindrPalette.deckBlue)
            bulletRow(icon: "wifi.slash", label: "Offline mode included", tint: BindrPalette.wishlistViolet)
        }
    }

    private func bulletRow(icon: String, label: String, tint: Color) -> some View {
        HStack(spacing: BindrSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24)
            Text(label)
                .font(.system(size: 14, weight: .semibold))
            Spacer(minLength: 0)
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, BindrSpacing.md)
        .padding(.vertical, 10)
        .glassCardStyle(cornerRadius: BindrRadius.lg, interactive: false)
    }

    // MARK: CTA panel

    private var ctaPanel: some View {
        VStack(spacing: BindrSpacing.sm) {
            if let err = purchaseError ?? services.store.purchaseError {
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(BindrPalette.alertRed)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BindrSpacing.lg)
            }

            Button {
                Task {
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
            } label: {
                ZStack {
                    if isPurchasing {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    } else {
                        subscribeLabel
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background {
                    RoundedRectangle(cornerRadius: BindrRadius.xl, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [accent, accent.opacity(0.78)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: BindrRadius.xl, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                }
                .shadow(color: accent.opacity(colorScheme == .dark ? 0.55 : 0.32), radius: 22, x: 0, y: 10)
            }
            .buttonStyle(.plain)
            .disabled(isPurchasing || services.store.products.isEmpty)
            .padding(.horizontal, BindrSpacing.lg)

            Button {
                Haptics.lightImpact()
                onFinish()
            } label: {
                Text("Maybe later")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .padding(.bottom, BindrSpacing.md)
        }
        .padding(.top, BindrSpacing.sm)
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
            .ignoresSafeArea(edges: .bottom)
        }
    }

    @ViewBuilder
    private var subscribeLabel: some View {
        let price = selectAnnual
            ? (services.store.annualProduct?.displayPrice ?? "£24.99")
            : (services.store.products.first?.displayPrice ?? "£2.99")
        HStack(spacing: 10) {
            Image(systemName: "crown.fill")
                .font(.system(size: 16, weight: .bold))
            Text("Subscribe")
                .font(.system(size: 17, weight: .heavy))
            Text("·")
                .font(.system(size: 17, weight: .heavy))
                .opacity(0.6)
            Text(price)
                .font(.system(size: 17, weight: .heavy))
        }
        .foregroundStyle(.white)
    }
}
