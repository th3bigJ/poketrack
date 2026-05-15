import StoreKit
import SwiftUI

// MARK: - PremiumUpgradeView
//
// New premium upgrade surface. Replaces the bare `List`-based
// `PaywallSheet` body with a marketing-grade screen that mirrors the
// new Social landing aesthetic: hero block, animated tier badge,
// feature pillars, and a sticky purchase CTA.
//
// Call-site contract is unchanged — `PaywallSheet` is still the sheet
// users present from 14+ places in the app; its body now defers to
// this view so we don't have to chase down every callsite.
//
// Visual tenets:
//   * The premium tier reads as a *collectible badge* (foil card-style
//     gradient + crown) rather than a price card. The price comes after.
//   * Feature pillars are glass tiles, same family as Social landing,
//     so the user reads premium as a "next layer" of the same product.
//   * Single CTA at the bottom — Restore Purchases lives in the toolbar
//     to keep the primary action visually uncontested.

struct PremiumUpgradeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.bindrAccent) private var accent
    @Environment(AppServices.self) private var services

    @State private var isPurchasing = false
    @State private var restoreError: String?
    @State private var hasAppeared = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(spacing: BindrSpacing.xxl) {
                        heroBlock
                        pillarsBlock
                        deepValueBlock
                        faqBlock
                        Color.clear.frame(height: 160)
                    }
                    .padding(.horizontal, BindrSpacing.lg)
                    .padding(.top, BindrSpacing.xl)
                }
                .scrollIndicators(.hidden)

                ctaPanel
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .bindrPageBackground(ignoresSafeArea: false)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .glassToolbarButton()
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
                    .glassToolbarSecondaryButton()
                }
            }
            .task {
                if services.store.products.isEmpty {
                    await services.store.loadProducts()
                }
                withAnimation(.easeOut(duration: 0.5)) {
                    hasAppeared = true
                }
            }
        }
    }

    // MARK: Hero

    private var heroBlock: some View {
        VStack(spacing: BindrSpacing.lg) {
            ZStack {
                premiumGlow
                premiumBadge
                    .scaleEffect(hasAppeared ? 1.0 : 0.85)
                    .opacity(hasAppeared ? 1 : 0)
            }
            .frame(height: 220)

            VStack(spacing: BindrSpacing.sm) {
                SocialSectionEyebrow(title: "BINDR PREMIUM")
                Text("The complete toolkit\nfor your collection.")
                    .font(.system(size: 32, weight: .heavy))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Advanced tools to track value, discover suggested trades, and manage your binders with a professional edge.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BindrSpacing.md)
            }
        }
    }

    private var premiumGlow: some View {
        ZStack {
            RadialGradient(
                colors: [accent.opacity(colorScheme == .dark ? 0.32 : 0.22), .clear],
                center: .center,
                startRadius: 10,
                endRadius: 220
            )
            .blur(radius: 28)

            RadialGradient(
                colors: [BindrPalette.binderGold.opacity(0.30), .clear],
                center: .center,
                startRadius: 4,
                endRadius: 140
            )
            .blur(radius: 18)
        }
        .allowsHitTesting(false)
    }

    private var premiumBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: BindrRadius.xxl, style: .continuous)
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
                .frame(width: 156, height: 200)

            // Foil overlay
            RoundedRectangle(cornerRadius: BindrRadius.xxl, style: .continuous)
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
                .frame(width: 156, height: 200)

            RoundedRectangle(cornerRadius: BindrRadius.xxl, style: .continuous)
                .stroke(Color.white.opacity(0.45), lineWidth: 1)
                .padding(0.5)
                .frame(width: 156, height: 200)

            VStack(spacing: 8) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 36, weight: .black))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                Text("PREMIUM")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .tracking(3)
                    .foregroundStyle(.white)
                Text("MEMBER")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .shadow(color: BindrPalette.binderGold.opacity(0.55), radius: 30, x: 0, y: 14)
    }

    // MARK: Pillars

    private var pillarsBlock: some View {
        VStack(alignment: .leading, spacing: BindrSpacing.md) {
            SocialSectionEyebrow(title: "WHAT'S INCLUDED")

            VStack(spacing: BindrSpacing.sm) {
                pillarRow(
                    icon: "bell.badge.fill",
                    title: "Wishlist notifications",
                    description: "Get notified the moment a card you want becomes available for trade.",
                    tint: BindrPalette.alertRed
                )
                pillarRow(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "Collection analytics",
                    description: "Cost basis, market deltas, and set completion tracking.",
                    tint: BindrPalette.deckBlue
                )
                pillarRow(
                    icon: "wand.and.stars",
                    title: "Public customization",
                    description: "Premium themes and animated binder covers for your profile.",
                    tint: BindrPalette.wishlistViolet
                )
                pillarRow(
                    icon: "bolt.fill",
                    title: "Priority trade listings",
                    description: "Your trade offers reach the top of the community network.",
                    tint: BindrPalette.binderGold
                )
                pillarRow(
                    icon: "wifi.slash",
                    title: "Offline access",
                    description: "Browse your binders and build decks without a signal.",
                    tint: BindrPalette.ownedGreen
                )
                pillarRow(
                    icon: "line.3.horizontal.decrease.circle.fill",
                    title: "Advanced filters",
                    description: "Filter by foil type, date, condition, and rarity.",
                    tint: accent
                )
            }
        }
    }

    private func pillarRow(icon: String, title: String, description: String, tint: Color) -> some View {
        HStack(spacing: BindrSpacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: BindrRadius.md, style: .continuous)
                    .fill(tint.opacity(colorScheme == .dark ? 0.20 : 0.15))
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                Text(description)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, BindrSpacing.md)
        .padding(.vertical, BindrSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCardStyle(cornerRadius: BindrRadius.xl, interactive: false)
    }

    // MARK: Deep value block

    private var deepValueBlock: some View {
        VStack(alignment: .leading, spacing: BindrSpacing.md) {
            SocialSectionEyebrow(title: "THE DIFFERENCE")

            VStack(alignment: .leading, spacing: BindrSpacing.lg) {
                bullet(
                    "Reach the community",
                    detail: "Get your listings seen and connect with other collectors faster."
                )
                bullet(
                    "Professional tracking",
                    detail: "Cost basis, market deltas, and ROI — know exactly where you stand."
                )
                bullet(
                    "Curated experience",
                    detail: "Priority trade offers, suggested matches, and a profile worth sharing."
                )
            }
            .padding(BindrSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCardStyle(cornerRadius: BindrRadius.xxl, interactive: false)
        }
    }

    private func bullet(_ title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: BindrSpacing.md) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.18))
                    .frame(width: 24, height: 24)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: FAQ

    private var faqBlock: some View {
        VStack(alignment: .leading, spacing: BindrSpacing.md) {
            SocialSectionEyebrow(title: "BEFORE YOU COMMIT")

            VStack(spacing: BindrSpacing.sm) {
                faqRow(question: "Cancel anytime", answer: "Manage in iOS Settings → Subscriptions. It stops at the end of the billing period, nothing extra.")
                faqRow(question: "Shared across devices", answer: "One Apple ID covers every iPhone and iPad you own.")
                faqRow(question: "Your collection stays put", answer: "Cards, folders, trades — nothing changes if you upgrade, downgrade, or cancel.")
            }
        }
    }

    private func faqRow(question: String, answer: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(question)
                .font(.system(size: 14, weight: .semibold))
            Text(answer)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .padding(BindrSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: BindrRadius.lg, style: .continuous)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.04 : 0.03))
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

            Button {
                Task {
                    isPurchasing = true
                    defer { isPurchasing = false }
                    try? await services.store.purchase()
                    if services.store.isPremium { dismiss() }
                }
            } label: {
                ZStack {
                    if isPurchasing {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    } else {
                        purchaseLabel
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
                .shadow(color: accent.opacity(colorScheme == .dark ? 0.55 : 0.35), radius: 22, x: 0, y: 10)
            }
            .buttonStyle(.plain)
            .disabled(isPurchasing || services.store.products.isEmpty)
            .padding(.horizontal, BindrSpacing.lg)

            Text(footerNote)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 6)
        }
        .padding(.top, BindrSpacing.md)
        .padding(.bottom, BindrSpacing.lg)
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

    @ViewBuilder
    private var purchaseLabel: some View {
        if let product = services.store.products.first {
            HStack(spacing: 10) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 16, weight: .bold))
                Text("Unlock Premium")
                    .font(.system(size: 17, weight: .heavy))
                Text("·")
                    .font(.system(size: 17, weight: .heavy))
                    .opacity(0.6)
                Text(product.displayPrice)
                    .font(.system(size: 17, weight: .heavy))
            }
            .foregroundStyle(.white)
        } else {
            Text("Premium not available yet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
        }
    }

    private var footerNote: String {
        if let product = services.store.products.first {
            return "\(product.displayName) · auto-renews until cancelled."
        }
        return "Configure in App Store Connect to enable purchase."
    }
}
