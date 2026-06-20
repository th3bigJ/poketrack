import SwiftUI

// MARK: - OnboardingWelcomeView
//
// Step 1. High-level intro to Bindr. Refactor brief:
//   * Headline drops from .heavy → .bold (still strong, less aggressive).
//   * Subtitle bumped from caption / muted to 15pt secondary so it
//     actually reads on first glance.
//   * Pastel-square backdrops behind each feature icon are gone — icons
//     render as monochrome SF Symbols tinted with the accent color.
//   * Primary CTA is a centred "Get Started" — no trailing arrow.

struct OnboardingWelcomeView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: BindrSpacing.xl) {
                    OnboardingHeadline(
                        title: "Your collection,\nbeautifully organized.",
                        subtitle: "The complete toolkit for serious collectors — catalog, scanner, binders, and community in one place."
                    )
                    featureGrid
                    Color.clear.frame(height: 80)
                }
                .padding(.horizontal, BindrSpacing.lg)
                .padding(.top, BindrSpacing.xl)
            }
            .scrollIndicators(.hidden)

            OnboardingFooterBar(
                primary: {
                    OnboardingPrimaryButton(title: "Get Started", action: onContinue)
                }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var featureGrid: some View {
        VStack(spacing: BindrSpacing.sm) {
            OnboardingFeatureRow(
                icon: "camera.viewfinder",
                title: "Card Scanner",
                description: "Point your camera at any card for instant identification, pricing, and set info."
            )
            OnboardingFeatureRow(
                icon: "rectangle.grid.3x2",
                title: "Full Catalog",
                description: "Every set, variant, and alt art across Pokémon in one place."
            )
            OnboardingFeatureRow(
                icon: "books.vertical",
                title: "Digital Binders",
                description: "3D embossed covers and custom layouts to show off your rarest pulls."
            )
            OnboardingFeatureRow(
                icon: "rectangle.stack.badge.plus",
                title: "Deck Builder",
                description: "Build from scratch, import/export TCG Live lists, and prep official tournament deck sheets."
            )
            OnboardingFeatureRow(
                icon: "scalemass",
                title: "Local Trade",
                description: "Compare card and cash values in person, then update your collection when the trade is done."
            )
            OnboardingFeatureRow(
                icon: "chart.line.uptrend.xyaxis",
                title: "Collection Value",
                description: "Live pricing, trend history, and portfolio value at a glance."
            )
            OnboardingFeatureRow(
                icon: "arrow.left.arrow.right",
                title: "Trade Wall",
                description: "Find suggested matches, wishlist opportunities, and friends' available cards."
            )
        }
    }
}
