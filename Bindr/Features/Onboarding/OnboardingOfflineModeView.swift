import SwiftUI

// MARK: - OnboardingOfflineModeView
//
// Step 3. Refactor brief:
//   * Headline drops from .heavy → .bold; subtitle pushed to standard
//     onboarding contrast.
//   * Feature rows reuse `OnboardingFeatureRow` (monochrome accent icons,
//     no pastel backdrops).
//   * Toggle row uses a clean native `Toggle` inside the same glass card
//     style — no oversized custom switch.
//   * CTA centered "Enable Pack" / "Continue" — no trailing arrow.
//
// Persistence: the toggle writes to `services.offlineImageSettings`,
// the same store that powers the Account → Offline Mode page. The
// user's choice is reflected there immediately on completion.

struct OnboardingOfflineModeView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.bindrAccent) private var accent

    let brand: TCGBrand
    let onContinue: () -> Void
    let onSkip: () -> Void

    @State private var enableOffline: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: BindrSpacing.xl) {
                    OnboardingHeadline(
                        title: "Built to go\nanywhere.",
                        subtitle: "Download the \(brand.displayTitle) image pack once over Wi-Fi and your full catalog is available offline — forever."
                    )
                    offlineFeatures
                    toggleBlock
                    Color.clear.frame(height: 80)
                }
                .padding(.horizontal, BindrSpacing.lg)
                .padding(.top, BindrSpacing.xl)
            }
            .scrollIndicators(.hidden)

            OnboardingFooterBar(
                primary: {
                    OnboardingPrimaryButton(
                        title: enableOffline ? "Enable Pack" : "Continue",
                        action: applyAndContinue
                    )
                },
                secondary: {
                    OnboardingSecondaryLink(title: "Not now", action: onSkip)
                }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Feature rows

    private var offlineFeatures: some View {
        VStack(spacing: BindrSpacing.sm) {
            OnboardingFeatureRow(
                icon: "photo.stack",
                title: "Full card images, no signal needed",
                description: "Browse, search, and view every card in the catalog without an internet connection."
            )
            OnboardingFeatureRow(
                icon: "camera.viewfinder",
                title: "Scanner works offline",
                description: "Scan and identify cards at markets, trade events, or anywhere without Wi-Fi."
            )
            OnboardingFeatureRow(
                icon: "books.vertical",
                title: "Binders stay accessible",
                description: "Open, browse, and share your binders without needing a connection."
            )
            OnboardingFeatureRow(
                icon: "rectangle.stack",
                title: "Deck builder runs locally",
                description: "Build and review decks on the go — card data is stored on your device."
            )
            OnboardingFeatureRow(
                icon: "lock.shield",
                title: "Wi-Fi only download",
                description: "The image pack never uses cellular data unless you explicitly allow it."
            )
        }
    }

    // MARK: Actions

    /// Mirrors the toggle behaviour in Account → Offline Mode: persist
    /// the preference and, when enabling, kick off `runFullDownloadIfNeeded`
    /// so the catalog images actually start downloading. Without this the
    /// "Enable Pack" CTA only flipped a flag and the user still had no
    /// offline data the next time they lost signal.
    private func applyAndContinue() {
        // Persist the preference now so it's readable by BindrOnboardingFlow.finish(),
        // but defer the actual download until onboarding is complete to avoid
        // competing with the remaining page transitions.
        services.offlineImageSettings.setOfflinePackEnabled(enableOffline, for: brand)
        onContinue()
    }

    // MARK: Toggle

    private var toggleBlock: some View {
        VStack(alignment: .leading, spacing: BindrSpacing.sm) {
            Toggle(isOn: $enableOffline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Download \(brand.displayTitle) pack")
                        .font(.system(size: 15, weight: .semibold))
                    Text("\(OfflinePackDownloadSizeCopy.approximateLabel(for: brand)) · Wi-Fi only")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            .tint(accent)
        }
        .padding(BindrSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCardStyle(cornerRadius: BindrRadius.xl, interactive: false)
    }
}
