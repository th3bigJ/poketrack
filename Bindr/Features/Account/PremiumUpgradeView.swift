import StoreKit
import SwiftUI

// MARK: - PremiumUpgradeView

struct PremiumUpgradeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.bindrAccent) private var accent
    @Environment(AppServices.self) private var services

    @State private var isPurchasing = false
    @State private var restoreError: String?
    @State private var hasAppeared = false
    @State private var selectedPlan: PlanOption = .monthly

    enum PlanOption { case monthly, annual }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: BindrSpacing.xxl) {
                    heroBlock
                    planPickerBlock
                    comparisonGrid
                    Color.clear.frame(height: 20)
                }
                .padding(.horizontal, BindrSpacing.lg)
                .padding(.top, BindrSpacing.xl)
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
            premiumBadge
                .scaleEffect(hasAppeared ? 1.0 : 0.85)
                .opacity(hasAppeared ? 1 : 0)

            VStack(spacing: BindrSpacing.sm) {
                SocialSectionEyebrow(title: "BINDR PREMIUM")

                VStack(spacing: 0) {
                    Text("Unlock the full")
                        .font(.system(size: 36, weight: .heavy))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 8) {
                        Text("experience.")
                            .font(.system(size: 36, weight: .heavy))
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
                .multilineTextAlignment(.leading)

                Text("Advanced tools to track value, discover suggested trades, and manage your binders with a professional edge.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineSpacing(2)
            }
        }
    }

    private var premiumBadge: some View {
        ZStack {
            // Soft diffuse glow beneath the card
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

            // Foil sheen
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

    // MARK: Plan Picker

    private var planPickerBlock: some View {
        VStack(alignment: .leading, spacing: BindrSpacing.md) {
            SocialSectionEyebrow(title: "CHOOSE YOUR PLAN")

            VStack(spacing: BindrSpacing.sm) {
                planTile(plan: .monthly, label: "Monthly Plan", price: services.store.products.first?.displayPrice ?? "—", badge: nil)
                planTile(plan: .annual, label: "Annual Plan", price: annualPrice, badge: "Best Value")
            }
        }
    }

    private var annualPrice: String {
        services.store.annualProduct?.displayPrice ?? "£24.99"
    }

    private func planTile(plan: PlanOption, label: String, price: String, badge: String?) -> some View {
        let isSelected = selectedPlan == plan
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) { selectedPlan = plan }
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

    // MARK: Comparison Grid

    private var comparisonGrid: some View {
        VStack(alignment: .leading, spacing: BindrSpacing.md) {
            SocialSectionEyebrow(title: "FREE VS PREMIUM")

            VStack(spacing: 0) {
                // Header row
                comparisonHeader

                Divider().opacity(0.12)

                // Feature rows
                comparisonRow(icon: "camera.viewfinder", label: "Card scans", free: "20 / month", premium: "Unlimited")
                comparisonRow(icon: "square.stack.3d.up.fill", label: "Collection", free: "25 cards", premium: "Unlimited")
                comparisonRow(icon: "arrow.left.arrow.right", label: "Trade list", free: "5 listings", premium: "Unlimited")
                comparisonRow(icon: "star.fill", label: "Wishlist", free: "5 cards", premium: "Unlimited")
                comparisonRow(icon: "books.vertical.fill", label: "Binders", free: "1", premium: "Unlimited")
                comparisonRow(icon: "rectangle.stack.fill", label: "Decks", free: "1", premium: "Unlimited")
                comparisonRow(icon: "chart.line.uptrend.xyaxis", label: "Price history", free: "7 days", premium: "Full history")
                comparisonRow(icon: "wifi.slash", label: "Offline mode", free: nil, premium: "Included")
                comparisonRow(icon: "bell.badge.fill", label: "Trade notifications", free: nil, premium: "Priority")
            }
            .background {
                RoundedRectangle(cornerRadius: BindrRadius.xl, style: .continuous)
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.04))
            }
            .clipShape(RoundedRectangle(cornerRadius: BindrRadius.xl, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: BindrRadius.xl, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
        }
    }

    private var comparisonHeader: some View {
        HStack {
            Spacer()
            Text("Free")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .center)
            Rectangle()
                .fill(accent.opacity(0.3))
                .frame(width: 1)
                .frame(height: 36)
            HStack(spacing: 4) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(accent)
                Text("Premium")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(accent)
            }
            .frame(width: 90, alignment: .center)
        }
        .padding(.horizontal, BindrSpacing.md)
        .frame(height: 36)
        .background(accent.opacity(colorScheme == .dark ? 0.08 : 0.05))
    }

    private func comparisonRow(icon: String, label: String, free: String?, premium: String) -> some View {
        VStack(spacing: 0) {
            Divider().opacity(0.08)
            HStack(spacing: BindrSpacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
                // Free column
                Group {
                    if let free {
                        Text(free)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(width: 90, alignment: .center)

                Rectangle()
                    .fill(accent.opacity(0.2))
                    .frame(width: 1)
                    .frame(height: 36)

                // Premium column
                Text(premium)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 90, alignment: .center)
            }
            .padding(.horizontal, BindrSpacing.md)
            .frame(height: 44)
        }
    }

    // MARK: Floating CTA panel

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
                    try? await services.store.purchase(annual: selectedPlan == .annual)
                    if services.store.isPremium { dismiss() }
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
            }
            .buttonStyle(.plain)
            .disabled(isPurchasing || services.store.products.isEmpty)

            Text(footerNote)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 6)
        }
        .padding(.top, BindrSpacing.sm)
        .padding(.bottom, BindrSpacing.sm)
        .padding(.horizontal, BindrSpacing.lg)
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
    private var subscribeLabel: some View {
        let price = selectedPlan == .annual ? annualPrice : (services.store.products.first?.displayPrice ?? "—")
        return HStack(spacing: 10) {
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

    private var footerNote: String {
        if let product = services.store.products.first {
            return "\(product.displayName) · auto-renews until cancelled."
        }
        return "Configure in App Store Connect to enable purchase."
    }
}
